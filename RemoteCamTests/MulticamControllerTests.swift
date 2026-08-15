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
    var capturing = false
    var recording = false
    var availablePeers: [MCPeerID] = []
    var rigSettings: RigSettingsSnapshot?
    var didExit = false

    func applyLanes(_ lanes: [MulticamLaneInfo]) { lastLanes = lanes }
    func applyShutterState(capturing: Bool, recording: Bool) {
        self.capturing = capturing
        self.recording = recording
    }
    func applyAvailablePeers(_ peers: [MCPeerID]) { availablePeers = peers }
    func applyRigSettings(_ settings: RigSettingsSnapshot) { rigSettings = settings }
    func exitMulticam() { didExit = true }
}

/// Records which peers' frame sinks fired — the test stand-in for the view
/// controller's per-lane decoders. Reads happen after `waitForIdle`.
private final class FrameSinkCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _peers: [MCPeerID] = []
    var peers: [MCPeerID] { lock.lock(); defer { lock.unlock() }; return _peers }
    func record(_ peer: MCPeerID) { lock.lock(); _peers.append(peer); lock.unlock() }
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
        let (controller, transport, _) = await makeController(peers: [camA, camB])
        // Register a per-lane sink for each camera, mirroring how the view
        // controller wires one at lane creation.
        let collector = FrameSinkCollector()
        let (a, b) = (camA, camB)
        await controller.setFrameSink(for: a) { _ in collector.record(a) }
        await controller.setFrameSink(for: b) { _ in collector.record(b) }
        transport.sentMessages.removeAll()

        controller.didReceiveFrame(sendFrame(), from: camB)
        await controller.waitForIdle()

        XCTAssertEqual(collector.peers, [camB],
                       "the frame reaches only its own lane's decoder, never another's")
        let acks = sent(transport, RemoteCmd.RequestFrame.self)
        XCTAssertEqual(acks.map(\.peers), [[camB]],
                       "the frame ack must address only the camera that sent the frame")
    }

    // MARK: - Focused-camera commands

    func testPerCameraCommandTargetsOnlyTheFocusedPeer() async {
        let (controller, transport, _) = await makeController(peers: [camA, camB])
        controller.setFocusedPeer(camB)
        await controller.waitForIdle()
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

        controller.capturePhoto()
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

        controller.capturePhoto()
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

        controller.capturePhoto()
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

        controller.capturePhoto()
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

        controller.capturePhoto()
        await controller.waitForIdle()

        XCTAssertTrue(sent(transport, RemoteCmd.ScheduledCapture.self).isEmpty,
                      "a missing offset forces the plain fan-out")
        let takes = sent(transport, RemoteCmd.TakePic.self)
        XCTAssertEqual(Set(takes.flatMap(\.peers)), [camA, camB])
        let fallbackState = await controller.captureStateForTesting()
        XCTAssertEqual(fallbackState?.remaining, 2)
    }

    // MARK: - Add camera

    func testDiscoveredPeerBecomesAvailableButDoesNotAutoJoin() async {
        let camC = MCPeerID(displayName: "CameraC")
        let (controller, transport, _) = await makeController(peers: [camA, camB])
        transport.invitedPeers.removeAll()

        controller.browserDidFindPeer(camC)
        await controller.waitForIdle()

        let available = await controller.availablePeersForTesting()
        XCTAssertEqual(available, [camC])
        // A fresh peer is a candidate only — it is never auto-invited.
        XCTAssertTrue(transport.invitedPeers.isEmpty)
        // And it is not in the rig.
        let count = await controller.cameraCountForTesting()
        XCTAssertEqual(count, 2)
    }

    func testInviteCameraInvitesADiscoveredPeer() async {
        let camC = MCPeerID(displayName: "CameraC")
        let (controller, transport, _) = await makeController(peers: [camA, camB])
        controller.browserDidFindPeer(camC)
        await controller.waitForIdle()
        transport.invitedPeers.removeAll()

        controller.inviteCamera(camC)
        await controller.waitForIdle()
        XCTAssertEqual(transport.invitedPeers.map(\.peer), [camC])

        // Inviting a peer that was never discovered does nothing.
        transport.invitedPeers.removeAll()
        controller.inviteCamera(MCPeerID(displayName: "Ghost"))
        await controller.waitForIdle()
        XCTAssertTrue(transport.invitedPeers.isEmpty)
    }

    func testAvailablePeerClearsOnceItJoins() async {
        let camC = MCPeerID(displayName: "CameraC")
        let (controller, _, _) = await makeController(peers: [camA, camB])
        controller.browserDidFindPeer(camC)
        await controller.waitForIdle()
        let avail = await controller.availablePeersForTesting()
        XCTAssertEqual(avail, [camC])

        controller.peerDidConnect(camC)
        await controller.waitForIdle()
        let availAfter = await controller.availablePeersForTesting()
        let countAfter = await controller.cameraCountForTesting()
        XCTAssertTrue(availAfter.isEmpty)
        XCTAssertEqual(countAfter, 3)
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

        controller.startRecording()
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

        controller.stopRecording()
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

        controller.startRecording()
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
        controller.stopRecording()
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

        controller.removeCamera(camA)
        await controller.waitForIdle()
        let lanes = await controller.lanesForTesting()
        XCTAssertEqual(lanes.map(\.peerID), [camB])
        let focusedAfter = await controller.focusedPeerForTesting()
        XCTAssertEqual(focusedAfter, camB)
    }

    // MARK: - Rig quality (intersection) + timer

    /// Caps whose current (back) camera advertises a resolution/fps matrix.
    private func capsWith(_ matrix: [VideoResolution: [VideoFrameRate]],
                          heif: Bool = true, hdr: Bool = true) -> RemoteCmd.CameraCapabilitiesResp {
        let info = RemoteCmd.CameraInfo(
            availableLenses: [.wideAngle], hasFlash: true, hasTorch: true,
            zoomCapabilities: [:],
            supportedResolutions: Array(matrix.keys),
            supportedFrameRates: Array(Set(matrix.values.flatMap { $0 })),
            resolutionFrameRates: matrix, supportsHEIF: heif, supportsHDR: hdr)
        return RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: info,
            currentCamera: .back, currentLens: .wideAngle, currentZoom: 1.0,
            supportsMulticam: true, error: nil)
    }

    private let full4K: [VideoResolution: [VideoFrameRate]] =
        [.uhd4k: [.fps30, .fps60], .hd1080p: [.fps30, .fps60]]
    private let only1080: [VideoResolution: [VideoFrameRate]] = [.hd1080p: [.fps30]]

    func testSetVideoQualityFansOutToEveryLane() async {
        let (controller, transport, _) = await makeController(peers: [camA, camB])
        transport.sentMessages.removeAll()

        controller.setVideoQuality(resolution: .uhd4k, frameRate: .fps30)
        await controller.waitForIdle()

        let sends = sent(transport, RemoteCmd.SetVideoQuality.self)
        XCTAssertEqual(Set(sends.flatMap(\.peers)), [camA, camB])
        for s in sends {
            let q = s.msg as? RemoteCmd.SetVideoQuality
            XCTAssertEqual(q?.resolution, .uhd4k)
            XCTAssertEqual(q?.frameRate, .fps30)
        }
        let active = await controller.activeVideoQualityForTesting()
        XCTAssertEqual(active?.0, .uhd4k)
    }

    /// Manual toggle between two shared options fans out each time (Dario's
    /// first-class-manual requirement).
    func testManualQualityToggleFansOutEachTime() async {
        let (controller, transport, _) = await makeController(peers: [camA, camB])
        controller.didReceiveMessage(capsWith(full4K), from: camA)
        controller.didReceiveMessage(capsWith(full4K), from: camB)
        await controller.waitForIdle()
        transport.sentMessages.removeAll()

        controller.setVideoQuality(resolution: .hd1080p, frameRate: .fps30)
        controller.setVideoQuality(resolution: .uhd4k, frameRate: .fps30)
        await controller.waitForIdle()

        let sends = sent(transport, RemoteCmd.SetVideoQuality.self)
        // Two toggles × two lanes = four sends.
        XCTAssertEqual(sends.count, 4)
    }

    func testAutomaticPicksBestInIntersectionAndFansOut() async {
        let (controller, transport, _) = await makeController(peers: [camA, camB])
        // camA does 4K; camB only 1080p → the rig can only agree on 1080p30.
        controller.didReceiveMessage(capsWith(full4K), from: camA)
        controller.didReceiveMessage(capsWith(only1080), from: camB)
        await controller.waitForIdle()
        transport.sentMessages.removeAll()

        controller.applyAutomaticVideoQuality()
        await controller.waitForIdle()

        let sends = sent(transport, RemoteCmd.SetVideoQuality.self)
        XCTAssertEqual(Set(sends.flatMap(\.peers)), [camA, camB])
        let q = sends.first?.msg as? RemoteCmd.SetVideoQuality
        XCTAssertEqual(q?.resolution, .hd1080p)
        XCTAssertEqual(q?.frameRate, .fps30)
    }

    func testLateJoinerThatCannotMatchIsFlagged() async {
        let (controller, _, _) = await makeController(peers: [camA, camB])
        controller.didReceiveMessage(capsWith(full4K), from: camA)
        controller.didReceiveMessage(capsWith(full4K), from: camB)
        await controller.waitForIdle()
        // Rig set to 4K30 (both can).
        controller.setVideoQuality(resolution: .uhd4k, frameRate: .fps30)
        await controller.waitForIdle()
        let flaggedBefore = await controller.needsRematchForTesting(camB)
        XCTAssertFalse(flaggedBefore)

        // camB device-switches to a 1080-only camera → can't match → flagged.
        controller.didReceiveMessage(capsWith(only1080), from: camB)
        await controller.waitForIdle()
        let flaggedAfter = await controller.needsRematchForTesting(camB)
        let camAstillOK = await controller.needsRematchForTesting(camA)
        XCTAssertTrue(flaggedAfter)
        XCTAssertFalse(camAstillOK)
    }

    func testRigTimerCountsDownFansOutAndFiresCapture() async {
        let (controller, transport, _) = await makeController(peers: [camA, camB])
        // Seed offsets so the fired capture takes the scheduled path.
        await controller.seedLaneForTesting(camA, supportsMulticam: true, offsetMillis: 0)
        await controller.seedLaneForTesting(camB, supportsMulticam: true, offsetMillis: 0)
        // Large interval so the production tick Task never fires during the
        // test — the ticks are driven deterministically through the inbox.
        await controller.setTimerTickInterval(1000)
        controller.setRigTimer(3)
        await controller.waitForIdle()
        transport.sentMessages.removeAll()

        controller.capturePhoto()
        await controller.waitForIdle() // arms the countdown, fans tick 3
        var remaining = await controller.countdownRemainingForTesting()
        XCTAssertEqual(remaining, 3)

        // Drive the countdown 3 → 2 → 1 → 0 (fires) through the pump.
        for _ in 0..<3 {
            await controller.advanceTimerForTesting()
            await controller.waitForIdle()
        }
        remaining = await controller.countdownRemainingForTesting()
        XCTAssertNil(remaining, "countdown finished")

        let ticks = sent(transport, RemoteCmd.TimerCountdown.self).compactMap { $0.msg as? RemoteCmd.TimerCountdown }
        XCTAssertTrue(ticks.contains { $0.value == 3 })
        XCTAssertTrue(ticks.contains { $0.value == 0 })
        XCTAssertFalse(sent(transport, RemoteCmd.ScheduledCapture.self).isEmpty,
                       "expiry fired the synced capture")
    }

    func testSetPhotoQualityFansOut() async {
        let (controller, transport, _) = await makeController(peers: [camA, camB])
        transport.sentMessages.removeAll()
        controller.setPhotoQuality(format: .heif, hdr: .on)
        await controller.waitForIdle()
        let sends = sent(transport, RemoteCmd.SetPhotoQuality.self)
        XCTAssertEqual(Set(sends.flatMap(\.peers)), [camA, camB])
        let q = sends.first?.msg as? RemoteCmd.SetPhotoQuality
        XCTAssertEqual(q?.format, .heif)
        XCTAssertEqual(q?.hdrMode, .on)
    }

    // MARK: - Auto-collect

    func testVideoResourceTransferUpdatesLaneStateAndSaves() async {
        let (controller, _, _) = await makeController(peers: [camA, camB])
        let progress = Progress(totalUnitCount: 100)

        controller.didStartReceivingResource(name: "RS_a_b_cam1.mov", from: camA, progress: progress)
        await controller.waitForIdle()
        var stateA = await controller.collectionStateForTesting(camA)
        XCTAssertEqual(stateA, .transferring(0))

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clip.mov")
        controller.didFinishReceivingResource(name: "RS_a_b_cam1.mov", from: camA, at: url, error: nil)
        await controller.waitForIdle()
        stateA = await controller.collectionStateForTesting(camA)
        XCTAssertEqual(stateA, .collected)
        // camB untouched.
        let stateB = await controller.collectionStateForTesting(camB)
        XCTAssertEqual(stateB, .idle)
    }

    func testFailedTransferMarksLaneAndRetryReRequests() async {
        let (controller, transport, _) = await makeController(peers: [camA, camB])
        controller.didFinishReceivingResource(
            name: "RS_a_b_cam1.mov", from: camA, at: nil,
            error: NSError(domain: "x", code: 1))
        await controller.waitForIdle()
        let failed = await controller.collectionStateForTesting(camA)
        XCTAssertEqual(failed, .failed)

        transport.sentMessages.removeAll()
        controller.retryCollection(for: camA)
        await controller.waitForIdle()
        // Re-request goes to that camera, and its lane returns to transferring.
        let resends = sent(transport, RemoteCmd.RequestVideoResend.self)
        XCTAssertEqual(resends.map(\.peers), [[camA]])
        let retrying = await controller.collectionStateForTesting(camA)
        XCTAssertEqual(retrying, .transferring(0))
    }

    func testReturnedPhotoMarksLaneCollected() async {
        let (controller, _, _) = await makeController(peers: [camA, camB])
        // A returned still (non-nil pic, no error) is collected on the director.
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0])
        controller.didReceiveMessage(
            RemoteCmd.TakePicResp(sender: nil, pic: jpeg, error: nil), from: camB)
        await controller.waitForIdle()
        let state = await controller.collectionStateForTesting(camB)
        XCTAssertEqual(state, .collected)
    }

    // MARK: - Fixtures

    private func multicamCaps() -> RemoteCmd.CameraCapabilitiesResp {
        RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, currentLens: .wideAngle, currentZoom: 1.0,
            supportsMulticam: true, error: nil)
    }

    /// Capabilities advertising both a front and a back camera, or only the
    /// back (`bothPositions: false`) — the flip button's enable condition.
    private func flipCaps(bothPositions: Bool) -> RemoteCmd.CameraCapabilitiesResp {
        let lens = RemoteCmd.CameraInfo(
            availableLenses: [.wideAngle], hasFlash: true, hasTorch: true,
            zoomCapabilities: [:], supportedResolutions: [.hd1080p],
            supportedFrameRates: [.fps30],
            resolutionFrameRates: [.hd1080p: [.fps30]],
            supportsHEIF: false, supportsHDR: false)
        return RemoteCmd.CameraCapabilitiesResp(
            frontCamera: bothPositions ? lens : nil, backCamera: lens,
            currentCamera: .back, currentLens: .wideAngle, currentZoom: 1.0,
            supportsMulticam: true, error: nil)
    }

    // MARK: - Camera flip (focused peer only)

    func testFlipGoesOnlyToTheFocusedCamera() async {
        let (controller, transport, _) = await makeController(peers: [camA, camB])
        controller.didReceiveMessage(flipCaps(bothPositions: true), from: camA)
        controller.didReceiveMessage(flipCaps(bothPositions: true), from: camB)
        await controller.setFocusedPeer(camA)
        await controller.waitForIdle()
        transport.sentMessages.removeAll()

        controller.toggleFocusedCamera()
        await controller.waitForIdle()

        let flips = sent(transport, RemoteCmd.ToggleCamera.self)
        XCTAssertEqual(flips.map(\.peers), [[camA]],
                       "framing is per-camera: only the focused peer flips")
    }

    func testFlipResponseUpdatesOnlyThatLane() async {
        let (controller, _, _) = await makeController(peers: [camA, camB])
        controller.didReceiveMessage(flipCaps(bothPositions: true), from: camA)
        controller.didReceiveMessage(flipCaps(bothPositions: true), from: camB)
        await controller.waitForIdle()

        // The camera flipped to a body that exposes only its back camera; its
        // refreshed capabilities ride the response.
        controller.didReceiveMessage(
            RemoteCmd.ToggleCameraResp(cameraCapabilities: flipCaps(bothPositions: false),
                                       error: nil), from: camA)
        await controller.waitForIdle()

        let lanes = await controller.lanesForTesting()
        let laneA = lanes.first { $0.peerID == camA }
        let laneB = lanes.first { $0.peerID == camB }
        XCTAssertEqual(laneA?.canFlipCamera, false, "only the responder's lane updates")
        XCTAssertEqual(laneB?.canFlipCamera, true, "the other lane is untouched")
    }

    /// The flip is ungated by advertised positions (mirroring the 1:1 monitor):
    /// a linked focused camera is always flipped, and the camera itself decides
    /// whether it does anything. It is only suppressed when no camera is linked.
    func testFlipSendsWheneverTheFocusedCameraIsLinked() async {
        let (controller, transport, _) = await makeController(peers: [camA, camB])
        controller.didReceiveMessage(flipCaps(bothPositions: false), from: camA)
        await controller.setFocusedPeer(camA)
        await controller.waitForIdle()
        transport.sentMessages.removeAll()

        controller.toggleFocusedCamera()
        await controller.waitForIdle()

        XCTAssertEqual(sent(transport, RemoteCmd.ToggleCamera.self).map(\.peers), [[camA]],
                      "a linked camera is flipped regardless of advertised positions")
    }

    func testFlipIsSuppressedWhenTheFocusedCameraIsNotLinked() async {
        let (controller, transport, _) = await makeController(peers: [camA, camB])
        await controller.setFocusedPeer(camA)
        // The focused camera drops → its lane goes .reconnecting, not .linked.
        transport.connectedPeers = [camB]
        controller.peerDidDisconnect(camA)
        await controller.waitForIdle()
        transport.sentMessages.removeAll()

        controller.toggleFocusedCamera()
        await controller.waitForIdle()

        XCTAssertTrue(sent(transport, RemoteCmd.ToggleCamera.self).isEmpty,
                      "a focused camera that is reconnecting is never flipped")
    }

    func testTorchTogglesOnlyTheFocusedLaneOptimistically() async {
        let (controller, transport, _) = await makeController(peers: [camA, camB])
        controller.didReceiveMessage(multicamCaps(), from: camA)
        controller.didReceiveMessage(multicamCaps(), from: camB)
        await controller.setFocusedPeer(camA)
        await controller.waitForIdle()
        transport.sentMessages.removeAll()

        controller.toggleTorch()
        await controller.waitForIdle()

        XCTAssertEqual(sent(transport, RemoteCmd.ToggleTorch.self).map(\.peers), [[camA]],
                       "torch drives only the focused camera")
        let lanes = await controller.lanesForTesting()
        XCTAssertEqual(lanes.first { $0.peerID == camA }?.torchOn, true,
                       "the focused lane reflects the tap immediately")
        XCTAssertEqual(lanes.first { $0.peerID == camB }?.torchOn, false,
                       "no other lane is touched")
    }

    // MARK: - Per-camera disconnect

    func testDisconnectSendsEndSessionToOnlyThatCameraAndRemovesItsLane() async {
        let (controller, transport, display) = await makeController(peers: [camA, camB])
        await controller.setFocusedPeer(camA)
        await controller.waitForIdle()
        transport.sentMessages.removeAll()

        controller.disconnectCamera(camA)
        await controller.waitForIdle()

        let goodbyes = sent(transport, RemoteCmd.EndSession.self)
        XCTAssertEqual(goodbyes.map(\.peers), [[camA]],
                       "the goodbye addresses only the disconnected camera")
        let lanes = await controller.lanesForTesting()
        XCTAssertEqual(lanes.map(\.peerID), [camB], "its lane is dropped")
        // Focus moved off the removed camera to the remaining one.
        let focused = await controller.focusedPeerForTesting()
        XCTAssertEqual(focused, camB)
        XCTAssertFalse(display.didExit, "the rig still has a camera, so it stays open")
    }

    func testDisconnectingTheLastCameraExitsTheDirector() async {
        let (controller, _, display) = await makeController(peers: [camA])
        await controller.waitForIdle()

        controller.disconnectCamera(camA)
        await controller.waitForIdle()

        let lanes = await controller.lanesForTesting()
        XCTAssertTrue(lanes.isEmpty)
        XCTAssertTrue(display.didExit, "disconnecting the last camera leaves the director")
    }

    private func sendFrame() -> RemoteCmd.SendFrame {
        RemoteCmd.SendFrame(data: Data([1, 2, 3]), sender: nil,
                            fps: 30, camPosition: .back, camOrientation: .portrait,
                            codec: .vp9, sequenceNumber: 1)
    }
}
