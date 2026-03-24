//
//  CameraRegistryTests.swift
//  RemoteShutterTests
//

import XCTest
import MultipeerConnectivity

@testable import RemoteShutter

class CameraRegistryTests: XCTestCase {

    var registry: CameraRegistry!
    let peer1 = MCPeerID(displayName: "Camera1")
    let peer2 = MCPeerID(displayName: "Camera2")
    let peer3 = MCPeerID(displayName: "Camera3")

    override func setUp() {
        super.setUp()
        registry = CameraRegistry()
    }

    // MARK: - Add

    func testAddPeer() {
        registry.add(peer: peer1)

        XCTAssertEqual(registry.count, 1)
        XCTAssertTrue(registry.contains(peer: peer1))
        XCTAssertEqual(registry.allPeers.count, 1)
    }

    func testAddSetsFirstPeerAsSelected() {
        registry.add(peer: peer1)

        XCTAssertEqual(registry.selectedCamera, peer1)
    }

    func testAddSecondPeerDoesNotChangeSelection() {
        registry.add(peer: peer1)
        registry.add(peer: peer2)

        XCTAssertEqual(registry.selectedCamera, peer1)
        XCTAssertEqual(registry.count, 2)
    }

    func testAddDuplicateIsNoOp() {
        registry.add(peer: peer1)
        registry.add(peer: peer1)

        XCTAssertEqual(registry.count, 1)
    }

    // MARK: - Remove

    func testRemovePeer() {
        registry.add(peer: peer1)
        registry.remove(peer: peer1)

        XCTAssertEqual(registry.count, 0)
        XCTAssertTrue(registry.isEmpty)
        XCTAssertFalse(registry.contains(peer: peer1))
    }

    func testRemoveSelectedPeerSelectsNext() {
        registry.add(peer: peer1)
        registry.add(peer: peer2)
        registry.remove(peer: peer1)

        XCTAssertEqual(registry.selectedCamera, peer2)
        XCTAssertEqual(registry.count, 1)
    }

    func testRemoveLastPeerClearsSelection() {
        registry.add(peer: peer1)
        registry.remove(peer: peer1)

        XCTAssertNil(registry.selectedCamera)
    }

    func testRemoveNilIsNoOp() {
        registry.add(peer: peer1)
        registry.remove(peer: nil)

        XCTAssertEqual(registry.count, 1)
    }

    func testRemoveNonExistentIsNoOp() {
        registry.add(peer: peer1)
        registry.remove(peer: peer2)

        XCTAssertEqual(registry.count, 1)
    }

    // MARK: - Status

    func testUpdateStatus() {
        registry.add(peer: peer1)
        registry.updateStatus(peer: peer1, status: .capturing)

        XCTAssertEqual(registry.cameras[peer1]?.status, .capturing)
    }

    func testInitialStatusIsConnected() {
        registry.add(peer: peer1)

        XCTAssertEqual(registry.cameras[peer1]?.status, .connected)
    }

    // MARK: - Reset

    func testReset() {
        registry.add(peer: peer1)
        registry.add(peer: peer2)
        registry.reset()

        XCTAssertTrue(registry.isEmpty)
        XCTAssertNil(registry.selectedCamera)
        XCTAssertEqual(registry.count, 0)
    }

    // MARK: - Multiple Peers

    func testMultiplePeers() {
        registry.add(peer: peer1)
        registry.add(peer: peer2)
        registry.add(peer: peer3)

        XCTAssertEqual(registry.count, 3)
        XCTAssertTrue(registry.contains(peer: peer1))
        XCTAssertTrue(registry.contains(peer: peer2))
        XCTAssertTrue(registry.contains(peer: peer3))
        XCTAssertEqual(registry.allPeers.count, 3)
    }

    func testDisplayName() {
        registry.add(peer: peer1)

        XCTAssertEqual(registry.cameras[peer1]?.displayName, "Camera1")
    }

    // MARK: - Available Cameras

    func testAddAvailable() {
        registry.addAvailable(peer: peer1)

        XCTAssertEqual(registry.availableCameras.count, 1)
        XCTAssertEqual(registry.availableCameras.first, peer1)
    }

    func testAddAvailableDuplicateIsNoOp() {
        registry.addAvailable(peer: peer1)
        registry.addAvailable(peer: peer1)

        XCTAssertEqual(registry.availableCameras.count, 1)
    }

    func testAddAvailableSkipsConnectedPeer() {
        registry.add(peer: peer1)
        registry.addAvailable(peer: peer1)

        XCTAssertEqual(registry.availableCameras.count, 0)
    }

    func testRemoveAvailable() {
        registry.addAvailable(peer: peer1)
        registry.addAvailable(peer: peer2)
        registry.removeAvailable(peer: peer1)

        XCTAssertEqual(registry.availableCameras.count, 1)
        XCTAssertEqual(registry.availableCameras.first, peer2)
    }

    func testConnectingAvailablePeerMovesToConnected() {
        registry.addAvailable(peer: peer1)
        XCTAssertEqual(registry.availableCameras.count, 1)

        registry.add(peer: peer1)

        XCTAssertEqual(registry.availableCameras.count, 0)
        XCTAssertTrue(registry.contains(peer: peer1))
    }

    func testResetClearsAvailable() {
        registry.addAvailable(peer: peer1)
        registry.addAvailable(peer: peer2)
        registry.reset()

        XCTAssertEqual(registry.availableCameras.count, 0)
    }

    // MARK: - Max Cameras Limit

    func testMaxCamerasIs7() {
        XCTAssertEqual(CameraRegistry.maxCameras, 7)
    }

    func testAddRejectsWhenFull() {
        for i in 0..<7 {
            let added = registry.add(peer: MCPeerID(displayName: "Cam\(i)"))
            XCTAssertTrue(added)
        }
        XCTAssertEqual(registry.count, 7)
        XCTAssertTrue(registry.isFull)

        let rejected = registry.add(peer: MCPeerID(displayName: "Cam8"))
        XCTAssertFalse(rejected)
        XCTAssertEqual(registry.count, 7)
    }

    func testAddAllowedAfterRemoveFromFull() {
        for i in 0..<7 {
            registry.add(peer: MCPeerID(displayName: "Cam\(i)"))
        }
        XCTAssertTrue(registry.isFull)

        registry.remove(peer: registry.allPeers.first)
        XCTAssertFalse(registry.isFull)

        let added = registry.add(peer: MCPeerID(displayName: "NewCam"))
        XCTAssertTrue(added)
        XCTAssertEqual(registry.count, 7)
    }
}
