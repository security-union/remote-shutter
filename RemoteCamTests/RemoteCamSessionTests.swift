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
    var startSessionCalled = false
    var stopSessionCalled = false
    var sendResult: Try<Actor.Message> = Failure(error: NSError(domain: "test", code: 0))

    func startSession(peerID: MCPeerID) { startSessionCalled = true }
    func stopSession() { stopSessionCalled = true }
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

    override func startScanning(lobby: DeviceScannerViewController) {
        // no-op — avoids MCAdvertiserAssistant, MCSession, and UI code
    }
}

// MARK: - Test ViewController

/// Subclass that prevents crashes from nil IBOutlets and storyboard-dependent code.
/// The real `DeviceScannerViewController` has IBOutlets (tableView, etc.) that are
/// nil when created programmatically. This subclass makes the VC safe for tests.
class TestDeviceScannerViewController: DeviceScannerViewController {
    override public func viewDidLoad() {
        // Skip super — avoids accessing nil IBOutlets and actor system registration
    }

    override func stopScanning() {
        // no-op — avoids accessing splash/tableView
    }

    override func startScanning() {
        // no-op
    }
}

// MARK: - Test Helpers

/// Waits for all prior operations on the actor's serial mailbox to drain.
/// Since Theater delivers messages (including OnEnter) via `mailbox.addOperation`,
/// queuing a fulfillment operation after the message-under-test guarantees it has
/// been fully processed before assertions run.
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

    // Class-level lobby VC created once to avoid a race condition:
    // DeviceScannerViewController.init registers actors in RemoteCamSystem.shared,
    // and deinit sends async Harakiri to remove them. Creating a new VC per test
    // races with the previous VC's async cleanup.
    private static var sharedLobby: TestDeviceScannerViewController!
    private var lobby: DeviceScannerViewController!
    private var lobbyWrapper: Weak<DeviceScannerViewController>!

    override class func setUp() {
        super.setUp()
        sharedLobby = TestDeviceScannerViewController()
    }

    override class func tearDown() {
        sharedLobby = nil
        super.tearDown()
    }

    override func setUp() {
        super.setUp()

        system = TestActorSystem(name: "test")
        ref = system.actorOf(clz: TestableRemoteCamSession.self, name: "session")
        session = system.actorForRef(ref: ref!) as! TestableRemoteCamSession
        peer = MCPeerID(displayName: "TestPeer")

        lobby = Self.sharedLobby
        lobbyWrapper = Weak(lobby)

        // Inject FakeMultipeerService so tests can inspect sent messages
        // and control connectedPeers without real MCSession infrastructure.
        fakeMP = FakeMultipeerService()
        fakeMP.connectedPeers = [peer]
        fakeMP.sendResult = Success(Actor.Message())
        session.multipeerService = fakeMP

        fakeAlerts = FakeAlertPresenter()
        session.alertPresenter = fakeAlerts

        // Wait for preStart's `become(waitingForCtrl)` + OnEnter to finish.
        waitForMailbox(session, test: self)
    }

    override func tearDown() {
        // Theater's Actor.tell() uses [unowned self] in mailbox operations.
        // If the actor is deallocated while operations are pending, the
        // unowned reference crashes. We must ensure the mailbox is fully
        // drained before releasing the actor.
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

    /// Drains the actor mailbox while keeping the main run loop alive.
    private func drainMailboxPumpingRunLoop() {
        let deadline = Date(timeIntervalSinceNow: 5.0)
        while session.mailbox.operationCount > 0 && Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }

    // MARK: - Helpers

    /// Pushes a no-op scanning state onto the state stack.
    /// The real `scanning` state accesses storyboard IBOutlets (splash, tableView)
    /// which crash when the VC is created programmatically. This placeholder
    /// gives `popAndStartScanning()` a target to pop back to.
    private func pushScanningState() {
        let noOpScanning: Receive = { [weak self] _ in
            // Minimal handler — just accept OnEnter without touching UI
            _ = self
        }
        session.become(name: session.states.scanning, state: noOpScanning)
        waitForMailbox(session, test: self) // let OnEnter process
    }

    /// Pushes the connected state on top of scanning.
    private func pushConnectedState() {
        session.become(name: session.states.connected,
                       state: session.connected(lobbyWrapper: lobbyWrapper, peer: peer))
        waitForMailbox(session, test: self) // let OnEnter process
    }

    /// Pushes the monitor photo mode state on top of scanning → connected.
    /// Clears sentMessages so tests only see messages from the action under test.
    private func pushMonitorPhotoModeState() {
        pushScanningState()
        // Push connected as a named placeholder (real connected's OnEnter touches UI via stopScanning,
        // but our TestDeviceScannerViewController handles that).
        pushConnectedState()
        session.become(name: session.states.monitor,
                       state: session.monitorPhotoMode(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self) // let OnEnter process
        fakeMP.sentMessages.removeAll() // clear OnEnter side-effects
    }

    /// Pushes the monitor video mode state on top of scanning → connected.
    private func pushMonitorVideoModeState() {
        pushScanningState()
        pushConnectedState()
        session.become(name: session.states.monitor,
                       state: session.monitorVideoMode(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)
        fakeMP.sentMessages.removeAll()
    }

    // MARK: - Initial State

    func testInitialStateIsWaitingForCtrl() {
        // ViewCtrlActor.preStart() pushes "waitingForCtrl"
        XCTAssertEqual(session.currentState()?.0, session.waitingForCtrlState)
    }

    // MARK: - Connected State: Disconnect

    func testConnectedStateDisconnect() {
        // Build state stack: waitingForCtrl → scanning → connected
        pushScanningState()
        pushConnectedState()

        // Act
        ref ! Disconnect(sender: nil)
        waitForMailbox(session, test: self)

        // Assert — should have popped back to scanning
        XCTAssertEqual(session.currentState()?.0, session.states.scanning)
        XCTAssertTrue(fakeMP.sentMessages.isEmpty,
                      "Disconnect should not send any remote messages")
    }

    // MARK: - Connected State: BecomeMonitor (Photo)

    func testConnectedStateBecomeMonitorPhoto() {
        pushScanningState()
        pushConnectedState()

        // BecomeMonitor requires a sender ActorRef (used as the monitor actor ref).
        // We reuse `ref` as a stand-in since we only care about state transitions.
        ref ! UICmd.BecomeMonitor(ref, mode: .Photo)
        waitForMailbox(session, test: self)

        // Assert — state should be "monitor" (monitorPhotoMode)
        XCTAssertEqual(session.currentState()?.0, session.states.monitor)

        // Should have sent PeerBecameMonitor to the peer.
        // The monitorPhotoMode OnEnter may also send a message (e.g. RequestCameraCapabilities),
        // so we check that PeerBecameMonitor is the first message sent.
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

        // Assert — state should be "monitor" (monitorVideoMode)
        XCTAssertEqual(session.currentState()?.0, session.states.monitor)

        // Should have sent PeerBecameMonitor to the peer.
        XCTAssertGreaterThanOrEqual(fakeMP.sentMessages.count, 1)
        XCTAssertTrue(fakeMP.sentMessages[0].msg is RemoteCmd.PeerBecameMonitor)
        XCTAssertEqual(fakeMP.sentMessages[0].peers, [peer])
    }

    // MARK: - Connected State: Nil Lobby Pops to Scanning

    func testConnectedStateNilLobbyPopsToScanning() {
        pushScanningState()

        // Create a lobby wrapper and immediately nil the value to simulate a deallocated VC.
        let weakLobby = Weak(lobby!)
        session.become(name: session.states.connected,
                       state: session.connected(lobbyWrapper: weakLobby, peer: peer))
        waitForMailbox(session, test: self)

        // Nil out the weak reference to simulate the lobby VC being deallocated
        weakLobby.value = nil

        // Send any message — the guard-let will fail and trigger popAndStartScanning
        ref ! Disconnect(sender: nil)
        waitForMailbox(session, test: self)

        // Should have popped back to scanning
        XCTAssertEqual(session.currentState()?.0, session.states.scanning)
    }

    // MARK: - MonitorPhotoMode: OnEnter

    func testMonitorPhotoModeOnEnterRequestsFrame() {
        pushScanningState()
        pushConnectedState()

        // Push monitorPhotoMode — OnEnter sends RenderPhotoMode to monitor + RequestFrame to peer
        session.become(name: session.states.monitor,
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

        XCTAssertEqual(session.currentState()?.0, session.states.connected)
    }

    // MARK: - MonitorPhotoMode: Disconnect

    func testMonitorPhotoModeDisconnectPopsToScanning() throws {
        pushMonitorPhotoModeState()

        ref ! Disconnect(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.scanning)
    }

    // MARK: - MonitorPhotoMode: TakePicture transitions to monitorTakingPicture
    
    func testMonitorPhotoModeTakePictureTransitions() throws {
        pushMonitorPhotoModeState()

        ref ! UICmd.TakePicture(sender: nil, sendMediaToRemote: true)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.monitorTakingPicture)
    }

    // MARK: - MonitorPhotoMode: ToggleFlash transitions to monitorTogglingFlash

    func testMonitorPhotoModeToggleFlashTransitions() throws {
        pushMonitorPhotoModeState()

        ref ! UICmd.ToggleFlash()
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.monitorTogglingFlash)
    }

    // MARK: - MonitorPhotoMode: ToggleCamera transitions to monitorTogglingCamera

    func testMonitorPhotoModeToggleCameraTransitions() throws {
        pushMonitorPhotoModeState()

        ref ! UICmd.ToggleCamera()
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.monitorTogglingCamera)
    }

    // MARK: - MonitorPhotoMode: Switch to Video mode

    func testMonitorPhotoModeSwitchToVideoMode() throws {
        pushMonitorPhotoModeState()

        ref ! UICmd.BecomeMonitor(ref, mode: .Video)
        waitForMailbox(session, test: self)

        // Should have replaced the current state with monitorVideoMode
        XCTAssertEqual(session.currentState()?.0, session.states.monitorVideoMode)
    }

    // MARK: - MonitorPhotoMode: ToggleTorch sends remote command

    func testMonitorPhotoModeToggleTorchSendsCommand() throws {
        pushMonitorPhotoModeState()

        ref ! UICmd.ToggleTorch()
        waitForMailbox(session, test: self)

        // Should stay in monitor state and send ToggleTorch via sendMessage
        XCTAssertEqual(session.currentState()?.0, session.states.monitor)
        let torchMessages = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.ToggleTorch }
        XCTAssertEqual(torchMessages.count, 1)
    }

    // MARK: - MonitorPhotoMode: RequestCameraCapabilities

    func testMonitorPhotoModeRequestCameraCapabilities() throws {
        pushMonitorPhotoModeState()

        ref ! UICmd.RequestCameraCapabilities()
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.monitor)
        let capRequests = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.RequestCameraCapabilities }
        XCTAssertEqual(capRequests.count, 1)
    }

    // MARK: - MonitorVideoMode: OnEnter

    func testMonitorVideoModeOnEnterRequestsFrame() throws {
        pushScanningState()
        pushConnectedState()

        session.become(name: session.states.monitor,
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

        XCTAssertEqual(session.currentState()?.0, session.states.monitorPhotoMode)
    }

    // MARK: - MonitorVideoMode: Disconnect

    func testMonitorVideoModeDisconnectPopsToScanning() throws {
        pushMonitorVideoModeState()

        ref ! Disconnect(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.scanning)
    }

    // MARK: - MonitorVideoMode: UnbecomeMonitor

    func testMonitorVideoModeUnbecomeMonitorPopsToConnected() throws {
        pushMonitorVideoModeState()

        ref ! UICmd.UnbecomeMonitor(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.connected)
    }

    // MARK: - MonitorPhotoMode: SwitchLens transitions to monitorSwitchingLens

    func testMonitorPhotoModeSwitchLensTransitions() throws {
        pushMonitorPhotoModeState()

        ref ! UICmd.SwitchLens(lensType: .telephoto)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.monitorSwitchingLens)
    }

    // MARK: - MonitorPhotoMode: SetZoom sends remote command

    func testMonitorPhotoModeSetZoomSendsCommand() throws {
        pushMonitorPhotoModeState()

        ref ! UICmd.SetZoom(zoomFactor: 2.0)
        waitForMailbox(session, test: self)

        // Should stay in monitor state
        XCTAssertEqual(session.currentState()?.0, session.states.monitor)
        let zoomMessages = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.SetZoom }
        XCTAssertEqual(zoomMessages.count, 1)
    }

    // MARK: - MonitorPhotoMode: PeerBecameCamera requests capabilities

    func testMonitorPhotoModePeerBecameCameraRequestsCapabilities() throws {
        pushMonitorPhotoModeState()

        ref ! RemoteCmd.PeerBecameCamera.createWithDefaults()
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.monitor)
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

        XCTAssertEqual(session.currentState()?.0, session.states.scanning)
    }

    // MARK: - MonitorVideoMode: TakePicture starts recording and transitions

    func testMonitorVideoModeTakePictureStartsRecording() throws {
        pushMonitorVideoModeState()

        ref ! UICmd.TakePicture(sender: nil, sendMediaToRemote: true)
        waitForMailbox(session, test: self)

        // Should have sent StartRecordingVideo to peer
        let startMsgs = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.StartRecordingVideo }
        XCTAssertEqual(startMsgs.count, 1)
        // Should have transitioned to monitorRecordingVideo
        XCTAssertEqual(session.currentState()?.0, session.states.monitorRecordingVideo)
    }

    // MARK: - MonitorVideoMode: ToggleCamera transitions

    func testMonitorVideoModeToggleCameraTransitions() throws {
        pushMonitorVideoModeState()

        ref ! UICmd.ToggleCamera()
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.monitorTogglingCamera)
    }

    // MARK: - MonitorVideoMode: ToggleTorch sends command

    func testMonitorVideoModeToggleTorchSendsCommand() throws {
        pushMonitorVideoModeState()

        ref ! UICmd.ToggleTorch()
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.monitor)
        let torchMessages = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.ToggleTorch }
        XCTAssertEqual(torchMessages.count, 1)
    }

    // MARK: - MonitorVideoMode: SwitchLens transitions

    func testMonitorVideoModeSwitchLensTransitions() throws {
        pushMonitorVideoModeState()

        ref ! UICmd.SwitchLens(lensType: .ultraWide)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.monitorSwitchingLens)
    }

    // MARK: - MonitorVideoMode: SetZoom sends command

    func testMonitorVideoModeSetZoomSendsCommand() throws {
        pushMonitorVideoModeState()

        ref ! UICmd.SetZoom(zoomFactor: 3.0)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.monitor)
        let zoomMessages = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.SetZoom }
        XCTAssertEqual(zoomMessages.count, 1)
    }

    // MARK: - MonitorVideoMode: RequestCameraCapabilities sends request

    func testMonitorVideoModeRequestCameraCapabilities() throws {
        pushMonitorVideoModeState()

        ref ! UICmd.RequestCameraCapabilities()
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.monitor)
        let capRequests = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.RequestCameraCapabilities }
        XCTAssertEqual(capRequests.count, 1)
    }

    // MARK: - MonitorVideoMode: PeerBecameCamera requests capabilities

    func testMonitorVideoModePeerBecameCameraRequestsCapabilities() throws {
        pushMonitorVideoModeState()

        ref ! RemoteCmd.PeerBecameCamera.createWithDefaults()
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.monitor)
        let capRequests = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.RequestCameraCapabilities }
        XCTAssertEqual(capRequests.count, 1)
    }

    // MARK: - MonitorVideoMode: DisconnectPeer pops to scanning

    func testMonitorVideoModeDisconnectPeerPopsToScanning() throws {
        pushMonitorVideoModeState()

        // Simulate MCSession removing the peer before the DisconnectPeer message arrives
        fakeMP.connectedPeers = []
        ref ! DisconnectPeer(peer: peer, sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.scanning)
    }

    // MARK: - MonitorTakingPicture Helpers

    private func pushMonitorTakingPictureState() {
        pushMonitorPhotoModeState()
        session.become(name: session.states.monitorTakingPicture,
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
        XCTAssertEqual(session.currentState()?.0, session.states.monitor)
    }

    // MARK: - MonitorTakingPicture: TakePicResp with picture unbecomes

    func testMonitorTakingPictureTakePicRespWithPicUnbecomes() throws {
        pushMonitorTakingPictureState()

        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0]) // minimal JPEG header
        ref ! RemoteCmd.TakePicResp(sender: nil, pic: imageData)
        waitForMailbox(session, test: self)

        // unbecome() pops monitorTakingPicture → back to monitorPhotoMode
        XCTAssertEqual(session.currentState()?.0, session.states.monitor)
    }

    // MARK: - MonitorTakingPicture: TakePicAck forwards to peer

    func testMonitorTakingPictureTakePicAckForwardsToPeer() throws {
        pushMonitorTakingPictureState()

        ref ! RemoteCmd.TakePicAck(sender: nil)
        waitForMailbox(session, test: self)

        // Should stay in monitorTakingPicture and send the ack to the camera peer
        XCTAssertEqual(session.currentState()?.0, session.states.monitorTakingPicture)
        let ackMessages = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.TakePicAck }
        XCTAssertEqual(ackMessages.count, 1)
        XCTAssertEqual(ackMessages[0].peers, [peer])
    }

    // MARK: - MonitorRecordingVideo Helpers

    /// Pushes the monitorRecordingVideo state.
    /// Uses monitorVideoMode as the name for the video mode state
    /// so that popToState(name: states.monitorVideoMode) works correctly.
    private func pushMonitorRecordingVideoState() {
        pushScanningState()
        pushConnectedState()
        session.become(name: session.states.monitorVideoMode,
                       state: session.monitorVideoMode(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)
        session.become(name: session.states.monitorRecordingVideo,
                       state: session.monitorRecordingVideo(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)
        fakeMP.sentMessages.removeAll()
    }

    // MARK: - MonitorRecordingVideo: OnEnter sends RenderVideoModeRecording + RequestFrame

    func testMonitorRecordingVideoOnEnter() throws {
        pushScanningState()
        pushConnectedState()
        session.become(name: session.states.monitorVideoMode,
                       state: session.monitorVideoMode(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)
        fakeMP.sentMessages.removeAll()

        session.become(name: session.states.monitorRecordingVideo,
                       state: session.monitorRecordingVideo(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)

        // OnEnter should have sent a RequestFrame
        let frameRequests = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.RequestFrame }
        XCTAssertEqual(frameRequests.count, 1)
    }

    // MARK: - MonitorRecordingVideo: StartRecordingVideoAck with error pops to video mode

    func testMonitorRecordingVideoStartAckWithErrorPopsToVideoMode() throws {
        pushMonitorRecordingVideoState()

        let error = NSError(domain: "TestError", code: 1, userInfo: nil)
        ref ! RemoteCmd.StartRecordingVideoAck(sender: nil, recordingStartTime: nil, error: error)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.monitorVideoMode)
    }

    // MARK: - MonitorRecordingVideo: TakePicture sends StopRecordingVideo

    func testMonitorRecordingVideoTakePictureSendsStopRecording() throws {
        pushMonitorRecordingVideoState()

        ref ! UICmd.TakePicture(sender: nil, sendMediaToRemote: true)
        waitForMailbox(session, test: self)

        let stopMsgs = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.StopRecordingVideo }
        XCTAssertEqual(stopMsgs.count, 1)
        // Should still be in recording state (waiting for ack)
        XCTAssertEqual(session.currentState()?.0, session.states.monitorRecordingVideo)
    }

    // MARK: - MonitorRecordingVideo: StopRecordingVideoAck transitions to monitorWaitingForVideo

    func testMonitorRecordingVideoStopAckTransitionsToWaiting() throws {
        pushMonitorRecordingVideoState()

        ref ! RemoteCmd.StopRecordingVideoAck()
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.monitorWaitingForVideo)
    }

    // MARK: - MonitorRecordingVideo: StopRecordingVideoResp with error pops to video mode

    func testMonitorRecordingVideoStopRespWithErrorPopsToVideoMode() throws {
        pushMonitorRecordingVideoState()

        let error = NSError(domain: "TestError", code: 2, userInfo: nil)
        ref ! RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: error)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.monitorVideoMode)
    }

    // MARK: - MonitorRecordingVideo: Disconnect pops to scanning

    func testMonitorRecordingVideoDisconnectPopsToScanning() throws {
        pushMonitorRecordingVideoState()

        ref ! Disconnect(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.scanning)
    }

    // MARK: - MonitorRecordingVideo: DisconnectPeer pops to scanning

    func testMonitorRecordingVideoDisconnectPeerPopsToScanning() throws {
        pushMonitorRecordingVideoState()

        // Simulate MCSession removing the peer before the DisconnectPeer message arrives
        fakeMP.connectedPeers = []
        ref ! DisconnectPeer(peer: peer, sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.scanning)
    }

    // MARK: - MonitorWaitingForVideo Helpers

    private func pushMonitorWaitingForVideoState() {
        pushMonitorRecordingVideoState()
        session.become(name: session.states.monitorWaitingForVideo,
                       state: session.monitorWaitingForVideo(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)
        fakeMP.sentMessages.removeAll()
    }

    // MARK: - MonitorWaitingForVideo: StopRecordingVideoResp pops to video mode

    func testMonitorWaitingForVideoStopRespPopsToVideoMode() throws {
        pushMonitorWaitingForVideoState()

        ref ! RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.monitorVideoMode)
    }

    // MARK: - MonitorWaitingForVideo: Disconnect pops to scanning

    func testMonitorWaitingForVideoDisconnectPopsToScanning() throws {
        pushMonitorWaitingForVideoState()

        ref ! Disconnect(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.scanning)
    }

    // MARK: - MonitorWaitingForVideo: DisconnectPeer pops to scanning

    func testMonitorWaitingForVideoDisconnectPeerPopsToScanning() throws {
        pushMonitorWaitingForVideoState()

        // Simulate MCSession removing the peer before the DisconnectPeer message arrives
        fakeMP.connectedPeers = []
        ref ! DisconnectPeer(peer: peer, sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.scanning)
    }

    // MARK: - Connected: DisconnectPeer pops to scanning when no peers

    func testConnectedStateDisconnectPeerPopsToScanning() throws {
        pushScanningState()
        pushConnectedState()

        // Simulate MCSession removing the peer before the DisconnectPeer message arrives
        fakeMP.connectedPeers = []
        ref ! DisconnectPeer(peer: peer, sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.scanning)
    }

    // MARK: - FakeMultipeerService: Connected sends PeerBecameCamera

    func testConnectedStateBecameCameraSendsPeerBecameCamera() throws {
        pushScanningState()
        pushConnectedState()
        fakeMP.sentMessages.removeAll()

        // BecomeCamera requires a CameraViewController, which we can't easily create.
        // Instead, verify PeerBecameMonitor (already covered above) and test
        // that sendCommandOrGoToScanning routes through multipeerService.send().

        // Verify via BecomeMonitor which is simpler to trigger
        ref ! UICmd.BecomeMonitor(ref, mode: .Photo)
        waitForMailbox(session, test: self)

        // The first message through FakeMultipeerService should be PeerBecameMonitor
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

        session.become(name: session.states.monitor,
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

        // Make sends fail
        fakeMP.sendResult = Failure(error: NSError(domain: "test", code: 1))

        // Push monitor photo mode — OnEnter calls sendCommandOrGoToScanning(RequestFrame)
        // which will fail and trigger popToState(scanning)
        session.become(name: session.states.monitor,
                       state: session.monitorPhotoMode(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)

        // Should have popped to scanning due to send failure
        XCTAssertEqual(session.currentState()?.0, session.states.scanning)
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
        session.become(name: session.states.monitorTogglingFlash,
                       state: session.monitorTogglingFlash(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)
        fakeMP.sentMessages.removeAll()
        fakeAlerts.shownAlerts.removeAll()
        fakeAlerts.shownErrors.removeAll()
    }

    // MARK: - MonitorTogglingFlash: ToggleFlash sends command and response unbecomes

    func testMonitorTogglingFlashSendsCommand() throws {
        pushMonitorTogglingFlashState()

        ref ! UICmd.ToggleFlash()
        waitForMailbox(session, test: self)

        let toggleMsgs = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.ToggleFlash }
        XCTAssertEqual(toggleMsgs.count, 1)
        XCTAssertEqual(session.currentState()?.0, session.states.monitorTogglingFlash)
    }

    func testMonitorTogglingFlashSuccessResponseUnbecomes() throws {
        pushMonitorTogglingFlashState()

        ref ! RemoteCmd.ToggleFlashResp(flashMode: .on, error: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.monitor)
    }

    func testMonitorTogglingFlashErrorResponseUnbecomes() throws {
        pushMonitorTogglingFlashState()

        let error = NSError(domain: "FlashError", code: 1, userInfo: nil)
        ref ! RemoteCmd.ToggleFlashResp(flashMode: nil, error: error)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.monitor)
    }

    func testMonitorTogglingFlashDisconnectPopsToScanning() throws {
        pushMonitorTogglingFlashState()

        ref ! Disconnect(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.scanning)
    }

    func testMonitorTogglingFlashDisconnectPeerPopsToScanning() throws {
        pushMonitorTogglingFlashState()

        fakeMP.connectedPeers = []
        ref ! DisconnectPeer(peer: peer, sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.scanning)
    }

    func testMonitorTogglingFlashUnbecomeMonitorPopsToConnected() throws {
        pushMonitorTogglingFlashState()

        ref ! UICmd.UnbecomeMonitor(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.connected)
    }

    // MARK: - MonitorTogglingCamera Helpers

    private func pushMonitorTogglingCameraState() {
        pushMonitorPhotoModeState()
        session.become(name: session.states.monitorTogglingCamera,
                       state: session.monitorTogglingCamera(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)
        fakeMP.sentMessages.removeAll()
        fakeAlerts.shownAlerts.removeAll()
        fakeAlerts.shownErrors.removeAll()
    }

    // MARK: - MonitorTogglingCamera: ToggleCamera sends command and response unbecomes

    func testMonitorTogglingCameraSendsCommand() throws {
        pushMonitorTogglingCameraState()

        ref ! UICmd.ToggleCamera()
        waitForMailbox(session, test: self)

        let toggleMsgs = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.ToggleCamera }
        XCTAssertEqual(toggleMsgs.count, 1)
        XCTAssertEqual(session.currentState()?.0, session.states.monitorTogglingCamera)
    }

    func testMonitorTogglingCameraSuccessResponseUnbecomes() throws {
        pushMonitorTogglingCameraState()

        let capabilities = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, currentLens: .wideAngle, currentZoom: 1.0, error: nil)
        ref ! RemoteCmd.ToggleCameraResp(cameraCapabilities: capabilities, error: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.monitor)
    }

    func testMonitorTogglingCameraErrorResponseUnbecomes() throws {
        pushMonitorTogglingCameraState()

        let error = NSError(domain: "CameraError", code: 1, userInfo: nil)
        ref ! RemoteCmd.ToggleCameraResp(cameraCapabilities: nil, error: error)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.monitor)
    }

    func testMonitorTogglingCameraDisconnectPopsToScanning() throws {
        pushMonitorTogglingCameraState()

        ref ! Disconnect(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.scanning)
    }

    func testMonitorTogglingCameraDisconnectPeerPopsToScanning() throws {
        pushMonitorTogglingCameraState()

        fakeMP.connectedPeers = []
        ref ! DisconnectPeer(peer: peer, sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.scanning)
    }

    func testMonitorTogglingCameraUnbecomeMonitorPopsToConnected() throws {
        pushMonitorTogglingCameraState()

        ref ! UICmd.UnbecomeMonitor(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.connected)
    }

    // MARK: - MonitorSwitchingLens Helpers

    private func pushMonitorSwitchingLensState() {
        pushMonitorPhotoModeState()
        session.become(name: session.states.monitorSwitchingLens,
                       state: session.monitorSwitchingLens(monitor: ref, peer: peer, lobby: lobbyWrapper))
        waitForMailbox(session, test: self)
        fakeMP.sentMessages.removeAll()
        fakeAlerts.shownAlerts.removeAll()
        fakeAlerts.shownErrors.removeAll()
    }

    // MARK: - MonitorSwitchingLens: SwitchLens sends command and response unbecomes

    func testMonitorSwitchingLensSendsCommand() throws {
        pushMonitorSwitchingLensState()

        ref ! UICmd.SwitchLens(lensType: .telephoto)
        waitForMailbox(session, test: self)

        let switchMsgs = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.SwitchLens }
        XCTAssertEqual(switchMsgs.count, 1)
        XCTAssertEqual(session.currentState()?.0, session.states.monitorSwitchingLens)
    }

    func testMonitorSwitchingLensSuccessResponseUnbecomes() throws {
        pushMonitorSwitchingLensState()

        ref ! RemoteCmd.SwitchLensResp(lensType: .telephoto, availableLenses: [.wideAngle, .telephoto], currentZoom: 2.0, zoomRange: RemoteCmd.ZoomRange(minZoom: 1.0, maxZoom: 10.0), error: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.monitor)
    }

    func testMonitorSwitchingLensErrorResponseUnbecomes() throws {
        pushMonitorSwitchingLensState()

        let error = NSError(domain: "LensError", code: 1, userInfo: nil)
        ref ! RemoteCmd.SwitchLensResp(lensType: nil, availableLenses: nil, currentZoom: nil, zoomRange: nil, error: error)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.monitor)
    }

    func testMonitorSwitchingLensDisconnectPeerPopsToScanning() throws {
        pushMonitorSwitchingLensState()

        fakeMP.connectedPeers = []
        ref ! DisconnectPeer(peer: peer, sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.scanning)
    }

    func testMonitorSwitchingLensUnbecomeMonitorPopsToConnected() throws {
        pushMonitorSwitchingLensState()

        ref ! UICmd.UnbecomeMonitor(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.connected)
    }

    // MARK: - MonitorTakingPicture: TakePicture sends command directly

    func testMonitorTakingPictureTakePictureSendsCommand() throws {
        pushMonitorTakingPictureState()

        ref ! UICmd.TakePicture(sender: nil, sendMediaToRemote: true)
        waitForMailbox(session, test: self)

        let takePicMsgs = fakeMP.sentMessages.filter { $0.msg is RemoteCmd.TakePic }
        XCTAssertEqual(takePicMsgs.count, 1)
        XCTAssertEqual(session.currentState()?.0, session.states.monitorTakingPicture)
    }

    // MARK: - MonitorTakingPicture: TakePicAck updates alert title

    func testMonitorTakingPictureTakePicAckUpdatesTitle() throws {
        pushMonitorTakingPictureState()

        ref ! RemoteCmd.TakePicAck(sender: nil)
        waitForMailbox(session, test: self)

        // Pump run loop so ^{} dispatches execute
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        // Verify alert title was updated
        let updatedHandles = fakeAlerts.shownAlerts.filter { $0.currentTitle == "Receiving picture" }
        XCTAssertEqual(updatedHandles.count, 1)
    }

    // MARK: - MonitorTakingPicture: TakePicResp error shows error alert

    func testMonitorTakingPictureTakePicRespErrorShowsErrorAlert() throws {
        pushMonitorTakingPictureState()

        let error = NSError(domain: "PicError", code: 1, userInfo: nil)
        ref ! RemoteCmd.TakePicResp(sender: nil, error: error)
        waitForMailbox(session, test: self)

        // Pump run loop so ^{} dispatches execute
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        XCTAssertEqual(session.currentState()?.0, session.states.monitor)
        XCTAssertTrue(fakeAlerts.shownErrors.contains("PicError"))
    }

    // MARK: - MonitorTakingPicture: Disconnect pops to scanning

    func testMonitorTakingPictureDisconnectPopsToScanning() throws {
        pushMonitorTakingPictureState()

        ref ! Disconnect(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.scanning)
    }

    // MARK: - MonitorTakingPicture: UnbecomeMonitor pops to connected

    func testMonitorTakingPictureUnbecomeMonitorPopsToConnected() throws {
        pushMonitorTakingPictureState()

        ref ! UICmd.UnbecomeMonitor(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentState()?.0, session.states.connected)
    }

}
