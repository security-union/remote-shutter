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
