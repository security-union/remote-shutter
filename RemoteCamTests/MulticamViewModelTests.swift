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
                      focused: Bool = false) -> MulticamLaneInfo {
        MulticamLaneInfo(peerID: peer, displayName: peer.displayName,
                         status: status, isFocused: focused, clockOffsetMillis: nil)
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
}
