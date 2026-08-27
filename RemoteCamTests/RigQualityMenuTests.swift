//
//  RigQualityMenuTests.swift
//  RemoteShutterTests
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import XCTest
@testable import RemoteShutter

final class RigQualityMenuTests: XCTestCase {

    /// A CameraInfo advertising a resolution/fps matrix (+ HEIF/HDR).
    private func info(_ matrix: [VideoResolution: [VideoFrameRate]],
                      heif: Bool = true, hdr: Bool = true) -> RemoteCmd.CameraInfo {
        RemoteCmd.CameraInfo(
            availableLenses: [.wideAngle], hasFlash: true, hasTorch: true,
            supportedResolutions: Array(matrix.keys),
            supportedFrameRates: Array(Set(matrix.values.flatMap { $0 })),
            resolutionFrameRates: matrix,
            supportsHEIF: heif, supportsHDR: hdr)
    }

    private func lane(_ name: String, _ matrix: [VideoResolution: [VideoFrameRate]],
                     heif: Bool = true, hdr: Bool = true) -> RigQualityMenu.Lane {
        RigQualityMenu.Lane(name: name, info: info(matrix, heif: heif, hdr: hdr))
    }

    private let full4K: [VideoResolution: [VideoFrameRate]] =
        [.uhd4k: [.fps24, .fps30, .fps60], .hd1080p: [.fps24, .fps30, .fps60]]
    private let only1080: [VideoResolution: [VideoFrameRate]] =
        [.hd1080p: [.fps24, .fps30]]

    // MARK: - Intersection

    func testHomogeneousRigOffersEverything() {
        let menu = RigQualityMenu(lanes: [lane("Cam 1", full4K), lane("Cam 2", full4K)])
        let opts = Set(menu.videoOptions().map { "\($0.resolution.rawValue):\($0.frameRate.rawValue)" })
        XCTAssertTrue(opts.contains("2:3")) // 4K60
        XCTAssertTrue(opts.contains("1:2")) // 1080p30
        XCTAssertTrue(menu.blockingLanes(resolution: .uhd4k, frameRate: .fps60).isEmpty)
    }

    func testHeterogeneousRigIntersectsAndNamesBlocker() {
        // Cam 2 can only do 1080p{24,30}. The rig loses 4K and 1080p60.
        let menu = RigQualityMenu(lanes: [lane("Cam 1", full4K), lane("Cam 2", only1080)])
        XCTAssertEqual(menu.blockingLanes(resolution: .uhd4k, frameRate: .fps30), ["Cam 2"])
        XCTAssertEqual(menu.blockingLanes(resolution: .hd1080p, frameRate: .fps60), ["Cam 2"])
        // 1080p30 survives (both do it).
        XCTAssertTrue(menu.blockingLanes(resolution: .hd1080p, frameRate: .fps30).isEmpty)
    }

    /// Dario's clarification: manual selection within the intersection is
    /// first-class — both 1080p30 and 4K30 must be enabled for a rig where both
    /// cameras do both, so the tray can toggle directly between them.
    func testManualOptionsBothEnabledWhenSharedByAllCameras() {
        let shared: [VideoResolution: [VideoFrameRate]] = [.uhd4k: [.fps30], .hd1080p: [.fps30]]
        let menu = RigQualityMenu(lanes: [lane("Cam 1", shared), lane("Cam 2", shared)])
        XCTAssertTrue(menu.blockingLanes(resolution: .hd1080p, frameRate: .fps30).isEmpty)
        XCTAssertTrue(menu.blockingLanes(resolution: .uhd4k, frameRate: .fps30).isEmpty)
    }

    // MARK: - Set algebra (multicam settings = camA ∩ camB ∩ camC)

    /// The video options a rig of `lanes` offers, as a set for algebra.
    private func optionSet(_ lanes: [RigQualityMenu.Lane]) -> Set<String> {
        Set(RigQualityMenu(lanes: lanes).videoOptions()
            .map { "\($0.resolution.rawValue):\($0.frameRate.rawValue)" })
    }

    /// The defining property: a three-camera rig's options are exactly the
    /// set intersection of each camera's own options.
    func testRigOptionsAreTheSetIntersectionOfEachCamerasOptions() {
        let camA = lane("A", full4K)
        let camB = lane("B", [.uhd4k: [.fps24, .fps30], .hd1080p: [.fps24, .fps30, .fps60]])
        let camC = lane("C", [.hd1080p: [.fps30, .fps60]])

        XCTAssertEqual(
            optionSet([camA, camB, camC]),
            optionSet([camA]).intersection(optionSet([camB])).intersection(optionSet([camC])))
        // Spelled out: only the 1080p rates every camera shares survive.
        XCTAssertEqual(optionSet([camA, camB, camC]),
                       optionSet([lane("solo", [.hd1080p: [.fps30, .fps60]])]))
    }

