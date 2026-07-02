//
//  JPEGFrameEncoder.swift
//  RemoteShutter
//
//  Universal-fallback still encoder: every iOS device and every peer app
//  version can decode JPEG.
//

import UIKit
import CoreImage

final class JPEGFrameEncoder: FrameEncoding {

    let codec: RemoteCmd.StreamCodec = .jpeg

    private let context: CIContext
    private let maxLongEdge: CGFloat
    private let quality: CGFloat

    init(context: CIContext = CIContext(options: [.useSoftwareRenderer: false]),
         maxLongEdge: CGFloat,
         quality: CGFloat) {
        self.context = context
        self.maxLongEdge = maxLongEdge
        self.quality = quality
    }

    func encode(pixelBuffer: CVPixelBuffer) -> Data? {
        guard let scaled = downscaledCIImage(from: pixelBuffer, maxLongEdge: maxLongEdge),
              let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: quality)
    }
}
