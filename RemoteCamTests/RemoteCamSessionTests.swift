//
//  RemoteCamSessionTests.swift
//  RemoteShutterTests
//
//  State-machine tests for SessionCoordinator — every behavioral assertion
//  carried over from the Theater-era RemoteCamSession tests, now driving the
//  enum machine through its real transitions (BecomeMonitor/BecomeCamera and
//  friends) instead of seeding closure states.
//

// swiftlint:disable file_length type_body_length

import XCTest
import MPCCompat
import Stormo

@testable import RemoteShutter

class SessionCoordinatorTests: XCTestCase {

    private var harness: CoordinatorHarness!
    private var presenter: MonitorPresenter!
    private var camera: FakeCameraControlling!

    override func setUp() async throws {
        try await super.setUp()
        harness = await makeCoordinatorHarness()
        presenter = MonitorPresenter()
        camera = FakeCameraControlling()
    }

    override func tearDown() async throws {
        harness.coordinator.stop()
        harness = nil
        presenter = nil
        camera = nil
        try await super.tearDown()
    }

    // MARK: - Seeding helpers (real transitions, like production)

    private func seedConnected() async {
        await harness.coordinator.seed(state: .connected, lobby: harness.lobbyWrapper, peer: harness.peer)
    }

    private func enterMonitor(_ mode: RecordingMode = .Photo) async {
        await seedConnected()
        await harness.deliver(UICmd.BecomeMonitor(presenter: presenter, mode: mode))
        harness.fakeMP.sentMessages.removeAll()
    }

    private func enterCamera() async {
        await seedConnected()
        await harness.deliver(UICmd.BecomeCamera(sender: nil, ctrl: camera))
        harness.fakeMP.sentMessages.removeAll()
    }

    private func enterMonitorTakingPicture() async {
        await enterMonitor(.Photo)
        await harness.deliver(UICmd.TakePicture(sender: nil, sendMediaToRemote: true))
        harness.fakeMP.sentMessages.removeAll()
        harness.alerts.shownAlerts.removeAll()
        harness.alerts.shownErrors.removeAll()
    }

    private func enterMonitorTogglingFlash() async {
        await enterMonitor(.Photo)
        await harness.deliver(UICmd.ToggleFlash())
        harness.fakeMP.sentMessages.removeAll()
        harness.alerts.shownAlerts.removeAll()
        harness.alerts.shownErrors.removeAll()
    }

    private func enterMonitorTogglingCamera() async {
        await enterMonitor(.Photo)
        await harness.deliver(UICmd.ToggleCamera())
        harness.fakeMP.sentMessages.removeAll()
        harness.alerts.shownAlerts.removeAll()
        harness.alerts.shownErrors.removeAll()
    }

    private func enterMonitorSwitchingLens() async {
        await enterMonitor(.Photo)
        await harness.deliver(UICmd.SwitchLens(lensType: .telephoto))
        harness.fakeMP.sentMessages.removeAll()
        harness.alerts.shownAlerts.removeAll()
        harness.alerts.shownErrors.removeAll()
    }

    private func enterMonitorRecordingVideo() async {
        await enterMonitor(.Video)
        await harness.deliver(UICmd.TakePicture(sender: nil, sendMediaToRemote: true))
        harness.fakeMP.sentMessages.removeAll()
    }

