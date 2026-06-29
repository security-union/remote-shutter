//
//  WatchPreviewStreamer.swift
//  RemoteShutter
//
//  Owns the Apple Watch live-preview streaming protocol so the camera doesn't have to.
//

import Foundation

/// Streams preview frames to the Apple Watch with back-pressure modelled on the peer
/// `FrameSender`: at most one frame in flight, the next encoded and sent only after the
/// Watch sends an explicit "ready for the next frame" request (`acknowledge()`), exactly
/// like the monitor's `RemoteCmd.RequestFrame`. Encoding is **lazy** — performed only
/// when the stream is ready — so the capture pipeline never spends CPU on a frame that
/// would be dropped. A watchdog re-arms the stream if an ack is ever lost, so a single
/// dropped message can't freeze the preview.
///
/// All mutable state is confined to `queue` (the camera's capture queue), so the type is
/// lock-free. `offer(_:)` must be called on `queue`; `acknowledge()` is safe to call from
/// any thread and hops onto `queue`.
final class WatchPreviewStreamer {

    /// Produces the JPEG for the current frame. Invoked synchronously inside `offer(_:)`
    /// on `queue`, while the sample buffer backing it is still valid. Returns `nil` to skip.
    typealias Encode = () -> Data?

    /// Sends one encoded frame to the Watch. Fire-and-forget — the ack comes back
    /// separately via `acknowledge()`. Injectable so the protocol can be tested.
    typealias Send = (_ jpeg: Data) -> Void

    private let queue: DispatchQueue
    private let send: Send
    private let ackTimeout: TimeInterval
    /// True while a frame is in flight to the Watch. Confined to `queue`.
    private var inFlight = false
    private var watchdog: DispatchWorkItem?

    init(queue: DispatchQueue,
         ackTimeout: TimeInterval = 1.0,
         send: @escaping Send = WatchPreviewStreamer.defaultSend) {
        self.queue = queue
        self.ackTimeout = ackTimeout
        self.send = send
    }

    /// Default transport: the live WCSession preview channel.
    static let defaultSend: Send = { jpeg in
        WatchSessionManager.shared.pushPreviewFrame(jpeg: jpeg)
    }

    /// Offers the current frame to the stream. If a frame is already in flight, returns
    /// immediately **without encoding** — the whole point — so no work is wasted on a
    /// frame that would be dropped. Otherwise it encodes, sends, and holds the gate until
    /// the Watch acks (or the watchdog fires). Must be called on `queue`.
    @discardableResult
    func offer(_ encode: Encode) -> Bool {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !inFlight else { return false }
        guard let jpeg = encode() else { return false }
        inFlight = true
        armWatchdog()
        send(jpeg)
        return true
    }

    /// The Watch consumed the in-flight frame and wants the next one. Re-arms the stream.
    /// Safe to call from any thread.
    func acknowledge() {
        queue.async { [weak self] in self?.release() }
    }

    private func release() {
        inFlight = false
        watchdog?.cancel()
        watchdog = nil
    }

    /// Re-arms the stream if no ack arrives within `ackTimeout`, so a dropped ack can't
    /// freeze the preview indefinitely.
    private func armWatchdog() {
        watchdog?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.inFlight = false
            self?.watchdog = nil
        }
        watchdog = work
        queue.asyncAfter(deadline: .now() + ackTimeout, execute: work)
    }
}
