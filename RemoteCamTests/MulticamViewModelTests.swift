//
//  MulticamViewModelTests.swift
//  RemoteShutterTests
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import MPCCompat
import XCTest
@testable import RemoteShutter

final class MulticamViewModelTests: XCTestCase {

    private let camA = MCPeerID(displayName: "CameraA")
    private let camB = MCPeerID(displayName: "CameraB")

    private func info(_ peer: MCPeerID, status: CameraLink.Status = .linked,
                      focused: Bool = false, canFlipCamera: Bool = false,
                      zoomFactor: CGFloat = 1.0, maxZoomFactor: CGFloat = 10.0,
                      zoomStops: [CGFloat] = [1.0], wideAngleZoomFactor: CGFloat = 1.0,
                      torchOn: Bool = false, flashOn: Bool = false) -> MulticamLaneInfo {
        MulticamLaneInfo(peerID: peer, displayName: peer.displayName,
                         status: status, isFocused: focused, clockOffsetMillis: nil,
                         captureOutcome: nil, isRecording: false, needsQualityRematch: false,
                         collection: .idle, canFlipCamera: canFlipCamera,
                         zoomFactor: zoomFactor, maxZoomFactor: maxZoomFactor,
                         zoomStops: zoomStops, wideAngleZoomFactor: wideAngleZoomFactor,
                         torchOn: torchOn, flashOn: flashOn)
    }

    func testApplyAddsLanesAndReportsCreated() {
        let vm = MulticamViewModel()
        let created = vm.apply([info(camA, focused: true), info(camB)])
        XCTAssertEqual(vm.lanes.map(\.peerID), [camA, camB])
        XCTAssertEqual(created.map(\.peerID), [camA, camB])
    }

    func testApplyPreservesExistingLaneInstances() {
        let vm = MulticamViewModel()
        vm.apply([info(camA, focused: true), info(camB)])
        let laneABefore = vm.lane(for: camA)

        // Second apply changes only status; the CameraLane (and its live
        // frames/receiver) must be the same instance, not rebuilt.
        let created = vm.apply([info(camA, status: .reconnecting, focused: true), info(camB)])
        XCTAssertTrue(created.isEmpty, "no new lanes should be created")
        XCTAssertTrue(vm.lane(for: camA) === laneABefore)
        XCTAssertEqual(vm.lane(for: camA)?.status, .reconnecting)
    }

    func testApplyDropsGoneLanes() {
        let vm = MulticamViewModel()
        vm.apply([info(camA, focused: true), info(camB)])
        vm.apply([info(camA, focused: true)])
        XCTAssertEqual(vm.lanes.map(\.peerID), [camA])
        XCTAssertNil(vm.lane(for: camB))
    }

    func testFocusedAndOtherLanesPartition() {
        let vm = MulticamViewModel()
        vm.apply([info(camA, focused: true), info(camB)])
        XCTAssertEqual(vm.focusedLane?.peerID, camA)
        XCTAssertEqual(vm.otherLanes.map(\.peerID), [camB])

        // Refocusing moves the partition without rebuilding lanes.
        vm.apply([info(camA), info(camB, focused: true)])
        XCTAssertEqual(vm.focusedLane?.peerID, camB)
        XCTAssertEqual(vm.otherLanes.map(\.peerID), [camA])
    }

    func testFocusedCameraCanFlipMirrorsTheOneToOneRule() {
        let vm = MulticamViewModel()

        // Focused and linked → live, regardless of advertised positions (the
        // ungated 1:1 rule; the button read as disabled on device when this was
        // gated on both-positions capabilities).
        vm.apply([info(camA, focused: true, canFlipCamera: false), info(camB)])
        XCTAssertTrue(vm.focusedCameraCanFlip)

        // Focused but reconnecting → suppressed until it is linked again.
        vm.apply([info(camA, status: .reconnecting, focused: true, canFlipCamera: true)])
        XCTAssertFalse(vm.focusedCameraCanFlip)

        // No camera focused → nothing to flip.
        vm.apply([info(camA, canFlipCamera: true)])
        XCTAssertFalse(vm.focusedCameraCanFlip)

        // Linked but recording → suppressed, mirroring the monitor.
        vm.apply([info(camA, focused: true, canFlipCamera: true)])
        vm.isRecording = true
        XCTAssertFalse(vm.focusedCameraCanFlip)
    }

