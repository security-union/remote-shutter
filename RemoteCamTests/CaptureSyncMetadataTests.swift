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

    // MARK: - First-frame offset

    func testFirstFrameOffsetIsFrameMinusCameraClockAnchorRounded() {
        // 5_000.4 ms → 5_000; 5_000.5 ms → 5_001.
        XCTAssertEqual(CaptureSyncMetadata.firstFrameOffsetMillis(
            firstFrameUptimeNanos: 5_000_400_000, cameraClockAnchorMillis: 4_950), 50)
        XCTAssertEqual(CaptureSyncMetadata.firstFrameOffsetMillis(
            firstFrameUptimeNanos: 5_000_500_000, cameraClockAnchorMillis: 4_950), 51)
        // A frame before the anchor (the camera was already rolling) is negative.
        XCTAssertEqual(CaptureSyncMetadata.firstFrameOffsetMillis(
            firstFrameUptimeNanos: 4_900_000_000, cameraClockAnchorMillis: 4_950), -50)
    }

    func testWithFirstFrameNeedsBothTheFrameAndTheCameraClockAnchor() {
        XCTAssertNil(sample.withFirstFrame(uptimeNanos: 5_000_000_000).firstFrameOffsetMillis,
                     "no camera-clock anchor → no offset, never a guess")
        var anchored = sample
        anchored.cameraClockAnchorMillis = 4_000
        XCTAssertNil(anchored.withFirstFrame(uptimeNanos: nil).firstFrameOffsetMillis)
        XCTAssertEqual(anchored.withFirstFrame(uptimeNanos: 4_033_000_000).firstFrameOffsetMillis, 33)
    }

    func testFirstFrameOffsetRidesInQuickTimeAndJSONOnceKnown() throws {
        var stamped = sample
        stamped.cameraClockAnchorMillis = 4_000
        stamped = stamped.withFirstFrame(uptimeNanos: 4_021_000_000)
        let items = stamped.quickTimeMetadataItems()
        XCTAssertEqual(items.count, 5)
        let offset = items.first { ($0.key as? String) == CaptureSyncMetadata.QuickTimeKey.firstFrameOffset }
        XCTAssertEqual((offset?.value as? NSNumber)?.int64Value, 21)

        let json = try XCTUnwrap(stamped.jsonString())
        XCTAssertTrue(json.contains("\"firstFrameOffsetMillis\":21"))
        XCTAssertEqual(CaptureSyncMetadata.fromJSONString(json), stamped)
    }

    func testJSONWithoutTheNewFieldsStillDecodes() throws {
        let legacy = #"{"anchorMillis":1,"cameraIndex":1,"captureID":"c","clockOffsetMillis":0,"roundTripMillis":0,"sessionID":"s"}"#
        let decoded = try XCTUnwrap(CaptureSyncMetadata.fromJSONString(legacy))
        XCTAssertNil(decoded.firstFrameOffsetMillis)
        XCTAssertNil(decoded.cameraClockAnchorMillis)
    }

    func testSidecarIsNamedAfterTheClipAndHoldsTheRecord() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var stamped = sample
        stamped.cameraClockAnchorMillis = 10
        stamped = stamped.withFirstFrame(uptimeNanos: 25_000_000)
        let url = try stamped.writeSidecar(in: directory)
        XCTAssertEqual(url.lastPathComponent, "RS_6bb65b12_d0e1f2a3_cam3.json")
        let json = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(CaptureSyncMetadata.fromJSONString(json)?.firstFrameOffsetMillis, 15)
    }

    // MARK: - Clock conversion

    func testMachUnitsToNanosMatchesTheTimebaseWithoutOverflow() {
        XCTAssertEqual(CaptureClockConversion.nanos(machUnits: 24, numer: 125, denom: 3), 1_000)
        XCTAssertEqual(CaptureClockConversion.nanos(machUnits: 1_000, numer: 1, denom: 1), 1_000)
        // ~1 year of arm64 ticks: numer * units would overflow UInt64.
        let units: UInt64 = 24_000_000 * 60 * 60 * 24 * 365
        XCTAssertEqual(CaptureClockConversion.nanos(machUnits: units, numer: 125, denom: 3),
                       units / 3 * 125)
    }

    /// A host-clock time lands in the same domain `SyncClock` reads — the
    /// equality the first-frame offset relies on.
    func testHostTimeConvertsIntoTheSyncClockDomain() throws {
        let host = CMClockGetHostTimeClock()
        let before = DispatchTime.now().uptimeNanoseconds
        let nanos = try XCTUnwrap(CaptureClockConversion.uptimeNanos(of: CMClockGetTime(host), on: host))
        let after = DispatchTime.now().uptimeNanoseconds
        XCTAssertGreaterThanOrEqual(nanos + 1_000_000, before)
        XCTAssertLessThanOrEqual(nanos, after + 1_000_000)
        XCTAssertNil(CaptureClockConversion.uptimeNanos(of: .invalid, on: host))
    }

    /// The wire capability appended for multicam must default to false for
    /// legacy peers (absent field) — PR0 ships it inert.
    func testCapabilitiesDefaultToNoMulticam() {
        let resp = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, currentLens: .wideAngle,
            currentZoom: 1.0, error: nil)
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
