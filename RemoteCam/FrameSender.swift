//
//  FrameSender.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 11/24/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import MultipeerConnectivity

/// Failed to push a frame to the peer — the session pops to scanning with a
/// connection alert, exactly as any other failed send.
final class FrameSendFailed: Message, @unchecked Sendable {}

/**
 Streams preview frames to the monitor with credit-based back-pressure:
 up to `maxInFlight` frames outstanding at once, each released by the
 monitor's `RemoteCmd.RequestFrame` ack, with a watchdog that resets the
 window when an ack is lost (without it, lost acks wedge the stream forever —
 the monitor only acks frames it receives, and the camera only sends when it
 has credit).

 All state is confined to its own serial queue; every entry point hops. The
 frame source (the capture stack's data queue) and the ack source (the
 transport delegate thread) never touch shared state directly.
 */
final class FrameSender {

    /// How long to wait for a `RequestFrame` ack before concluding it was lost.
    static let ackTimeout: TimeInterval = StreamingConfig.default.peerAckTimeout

    private let queue = DispatchQueue(label: "frame sender queue", attributes: [], target: nil)

    /// Credit window, shared logic with `WatchPreviewStreamer` via `FrameCreditWindow`.
    private var window = FrameCreditWindow(maxInFlight: StreamingConfig.default.peerMaxInFlight)

    /// Invalidates watchdog timeouts from completed/superseded waits.
    private var ackGeneration = 0

    private var peer: MCPeerID?
    private var transport: (any MultipeerServiceProtocol)?
    private var hasSession = false

    /// Cross-queue mirror of `window.hasCredit`, so the capture-queue frame
    /// streamer can gate VP9 encoding on back-pressure without hopping onto this
    /// queue. Updated inside `queue` on every window change.
    private let creditAvailableMirror = Locked<Bool>(true)

    /// The connected monitor advertised VP9 decode support (negotiation).
    /// Written by the coordinator when it decodes `PeerBecameMonitor`; read on
    /// the capture queue by the frame streamer. Reset on each session re-bind.
    let peerSupportsVP9 = Locked<Bool>(false)

    /// Set by the coordinator when the monitor requests a keyframe (decoder
    /// re-sync); read-and-cleared once by the frame streamer on the capture
    /// queue, which forces the next VP9 frame to be a keyframe.
    private let keyframeRequestPending = Locked<Bool>(false)

    /// Send failures pop the session to scanning (via the inbox).
    weak var coordinator: SessionCoordinator?

    init(coordinator: SessionCoordinator? = nil) {
        self.coordinator = coordinator
    }

    /// Binds the streaming target. Re-binding (each time the camera state is
    /// re-entered) resets the credit window, matching the old re-become.
    func setSession(peer: MCPeerID, transport: any MultipeerServiceProtocol) {
        // A re-bind is a fresh connection: the new monitor re-advertises VP9
        // (or doesn't), so drop the previous negotiation until it does.
        peerSupportsVP9.value = false
        keyframeRequestPending.value = false
        queue.async {
            if self.hasSession {
                self.window.reset()
            }
            self.hasSession = true
            self.peer = peer
            self.transport = transport
            self.refreshCreditMirror()
        }
    }

    /// Whether the credit window currently has room. Safe to call from any
    /// thread (reads the lock-boxed mirror); the capture-queue frame streamer
    /// uses it to gate VP9 encoding.
    func hasCredit() -> Bool { creditAvailableMirror.value }

    /// The monitor asked for a keyframe — arm it. Safe from any thread.
    func requestKeyframe() { keyframeRequestPending.value = true }

    /// Reads-and-clears a pending keyframe request (capture queue).
    func takeKeyframeRequest() -> Bool {
        var pending = false
        keyframeRequestPending.mutate { pending = $0; $0 = false }
        return pending
    }

    /// Offer a frame; sends if the credit window allows, drops otherwise.
    /// Callable from any thread (the capture data queue in production).
    func send(_ frame: RemoteCmd.SendFrame) {
        queue.async {
            guard self.hasSession, let peer = self.peer, let transport = self.transport else { return }
            let isVideo = frame.codec == .vp9
            if !isVideo {
                // Stills are independent frames: drop under back-pressure so a
                // network hiccup can't build a stale queue. VP9 is gated BEFORE
                // encode (FrameStreamer only encodes with credit), so a VP9
                // frame reaching here already has room — dropping it would
                // corrupt the stateful stream, so it is never dropped here.
                guard self.window.hasCredit else { return }
            }
            // Transport mode is codec-specific:
            //  • Stills go .unreliable — a live viewfinder shows the newest
            //    frame or nothing; reliable mode would queue+retransmit stale
            //    frames, turning any hiccup into an ever-staler laggy stream.
            //  • VP9 is a stateful stream: a dropped delta frame corrupts decode
            //    until a keyframe, so it goes .reliable. The credit window
            //    (applied at encode time) keeps the reliable queue from ever
            //    building up, and a lost-ack watchdog frees it if acks stop.
            // MC's datagram channel negotiates for ~10s after "Connected"; that
            // is solved by warming the channel at peer connect.
            let mode: MCSessionSendDataMode = isVideo ? .reliable : .unreliable
            if transport.send(frame, to: [peer], mode: mode).isFailure() {
                self.coordinator?.tell(FrameSendFailed())
                return
            }
            self.window.acquire()
            self.refreshCreditMirror()
            self.armAckWatchdog()
        }
    }

    /// The monitor acked a frame — release a credit.
    func receiveAck(_ request: RemoteCmd.RequestFrame) {
        queue.async {
            self.window.release()
            self.refreshCreditMirror()
            // Keep guarding any frames still outstanding; stand the watchdog
            // down (by bumping the generation) once the window is empty.
            if self.window.isEmpty {
                self.ackGeneration += 1
            } else {
                self.armAckWatchdog()
            }
        }
    }

    /// Republishes the credit-available mirror. Call inside `queue` after every
    /// window mutation.
    private func refreshCreditMirror() {
        dispatchPrecondition(condition: .onQueue(queue))
        creditAvailableMirror.value = window.hasCredit
    }

    private func armAckWatchdog() {
        dispatchPrecondition(condition: .onQueue(queue))
        ackGeneration += 1
        let generation = ackGeneration
        queue.asyncAfter(deadline: .now() + Self.ackTimeout) { [weak self] in
            self?.handleAckTimeout(generation: generation)
        }
    }

    private func handleAckTimeout(generation: Int) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard generation == ackGeneration else { return } // stale wait
        StreamLog.transport.info(
            "ack watchdog fired after \(Self.ackTimeout, format: .fixed(precision: 1))s — resetting window")
        window.reset()
        refreshCreditMirror()
    }

    // MARK: - Test support

    func windowSnapshot() -> FrameCreditWindow {
        queue.sync { window }
    }

    func currentAckGeneration() -> Int {
        queue.sync { ackGeneration }
    }

    /// Delivers a watchdog firing directly (bypassing the timer) — same code
    /// path the scheduled watchdog runs.
    func fireAckWatchdog(generation: Int) {
        queue.sync { handleAckTimeout(generation: generation) }
    }

    func drain() {
        queue.sync {}
    }
}
