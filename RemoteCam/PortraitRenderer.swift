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

    /// The f-numbers a camera reports: f/1.4...f/16 (Apple's Depth Control
    /// range), narrowed to what `CIDepthBlurEffect`'s `inputAperture` accepts
    /// on this device.
    static let apertureRange: ClosedRange<Float> = {
        let apple: ClosedRange<Float> = 1.4...16
        guard let attributes = CIFilter(name: "CIDepthBlurEffect")?
                .attributes["inputAperture"] as? [String: Any],
              let low = (attributes[kCIAttributeMin] as? NSNumber)?.floatValue,
              let high = (attributes[kCIAttributeMax] as? NSNumber)?.floatValue else { return apple }
        let lower = max(apple.lowerBound, low)
        let upper = min(apple.upperBound, high)
        return upper > lower ? lower...upper : apple
    }()

    /// `aperture` clamped into `apertureRange`; the default for a value that
    /// is not a number.
    static func clampedAperture(_ aperture: Float) -> Float {
        guard aperture.isFinite else { return defaultAperture }
        return min(max(aperture, apertureRange.lowerBound), apertureRange.upperBound)
    }

    // MARK: - Delivery

    /// What the camera does with a finished still.
    enum Delivery: Equatable {
        /// Blur rendered into the still (`render`), cropped to the aspect.
        case bake
        /// The capture file as AVFoundation wrote it: depth and mattes
        /// embedded, native ratio, no re-encode. Photos offers Depth Control.
        case passThrough
        /// A plain still, cropped to the aspect (`CaptureEngine.cropPhotoData`).
        case crop
    }

    /// The single decision for a still. Only a Portrait capture that carries
    /// depth gets Portrait treatment; Editable keeps the file untouched.
    static func delivery(mode: RecordingMode, output: PortraitOutput, hasDepth: Bool) -> Delivery {
        guard mode == .Portrait, hasDepth else { return .crop }
        switch output {
        case .baked: return .bake
        case .editable: return .passThrough
        }
    }

    // MARK: - Rendering

    private static let context = CIContext()

    /// A Portrait still: Core Image's portrait filter blurs the background
    /// at `aperture`, then the result is cropped to the aspect ratio. The
    /// filter loads everything the file carries on its own: disparity, the
    /// portrait effects matte, the hair and glasses mattes and the gain map
    /// (pinned by `PortraitRendererTests`), and it locates the face's
    /// landmarks to set the focus plane on the subject.
    /// The render stays in sensor space with the EXIF orientation and
    /// metadata carried. A HEIC with a gain map keeps its HDR: the blur also
    /// runs on the HDR image and Core Image writes a fresh gain map from the
    /// pair. The depth is not kept. Nil when the data carries no depth, so
    /// the caller falls back to a plain crop.
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
        if #available(iOS 18.0, macCatalyst 18.0, *),
           let hdr = renderHDR(data, source: source, type: type, filter: filter, sdr: blurred, rect: rect) {
            return hdr
        }
        let colorSpace = CGImageSourceCreateImageAtIndex(source, 0, nil)?.colorSpace
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let cgImage = context.createCGImage(
            blurred, from: rect, format: .RGBA8, colorSpace: colorSpace) else {
            debugLog("PortraitRenderer: render failed for rect \(rect)")
            return nil
        }
        return CaptureEngine.encode(cgImage, like: source, type: type)
    }

    /// Whether the still's file carries an HDR gain map (Apple's or ISO's).
    static func hasGainMap(_ source: CGImageSource) -> Bool {
        var types = [kCGImageAuxiliaryDataTypeHDRGainMap]
        if #available(iOS 18.0, macCatalyst 18.0, *) { types.append(kCGImageAuxiliaryDataTypeISOGainMap) }
        return types.contains { CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, $0) != nil }
    }

    /// The HDR still (WWDC24 "Use HDR for dynamic image experiences"): the
    /// same blur runs on the gain-map-expanded HDR image. HEIC with a gain
    /// map only; nil otherwise or on failure, and the caller takes the SDR
    /// path.
    @available(iOS 18.0, macCatalyst 18.0, *)
    private static func renderHDR(_ data: Data, source: CGImageSource, type: CFString,
                                  filter: CIFilter, sdr: CIImage, rect: CGRect) -> Data? {
        guard type as String == "public.heic", hasGainMap(source),
              let hdrInput = CIImage(data: data, options: [.expandToHDR: true]) else { return nil }
        filter.setValue(hdrInput, forKey: kCIInputImageKey)
        guard let hdr = filter.outputImage else { return nil }
        return encodeHDR(sdr: sdr, hdr: hdr, rect: rect, like: source)
    }

    /// Writes `rect` of an SDR/HDR pair as a HEIC: the SDR image is the
    /// primary and the HDR image goes in as `.hdrImage`, so Core Image
    /// computes the gain map. `source`'s metadata and orientation ride along,
    /// EXIF pixel dimensions rewritten to the crop.
    @available(iOS 18.0, macCatalyst 18.0, *)
    static func encodeHDR(sdr: CIImage, hdr: CIImage, rect: CGRect, like source: CGImageSource) -> Data? {
        let toOrigin = CGAffineTransform(translationX: -rect.minX, y: -rect.minY)
        let properties = metadata(of: source, width: Int(rect.width), height: Int(rect.height))
        let primary = sdr.cropped(to: rect).transformed(by: toOrigin).settingProperties(properties)
        let colorSpace = CIImage(cgImageSource: source, index: 0, options: nil).colorSpace
            ?? CGColorSpace(name: CGColorSpace.displayP3)!
        let quality = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        let options: [CIImageRepresentationOption: Any] = [
            .hdrImage: hdr.cropped(to: rect).transformed(by: toOrigin),
            quality: 0.95
        ]
        guard let encoded = context.heifRepresentation(of: primary, format: .RGBA8,
                                                       colorSpace: colorSpace, options: options) else {
            debugLog("PortraitRenderer: HDR HEIF write failed for rect \(rect)")
            return nil
        }
        return encoded
    }

    /// The source's properties with the EXIF pixel dimensions rewritten to
    /// the rendered size; orientation and the rest ride along untouched.
    private static func metadata(of source: CGImageSource, width: Int, height: Int) -> [String: Any] {
        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]) ?? [:]
        if var exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            exif[kCGImagePropertyExifPixelXDimension as String] = width
            exif[kCGImagePropertyExifPixelYDimension as String] = height
            properties[kCGImagePropertyExifDictionary as String] = exif
        }
        return properties
    }
}
