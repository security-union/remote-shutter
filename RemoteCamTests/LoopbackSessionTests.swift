//
//  LoopbackSessionTests.swift
//  RemoteShutterTests
//
//  Two RemoteCamSession actors wired to each other through an in-process
//  transport that passes every message through the real FlatBuffers
//  encode/decode path. This exercises full protocol round trips across
//  BOTH state machines — the closest thing to a two-device test that can
//  run in CI.
//

import XCTest
import MultipeerConnectivity
import Combine

@testable import RemoteShutter

// MARK: - Loopback transport

/// Delivers sent messages to a paired peer service in-process, mirroring
/// `MultipeerService`'s wire serialization and inbound dispatch exactly.
class LoopbackMultipeerService: MultipeerServiceProtocol {
    weak var delegate: MultipeerServiceDelegate?
    var session: MCSession!
    let localPeerID: MCPeerID
    weak var remote: LoopbackMultipeerService?
    var progressCancellables = Set<AnyCancellable>()

    /// Messages sent from this side, recorded before serialization.
    var sentMessages: [Actor.Message] = []

    init(peerName: String) {
        localPeerID = MCPeerID(displayName: peerName)
    }

    var connectedPeers: [MCPeerID] {
        guard let remote else { return [] }
        return [remote.localPeerID]
    }

    func startAdvertisingAndBrowsing() {}
    func startAdvertisingOnly(discoveryInfo: [String: String]?) {}
    func startBrowsingOnly() {}
    func stopAdvertisingAndBrowsing() {}
    func disconnect() {}
    func stopSession() {}
    func invitePeer(_ peer: MCPeerID, timeout: TimeInterval) {}
    func sendResource(at url: URL, withName name: String,
                      toPeer peer: MCPeerID,
                      completion: @escaping (Error?) -> Void) -> Progress? { nil }

    func send(_ msg: Actor.Message, to peers: [MCPeerID],
              mode: MCSessionSendDataMode) -> Try<Actor.Message> {
        sentMessages.append(msg)

        guard let data = serializeToFlatBuffer(msg) else {
            return Failure(error: NSError(
                domain: "Loopback", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unknown message type: \(type(of: msg))"]))
        }
        guard let remote, let remoteDelegate = remote.delegate else {
            return Failure(error: NSError(
                domain: "Loopback", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "No connected peer"]))
        }
        guard let decoded = RemoteCmd.fromFlatBuffer(data) else {
            remoteDelegate.didDetectIncompatibility()
            return Success(msg)
        }

        // Mirror MultipeerService.session(_:didReceive:fromPeer:) routing.
        switch decoded {
        case let requestFrame as RemoteCmd.RequestFrame:
            remoteDelegate.didReceiveFrameRequest(requestFrame)
        case let frame as RemoteCmd.SendFrame:
            remoteDelegate.didReceiveFrame(frame, from: localPeerID)
        default:
            remoteDelegate.didReceiveMessage(decoded)
        }
        return Success(msg)
    }

    /// Severs the link and delivers the disconnect the way MCSessionDelegate would.
    func simulateRemoteDisconnected() {
        guard let peer = remote?.localPeerID else { return }
        remote = nil
        delegate?.peerDidDisconnect(peer)
    }
}

// MARK: - Tests

class LoopbackSessionTests: XCTestCase {

    private var system: TestActorSystem!

    private var monitorRef: ActorRef!
    private var monitorSession: TestableRemoteCamSession!
    private var monitorTransport: LoopbackMultipeerService!
    private var monitorAlerts: FakeAlertPresenter!

    private var cameraRef: ActorRef!
    private var cameraSession: TestableRemoteCamSession!
    private var cameraTransport: LoopbackMultipeerService!
    private var cameraAlerts: FakeAlertPresenter!

    private static var sharedLobby: FakeScannerLobby!
    private var lobbyWrapper: WeakScannerLobby!

    override class func setUp() {
        super.setUp()
        sharedLobby = FakeScannerLobby()
    }

    override class func tearDown() {
        sharedLobby = nil
        super.tearDown()
    }

    override func setUp() {
        super.setUp()
        system = TestActorSystem(name: "loopback")

        monitorRef = system.actorOf(clz: TestableRemoteCamSession.self, name: "monitor-side")
        monitorSession = (system.actorForRef(ref: monitorRef) as! TestableRemoteCamSession)
        cameraRef = system.actorOf(clz: TestableRemoteCamSession.self, name: "camera-side")
        cameraSession = (system.actorForRef(ref: cameraRef) as! TestableRemoteCamSession)

        monitorTransport = LoopbackMultipeerService(peerName: "MonitorDevice")
        cameraTransport = LoopbackMultipeerService(peerName: "CameraDevice")
        monitorTransport.remote = cameraTransport
        cameraTransport.remote = monitorTransport
        monitorTransport.delegate = monitorSession
        cameraTransport.delegate = cameraSession
        monitorSession.multipeerService = monitorTransport
        cameraSession.multipeerService = cameraTransport

        monitorAlerts = FakeAlertPresenter()
        cameraAlerts = FakeAlertPresenter()
        monitorSession.alertPresenter = monitorAlerts
        cameraSession.alertPresenter = cameraAlerts

        lobbyWrapper = WeakScannerLobby(Self.sharedLobby)

        drainBothSessions()
    }

