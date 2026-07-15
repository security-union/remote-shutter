//
//  WatchPreviewStreamer.swift
//  RemoteShutter
//
//  Owns the Apple Watch live-preview streaming protocol so the camera doesn't have to.
//

import Foundation

/// Streams preview frames to the Apple Watch with credit-based back-pressure modelled on
/// the peer `FrameSender`, but with a small **window**: up to `maxInFlight` frames may be
/// outstanding at once, each released only after the Watch sends an explicit "ready for the
/// next frame" request (`acknowledge()`), exactly like the monitor's `RemoteCmd.RequestFrame`.
/// A window >1 keeps the pipe full while acks travel back over WCSession, so throughput is
/// no longer capped at one frame per round-trip. It stays self-limiting on latency: the
/// Watch only acks *after* it renders, so credits return no faster than the Watch consumes
/// frames, bounding the backlog to ~`maxInFlight` frame-times.
///
/// Encoding is **lazy** — performed only when a credit is available — so the capture
/// pipeline never spends CPU on a frame that would be dropped. A watchdog resets the window
/// if acks ever stop arriving, so a lost message can't freeze the preview.
///
/// All mutable state is confined to `queue` (the camera's capture queue), so the type is
/// lock-free. `offer(_:)` must be called on `queue`; `acknowledge()` is safe to call from
/// any thread and hops onto `queue`.
final class WatchPreviewStreamer {

    /// Produces the encoded payload for the current frame (VP9/HEIC/JPEG, tagged with
    /// its codec). Invoked synchronously inside `offer(_:)` on `queue`, while the sample
    /// buffer backing it is still valid. Returns `nil` to skip.
    typealias Encode = () -> EncodedFrame?

    /// Sends one encoded frame to the Watch. Fire-and-forget — the ack comes back
    /// separately via `acknowledge()`. Injectable so the protocol can be tested.
    typealias Send = (_ frame: EncodedFrame) -> Void

    private let queue: DispatchQueue
    private let send: Send
    private let ackTimeout: TimeInterval
    /// Credit-based back-pressure, shared with the peer `FrameSender`. Confined to `queue`.
    private var window: FrameCreditWindow
    private var watchdog: DispatchWorkItem?

    init(queue: DispatchQueue,
         maxInFlight: Int = 3,
         ackTimeout: TimeInterval = 1.0,
         send: @escaping Send = WatchPreviewStreamer.defaultSend) {
        self.queue = queue
        self.window = FrameCreditWindow(maxInFlight: maxInFlight)
        self.ackTimeout = ackTimeout
        self.send = send
    }

    /// Default transport: the live WCSession preview channel.
    static let defaultSend: Send = { frame in
        WatchSessionManager.shared.pushPreviewFrame(payload: frame.data, codec: frame.codec)
    }

    /// Offers the current frame to the stream. If the in-flight window is already full,
    /// returns immediately **without encoding** — the whole point — so no work is wasted on
    /// a frame that would be dropped. Otherwise it encodes, sends, and consumes one credit
    /// until the Watch acks (or the watchdog fires). Must be called on `queue`.
    @discardableResult
    func offer(_ encode: Encode) -> Bool {
        dispatchPrecondition(condition: .onQueue(queue))
        guard window.hasCredit else { return false }
        guard let frame = encode() else { return false }
        window.acquire()
        armWatchdog()
        send(frame)
        return true
    }

    /// The Watch consumed one in-flight frame and wants the next — returns one credit.
    /// Safe to call from any thread.
    func acknowledge() {
        queue.async { [weak self] in self?.release() }
    }

    private func release() {
        window.release()
        // Keep the watchdog guarding any frames still outstanding; stand it down once the
        // window is empty.
        if window.isEmpty {
            watchdog?.cancel()
            watchdog = nil
        } else {
            armWatchdog()
        }
    }

    /// Resets the window if no ack arrives within `ackTimeout`, so a stall (lost ack) can't
    /// freeze the preview indefinitely. Re-armed on every send and every ack-while-outstanding,
    /// so a steady ack stream keeps pushing it out — it only fires on a genuine stall. Acks
    /// carry no sequence number, so recovery clears the whole window rather than one slot.
    private func armWatchdog() {
        watchdog?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.window.reset()
            self?.watchdog = nil
        }
        watchdog = work
        queue.asyncAfter(deadline: .now() + ackTimeout, execute: work)
    }
}
