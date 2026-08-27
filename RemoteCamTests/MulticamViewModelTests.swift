//
//  MulticamViewModelTests.swift
//  RemoteShutterTests
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import MPCCompat
import Stormo
import XCTest
@testable import RemoteShutter

final class MulticamViewModelTests: XCTestCase {

    private let camA = MCPeerID(displayName: "CameraA")
    private let camB = MCPeerID(displayName: "CameraB")

    private func info(_ peer: MCPeerID, status: CameraLink.Status = .linked,
                      focused: Bool = false, canFlipCamera: Bool = false,
                      supportsFocusPoint: Bool = false, hasTorch: Bool = false,
                      supportsManualExposure: Bool = false,
                      supportsCinematicVideo: Bool = false,
                      zoomFactor: CGFloat = 1.0, maxZoomFactor: CGFloat = 10.0,
                      zoomStops: [CGFloat] = [1.0], wideAngleZoomFactor: CGFloat = 1.0,
                      torchOn: Bool = false, flashOn: Bool = false) -> MulticamLaneInfo {
        MulticamLaneInfo(peerID: peer, displayName: peer.displayName,
                         status: status, isFocused: focused, clockOffsetMillis: nil,
                         captureOutcome: nil, isRecording: false, recordingElapsedMillis: nil,
                         needsQualityRematch: false,
                         collection: .idle, canFlipCamera: canFlipCamera,
                         supportsFocusPoint: supportsFocusPoint,
                         supportsManualExposure: supportsManualExposure, exposure: nil,
                         supportsCinematicVideo: supportsCinematicVideo, cinematic: nil,
                         hasTorch: hasTorch,
                         zoomFactor: zoomFactor, maxZoomFactor: maxZoomFactor,
                         zoomStops: zoomStops, wideAngleZoomFactor: wideAngleZoomFactor,
                         torchOn: torchOn, flashOn: flashOn)
    }

    /// The pro tiles are a property of the FOCUSED camera: refocusing from a
    /// camera without pro controls to one with them makes them appear, and
    /// Cinematic alone earns its tile only once the director is in video mode.
    func testProTilesFollowFocusedCameraCapabilities() {
        let vm = MulticamViewModel()
        vm.apply([info(camA, focused: true), info(camB, supportsManualExposure: true)])
        XCTAssertTrue(vm.focusedProTiles.isEmpty, "focused camera offers nothing")

        vm.apply([info(camA), info(camB, focused: true, supportsManualExposure: true)])
        XCTAssertEqual(vm.focusedProTiles, [.shutter, .iso], "focused camera does manual exposure")

        vm.apply([info(camA), info(camB, focused: true, supportsCinematicVideo: true)])
        XCTAssertTrue(vm.focusedProTiles.isEmpty, "Cinematic is not a photo control")
        vm.mode = .video
        XCTAssertEqual(vm.focusedProTiles, [.cinematic])

        vm.apply([info(camA), info(camB, status: .reconnecting, focused: true, supportsManualExposure: true)])
        XCTAssertTrue(vm.focusedProTiles.isEmpty, "a dropped camera cannot be driven")
    }

    /// An open slider stays only while the focused camera still offers its
    /// tile: refocusing onto a camera without manual exposure hides it (the
    /// choice is remembered, so focusing back restores it).
    func testOpenSliderFollowsTheFocusedCamera() {
        let vm = MulticamViewModel()
        vm.apply([info(camA, focused: true, supportsManualExposure: true), info(camB)])
        vm.activeProSlider = .shutter
        XCTAssertEqual(vm.visibleProSlider, .shutter)

        vm.apply([info(camA, supportsManualExposure: true), info(camB, focused: true)])
        XCTAssertNil(vm.visibleProSlider, "camB has no shutter to slide")

        vm.apply([info(camA, focused: true, supportsManualExposure: true), info(camB)])
        XCTAssertEqual(vm.visibleProSlider, .shutter)
    }

