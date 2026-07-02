//
//  FrameCreditWindow.swift
//  RemoteShutter
//
//  Credit-based back-pressure shared by both camera-side frame senders.
//

import Foundation

/// Credit-based back-pressure window shared by the two camera-side frame senders —
/// the peer `FrameSender` (phone → phone monitor) and the `WatchPreviewStreamer`
/// (phone → Apple Watch). Up to `maxInFlight` frames may be **outstanding**: sent, not
/// yet acked. A window >1 keeps the pipe full while acks travel back, so throughput is
/// no longer capped at one frame per round-trip; it stays self-limiting on latency because
/// the receiver acks only after it consumes a frame, bounding the backlog to ~`maxInFlight`
/// frame-times.
///
/// The owner checks `hasCredit` before encoding/sending, `acquire()`s on send, `release()`s
/// on each ack, and `reset()`s when its stall watchdog fires. Acks carry no per-frame id, so
/// recovery clears the whole window rather than one slot.
///
/// **Not thread-safe on purpose** — the owner confines it to its own single-threaded
/// execution context (a serial `DispatchQueue` for `WatchPreviewStreamer`, the actor mailbox
/// for `FrameSender`), so no locking is needed.
struct FrameCreditWindow {

    /// How many frames may be outstanding at once. Clamped to ≥1.
    let maxInFlight: Int

    /// Frames currently outstanding (sent, not yet acked).
    private(set) var inFlight = 0

    init(maxInFlight: Int) {
        self.maxInFlight = max(1, maxInFlight)
    }

    /// A credit is available to send another frame.
    var hasCredit: Bool { inFlight < maxInFlight }

    /// No frames are outstanding — the owner can stand its watchdog down.
    var isEmpty: Bool { inFlight == 0 }

    /// Consumes one credit for a frame about to be sent. Call only when `hasCredit`.
    mutating func acquire() { inFlight += 1 }

    /// Returns one credit when the receiver acks a frame.
    mutating func release() { inFlight = max(0, inFlight - 1) }

    /// Clears the whole window after a stall (a lost ack can't be attributed to one frame).
    mutating func reset() { inFlight = 0 }
}
