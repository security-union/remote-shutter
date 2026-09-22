//
//  RemoteCamSessionTests.swift
//  RemoteShutterTests
//
//  State-machine tests for SessionCoordinator — every behavioral assertion
//  carried over from the Theater-era RemoteCamSession tests, now driving the
//  enum machine through its real transitions (BecomeCamera and friends)
//  instead of seeding closure states.
//

// swiftlint:disable file_length type_body_length

import XCTest
import MPCCompat
import Stormo

@testable import RemoteShutter

class SessionCoordinatorTests: XCTestCase {

    private var harness: CoordinatorHarness!
    private var camera: FakeCameraControlling!

    override func setUp() async throws {
        try await super.setUp()
        harness = await makeCoordinatorHarness()
        camera = FakeCameraControlling()
    }

    override func tearDown() async throws {
        harness.coordinator.stop()
        harness = nil
        camera = nil
        try await super.tearDown()
    }

    // MARK: - Seeding helpers (real transitions, like production)

    private func seedConnected() async {
        await harness.coordinator.seed(state: .connected, lobby: harness.lobbyWrapper, peer: harness.peer)
    }

    private func enterCamera() async {
        await seedConnected()
        await harness.deliver(UICmd.BecomeCamera(sender: nil, ctrl: camera))
        harness.fakeMP.sentMessages.removeAll()
    }

    private func sent<T>(_ type: T.Type) -> [(msg: Message, peers: [MCPeerID], mode: MCSessionSendDataMode)] {
        harness.fakeMP.sentMessages.filter { $0.msg is T }
    }

    // MARK: - Initial state

    func testInitialStateIsIdleFloor() async {
        // (Was "waitingForCtrl" — both floor states map to .idle in the enum machine.)
        let name = await harness.stateName()
        XCTAssertEqual(name, .idle)
    }

    // MARK: - Scanning state: connect retry

    private func seedScanning() async {
        await harness.coordinator.seed(state: .scanning, lobby: harness.lobbyWrapper)
    }

    // MARK: - Multicam "Connect (N)": invite the selected set, retry, report

    /// The device-test regression, guarded at the transport: selecting rows
    /// (pure VM toggles, the production tap path) must invite nothing.
    func testSelectingRowsSendsZeroInvites() async {
        await seedScanning()
        await harness.deliver(UICmd.SetMulticamCollecting(on: true))
        let vm = harness.lobby.scannerViewModel
        let peers = (0..<5).map { MCPeerID(displayName: "Cam\($0)") }
        peers.forEach { vm.addPeer($0) }
        peers.forEach { vm.toggleMulticamSelection($0) } // taps = pure selection

        await harness.coordinator.waitForIdle()
        XCTAssertTrue(harness.fakeMP.invitedPeers.isEmpty,
                      "selecting must never invite — the device-test regression")
    }

    /// Re-arming collecting (the scanner reappeared after back-navigation)
    /// reports the coordinator's current live set so the scanner can resync,
    /// and clears the previous cycle's per-peer bookkeeping without inviting.
    func testReArmingCollectingReportsLiveLinksAndClearsCycle() async {
        await seedScanning()
        await harness.deliver(UICmd.SetMulticamCollecting(on: true))
        // A camera from the first cycle is still connected at the transport.
        let camA = MCPeerID(displayName: "CamA")
        harness.fakeMP.connectedPeers = [camA]
        harness.lobby.rearmReports.removeAll()
        harness.fakeMP.invitedPeers.removeAll()

        // The scanner reappears → re-arm.
        await harness.deliver(UICmd.SetMulticamCollecting(on: true))

        XCTAssertEqual(harness.lobby.rearmReports.last, [camA],
                       "re-arm reports the live set so the scanner resyncs")
        XCTAssertTrue(harness.fakeMP.invitedPeers.isEmpty,
                      "re-arming never invites a live peer")
        let count = await harness.coordinator.multicamConnectedCount()
        XCTAssertEqual(count, 1, "collecting is armed and sees the live camera")
    }

    /// The handoff seam serves whatever `MulticamHandoff.decide` asked for —
    /// including a single camera: one collected
    /// camera detaches to the director. Pins the stranded-scanner bug where a
    /// two-camera floor here silently returned nil while the camera went live.
    func testDetachTransportHandsOffASingleCollectedCamera() async {
        await seedScanning()
        await harness.deliver(UICmd.SetMulticamCollecting(on: true))
        let camA = MCPeerID(displayName: "CamA")
        harness.fakeMP.connectedPeers = [camA]

        let handoff = await harness.coordinator.detachTransportForMulticam()
        XCTAssertEqual(handoff?.peers, [camA])
        let stillCollecting = await harness.coordinator.multicamCollectingForTesting()
        XCTAssertFalse(stillCollecting, "detach hands the session over and ends collecting")
    }

    /// An empty rig has nothing to hand off.
    func testDetachTransportRefusesAnEmptyRig() async {
        await seedScanning()
        await harness.deliver(UICmd.SetMulticamCollecting(on: true))
        harness.fakeMP.connectedPeers = []
        let handoff = await harness.coordinator.detachTransportForMulticam()
        XCTAssertNil(handoff)
    }

    func testMulticamConnectInvitesEachSelectedPeer() async {
        await seedScanning()
        await harness.deliver(UICmd.SetMulticamCollecting(on: true))
        harness.fakeMP.connectedPeers = []
        let camA = MCPeerID(displayName: "CamA")
        let camB = MCPeerID(displayName: "CamB")

        // "Connect" fires one invite per selected camera — no `link` clobbering.
        await harness.deliver(ConnectToDevice(peer: camA, sender: nil))
        await harness.deliver(ConnectToDevice(peer: camB, sender: nil))
        XCTAssertEqual(Set(harness.fakeMP.invitedPeers.map(\.peer)), [camA, camB])

        // As each connects, the coordinator reports the growing connected set.
        harness.fakeMP.connectedPeers = [camA]
        await harness.deliver(OnConnectToDevice(peer: camA, sender: nil))
        harness.fakeMP.connectedPeers = [camA, camB]
        await harness.deliver(OnConnectToDevice(peer: camB, sender: nil))
        let count = await harness.coordinator.multicamConnectedCount()
        XCTAssertEqual(count, 2)
    }

    func testMulticamInviteRetriesOnceThenReportsFailure() async {
        await seedScanning()
        await harness.deliver(UICmd.SetMulticamCollecting(on: true))
        harness.fakeMP.connectedPeers = []
        let camA = MCPeerID(displayName: "CamA")

        await harness.deliver(ConnectToDevice(peer: camA, sender: nil))
        XCTAssertEqual(harness.fakeMP.invitedPeers.count, 1)

        // First drop → retry (a second invite), no failure yet.
        await harness.deliver(DisconnectPeer(peer: camA, sender: nil))
        XCTAssertEqual(harness.fakeMP.invitedPeers.count, 2)
        XCTAssertTrue(harness.lobby.failedPeers.isEmpty)

        // Second drop → reported failed, no third invite.
        await harness.deliver(DisconnectPeer(peer: camA, sender: nil))
        XCTAssertEqual(harness.fakeMP.invitedPeers.count, 2, "no third invite")
        XCTAssertEqual(harness.lobby.failedPeers, [camA])
    }