    func testFocusedZoomPillSwapsRangeWithFocusAndHidesWhenDegenerate() {
        let vm = MulticamViewModel()
        // Camera A: real range 1–6; Camera B: a wider 2–8 on a 2× wide-angle.
        vm.apply([info(camA, focused: true, zoomFactor: 3, maxZoomFactor: 6,
                       zoomStops: [1, 2], wideAngleZoomFactor: 1),
                  info(camB, zoomFactor: 4, maxZoomFactor: 8,
                       zoomStops: [2, 4], wideAngleZoomFactor: 2)])

        XCTAssertTrue(vm.showsFocusedZoomPill)
        XCTAssertEqual(vm.focusedZoomFactor, 3)
        XCTAssertEqual(vm.focusedZoomScale.maxZoom, 6)

        // Refocusing swaps the displayed range to camera B's.
        vm.apply([info(camA, zoomFactor: 3, maxZoomFactor: 6, zoomStops: [1, 2]),
                  info(camB, focused: true, zoomFactor: 4, maxZoomFactor: 8,
                       zoomStops: [2, 4], wideAngleZoomFactor: 2)])
        XCTAssertEqual(vm.focusedZoomFactor, 4)
        XCTAssertEqual(vm.focusedZoomScale.maxZoom, 8)

        // A fixed-focal-length camera (max == min) → the pill hides, like 1:1.
        vm.apply([info(camA, focused: true, zoomFactor: 1, maxZoomFactor: 1, zoomStops: [1])])
        XCTAssertFalse(vm.showsFocusedZoomPill)
    }

    func testFocusedControlStateDerivesFromTheFocusedLane() {
        let vm = MulticamViewModel()
        vm.apply([info(camA, focused: true, torchOn: true, flashOn: false), info(camB)])

        XCTAssertTrue(vm.focusedControlsEnabled)
        XCTAssertTrue(vm.focusedTorchOn)
        XCTAssertFalse(vm.focusedFlashOn)
        XCTAssertEqual(vm.focusedLinkState, .live)
        // Photo mode → flash available; video mode → not.
        vm.mode = .photo
        XCTAssertTrue(vm.focusedFlashEnabled)
        vm.mode = .video
        XCTAssertFalse(vm.focusedFlashEnabled)

        // Reconnecting focus → controls off, chip shows reconnecting.
        vm.apply([info(camA, status: .reconnecting, focused: true)])
        XCTAssertFalse(vm.focusedControlsEnabled)
        XCTAssertEqual(vm.focusedLinkState, .reconnecting)
    }
}

/// The shared enablement rules both camera-control paths derive from.
final class FocusedCameraControlStateTests: XCTestCase {
    func testEnablementRules() {
        // Linked, photo, idle → everything on.
        let photo = FocusedCameraControlState(isLinked: true, isPhotoMode: true, isRecording: false)
        XCTAssertTrue(photo.flipEnabled)
        XCTAssertTrue(photo.torchEnabled)
        XCTAssertTrue(photo.flashEnabled)

        // Video mode → flash off; flip/torch stay on.
        let video = FocusedCameraControlState(isLinked: true, isPhotoMode: false, isRecording: false)
        XCTAssertFalse(video.flashEnabled)
        XCTAssertTrue(video.flipEnabled)
        XCTAssertTrue(video.torchEnabled)

        // Recording → flip and flash off; torch stays.
        let rec = FocusedCameraControlState(isLinked: true, isPhotoMode: true, isRecording: true)
        XCTAssertFalse(rec.flipEnabled)
        XCTAssertFalse(rec.flashEnabled)
        XCTAssertTrue(rec.torchEnabled)

        // Not linked → nothing.
        let off = FocusedCameraControlState(isLinked: false, isPhotoMode: true, isRecording: false)
        XCTAssertFalse(off.flipEnabled)
        XCTAssertFalse(off.torchEnabled)
        XCTAssertFalse(off.flashEnabled)
    }
}

/// The shared zoom math both paths derive from.
final class ZoomScaleSeedTests: XCTestCase {
    func testClampCapsAtFiveTimesWideAngle() {
        XCTAssertEqual(ZoomScaleSeed.clampMaxZoom(8, wideAngle: 1), 5)     // 5×1 ceiling
        XCTAssertEqual(ZoomScaleSeed.clampMaxZoom(8, wideAngle: 2), 8)     // 5×2 = 10, so 8 stands
        XCTAssertEqual(ZoomScaleSeed.clampMaxZoom(20, wideAngle: 2), 10)   // capped at 5×2
    }