    private func enterMonitorWaitingForVideo() async {
        await enterMonitorRecordingVideo()
        await harness.deliver(RemoteCmd.StopRecordingVideoAck())
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
        await harness.deliver(Disconnect(sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
        // The exit is announced so the peer stops reconnecting — and that is
        // the ONLY thing a deliberate disconnect puts on the wire.
        XCTAssertEqual(harness.fakeMP.sentMessages.count, 1)
        XCTAssertTrue(harness.fakeMP.sentMessages.first?.msg is RemoteCmd.EndSession)
    }

    func testConnectedStateBecomeMonitorPhoto() async {
        await seedConnected()
        await harness.deliver(UICmd.BecomeMonitor(presenter: presenter, mode: .Photo))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
        XCTAssertGreaterThanOrEqual(sent(RemoteCmd.PeerBecameMonitor.self).count, 1)
        XCTAssertEqual(sent(RemoteCmd.PeerBecameMonitor.self)[0].peers, [harness.peer])
    }

    func testConnectedStateBecomeMonitorVideo() async {
        await seedConnected()
        await harness.deliver(UICmd.BecomeMonitor(presenter: presenter, mode: .Video))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
        XCTAssertGreaterThanOrEqual(sent(RemoteCmd.PeerBecameMonitor.self).count, 1)
    }

    func testConnectedStateNilLobbyPopsToScanning() async {
        let deadLobby = FakeScannerLobby()
        var wrapper: WeakScannerLobby? = WeakScannerLobby(deadLobby)
        await harness.coordinator.seed(state: .connected, lobby: wrapper, peer: harness.peer)
        wrapper?.value = nil
        wrapper = nil

        await harness.deliver(Disconnect(sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    func testConnectedStateDisconnectPeerPopsToScanning() async {
        await seedConnected()

        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    func testConnectedStateBecomeMonitorSendsPeerBecameMonitor() async {
        await seedConnected()
        harness.fakeMP.sentMessages.removeAll()

        await harness.deliver(UICmd.BecomeMonitor(presenter: presenter, mode: .Photo))

        let becameMonitor = sent(RemoteCmd.PeerBecameMonitor.self)
        XCTAssertEqual(becameMonitor.count, 1)
        XCTAssertEqual(becameMonitor[0].peers, [harness.peer])
        XCTAssertEqual(becameMonitor[0].mode, .reliable)
    }

    // MARK: - Monitor photo mode

    func testMonitorPhotoModeOnEnterRequestsFrame() async {
        await seedConnected()
        await harness.deliver(UICmd.BecomeMonitor(presenter: presenter, mode: .Photo))

        let frameRequests = sent(RemoteCmd.RequestFrame.self)
        XCTAssertEqual(frameRequests.count, 1)
        XCTAssertEqual(frameRequests[0].peers, [harness.peer])
    }

    func testMonitorPhotoModeRequestFrameUsesReliableMode() async {
        await seedConnected()
        await harness.deliver(UICmd.BecomeMonitor(presenter: presenter, mode: .Photo))

        let frameRequests = sent(RemoteCmd.RequestFrame.self)
        XCTAssertEqual(frameRequests.count, 1)
        XCTAssertEqual(frameRequests[0].mode, .reliable)
    }

    func testMonitorPhotoModeUnbecomeMonitorPopsToConnected() async {
        await enterMonitor(.Photo)
        await harness.deliver(UICmd.UnbecomeMonitor(sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .connected)
    }

    func testMonitorPhotoModeDisconnectPopsToScanning() async {
        await enterMonitor(.Photo)
        await harness.deliver(Disconnect(sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    func testMonitorPhotoModeTakePictureTransitions() async {
        await enterMonitor(.Photo)
        await harness.deliver(UICmd.TakePicture(sender: nil, sendMediaToRemote: true))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitorTakingPicture)
    }

    func testMonitorPhotoModeToggleFlashTransitions() async {
        await enterMonitor(.Photo)
        await harness.deliver(UICmd.ToggleFlash())

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitorTogglingFlash)
    }

    func testMonitorPhotoModeToggleCameraTransitions() async {
        await enterMonitor(.Photo)
        await harness.deliver(UICmd.ToggleCamera())

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitorTogglingCamera)
    }

    func testMonitorPhotoModeSwitchToVideoMode() async {
        await enterMonitor(.Photo)
        await harness.deliver(UICmd.BecomeMonitor(presenter: presenter, mode: .Video))

        // Mode swap replaces the state in place — still .monitor.
        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
    }

    func testMonitorPhotoModeToggleTorchSendsCommand() async {
        await enterMonitor(.Photo)
        await harness.deliver(UICmd.ToggleTorch())

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
        XCTAssertEqual(sent(RemoteCmd.ToggleTorch.self).count, 1)
    }

    func testMonitorPhotoModeRequestCameraCapabilities() async {
        await enterMonitor(.Photo)
        await harness.deliver(UICmd.RequestCameraCapabilities())

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
        XCTAssertEqual(sent(RemoteCmd.RequestCameraCapabilities.self).count, 1)
    }

    func testMonitorPhotoModeSwitchLensTransitions() async {
        await enterMonitor(.Photo)
        await harness.deliver(UICmd.SwitchLens(lensType: .telephoto))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitorSwitchingLens)
    }

    func testMonitorPhotoModeSetZoomSendsCommand() async {
        await enterMonitor(.Photo)
        await harness.deliver(UICmd.SetZoom(zoomFactor: 2.0))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
        XCTAssertEqual(sent(RemoteCmd.SetZoom.self).count, 1)
    }

    func testMonitorPhotoModePeerBecameCameraRequestsCapabilities() async {
        await enterMonitor(.Photo)
        await harness.deliver(RemoteCmd.PeerBecameCamera.createWithDefaults())

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
        XCTAssertEqual(sent(RemoteCmd.RequestCameraCapabilities.self).count, 1)
    }

    func testMonitorPhotoModeDisconnectPeerPopsToScanning() async {
        await enterMonitor(.Photo)

        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    func testMonitorPhotoModeSetAspectRatioSendsCommand() async throws {
        await enterMonitor(.Photo)
        await harness.deliver(UICmd.SetAspectRatio(aspectRatio: .fourThree))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
        let ratioMessages = sent(RemoteCmd.SetAspectRatio.self)
        XCTAssertEqual(ratioMessages.count, 1)
        let msg = try XCTUnwrap(ratioMessages[0].msg as? RemoteCmd.SetAspectRatio)
        XCTAssertEqual(msg.aspectRatio, .fourThree)
    }

    // MARK: - Monitor video mode

    func testMonitorVideoModeOnEnterRequestsFrame() async {
        await seedConnected()
        await harness.deliver(UICmd.BecomeMonitor(presenter: presenter, mode: .Video))

        XCTAssertEqual(sent(RemoteCmd.RequestFrame.self).count, 1)
    }

    func testMonitorVideoModeSwitchToPhotoMode() async {
        await enterMonitor(.Video)
        await harness.deliver(UICmd.BecomeMonitor(presenter: presenter, mode: .Photo))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
    }

    func testMonitorVideoModeDisconnectPopsToScanning() async {
        await enterMonitor(.Video)
        await harness.deliver(Disconnect(sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    func testMonitorVideoModeUnbecomeMonitorPopsToConnected() async {
        await enterMonitor(.Video)
        await harness.deliver(UICmd.UnbecomeMonitor(sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .connected)
    }

    func testMonitorVideoModeTakePictureStartsRecording() async {
        await enterMonitor(.Video)
        await harness.deliver(UICmd.TakePicture(sender: nil, sendMediaToRemote: true))

        XCTAssertEqual(sent(RemoteCmd.StartRecordingVideo.self).count, 1)
        let name = await harness.stateName()
        XCTAssertEqual(name, .monitorRecordingVideo)
    }

    func testMonitorVideoModeToggleCameraTransitions() async {
        await enterMonitor(.Video)
        await harness.deliver(UICmd.ToggleCamera())

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitorTogglingCamera)
    }

    func testMonitorVideoModeToggleTorchSendsCommand() async {
        await enterMonitor(.Video)
        await harness.deliver(UICmd.ToggleTorch())

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
        XCTAssertEqual(sent(RemoteCmd.ToggleTorch.self).count, 1)
    }

    func testMonitorVideoModeSwitchLensTransitions() async {
        await enterMonitor(.Video)
        await harness.deliver(UICmd.SwitchLens(lensType: .ultraWide))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitorSwitchingLens)
    }

    func testMonitorVideoModeSetZoomSendsCommand() async {
        await enterMonitor(.Video)
        await harness.deliver(UICmd.SetZoom(zoomFactor: 3.0))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
        XCTAssertEqual(sent(RemoteCmd.SetZoom.self).count, 1)
    }

    func testMonitorVideoModeRequestCameraCapabilities() async {
        await enterMonitor(.Video)
        await harness.deliver(UICmd.RequestCameraCapabilities())

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
        XCTAssertEqual(sent(RemoteCmd.RequestCameraCapabilities.self).count, 1)
    }

    func testMonitorVideoModePeerBecameCameraRequestsCapabilities() async {
        await enterMonitor(.Video)
        await harness.deliver(RemoteCmd.PeerBecameCamera.createWithDefaults())

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
        XCTAssertEqual(sent(RemoteCmd.RequestCameraCapabilities.self).count, 1)
    }

    func testMonitorVideoModeDisconnectPeerPopsToScanning() async {
        await enterMonitor(.Video)

        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    func testMonitorVideoModeStartRecordingVideoSentToPeer() async {
        await enterMonitor(.Video)
        await harness.deliver(UICmd.TakePicture(sender: nil, sendMediaToRemote: true))

        let startMsgs = sent(RemoteCmd.StartRecordingVideo.self)
        XCTAssertEqual(startMsgs.count, 1)
        XCTAssertEqual(startMsgs[0].peers, [harness.peer])
        XCTAssertEqual(startMsgs[0].mode, .reliable)
    }

    func testMonitorVideoModeSetAspectRatioSendsCommand() async {
        await enterMonitor(.Video)
        await harness.deliver(UICmd.SetAspectRatio(aspectRatio: .sixteenNine))

        XCTAssertEqual(sent(RemoteCmd.SetAspectRatio.self).count, 1)
    }

    // MARK: - Monitor taking picture

    func testMonitorTakingPictureTakePicRespWithErrorUnbecomes() async {
        await enterMonitorTakingPicture()

        let error = NSError(domain: "TestError", code: 42, userInfo: nil)
        await harness.deliver(RemoteCmd.TakePicResp(sender: nil, error: error))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
    }

    func testMonitorTakingPictureTakePicRespWithPicUnbecomes() async {
        await enterMonitorTakingPicture()
        // Route the save through a recorder instead of PHPhotoLibrary.
        await harness.coordinator.setPhotoLibrarySaver { _ in }

        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0]) // minimal JPEG header
        await harness.deliver(RemoteCmd.TakePicResp(sender: nil, pic: imageData))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
    }

    func testMonitorTakingPictureTakePicAckForwardsToPeer() async {
        await enterMonitorTakingPicture()
        await harness.deliver(RemoteCmd.TakePicAck(sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitorTakingPicture)
        let ackMessages = sent(RemoteCmd.TakePicAck.self)
        XCTAssertEqual(ackMessages.count, 1)
        XCTAssertEqual(ackMessages[0].peers, [harness.peer])
    }

    func testMonitorTakingPictureTakePictureSendsCommand() async {
        await enterMonitorTakingPicture()
        await harness.deliver(UICmd.TakePicture(sender: nil, sendMediaToRemote: true))

        XCTAssertEqual(sent(RemoteCmd.TakePic.self).count, 1)
        let name = await harness.stateName()
        XCTAssertEqual(name, .monitorTakingPicture)
    }

    func testMonitorTakingPictureTakePicAckUpdatesTitle() async {
        await enterMonitor(.Photo)
        await harness.deliver(UICmd.TakePicture(sender: nil, sendMediaToRemote: true))
        // Keep the alert handle from the real transition.
        await harness.deliver(RemoteCmd.TakePicAck(sender: nil))

        let updatedHandles = harness.alerts.shownAlerts.filter { $0.currentTitle == "Receiving picture" }
        XCTAssertEqual(updatedHandles.count, 1)
    }

    func testMonitorTakingPictureTakePicRespErrorShowsErrorAlert() async {
        await enterMonitorTakingPicture()

        let error = NSError(domain: "PicError", code: 1, userInfo: nil)
        await harness.deliver(RemoteCmd.TakePicResp(sender: nil, error: error))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
        XCTAssertTrue(harness.alerts.shownErrors.contains("PicError"))
    }

    func testMonitorTakingPictureDisconnectPopsToScanning() async {
        await enterMonitorTakingPicture()
        await harness.deliver(Disconnect(sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    func testMonitorTakingPictureUnbecomeMonitorPopsToConnected() async {
        await enterMonitorTakingPicture()
        await harness.deliver(UICmd.UnbecomeMonitor(sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .connected)
    }

    // MARK: - Monitor recording video

    func testMonitorRecordingVideoOnEnter() async {
        await enterMonitor(.Video)
        await harness.deliver(UICmd.TakePicture(sender: nil, sendMediaToRemote: true))

        let frameRequests = sent(RemoteCmd.RequestFrame.self)
        XCTAssertEqual(frameRequests.count, 1)
    }

    func testMonitorRecordingVideoStartAckWithErrorPopsToVideoMode() async {
        await enterMonitorRecordingVideo()

        let error = NSError(domain: "TestError", code: 1, userInfo: nil)
        await harness.deliver(RemoteCmd.StartRecordingVideoAck(sender: nil, recordingStartTime: nil, error: error))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
    }

    func testMonitorRecordingVideoTakePictureSendsStopRecording() async {
        await enterMonitorRecordingVideo()
        await harness.deliver(UICmd.TakePicture(sender: nil, sendMediaToRemote: true))

        XCTAssertEqual(sent(RemoteCmd.StopRecordingVideo.self).count, 1)
        let name = await harness.stateName()
        XCTAssertEqual(name, .monitorRecordingVideo)
    }

    func testMonitorRecordingVideoStopAckTransitionsToWaiting() async {
        await enterMonitorRecordingVideo()
        await harness.deliver(RemoteCmd.StopRecordingVideoAck())

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitorWaitingForVideo)
    }

    func testMonitorRecordingVideoStopRespWithErrorPopsToVideoMode() async {
        await enterMonitorRecordingVideo()

        let error = NSError(domain: "TestError", code: 2, userInfo: nil)
        await harness.deliver(RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: error))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
    }

    func testMonitorRecordingVideoDisconnectPopsToScanning() async {
        await enterMonitorRecordingVideo()
        await harness.deliver(Disconnect(sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    func testMonitorRecordingVideoDisconnectPeerPopsToScanning() async {
        await enterMonitorRecordingVideo()

        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    func testMonitorRecordingVideoUnbecomeMonitorPopsToConnected() async {
        await enterMonitorRecordingVideo()
        await harness.deliver(UICmd.UnbecomeMonitor(sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .connected)
    }

    func testMonitorRecordingVideoStopRecordingVideoSentToPeer() async {
        await enterMonitorRecordingVideo()
        await harness.deliver(UICmd.TakePicture(sender: nil, sendMediaToRemote: false))

        let stopMsgs = sent(RemoteCmd.StopRecordingVideo.self)
        XCTAssertEqual(stopMsgs.count, 1)
        XCTAssertEqual(stopMsgs[0].peers, [harness.peer])
        XCTAssertEqual(stopMsgs[0].mode, .reliable)
    }

    // MARK: - Monitor waiting for video

    func testMonitorWaitingForVideoStopRespPopsToVideoMode() async {
        await enterMonitorWaitingForVideo()
        await harness.deliver(RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
    }

    func testMonitorWaitingForVideoDisconnectPopsToScanning() async {
        await enterMonitorWaitingForVideo()
        await harness.deliver(Disconnect(sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    func testMonitorWaitingForVideoDisconnectPeerPopsToScanning() async {
        await enterMonitorWaitingForVideo()

        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    func testMonitorWaitingForVideoUnbecomeMonitorPopsToConnected() async {
        await enterMonitorWaitingForVideo()
        await harness.deliver(UICmd.UnbecomeMonitor(sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .connected)
    }

    // MARK: - Toggling flash transient

    func testMonitorTogglingFlashIgnoresDuplicateTap() async {
        await enterMonitorTogglingFlash()
        await harness.deliver(UICmd.ToggleFlash())

        XCTAssertEqual(sent(RemoteCmd.ToggleFlash.self).count, 0)
        let name = await harness.stateName()
        XCTAssertEqual(name, .monitorTogglingFlash)
    }

    func testMonitorTogglingFlashSuccessResponseUnbecomes() async {
        await enterMonitorTogglingFlash()
        await harness.deliver(RemoteCmd.ToggleFlashResp(flashMode: .on, error: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
    }

    func testMonitorTogglingFlashErrorResponseUnbecomes() async {
        await enterMonitorTogglingFlash()

        let error = NSError(domain: "FlashError", code: 1, userInfo: nil)
        await harness.deliver(RemoteCmd.ToggleFlashResp(flashMode: nil, error: error))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
    }

    func testMonitorTogglingFlashNilNilResponseUnbecomes() async {
        await enterMonitorTogglingFlash()
        await harness.deliver(RemoteCmd.ToggleFlashResp(flashMode: nil, error: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor,
                       "State should unbecome even when both flashMode and error are nil")
    }

    func testMonitorTogglingFlashDisconnectPopsToScanning() async {
        await enterMonitorTogglingFlash()
        await harness.deliver(Disconnect(sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    func testMonitorTogglingFlashDisconnectPeerPopsToScanning() async {
        await enterMonitorTogglingFlash()

        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    func testMonitorTogglingFlashUnbecomeMonitorPopsToConnected() async {
        await enterMonitorTogglingFlash()
        await harness.deliver(UICmd.UnbecomeMonitor(sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .connected)
    }

    // MARK: - Toggling camera transient

    func testMonitorTogglingCameraIgnoresDuplicateTap() async {
        await enterMonitorTogglingCamera()
        await harness.deliver(UICmd.ToggleCamera())

        XCTAssertEqual(sent(RemoteCmd.ToggleCamera.self).count, 0)
        let name = await harness.stateName()
        XCTAssertEqual(name, .monitorTogglingCamera)
    }

    func testMonitorTogglingCameraSuccessResponseUnbecomes() async {
        await enterMonitorTogglingCamera()

        let capabilities = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, currentLens: .wideAngle, currentZoom: 1.0, error: nil)
        await harness.deliver(RemoteCmd.ToggleCameraResp(cameraCapabilities: capabilities, error: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
    }

    func testMonitorTogglingCameraErrorResponseUnbecomes() async {
        await enterMonitorTogglingCamera()

        let error = NSError(domain: "CameraError", code: 1, userInfo: nil)
        await harness.deliver(RemoteCmd.ToggleCameraResp(cameraCapabilities: nil, error: error))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
    }

    func testMonitorTogglingCameraNilNilResponseUnbecomes() async {
        await enterMonitorTogglingCamera()
        await harness.deliver(RemoteCmd.ToggleCameraResp(cameraCapabilities: nil, error: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor,
                       "State should unbecome even when both capabilities and error are nil")
    }

    func testMonitorTogglingCameraDisconnectPopsToScanning() async {
        await enterMonitorTogglingCamera()
        await harness.deliver(Disconnect(sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    func testMonitorTogglingCameraDisconnectPeerPopsToScanning() async {
        await enterMonitorTogglingCamera()

        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    func testMonitorTogglingCameraUnbecomeMonitorPopsToConnected() async {
        await enterMonitorTogglingCamera()
        await harness.deliver(UICmd.UnbecomeMonitor(sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .connected)
    }

    // MARK: - Switching lens transient

    func testMonitorSwitchingLensIgnoresDuplicateTap() async {
        await enterMonitorSwitchingLens()
        await harness.deliver(UICmd.SwitchLens(lensType: .telephoto))

        XCTAssertEqual(sent(RemoteCmd.SwitchLens.self).count, 0)
        let name = await harness.stateName()
        XCTAssertEqual(name, .monitorSwitchingLens)
    }

    func testMonitorSwitchingLensSuccessResponseUnbecomes() async {
        await enterMonitorSwitchingLens()
        await harness.deliver(RemoteCmd.SwitchLensResp(
            lensType: .telephoto, availableLenses: [.wideAngle, .telephoto],
            currentZoom: 2.0, zoomRange: RemoteCmd.ZoomRange(minZoom: 1.0, maxZoom: 10.0), error: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
    }

    func testMonitorSwitchingLensErrorResponseUnbecomes() async {
        await enterMonitorSwitchingLens()

        let error = NSError(domain: "LensError", code: 1, userInfo: nil)
        await harness.deliver(RemoteCmd.SwitchLensResp(
            lensType: nil, availableLenses: nil, currentZoom: nil, zoomRange: nil, error: error))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
    }

    func testMonitorSwitchingLensNilNilResponseUnbecomes() async {
        await enterMonitorSwitchingLens()
        await harness.deliver(RemoteCmd.SwitchLensResp(
            lensType: nil, availableLenses: nil, currentZoom: nil, zoomRange: nil, error: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor,
                       "State should unbecome even when both lensType and error are nil")
    }

    func testMonitorSwitchingLensDisconnectPeerPopsToScanning() async {
        await enterMonitorSwitchingLens()

        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    func testMonitorSwitchingLensDisconnectPopsToScanning() async {
        await enterMonitorSwitchingLens()
        await harness.deliver(Disconnect(sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    func testMonitorSwitchingLensUnbecomeMonitorPopsToConnected() async {
        await enterMonitorSwitchingLens()
        await harness.deliver(UICmd.UnbecomeMonitor(sender: nil))

        let name = await harness.stateName()
        XCTAssertEqual(name, .connected)
    }

    // MARK: - Recording transitions

    func testMonitorVideoModeTransitionsToRecordingAfterSend() async {
        await enterMonitor(.Video)
        await harness.deliver(UICmd.TakePicture(sender: nil, sendMediaToRemote: true))

        XCTAssertEqual(sent(RemoteCmd.StartRecordingVideo.self).count, 1)
        let name = await harness.stateName()
        XCTAssertEqual(name, .monitorRecordingVideo)
    }

    func testMonitorRecordingVideoErrorAckPopsToMonitor() async {
        await enterMonitor(.Video)
        await harness.deliver(UICmd.TakePicture(sender: nil, sendMediaToRemote: true))
        var name = await harness.stateName()
        XCTAssertEqual(name, .monitorRecordingVideo)

        let error = NSError(domain: "MicrophoneDenied", code: 1, userInfo: nil)
        await harness.deliver(RemoteCmd.StartRecordingVideoAck(sender: nil, recordingStartTime: nil, error: error))

        name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
    }

    func testVideoModePushedWithMonitorStateName() async {
        await enterMonitor(.Video)
        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
    }

    func testPopToMonitorWorksAfterModeSwitch() async {
        await enterMonitor(.Photo)
        await harness.deliver(UICmd.BecomeMonitor(presenter: presenter, mode: .Video))
        var name = await harness.stateName()
        XCTAssertEqual(name, .monitor)

        await harness.deliver(UICmd.TakePicture(sender: nil, sendMediaToRemote: true))
        harness.fakeMP.sentMessages.removeAll()

        let error = NSError(domain: "TestError", code: 1, userInfo: nil)
        await harness.deliver(RemoteCmd.StartRecordingVideoAck(sender: nil, recordingStartTime: nil, error: error))

        name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
    }

    // MARK: - Send-before-become

    func testMonitorPhotoModeToggleCameraSendsBeforeTransition() async {
        await enterMonitor(.Photo)
        await harness.deliver(UICmd.ToggleCamera())

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitorTogglingCamera)
        XCTAssertEqual(sent(RemoteCmd.ToggleCamera.self).count, 1)
    }

    func testMonitorVideoModeToggleCameraSendsBeforeTransition() async {
        await enterMonitor(.Video)
        await harness.deliver(UICmd.ToggleCamera())

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitorTogglingCamera)
        XCTAssertEqual(sent(RemoteCmd.ToggleCamera.self).count, 1)
    }

    func testMonitorPhotoModeToggleFlashSendsBeforeTransition() async {
        await enterMonitor(.Photo)
        await harness.deliver(UICmd.ToggleFlash())

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitorTogglingFlash)
        XCTAssertEqual(sent(RemoteCmd.ToggleFlash.self).count, 1)
    }

    func testMonitorPhotoModeTakePictureSendsBeforeTransition() async {
        await enterMonitor(.Photo)
        await harness.deliver(UICmd.TakePicture(sender: nil, sendMediaToRemote: true))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitorTakingPicture)
        XCTAssertEqual(sent(RemoteCmd.TakePic.self).count, 1)
    }

    func testMonitorPhotoModeSwitchLensSendsBeforeTransition() async {
        await enterMonitor(.Photo)
        await harness.deliver(UICmd.SwitchLens(lensType: .telephoto))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitorSwitchingLens)
        XCTAssertEqual(sent(RemoteCmd.SwitchLens.self).count, 1)
    }

    func testMonitorVideoModeSwitchLensSendsBeforeTransition() async {
        await enterMonitor(.Video)
        await harness.deliver(UICmd.SwitchLens(lensType: .ultraWide))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitorSwitchingLens)
        XCTAssertEqual(sent(RemoteCmd.SwitchLens.self).count, 1)
    }

    // MARK: - Timeouts

    func testTimeout_monitorTogglingFlash_unbecomes() async {
        await enterMonitorTogglingFlash()

        let generation = await harness.coordinator.currentTimeoutGeneration()
        await harness.deliver(UICmd.StateTimeout(stateName: .monitorTogglingFlash, generation: generation))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor, "Timeout should unbecome back to photo mode")
    }

    func testTimeout_staleGeneration_ignored() async {
        await enterMonitorTogglingFlash()

        let generation = await harness.coordinator.currentTimeoutGeneration()
        await harness.deliver(UICmd.StateTimeout(stateName: .monitorTogglingFlash, generation: generation - 1))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitorTogglingFlash, "Stale timeout should be ignored")
    }

    func testTimeout_monitorTogglingCamera_unbecomes() async {
        await enterMonitorTogglingCamera()

        let generation = await harness.coordinator.currentTimeoutGeneration()
        await harness.deliver(UICmd.StateTimeout(stateName: .monitorTogglingCamera, generation: generation))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
    }

    func testTimeout_monitorSwitchingLens_unbecomes() async {
        await enterMonitorSwitchingLens()

        let generation = await harness.coordinator.currentTimeoutGeneration()
        await harness.deliver(UICmd.StateTimeout(stateName: .monitorSwitchingLens, generation: generation))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
    }

    func testTimeout_monitorTakingPicture_unbecomes() async {
        await enterMonitorTakingPicture()

        let generation = await harness.coordinator.currentTimeoutGeneration()
        await harness.deliver(UICmd.StateTimeout(stateName: .monitorTakingPicture, generation: generation))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitor)
    }

    // MARK: - Send failure recovery

    func testMonitorPhotoModeToggleFlashSendFailurePopsToScanning() async {
        await enterMonitor(.Photo)
        harness.fakeMP.sendResult = Failure(error: NSError(domain: "test", code: 1))

        await harness.deliver(UICmd.ToggleFlash())

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    func testMonitorPhotoModeToggleCameraSendFailurePopsToScanning() async {
        await enterMonitor(.Photo)
        harness.fakeMP.sendResult = Failure(error: NSError(domain: "test", code: 1))

        await harness.deliver(UICmd.ToggleCamera())

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    func testMonitorPhotoModeSwitchLensSendFailurePopsToScanning() async {
        await enterMonitor(.Photo)
        harness.fakeMP.sendResult = Failure(error: NSError(domain: "test", code: 1))

        await harness.deliver(UICmd.SwitchLens(lensType: .telephoto))

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    func testMonitorVideoModeStartRecordingSendFailurePopsToScanning() async {
        await enterMonitor(.Video)
        harness.fakeMP.sendResult = Failure(error: NSError(domain: "test", code: 1))

        await harness.deliver(UICmd.TakePicture(sender: nil, sendMediaToRemote: true))

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    func testMonitorRecordingVideoOnEnterShowsRecordingUI() async {
        await enterMonitor(.Video)
        await harness.deliver(UICmd.TakePicture(sender: nil, sendMediaToRemote: true))

        let name = await harness.stateName()
        XCTAssertEqual(name, .monitorRecordingVideo)
    }

    func testMonitorPhotoModeTakePictureSendFailurePopsToScanning() async {
        await enterMonitor(.Photo)
        harness.fakeMP.sendResult = Failure(error: NSError(domain: "test", code: 1))

        await harness.deliver(UICmd.TakePicture(sender: nil, sendMediaToRemote: true))

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    func testSendFailureTriggersPopToScanning() async {
        await seedConnected()
        harness.fakeMP.sentMessages.removeAll()
        harness.fakeMP.sendResult = Failure(error: NSError(domain: "test", code: 1))

        // OnEnter's RequestFrame send fails → pop to scanning.
        await harness.deliver(UICmd.BecomeMonitor(presenter: presenter, mode: .Photo))

        let name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
    }

    // MARK: - Camera taking pic: timeout with send failure

    func testCameraTakingPicTimeoutSendFailurePopsToScanning() async {
        await enterCamera()
        await harness.deliver(RemoteCmd.TakePic(sender: nil, sendMediaToPeer: true))
        var name = await harness.stateName()
        XCTAssertEqual(name, .cameraTakingPic)

        harness.fakeMP.sendResult = Failure(error: NSError(domain: "test", code: 1))
        let generation = await harness.coordinator.currentTimeoutGeneration()
        await harness.deliver(UICmd.StateTimeout(stateName: .cameraTakingPic, generation: generation))

        name = await harness.stateName()
        XCTAssertEqual(name, .scanning)
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

    /// A peer disconnect leaves stragglers in flight, and every one of them
    /// fails to send. Discovery must restart exactly once — not once per
    /// failed straggler (the old behavior re-entered scanning per failure,
    /// resetting the lobby UI and re-arming the connection-error alert).
    func testFailedSendStormRestartsScanningOnce() async {
        await harness.coordinator.seed(state: .monitor(mode: .photo),
                                       lobby: harness.lobbyWrapper,
                                       peer: harness.peer)

        // The peer is gone: every send fails. Each straggler command reaches
        // the root handler, synthesizes an error response, and fails to send it.
        harness.fakeMP.sendResult = Failure(error: NSError(domain: "peer gone", code: 0))
        for _ in 0..<5 {
            await harness.deliver(RemoteCmd.TakePic(sender: nil, sendMediaToPeer: false))
        }

        let state = await harness.stateName()
        XCTAssertEqual(state, .scanning)
        XCTAssertEqual(harness.lobby.returnsToLobby, 1,
                       "straggler failures after the pop must not restart discovery again")
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
        XCTAssertEqual(state, .scanning, "the machine drops to scanning as always")
    }

    func testSuspendedDisconnectDropsToScanningAndMonitorRetries() async {
        harness.lobby.role = .monitor
        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))

        let state = await harness.stateName()
        XCTAssertEqual(state, .scanning)
        let stillWaiting = await isReconnecting()
        XCTAssertTrue(stillWaiting, "the overlay survives the drop to scanning")

        await awaitRetryTick()
        XCTAssertEqual(harness.fakeMP.invitedPeers.first?.peer, harness.peer,
                       "the retry loop re-invites the suspended peer")

        // A failed attempt surfaces as DisconnectPeer — the loop re-arms.
        let invitesSoFar = harness.fakeMP.invitedPeers.count
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))
        await awaitRetryTick()
        XCTAssertGreaterThan(harness.fakeMP.invitedPeers.count, invitesSoFar,
                             "retries continue with no attempt cap")

        // Reconnection ends the loop and dismisses the dialog.
        await harness.deliver(OnConnectToDevice(peer: harness.peer, sender: nil))
        let cleared = await isReconnecting()
        XCTAssertFalse(cleared, "reconnected ⇒ no overlay")
        let finalState = await harness.stateName()
        XCTAssertEqual(finalState, .connected)
    }

    /// Device bug: the 1 s tick called invitePeer every second, and
    /// invitePeer rebuilds the session — tearing down the QUIC handshake
    /// that was still completing. The dial never got its couple of seconds,
    /// so the pair churned "Connecting…/Not Connected" forever.
    func testRetryDoesNotRestartAnAttemptInFlight() async {
        harness.lobby.role = .monitor
        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))

        await awaitRetryTick()
        XCTAssertEqual(harness.fakeMP.invitedPeers.count, 1, "one attempt starts")

        // Ticks while that attempt is still running must not re-invite.
        await awaitRetryTick()
        await awaitRetryTick()
        XCTAssertEqual(harness.fakeMP.invitedPeers.count, 1,
                       "an in-flight handshake is left alone")

        // Only its failure frees the next attempt.
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))
        await awaitRetryTick()
        XCTAssertEqual(harness.fakeMP.invitedPeers.count, 2,
                       "the loop continues once the attempt is over")
    }

    func testCameraRoleWaitsWithoutInviting() async {
        harness.lobby.role = .camera
        harness.fakeMP.connectedPeers = []
        await harness.deliver(DisconnectPeer(peer: harness.peer, sender: nil))
        await awaitRetryTick()

        XCTAssertTrue(harness.fakeMP.invitedPeers.isEmpty,
                      "only the monitor invites; the camera advertises and waits")
        XCTAssertTrue(harness.fakeMP.startAdvertisingAndBrowsingCalled,
                      "scanning re-entry restarted the radios")
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
        await harness.deliver(Disconnect(sender: nil))

        let announced = harness.fakeMP.sentMessages.contains { $0.msg is RemoteCmd.EndSession }
        XCTAssertTrue(announced, "the peer must be told before we tear down")
    }

    /// The back button's real path: the monitor screen pops, the scanner's
    /// viewDidAppear sends Disconnect, and the camera must hear about it from
    /// whatever state the user was in.
    func testBackButtonFromMonitorAnnouncesTheExit() async {
        let presenter = MonitorPresenter()
        await harness.deliver(UICmd.BecomeMonitor(presenter: presenter, mode: .Photo))
        harness.fakeMP.sentMessages.removeAll()

        await harness.deliver(Disconnect(sender: nil))

        let announced = harness.fakeMP.sentMessages.contains { $0.msg is RemoteCmd.EndSession }
        XCTAssertTrue(announced, "leaving the monitor screen must tell the camera")
        let state = await harness.stateName()
        XCTAssertEqual(state, .scanning)
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
            bundleVersion: VP9PreviewCompatibility.minimumPeerBundleVersion,
            shortVersion: "\(local.major + 1).0.0",
            platform: "iPhone"))

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
}
