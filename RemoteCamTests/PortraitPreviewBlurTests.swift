//
//  PortraitPreviewBlurTests.swift
//  RemoteShutterTests
//
//  Copyright © 2026 Security Union. All rights reserved.
//

import XCTest
import AVFoundation
import CoreVideo
@testable import RemoteShutter

final class PortraitPreviewBlurTests: XCTestCase {

    // MARK: - Pure decisions

    func testRadiusShrinksAsTheApertureCloses() {
        let wide = PortraitPreviewBlur.blurRadius(aperture: 1.4, longEdge: 960)
        let middle = PortraitPreviewBlur.blurRadius(aperture: 4.5, longEdge: 960)
        let closed = PortraitPreviewBlur.blurRadius(aperture: 16, longEdge: 960)
        XCTAssertEqual(wide, 960 * PortraitPreviewBlur.maxRadiusFraction, accuracy: 0.001)
        XCTAssertGreaterThan(wide, middle)
        XCTAssertGreaterThan(middle, closed)
        XCTAssertLessThan(closed, 2, "f/16 is nearly sharp")
    }

    func testRadiusScalesWithTheFrame() {
        XCTAssertEqual(PortraitPreviewBlur.blurRadius(aperture: 2.8, longEdge: 1920),
                       2 * PortraitPreviewBlur.blurRadius(aperture: 2.8, longEdge: 960), accuracy: 0.001)
    }

    func testFocusIsTheMedianOfTheMiddleRegion() {
        // 9x9 map: 0.5 everywhere, 2.0 in the middle third (rows/cols 3..5).
        let width = 9, height = 9
        var values = [Float](repeating: 0.5, count: width * height)
        for row in 3..<6 { for column in 3..<6 { values[row * width + column] = 2.0 } }
        let focus = values.withUnsafeBufferPointer {
            PortraitPreviewBlur.focusDisparity($0, width: width, height: height, rowStride: width, stride: 1)
        }
        XCTAssertEqual(focus, 2.0)
    }

    func testFocusIgnoresHolesAndHonorsRowStride() {
        // Row stride 12 with garbage padding; NaN and zero holes in the middle.
        let width = 9, height = 9, rowStride = 12
        var values = [Float](repeating: 99, count: rowStride * height)
        for row in 0..<height { for column in 0..<width { values[row * rowStride + column] = 1.5 } }
        values[3 * rowStride + 3] = .nan
        values[4 * rowStride + 4] = 0
        let focus = values.withUnsafeBufferPointer {
            PortraitPreviewBlur.focusDisparity($0, width: width, height: height, rowStride: rowStride, stride: 1)
        }
        XCTAssertEqual(focus, 1.5)
    }

    func testFocusIsNilWithoutUsableDepth() {
        let values = [Float](repeating: .nan, count: 16)
        let focus = values.withUnsafeBufferPointer {
            PortraitPreviewBlur.focusDisparity($0, width: 4, height: 4, rowStride: 4)
        }
        XCTAssertNil(focus)
    }

    func testDepthTurnsWithTheFrame() {
        XCTAssertEqual(PortraitPreviewBlur.depthOrientation(for: .landscapeRight, position: .back), .up)
        XCTAssertEqual(PortraitPreviewBlur.depthOrientation(for: .landscapeLeft, position: .back), .down)
        XCTAssertEqual(PortraitPreviewBlur.depthOrientation(for: .portrait, position: .back), .right)
        XCTAssertEqual(PortraitPreviewBlur.depthOrientation(for: .portraitUpsideDown, position: .back), .left)
        XCTAssertEqual(PortraitPreviewBlur.depthOrientation(for: .portrait, position: .front), .left)
    }

    // MARK: - Rendering

    func testNilDisparityReturnsTheSameBuffer() throws {
        let frame = try Self.checkerboard(width: 64, height: 48)
        let result = PortraitPreviewBlur().blurred(frame, disparity: nil, aperture: 1.4)
        XCTAssertTrue(result === frame)
    }

    func testOutputKeepsFormatAndSize() throws {
        let frame = try Self.checkerboard(width: 320, height: 240)
        let result = PortraitPreviewBlur().blurred(frame, disparityMap: try Self.twoLevelDisparity(), aperture: 2.8)
        XCTAssertFalse(result === frame, "a blurred frame is a new buffer; the capture buffer is untouched")
        XCTAssertEqual(CVPixelBufferGetPixelFormatType(result), CVPixelBufferGetPixelFormatType(frame))
        XCTAssertEqual(CVPixelBufferGetWidth(result), 320)
        XCTAssertEqual(CVPixelBufferGetHeight(result), 240)
    }