    override func tearDown() {
        drainBothSessions()
        system.stop()
        drainBothSessions()
        system = nil
        monitorRef = nil
        monitorSession = nil
        monitorTransport = nil
        monitorAlerts = nil
        cameraRef = nil
        cameraSession = nil
        cameraTransport = nil
        cameraAlerts = nil
        lobbyWrapper = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// A message hop lands on the peer's mailbox asynchronously, and replies hop
    /// back. Drain both mailboxes several times so multi-hop exchanges settle.
    private func drainBothSessions(hops: Int = 6) {
        for _ in 0..<hops {
            waitForMailbox(monitorSession, test: self)
            waitForMailbox(cameraSession, test: self)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
    }

    /// Puts both sessions in the connected state, each pointing at the other's peer ID.
    private func connectBothSessions() {
        let noOpScanning: Receive = { _ in }

        monitorSession.become(name: .scanning, state: noOpScanning)
        monitorSession.become(
            name: .connected,
            state: monitorSession.connected(lobbyWrapper: lobbyWrapper,
                                            peer: cameraTransport.localPeerID))

        cameraSession.become(name: .scanning, state: noOpScanning)
        cameraSession.become(
            name: .connected,
            state: cameraSession.connected(lobbyWrapper: lobbyWrapper,
                                           peer: monitorTransport.localPeerID))

        drainBothSessions()
        monitorTransport.sentMessages.removeAll()
        cameraTransport.sentMessages.removeAll()
    }

    private func becomeMonitor(mode: RecordingMode) {
        monitorRef ! UICmd.BecomeMonitor(monitorRef, mode: mode)
        drainBothSessions()
    }

    // MARK: - Handshake

    func testBecomeMonitorHandshakeCrossesTheWire() {
        connectBothSessions()

        becomeMonitor(mode: .Photo)

        XCTAssertEqual(monitorSession.currentStateName(), .monitor)
        // The handshake and the photo-mode frame request both crossed the wire.
        XCTAssertTrue(monitorTransport.sentMessages.contains { $0 is RemoteCmd.PeerBecameMonitor })
        XCTAssertTrue(monitorTransport.sentMessages.contains { $0 is RemoteCmd.RequestFrame })
        // The peer decoded PeerBecameMonitor without tripping the incompatibility path.
        XCTAssertEqual(cameraSession.currentStateName(), .connected)
        XCTAssertTrue(cameraAlerts.shownErrors.isEmpty)
    }

    // MARK: - Take picture round trip

    func testTakePictureRoundTripAgainstPeerNotInCameraMode() {
        connectBothSessions()
        becomeMonitor(mode: .Photo)

        monitorRef ! UICmd.TakePicture(sender: nil, sendMediaToRemote: true)
        drainBothSessions()

        // TakePic crossed to the peer; the peer (not in camera mode) answered with
        // a TakePicResp carrying an error; the monitor popped back to photo mode
        // and surfaced the error.
        XCTAssertTrue(monitorTransport.sentMessages.contains { $0 is RemoteCmd.TakePic })
        XCTAssertTrue(cameraTransport.sentMessages.contains { $0 is RemoteCmd.TakePicResp })
        XCTAssertEqual(monitorSession.currentStateName(), .monitor)
        XCTAssertFalse(monitorAlerts.shownErrors.isEmpty)
        XCTAssertEqual(cameraSession.currentStateName(), .connected)
    }

    // MARK: - Toggle flash round trip

    func testToggleFlashRoundTripAgainstPeerNotInCameraMode() {
        connectBothSessions()
        becomeMonitor(mode: .Photo)

        monitorRef ! UICmd.ToggleFlash()
        drainBothSessions()

        XCTAssertTrue(monitorTransport.sentMessages.contains { $0 is RemoteCmd.ToggleFlash })
        XCTAssertTrue(cameraTransport.sentMessages.contains { $0 is RemoteCmd.ToggleFlashResp })
        // Error response unbecomes monitorTogglingFlash back to photo mode.
        XCTAssertEqual(monitorSession.currentStateName(), .monitor)
    }

    // MARK: - Video recording round trip

    func testStartRecordingRoundTripAgainstPeerNotInCameraMode() {
        connectBothSessions()
        becomeMonitor(mode: .Video)

        monitorRef ! UICmd.TakePicture(sender: nil, sendMediaToRemote: true)
        drainBothSessions()

        XCTAssertTrue(monitorTransport.sentMessages.contains { $0 is RemoteCmd.StartRecordingVideo })
        XCTAssertTrue(cameraTransport.sentMessages.contains { $0 is RemoteCmd.StartRecordingVideoAck })
        // The error ack pops monitorRecordingVideo back to video mode.
        XCTAssertEqual(monitorSession.currentStateName(), .monitor)
    }

    // MARK: - Zoom round trip

    func testSetZoomRoundTripAgainstPeerNotInCameraMode() {
        connectBothSessions()
        becomeMonitor(mode: .Photo)

        monitorRef ! UICmd.SetZoom(zoomFactor: 2.5)
        drainBothSessions()

        let sentZooms = monitorTransport.sentMessages.compactMap { $0 as? RemoteCmd.SetZoom }
        XCTAssertEqual(sentZooms.count, 1)
        XCTAssertEqual(sentZooms[0].zoomFactor, 2.5, accuracy: 0.001)
        XCTAssertTrue(cameraTransport.sentMessages.contains { $0 is RemoteCmd.SetZoomResp })
        XCTAssertEqual(monitorSession.currentStateName(), .monitor)
    }

    // MARK: - Peer disconnect

    func testPeerDisconnectPopsMonitorToScanning() {
        connectBothSessions()
        becomeMonitor(mode: .Photo)

        monitorTransport.simulateRemoteDisconnected()
        drainBothSessions()

        XCTAssertEqual(monitorSession.currentStateName(), .scanning)
    }

    // MARK: - Happy-path photo capture with a camera peer

    func testTakePictureHappyPathAcrossTheWire() {
        connectBothSessions()

        // Camera side: enter the camera state with a fake capture device.
        let fakeCamera = LoopbackFakeCamera()
        fakeCamera.sessionRef = cameraRef
        var cameraSaves: [Data] = []
        cameraSession.photoLibrarySaver = { data in cameraSaves.append(data) }
        cameraRef ! UICmd.BecomeCamera(sender: nil, ctrl: fakeCamera)
        drainBothSessions()
        XCTAssertEqual(cameraSession.currentStateName(), .camera)

        becomeMonitor(mode: .Photo)
        XCTAssertEqual(monitorSession.currentStateName(), .monitor)

        monitorRef ! UICmd.TakePicture(sender: nil, sendMediaToRemote: true)
        drainBothSessions()

        // The fake camera captured exactly once and the photo was saved camera-side.
        XCTAssertEqual(fakeCamera.takePictureCalls, [true])
        XCTAssertEqual(cameraSaves, [fakeCamera.photoBytes])

        // Ack + response carrying the picture crossed back to the monitor.
        XCTAssertTrue(cameraTransport.sentMessages.contains { $0 is RemoteCmd.TakePicAck })
        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.TakePicResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertEqual(resps.first?.pic, fakeCamera.photoBytes)

        // Both sides settled back into their steady states, with no errors surfaced.
        XCTAssertEqual(monitorSession.currentStateName(), .monitor)
        XCTAssertEqual(cameraSession.currentStateName(), .camera)
        XCTAssertTrue(monitorAlerts.shownErrors.isEmpty)
        XCTAssertTrue(cameraAlerts.shownErrors.isEmpty)
    }

    // MARK: - Happy-path camera-control round trips

    /// Wires a fake camera into the camera-side session and a photo-mode monitor
    /// on the other side; returns the fake.
    private func connectCameraAndMonitor(monitorMode: RecordingMode = .Photo) -> LoopbackFakeCamera {
        connectBothSessions()
        let fakeCamera = LoopbackFakeCamera()
        fakeCamera.sessionRef = cameraRef
        cameraRef ! UICmd.BecomeCamera(sender: nil, ctrl: fakeCamera)
        drainBothSessions()
        becomeMonitor(mode: monitorMode)
        cameraTransport.sentMessages.removeAll()
        monitorTransport.sentMessages.removeAll()
        return fakeCamera
    }

    func testToggleFlashHappyPathAcrossTheWire() {
        let fakeCamera = connectCameraAndMonitor()

        monitorRef ! UICmd.ToggleFlash()
        drainBothSessions()

        // The fake flips .off -> .on and the mode crosses back in the response.
        XCTAssertEqual(fakeCamera.currentFlashMode, .on)
        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.ToggleFlashResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertEqual(resps.first?.flashMode, .on)
        XCTAssertNil(resps.first?.error)
        // Response unbecomes monitorTogglingFlash back to photo mode.
        XCTAssertEqual(monitorSession.currentStateName(), .monitor)
        XCTAssertTrue(monitorAlerts.shownErrors.isEmpty)
    }

    func testToggleCameraHappyPathCarriesCapabilities() {
        _ = connectCameraAndMonitor()

        monitorRef ! UICmd.ToggleCamera()
        drainBothSessions()

        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.ToggleCameraResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertNil(resps.first?.error)
        XCTAssertNotNil(resps.first?.cameraCapabilities,
                        "toggle response must carry fresh capabilities")
        XCTAssertEqual(resps.first?.cameraCapabilities?.currentLens, .wideAngle)
        XCTAssertEqual(monitorSession.currentStateName(), .monitor)
    }

    func testSetZoomHappyPathEchoesFactorAndRange() {
        let fakeCamera = connectCameraAndMonitor()

        monitorRef ! UICmd.SetZoom(zoomFactor: 2.5)
        drainBothSessions()

        XCTAssertEqual(fakeCamera.zoomCalls, [2.5])
        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.SetZoomResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertEqual(resps.first?.zoomFactor ?? 0, 2.5, accuracy: 0.001)
        XCTAssertEqual(resps.first?.zoomRange?.maxZoom ?? 0, 10, accuracy: 0.001)
        XCTAssertEqual(monitorSession.currentStateName(), .monitor)
    }

    func testSwitchLensHappyPathAcrossTheWire() {
        let fakeCamera = connectCameraAndMonitor()

        monitorRef ! UICmd.SwitchLens(lensType: .telephoto)
        drainBothSessions()

        XCTAssertEqual(fakeCamera.lensSwitches, [.telephoto])
        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.SwitchLensResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertEqual(resps.first?.lensType, .telephoto)
        XCTAssertNil(resps.first?.error)
        // Response unbecomes monitorSwitchingLens back to photo mode.
        XCTAssertEqual(monitorSession.currentStateName(), .monitor)
    }

    /// The full 3-step stop protocol across both machines:
    /// StopRecordingVideo → StopRecordingVideoAck → StopRecordingVideoResp.
    func testVideoRecordingStartStopProtocolAcrossTheWire() {
        let fakeCamera = connectCameraAndMonitor(monitorMode: .Video)

        // Start: monitor's shutter sends StartRecordingVideo.
        monitorRef ! UICmd.TakePicture(sender: nil, sendMediaToRemote: true)
        drainBothSessions()

        XCTAssertEqual(fakeCamera.startRecordingCalls, 1)
        XCTAssertEqual(cameraSession.currentStateName(), .cameraRecordingVideo)
        XCTAssertEqual(monitorSession.currentStateName(), .monitorRecordingVideo)

        // Stop: the same shutter now sends StopRecordingVideo.
        monitorRef ! UICmd.TakePicture(sender: nil, sendMediaToRemote: true)
        drainBothSessions()

        XCTAssertEqual(fakeCamera.stopRecordingCalls, [true])
        XCTAssertTrue(cameraTransport.sentMessages.contains { $0 is RemoteCmd.StopRecordingVideoAck })
        XCTAssertTrue(cameraTransport.sentMessages.contains { $0 is RemoteCmd.StopRecordingVideoResp })
        // Camera popped back to .camera after transmitting; monitor walked
        // monitorRecordingVideo → monitorWaitingForVideo → .monitor.
        XCTAssertEqual(cameraSession.currentStateName(), .camera)
        XCTAssertEqual(monitorSession.currentStateName(), .monitor)
        XCTAssertTrue(monitorAlerts.shownErrors.isEmpty)
        XCTAssertTrue(cameraAlerts.shownErrors.isEmpty)
    }
}

// MARK: - Fake camera for happy-path flows

/// A `CameraControlling` fake that "captures" a photo by sending `OnPicture`
/// back to its session — the same message the real capture callback sends —
/// and completes a stopped recording by injecting `StopRecordingVideoResp`,
/// the way the real pipeline's completion does.
final class LoopbackFakeCamera: FakeWatchCameraController {
    var sessionRef: ActorRef?
    let photoBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x42])

    override func takePicture(_ sendMediaToRemote: Bool) {
        super.takePicture(sendMediaToRemote)
        if let sessionRef {
            sessionRef ! UICmd.OnPicture(sender: nil, pic: photoBytes)
        }
    }

    override func stopRecordingVideo(_ shouldSendVideo: Bool) {
        super.stopRecordingVideo(shouldSendVideo)
        if let sessionRef {
            sessionRef ! RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: nil)
        }
    }

    override func gatherCurrentCameraCapabilities() -> RemoteCmd.CameraCapabilitiesResp? {
        RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, currentLens: .wideAngle, currentZoom: 1.0, error: nil)
    }
}
