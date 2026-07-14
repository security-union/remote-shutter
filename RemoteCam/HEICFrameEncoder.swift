//
//  HEICFrameEncoder.swift
//  RemoteShutter
//
//  Default still encoder: HEIC rides the same hardware HEVC block the video
//  pipeline uses and is roughly half the bytes of JPEG at equal quality, which
//  directly doubles the deliverable frame rate on bandwidth-bound links
//  (MultipeerConnectivity and especially WCSession to the Watch). Decodes
//  natively via ImageIO/UIImage(data:) on iOS and watchOS alike.
//
//  encode() returns nil on hardware without an HEVC encoder (pre-A10 devices)
//  or on any CoreImage failure; the streamer then falls back to JPEG.
//

import UIKit
import CoreImage
import AVFoundation

final class HEICFrameEncoder: FrameEncoding {

    let codec: RemoteCmd.StreamCodec = .heic

    private let context: CIContext
    private let maxLongEdge: CGFloat
    private let quality: CGFloat
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    init(context: CIContext = CIContext(options: [.useSoftwareRenderer: false]),
         maxLongEdge: CGFloat,
         quality: CGFloat) {
        self.context = context
        self.maxLongEdge = maxLongEdge
        self.quality = quality
    }

    func encode(pixelBuffer: CVPixelBuffer) -> FrameEncodeResult {
        guard let scaled = downscaledCIImage(from: pixelBuffer, maxLongEdge: maxLongEdge),
              let data = context.heifRepresentation(
                of: scaled,
                format: .RGBA8,
                colorSpace: colorSpace,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
              ) else { return .failed }
        return .encoded(data)
    }
}
