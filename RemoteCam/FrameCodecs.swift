//
//  FrameCodecs.swift
//  RemoteShutter
//
//  Encoder abstraction for the preview stream. Each encoder is a named,
//  self-contained strategy (JPEGFrameEncoder, HEICFrameEncoder, later
//  HEVCFrameEncoder for true video) so codecs can be added without touching
//  the pipeline. The wire carries RemoteCmd.StreamCodec per frame, so the
//  receiver decodes whatever arrives.
//

import Foundation
import CoreImage
import CoreVideo
import VideocallCodecs

/// Whether the pure-Rust VP9 codec (VideocallCodecs) can actually run on this
/// device. The framework ships arm64-only slices; on any architecture where the
/// codec can't initialize this is false, both peers advertise no VP9 support,
/// and the preview falls back to the HEIC/JPEG still path. Probed once by
/// constructing a tiny encoder — capability advertisement must reflect what
/// runs at runtime, not what happened to compile (CLAUDE.md Catalyst rule).
enum VP9Support {
    static let isAvailable: Bool = probe()

    private static func probe() -> Bool {
        do {
            _ = try Vp9Encoder(width: 16, height: 16, fps: 30, bitrateKbps: 100,
                               keyframeInterval: 30, minQuantizer: 40, maxQuantizer: 60, cpuUsed: 8)
            return true
        } catch {
            StreamLog.encode.info("VP9 codec unavailable at runtime (\(error)) — preview falls back to stills")
            return false
        }
    }
}

/// Compatibility policy for the peer (phone→phone-monitor) VP9 preview stream.
/// The camera streams VP9 (never stills) to a monitor, so a monitor that is too
/// old to decode VP9 must be told to update rather than shown a broken preview.
/// The gate is the peer's `bundleVersion`, carried on `PeerBecameCamera`/
/// `PeerBecameMonitor` — no per-connection capability handshake. Pure and
/// side-effect-free so the policy is a single unit-tested decision.
enum VP9PreviewCompatibility {
    /// CFBundleVersion of the first release that can decode the peer VP9 preview
    /// stream (this build's CURRENT_PROJECT_VERSION when the feature landed). A
    /// monitor below this renders VP9 as garbage, so the camera routes it to the
    /// existing "app out of date" flow instead.
    static let minimumPeerBundleVersion = 100

    /// Whether a peer at `bundleVersion` can decode the VP9 preview stream.
    /// `bundleVersion <= 0` (unknown/legacy peer) also returns false, so one
    /// check covers both the legacy and the too-old cases.
    static func peerCanDecodeVP9Preview(bundleVersion: Int) -> Bool {
        bundleVersion >= minimumPeerBundleVersion
    }
}

/// Outcome of one encode attempt. Stills only ever produce `.encoded` or
/// `.failed`; a stateful video encoder (VP9) may also consume a frame without
/// emitting output, which must NOT be confused with hardware failure.
enum FrameEncodeResult {
    case encoded(Data)
    /// Transient: the encoder accepted the frame but produced nothing this call
    /// (e.g. VP9 buffered it). Skip the frame; keep the encoder.
    case skipped
    /// Permanent: this codec can't encode on the current hardware — the
    /// streamer falls back to the next preferred codec for good.
    case failed
}

/// One encoded preview frame plus the codec that produced it, so the wire
/// message can tag the payload for the receiver.
struct EncodedFrame {
    let data: Data
    let codec: RemoteCmd.StreamCodec
}

/// A synchronous preview-frame encoder. Called on the capture queue; must not
/// block longer than a frame interval.
protocol FrameEncoding: AnyObject {
    var codec: RemoteCmd.StreamCodec { get }
    func encode(pixelBuffer: CVPixelBuffer) -> FrameEncodeResult
}

/// A stateful video encoder whose delta frames depend on the previous frame
/// (VP9). Adds keyframe control so a desynced receiver can be re-synced on
/// demand. Capture-queue confined like `FrameEncoding`.
protocol StreamVideoEncoding: FrameEncoding {
    /// Force the next encoded frame to be a keyframe.
    func forceKeyframe()
}

/// Encodes with the first working encoder in `chain`, permanently dropping
/// encoders that fail (e.g. HEIC on hardware without an HEVC encoder). Shared
/// by the phone-monitor pipeline (FrameStreamer) and the Watch preview path.
/// Confined to the caller's queue; `chain` is mutated on fallback.
func encodeWithFallback(_ chain: inout [FrameEncoding], pixelBuffer: CVPixelBuffer) -> EncodedFrame? {
    while let encoder = chain.first {
        switch encoder.encode(pixelBuffer: pixelBuffer) {
        case .encoded(let data):
            return EncodedFrame(data: data, codec: encoder.codec)
        case .skipped:
            return nil
        case .failed:
            chain.removeFirst()
            let next = chain.first.map { String(describing: $0.codec) } ?? "none"
            StreamLog.encode.error("\(String(describing: encoder.codec)) encoder failed — falling back to \(next)")
        }
    }
    return nil
}

/// Downscales a capture pixel buffer so its long edge is at most `maxLongEdge`.
/// The buffer is already oriented by the capture connection's videoOrientation,
/// so no rotation is applied here.
func downscaledCIImage(from pixelBuffer: CVPixelBuffer, maxLongEdge: CGFloat) -> CIImage? {
    let image = CIImage(cvPixelBuffer: pixelBuffer)
    let longEdge = max(image.extent.width, image.extent.height)
    guard longEdge > 0 else { return nil }
    let scale = min(1.0, maxLongEdge / longEdge)
    return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
}
