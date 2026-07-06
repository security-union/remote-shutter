//
//  RemoteCamSessionTests.swift
//  RemoteShutterTests
//
//  Created by Tests on 3/1/26.
//

import XCTest
import MultipeerConnectivity
import Combine

@testable import RemoteShutter

// MARK: - Fake MultipeerService

class FakeMultipeerService: MultipeerServiceProtocol {
    weak var delegate: MultipeerServiceDelegate?
    var session: MCSession!
    var connectedPeers: [MCPeerID] = []
    var progressCancellables = Set<AnyCancellable>()

    // Recording
    var sentMessages: [(msg: Actor.Message, peers: [MCPeerID], mode: MCSessionSendDataMode)] = []
    var stopSessionCalled = false
    var disconnectCalled = false
    var startAdvertisingAndBrowsingCalled = false
    var stopAdvertisingAndBrowsingCalled = false
    var invitedPeers: [(peer: MCPeerID, timeout: TimeInterval)] = []
    var sendResult: Try<Actor.Message> = Failure(error: NSError(domain: "test", code: 0))

    func startAdvertisingAndBrowsing() { startAdvertisingAndBrowsingCalled = true }
    func startAdvertisingOnly(discoveryInfo: [String: String]?) { startAdvertisingAndBrowsingCalled = true }
    func startBrowsingOnly() { startAdvertisingAndBrowsingCalled = true }
    func stopAdvertisingAndBrowsing() { stopAdvertisingAndBrowsingCalled = true }
    func disconnect() { disconnectCalled = true }
    func stopSession() { stopSessionCalled = true }
    func invitePeer(_ peer: MCPeerID, timeout: TimeInterval) {
        invitedPeers.append((peer, timeout))
    }
    func send(_ msg: Actor.Message, to peers: [MCPeerID],
              mode: MCSessionSendDataMode) -> Try<Actor.Message> {
        sentMessages.append((msg, peers, mode))
        return sendResult
    }
    func sendResource(at url: URL, withName name: String,
                      toPeer peer: MCPeerID,
                      completion: @escaping (Error?) -> Void) -> Progress? { return nil }
}

// MARK: - Fake AlertPresenter

class FakeAlertHandle: AlertHandle {
    var currentTitle: String?
    var dismissed = false
    init(title: String) { self.currentTitle = title }
}

class FakeAlertPresenter: AlertPresenting {
    var shownAlerts: [FakeAlertHandle] = []
    var shownErrors: [String] = []

    func showAlert(title: String) -> AlertHandle {
        let h = FakeAlertHandle(title: title)
        shownAlerts.append(h)
        return h
    }
    func updateAlert(_ handle: AlertHandle, title: String) {
        (handle as? FakeAlertHandle)?.currentTitle = title
    }
    func dismissAlert(_ handle: AlertHandle) {
        (handle as? FakeAlertHandle)?.dismissed = true
    }
    func showError(title: String) {
        shownErrors.append(title)
    }
}

// MARK: - Testable Subclass

class TestableRemoteCamSession: RemoteCamSession {

    override func startScanning(lobby: ScannerLobby) {
        // no-op — avoids MultipeerService creation and UI code
    }
}

// MARK: - Fake ScannerLobby

/// Plain fake for the session's lobby seam — no UIKit involved.
class FakeScannerLobby: ScannerLobby {
    let peerID = MCPeerID(displayName: "FakeLobby")
    var role: DeviceRole = .monitor
    let scannerViewModel = DeviceScannerViewModel()

    var roleScreenShown = 0
    var returnsToLobby = 0
    var scanningErrors = 0

    func goToRole() { roleScreenShown += 1 }
    func returnToLobby() { returnsToLobby += 1 }
    func presentScanningError() { scanningErrors += 1 }
}

// MARK: - Test Helpers

/// Queues a fulfillment operation on the actor's serial mailbox so that
/// all prior messages (including OnEnter) are fully processed before assertions run.
func waitForMailbox(_ session: TestableRemoteCamSession, test: XCTestCase) {
    let expectation = test.expectation(description: "mailbox drained")
    session.mailbox.addOperation { expectation.fulfill() }
    test.wait(for: [expectation], timeout: 5.0)
}

// MARK: - Tests

class RemoteCamSessionTests: XCTestCase {

    private var system: TestActorSystem!
    private var ref: ActorRef!
    private var session: TestableRemoteCamSession!
    private var peer: MCPeerID!
    private var fakeMP: FakeMultipeerService!
    private var fakeAlerts: FakeAlertPresenter!

    private var lobby: FakeScannerLobby!
    private var lobbyWrapper: WeakScannerLobby!

    override func setUp() {
        super.setUp()

        system = TestActorSystem(name: "test")
        ref = system.actorOf(clz: TestableRemoteCamSession.self, name: "session")
        session = system.actorForRef(ref: ref!) as! TestableRemoteCamSession
        peer = MCPeerID(displayName: "TestPeer")

        lobby = FakeScannerLobby()
        lobbyWrapper = WeakScannerLobby(lobby)

        fakeMP = FakeMultipeerService()
        fakeMP.connectedPeers = [peer]
        fakeMP.sendResult = Success(Actor.Message())
        session.multipeerService = fakeMP

        fakeAlerts = FakeAlertPresenter()
        session.alertPresenter = fakeAlerts

        waitForMailbox(session, test: self)
    }

    override func tearDown() {
        // Drain before dealloc — Theater uses [unowned self] in mailbox ops
        drainMailboxPumpingRunLoop()
        system.stop()
        drainMailboxPumpingRunLoop()
        system = nil
        ref = nil
        session = nil
        peer = nil
        fakeMP = nil
        fakeAlerts = nil
        lobby = nil
        lobbyWrapper = nil
        super.tearDown()
    }

    private func drainMailboxPumpingRunLoop() {
        let deadline = Date(timeIntervalSinceNow: 5.0)
        while session.mailbox.operationCount > 0 && Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }

    // MARK: - Helpers

    private func pushScanningState() {
        let noOpScanning: Receive = { [weak self] _ in _ = self }
        session.become(name: .scanning, state: noOpScanning)
        waitForMailbox(session, test: self)
    }