    /// Intersection is order-independent: the rig's options don't depend on
    /// which camera joined first.
    func testIntersectionIsCommutative() {
        let camA = lane("A", full4K)
        let camB = lane("B", only1080)
        let camC = lane("C", [.uhd4k: [.fps30], .hd1080p: [.fps30]])
        XCTAssertEqual(optionSet([camA, camB, camC]), optionSet([camC, camA, camB]))
        XCTAssertEqual(optionSet([camA, camB, camC]), optionSet([camB, camC, camA]))
    }

    /// A camera dropping can only widen (or keep) the rig's options — never
    /// shrink them. This is what the settings tray must reflect live.
    func testRemovingACameraNeverShrinksTheOptionSet() {
        let camA = lane("A", full4K)
        let camB = lane("B", only1080)
        let camC = lane("C", [.uhd4k: [.fps30], .hd1080p: [.fps30]])
        XCTAssertTrue(optionSet([camA, camB, camC]).isSubset(of: optionSet([camA, camB])))
        XCTAssertTrue(optionSet([camA, camB]).isSubset(of: optionSet([camA])))
    }

    /// HEIF/HDR are conjunctions: available iff every camera supports them —
    /// checked over every combination of three cameras.
    func testHEIFAndHDRAreANDedAcrossThreeCameras() {
        for mask in 0..<8 {
            let flags = [mask & 1 != 0, mask & 2 != 0, mask & 4 != 0]
            let lanes = flags.enumerated().map { idx, flag in
                lane("Cam \(idx + 1)", only1080, heif: flag, hdr: flag)
            }
            let menu = RigQualityMenu(lanes: lanes)
            let allSupport = flags.allSatisfy { $0 }
            XCTAssertEqual(menu.supportsHEIF(), allSupport, "HEIF for mask \(mask)")
            XCTAssertEqual(menu.supportsHDR(), allSupport, "HDR for mask \(mask)")
            // The blockers are exactly the cameras that can't.
            XCTAssertEqual(Set(menu.lanesBlockingHEIF()),
                           Set(flags.enumerated().filter { !$0.element }.map { "Cam \($0.offset + 1)" }))
        }
    }

    // MARK: - Automatic

    func testAutomaticPicksHighestResThenFps() {
        let menu = RigQualityMenu(lanes: [lane("Cam 1", full4K), lane("Cam 2", full4K)])
        let auto = menu.automaticVideo()
        XCTAssertEqual(auto.resolution, .uhd4k)
        XCTAssertEqual(auto.frameRate, .fps60)
    }

    func testAutomaticFallsBackToFloorOnEmptyIntersection() {
        // Cam 1 does 4K only; Cam 2 does 1080p only → nothing shared but the
        // floor, so Automatic is 1080p30.
        let menu = RigQualityMenu(lanes: [
            lane("Cam 1", [.uhd4k: [.fps30]]),
            lane("Cam 2", [.hd1080p: [.fps30]])])
        let auto = menu.automaticVideo()
        XCTAssertEqual(auto.resolution, RigQualityMenu.floor.resolution)
        XCTAssertEqual(auto.frameRate, RigQualityMenu.floor.frameRate)
    }

    func testEmptyRigAutomaticIsFloor() {
        let menu = RigQualityMenu(lanes: [])
        XCTAssertEqual(menu.automaticVideo().resolution, .hd1080p)
        XCTAssertEqual(menu.automaticVideo().frameRate, .fps30)
    }

    // MARK: - Photo

    func testPhotoIntersection() {
        let both = RigQualityMenu(lanes: [lane("A", only1080, heif: true, hdr: true),
                                          lane("B", only1080, heif: true, hdr: true)])
        XCTAssertTrue(both.supportsHEIF())
        XCTAssertTrue(both.supportsHDR())
        XCTAssertEqual(both.automaticPhoto().format, .heif)
        XCTAssertEqual(both.automaticPhoto().hdr, .on)

        let mixed = RigQualityMenu(lanes: [lane("A", only1080, heif: true, hdr: false),
                                           lane("B", only1080, heif: false, hdr: true)])
        XCTAssertFalse(mixed.supportsHEIF())
        XCTAssertFalse(mixed.supportsHDR())
        XCTAssertEqual(mixed.lanesBlockingHEIF(), ["B"])
        XCTAssertEqual(mixed.lanesBlockingHDR(), ["A"])
        XCTAssertEqual(mixed.automaticPhoto().format, .jpeg)
    }

    // MARK: - Late joiner

