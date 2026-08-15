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
                      currentZoomFactor: CGFloat = 1.0, torchOn: Bool = false,
                      flashOn: Bool = false) -> MulticamLaneInfo {
        MulticamLaneInfo(peerID: peer, displayName: peer.displayName,
                         status: status, isFocused: focused, clockOffsetMillis: nil,
                         captureOutcome: nil, isRecording: false, needsQualityRematch: false,
                         collection: .idle, canFlipCamera: canFlipCamera,
                         currentZoomFactor: currentZoomFactor, torchOn: torchOn,
                         flashOn: flashOn)
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
