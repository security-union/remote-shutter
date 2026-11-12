//
//  PortraitRendererTests.swift
//  RemoteShutterTests
//
//  Copyright © 2026 Security Union. All rights reserved.
//

import XCTest
import AVFoundation
import CoreImage
import ImageIO
@testable import RemoteShutter

final class PortraitRendererTests: XCTestCase {
    /// The camera reports this range to the director, so it must be a real
    /// f-number range inside Apple's f/1.4...f/16, with the default in it.
    func testApertureRangeHoldsTheDefault() {
        let range = PortraitRenderer.apertureRange
        XCTAssertGreaterThanOrEqual(range.lowerBound, 1.4)
        XCTAssertLessThanOrEqual(range.upperBound, 16)
        XCTAssertTrue(range.contains(PortraitRenderer.defaultAperture))
    }

    func testClampedApertureStaysInRange() {
        let range = PortraitRenderer.apertureRange
        XCTAssertEqual(PortraitRenderer.clampedAperture(0.1), range.lowerBound)
        XCTAssertEqual(PortraitRenderer.clampedAperture(100), range.upperBound)
        XCTAssertEqual(PortraitRenderer.clampedAperture(4.5), 4.5)
        XCTAssertEqual(PortraitRenderer.clampedAperture(.nan), PortraitRenderer.defaultAperture)
    }

    // MARK: - Delivery

    func testOnlyAPortraitCaptureWithDepthGetsPortraitTreatment() {
        for mode in [RecordingMode.Photo, .Video, .Shorts, .Portrait] {
            for output in [PortraitOutput.baked, .editable] {
                for hasDepth in [false, true] {
                    let expected: PortraitRenderer.Delivery
                    if mode == .Portrait && hasDepth {
                        expected = output == .baked ? .bake : .passThrough
                    } else {
                        expected = .crop
                    }
                    XCTAssertEqual(PortraitRenderer.delivery(mode: mode, output: output, hasDepth: hasDepth),
                                   expected, "\(mode) \(output) depth=\(hasDepth)")
                }
            }
        }
    }

    // MARK: - Mattes and photo size

    func testPortraitAsksOnlyForOfferedMattes() {
        XCTAssertEqual(CaptureEngine.portraitMatteTypes(available: []), [])
        XCTAssertEqual(CaptureEngine.portraitMatteTypes(available: [.glasses, .hair]), [.hair, .glasses])
        XCTAssertEqual(CaptureEngine.portraitMatteTypes(available: [.teeth, .skin, .hair, .glasses]),
                       [.hair, .skin, .teeth, .glasses])
    }

    func testPortraitPhotoSizeIsTheLargestWithin24MPFromTheFormatsOwnList() throws {
        let twelve = CMVideoDimensions(width: 4032, height: 3024)
        let twentyFour = CMVideoDimensions(width: 5712, height: 4284)
        let fortyEight = CMVideoDimensions(width: 8064, height: 6048)
        let pick = { (dims: [CMVideoDimensions], depth: Bool) -> CMVideoDimensions? in
            CaptureEngine.maxPhotoDimensions(supported: dims, depthEnabled: depth)
        }
        XCTAssertEqual(try XCTUnwrap(pick([twelve, fortyEight, twentyFour], true)).width, twentyFour.width)
        XCTAssertEqual(try XCTUnwrap(pick([twelve, fortyEight, twentyFour], false)).width, fortyEight.width)
        XCTAssertEqual(try XCTUnwrap(pick([twelve, fortyEight], true)).width, twelve.width)
        XCTAssertEqual(try XCTUnwrap(pick([fortyEight], true)).width, fortyEight.width,
                       "never a size the format does not list")
        XCTAssertNil(pick([], true))
    }

    // MARK: - The filter's inputs

