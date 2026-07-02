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

/// A synchronous still-frame encoder. Called on the capture queue; must not
/// block longer than a frame interval. Returns nil when this codec cannot
/// encode on the current hardware — the streamer then falls back to the next
/// preferred codec permanently.
protocol FrameEncoding: AnyObject {
    var codec: RemoteCmd.StreamCodec { get }
    func encode(pixelBuffer: CVPixelBuffer) -> Data?
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
