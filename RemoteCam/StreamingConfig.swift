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

    /// Still codecs to try for the phone-monitor (peer) stream, in order. This
    /// chain only holds self-contained encodings of a single frame, which makes
    /// per-frame fallback meaningful: when an encoder fails (e.g. HEIC on
    /// hardware without an HEVC encoder) the streamer re-encodes that same
    /// frame with the next entry and steps down permanently. VP9 is NOT in
    /// this chain because a VP9 frame is a delta against decoder state, not a
    /// standalone picture — no still can substitute for it, and mixing codecs
    /// mid-stream corrupts the decode. Whether to stream VP9 at all is a
    /// per-session mode decision made elsewhere (runtime encoder availability
    /// + the peer bundleVersion gate in VP9PreviewCompatibility); this chain
    /// is what runs when that mode is off.
    var preferredCodecs: [RemoteCmd.StreamCodec] = [.heic, .jpeg]

    /// Long edge of the frame sent to the phone monitor. Replaces the old
    /// full-sensor-resolution JPEG at quality 0.1.
    var maxLongEdge: CGFloat = 960
    var heicQuality: CGFloat = 0.5
    var jpegQuality: CGFloat = 0.6

    /// VP9 tuning for the phone-monitor (peer) preview: a bigger frame (960 px)
    /// and a higher bitrate than the Watch's 320 px stream. The first frame of
    /// every encoder session is a keyframe, and a forced keyframe every
    /// `keyframeInterval` bounds decoder re-sync latency after any desync.
    var peerVP9 = VP9Settings(bitrateKbps: 800, fps: 30, keyframeInterval: 30,
                              minQuantizer: 32, maxQuantizer: 56, cpuUsed: 7)

    /// Send every Nth capture callback (30fps capture / 2 = 15fps offered).
    var frameDivisor: Int = 2

    /// Phone-monitor (peer) frame back-pressure window: how many frames may be in
    /// flight (sent, not yet acked via `RemoteCmd.RequestFrame`) at once. Mirrors the
    /// Watch preview window — see `watchPreviewMaxInFlight`.
    var peerMaxInFlight: Int = 5
    /// Re-opens the peer window if no `RequestFrame` ack arrives within this long, so a
    /// lost ack can't wedge the stream.
    var peerAckTimeout: TimeInterval = 1.0

    /// Codecs to try for the Apple Watch preview, in order (same permanent-
    /// fallback semantics as `preferredCodecs`). VP9 leads: inter frames are a
    /// fraction of a still's bytes, and the Watch decodes them with the Rust
    /// Vp9Decoder (no VideoToolbox on watchOS).
    var watchPreferredCodecs: [RemoteCmd.StreamCodec] = [.vp9, .heic, .jpeg]

    /// Long edge of the Apple Watch preview (matches the Watch screen width).
    var watchMaxLongEdge: CGFloat = 320
    var watchHEICQuality: CGFloat = 0.5
    var watchJPEGQuality: CGFloat = 0.55

    /// VP9 tuning for the Watch preview stream (videocall-codecs). Inter frames
    /// are a fraction of a still's size, so the same WCSession byte budget
    /// carries more frames per second than HEIC/JPEG stills.
    struct VP9Settings {
        /// Target bitrate for the ~320 px preview.
        var bitrateKbps: UInt32 = 300
        /// Encoder timebase fps (WCSession round-trips pace actual delivery).
        var fps: UInt32 = 30
        /// Forced keyframe every N frames: after a dropped/undecodable frame the
        /// Watch re-syncs in at most N frames (~3 s at ~10 fps delivered).
        var keyframeInterval: UInt32 = 30
        /// VP9 quantizer window (0-63, lower = better quality).
        var minQuantizer: UInt32 = 40
        var maxQuantizer: UInt32 = 60
        /// Fastest speed preset — encode runs on the capture queue.
        var cpuUsed: UInt8 = 7
    }
    var watchVP9 = VP9Settings()

    /// Apple Watch preview back-pressure window: how many frames may be in flight
    /// (sent, not yet acked) at once. >1 keeps the pipe full while acks travel back
    /// over WCSession, so throughput isn't capped at one frame per round-trip. Stays
    /// self-limiting on latency — the Watch acks only after it renders.
    var watchPreviewMaxInFlight: Int = 5
    /// Resets the Watch preview window if no ack arrives within this long, so a lost
    /// ack can't freeze the stream.
    var watchPreviewAckTimeout: TimeInterval = 1.0

    /// Monitor-side stall watchdog: if no frame arrives for this long, raise
    /// `UICmd.StreamStalled` so the state machine re-requests a frame.
    /// Re-raises at most once per interval while the stall persists.
    var stallTimeout: TimeInterval = 2.0
    /// How often the stall watchdog wakes up to check.
    var stallCheckInterval: TimeInterval = 1.0

    /// Monitor-side VP9 recovery: rate-limits `RemoteCmd.RequestKeyframe` while
    /// the decoder is desynced (undecodable frames), so a burst of bad frames
    /// asks for at most one keyframe per interval instead of flooding the wire.
    var keyframeRequestInterval: TimeInterval = 0.5

    static let `default` = StreamingConfig()
}