    /// `depthBlurEffectFilter(forImageData:)` loads the disparity and every
    /// matte the file carries on its own, so the renderer needs no explicit
    /// variant.
    func testFilterLoadsDisparityAndMattesFromTheFile() throws {
        let filter = try XCTUnwrap(CIContext().depthBlurEffectFilter(
            forImageData: try PortraitFixture.portraitCapture(), options: nil))
        for key in ["inputImage", "inputDisparityImage", "inputMatteImage", "inputHairImage", "inputGlassesImage"] {
            XCTAssertNotNil(filter.value(forKey: key) as? CIImage, "\(key) not loaded")
        }
    }

    // MARK: - Rendering

    func testBakedStillIsBlurredCroppedInSensorSpaceAndDropsDepth() throws {
        let baked = try XCTUnwrap(PortraitRenderer.render(
            try PortraitFixture.portraitCapture(), aperture: 2.8, aspectRatio: .sixteenNine))
        let output = try source(baked)
        XCTAssertEqual(CGImageSourceGetType(output) as String?, "public.heic")
        XCTAssertNil(CGImageSourceCopyAuxiliaryDataInfoAtIndex(output, 0, kCGImageAuxiliaryDataTypeDisparity))
        XCTAssertFalse(PortraitRenderer.hasGainMap(output), "an SDR capture stays SDR")
        let rect = try XCTUnwrap(CaptureEngine.cropRect(sourceWidth: CGFloat(PortraitFixture.width),
                                                        sourceHeight: CGFloat(PortraitFixture.height),
                                                        aspectRatio: .sixteenNine))
        try assertMetadata(of: output, width: Int(rect.width), height: Int(rect.height))
    }

    func testAStillWithoutDepthIsNotRendered() throws {
        let plain = try XCTUnwrap(CIContext().heifRepresentation(
            of: PortraitFixture.primary, format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!, options: [:]))
        XCTAssertNil(PortraitRenderer.render(plain, aperture: 4.5, aspectRatio: .fourThree))
    }

    /// The baked still's HDR write: an SDR/HDR pair in, a HEIC with a gain
    /// map out, cropped, with the capture's orientation and metadata. The
    /// simulator neither writes a file with both depth and a gain map nor
    /// expands a gain map to HDR, so the HDR image here is the fixture's own
    /// and the whole render from an HDR Portrait capture is checked by the
    /// hardware test.
    func testHDRWriteCarriesAGainMapAndTheCapturesMetadata() throws {
        guard #available(iOS 18.0, *) else { throw XCTSkip("gain-map writing needs iOS 18") }
        let capture = try PortraitFixture.hdrCapture()
        let captureSource = try source(capture)
        XCTAssertTrue(PortraitRenderer.hasGainMap(captureSource), "fixture carries a gain map")
        let sdr = try XCTUnwrap(CIImage(data: capture))
        let rect = try XCTUnwrap(CaptureEngine.cropRect(sourceWidth: CGFloat(PortraitFixture.width),
                                                        sourceHeight: CGFloat(PortraitFixture.height),
                                                        aspectRatio: .sixteenNine))

        let written = try XCTUnwrap(PortraitRenderer.encodeHDR(
            sdr: sdr, hdr: PortraitFixture.brighter, rect: rect, like: captureSource))
        let output = try source(written)
        XCTAssertEqual(CGImageSourceGetType(output) as String?, "public.heic")
        XCTAssertTrue(PortraitRenderer.hasGainMap(output), "the written still keeps its HDR")
        try assertMetadata(of: output, width: Int(rect.width), height: Int(rect.height))
    }

    private func assertMetadata(of output: CGImageSource, width: Int, height: Int,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(output, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, width, file: file, line: line)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, height, file: file, line: line)
        XCTAssertEqual(properties[kCGImagePropertyOrientation] as? Int, PortraitFixture.orientation,
                       "sensor space, orientation carried", file: file, line: line)
        let exif = try XCTUnwrap(properties[kCGImagePropertyExifDictionary] as? [CFString: Any])
        XCTAssertEqual(exif[kCGImagePropertyExifLensModel] as? String, PortraitFixture.lensModel,
                       file: file, line: line)
        XCTAssertEqual(exif[kCGImagePropertyExifPixelXDimension] as? Int, width, file: file, line: line)
        XCTAssertEqual(exif[kCGImagePropertyExifPixelYDimension] as? Int, height, file: file, line: line)
    }

    private func source(_ data: Data) throws -> CGImageSource {
        try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    }
}

