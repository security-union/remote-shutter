//
//  StreamingConfig.swift
//  RemoteShutter
//
//  Tuning knobs for the preview streaming pipeline (camera -> monitor and
//  camera -> Watch). Code constants on purpose: a bundled JSON config would
//  hide typos until runtime and cost pbxproj wiring for nothing.
//

import Foundation
import CoreGraphics

struct StreamingConfig {

    /// Codecs to try on the camera side, in order. The streamer permanently
    /// falls back to the next entry when an encoder fails (e.g. HEIC on
    /// hardware without an HEVC encoder).
    var preferredCodecs: [RemoteCmd.StreamCodec] = [.heic, .jpeg]

    /// Long edge of the frame sent to the phone monitor. Replaces the old
    /// full-sensor-resolution JPEG at quality 0.1.
    var maxLongEdge: CGFloat = 960
    var heicQuality: CGFloat = 0.5
    var jpegQuality: CGFloat = 0.6

    /// Send every Nth capture callback (30fps capture / 2 = 15fps offered).
    var frameDivisor: Int = 2

    /// Phone-monitor (peer) frame back-pressure window: how many frames may be in
    /// flight (sent, not yet acked via `RemoteCmd.RequestFrame`) at once. Mirrors the
    /// Watch preview window — see `watchPreviewMaxInFlight`.
    var peerMaxInFlight: Int = 3
    /// Re-opens the peer window if no `RequestFrame` ack arrives within this long, so a
    /// lost ack can't wedge the stream.
    var peerAckTimeout: TimeInterval = 1.0

    /// Long edge of the Apple Watch preview (matches the Watch screen width).
    var watchMaxLongEdge: CGFloat = 320
    var watchHEICQuality: CGFloat = 0.5
    var watchJPEGQuality: CGFloat = 0.55

    /// Apple Watch preview back-pressure window: how many frames may be in flight
    /// (sent, not yet acked) at once. >1 keeps the pipe full while acks travel back
    /// over WCSession, so throughput isn't capped at one frame per round-trip. Stays
    /// self-limiting on latency — the Watch acks only after it renders.
    var watchPreviewMaxInFlight: Int = 3
    /// Resets the Watch preview window if no ack arrives within this long, so a lost
    /// ack can't freeze the stream.
    var watchPreviewAckTimeout: TimeInterval = 1.0

    /// Monitor-side stall watchdog: if no frame arrives for this long, raise
    /// `UICmd.StreamStalled` so the state machine re-requests a frame.
    /// Re-raises at most once per interval while the stall persists.
    var stallTimeout: TimeInterval = 2.0
    /// How often the stall watchdog wakes up to check.
    var stallCheckInterval: TimeInterval = 1.0

    static let `default` = StreamingConfig()
}
