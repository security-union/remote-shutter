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
final class FrameSendFailed: Message {}

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

    /// Send failures pop the session to scanning (via the inbox).
    weak var coordinator: SessionCoordinator?

    init(coordinator: SessionCoordinator? = nil) {
        self.coordinator = coordinator
    }

    /// Binds the streaming target. Re-binding (each time the camera state is
    /// re-entered) resets the credit window, matching the old re-become.
    func setSession(peer: MCPeerID, transport: any MultipeerServiceProtocol) {
        queue.async {
            if self.hasSession {
                self.window.reset()
            }
            self.hasSession = true
            self.peer = peer
            self.transport = transport
        }
    }

    /// Offer a frame; sends if the credit window allows, drops otherwise.
    /// Callable from any thread (the capture data queue in production).
    func send(_ frame: RemoteCmd.SendFrame) {
        queue.async {
            guard self.hasSession, let peer = self.peer, let transport = self.transport else { return }
            guard self.window.hasCredit else { return } // back-pressure: drop until a credit frees
            // ALWAYS .unreliable for frames: a live viewfinder shows the
            // newest frame or nothing — reliable mode queues and retransmits,
            // turning any network hiccup into an ever-staler laggy stream.
            // MC's datagram channel negotiates for ~10s after "Connected" and
            // drops sends until ready; that is solved by warming the channel
            // at session connect, never by switching frames to reliable.
            if transport.send(frame, to: [peer], mode: .unreliable).isFailure() {
                self.coordinator?.tell(FrameSendFailed())
                return
            }
            self.window.acquire()
            self.armAckWatchdog()
        }
    }

    /// The monitor acked a frame — release a credit.
    func receiveAck(_ request: RemoteCmd.RequestFrame) {
        queue.async {
            self.window.release()
            // Keep guarding any frames still outstanding; stand the watchdog
            // down (by bumping the generation) once the window is empty.
            if self.window.isEmpty {
                self.ackGeneration += 1
            } else {
                self.armAckWatchdog()
            }
        }
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