    /// The shutter is a broadcast: cameras present is enough — focus is
    /// presentation and must never gate firing.
    func testShutterNeedsCamerasNotFocus() {
        let vm = MulticamViewModel()
        XCTAssertFalse(vm.canFire, "no cameras, nothing to fire")

        _ = vm.apply([info(camA)]) // present but NOT focused
        XCTAssertTrue(vm.canFire, "an unfocused rig still fires")

        vm.isCapturing = true
        XCTAssertFalse(vm.canFire, "never mid-capture")
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

    /// The torch glyph shows only in focus mode, and only when the focused
    /// camera's current device has a torch — the grid has no "current" camera
    /// to drive, and a torchless (front) camera must not offer a dead control.
    func testTorchButtonShowsOnlyInFocusModeWhenFocusedCameraHasTorch() {
        let vm = MulticamViewModel()

        // Focused camera has a torch, focus mode → shown.
        vm.apply([info(camA, focused: true, hasTorch: true), info(camB)])
        XCTAssertTrue(vm.showsTorchButton)

        // Grid (collage) mode → hidden, torch or not.
        vm.displayMode = .grid
        XCTAssertFalse(vm.showsTorchButton)
        vm.displayMode = .focus

        // Refocusing onto a torchless camera → hidden.
        vm.apply([info(camA, hasTorch: true), info(camB, focused: true, hasTorch: false)])
        XCTAssertFalse(vm.showsTorchButton)

        // No focused lane (or capabilities not in yet) → hidden.
        vm.apply([info(camA, hasTorch: true)])
        XCTAssertFalse(vm.showsTorchButton)
    }

    /// The last leg of the caps→controls chain: applying a lane snapshot that
    /// (only) gained a torch must publish the view model — that's what makes
    /// SwiftUI re-run the chrome and re-evaluate `showsTorchButton`. Pins the
    /// first-render race where capabilities arrive after the screen is up.
    func testApplyingTorchBearingCapsPublishesAndFlipsTheButton() {
        let vm = MulticamViewModel()
        vm.apply([info(camA, focused: true, hasTorch: false)]) // pre-caps render
        XCTAssertFalse(vm.showsTorchButton)

        var published = false
        let sub = vm.objectWillChange.sink { published = true }
        defer { sub.cancel() }

        // The caps-bearing snapshot arrives; nothing else about the lane changed.
        vm.apply([info(camA, focused: true, hasTorch: true)])
        XCTAssertTrue(published, "apply must publish so the chrome re-renders")
        XCTAssertTrue(vm.showsTorchButton)
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

/// The tile badge coalesces capture + collection into exactly one status, on a
/// strict priority ladder — the fix for the overlapping-checks blob.
final class TileStatusTests: XCTestCase {
    private func resolve(_ status: CameraLink.Status = .linked,
                         capture: CaptureOutcome? = nil,
                         recording: Bool = false,
                         collection: CameraLink.LaneCollectionState = .idle,
                         rematch: Bool = false,
                         includeSuccess: Bool = true) -> TileStatus {
        TileStatus.resolve(status: status, captureOutcome: capture, isRecording: recording,
                           collection: collection, needsQualityRematch: rematch,
                           includeSuccess: includeSuccess)
    }

    func testCapturedAndCollectedCollapseToOneSuccess() {
        // The exact device case: a synced photo is both captured AND collected.
        XCTAssertEqual(resolve(capture: .captured, collection: .collected), .success)
        // Either alone is also a single success.
        XCTAssertEqual(resolve(capture: .captured), .success)
        XCTAssertEqual(resolve(collection: .collected), .success)
    }

    func testPriorityLadder() {
        // transfer-failed beats everything, even a fresh capture success.
        XCTAssertEqual(resolve(capture: .captured, collection: .failed), .transferFailed)
        // capture-failed beats reconnecting/transferring.
        XCTAssertEqual(resolve(.reconnecting, capture: .failed, collection: .transferring(0.5)), .captureFailed)
        // reconnecting beats transferring.
        XCTAssertEqual(resolve(.reconnecting, collection: .transferring(0.5)), .reconnecting)
        // transferring beats REC.
        XCTAssertEqual(resolve(recording: true, collection: .transferring(0.3)), .transferring(0.3))
        // REC beats a success confirmation.
        XCTAssertEqual(resolve(capture: .captured, recording: true), .recording)
        // success beats a rematch warning.
        XCTAssertEqual(resolve(capture: .captured, rematch: true), .success)
        // rematch is the last thing before nothing.
        XCTAssertEqual(resolve(rematch: true), .needsRematch)
        XCTAssertEqual(resolve(), .none)
    }

    func testRestingStatusRevealedWhenSuccessFades() {
        // With success suppressed (faded), the tile falls back to its resting
        // state: a rematch warning if present, else nothing — never two badges.
        XCTAssertEqual(resolve(capture: .captured, rematch: true, includeSuccess: false), .needsRematch)
        XCTAssertEqual(resolve(capture: .captured, collection: .collected, includeSuccess: false), .none)
    }

    func testOnlyReconnectingIsTransient() {
        XCTAssertTrue(TileStatus.success.isTransient)
        for s: TileStatus in [.none, .reconnecting, .recording, .transferring(0.5),
                              .captureFailed, .transferFailed, .needsRematch] {
            XCTAssertFalse(s.isTransient, "\(s) must not auto-fade")
        }
    }
}

/// The discovery-list model shared by the main scanner and the director's
/// add-camera flow — one place for the name-resolution rule.
final class DiscoveredPeersTests: XCTestCase {
    private func hashed(_ tag: UInt8, _ name: String) -> MCPeerID {
        PeerID(keyHash: Data([0x12, 0x20]) + Data(repeating: tag, count: 32), displayName: name)
    }

    func testUpsertAppendsNewAndUpgradesReDeliveredInPlace() {
        var d = DiscoveredPeers()
        d.upsert(hashed(0x01, "QmAbc…"))
        d.upsert(hashed(0x02, "iPad"))
        XCTAssertEqual(d.peers.count, 2)

        // Re-delivery of peer 0x01 with a resolved name replaces in place.
        d.upsert(hashed(0x01, "Dario's iPhone"))
        XCTAssertEqual(d.peers.count, 2, "no duplicate")
        XCTAssertEqual(d.peers.first?.displayName, "Dario's iPhone", "name upgraded in place")
        XCTAssertEqual(d.peers.first, hashed(0x01, "anything"), "identity is key-hash, not name")
    }

    func testStaticUpsertMatchesTheStructRule() {
        // The scanner view model uses the static form over its own @Published
        // array — same in-place upgrade.
        var peers: [MCPeerID] = []
        DiscoveredPeers.upsert(&peers, hashed(0x03, "Qm…"))
        DiscoveredPeers.upsert(&peers, hashed(0x03, "iPad Pro"))
        XCTAssertEqual(peers.count, 1)
        XCTAssertEqual(peers[0].displayName, "iPad Pro")
    }

    func testRemoveAndContains() {
        var d = DiscoveredPeers()
        let p = hashed(0x04, "Cam")
        d.upsert(p)
        XCTAssertTrue(d.contains(p))
        XCTAssertTrue(d.remove(p))
        XCTAssertFalse(d.contains(p))
        XCTAssertFalse(d.remove(p), "removing an absent peer reports false")
    }
}
