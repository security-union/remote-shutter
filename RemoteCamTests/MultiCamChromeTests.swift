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

    /// Rows complete the wall: rows × columns always covers the camera count,
    /// so sizing cells to viewport/rows keeps the whole grid inside the window
    /// (the off-screen-controls fix for wide Mac windows).
    func testGridRowsTimesColumnsCoverEveryCamera() {
        XCTAssertEqual(MultiCamChrome.gridRowCount(cameraCount: 1), 1)
        XCTAssertEqual(MultiCamChrome.gridRowCount(cameraCount: 2), 1) // 2-up
        XCTAssertEqual(MultiCamChrome.gridRowCount(cameraCount: 3), 2) // 2×2
        XCTAssertEqual(MultiCamChrome.gridRowCount(cameraCount: 4), 2) // 2×2
        for count in 1...9 {
            let cells = MultiCamChrome.gridRowCount(cameraCount: count)
                * MultiCamChrome.gridColumnCount(cameraCount: count)
            XCTAssertGreaterThanOrEqual(cells, count, "\(count) cameras need \(count) cells")
        }
    }

    func testGridToggleOnlyWhenMoreThanOneCamera() {
        XCTAssertFalse(MultiCamChrome.showsGridToggle(cameraCount: 1))
        XCTAssertTrue(MultiCamChrome.showsGridToggle(cameraCount: 2))
        XCTAssertTrue(MultiCamChrome.showsGridToggle(cameraCount: 4))
    }

    // MARK: - Rig tray (mirrors MonitorTray's mode-conditioning)

    /// Photo mode lists photo settings only — no video-quality tile, exactly
    /// as the 1:1 monitor's tray behaves in photo mode.
    func testRigTrayPhotoModeListsPhotoTilesOnly() {
        XCTAssertEqual(RigTray.items(mode: .photo, standbyAvailable: true),
                       [.timer, .aspect, .format, .hdr, .cameraStandby, .settings, .help])
    }

    /// Video mode lists the single rig-quality tile only — no photo format or
    /// HDR tiles (frame rate rides the quality tile's intersection cycle).
    func testRigTrayVideoModeListsQualityTileOnly() {
        XCTAssertEqual(RigTray.items(mode: .video, standbyAvailable: true),
                       [.timer, .aspect, .resolution, .cameraStandby, .settings, .help])
    }

    /// A rig with no standby-capable camera omits the tile (not dims it),
    /// matching `MonitorTray`'s capability-driven omission.
    func testRigTrayOmitsStandbyWhenUnavailable() {
        XCTAssertFalse(RigTray.items(mode: .photo, standbyAvailable: false).contains(.cameraStandby))
        XCTAssertFalse(RigTray.items(mode: .video, standbyAvailable: false).contains(.cameraStandby))
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