    func testConnectInvitesWithLongTimeout() async {
        await seedScanning()
        await harness.deliver(ConnectToDevice(peer: harness.peer, sender: nil))

        XCTAssertEqual(harness.fakeMP.invitedPeers.count, 1)
        XCTAssertEqual(harness.fakeMP.invitedPeers[0].peer, harness.peer)
        XCTAssertEqual(harness.fakeMP.invitedPeers[0].timeout, 20)
        XCTAssertTrue(harness.lobby.scannerViewModel.isConnecting)
    }

    func testFailedInviteRetriesOnceThenSurfacesError() async {
        await seedScanning()
        await harness.deliver(ConnectToDevice(peer: harness.peer, sender: nil))

        // First failure: silent automatic retry, overlay stays up.
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))
        XCTAssertEqual(harness.fakeMP.invitedPeers.count, 2)
        XCTAssertTrue(harness.lobby.scannerViewModel.isConnecting)
        XCTAssertFalse(harness.lobby.scannerViewModel.hasConnectionError)

        // Second failure: give up, tell the user.
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))
        XCTAssertEqual(harness.fakeMP.invitedPeers.count, 2)
        XCTAssertFalse(harness.lobby.scannerViewModel.isConnecting)
        XCTAssertTrue(harness.lobby.scannerViewModel.hasConnectionError)
    }

    func testSuccessfulConnectClearsPendingSoLaterDropDoesNotReinvite() async {
        await seedScanning()
        await harness.deliver(ConnectToDevice(peer: harness.peer, sender: nil))
        await harness.deliver(OnConnectToDevice(peer: harness.peer, sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .connected)

        // The eventual real disconnect must not trigger a stale retry invite.
        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))
        XCTAssertEqual(harness.fakeMP.invitedPeers.count, 1)
    }

    func testCancelConnectTearsDownAndIgnoresLateFailure() async {
        await seedScanning()
        await harness.deliver(ConnectToDevice(peer: harness.peer, sender: nil))
        await harness.deliver(UICmd.CancelConnect(sender: nil))

        XCTAssertTrue(harness.fakeMP.disconnectCalled)
        XCTAssertFalse(harness.lobby.scannerViewModel.isConnecting)

        // The aborted invite's .notConnected must not re-invite or show an error.
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))
        XCTAssertEqual(harness.fakeMP.invitedPeers.count, 1)
        XCTAssertFalse(harness.lobby.scannerViewModel.hasConnectionError)
    }

    // MARK: - Connected state

    func testConnectedStateDisconnect() async {
        await seedConnected()
        await harness.deliver(UICmd.ScannerDidAppear())

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
        // The exit is announced so the peer stops reconnecting — and that is
        // the ONLY thing a deliberate disconnect puts on the wire.
        XCTAssertEqual(harness.fakeMP.sentMessages.count, 1)
        XCTAssertTrue(harness.fakeMP.sentMessages.first?.msg is RemoteCmd.EndSession)
    }

    func testConnectedStateNilLobbyPopsToScanning() async {
        let deadLobby = FakeScannerLobby()
        var wrapper: WeakScannerLobby? = WeakScannerLobby(deadLobby)
        await harness.coordinator.seed(state: .connected, lobby: wrapper, peer: harness.peer)
        wrapper?.value = nil
        wrapper = nil

        await harness.deliver(UICmd.ScannerDidAppear())

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    func testConnectedStateDisconnectPeerStartsReconnecting() async {
        await seedConnected()

        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .reconnecting, "a lost peer starts the wait")
    }

    // MARK: - Clock sync, camera side

    /// A camera answers a clock-sync ping immediately, from any state, with
    /// the pong addressed to the pinging peer — off the actor inbox so the
    /// timestamp isn't smeared by queued state-machine work.
    func testClockSyncPingIsAnsweredDirectlyToTheSource() async {
        harness.coordinator.didReceiveMessage(
            RemoteCmd.ClockSyncPing(t0Millis: 424_242), from: harness.peer)

        let pongs = sent(RemoteCmd.ClockSyncPong.self)
        XCTAssertEqual(pongs.count, 1)
        XCTAssertEqual(pongs[0].peers, [harness.peer])
        XCTAssertEqual((pongs[0].msg as? RemoteCmd.ClockSyncPong)?.echoT0Millis, 424_242)
        XCTAssertGreaterThan(
            (pongs[0].msg as? RemoteCmd.ClockSyncPong)?.cameraClockMillis ?? 0, 0)
    }

    // MARK: - Scheduled (multicam) capture, camera side

    func testScheduledCaptureInThePastNacks() async {
        await enterCamera()
        harness.fakeMP.sendResult = true

        await harness.deliver(RemoteCmd.ScheduledCapture(
            fireAtCameraClockMillis: 1, // long past
            anchorMillis: 1, captureId: "CAP-1", sessionId: "S", cameraIndex: 1))

        let acks = sent(RemoteCmd.ScheduledCaptureAck.self)
            .compactMap { $0.msg as? RemoteCmd.ScheduledCaptureAck }
        XCTAssertEqual(acks.count, 1)
        XCTAssertEqual(acks[0].captureId, "CAP-1")
        XCTAssertNotNil(acks[0].error, "a fire time in the past is refused")
        XCTAssertTrue(camera.takePictureCalls.isEmpty, "no shutter on a nack")
    }

    func testValidScheduledCaptureAcksImmediatelyAndFires() async {
        await enterCamera()
        harness.fakeMP.sendResult = true

        // Fire ~now: acked immediately, then the shutter pulls a moment later.
        await harness.deliver(RemoteCmd.ScheduledCapture(
            fireAtCameraClockMillis: SyncClock.nowMillis(),
            anchorMillis: SyncClock.nowMillis(), captureId: "CAP-2",
            sessionId: "S", cameraIndex: 2))

        let acks = sent(RemoteCmd.ScheduledCaptureAck.self)
            .compactMap { $0.msg as? RemoteCmd.ScheduledCaptureAck }
        XCTAssertEqual(acks.map(\.captureId), ["CAP-2"])
        XCTAssertNil(acks[0].error, "accepted")

        // The fire is enqueued by an off-actor delay task; wait for it.
        for _ in 0..<200 where camera.takePictureCalls.isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(camera.takePictureCalls, [true],
                       "the scheduled shutter fires, saving locally AND returning the still to the director")
    }

    // MARK: - Recording truth derivation (v10)

    private var reportSeq: UInt64 = 0

    private func stateReport(elapsed: UInt64?) -> RemoteCmd.CameraStateReport {
        reportSeq += 1
        return RemoteCmd.CameraStateReport(
            seq: reportSeq,
            state: elapsed.map { .recording(elapsedMillis: $0) } ?? .idle)
    }

    /// Pumps the main queue until `condition` holds.
    private func pumpMain(_ condition: @escaping () -> Bool) async {
        for _ in 0..<50 {
            let done = await MainActor.run { () -> Bool in
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
                return condition()
            }
            if done { return }
        }
    }

    /// The pipeline terminated a recording on its own (storage gate refusal,
    /// writer death): the error is reported through the stop-response path
    /// the monitor already handles, and the camera returns to idle.
    func testRecordingTerminatedReportsErrorAndReturnsToCamera() async {
        await enterCamera()
        harness.fakeMP.sendResult = true
        await harness.deliver(RemoteCmd.StartRecordingVideo(sender: nil))
        var name = await harness.stateName()
        XCTAssertEqual(name, .cameraRecordingVideo)
        harness.fakeMP.sentMessages.removeAll()

        await harness.deliver(UICmd.RecordingTerminated(
            error: NSError(domain: "Not enough storage", code: 0)))

        let resps = sent(RemoteCmd.StopRecordingVideoResp.self)
            .compactMap { $0.msg as? RemoteCmd.StopRecordingVideoResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertNotNil(resps.first?.error, "the monitor must learn WHY, not get a clean stop")
        name = await harness.stateName()
        XCTAssertEqual(name, .camera)
    }

    /// Writer death during the transmit phase (finalize failed under a
    /// remote-initiated stop): same truth-routing, then back to camera via
    /// the deferred pop.
    func testRecordingTerminatedDuringTransmitReportsError() async {
        await enterCamera()
        harness.fakeMP.sendResult = true
        await harness.deliver(RemoteCmd.StartRecordingVideo(sender: nil))
        await harness.deliver(RemoteCmd.StopRecordingVideo(sender: nil, sendMediaToPeer: false))
        var name = await harness.stateName()
        XCTAssertEqual(name, .cameraTransmittingVideo)
        harness.fakeMP.sentMessages.removeAll()

        await harness.deliver(UICmd.RecordingTerminated(
            error: NSError(domain: "disk full", code: 0)))
        await harness.coordinator.waitForIdle()

        let resps = sent(RemoteCmd.StopRecordingVideoResp.self)
            .compactMap { $0.msg as? RemoteCmd.StopRecordingVideoResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertNotNil(resps.first?.error)
        name = await harness.stateName()
        XCTAssertEqual(name, .camera)
    }

    // MARK: - Keep rolling through a drop (uniform: solo and multicam)

    /// Drives the machine into `.cameraRecordingVideo` and drops the peer.
    private func dropPeerMidRecording() async {
        await enterCamera()
        harness.fakeMP.sendResult = true
        harness.lobby.role = .camera

        await harness.deliver(RemoteCmd.StartRecordingVideo(sender: nil))
        let name = await harness.stateName()
        XCTAssertEqual(name, .cameraRecordingVideo)

        harness.fakeMP.discoveryStarts = 0
        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))
    }

    /// A link drop is not an input to the recording state machine: the camera
    /// keeps rolling IN PLACE — no stop, no `.reconnecting` (which would pop
    /// the screen and starve the writer) — and re-arms its advertiser so the
    /// remote can rejoin.
    func testDisconnectMidRecordingKeepsRollingInPlace() async {
        await dropPeerMidRecording()

        XCTAssertTrue(camera.stopRecordingCalls.isEmpty,
                      "the clip keeps rolling through the drop")
        let name = await harness.stateName()
        XCTAssertEqual(name, .cameraRecordingVideo)
        XCTAssertEqual(harness.lobby.returnsToLobby, 0,
                       "the camera screen must NOT pop mid-take")
        XCTAssertEqual(harness.fakeMP.discoveryStarts, 1,
                       "advertising re-arms so the remote can rejoin")
        await MainActor.run {
            XCTAssertTrue(camera.cameraViewModel.isAwaitingRemoteReconnect,
                          "the reconnect chip + on-camera stop appear")
        }
    }

    /// The rejoin re-binds in place: same state, role re-announced, and the
    /// capabilities request answered from the recording state — carrying the
    /// live recording truth the remote derives from.
    func testRecordingCameraRebindsOnReconnect() async {
        await dropPeerMidRecording()

        harness.fakeMP.connectedPeers = [harness.peer]
        harness.fakeMP.sentMessages.removeAll()
        await harness.deliver(OnConnectToDevice(peer: harness.peer, sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .cameraRecordingVideo, "no role re-entry, no rig rebuild")
        XCTAssertEqual(sent(RemoteCmd.PeerBecameCamera.self).count, 1)
        await MainActor.run {
            XCTAssertFalse(camera.cameraViewModel.isAwaitingRemoteReconnect)
        }

        // The handshake follow-up is answered with capabilities PLUS a fresh
        // state report — the report is the recording-truth carrier.
        camera.reportedRecordingStartedAt = Date(timeIntervalSinceNow: -30)
        harness.fakeMP.sentMessages.removeAll()
        await harness.deliver(RemoteCmd.RequestCameraCapabilities())
        XCTAssertEqual(sent(RemoteCmd.CameraCapabilitiesResp.self).count, 1)
        let reports = sent(RemoteCmd.CameraStateReport.self)
            .compactMap { $0.msg as? RemoteCmd.CameraStateReport }
        guard case .recording = reports.last?.state else {
            return XCTFail("the state report must carry the live recording truth, got \(String(describing: reports.last?.state))")
        }
    }

    /// The on-camera stop finalizes + saves locally and returns to the idle
    /// camera — still advertising, never the scanner.
    func testStopRecordingLocallyFinalizesAndReturnsToCamera() async {
        await dropPeerMidRecording()

        await harness.deliver(UICmd.StopRecordingLocally())

        XCTAssertEqual(camera.stopRecordingCalls, [false],
                       "finalize + save locally, nothing sent to a dead link")
        var name = await harness.stateName()
        XCTAssertEqual(name, .cameraRecordingVideo,
                       "the recording is a fact until the writer reports the stop")

        // The pipeline reports the finalized stop; the machine settles.
        await harness.deliver(RemoteCmd.StopRecordingVideoResp())
        name = await harness.stateName()
        XCTAssertEqual(name, .camera)
        XCTAssertEqual(harness.lobby.returnsToLobby, 0)
    }

    /// The remote is an observer of camera state: a LINKED on-camera stop
    /// pushes a fresh cam-state report the moment the camera lands on idle —
    /// the remote's derivation does the rest, no imperative notification.
    func testStopRecordingLocallyWhileLinkedPushesState() async {
        await enterCamera()
        harness.fakeMP.sendResult = true
        await harness.deliver(RemoteCmd.StartRecordingVideo(sender: nil))
        harness.fakeMP.sentMessages.removeAll()

        await harness.deliver(UICmd.StopRecordingLocally())
        await harness.deliver(RemoteCmd.StopRecordingVideoResp())

        XCTAssertEqual(camera.stopRecordingCalls, [false])
        let name = await harness.stateName()
        XCTAssertEqual(name, .camera)
        let reports = sent(RemoteCmd.CameraStateReport.self)
            .compactMap { $0.msg as? RemoteCmd.CameraStateReport }
        XCTAssertEqual(reports.count, 1,
                       "arriving at idle reports the new truth to the remote")
        XCTAssertEqual(reports[0].state, .idle)
    }

    /// A backgrounding blip while unlinked must not pop a rolling take to the
    /// scanner: the foreground re-arm holds the recording state and re-arms
    /// advertising instead.
    func testForegroundRearmHoldsRecordingState() async {
        await dropPeerMidRecording()

        harness.fakeMP.discoveryStarts = 0
        await harness.deliver(UICmd.AppForegrounded())

        let name = await harness.stateName()
        XCTAssertEqual(name, .cameraRecordingVideo)
        XCTAssertTrue(camera.stopRecordingCalls.isEmpty)
        XCTAssertEqual(harness.fakeMP.discoveryStarts, 1)
    }

    /// The unified policy, idle case: an IDLE camera also holds its post on a
    /// drop — no `.reconnecting`, no screen pop, no rig teardown/rebuild —
    /// with the chip up and advertising re-armed.
    func testIdleCameraDisconnectHoldsInPlace() async {
        await enterCamera()
        harness.lobby.role = .camera
        harness.fakeMP.discoveryStarts = 0
        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .camera, "the idle camera holds — .reconnecting is monitor-only")
        XCTAssertEqual(harness.lobby.returnsToLobby, 0)
        XCTAssertEqual(harness.fakeMP.discoveryStarts, 1)
        await MainActor.run {
            XCTAssertTrue(camera.cameraViewModel.isAwaitingRemoteReconnect)
        }
    }

    /// And the idle rejoin: re-bind in place, role re-announced, chip cleared.
    func testIdleCameraRebindsOnReconnect() async {
        await enterCamera()
        harness.lobby.role = .camera
        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))

        harness.fakeMP.connectedPeers = [harness.peer]
        harness.fakeMP.sendResult = true
        harness.fakeMP.sentMessages.removeAll()
        await harness.deliver(OnConnectToDevice(peer: harness.peer, sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .camera)
        XCTAssertEqual(sent(RemoteCmd.PeerBecameCamera.self).count, 1)
        await MainActor.run {
            XCTAssertFalse(camera.cameraViewModel.isAwaitingRemoteReconnect)
        }
    }

    /// Drop mid-capture: the in-flight photo completes and SAVES locally, the
    /// unsendable responses are dropped by the role-split send policy, and the
    /// machine settles to the idle camera — never the scanner.
    func testTakingPicDisconnectSavesLocallyAndSettles() async {
        var savedPics = 0
        await harness.coordinator.setPhotoLibrarySaver { _ in savedPics += 1 }
        await enterCamera()
        harness.lobby.role = .camera
        harness.fakeMP.sendResult = true
        await harness.deliver(RemoteCmd.TakePic(sender: nil, sendMediaToPeer: true))
        var name = await harness.stateName()
        XCTAssertEqual(name, .cameraTakingPic)

        harness.fakeMP.connectedPeers = []
        harness.fakeMP.sendResult = false
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))
        name = await harness.stateName()
        XCTAssertEqual(name, .cameraTakingPic, "the capture is still in flight")

        await harness.deliver(UICmd.OnPicture(sender: nil, pic: Data([0xFF])))
        XCTAssertEqual(savedPics, 1, "the still is saved locally regardless of the link")
        name = await harness.stateName()
        XCTAssertEqual(name, .camera, "settles to idle, never the scanner")
    }

    /// Drop mid-transfer: the clip is already saved locally, so the camera
    /// holds its post and settles to idle; the director re-collects on rejoin.
    func testTransmittingDisconnectSettlesToIdleCamera() async {
        await enterCamera()
        harness.lobby.role = .camera
        harness.fakeMP.sendResult = true
        await harness.deliver(RemoteCmd.StartRecordingVideo(sender: nil))
        await harness.deliver(RemoteCmd.StopRecordingVideo(sender: nil, sendMediaToPeer: true))
        var name = await harness.stateName()
        XCTAssertEqual(name, .cameraTransmittingVideo)

        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))
        await harness.coordinator.waitForIdle()

        name = await harness.stateName()
        XCTAssertEqual(name, .camera)
        XCTAssertEqual(harness.lobby.returnsToLobby, 0)
        await MainActor.run {
            XCTAssertTrue(camera.cameraViewModel.isAwaitingRemoteReconnect)
        }
    }

    /// A capture interruption (lock, phone call, camera stolen) finalizes at
    /// the CAPTURE layer (rig + pipeline); what the coordinator sees is the
    /// pipeline's stop response — the machine settles to idle and entering
    /// `.camera` reports the new truth to the remote.
    func testPipelineSelfStopSettlesToIdleAndReportsIdle() async {
        await enterCamera()
        harness.fakeMP.sendResult = true
        await harness.deliver(RemoteCmd.StartRecordingVideo(sender: nil))
        harness.fakeMP.sentMessages.removeAll()

        // The pipeline clears its truth BEFORE emitting the stop response
        // (resetRecordingState precedes the sendMessage) — model that order.
        camera.reportedRecordingStartedAt = nil
        await harness.deliver(RemoteCmd.StopRecordingVideoResp())

        let name = await harness.stateName()
        XCTAssertEqual(name, .camera, "wakes up truthfully idle")
        let reports = sent(RemoteCmd.CameraStateReport.self)
            .compactMap { $0.msg as? RemoteCmd.CameraStateReport }
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports[0].state, .idle, "the report says idle")
    }

    /// The wake is the authority, not the transport's membership list: even
    /// when `connectedPeers` STILL lists the dead peer at wake (its death
    /// notice queued behind the wake), the camera re-arms its advertiser —
    /// trusting the stale list left the camera invisible to a searching
    /// remote.
    func testForegroundRearmsAdvertisingDespiteStalePeerList() async {
        await enterCamera()
        harness.lobby.role = .camera
        // The list still claims the peer is connected — stale.
        harness.fakeMP.connectedPeers = [harness.peer]
        harness.fakeMP.discoveryStarts = 0

        await harness.deliver(UICmd.AppForegrounded())

        let name = await harness.stateName()
        XCTAssertEqual(name, .camera)
        XCTAssertEqual(harness.fakeMP.discoveryStarts, 1,
                       "advertising re-arms regardless of the stale list")
        await MainActor.run {
            XCTAssertFalse(camera.cameraViewModel.isAwaitingRemoteReconnect,
                           "no disconnected chrome until the drop actually lands")
        }
    }

    /// A deliberate goodbye is intent, not a drop: `EndSession` mid-recording
    /// finalizes + saves, then leaves like any deliberate end.
    func testEndSessionMidRecordingStopsAndLeaves() async {
        await enterCamera()
        harness.fakeMP.sendResult = true
        await harness.deliver(RemoteCmd.StartRecordingVideo(sender: nil))

        await harness.deliver(RemoteCmd.EndSession())

        XCTAssertEqual(camera.stopRecordingCalls, [false],
                       "intent stops the clip — only unintended drops keep rolling")
        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    /// A scheduled start latches the session and stamps the recording with sync
    /// metadata; a scheduled stop later fires the stop.
    func testScheduledRecordingStampsMetadataAndFires() async {
        await enterCamera()
        harness.fakeMP.sendResult = true

        await harness.deliver(RemoteCmd.ScheduledStartRecording(
            fireAtCameraClockMillis: SyncClock.nowMillis(),
            anchorMillis: 42, captureId: "R7", sessionId: "S3", cameraIndex: 4))

        let acks = sent(RemoteCmd.ScheduledRecordingAck.self)
            .compactMap { $0.msg as? RemoteCmd.ScheduledRecordingAck }
        XCTAssertEqual(acks.map(\.captureId), ["R7"])
        XCTAssertFalse(acks[0].isStop)

        for _ in 0..<200 where camera.startRecordingCalls == 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        // The recording carries its sync metadata (anchor as opaque key).
        XCTAssertEqual(camera.videoSyncMetadata?.captureID, "R7")
        XCTAssertEqual(camera.videoSyncMetadata?.cameraIndex, 4)
        XCTAssertEqual(camera.videoSyncMetadata?.anchorMillis, 42)

        // A scheduled stop fires the stop.
        await harness.deliver(RemoteCmd.ScheduledStopRecording(
            fireAtCameraClockMillis: SyncClock.nowMillis(),
            anchorMillis: 42, captureId: "R7", sessionId: "S3", cameraIndex: 4))
        for _ in 0..<200 where camera.stopRecordingCalls.isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(camera.stopRecordingCalls, [true],
                       "scheduled stop saves locally AND pushes the clip to the director")
    }

    /// The director's "Send Media to Remote" setting rides the scheduled stop:
    /// off means the clip is saved on the camera and NOT pushed — no duplicate
    /// on the phone acting as the remote.
    func testScheduledStopWithSendMediaOffKeepsTheClipOnTheCamera() async {
        await enterCamera()
        harness.fakeMP.sendResult = true
        await harness.deliver(RemoteCmd.ScheduledStartRecording(
            fireAtCameraClockMillis: SyncClock.nowMillis(),
            anchorMillis: 42, captureId: "R8", sessionId: "S3", cameraIndex: 1))
        for _ in 0..<200 where camera.startRecordingCalls == 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        await harness.deliver(RemoteCmd.ScheduledStopRecording(
            fireAtCameraClockMillis: SyncClock.nowMillis(),
            anchorMillis: 42, captureId: "R8", sessionId: "S3", cameraIndex: 1,
            sendMediaToPeer: false))
        for _ in 0..<200 where camera.stopRecordingCalls.isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(camera.stopRecordingCalls, [false],
                       "setting off: the clip is saved locally and stays here")
    }

    /// Same setting on the scheduled photo: the still is saved locally and not
    /// returned to the director.
    func testScheduledCaptureWithSendMediaOffKeepsTheStillOnTheCamera() async {
        await enterCamera()
        harness.fakeMP.sendResult = true
        await harness.deliver(RemoteCmd.ScheduledCapture(
            fireAtCameraClockMillis: SyncClock.nowMillis(),
            anchorMillis: SyncClock.nowMillis(), captureId: "CAP-3",
            sessionId: "S", cameraIndex: 1, sendMediaToPeer: false))
        for _ in 0..<200 where camera.takePictureCalls.isEmpty {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(camera.takePictureCalls, [false],
                       "setting off: the shutter fires without returning the still")
    }

    // MARK: - Camera taking pic: timeout with send failure

    func testCameraTakingPicTimeoutSendFailurePopsToScanning() async {
        await enterCamera()
        await harness.deliver(RemoteCmd.TakePic(sender: nil, sendMediaToPeer: true))
        var name = await harness.stateName()
        XCTAssertEqual(name, .cameraTakingPic)

        harness.fakeMP.sendResult = false
        let generation = await harness.coordinator.currentTimeoutGeneration()
        await harness.deliver(UICmd.StateTimeout(stateName: .cameraTakingPic, generation: generation))

        name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    // MARK: - Camera family: failed sends and stale timeouts

    /// A send that fails is a link that is gone: the camera answers a command,
    /// the answer cannot leave, and the session pops to scanning.
    func testCameraSendFailurePopsToScanning() async {
        await enterCamera()
        harness.fakeMP.sendResult = false
        await harness.deliver(RemoteCmd.ToggleFlash())
        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    /// A peer disconnect leaves stragglers in flight, and every one of them
    /// fails to send. Discovery must restart exactly once — not once per
    /// failed straggler (re-entering scanning per failure reset the lobby UI
    /// and re-armed the connection-error alert).
    func testFailedSendStormRestartsScanningOnce() async {
        await enterCamera()
        harness.fakeMP.sendResult = false
        for _ in 0..<5 {
            await harness.deliver(RemoteCmd.ToggleFlash())
        }
        let state = await harness.stateName()
        XCTAssertEqual(state, .scanning)
        XCTAssertEqual(harness.lobby.returnsToLobby, 1,
                       "straggler failures after the pop must not restart discovery again")
    }

    /// Timeouts are generation-counted: one armed for an earlier transient
    /// state cannot pop the state that replaced it.
    func testStaleGenerationTimeoutIsIgnored() async {
        await enterCamera()
        await harness.deliver(RemoteCmd.TakePic(sender: nil, sendMediaToPeer: true))
        let generation = await harness.coordinator.currentTimeoutGeneration()
        await harness.deliver(UICmd.StateTimeout(stateName: .cameraTakingPic, generation: generation - 1))
        let name = await harness.stateName()
        XCTAssertEqual(name, .cameraTakingPic, "a stale timeout is ignored")
    }

    // MARK: - Watch Remote crash guard (nil multipeerService)

    /// In Watch Remote mode no multipeer session ever exists. Commands that fall
    /// through to the root receive must not crash on the nil service, must not
    /// pop to scanning, and must not surface a "Connection error" alert.
    func testRootReceiveCommandsWithNilMultipeerServiceDoNotCrash() async {
        // Fresh coordinator with NO transport at all.
        let coordinator = SessionCoordinator()
        let alerts = FakeAlertPresenter()
        await coordinator.setAlertPresenter(alerts)

        coordinator.tell(RemoteCmd.TakePic(sender: nil, sendMediaToPeer: false))
        coordinator.tell(RemoteCmd.TakePic(sender: nil, sendMediaToPeer: false))
        coordinator.tell(RemoteCmd.SetZoom(zoomFactor: 2.0))
        coordinator.tell(RemoteCmd.StartRecordingVideo(sender: nil))
        coordinator.tell(RemoteCmd.StopRecordingVideo(sender: nil))
        coordinator.tell(RemoteCmd.ToggleFlash())
        await coordinator.waitForIdle()

        // (Was `nil` for an empty Theater stack — the enum floor maps to .idle.)
        let name = await coordinator.currentStateName()
        XCTAssertEqual(name, .idle, "root state must be untouched")
        XCTAssertTrue(alerts.shownErrors.isEmpty,
                      "nil multipeer service must not surface a connection error")
        coordinator.stop()
    }

    func testRootReceiveCommandsWithNilMultipeerServiceKeepPushedState() async {
        let coordinator = SessionCoordinator()
        let alerts = FakeAlertPresenter()
        let pusher = RecordingWatchPusher()
        await coordinator.setAlertPresenter(alerts)
        await coordinator.setWatchStatePusher(pusher)
        await coordinator.seed(state: .watchCamera, ctrl: FakeCameraControlling())

        // Commands the watch state doesn't handle fall to root; with no
        // transport they must be dropped without popping the watch state.
        coordinator.tell(RemoteCmd.TakePicResp(sender: nil, pic: nil, error: nil))
        await coordinator.waitForIdle()

        let name = await coordinator.currentStateName()
        XCTAssertEqual(name, .watchRemoteCamera)
        XCTAssertTrue(alerts.shownErrors.isEmpty)
        coordinator.stop()
    }

    // MARK: - Keyframe requests across camera states

    /// The preview keeps streaming while a picture is taken, so the monitor can
    /// desync there. The request used to fall through to handleRoot's unhandled
    /// default and vanish.
    func testKeyframeRequestHonoredWhileTakingPicture() async {
        let sender = FrameSender()
        harness.coordinator.setFrameSender(sender)
        sender.drain()
        _ = sender.takeKeyframeRequest()  // clear anything the seed armed

        await harness.coordinator.seed(state: .cameraTakingPic(sendMediaToPeer: true, generation: 0),
                                       lobby: harness.lobbyWrapper,
                                       peer: harness.peer,
                                       ctrl: FakeCameraControlling())
        await harness.deliver(RemoteCmd.RequestKeyframe(sender: nil))

        XCTAssertTrue(sender.takeKeyframeRequest(),
                      "a keyframe request must not be dropped while taking a picture")
    }

    /// A video file transfer saturates the link while the preview keeps flowing,
    /// making this the likeliest place to desync — and the one place the request
    /// was silently discarded.
    func testKeyframeRequestHonoredWhileTransmittingVideo() async {
        let sender = FrameSender()
        harness.coordinator.setFrameSender(sender)
        sender.drain()
        _ = sender.takeKeyframeRequest()

        await harness.coordinator.seed(state: .cameraTransmittingVideo,
                                       lobby: harness.lobbyWrapper,
                                       peer: harness.peer,
                                       ctrl: FakeCameraControlling())
        await harness.deliver(RemoteCmd.RequestKeyframe(sender: nil))

        XCTAssertTrue(sender.takeKeyframeRequest(),
                      "a keyframe request must not be dropped while transmitting video")
    }

    /// The engine reverts a switch whose graph cannot start; frames then flow
    /// from the restored device and the confirm passes. The response must
    /// still report failure — landing back on the pre-toggle device is an
    /// error, not a no-op success.
    func testRevertedToggleAnswersWithAnError() async {
        let ctrl = FakeCameraControlling()
        ctrl.toggleSticks = false
        await harness.coordinator.seed(state: .camera, lobby: harness.lobbyWrapper,
                                       peer: harness.peer, ctrl: ctrl)
        await harness.deliver(RemoteCmd.ToggleCamera())

        let resp = harness.fakeMP.sentMessages.compactMap { $0.msg as? RemoteCmd.CameraCapabilitiesResp }.last
        XCTAssertEqual(resp?.inReplyTo, .togglecamera, "the toggle must be answered")
        XCTAssertNotNil(resp?.error, "a reverted switch must not read as success")
    }

    /// The healthy path is untouched: a toggle that sticks answers with the
    /// refreshed capabilities and no error.
    func testStickingToggleAnswersWithCapabilities() async {
        let ctrl = FakeCameraControlling()
        await harness.coordinator.seed(state: .camera, lobby: harness.lobbyWrapper,
                                       peer: harness.peer, ctrl: ctrl)
        await harness.deliver(RemoteCmd.ToggleCamera())

        let resp = harness.fakeMP.sentMessages.compactMap { $0.msg as? RemoteCmd.CameraCapabilitiesResp }.last
        XCTAssertEqual(resp?.inReplyTo, .togglecamera)
        XCTAssertNil(resp?.error)
        XCTAssertEqual(resp?.activeDeviceID, "fake-front")
    }

    /// The pipeline refuses to record when audio can't be configured and
    /// reports MicrophoneAccessDenied. The recording state must answer the
    /// monitor with the stop ack + an error response, and return to camera.
    func testMicrophoneDeniedDuringRecordingAcksErrorAndReturnsToCamera() async {
        let ctrl = FakeCameraControlling()
        await harness.coordinator.seed(state: .cameraRecordingVideo,
                                       lobby: harness.lobbyWrapper,
                                       peer: harness.peer,
                                       ctrl: ctrl)

        await harness.deliver(UICmd.MicrophoneAccessDenied(error: NSError(domain: "mic", code: 1002)))

        let state = await harness.stateName()
        XCTAssertEqual(state, .camera)
        let sent = harness.fakeMP.sentMessages.map(\.msg)
        XCTAssertTrue(sent.contains { $0 is RemoteCmd.StopRecordingVideoAck })
        let resp = sent.compactMap { $0 as? RemoteCmd.StopRecordingVideoResp }.first
        XCTAssertNotNil(resp, "the monitor must receive a stop response")
        XCTAssertNotNil(resp?.error, "…carrying the error")
    }

    // MARK: - Camera preview mode (standby)

    /// The persisted preference defaults to preview-on — the shipping behavior.
    /// Opt-in feature: an unset store must never report standby.
    func testCameraPreviewModeDefaultsToOn() {
        let suite = UserDefaults(suiteName: "preview-mode-default-\(UUID().uuidString)")!
        let store = CameraPreviewModeStore(defaults: suite)
        XCTAssertEqual(store.load(), .on)
        XCTAssertEqual(CameraPreviewMode.default, .on)
    }

    /// The preference round-trips through UserDefaults (survives relaunch).
    func testCameraPreviewModePersistsRoundTrip() {
        let suite = UserDefaults(suiteName: "preview-mode-roundtrip-\(UUID().uuidString)")!

        CameraPreviewModeStore(defaults: suite).save(.standby)
        // A fresh store over the same suite = a relaunch.
        XCTAssertEqual(CameraPreviewModeStore(defaults: suite).load(), .standby)

        CameraPreviewModeStore(defaults: suite).save(.on)
        XCTAssertEqual(CameraPreviewModeStore(defaults: suite).load(), .on)
    }

    /// Camera side: a remote SetCameraPreviewMode applies the mode on the rig and
    /// reports it back to the monitor.
    func testCameraAppliesRemoteSetPreviewMode() async {
        await enterCamera()

        await harness.deliver(RemoteCmd.SetCameraPreviewMode(mode: .standby))

        XCTAssertEqual(camera.previewModeCalls, [.standby])
        let sent = harness.fakeMP.sentMessages.map(\.msg)
        let resps = sent.compactMap { $0 as? RemoteCmd.CameraCapabilitiesResp }.filter { $0.inReplyTo == .setcamerapreviewmode }
        XCTAssertEqual(resps.count, 1)
        XCTAssertEqual(resps.first?.previewMode, .standby)
        // Display-only: never mistaken for a capture.
        XCTAssertTrue(camera.takePictureCalls.isEmpty)
    }

    /// Camera side: a LOCAL toggle (the camera's own chrome) applies + persists
    /// the mode and reports it to the monitor, same as the remote path.
    func testCameraAppliesLocalSetPreviewMode() async {
        await enterCamera()

        await harness.deliver(UICmd.SetCameraPreviewMode(mode: .standby))

        XCTAssertEqual(camera.previewModeCalls, [.standby])
        // A camera-originated change reaches the remote as a state push.
        let sent = harness.fakeMP.sentMessages.map(\.msg)
        let resps = sent.compactMap { $0 as? RemoteCmd.CameraCapabilitiesResp }
        XCTAssertEqual(resps.last?.inReplyTo, .requestcapabilities)
        XCTAssertEqual(resps.last?.previewMode, .standby)
        let state = await harness.stateName()
        XCTAssertEqual(state, .camera)
    }
}

// MARK: - Peer-backgrounded reconnect flow (C-5)

/// Losing the peer puts up one cancelable overlay and starts a fixed-cadence
/// retry (monitor role re-invites; the camera advertises and waits), ending
/// only on reconnect or Cancel. The connection ending is the sole trigger —
/// there is no announcement to trust.
class SessionReconnectTests: XCTestCase {

    private var harness: CoordinatorHarness!
    private var peerLink: PeerLinkStatus!

    override func setUp() async throws {
        try await super.setUp()
        harness = await makeCoordinatorHarness()
        peerLink = PeerLinkStatus()
        await harness.coordinator.setPeerLinkStatus(peerLink)
        await harness.coordinator.setReconnectRetryDelay(0.05)
        await harness.coordinator.seed(
            state: .connected, lobby: harness.lobbyWrapper, peer: harness.peer)
    }

    /// The overlay is a pure function of this value.
    private func isReconnecting() async -> Bool {
        await MainActor.run {
            if case .reconnecting = peerLink.link { return true }
            return false
        }
    }

    /// Sleep past one retry tick, then drain the inbox and main queue.
    private func awaitRetryTick() async {
        try? await Task.sleep(nanoseconds: 120_000_000)
        await harness.coordinator.waitForIdle()
        await MainActor.run { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02)) }
    }

    func testLosingThePeerShowsTheOverlay() async {
        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))

        let waiting = await isReconnecting()
        XCTAssertTrue(waiting, "the overlay renders while we wait")
        let state = await harness.stateName()
        XCTAssertEqual(state, .reconnecting, "losing the peer IS a state, not a flag")
    }

    /// The one behavior this state exists for: the machine's own pop back to
    /// the scanner makes the scanner announce itself, and that announcement
    /// must not end the wait it is a side effect of.
    func testScannerAppearingDuringAWaitChangesNothing() async {
        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))

        await harness.deliver(UICmd.ScannerDidAppear())

        let state = await harness.stateName()
        XCTAssertEqual(state, .reconnecting, "the machine caused this arrival; it ends nothing")
        let waiting = await isReconnecting()
        XCTAssertTrue(waiting, "the overlay survives the scanner's announcement")
    }

    /// The wait rebuilds discovery and invites on re-discovery. Dialing the
    /// endpoint we already hold is useless: it was learned before the link
    /// died, and after the interface goes down it addresses nothing.
    func testWaitRestartsDiscoveryAndInvitesOnRediscovery() async {
        harness.lobby.role = .monitor
        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))

        let state = await harness.stateName()
        XCTAssertEqual(state, .reconnecting)
        let stillWaiting = await isReconnecting()
        XCTAssertTrue(stillWaiting, "the overlay is up while we wait")

        let startsAfterDrop = harness.fakeMP.discoveryStarts
        await awaitRetryTick()
        XCTAssertGreaterThan(harness.fakeMP.discoveryStarts, startsAfterDrop,
                             "each tick rebuilds the radios")
        XCTAssertTrue(harness.fakeMP.invitedPeers.isEmpty,
                      "nothing is dialed until the peer is actually found again")

        // Re-discovery is the moment the endpoint is real again.
        await harness.deliver(UICmd.BrowserFoundPeer(peer: harness.peer))
        XCTAssertEqual(harness.fakeMP.invitedPeers.first?.peer, harness.peer,
                       "finding the awaited peer invites it")

        // Reconnection ends the loop and dismisses the dialog.
        await harness.deliver(OnConnectToDevice(peer: harness.peer, sender: nil))
        let cleared = await isReconnecting()
        XCTAssertFalse(cleared, "reconnected ⇒ no overlay")
        let finalState = await harness.stateName()
        XCTAssertEqual(finalState, .connected)
    }

    /// `invitePeer` rebuilds the session, which drops a QUIC handshake still
    /// completing. A dial needs seconds, so nothing — a tick, or the browser
    /// re-reporting the peer — may interrupt one.
    func testWaitDoesNotRestartAnAttemptInFlight() async {
        harness.lobby.role = .monitor
        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))
        await harness.deliver(UICmd.BrowserFoundPeer(peer: harness.peer))
        XCTAssertEqual(harness.fakeMP.invitedPeers.count, 1, "one attempt starts")

        await awaitRetryTick()
        await harness.deliver(UICmd.BrowserFoundPeer(peer: harness.peer))
        XCTAssertEqual(harness.fakeMP.invitedPeers.count, 1,
                       "an in-flight handshake is left alone")

        // Only its failure frees the next attempt.
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))
        await harness.deliver(UICmd.BrowserFoundPeer(peer: harness.peer))
        XCTAssertEqual(harness.fakeMP.invitedPeers.count, 2,
                       "the wait continues once the attempt is over")
    }

    func testCameraRoleWaitsWithoutInviting() async {
        harness.lobby.role = .camera
        harness.fakeMP.connectedPeers = []
        let startsBefore = harness.fakeMP.discoveryStarts
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))
        await awaitRetryTick()
        await harness.deliver(UICmd.BrowserFoundPeer(peer: harness.peer))

        XCTAssertTrue(harness.fakeMP.invitedPeers.isEmpty,
                      "only the monitor invites; the camera advertises and waits")
        XCTAssertGreaterThan(harness.fakeMP.discoveryStarts, startsBefore,
                             "the camera's half of the wait is advertising again")
        let stillWaiting = await isReconnecting()
        XCTAssertTrue(stillWaiting)
    }

    func testCancelStopsTheRetryLoop() async {
        harness.lobby.role = .monitor
        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))
        await awaitRetryTick()

        await harness.deliver(UICmd.CancelReconnect())
        let cleared = await isReconnecting()
        XCTAssertFalse(cleared)

        let invitesAtCancel = harness.fakeMP.invitedPeers.count
        await awaitRetryTick()
        XCTAssertEqual(harness.fakeMP.invitedPeers.count, invitesAtCancel,
                       "no further invites after Cancel")
    }

    /// Cancelling forgets the peer, so the invitation still in flight can fail
    /// without that failure being read as a fresh loss.
    func testCancelSurvivesTheInviteThatWasInFlight() async {
        harness.lobby.role = .monitor
        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))
        await harness.deliver(UICmd.BrowserFoundPeer(peer: harness.peer))
        XCTAssertEqual(harness.fakeMP.invitedPeers.count, 1, "an invite is in flight")

        await harness.deliver(UICmd.CancelReconnect())
        // That in-flight invite now fails, the way every failure arrives.
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))

        let waiting = await isReconnecting()
        XCTAssertFalse(waiting, "a cancelled wait stays cancelled")
        await awaitRetryTick()
        await harness.deliver(UICmd.BrowserFoundPeer(peer: harness.peer))
        XCTAssertEqual(harness.fakeMP.invitedPeers.count, 1,
                       "and the peer is not chased again")
    }

    func testCancelStopsWaitingAndStaysInScanning() async {
        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))
        await harness.deliver(UICmd.CancelReconnect())

        let waiting = await isReconnecting()
        XCTAssertFalse(waiting)
        let state = await harness.stateName()
        XCTAssertEqual(state, .scanning)
    }

    /// Traffic is proof the peer is here, whatever else we believe.
    func testInboundTrafficClearsTheOverlay() async {
        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))
        let waiting = await isReconnecting()
        XCTAssertTrue(waiting)

        await harness.deliver(UICmd.PeerTrafficObserved())
        let cleared = await isReconnecting()
        XCTAssertFalse(cleared, "packets arriving ⇒ the peer is here")
        let state = await harness.stateName()
        XCTAssertEqual(state, .connected,
                       "traffic resumes the session through the same door a fresh connection uses")
    }

    /// A peer that says goodbye is not chased: no overlay, no invites.
    func testAnnouncedExitSuppressesTheRetryLoop() async {
        harness.lobby.role = .monitor
        await harness.deliver(RemoteCmd.EndSession())
        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))

        let waiting = await isReconnecting()
        XCTAssertFalse(waiting, "an announced exit is expected, not a loss")

        await awaitRetryTick()
        XCTAssertTrue(harness.fakeMP.invitedPeers.isEmpty, "nobody chases a peer that left")

        // The next, UNannounced loss still starts a wait.
        await harness.deliver(OnConnectToDevice(peer: harness.peer, sender: nil))
        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))
        let waitingAgain = await isReconnecting()
        XCTAssertTrue(waitingAgain, "the suppression is one-shot")
    }

    /// Leaving on purpose tells the peer, so it does not reconnect.
    func testDeliberateDisconnectAnnouncesTheExit() async {
        await harness.deliver(UICmd.ScannerDidAppear())

        let announced = harness.fakeMP.sentMessages.contains { $0.msg is RemoteCmd.EndSession }
        XCTAssertTrue(announced, "the peer must be told before we tear down")
    }

    /// An incompatible peer is left the way a deliberate exit leaves one: it is
    /// told, and this device stops waiting for it. Skip either half and the two
    /// devices reconnect, re-announce roles, fail the same gate and drop again
    /// once a second for as long as they are in range.
    func testIncompatiblePeerIsLeftWithoutStartingARetryLoop() async {
        guard let local = PeerAppCompatibility.localVersion else {
            return XCTFail("the test host must carry a parseable CFBundleShortVersionString")
        }
        harness.lobby.role = .monitor

        await harness.deliver(RemoteCmd.PeerBecameMonitor(
            bundleVersion: 110, shortVersion: "\(local.major + 1).0.0", platform: "iPhone"))

        XCTAssertTrue(harness.fakeMP.sentMessages.contains { $0.msg is RemoteCmd.EndSession },
                      "the peer must be told, or it keeps re-inviting a session it cannot hold")
        XCTAssertTrue(harness.fakeMP.disconnectCalled, "the link is dropped, not left open")

        // Our own teardown comes back as a peer loss; it must not read as one.
        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))

        let waiting = await isReconnecting()
        XCTAssertFalse(waiting, "we left on purpose ⇒ no overlay")
        await awaitRetryTick()
        XCTAssertTrue(harness.fakeMP.invitedPeers.isEmpty,
                      "and no invites back to a peer we cannot talk to")
        let state = await harness.stateName()
        XCTAssertEqual(state, .scanning)
    }

    func testLosingAnUnknownPeerIsIgnored() async {
        let stranger = MCPeerID(displayName: "Stranger")
        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: stranger, sender: nil))
        let waiting = await isReconnecting()
        XCTAssertFalse(waiting, "only the session peer starts a wait")
    }

    // MARK: - Foreground re-arm

    /// Suspension kills the peer session within seconds, and the notice is
    /// delivered to a frozen process — it may never arrive. A camera that never
    /// learns it lost a session never advertises again, so no remote can find
    /// it. Returning to the foreground with nothing connected re-arms
    /// advertising — and the camera HOLDS its post (server role): a camera
    /// state without a link is not a lie, it is a camera awaiting its remote,
    /// and the chip says so.
    func testForegroundHoldsACameraStateWithNoLiveLink() async {
        let ctrl = FakeCameraControlling()
        await harness.coordinator.seed(
            state: .camera, lobby: harness.lobbyWrapper, peer: harness.peer,
            ctrl: ctrl)
        harness.lobby.role = .camera
        harness.fakeMP.connectedPeers = []
        let startsBefore = harness.fakeMP.discoveryStarts

        await harness.deliver(UICmd.AppForegrounded())

        let state = await harness.stateName()
        XCTAssertEqual(state, .camera, "the camera holds its post; .reconnecting is monitor-only")
        XCTAssertGreaterThan(harness.fakeMP.discoveryStarts, startsBefore,
                             "the wake re-arms advertising")
        await MainActor.run {
            XCTAssertTrue(ctrl.cameraViewModel.isAwaitingRemoteReconnect)
        }
    }

    /// Already scanning: rebuild the radios in place. They may have died while
    /// the process was frozen, and re-entering the state would reset the lobby.
    func testForegroundRestartsDiscoveryWhileScanning() async {
        await harness.coordinator.seed(state: .scanning, lobby: harness.lobbyWrapper)
        harness.fakeMP.connectedPeers = []
        let startsBefore = harness.fakeMP.discoveryStarts

        await harness.deliver(UICmd.AppForegrounded())

        XCTAssertGreaterThan(harness.fakeMP.discoveryStarts, startsBefore,
                             "stale radios are rebuilt")
        let state = await harness.stateName()
        XCTAssertEqual(state, .scanning)
    }

    /// A short background can end with the link still up. Nothing to fix, and
    /// re-arming would tear down a working session.
    func testForegroundWithALiveLinkChangesNothing() async {
        let startsBefore = harness.fakeMP.discoveryStarts

        await harness.deliver(UICmd.AppForegrounded())

        XCTAssertEqual(harness.fakeMP.discoveryStarts, startsBefore)
        XCTAssertFalse(harness.fakeMP.disconnectCalled)
        let state = await harness.stateName()
        XCTAssertEqual(state, .connected)
    }
}
