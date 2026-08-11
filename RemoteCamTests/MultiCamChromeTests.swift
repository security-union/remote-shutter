//
//  MultiCamChromeTests.swift
//  RemoteShutterTests
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import XCTest
@testable import RemoteShutter

final class MultiCamChromeTests: XCTestCase {

    func testGridColumnsAreNearSquare() {
        XCTAssertEqual(MultiCamChrome.gridColumnCount(cameraCount: 1), 1)
        XCTAssertEqual(MultiCamChrome.gridColumnCount(cameraCount: 2), 2) // 2-up
        XCTAssertEqual(MultiCamChrome.gridColumnCount(cameraCount: 3), 2) // 2×2
        XCTAssertEqual(MultiCamChrome.gridColumnCount(cameraCount: 4), 2) // 2×2
        XCTAssertEqual(MultiCamChrome.gridColumnCount(cameraCount: 9), 3) // grows by √n
    }

    func testGridToggleOnlyWhenMoreThanOneCamera() {
        XCTAssertFalse(MultiCamChrome.showsGridToggle(cameraCount: 1))
        XCTAssertTrue(MultiCamChrome.showsGridToggle(cameraCount: 2))
        XCTAssertTrue(MultiCamChrome.showsGridToggle(cameraCount: 4))
    }

    func testStreamProfilePresets() {
        // The focused tier reproduces today's 1:1 peer preview.
        XCTAssertEqual(StreamProfile.focused.maxLongEdge, 1200)
        XCTAssertEqual(StreamProfile.focused.fps, 30)
        // The thumbnail tier is smaller and cheaper on every axis.
        XCTAssertLessThan(StreamProfile.thumbnail.maxLongEdge, StreamProfile.focused.maxLongEdge)
        XCTAssertLessThan(StreamProfile.thumbnail.bitrateKbps, StreamProfile.focused.bitrateKbps)
        XCTAssertLessThan(StreamProfile.thumbnail.fps, StreamProfile.focused.fps)
    }
}
