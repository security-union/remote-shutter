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
    var capturing = false
    var recording = false
    var didExit = false

    func applyLanes(_ lanes: [MulticamLaneInfo]) { lastLanes = lanes }
    func applyShutterState(capturing: Bool, recording: Bool) {
        self.capturing = capturing
        self.recording = recording
    }
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

    // MARK: - Synced photo capture

    func testScheduledCaptureAppliesPerLaneOffsets() async {
        let (controller, transport, _) = await makeController(peers: [camA, camB])
        await controller.seedLaneForTesting(camA, supportsMulticam: true, offsetMillis: 100)
        await controller.seedLaneForTesting(camB, supportsMulticam: true, offsetMillis: -50)
        transport.sentMessages.removeAll()

        await controller.capturePhoto()
        await controller.waitForIdle()

        let scheduled = sent(transport, RemoteCmd.ScheduledCapture.self)
        XCTAssertEqual(scheduled.count, 2)
        for s in scheduled { XCTAssertEqual(s.peers.count, 1) }

        func fireAt(_ peer: MCPeerID) -> UInt64? {
            (scheduled.first { $0.peers == [peer] }?.msg as? RemoteCmd.ScheduledCapture)?
                .fireAtCameraClockMillis
        }
        // Same shared anchor + each lane's own offset ⇒ the fire instants differ
        // by exactly the offset difference (100 − (−50) = 150), regardless of
        // the nondeterministic base.
        let a = fireAt(camA), b = fireAt(camB)
        XCTAssertNotNil(a); XCTAssertNotNil(b)
        XCTAssertEqual(Int64(a!) - Int64(b!), 150)

        // One shared capture id across both cameras.
        let ids = Set(scheduled.compactMap { ($0.msg as? RemoteCmd.ScheduledCapture)?.captureId })
        XCTAssertEqual(ids.count, 1)
    }

    func testNonMulticamLaneIsExcludedFromCapture() async {
        let (controller, transport, _) = await makeController(peers: [camA, camB])
        await controller.seedLaneForTesting(camA, supportsMulticam: true, offsetMillis: 10)
        await controller.seedLaneForTesting(camB, supportsMulticam: false, offsetMillis: 10)
        transport.sentMessages.removeAll()

        await controller.capturePhoto()
        await controller.waitForIdle()

        let scheduled = sent(transport, RemoteCmd.ScheduledCapture.self)
        XCTAssertEqual(scheduled.map(\.peers), [[camA]])
        let capture = await controller.captureStateForTesting()
        XCTAssertEqual(capture?.remaining, 1)
    }

    func testAckAggregationReturnsToMonitoring() async {
        let (controller, _, _) = await makeController(peers: [camA, camB])
        await controller.seedLaneForTesting(camA, supportsMulticam: true, offsetMillis: 0)
        await controller.seedLaneForTesting(camB, supportsMulticam: true, offsetMillis: 0)

        await controller.capturePhoto()
        await controller.waitForIdle()
        let captureID = await controller.captureStateForTesting()?.id
        XCTAssertNotNil(captureID)

        controller.didReceiveMessage(RemoteCmd.ScheduledCaptureAck(captureId: captureID!), from: camA)
        await controller.waitForIdle()
        let afterFirst = await controller.captureStateForTesting()
        XCTAssertEqual(afterFirst?.remaining, 1)

        controller.didReceiveMessage(RemoteCmd.ScheduledCaptureAck(captureId: captureID!), from: camB)
        await controller.waitForIdle()
        let afterSecond = await controller.captureStateForTesting()
        let outA = await controller.captureOutcomeForTesting(camA)
        let outB = await controller.captureOutcomeForTesting(camB)
        XCTAssertNil(afterSecond, "back to monitoring")
        XCTAssertEqual(outA, .captured)
        XCTAssertEqual(outB, .captured)
    }

    func testCaptureTimeoutMarksTheSilentLaneAndCompletes() async {
        let (controller, _, _) = await makeController(peers: [camA, camB])
        await controller.setCaptureAckTimeout(0.1)
        await controller.seedLaneForTesting(camA, supportsMulticam: true, offsetMillis: 0)
        await controller.seedLaneForTesting(camB, supportsMulticam: true, offsetMillis: 0)

        await controller.capturePhoto()
        await controller.waitForIdle()
        let captureID = await controller.captureStateForTesting()?.id
        controller.didReceiveMessage(RemoteCmd.ScheduledCaptureAck(captureId: captureID!), from: camA)
        await controller.waitForIdle()

        // Wait out the ack timeout; camB never answered.
        try? await Task.sleep(nanoseconds: 300_000_000)
        let resolved = await controller.captureStateForTesting()
        let outA = await controller.captureOutcomeForTesting(camA)
        let outB = await controller.captureOutcomeForTesting(camB)
        XCTAssertNil(resolved, "aggregate resolves")
        XCTAssertEqual(outA, .captured)
        XCTAssertEqual(outB, .failed)
    }

    func testFallbackToPlainTakePicWhenAnOffsetIsMissing() async {
        let (controller, transport, _) = await makeController(peers: [camA, camB])
        await controller.seedLaneForTesting(camA, supportsMulticam: true, offsetMillis: 20)
        await controller.seedLaneForTesting(camB, supportsMulticam: true, offsetMillis: nil)
        transport.sentMessages.removeAll()

        await controller.capturePhoto()
        await controller.waitForIdle()

        XCTAssertTrue(sent(transport, RemoteCmd.ScheduledCapture.self).isEmpty,
                      "a missing offset forces the plain fan-out")
        let takes = sent(transport, RemoteCmd.TakePic.self)
        XCTAssertEqual(Set(takes.flatMap(\.peers)), [camA, camB])
        let fallbackState = await controller.captureStateForTesting()
        XCTAssertEqual(fallbackState?.remaining, 2)
    }

    // MARK: - Stream profile tiering

    func testFocusedLaneGetsFullProfileOthersGetThumbnail() async {
        let (controller, transport, _) = await makeController(peers: [camA, camB])
        transport.sentMessages.removeAll()

        // Both cameras report multicam caps; camA is focused (first-in).
        controller.didReceiveMessage(multicamCaps(), from: camA)
        controller.didReceiveMessage(multicamCaps(), from: camB)
        await controller.waitForIdle()

        let profiles = sent(transport, RemoteCmd.SetStreamProfile.self)
        func profile(_ p: MCPeerID) -> RemoteCmd.SetStreamProfile? {
            profiles.first { $0.peers == [p] }?.msg as? RemoteCmd.SetStreamProfile
        }
        XCTAssertEqual(profile(camA)?.maxLongEdge, Int(StreamProfile.focused.maxLongEdge))
        XCTAssertEqual(profile(camB)?.maxLongEdge, Int(StreamProfile.thumbnail.maxLongEdge))
    }

    func testFocusSwitchRetiersBothLanes() async {
        let (controller, transport, _) = await makeController(peers: [camA, camB])
        controller.didReceiveMessage(multicamCaps(), from: camA)
        controller.didReceiveMessage(multicamCaps(), from: camB)
        await controller.waitForIdle()
        transport.sentMessages.removeAll()

        await controller.setFocusedPeer(camB)
        await controller.waitForIdle()

        let profiles = sent(transport, RemoteCmd.SetStreamProfile.self)
        func edge(_ p: MCPeerID) -> Int? {
            (profiles.first { $0.peers == [p] }?.msg as? RemoteCmd.SetStreamProfile)?.maxLongEdge
        }
        // camB becomes full, camA drops to thumbnail — no redundant re-sends.
        XCTAssertEqual(edge(camB), Int(StreamProfile.focused.maxLongEdge))
        XCTAssertEqual(edge(camA), Int(StreamProfile.thumbnail.maxLongEdge))
    }

    func testProfileNotResentWhenUnchanged() async {
        let (controller, transport, _) = await makeController(peers: [camA, camB])
        controller.didReceiveMessage(multicamCaps(), from: camA)
        controller.didReceiveMessage(multicamCaps(), from: camB)
        await controller.waitForIdle()
        transport.sentMessages.removeAll()

        // Focusing the already-focused camera changes no tier → no profile sends.
        await controller.setFocusedPeer(camA)
        await controller.waitForIdle()
        XCTAssertTrue(sent(transport, RemoteCmd.SetStreamProfile.self).isEmpty)
    }

    // MARK: - Synced video

    func testStartAndStopAnchorsGiveMatchingClipLengths() async {
        let (controller, transport, _) = await makeController(peers: [camA, camB])
        await controller.seedLaneForTesting(camA, supportsMulticam: true, offsetMillis: 100)
        await controller.seedLaneForTesting(camB, supportsMulticam: true, offsetMillis: -50)
        transport.sentMessages.removeAll()

        await controller.startRecording()
        await controller.waitForIdle()
        let starts = sent(transport, RemoteCmd.ScheduledStartRecording.self)
        func startFire(_ p: MCPeerID) -> UInt64 {
            (starts.first { $0.peers == [p] }!.msg as! RemoteCmd.ScheduledStartRecording).fireAtCameraClockMillis
        }

        // Mark both rolling so stopRecording targets them.
        let recID = await controller.recordingStateForTesting()?.id
        controller.didReceiveMessage(RemoteCmd.ScheduledRecordingAck(captureId: recID!, isStop: false), from: camA)
        controller.didReceiveMessage(RemoteCmd.ScheduledRecordingAck(captureId: recID!, isStop: false), from: camB)
        await controller.waitForIdle()
        transport.sentMessages.removeAll()

        await controller.stopRecording()
        await controller.waitForIdle()
        let stops = sent(transport, RemoteCmd.ScheduledStopRecording.self)
        func stopFire(_ p: MCPeerID) -> UInt64 {
            (stops.first { $0.peers == [p] }!.msg as! RemoteCmd.ScheduledStopRecording).fireAtCameraClockMillis
        }

        // Per-lane clip length (stop − start) is identical across cameras: each
        // lane's offset cancels, leaving the shared (stopBase − startBase).
        let lenA = Int64(stopFire(camA)) - Int64(startFire(camA))
        let lenB = Int64(stopFire(camB)) - Int64(startFire(camB))
        XCTAssertEqual(lenA, lenB, "clip lengths must match across the rig")
        // And the per-lane fire instants differ by the offset delta (150) for
        // both start and stop.
        XCTAssertEqual(Int64(startFire(camA)) - Int64(startFire(camB)), 150)
        XCTAssertEqual(Int64(stopFire(camA)) - Int64(stopFire(camB)), 150)
    }

    func testStartAcksMarkLanesRecording() async {
        let (controller, _, _) = await makeController(peers: [camA, camB])
        await controller.seedLaneForTesting(camA, supportsMulticam: true, offsetMillis: 0)
        await controller.seedLaneForTesting(camB, supportsMulticam: true, offsetMillis: 0)

        await controller.startRecording()
        await controller.waitForIdle()
        let recID = await controller.recordingStateForTesting()?.id
        XCTAssertNotNil(recID)

        controller.didReceiveMessage(RemoteCmd.ScheduledRecordingAck(captureId: recID!, isStop: false), from: camA)
        controller.didReceiveMessage(RemoteCmd.ScheduledRecordingAck(captureId: recID!, isStop: false), from: camB)
        await controller.waitForIdle()

        let recA = await controller.isRecordingForTesting(camA)
        let recB = await controller.isRecordingForTesting(camB)
        XCTAssertTrue(recA)
        XCTAssertTrue(recB)
        // Still recording (all start acks in, remaining 0).
        let stillRecording = await controller.recordingStateForTesting()
        XCTAssertEqual(stillRecording?.remaining, 0)

        // Stop resolves back to monitoring.
        await controller.stopRecording()
        await controller.waitForIdle()
        let stopID = await controller.stoppingStateForTesting()?.id
        controller.didReceiveMessage(RemoteCmd.ScheduledRecordingAck(captureId: stopID!, isStop: true), from: camA)
        controller.didReceiveMessage(RemoteCmd.ScheduledRecordingAck(captureId: stopID!, isStop: true), from: camB)
        await controller.waitForIdle()
        let afterStop = await controller.recordingStateForTesting()
        let stoppingAfter = await controller.stoppingStateForTesting()
        XCTAssertNil(afterStop)
        XCTAssertNil(stoppingAfter, "back to monitoring")
        let recAafter = await controller.isRecordingForTesting(camA)
        XCTAssertFalse(recAafter)
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
