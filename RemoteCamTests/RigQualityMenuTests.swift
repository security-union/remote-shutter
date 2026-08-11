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
            zoomCapabilities: [:],
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
}