/// HEICs shaped like captures: a 4:3 primary in sensor space with an EXIF
/// orientation and a lens model.
private enum PortraitFixture {
    static let width = 400
    static let height = 300
    static let orientation = 6
    static let lensModel = "fixture lens"

    static var primary: CIImage {
        CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0),
            "inputPoint1": CIVector(x: CGFloat(width), y: CGFloat(height)),
            "inputColor0": CIColor(red: 0.9, green: 0.2, blue: 0.1),
            "inputColor1": CIColor(red: 0.1, green: 0.3, blue: 0.9)
        ])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    private static var properties: [String: Any] {
        [kCGImagePropertyOrientation as String: orientation,
         kCGImagePropertyExifDictionary as String: [kCGImagePropertyExifLensModel as String: lensModel]]
    }

    /// The primary three times brighter: HDR, well past SDR white.
    static var brighter: CIImage {
        primary.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 3, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 3, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 3, w: 0)
        ])
    }

    /// An HDR capture: Core Image computes the gain map from `brighter`.
    @available(iOS 18.0, *)
    static func hdrCapture() throws -> Data {
        try XCTUnwrap(CIContext().heifRepresentation(
            of: primary.settingProperties(properties), format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!, options: [.hdrImage: brighter]),
            "this runtime cannot encode HEIC")
    }

    /// A Portrait capture: disparity plus the portrait, hair and glasses
    /// mattes. Core Image writes the image and mattes; ImageIO adds the
    /// disparity, as Float32 because the simulator's HEIC writer refuses a
    /// Float16 map.
    static func portraitCapture() throws -> Data {
        let matte = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        let withMattes = try XCTUnwrap(CIContext().heifRepresentation(
            of: primary.settingProperties(properties), format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
            options: [.portraitEffectsMatteImage: matte,
                      .semanticSegmentationHairMatteImage: matte,
                      .semanticSegmentationGlassesMatteImage: matte]),
            "this runtime cannot encode HEIC")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(withMattes as CFData, nil))

        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(output, "public.heic" as CFString, 1, nil))
        CGImageDestinationAddImageFromSource(destination, source, 0, nil)
        for type in [kCGImageAuxiliaryDataTypePortraitEffectsMatte,
                     kCGImageAuxiliaryDataTypeSemanticSegmentationHairMatte,
                     kCGImageAuxiliaryDataTypeSemanticSegmentationGlassesMatte] {
            let info = try XCTUnwrap(CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, type))
            CGImageDestinationAddAuxiliaryDataInfo(destination, type, info)
        }
        var disparityType: NSString?
        let disparity = try XCTUnwrap(disparityData().dictionaryRepresentation(forAuxiliaryDataType: &disparityType))
        CGImageDestinationAddAuxiliaryDataInfo(destination, try XCTUnwrap(disparityType) as CFString,
                                               disparity as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    /// A quarter-size disparity map: a near band down the middle, far elsewhere.
    private static func disparityData() throws -> AVDepthData {
        let mapWidth = width / 4, mapHeight = height / 4
        var map = [Float32](repeating: 0.5, count: mapWidth * mapHeight)
        for row in 0..<mapHeight {
            for column in mapWidth / 3..<2 * mapWidth / 3 { map[row * mapWidth + column] = 2 }
        }
        let description: [CFString: Any] = [
            kCGImagePropertyWidth: mapWidth,
            kCGImagePropertyHeight: mapHeight,
            kCGImagePropertyBytesPerRow: mapWidth * MemoryLayout<Float32>.size,
            kCGImagePropertyPixelFormat: kCVPixelFormatType_DisparityFloat32
        ]
        return try AVDepthData(fromDictionaryRepresentation: [
            kCGImageAuxiliaryDataInfoData: map.withUnsafeBytes { Data($0) },
            kCGImageAuxiliaryDataInfoDataDescription: description
        ])
    }
}
