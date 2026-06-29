//
//  WatchPreviewStreamer.swift
//  RemoteShutter
//
//  Owns the Apple Watch live-preview streaming protocol so the camera doesn't have to.
//

import Foundation

/// Streams preview frames to the Apple Watch with strict back-pressure: at most one
/// frame in flight, and the next frame is encoded and sent only after the Watch acks the
/// previous one (WCSession's reply is the ack). Encoding is **lazy** — performed only
/// when the stream is ready — so the capture pipeline never spends CPU encoding a frame
/// that would just be dropped.
///
/// All mutable state is confined to `queue` (the camera's capture queue), so the type is
/// lock-free. `offer(_:)` must be called on `queue`; the ack arrives on an arbitrary
/// WCSession queue and hops back onto `queue` to re-arm.
final class WatchPreviewStreamer {

    /// Produces the JPEG for the current frame. Invoked synchronously inside `offer(_:)`
    /// on `queue`, while the sample buffer backing it is still valid. Returns `nil` to skip.
    typealias Encode = () -> Data?

    /// Sends one encoded frame and invokes `onAck` exactly once when the Watch replies (or
    /// delivery fails). Injectable so the protocol can be tested without WCSession.
    typealias Send = (_ jpeg: Data, _ onAck: @escaping () -> Void) -> Void

    private let queue: DispatchQueue
    private let send: Send
    /// True while a frame is in flight to the Watch. Confined to `queue`.
    private var inFlight = false

    init(queue: DispatchQueue, send: @escaping Send = WatchPreviewStreamer.defaultSend) {
        self.queue = queue
        self.send = send
    }

    /// Default transport: the live WCSession preview channel.
    static let defaultSend: Send = { jpeg, onAck in
        WatchSessionManager.shared.pushPreviewFrame(jpeg: jpeg, onAck: onAck)
    }

    /// Offers the current frame to the stream. If a frame is already in flight, returns
    /// immediately **without encoding** — the whole point — so no work is wasted on a
    /// frame that would be dropped. Otherwise it encodes, sends, and holds the gate until
    /// the Watch acks. Must be called on `queue`.
    @discardableResult
    func offer(_ encode: Encode) -> Bool {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !inFlight else { return false }
        guard let jpeg = encode() else { return false }
        inFlight = true
        send(jpeg) { [weak self] in
            guard let self else { return }
            self.queue.async { self.inFlight = false }
        }
        return true
    }
}
