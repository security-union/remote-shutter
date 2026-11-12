//
//  PortraitRenderer.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union. All rights reserved.
//

import Foundation
import CoreImage
import ImageIO

/// Bakes Portrait's blur into a captured still. Pure and stateless: the
/// engine hands it the photo's file data and the rig's aperture.
enum PortraitRenderer {
    /// Apple's Camera opens Portrait at f/4.5; so does a camera here until the
    /// director asks for another f-number.
    static let defaultAperture: Float = 4.5

    /// The f-numbers the blur accepts, read from `CIDepthBlurEffect`'s
    /// `inputAperture` slider attributes. f/1.4...f/16 (Apple Camera's range)
    /// when the filter does not describe a usable one.
    static let apertureRange: ClosedRange<Float> = {
        let fallback: ClosedRange<Float> = 1.4...16
        guard let attributes = CIFilter(name: "CIDepthBlurEffect")?
                .attributes["inputAperture"] as? [String: Any],
              let low = (attributes[kCIAttributeSliderMin] as? NSNumber)?.floatValue,
              let high = (attributes[kCIAttributeSliderMax] as? NSNumber)?.floatValue,
              low > 0, high > low else { return fallback }
        return low...high
    }()

    /// `aperture` clamped into `apertureRange`; the default for a value that
    /// is not a number.
    static func clampedAperture(_ aperture: Float) -> Float {
        guard aperture.isFinite else { return defaultAperture }
        return min(max(aperture, apertureRange.lowerBound), apertureRange.upperBound)
    }

    private static let context = CIContext()

    /// A Portrait still: Core Image's portrait filter blurs the background
    /// from the photo's own depth (and person matte, when delivered) at
    /// `aperture`, then the result is cropped to the aspect ratio and encoded
    /// like `CaptureEngine.cropPhotoData` (sensor space, EXIF orientation and
    /// metadata carried). The blur is baked in; the depth is not kept. Nil
    /// when the data carries no depth, so the caller falls back to a plain crop.
    static func render(_ data: Data, aperture: Float, aspectRatio: AspectRatio) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source),
              let filter = context.depthBlurEffectFilter(forImageData: data, options: nil) else {
            debugLog("PortraitRenderer: no depth in photo data (\(data.count) bytes)")
            return nil
        }
        filter.setValue(clampedAperture(aperture), forKey: "inputAperture")
        guard let blurred = filter.outputImage else { return nil }
        let extent = blurred.extent
        let rect = CaptureEngine.cropRect(sourceWidth: extent.width, sourceHeight: extent.height,
                                          aspectRatio: aspectRatio)?
            .offsetBy(dx: extent.minX, dy: extent.minY) ?? extent
        let colorSpace = CGImageSourceCreateImageAtIndex(source, 0, nil)?.colorSpace
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let cgImage = context.createCGImage(
            blurred, from: rect, format: .RGBA8, colorSpace: colorSpace) else {
            debugLog("PortraitRenderer: render failed for rect \(rect)")
            return nil
        }
        return CaptureEngine.encode(cgImage, like: source, type: type)
    }
}
