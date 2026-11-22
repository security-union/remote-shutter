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

    /// The largest paid rig: 8 cameras sit in a 3×3 with the last cell empty.
    func testEightCamerasMakeAThreeByThreeGrid() {
        XCTAssertEqual(StoreManager.maxPaidCameras, 8, "update this test with the cap")
        XCTAssertEqual(MultiCamChrome.gridColumnCount(cameraCount: 8), 3)
        XCTAssertEqual(MultiCamChrome.gridRowCount(cameraCount: 8), 3)
    }

    /// Every rig size up to the paid cap fits the viewport: the cells, gaps and
    /// padding add up to exactly the window, on an iPad and on an iPhone.
    func testGridCellsFillTheViewportExactly() {
        let viewports = [CGSize(width: 1180, height: 820), CGSize(width: 852, height: 393)]
        for viewport in viewports {
            for count in 2...StoreManager.maxPaidCameras {
                let cell = MultiCamChrome.gridCellSize(cameraCount: count, in: viewport)
                let columns = CGFloat(MultiCamChrome.gridColumnCount(cameraCount: count))
                let rows = CGFloat(MultiCamChrome.gridRowCount(cameraCount: count))
                let pad = MultiCamChrome.gridPadding * 2, gap = MultiCamChrome.gridSpacing
                XCTAssertEqual(cell.width * columns + gap * (columns - 1) + pad, viewport.width,
                               accuracy: 0.001, "\(count) cameras in \(viewport)")
                XCTAssertEqual(cell.height * rows + gap * (rows - 1) + pad, viewport.height,
                               accuracy: 0.001, "\(count) cameras in \(viewport)")
            }
        }
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

    // MARK: - Rig tray mode-conditioning

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

    /// Portrait is a still mode: the same tiles as Photo.
    func testRigTrayPortraitModeListsPhotoTiles() {
        XCTAssertEqual(RigTray.items(mode: .portrait, standbyAvailable: true),
                       RigTray.items(mode: .photo, standbyAvailable: true))
    }

    /// A rig with no standby-capable camera omits the tile (not dims it).
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

    /// The tray is a real sheet only where one is the right shape. On Mac
    /// Catalyst a sheet is a modal card bolted to the window, so the Mac
    /// keeps the overlay, which a pointer dismisses by clicking away.
    func testTrayPresentationSuitsThePlatform() {
        #if targetEnvironment(macCatalyst)
        XCTAssertEqual(RigTrayPresentation.style, .overlay, "a Mac keeps the overlay")
        #else
        if #available(iOS 16.0, *) {
            XCTAssertEqual(RigTrayPresentation.style, .sheet, "the system sheet brings the drag")
        } else {
            XCTAssertEqual(RigTrayPresentation.style, .overlay, "no detents before iOS 16")
        }
        #endif
    }
}