    private func pushConnectedState() {
        session.become(name: .connected,
                       state: session.connected(lobbyWrapper: lobbyWrapper, peer: peer))
        waitForMailbox(session, test: self)
    }

    private func pushMonitorPhotoModeState() {
        pushScanningState()
        pushConnectedState()
        session.become(name: .monitor,
                       state: session.monitorPhotoMode(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)
        fakeMP.sentMessages.removeAll()
    }

    private func pushMonitorVideoModeState() {
        pushScanningState()
        pushConnectedState()
        session.become(name: .monitor,
                       state: session.monitorVideoMode(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)
        fakeMP.sentMessages.removeAll()
    }

    // MARK: - Initial State

    func testInitialStateIsWaitingForCtrl() {
        XCTAssertEqual(session.currentState()?.0, session.waitingForCtrlState)
    }

    // MARK: - Connected State: Disconnect

    func testConnectedStateDisconnect() {
        pushScanningState()
        pushConnectedState()

        ref ! Disconnect(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
        XCTAssertTrue(fakeMP.sentMessages.isEmpty)
    }

    // MARK: - Connected State: BecomeMonitor (Photo)

    func testConnectedStateBecomeMonitorPhoto() {
        pushScanningState()
        pushConnectedState()

        ref ! UICmd.BecomeMonitor(ref, mode: .Photo)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor)
        XCTAssertGreaterThanOrEqual(fakeMP.sentMessages.count, 1)
        XCTAssertTrue(fakeMP.sentMessages[0].msg is RemoteCmd.PeerBecameMonitor)
        XCTAssertEqual(fakeMP.sentMessages[0].peers, [peer])
    }

    // MARK: - Connected State: BecomeMonitor (Video)

    func testConnectedStateBecomeMonitorVideo() {
        pushScanningState()
        pushConnectedState()

        ref ! UICmd.BecomeMonitor(ref, mode: .Video)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor)
        XCTAssertGreaterThanOrEqual(fakeMP.sentMessages.count, 1)
        XCTAssertTrue(fakeMP.sentMessages[0].msg is RemoteCmd.PeerBecameMonitor)
        XCTAssertEqual(fakeMP.sentMessages[0].peers, [peer])
    }

    // MARK: - Connected State: Nil Lobby Pops to Scanning

    func testConnectedStateNilLobbyPopsToScanning() {
        pushScanningState()

        let weakLobby = WeakScannerLobby(lobby!)
        session.become(name: .connected,
                       state: session.connected(lobbyWrapper: weakLobby, peer: peer))
        waitForMailbox(session, test: self)

        weakLobby.value = nil

        ref ! Disconnect(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
    }

    // MARK: - MonitorPhotoMode: OnEnter

    func testMonitorPhotoModeOnEnterRequestsFrame() {
        pushScanningState()
        pushConnectedState()

        // Push monitorPhotoMode — OnEnter sends RenderPhotoMode to monitor + RequestFrame to peer
        session.become(name: .monitor,
                       state: session.monitorPhotoMode(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)

        // OnEnter should have sent a RequestFrame via sendCommandOrGoToScanning
        let frameRequests = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.RequestFrame }
        XCTAssertEqual(frameRequests.count, 1)
        XCTAssertEqual(frameRequests[0].peers, [peer])
    }

    // MARK: - MonitorPhotoMode: UnbecomeMonitor

    func testMonitorPhotoModeUnbecomeMonitorPopsToConnected() {
        pushMonitorPhotoModeState()

        ref ! UICmd.UnbecomeMonitor(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .connected)
    }

    // MARK: - MonitorPhotoMode: Disconnect

    func testMonitorPhotoModeDisconnectPopsToScanning() throws {
        pushMonitorPhotoModeState()

        ref ! Disconnect(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
    }

    // MARK: - MonitorPhotoMode: TakePicture transitions to monitorTakingPicture
    
    func testMonitorPhotoModeTakePictureTransitions() throws {
        pushMonitorPhotoModeState()

        ref ! UICmd.TakePicture(sender: nil, sendMediaToRemote: true)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitorTakingPicture)
    }

    // MARK: - MonitorPhotoMode: ToggleFlash transitions to monitorTogglingFlash

    func testMonitorPhotoModeToggleFlashTransitions() throws {
        pushMonitorPhotoModeState()

        ref ! UICmd.ToggleFlash()
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitorTogglingFlash)
    }

    // MARK: - MonitorPhotoMode: ToggleCamera transitions to monitorTogglingCamera

    func testMonitorPhotoModeToggleCameraTransitions() throws {
        pushMonitorPhotoModeState()

        ref ! UICmd.ToggleCamera()
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitorTogglingCamera)
    }

    // MARK: - MonitorPhotoMode: Switch to Video mode

    func testMonitorPhotoModeSwitchToVideoMode() throws {
        pushMonitorPhotoModeState()

        ref ! UICmd.BecomeMonitor(ref, mode: .Video)
        waitForMailbox(session, test: self)

        // Should have replaced the current state — still named .monitor so popToState(.monitor) works
        XCTAssertEqual(session.currentStateName(), .monitor)
    }

    // MARK: - MonitorPhotoMode: ToggleTorch sends remote command