    func testSeedReadsStopsWideAngleFactorAndClampedRange() {
        let info = RemoteCmd.CameraInfo(
            availableLenses: [.wideAngle], hasFlash: true, hasTorch: true,
            zoomCapabilities: [.wideAngle: RemoteCmd.ZoomRange(minZoom: 1, maxZoom: 8)],
            supportedResolutions: [.hd1080p], supportedFrameRates: [.fps30],
            resolutionFrameRates: [.hd1080p: [.fps30]], supportsHEIF: false, supportsHDR: false,
            zoomStops: [1, 2], wideAngleZoomFactor: 1)
        let caps = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: info,
            currentCamera: .back, currentLens: .wideAngle, currentZoom: 3,
            supportsMulticam: true, error: nil)

        let seed = ZoomScaleSeed.seed(from: caps)
        XCTAssertEqual(seed?.zoomFactor, 3)
        XCTAssertEqual(seed?.zoomStops, [1, 2])
        XCTAssertEqual(seed?.wideAngleZoomFactor, 1)
        XCTAssertEqual(seed?.maxZoomFactor, 5, "range 1–8 clamps to the 5×wide ceiling")
    }

    func testSeedLeavesCeilingUnsetWhenNoRangeForCurrentLens() {
        let info = RemoteCmd.CameraInfo(
            availableLenses: [.wideAngle], hasFlash: false, hasTorch: false,
            zoomCapabilities: [:],   // no range advertised
            supportedResolutions: [.hd1080p], supportedFrameRates: [.fps30],
            resolutionFrameRates: [.hd1080p: [.fps30]], supportsHEIF: false, supportsHDR: false,
            zoomStops: [1], wideAngleZoomFactor: 1)
        let caps = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: info,
            currentCamera: .back, currentLens: .wideAngle, currentZoom: 1,
            supportsMulticam: true, error: nil)
        XCTAssertNil(ZoomScaleSeed.seed(from: caps)?.maxZoomFactor)
    }
}

/// The genuinely-shared coordinator mechanics both actors adopt.
final class PeerSessionCoreTests: XCTestCase {
    func testOnFrameForwardingCopiesEveryField() {
        let peer = MCPeerID(displayName: "Cam")
        let frame = RemoteCmd.SendFrame(data: Data([9, 8, 7]), sender: nil,
                                        fps: 24, camPosition: .front, camOrientation: .landscapeLeft,
                                        codec: .hevc, sequenceNumber: 42)
        let onFrame = RemoteCmd.OnFrame(forwarding: frame, from: peer)
        XCTAssertEqual(onFrame.data, Data([9, 8, 7]))
        XCTAssertEqual(onFrame.peerId, peer)
        XCTAssertEqual(onFrame.fps, 24)
        XCTAssertEqual(onFrame.camPosition, .front)
        XCTAssertEqual(onFrame.camOrientation, .landscapeLeft)
        XCTAssertEqual(onFrame.codec, .hevc)
        XCTAssertEqual(onFrame.sequenceNumber, 42)
    }

    func testIsCompatibleMatchesDecideAndDefaultsTrueWithoutLocalVersion() {
        // A missing local version never blames the peer.
        if PeerAppCompatibility.localVersion == nil {
            XCTAssertTrue(PeerAppCompatibility.isCompatible(remoteShortVersion: "0.0"))
            return
        }
        // Otherwise it agrees with `decide` for a same-major and a cross-major peer.
        let local = PeerAppCompatibility.localVersion!
        for remote in ["\(local.major).0", "\(local.major + 1).0", nil] {
            let expected = PeerAppCompatibility.decide(local: local, remoteShortVersion: remote) == .compatible
            XCTAssertEqual(PeerAppCompatibility.isCompatible(remoteShortVersion: remote), expected,
                           "isCompatible must mirror decide for remote \(remote ?? "nil")")
        }
    }

    func testReconnectTickFiresAfterDelayAndNotWhenCancelled() async {
        let fired = expectation(description: "tick fired")
        PeerReconnect.scheduleTick(after: 0.02) { fired.fulfill() }
        await fulfillment(of: [fired], timeout: 1.0)

        let notFired = expectation(description: "cancelled tick never fires")
        notFired.isInverted = true
        let task = PeerReconnect.scheduleTick(after: 0.2) { notFired.fulfill() }
        task.cancel()
        await fulfillment(of: [notFired], timeout: 0.4)
    }
}
