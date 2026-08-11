//
//  CaptureSyncMetadataTests.swift
//  RemoteShutterTests
//
//  Created by Dario Lencina on 2026.
//  Copyright © 2026 Security Union. All rights reserved.
//

import AVFoundation
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
            currentCamera: .back, currentLens: .wideAngle,
            currentZoom: 1.0, error: nil)
        XCTAssertFalse(resp.supportsMulticam)
    }
}
