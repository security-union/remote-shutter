//
//  MultiCamChromeTests.swift
//  RemoteShutterTests
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import XCTest
@testable import RemoteShutter

final class MultiCamChromeTests: XCTestCase {

    // MARK: - Cinematic

    /// The CINEMATIC tile is a video-mode tile for a camera that reports the
    /// block; EDIT IN PHOTOS joins it once the effect is on.
    func testCinematicTilesAreVideoOnlyAndFollowTheEffect() {
        XCTAssertFalse(RigTray.items(mode: .photo, standbyAvailable: false,
                                     cinematicAvailable: true, cinematicOn: true).contains(.cinematic))
        XCTAssertFalse(RigTray.items(mode: .video, standbyAvailable: false).contains(.cinematic),
                       "no block, no tile")
        let off = RigTray.items(mode: .video, standbyAvailable: false, cinematicAvailable: true)
        XCTAssertTrue(off.contains(.cinematic))
        XCTAssertFalse(off.contains(.cinematicEditable), "the output choice waits for the effect")
        let on = RigTray.items(mode: .video, standbyAvailable: false, cinematicAvailable: true, cinematicOn: true)
        XCTAssertEqual(on.firstIndex(of: .cinematicEditable), on.firstIndex(of: .cinematic).map { $0 + 1 },
                       "the output sits beside the effect it belongs to")
    }

    func testApertureLabelsAndTrack() {
        XCTAssertEqual(CinematicApertureStops.label(2), "f/2")
        XCTAssertEqual(CinematicApertureStops.label(2.8), "f/2.8")
        XCTAssertEqual(CinematicApertureStops.label(16), "f/16")
        let state = CinematicState(enabled: true, output: .baked, aperture: 2.8, minAperture: 2, maxAperture: 16,
                                   defaultAperture: 2.8, qualities: [:])
        let track = CinematicApertureStops.track(state)
        XCTAssertEqual(track.minValue, 2)
        XCTAssertEqual(track.maxValue, 16)
        XCTAssertEqual(track.mapping, .log2, "each whole stop is an equal step")
        XCTAssertEqual(track.snappedToStop(3.0, tolerance: 0.05), 2.8, accuracy: 0.001, "detents at the whole stops")
    }

    private func subject(_ id: Int, _ kind: CinematicSubjectKind, group: Int, _ rect: CGRect,
                         focus: CinematicFocusStrength? = nil) -> CinematicSubject {
        CinematicSubject(id: id, groupID: group, kind: kind, rect: rect, focus: focus, isFixedFocus: false)
    }

    /// One box per person: a body is dropped when that person's face is there.
    func testSubjectBoxesDropABodyWhoseFaceIsShown() {
        let face = subject(1, .face, group: 5, CGRect(x: 0.4, y: 0.1, width: 0.2, height: 0.2))
        let body = subject(2, .humanBody, group: 5, CGRect(x: 0.3, y: 0.1, width: 0.4, height: 0.8))
        let loneBody = subject(3, .humanBody, group: 6, CGRect(x: 0.8, y: 0.2, width: 0.1, height: 0.6))
        let visible = CinematicSubjectLayout.visibleSubjects([face, body, loneBody]).map(\.id)
        XCTAssertEqual(visible, [1, 3])
    }

    /// A tap inside a box locks that subject (the smallest box wins); a tap
    /// elsewhere tracks the point; a long press holds focus there.
    func testTapMapsToCinematicFocus() {
        let object = subject(9, .salientObject, group: -1, CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        let face = subject(1, .face, group: 5, CGRect(x: 0.4, y: 0.3, width: 0.1, height: 0.1))
        let subjects = [object, face]

        XCTAssertEqual(CinematicSubjectLayout.focus(forTap: CGPoint(x: 0.45, y: 0.35), subjects: subjects,
                                                    isLongPress: false),
                       .subject(id: 1, strength: .strong))
        XCTAssertEqual(CinematicSubjectLayout.focus(forTap: CGPoint(x: 0.25, y: 0.25), subjects: subjects,
                                                    isLongPress: false),
                       .subject(id: 9, strength: .strong))
        XCTAssertEqual(CinematicSubjectLayout.focus(forTap: CGPoint(x: 0.9, y: 0.9), subjects: subjects,
                                                    isLongPress: false),
                       .trackPoint(x: 0.9, y: 0.9, strength: .strong))
        XCTAssertEqual(CinematicSubjectLayout.focus(forTap: CGPoint(x: 0.45, y: 0.35), subjects: subjects,
                                                    isLongPress: true),
                       .fixedPoint(x: 0.45, y: 0.35))
    }

    /// Boxes land where the letterboxed image is drawn, and a box's center
    /// maps back through the tap mapping to the same normalized point.
    func testSubjectBoxMappingMatchesTheTapMapping() throws {
        let view = CGSize(width: 400, height: 800)       // portrait viewfinder
        let image = CGSize(width: 1920, height: 1080)    // 16:9 frame, letterboxed
        let frame = try XCTUnwrap(CinematicSubjectLayout.imageFrame(viewSize: view, imageSize: image))
        XCTAssertEqual(frame.width, 400, accuracy: 0.001)
        XCTAssertEqual(frame.height, 225, accuracy: 0.001)
        XCTAssertEqual(frame.minY, 287.5, accuracy: 0.001)

        let box = CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.2)
        let onScreen = CinematicSubjectLayout.viewRect(box, in: frame)
        let back = try XCTUnwrap(FocusPointMapping.normalizedImagePoint(
            tap: CGPoint(x: onScreen.midX, y: onScreen.midY), viewSize: view, imageSize: image))
        XCTAssertEqual(back.x, box.midX, accuracy: 0.0001)
        XCTAssertEqual(back.y, box.midY, accuracy: 0.0001)
    }

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