    func testLateJoinerThatCannotMatchIsDetected() {
        let menu = RigQualityMenu(lanes: [lane("Cam 1", full4K), lane("Cam 2", only1080)])
        // The rig is running at 4K30; Cam 2 (1080-only) can't match.
        XCTAssertFalse(menu.laneCanMatch(lane("Cam 2", only1080),
                                         resolution: .uhd4k, frameRate: .fps30))
        XCTAssertTrue(menu.laneCanMatch(lane("Cam 1", full4K),
                                        resolution: .uhd4k, frameRate: .fps30))
    }

    // MARK: - Glass tray: quality cycle, tile value, footnote

    private func option(_ res: VideoResolution, _ fps: VideoFrameRate,
                        enabled: Bool = true, blockedBy: [String] = []) -> RigVideoOption {
        RigVideoOption(resolution: res, frameRate: fps, enabled: enabled, blockedBy: blockedBy)
    }

    /// The tile cycles Automatic → each enabled option in order → back to Automatic.
    func testQualityTileCyclesThroughIntersectionAndBackToAuto() {
        let opts = [option(.hd1080p, .fps30), option(.uhd4k, .fps30)]
        var snap = RigSettingsSnapshot(videoOptions: opts)

        // Automatic → first enabled option.
        snap.activeVideo = nil
        XCTAssertEqual(snap.nextVideoSelection, RigVideoSelection(resolution: .hd1080p, frameRate: .fps30))
        // 1080p30 → 4K30.
        snap.activeVideo = RigVideoSelection(resolution: .hd1080p, frameRate: .fps30)
        XCTAssertEqual(snap.nextVideoSelection, RigVideoSelection(resolution: .uhd4k, frameRate: .fps30))
        // Last option → back to Automatic.
        snap.activeVideo = RigVideoSelection(resolution: .uhd4k, frameRate: .fps30)
        XCTAssertNil(snap.nextVideoSelection)
    }

    func testQualityCycleSkipsDisabledOptions() {
        let opts = [option(.hd1080p, .fps30), option(.uhd4k, .fps60, enabled: false, blockedBy: ["iPad"])]
        var snap = RigSettingsSnapshot(videoOptions: opts)
        snap.activeVideo = RigVideoSelection(resolution: .hd1080p, frameRate: .fps30)
        // The only other option is disabled, so the cycle wraps to Automatic.
        XCTAssertNil(snap.nextVideoSelection)
    }

    func testVideoTileValueShowsAutoOrRunningQuality() {
        var snap = RigSettingsSnapshot(videoOptions: [option(.uhd4k, .fps30)])
        snap.activeVideo = nil
        XCTAssertEqual(snap.videoTileValue, "AUTO")
        snap.activeVideo = RigVideoSelection(resolution: .uhd4k, frameRate: .fps30)
        XCTAssertEqual(snap.videoTileValue, RigVideoSelection(resolution: .uhd4k, frameRate: .fps30).label)
    }

    func testFootnoteNamesTheBlockingCamera() {
        var snap = RigSettingsSnapshot(videoOptions: [
            option(.hd1080p, .fps30),
            option(.uhd4k, .fps60, enabled: false, blockedBy: ["iPad"]),
        ])
        XCTAssertNotNil(snap.blockerFootnote(for: .video))
        XCTAssertTrue(snap.blockerFootnote(for: .video)?.contains("iPad") == true)

        // No blockers → no footnote.
        snap = RigSettingsSnapshot(videoOptions: [option(.hd1080p, .fps30)], hdrAvailable: true)
        XCTAssertNil(snap.blockerFootnote(for: .video))
    }

    /// The footnote is scoped to the tray's mode: the photo tray never explains
    /// a video limit, and vice versa.
    func testFootnoteIsModeScoped() {
        var snap = RigSettingsSnapshot(videoOptions: [
            option(.uhd4k, .fps60, enabled: false, blockedBy: ["iPad"]),
        ])
        snap.heifAvailable = true
        snap.hdrAvailable = true
        // A video blocker exists, but the photo tray doesn't list video quality.
        XCTAssertNotNil(snap.blockerFootnote(for: .video))
        XCTAssertNil(snap.blockerFootnote(for: .photo))

        // A HEIF blocker outranks the HDR one; neither shows in video mode.
        snap = RigSettingsSnapshot(videoOptions: [option(.hd1080p, .fps30)])
        snap.heifAvailable = false
        snap.heifBlockedBy = ["iPad"]
        snap.hdrAvailable = false
        snap.hdrBlockedBy = ["iPhone"]
        XCTAssertTrue(snap.blockerFootnote(for: .photo)?.contains("iPad") == true)
        XCTAssertTrue(snap.blockerFootnote(for: .photo)?.contains("HEIF") == true)
        XCTAssertNil(snap.blockerFootnote(for: .video))

        // HDR blocker alone.
        snap.heifAvailable = true
        snap.heifBlockedBy = []
        XCTAssertTrue(snap.blockerFootnote(for: .photo)?.contains("iPhone") == true)
    }
}