    /// The map is near (2.0) over the top 70% of rows, which holds the middle
    /// region, so the subject is near; the bottom 30% is far (0.5).
    func testFarRegionLosesSharpnessAndNearRegionKeepsIt() throws {
        let frame = try Self.checkerboard(width: 320, height: 240)
        let original = Self.sharpness(frame)
        let result = PortraitPreviewBlur().blurred(frame, disparityMap: try Self.twoLevelDisparity(), aperture: 1.4)
        let blurred = Self.sharpness(result)
        XCTAssertGreaterThan(blurred.near, 0.8 * original.near, "the subject stays sharp")
        XCTAssertLessThan(blurred.far, 0.3 * original.far, "the background is blurred")
    }

    func testWideApertureBlursMoreThanClosed() throws {
        let frame = try Self.checkerboard(width: 320, height: 240)
        let map = try Self.twoLevelDisparity()
        let blur = PortraitPreviewBlur()
        let wide = Self.sharpness(blur.blurred(frame, disparityMap: map, aperture: 1.4)).far
        let closed = Self.sharpness(blur.blurred(frame, disparityMap: map, aperture: 16)).far
        XCTAssertLessThan(wide, closed)
        XCTAssertEqual(blur.framesBlurred, 2)
    }

    func testDepthDataEntryPointBlursToo() throws {
        let frame = try Self.checkerboard(width: 320, height: 240)
        let depth = try Self.depthData(from: try Self.twoLevelDisparity())
        let result = PortraitPreviewBlur().blurred(frame, disparity: depth, aperture: 1.4)
        XCTAssertFalse(result === frame)
        XCTAssertLessThan(Self.sharpness(result).far, 0.3 * Self.sharpness(frame).far)
    }

    // MARK: - Fixtures

    /// A full-range 4:2:0 frame (the capture format) with a 2-pixel luma
    /// checkerboard: maximum high-frequency detail, neutral chroma.
    private static func checkerboard(width: Int, height: Int) throws -> CVPixelBuffer {
        var created: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, attributes, &created)
        let buffer = try XCTUnwrap(created)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let luma = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!.assumingMemoryBound(to: UInt8.self)
        let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        for row in 0..<height {
            for column in 0..<width {
                luma[row * lumaStride + column] = ((row / 2 + column / 2) % 2 == 0) ? 235 : 20
            }
        }
        let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)!.assumingMemoryBound(to: UInt8.self)
        let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        for index in 0..<(chromaStride * CVPixelBufferGetHeightOfPlane(buffer, 1)) { chroma[index] = 128 }
        return buffer
    }

    /// 80x60 disparity, near (2.0) in the top 70% of rows, far (0.5) below.
    private static func twoLevelDisparity() throws -> CVPixelBuffer {
        let width = 80, height = 60
        var created: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_DisparityFloat32, attributes, &created)
        let buffer = try XCTUnwrap(created)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let values = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: Float.self)
        let rowStride = CVPixelBufferGetBytesPerRow(buffer) / MemoryLayout<Float>.stride
        for row in 0..<height {
            for column in 0..<width {
                values[row * rowStride + column] = row < height * 7 / 10 ? 2.0 : 0.5
            }
        }
        return buffer
    }

    private static func depthData(from map: CVPixelBuffer) throws -> AVDepthData {
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(map)
        let height = CVPixelBufferGetHeight(map)
        let data = Data(bytes: CVPixelBufferGetBaseAddress(map)!, count: bytesPerRow * height)
        let description: [String: Any] = [
            kCGImagePropertyPixelFormat as String: kCVPixelFormatType_DisparityFloat32,
            kCGImagePropertyWidth as String: CVPixelBufferGetWidth(map),
            kCGImagePropertyHeight as String: height,
            kCGImagePropertyBytesPerRow as String: bytesPerRow
        ]
        return try AVDepthData(fromDictionaryRepresentation: [
            kCGImageAuxiliaryDataInfoData as String: data,
            kCGImageAuxiliaryDataInfoDataDescription as String: description
        ])
    }

    /// Mean absolute horizontal luma step in the top 60% of rows (near) and
    /// the bottom 20% (far), skipping the band where the two meet.
    private static func sharpness(_ buffer: CVPixelBuffer) -> (near: Double, far: Double) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let luma = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        func mean(rows: Range<Int>) -> Double {
            var total = 0, count = 0
            for row in rows {
                for column in 8..<(width - 8) {
                    total += abs(Int(luma[row * stride + column + 1]) - Int(luma[row * stride + column]))
                    count += 1
                }
            }
            return Double(total) / Double(count)
        }
        return (mean(rows: 8..<(height * 6 / 10)), mean(rows: (height * 8 / 10)..<(height - 8)))
    }
}
