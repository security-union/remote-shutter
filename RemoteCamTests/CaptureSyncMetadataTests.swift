//
//  CaptureSyncMetadataTests.swift
//  RemoteShutterTests
//
//  Created by Dario Lencina on 2026.
//  Copyright © 2026 Security Union. All rights reserved.
//

import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import RemoteShutter

final class CaptureSyncMetadataTests: XCTestCase {

    private let sample = CaptureSyncMetadata(
        sessionID: "6BB65B12-30A4-4A5C-9F41-000000000001",
        captureID: "D0E1F2A3-1111-2222-3333-000000000002",
        cameraIndex: 3,
        anchorMillis: 1_754_800_000_123,
        clockOffsetMillis: -42,
        roundTripMillis: 11
    )

    func testFilenamePrefixGroupsBySessionCaptureAndCamera() {
        XCTAssertEqual(sample.filenamePrefix, "RS_6bb65b12_d0e1f2a3_cam3")
    }

    func testJSONRoundTrip() {
        guard let json = sample.jsonString() else {
            return XCTFail("expected JSON encoding to succeed")
        }
        XCTAssertEqual(CaptureSyncMetadata.fromJSONString(json), sample)
    }

    func testJSONIsDeterministic() {
        XCTAssertEqual(sample.jsonString(), sample.jsonString())
    }

    /// The alignment key rides in UserComment as opaque JSON; the EXIF capture
    /// date is the camera's WALL clock (a real recent date), never the
    /// monotonic-uptime anchor — which would land photos in ~1970.
    func testStampedExifDateIsWallClockNotTheMonotonicAnchor() throws {
        let png = try makeTinyPNG()
        // A 2025 wall-clock instant; the sample's anchorMillis (~1.7e12 ms of
        // uptime, i.e. ~55000 years) would parse to a nonsense EXIF date.
        let capturedAt = Date(timeIntervalSince1970: 1_754_800_000.250)
        let stamped = sample.stamped(png, capturedAt: capturedAt)

        let source = try XCTUnwrap(CGImageSourceCreateWithData(stamped as CFData, nil))
        let props = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let exif = try XCTUnwrap(props[kCGImagePropertyExifDictionary] as? [CFString: Any])

        // "yyyy:MM:dd HH:mm:ss" — assert the year is the capturedAt year in the
        // formatter's own zone (timezone-robust: we don't hard-code HH:mm:ss).
        let dateString = try XCTUnwrap(exif[kCGImagePropertyExifDateTimeOriginal] as? String)
        let year = Int(dateString.prefix(4))
        XCTAssertEqual(year, 2025, "EXIF DateTimeOriginal must be the wall clock, got \(dateString)")
        XCTAssertEqual(exif[kCGImagePropertyExifSubsecTimeOriginal] as? String, "250")

        // The anchor is present, but only inside the opaque UserComment JSON.
        let userComment = try XCTUnwrap(exif[kCGImagePropertyExifUserComment] as? String)
        let decoded = try XCTUnwrap(CaptureSyncMetadata.fromJSONString(userComment))
        XCTAssertEqual(decoded.anchorMillis, sample.anchorMillis)
    }

    /// A 1×1 PNG, enough for CGImageSource to round-trip through the stamper.
    private func makeTinyPNG() throws -> Data {
        let data = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil))
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(ctx.makeImage())
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return data as Data
    }

    func testQuickTimeItemsCarryAnchorAndIDs() {
        let items = sample.quickTimeMetadataItems()
        XCTAssertEqual(items.count, 4)

        func value(for key: String) -> Any? {
            items.first { ($0.key as? String) == key }?.value
        }
        XCTAssertEqual(
            (value(for: CaptureSyncMetadata.QuickTimeKey.anchor) as? NSNumber)?.uint64Value,
            sample.anchorMillis)
        XCTAssertEqual(
            value(for: CaptureSyncMetadata.QuickTimeKey.capture) as? String,
            sample.captureID)
        XCTAssertEqual(
            value(for: CaptureSyncMetadata.QuickTimeKey.session) as? String,
            sample.sessionID)
        XCTAssertEqual(
            (value(for: CaptureSyncMetadata.QuickTimeKey.offset) as? NSNumber)?.int64Value,
            sample.clockOffsetMillis)
        for item in items {
            XCTAssertEqual(item.keySpace, .quickTimeMetadata)
            XCTAssertNotNil(item.identifier)
        }
    }

    /// The wire capability appended for multicam must default to false for
    /// legacy peers (absent field) — PR0 ships it inert.
    func testCapabilitiesDefaultToNoMulticam() {
        let resp = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, error: nil)
        XCTAssertFalse(resp.supportsMulticam)
    }
}

/// The runtime-error classification: one error is transient, a repeat inside
/// the window convicts the current device (it is then marked failed and every
/// selection surface skips it via the descriptor's `isSuspended`).
final class CaptureErrorStrikesTests: XCTestCase {

    func testSingleErrorIsTransient() {
        let verdict = CaptureErrorStrikes.record([], now: 100)
        XCTAssertFalse(verdict.deterministic)
        XCTAssertEqual(verdict.strikes, [100])
    }

    func testRepeatWithinWindowIsDeterministic() {
        var state = CaptureErrorStrikes.record([], now: 100)
        state = CaptureErrorStrikes.record(state.strikes, now: 100.016) // the -666 loop cadence
        XCTAssertTrue(state.deterministic)
    }

    func testErrorsSpacedBeyondTheWindowStayTransient() {
        var state = CaptureErrorStrikes.record([], now: 100)
        state = CaptureErrorStrikes.record(state.strikes, now: 100 + CaptureErrorStrikes.window + 1)
        XCTAssertFalse(state.deterministic, "isolated errors hours apart must never convict a device")
        XCTAssertEqual(state.strikes.count, 1, "stale strikes are dropped")
    }
}