    func testMonitorPhotoModeToggleTorchSendsCommand() throws {
        pushMonitorPhotoModeState()

        ref ! UICmd.ToggleTorch()
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor)
        let torchMessages = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.ToggleTorch }
        XCTAssertEqual(torchMessages.count, 1)
    }

    // MARK: - MonitorPhotoMode: RequestCameraCapabilities

    func testMonitorPhotoModeRequestCameraCapabilities() throws {
        pushMonitorPhotoModeState()

        ref ! UICmd.RequestCameraCapabilities()
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor)
        let capRequests = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.RequestCameraCapabilities }
        XCTAssertEqual(capRequests.count, 1)
    }

    // MARK: - MonitorVideoMode: OnEnter

    func testMonitorVideoModeOnEnterRequestsFrame() throws {
        pushScanningState()
        pushConnectedState()

        session.become(name: .monitor,
                       state: session.monitorVideoMode(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)

        let frameRequests = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.RequestFrame }
        XCTAssertEqual(frameRequests.count, 1)
    }

    // MARK: - MonitorVideoMode: Switch to Photo mode

    func testMonitorVideoModeSwitchToPhotoMode() throws {
        pushMonitorVideoModeState()

        ref ! UICmd.BecomeMonitor(ref, mode: .Photo)
        waitForMailbox(session, test: self)

        // Still named .monitor so popToState(.monitor) works
        XCTAssertEqual(session.currentStateName(), .monitor)
    }

    // MARK: - MonitorVideoMode: Disconnect

    func testMonitorVideoModeDisconnectPopsToScanning() throws {
        pushMonitorVideoModeState()

        ref ! Disconnect(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
    }

    // MARK: - MonitorVideoMode: UnbecomeMonitor

    func testMonitorVideoModeUnbecomeMonitorPopsToConnected() throws {
        pushMonitorVideoModeState()

        ref ! UICmd.UnbecomeMonitor(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .connected)
    }

    // MARK: - MonitorPhotoMode: SwitchLens transitions to monitorSwitchingLens

    func testMonitorPhotoModeSwitchLensTransitions() throws {
        pushMonitorPhotoModeState()

        ref ! UICmd.SwitchLens(lensType: .telephoto)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitorSwitchingLens)
    }

    // MARK: - MonitorPhotoMode: SetZoom sends remote command

    func testMonitorPhotoModeSetZoomSendsCommand() throws {
        pushMonitorPhotoModeState()

        ref ! UICmd.SetZoom(zoomFactor: 2.0)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor)
        let zoomMessages = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.SetZoom }
        XCTAssertEqual(zoomMessages.count, 1)
    }

    // MARK: - MonitorPhotoMode: PeerBecameCamera requests capabilities

    func testMonitorPhotoModePeerBecameCameraRequestsCapabilities() throws {
        pushMonitorPhotoModeState()

        ref ! RemoteCmd.PeerBecameCamera.createWithDefaults()
        waitForMailbox(session, test: self)
        waitForMailbox(session, test: self) // drain any follow-up mailbox ops

        XCTAssertEqual(session.currentStateName(), .monitor)
        let capRequests = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.RequestCameraCapabilities }
        XCTAssertEqual(capRequests.count, 1)
    }

    // MARK: - MonitorPhotoMode: DisconnectPeer pops to scanning

    func testMonitorPhotoModeDisconnectPeerPopsToScanning() throws {
        pushMonitorPhotoModeState()

        // Simulate MCSession removing the peer before the DisconnectPeer message arrives
        fakeMP.connectedPeers = []
        ref ! DisconnectPeer(peer: peer, sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
    }

    // MARK: - MonitorVideoMode: TakePicture starts recording and transitions

    func testMonitorVideoModeTakePictureStartsRecording() throws {
        pushMonitorVideoModeState()

        ref ! UICmd.TakePicture(sender: nil, sendMediaToRemote: true)
        waitForMailbox(session, test: self)

        let startMsgs = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.StartRecordingVideo }
        XCTAssertEqual(startMsgs.count, 1)
        XCTAssertEqual(session.currentStateName(), .monitorRecordingVideo)
    }

    // MARK: - MonitorVideoMode: ToggleCamera transitions

    func testMonitorVideoModeToggleCameraTransitions() throws {
        pushMonitorVideoModeState()

        ref ! UICmd.ToggleCamera()
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitorTogglingCamera)
    }

    // MARK: - MonitorVideoMode: ToggleTorch sends command

    func testMonitorVideoModeToggleTorchSendsCommand() throws {
        pushMonitorVideoModeState()

        ref ! UICmd.ToggleTorch()
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor)
        let torchMessages = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.ToggleTorch }
        XCTAssertEqual(torchMessages.count, 1)
    }

    // MARK: - MonitorVideoMode: SwitchLens transitions

    func testMonitorVideoModeSwitchLensTransitions() throws {
        pushMonitorVideoModeState()

        ref ! UICmd.SwitchLens(lensType: .ultraWide)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitorSwitchingLens)
    }

    // MARK: - MonitorVideoMode: SetZoom sends command

    func testMonitorVideoModeSetZoomSendsCommand() throws {
        pushMonitorVideoModeState()

        ref ! UICmd.SetZoom(zoomFactor: 3.0)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor)
        let zoomMessages = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.SetZoom }
        XCTAssertEqual(zoomMessages.count, 1)
    }

    // MARK: - MonitorVideoMode: RequestCameraCapabilities sends request

    func testMonitorVideoModeRequestCameraCapabilities() throws {
        pushMonitorVideoModeState()

        ref ! UICmd.RequestCameraCapabilities()
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor)
        let capRequests = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.RequestCameraCapabilities }
        XCTAssertEqual(capRequests.count, 1)
    }

    // MARK: - MonitorVideoMode: PeerBecameCamera requests capabilities

    func testMonitorVideoModePeerBecameCameraRequestsCapabilities() throws {
        pushMonitorVideoModeState()

        ref ! RemoteCmd.PeerBecameCamera.createWithDefaults()
        waitForMailbox(session, test: self)
        waitForMailbox(session, test: self) // drain any follow-up mailbox ops

        XCTAssertEqual(session.currentStateName(), .monitor)
        let capRequests = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.RequestCameraCapabilities }
        XCTAssertEqual(capRequests.count, 1)
    }

    // MARK: - MonitorVideoMode: DisconnectPeer pops to scanning

    func testMonitorVideoModeDisconnectPeerPopsToScanning() throws {
        pushMonitorVideoModeState()

        fakeMP.connectedPeers = []
        ref ! DisconnectPeer(peer: peer, sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
    }

    // MARK: - MonitorTakingPicture Helpers

    private func pushMonitorTakingPictureState() {
        pushMonitorPhotoModeState()
        session.become(name: .monitorTakingPicture,
                       state: session.monitorTakingPicture(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)
        fakeMP.sentMessages.removeAll()
    }

    // MARK: - MonitorTakingPicture: TakePicResp with error unbecomes

    func testMonitorTakingPictureTakePicRespWithErrorUnbecomes() throws {
        pushMonitorTakingPictureState()

        let error = NSError(domain: "TestError", code: 42, userInfo: nil)
        ref ! RemoteCmd.TakePicResp(sender: nil, error: error)
        waitForMailbox(session, test: self)

        // unbecome() pops monitorTakingPicture → back to monitorPhotoMode
        XCTAssertEqual(session.currentStateName(), .monitor)
    }

    // MARK: - MonitorTakingPicture: TakePicResp with picture unbecomes

    func testMonitorTakingPictureTakePicRespWithPicUnbecomes() throws {
        pushMonitorTakingPictureState()

        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0]) // minimal JPEG header
        ref ! RemoteCmd.TakePicResp(sender: nil, pic: imageData)
        waitForMailbox(session, test: self)

        // unbecome() pops monitorTakingPicture → back to monitorPhotoMode
        XCTAssertEqual(session.currentStateName(), .monitor)
    }

    // MARK: - MonitorTakingPicture: TakePicAck forwards to peer

    func testMonitorTakingPictureTakePicAckForwardsToPeer() throws {
        pushMonitorTakingPictureState()

        ref ! RemoteCmd.TakePicAck(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitorTakingPicture)
        let ackMessages = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.TakePicAck }
        XCTAssertEqual(ackMessages.count, 1)
        XCTAssertEqual(ackMessages[0].peers, [peer])
    }

    // MARK: - MonitorRecordingVideo Helpers

    /// Pushes the monitorRecordingVideo state.
    /// Uses "monitor" as the name for the video mode state to match production
    /// (see RemoteCamConnected.swift where BecomeMonitor pushes with states.monitor).
    private func pushMonitorRecordingVideoState() {
        pushScanningState()
        pushConnectedState()
        session.become(name: .monitor,
                       state: session.monitorVideoMode(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)
        session.become(name: .monitorRecordingVideo,
                       state: session.monitorRecordingVideo(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)
        fakeMP.sentMessages.removeAll()
    }

    // MARK: - MonitorRecordingVideo: OnEnter sends RenderVideoModeRecording + RequestFrame

    func testMonitorRecordingVideoOnEnter() throws {
        pushScanningState()
        pushConnectedState()
        session.become(name: .monitorVideoMode,
                       state: session.monitorVideoMode(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)
        fakeMP.sentMessages.removeAll()

        session.become(name: .monitorRecordingVideo,
                       state: session.monitorRecordingVideo(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)

        let frameRequests = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.RequestFrame }
        XCTAssertEqual(frameRequests.count, 1)
    }

    // MARK: - MonitorRecordingVideo: StartRecordingVideoAck with error pops to video mode

    func testMonitorRecordingVideoStartAckWithErrorPopsToVideoMode() throws {
        pushMonitorRecordingVideoState()

        let error = NSError(domain: "TestError", code: 1, userInfo: nil)
        ref ! RemoteCmd.StartRecordingVideoAck(sender: nil, recordingStartTime: nil, error: error)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor)
    }

    // MARK: - MonitorRecordingVideo: TakePicture sends StopRecordingVideo

    func testMonitorRecordingVideoTakePictureSendsStopRecording() throws {
        pushMonitorRecordingVideoState()

        ref ! UICmd.TakePicture(sender: nil, sendMediaToRemote: true)
        waitForMailbox(session, test: self)

        let stopMsgs = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.StopRecordingVideo }
        XCTAssertEqual(stopMsgs.count, 1)
        XCTAssertEqual(session.currentStateName(), .monitorRecordingVideo)
    }

    // MARK: - MonitorRecordingVideo: StopRecordingVideoAck transitions to monitorWaitingForVideo

    func testMonitorRecordingVideoStopAckTransitionsToWaiting() throws {
        pushMonitorRecordingVideoState()

        ref ! RemoteCmd.StopRecordingVideoAck()
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitorWaitingForVideo)
    }

    // MARK: - MonitorRecordingVideo: StopRecordingVideoResp with error pops to video mode

    func testMonitorRecordingVideoStopRespWithErrorPopsToVideoMode() throws {
        pushMonitorRecordingVideoState()

        let error = NSError(domain: "TestError", code: 2, userInfo: nil)
        ref ! RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: error)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor)
    }

    // MARK: - MonitorRecordingVideo: Disconnect pops to scanning

    func testMonitorRecordingVideoDisconnectPopsToScanning() throws {
        pushMonitorRecordingVideoState()

        ref ! Disconnect(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
    }

    // MARK: - MonitorRecordingVideo: DisconnectPeer pops to scanning

    func testMonitorRecordingVideoDisconnectPeerPopsToScanning() throws {
        pushMonitorRecordingVideoState()

        fakeMP.connectedPeers = []
        ref ! DisconnectPeer(peer: peer, sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
    }

    // MARK: - MonitorRecordingVideo: UnbecomeMonitor pops to connected

    func testMonitorRecordingVideoUnbecomeMonitorPopsToConnected() throws {
        pushMonitorRecordingVideoState()

        ref ! UICmd.UnbecomeMonitor(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .connected)
    }

    // MARK: - MonitorWaitingForVideo Helpers

    private func pushMonitorWaitingForVideoState() {
        pushMonitorRecordingVideoState()
        session.become(name: .monitorWaitingForVideo,
                       state: session.monitorWaitingForVideo(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)
        fakeMP.sentMessages.removeAll()
    }

    // MARK: - MonitorWaitingForVideo: StopRecordingVideoResp pops to video mode

    func testMonitorWaitingForVideoStopRespPopsToVideoMode() throws {
        pushMonitorWaitingForVideoState()

        ref ! RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor)
    }

    // MARK: - MonitorWaitingForVideo: Disconnect pops to scanning

    func testMonitorWaitingForVideoDisconnectPopsToScanning() throws {
        pushMonitorWaitingForVideoState()

        ref ! Disconnect(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
    }

    // MARK: - MonitorWaitingForVideo: DisconnectPeer pops to scanning

    func testMonitorWaitingForVideoDisconnectPeerPopsToScanning() throws {
        pushMonitorWaitingForVideoState()

        fakeMP.connectedPeers = []
        ref ! DisconnectPeer(peer: peer, sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
    }

    // MARK: - Connected: DisconnectPeer pops to scanning when no peers

    func testConnectedStateDisconnectPeerPopsToScanning() throws {
        pushScanningState()
        pushConnectedState()

        fakeMP.connectedPeers = []
        ref ! DisconnectPeer(peer: peer, sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
    }

    // MARK: - FakeMultipeerService: Connected sends PeerBecameMonitor

    func testConnectedStateBecomeMonitorSendsPeerBecameMonitor() throws {
        pushScanningState()
        pushConnectedState()
        fakeMP.sentMessages.removeAll()

        // BecomeCamera requires CameraViewController; verify via BecomeMonitor instead
        ref ! UICmd.BecomeMonitor(ref, mode: .Photo)
        waitForMailbox(session, test: self)

        let becameMonitor = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.PeerBecameMonitor }
        XCTAssertEqual(becameMonitor.count, 1)
        XCTAssertEqual(becameMonitor[0].peers, [peer])
        XCTAssertEqual(becameMonitor[0].mode, .reliable)
    }

    // MARK: - FakeMultipeerService: MonitorPhotoMode RequestFrame uses reliable mode

    func testMonitorPhotoModeRequestFrameUsesReliableMode() throws {
        pushScanningState()
        pushConnectedState()
        fakeMP.sentMessages.removeAll()

        session.become(name: .monitor,
                       state: session.monitorPhotoMode(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)

        let frameRequests = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.RequestFrame }
        XCTAssertEqual(frameRequests.count, 1)
        XCTAssertEqual(frameRequests[0].mode, .reliable)
    }

    // MARK: - FakeMultipeerService: Send failure triggers pop to scanning

    func testSendFailureTriggersPopToScanning() throws {
        pushScanningState()
        pushConnectedState()
        fakeMP.sentMessages.removeAll()

        fakeMP.sendResult = Failure(error: NSError(domain: "test", code: 1))

        // OnEnter's sendCommandOrGoToScanning(RequestFrame) will fail
        session.become(name: .monitor,
                       state: session.monitorPhotoMode(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
    }

    // MARK: - FakeMultipeerService: MonitorVideoMode StartRecordingVideo sent to peer

    func testMonitorVideoModeStartRecordingVideoSentToPeer() throws {
        pushMonitorVideoModeState()

        ref ! UICmd.TakePicture(sender: nil, sendMediaToRemote: true)
        waitForMailbox(session, test: self)

        let startMsgs = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.StartRecordingVideo }
        XCTAssertEqual(startMsgs.count, 1)
        XCTAssertEqual(startMsgs[0].peers, [peer])
        XCTAssertEqual(startMsgs[0].mode, .reliable)
    }

    // MARK: - FakeMultipeerService: MonitorRecordingVideo StopRecordingVideo sent to peer

    func testMonitorRecordingVideoStopRecordingVideoSentToPeer() throws {
        pushMonitorRecordingVideoState()

        ref ! UICmd.TakePicture(sender: nil, sendMediaToRemote: false)
        waitForMailbox(session, test: self)

        let stopMsgs = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.StopRecordingVideo }
        XCTAssertEqual(stopMsgs.count, 1)
        XCTAssertEqual(stopMsgs[0].peers, [peer])
        XCTAssertEqual(stopMsgs[0].mode, .reliable)
    }

    // MARK: - MonitorTogglingFlash Helpers

    private func pushMonitorTogglingFlashState() {
        pushMonitorPhotoModeState()
        session.become(name: .monitorTogglingFlash,
                       state: session.monitorTogglingFlash(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)
        fakeMP.sentMessages.removeAll()
        fakeAlerts.shownAlerts.removeAll()
        fakeAlerts.shownErrors.removeAll()
    }

    // MARK: - MonitorTogglingFlash: duplicate tap ignored, response unbecomes

    func testMonitorTogglingFlashIgnoresDuplicateTap() throws {
        pushMonitorTogglingFlashState()

        ref ! UICmd.ToggleFlash()
        waitForMailbox(session, test: self)

        let toggleMsgs = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.ToggleFlash }
        XCTAssertEqual(toggleMsgs.count, 0)
        XCTAssertEqual(session.currentStateName(), .monitorTogglingFlash)
    }

    func testMonitorTogglingFlashSuccessResponseUnbecomes() throws {
        pushMonitorTogglingFlashState()

        ref ! RemoteCmd.ToggleFlashResp(flashMode: .on, error: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor)
    }

    func testMonitorTogglingFlashErrorResponseUnbecomes() throws {
        pushMonitorTogglingFlashState()

        let error = NSError(domain: "FlashError", code: 1, userInfo: nil)
        ref ! RemoteCmd.ToggleFlashResp(flashMode: nil, error: error)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor)
    }

    func testMonitorTogglingFlashNilNilResponseUnbecomes() throws {
        pushMonitorTogglingFlashState()

        ref ! RemoteCmd.ToggleFlashResp(flashMode: nil, error: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor,
                       "State should unbecome even when both flashMode and error are nil")
    }

    func testMonitorTogglingFlashDisconnectPopsToScanning() throws {
        pushMonitorTogglingFlashState()

        ref ! Disconnect(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
    }

    func testMonitorTogglingFlashDisconnectPeerPopsToScanning() throws {
        pushMonitorTogglingFlashState()

        fakeMP.connectedPeers = []
        ref ! DisconnectPeer(peer: peer, sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
    }

    func testMonitorTogglingFlashUnbecomeMonitorPopsToConnected() throws {
        pushMonitorTogglingFlashState()

        ref ! UICmd.UnbecomeMonitor(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .connected)
    }

    // MARK: - MonitorTogglingCamera Helpers

    private func pushMonitorTogglingCameraState() {
        pushMonitorPhotoModeState()
        session.become(name: .monitorTogglingCamera,
                       state: session.monitorTogglingCamera(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)
        fakeMP.sentMessages.removeAll()
        fakeAlerts.shownAlerts.removeAll()
        fakeAlerts.shownErrors.removeAll()
    }

    // MARK: - MonitorTogglingCamera: duplicate tap ignored, response unbecomes

    func testMonitorTogglingCameraIgnoresDuplicateTap() throws {
        pushMonitorTogglingCameraState()

        ref ! UICmd.ToggleCamera()
        waitForMailbox(session, test: self)

        let toggleMsgs = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.ToggleCamera }
        XCTAssertEqual(toggleMsgs.count, 0)
        XCTAssertEqual(session.currentStateName(), .monitorTogglingCamera)
    }

    func testMonitorTogglingCameraSuccessResponseUnbecomes() throws {
        pushMonitorTogglingCameraState()

        let capabilities = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, currentLens: .wideAngle, currentZoom: 1.0, error: nil)
        ref ! RemoteCmd.ToggleCameraResp(cameraCapabilities: capabilities, error: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor)
    }

    func testMonitorTogglingCameraErrorResponseUnbecomes() throws {
        pushMonitorTogglingCameraState()

        let error = NSError(domain: "CameraError", code: 1, userInfo: nil)
        ref ! RemoteCmd.ToggleCameraResp(cameraCapabilities: nil, error: error)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor)
    }

    func testMonitorTogglingCameraNilNilResponseUnbecomes() throws {
        pushMonitorTogglingCameraState()

        ref ! RemoteCmd.ToggleCameraResp(cameraCapabilities: nil, error: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor,
                       "State should unbecome even when both capabilities and error are nil")
    }

    func testMonitorTogglingCameraDisconnectPopsToScanning() throws {
        pushMonitorTogglingCameraState()

        ref ! Disconnect(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
    }

    func testMonitorTogglingCameraDisconnectPeerPopsToScanning() throws {
        pushMonitorTogglingCameraState()

        fakeMP.connectedPeers = []
        ref ! DisconnectPeer(peer: peer, sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
    }

    func testMonitorTogglingCameraUnbecomeMonitorPopsToConnected() throws {
        pushMonitorTogglingCameraState()

        ref ! UICmd.UnbecomeMonitor(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .connected)
    }

    // MARK: - MonitorSwitchingLens Helpers

    private func pushMonitorSwitchingLensState() {
        pushMonitorPhotoModeState()
        session.become(name: .monitorSwitchingLens,
                       state: session.monitorSwitchingLens(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)
        fakeMP.sentMessages.removeAll()
        fakeAlerts.shownAlerts.removeAll()
        fakeAlerts.shownErrors.removeAll()
    }

    // MARK: - MonitorSwitchingLens: duplicate tap ignored, response unbecomes

    func testMonitorSwitchingLensIgnoresDuplicateTap() throws {
        pushMonitorSwitchingLensState()

        ref ! UICmd.SwitchLens(lensType: .telephoto)
        waitForMailbox(session, test: self)

        let switchMsgs = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.SwitchLens }
        XCTAssertEqual(switchMsgs.count, 0)
        XCTAssertEqual(session.currentStateName(), .monitorSwitchingLens)
    }

    func testMonitorSwitchingLensSuccessResponseUnbecomes() throws {
        pushMonitorSwitchingLensState()

        ref ! RemoteCmd.SwitchLensResp(lensType: .telephoto, availableLenses: [.wideAngle, .telephoto], currentZoom: 2.0, zoomRange: RemoteCmd.ZoomRange(minZoom: 1.0, maxZoom: 10.0), error: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor)
    }

    func testMonitorSwitchingLensErrorResponseUnbecomes() throws {
        pushMonitorSwitchingLensState()

        let error = NSError(domain: "LensError", code: 1, userInfo: nil)
        ref ! RemoteCmd.SwitchLensResp(lensType: nil, availableLenses: nil, currentZoom: nil, zoomRange: nil, error: error)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor)
    }

    func testMonitorSwitchingLensNilNilResponseUnbecomes() throws {
        pushMonitorSwitchingLensState()

        ref ! RemoteCmd.SwitchLensResp(lensType: nil, availableLenses: nil, currentZoom: nil, zoomRange: nil, error: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor,
                       "State should unbecome even when both lensType and error are nil")
    }

    func testMonitorSwitchingLensDisconnectPeerPopsToScanning() throws {
        pushMonitorSwitchingLensState()

        fakeMP.connectedPeers = []
        ref ! DisconnectPeer(peer: peer, sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
    }

    func testMonitorSwitchingLensDisconnectPopsToScanning() throws {
        pushMonitorSwitchingLensState()

        ref ! Disconnect(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
    }

    func testMonitorSwitchingLensUnbecomeMonitorPopsToConnected() throws {
        pushMonitorSwitchingLensState()

        ref ! UICmd.UnbecomeMonitor(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .connected)
    }

    // MARK: - MonitorTakingPicture: TakePicture sends command directly

    func testMonitorTakingPictureTakePictureSendsCommand() throws {
        pushMonitorTakingPictureState()

        ref ! UICmd.TakePicture(sender: nil, sendMediaToRemote: true)
        waitForMailbox(session, test: self)

        let takePicMsgs = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.TakePic }
        XCTAssertEqual(takePicMsgs.count, 1)
        XCTAssertEqual(session.currentStateName(), .monitorTakingPicture)
    }

    // MARK: - MonitorTakingPicture: TakePicAck updates alert title

    func testMonitorTakingPictureTakePicAckUpdatesTitle() throws {
        pushMonitorTakingPictureState()

        ref ! RemoteCmd.TakePicAck(sender: nil)
        waitForMailbox(session, test: self)

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1)) // pump ^{} dispatches

        let updatedHandles = fakeAlerts.shownAlerts.filter { $0.currentTitle == "Receiving picture" }
        XCTAssertEqual(updatedHandles.count, 1)
    }

    // MARK: - MonitorTakingPicture: TakePicResp error shows error alert

    func testMonitorTakingPictureTakePicRespErrorShowsErrorAlert() throws {
        pushMonitorTakingPictureState()

        let error = NSError(domain: "PicError", code: 1, userInfo: nil)
        ref ! RemoteCmd.TakePicResp(sender: nil, error: error)
        waitForMailbox(session, test: self)

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        XCTAssertEqual(session.currentStateName(), .monitor)
        XCTAssertTrue(fakeAlerts.shownErrors.contains("PicError"))
    }

    // MARK: - MonitorTakingPicture: Disconnect pops to scanning

    func testMonitorTakingPictureDisconnectPopsToScanning() throws {
        pushMonitorTakingPictureState()

        ref ! Disconnect(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
    }

    // MARK: - MonitorTakingPicture: UnbecomeMonitor pops to connected

    func testMonitorTakingPictureUnbecomeMonitorPopsToConnected() throws {
        pushMonitorTakingPictureState()

        ref ! UICmd.UnbecomeMonitor(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .connected)
    }

    // MARK: - Recording transition

    /// Verifies monitor transitions to recording only after successful send.
    func testMonitorVideoModeTransitionsToRecordingAfterSend() throws {
        pushMonitorVideoModeState()

        ref ! UICmd.TakePicture(sender: nil, sendMediaToRemote: true)
        waitForMailbox(session, test: self)

        let startMsgs = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.StartRecordingVideo }
        XCTAssertEqual(startMsgs.count, 1)
        XCTAssertEqual(session.currentStateName(), .monitorRecordingVideo)
    }

    /// Verifies popToState(.monitor) finds the video mode state after error ack.
    func testMonitorRecordingVideoErrorAckPopsToMonitor() throws {
        pushMonitorVideoModeState()

        ref ! UICmd.TakePicture(sender: nil, sendMediaToRemote: true)
        waitForMailbox(session, test: self)
        XCTAssertEqual(session.currentStateName(), .monitorRecordingVideo)

        let error = NSError(domain: "MicrophoneDenied", code: 1, userInfo: nil)
        ref ! RemoteCmd.StartRecordingVideoAck(sender: nil, recordingStartTime: nil, error: error)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor)
    }

    /// Verifies production pushes video mode with name .monitor (not .monitorVideoMode).
    func testVideoModePushedWithMonitorStateName() throws {
        pushMonitorVideoModeState()
        XCTAssertEqual(session.currentStateName(), .monitor)
    }

    // MARK: - Send-before-become pattern

    func testMonitorPhotoModeToggleCameraSendsBeforeTransition() throws {
        pushMonitorPhotoModeState()

        ref ! UICmd.ToggleCamera()
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitorTogglingCamera)
        let toggleMsgs = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.ToggleCamera }
        XCTAssertEqual(toggleMsgs.count, 1)
    }

    func testMonitorVideoModeToggleCameraSendsBeforeTransition() throws {
        pushMonitorVideoModeState()

        ref ! UICmd.ToggleCamera()
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitorTogglingCamera)
        let toggleMsgs = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.ToggleCamera }
        XCTAssertEqual(toggleMsgs.count, 1)
    }

    // MARK: - Timeout: transient states unbecome after timeout

    func testTimeout_monitorTogglingFlash_unbecomes() throws {
        pushMonitorTogglingFlashState()

        ref ! UICmd.StateTimeout(stateName: .monitorTogglingFlash,
                                 generation: session._timeoutGeneration)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor,
                       "Timeout should unbecome back to photo mode")
    }

    func testTimeout_staleGeneration_ignored() throws {
        pushMonitorTogglingFlashState()

        ref ! UICmd.StateTimeout(stateName: .monitorTogglingFlash,
                                 generation: session._timeoutGeneration - 1)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitorTogglingFlash,
                       "Stale timeout should be ignored")
    }

    func testTimeout_monitorTogglingCamera_unbecomes() throws {
        pushMonitorTogglingCameraState()

        ref ! UICmd.StateTimeout(stateName: .monitorTogglingCamera,
                                 generation: session._timeoutGeneration)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor)
    }

    func testTimeout_monitorSwitchingLens_unbecomes() throws {
        pushMonitorSwitchingLensState()

        ref ! UICmd.StateTimeout(stateName: .monitorSwitchingLens,
                                 generation: session._timeoutGeneration)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor)
    }

    func testTimeout_monitorTakingPicture_unbecomes() throws {
        pushMonitorTakingPictureState()

        ref ! UICmd.StateTimeout(stateName: .monitorTakingPicture,
                                 generation: session._timeoutGeneration)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor)
    }

    // MARK: - Send-before-become: commands sent directly from parent state

    func testMonitorPhotoModeToggleFlashSendsBeforeTransition() throws {
        pushMonitorPhotoModeState()

        ref ! UICmd.ToggleFlash()
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitorTogglingFlash)
        let flashMsgs = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.ToggleFlash }
        XCTAssertEqual(flashMsgs.count, 1)
    }

    func testMonitorPhotoModeTakePictureSendsBeforeTransition() throws {
        pushMonitorPhotoModeState()

        ref ! UICmd.TakePicture(sender: nil, sendMediaToRemote: true)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitorTakingPicture)
        let takePicMsgs = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.TakePic }
        XCTAssertEqual(takePicMsgs.count, 1)
    }

    func testMonitorPhotoModeSwitchLensSendsBeforeTransition() throws {
        pushMonitorPhotoModeState()

        ref ! UICmd.SwitchLens(lensType: .telephoto)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitorSwitchingLens)
        let switchMsgs = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.SwitchLens }
        XCTAssertEqual(switchMsgs.count, 1)
    }

    func testMonitorVideoModeSwitchLensSendsBeforeTransition() throws {
        pushMonitorVideoModeState()

        ref ! UICmd.SwitchLens(lensType: .ultraWide)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitorSwitchingLens)
        let switchMsgs = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.SwitchLens }
        XCTAssertEqual(switchMsgs.count, 1)
    }

    // MARK: - Send failure recovery

    /// Send failure pops to scanning as an escape hatch.
    func testMonitorPhotoModeToggleFlashSendFailurePopsToScanning() throws {
        pushMonitorPhotoModeState()

        // Make sends fail
        fakeMP.sendResult = Failure(error: NSError(domain: "test", code: 1))

        ref ! UICmd.ToggleFlash()
        waitForMailbox(session, test: self)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
    }

    func testMonitorPhotoModeToggleCameraSendFailurePopsToScanning() throws {
        pushMonitorPhotoModeState()

        fakeMP.sendResult = Failure(error: NSError(domain: "test", code: 1))

        ref ! UICmd.ToggleCamera()
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
    }

    func testMonitorPhotoModeSwitchLensSendFailurePopsToScanning() throws {
        pushMonitorPhotoModeState()

        fakeMP.sendResult = Failure(error: NSError(domain: "test", code: 1))

        ref ! UICmd.SwitchLens(lensType: .telephoto)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
    }

    func testMonitorVideoModeStartRecordingSendFailurePopsToScanning() throws {
        pushMonitorVideoModeState()

        fakeMP.sendResult = Failure(error: NSError(domain: "test", code: 1))

        ref ! UICmd.TakePicture(sender: nil, sendMediaToRemote: true)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
    }

    /// Verifies recording UI only shows after successful send.
    func testMonitorRecordingVideoOnEnterShowsRecordingUI() throws {
        pushMonitorVideoModeState()

        ref ! UICmd.TakePicture(sender: nil, sendMediaToRemote: true)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitorRecordingVideo)
    }

    func testMonitorPhotoModeTakePictureSendFailurePopsToScanning() throws {
        pushMonitorPhotoModeState()

        fakeMP.sendResult = Failure(error: NSError(domain: "test", code: 1))

        ref ! UICmd.TakePicture(sender: nil, sendMediaToRemote: true)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
    }

    // MARK: - CameraTakingPic: timeout with send failure

    /// Verifies timeout + send failure lands on scanning (not nil from double-pop).
    func testCameraTakingPicTimeoutSendFailurePopsToScanning() throws {
        pushScanningState()
        pushConnectedState()

        let noOpCamera: Receive = { _ in }
        session.become(name: .camera, state: noOpCamera)
        waitForMailbox(session, test: self)

        let gen = session.scheduleTimeout(stateName: .cameraTakingPic)
        let fixedTimeout: Receive = { [unowned self] (msg: Actor.Message) in
            if let timeout = msg as? UICmd.StateTimeout,
               timeout.stateName == .cameraTakingPic,
               timeout.generation == gen {
                let error = NSError(domain: "Photo capture timed out", code: 0)
                if self.session.sendMessage(
                    peer: [self.peer],
                    msg: RemoteCmd.TakePicResp(sender: self.session.this, error: error)).isSuccess() {
                    self.session.unbecome()
                } else {
                    self.session.popAndStartScanning()
                }
            }
        }
        session.become(name: .cameraTakingPic, state: fixedTimeout)
        waitForMailbox(session, test: self)

        fakeMP.sendResult = Failure(error: NSError(domain: "test", code: 1))

        ref ! UICmd.StateTimeout(stateName: .cameraTakingPic, generation: gen)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .scanning)
    }

    // MARK: - MonitorWaitingForVideo: UnbecomeMonitor

    func testMonitorWaitingForVideoUnbecomeMonitorPopsToConnected() throws {
        pushMonitorWaitingForVideoState()

        ref ! UICmd.UnbecomeMonitor(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .connected)
    }

    // MARK: - PopToState after mode switch

    func testPopToMonitorWorksAfterModeSwitch() throws {
        pushScanningState()
        pushConnectedState()

        session.become(name: .monitor,
                       state: session.monitorPhotoMode(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)

        ref ! UICmd.BecomeMonitor(ref, mode: .Video)
        waitForMailbox(session, test: self)
        XCTAssertEqual(session.currentStateName(), .monitor)

        session.become(name: .monitorRecordingVideo,
                       state: session.monitorRecordingVideo(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)
        fakeMP.sentMessages.removeAll()

        let error = NSError(domain: "TestError", code: 1, userInfo: nil)
        ref ! RemoteCmd.StartRecordingVideoAck(sender: nil, recordingStartTime: nil, error: error)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor)
    }

    // MARK: - Aspect Ratio Integration Tests

    func testMonitorPhotoModeSetAspectRatioSendsCommand() throws {
        pushMonitorPhotoModeState()

        ref ! UICmd.SetAspectRatio(aspectRatio: .fourThree)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .monitor)
        let ratioMessages = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.SetAspectRatio }
        XCTAssertEqual(ratioMessages.count, 1)
        let msg = ratioMessages[0].msg as! RemoteCmd.SetAspectRatio
        XCTAssertEqual(msg.aspectRatio, .fourThree)
    }

    func testMonitorVideoModeSetAspectRatioSendsCommand() throws {
        pushMonitorVideoModeState()

        ref ! UICmd.SetAspectRatio(aspectRatio: .sixteenNine)
        waitForMailbox(session, test: self)

        let ratioMessages = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.SetAspectRatio }
        XCTAssertEqual(ratioMessages.count, 1)
    }

    // MARK: - Watch Remote Crash Guard (nil multipeerService)

    /// In Watch Remote mode no multipeer session ever exists. Commands that fall
    /// through to the root receive must not crash on the nil service, must not
    /// pop to scanning, and must not surface a "Connection error" alert.
    func testRootReceiveCommandsWithNilMultipeerServiceDoNotCrash() throws {
        session.multipeerService = nil

        ref ! RemoteCmd.TakePic(sender: nil, sendMediaToPeer: false)
        ref ! RemoteCmd.TakePic(sender: nil, sendMediaToPeer: false)
        ref ! RemoteCmd.SetZoom(zoomFactor: 2.0)
        ref ! RemoteCmd.StartRecordingVideo(sender: nil)
        ref ! RemoteCmd.StopRecordingVideo(sender: nil)
        ref ! RemoteCmd.ToggleFlash()
        waitForMailbox(session, test: self)

        XCTAssertNil(session.currentStateName(), "root state must be untouched")
        XCTAssertTrue(fakeAlerts.shownErrors.isEmpty,
                      "nil multipeer service must not surface a connection error")
    }

    func testRootReceiveCommandsWithNilMultipeerServiceKeepPushedState() throws {
        session.multipeerService = nil
        let inert: Receive = { [weak self] _ in _ = self }
        session.become(name: .watchRemoteCamera, state: inert)
        waitForMailbox(session, test: self)

        // Simulate the wedged-substate scenario: commands the state doesn't
        // handle would previously crash or pop the watch state to scanning.
        // Run on the mailbox — sendCommandOrGoToScanning asserts off-main.
        session.mailbox.addOperation { [session] in
            session!.sendCommandOrGoToScanning(
                peer: [], msg: RemoteCmd.TakePicResp(sender: nil, pic: nil, error: nil))
        }
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .watchRemoteCamera)
        XCTAssertTrue(fakeAlerts.shownErrors.isEmpty)
    }

}
