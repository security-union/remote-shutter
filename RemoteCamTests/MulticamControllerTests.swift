//
//  MulticamControllerTests.swift
//  RemoteShutterTests
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import MPCCompat
import XCTest
@testable import RemoteShutter

/// Captures what the controller pushes to the screen.
private final class FakeMulticamDisplay: MulticamDisplay, @unchecked Sendable {
    var lastLanes: [MulticamLaneInfo] = []
    var receivedFrames: [MCPeerID] = []
    var didExit = false

    func applyLanes(_ lanes: [MulticamLaneInfo]) { lastLanes = lanes }
    func receiveFrame(_ frame: RemoteCmd.OnFrame) { receivedFrames.append(frame.peerId) }
    func exitMulticam() { didExit = true }
}

final class MulticamControllerTests: XCTestCase {

    private let camA = MCPeerID(displayName: "CameraA")
    private let camB = MCPeerID(displayName: "CameraB")

    private func makeController(peers: [MCPeerID])
        async -> (MulticamController, FakeMultipeerService, FakeMulticamDisplay) {
        let controller = MulticamController()
        let transport = FakeMultipeerService()
        transport.sendResult = true
        transport.connectedPeers = peers
        let display = FakeMulticamDisplay()
        await controller.setDisplay(display)
        await controller.install(transport: transport, initialPeers: peers, mode: .photo)
        await controller.waitForIdle()
        return (controller, transport, display)
    }

    private func sent<T>(_ transport: FakeMultipeerService, _ type: T.Type)
        -> [(msg: Message, peers: [MCPeerID], mode: MCSessionSendDataMode)] {
        transport.sentMessages.filter { $0.msg is T }
    }

    // MARK: - Handshake

    func testInstallSeedsLaneAndHandshakesEveryCamera() async {
        let (controller, transport, _) = await makeController(peers: [camA, camB])

        let lanes = await controller.lanesForTesting()
        XCTAssertEqual(Set(lanes.map(\.peerID)), [camA, camB])

        // Each camera is asked for capabilities, exactly addressed to itself.
        let requests = sent(transport, RemoteCmd.RequestCameraCapabilities.self)
        XCTAssertEqual(Set(requests.flatMap(\.peers)), [camA, camB])
        for req in requests { XCTAssertEqual(req.peers.count, 1) }

        // And discovery keeps running so more cameras can be added later.
        XCTAssertGreaterThanOrEqual(transport.discoveryStarts, 1)
    }

    func testFirstCameraIsFocused() async {
        let (controller, _, _) = await makeController(peers: [camA, camB])
        let focused = await controller.focusedPeerForTesting()
        XCTAssertEqual(focused, camA)
    }

    // MARK: - Capabilities → live

    func testCapabilitiesMarkLaneLinkedAndPingClockWhenMulticam() async {
        let (controller, transport, _) = await makeController(peers: [camA, camB])
        transport.sentMessages.removeAll()

        controller.didReceiveMessage(multicamCaps(), from: camA)
        await controller.waitForIdle()

        let statusA = await controller.statusForTesting(camA)
        XCTAssertEqual(statusA, .linked)
        // A multicam-capable camera gets an immediate clock probe, to itself.
        let pings = sent(transport, RemoteCmd.ClockSyncPing.self)
        XCTAssertEqual(pings.map(\.peers), [[camA]])
    }

    // MARK: - Frame routing (Seam B)

    func testFrameRoutesToItsLaneAndAcksOnlyItsSource() async {
        let (controller, transport, display) = await makeController(peers: [camA, camB])
        transport.sentMessages.removeAll()

        controller.didReceiveFrame(sendFrame(), from: camB)
        await controller.waitForIdle()

        XCTAssertEqual(display.receivedFrames, [camB])
        let acks = sent(transport, RemoteCmd.RequestFrame.self)
        XCTAssertEqual(acks.map(\.peers), [[camB]],
                       "the frame ack must address only the camera that sent the frame")
    }

    // MARK: - Focused-camera commands

    func testPerCameraCommandTargetsOnlyTheFocusedPeer() async {
        let (controller, transport, _) = await makeController(peers: [camA, camB])
        await controller.setFocusedPeer(camB)
        transport.sentMessages.removeAll()

        await controller.setZoom(2.0)
        await controller.waitForIdle()

        let zooms = sent(transport, RemoteCmd.SetZoom.self)
        XCTAssertEqual(zooms.map(\.peers), [[camB]])
    }

    // MARK: - Disconnect / reconnect

    func testDisconnectDegradesOnlyThatLane() async {
        let (controller, _, _) = await makeController(peers: [camA, camB])

        controller.peerDidDisconnect(camA)
        await controller.waitForIdle()

        let statusA = await controller.statusForTesting(camA)
        let statusB = await controller.statusForTesting(camB)
        XCTAssertEqual(statusA, .reconnecting)
        XCTAssertEqual(statusB, .linked, "one camera dropping must not disturb the others")
    }

    func testBrowserReinvitesOnlyAReconnectingCamera() async {
        let (controller, transport, _) = await makeController(peers: [camA, camB])
        controller.peerDidDisconnect(camA)
        await controller.waitForIdle()
        transport.invitedPeers.removeAll()

        controller.browserDidFindPeer(camA)
        await controller.waitForIdle()
        XCTAssertEqual(transport.invitedPeers.map(\.peer), [camA])

        // A camera that is already linked is not re-invited on a browser hit.
        transport.invitedPeers.removeAll()
        controller.browserDidFindPeer(camB)
        await controller.waitForIdle()
        XCTAssertTrue(transport.invitedPeers.isEmpty)
    }

    // MARK: - Clock sync

    func testPongUpdatesThatLanesOffset() async {
        let (controller, _, _) = await makeController(peers: [camA, camB])

        // Camera A is 500ms ahead; symmetric 20ms RTT is faked via the pong's
        // camera clock relative to our own — we only assert an offset landed.
        controller.didReceiveMessage(
            RemoteCmd.ClockSyncPong(echoT0Millis: SyncClock.nowMillis(),
                                    cameraClockMillis: SyncClock.nowMillis() + 500),
            from: camA)
        await controller.waitForIdle()

        let offsetA = await controller.offsetForTesting(camA)
        let offsetB = await controller.offsetForTesting(camB)
        XCTAssertNotNil(offsetA)
        XCTAssertNil(offsetB)
    }

    // MARK: - Removal

    func testRemoveCameraDropsTheLaneAndRefocuses() async {
        let (controller, _, _) = await makeController(peers: [camA, camB])

        await controller.removeCamera(camA)
        let lanes = await controller.lanesForTesting()
        XCTAssertEqual(lanes.map(\.peerID), [camB])
        let focusedAfter = await controller.focusedPeerForTesting()
        XCTAssertEqual(focusedAfter, camB)
    }

    // MARK: - Fixtures

    private func multicamCaps() -> RemoteCmd.CameraCapabilitiesResp {
        RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, currentLens: .wideAngle, currentZoom: 1.0,
            supportsMulticam: true, error: nil)
    }

    private func sendFrame() -> RemoteCmd.SendFrame {
        RemoteCmd.SendFrame(data: Data([1, 2, 3]), sender: nil,
                            fps: 30, camPosition: .back, camOrientation: .portrait,
                            codec: .vp9, sequenceNumber: 1)
    }
}
