//
//  LoopbackSessionTests.swift
//  RemoteShutterTests
//
//  Two SessionCoordinators wired to each other through an in-process
//  transport that passes every message through the real FlatBuffers
//  encode/decode path. This exercises full protocol round trips across
//  BOTH state machines — the closest thing to a two-device test that can
//  run in CI.
//

import XCTest
import MultipeerConnectivity
import AVFoundation
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
    var sentMessages: [Message] = []

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

    func send(_ msg: Message, to peers: [MCPeerID],
              mode: MCSessionSendDataMode) -> Try<Message> {
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

// MARK: - Fake camera for happy-path flows

/// A `CameraControlling` fake that "captures" a photo by sending `OnPicture`
/// back to its session — the same message the real capture callback sends —
/// and completes a stopped recording by injecting `StopRecordingVideoResp`,
/// the way the real pipeline's completion does.
final class LoopbackFakeCamera: FakeCameraControlling {
    weak var coordinator: SessionCoordinator?

    override func takePicture(_ sendMediaToRemote: Bool) {
        super.takePicture(sendMediaToRemote)
        coordinator?.tell(UICmd.OnPicture(sender: nil, pic: photoBytes))
    }

    override func startRecordingVideo() {
        super.startRecordingVideo()
        // The real pipeline sends this to the local session once the writer
        // produces its first frames (RecordingPipeline.processFrame).
        coordinator?.tell(RemoteCmd.StartRecordingVideoAck(sender: nil, recordingStartTime: Date()))
    }

    override func stopRecordingVideo(_ shouldSendVideo: Bool) {
        super.stopRecordingVideo(shouldSendVideo)
        coordinator?.tell(RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: nil))
    }
}

// MARK: - Tests

class LoopbackSessionTests: XCTestCase {

    private var monitorCoordinator: SessionCoordinator!
    private var monitorTransport: LoopbackMultipeerService!
    private var monitorAlerts: FakeAlertPresenter!
    private var monitorPresenter: MonitorPresenter!

    private var cameraCoordinator: SessionCoordinator!
    private var cameraTransport: LoopbackMultipeerService!
    private var cameraAlerts: FakeAlertPresenter!

    private var lobby: FakeScannerLobby!
    private var lobbyWrapper: WeakScannerLobby!

    override func setUp() async throws {
        try await super.setUp()

        monitorCoordinator = SessionCoordinator()
        cameraCoordinator = SessionCoordinator()

        monitorTransport = LoopbackMultipeerService(peerName: "MonitorDevice")
        cameraTransport = LoopbackMultipeerService(peerName: "CameraDevice")
        monitorTransport.remote = cameraTransport
        cameraTransport.remote = monitorTransport
        monitorTransport.delegate = monitorCoordinator
        cameraTransport.delegate = cameraCoordinator
        await monitorCoordinator.setMultipeerService(monitorTransport)
        await cameraCoordinator.setMultipeerService(cameraTransport)

        monitorAlerts = FakeAlertPresenter()
        cameraAlerts = FakeAlertPresenter()
        await monitorCoordinator.setAlertPresenter(monitorAlerts)
        await cameraCoordinator.setAlertPresenter(cameraAlerts)

        monitorPresenter = MonitorPresenter()
        lobby = FakeScannerLobby()
        lobbyWrapper = WeakScannerLobby(lobby)

        await drainBothSessions()
    }

    override func tearDown() async throws {
        await drainBothSessions()
        monitorCoordinator.stop()
        cameraCoordinator.stop()
        monitorCoordinator = nil
        cameraCoordinator = nil
        monitorTransport = nil
        cameraTransport = nil
        monitorAlerts = nil
        cameraAlerts = nil
        monitorPresenter = nil
        lobby = nil
        lobbyWrapper = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// A message hop lands on the peer's inbox, and replies hop back. Drain
    /// both inboxes several times so multi-hop exchanges settle.
    private func drainBothSessions(hops: Int = 6) async {
        for _ in 0..<hops {
            await monitorCoordinator.waitForIdle()
            await cameraCoordinator.waitForIdle()
            await MainActor.run { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02)) }
        }
    }

    /// Puts both sessions in the connected state, each pointing at the other's peer ID.
    private func connectBothSessions() async {
        await monitorCoordinator.seed(state: .connected, lobby: lobbyWrapper, peer: cameraTransport.localPeerID)
        await cameraCoordinator.seed(state: .connected, lobby: lobbyWrapper, peer: monitorTransport.localPeerID)

        await drainBothSessions()
        monitorTransport.sentMessages.removeAll()
        cameraTransport.sentMessages.removeAll()
    }

    private func becomeMonitor(mode: RecordingMode) async {
        monitorCoordinator.tell(UICmd.BecomeMonitor(presenter: monitorPresenter, mode: mode))
        await drainBothSessions()
    }

    // MARK: - Handshake

    func testBecomeMonitorHandshakeCrossesTheWire() async {
        await connectBothSessions()

        await becomeMonitor(mode: .Photo)

        let monitorState = await monitorCoordinator.currentStateName()
        XCTAssertEqual(monitorState, .monitor)
        // The handshake and the photo-mode frame request both crossed the wire.
        XCTAssertTrue(monitorTransport.sentMessages.contains { $0 is RemoteCmd.PeerBecameMonitor })
        XCTAssertTrue(monitorTransport.sentMessages.contains { $0 is RemoteCmd.RequestFrame })
        // The peer decoded PeerBecameMonitor without tripping the incompatibility path.
        let cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .connected)
        XCTAssertTrue(cameraAlerts.shownErrors.isEmpty)
    }

    // MARK: - Take picture round trip

    func testTakePictureRoundTripAgainstPeerNotInCameraMode() async {
        await connectBothSessions()
        await becomeMonitor(mode: .Photo)

        monitorCoordinator.tell(UICmd.TakePicture(sender: nil, sendMediaToRemote: true))
        await drainBothSessions()

        // TakePic crossed to the peer; the peer (not in camera mode) answered with
        // a TakePicResp carrying an error; the monitor popped back to photo mode
        // and surfaced the error.
        XCTAssertTrue(monitorTransport.sentMessages.contains { $0 is RemoteCmd.TakePic })
        XCTAssertTrue(cameraTransport.sentMessages.contains { $0 is RemoteCmd.TakePicResp })
        let monitorState = await monitorCoordinator.currentStateName()
        XCTAssertEqual(monitorState, .monitor)
        XCTAssertFalse(monitorAlerts.shownErrors.isEmpty)
        let cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .connected)
    }

    // MARK: - Toggle flash round trip

    func testToggleFlashRoundTripAgainstPeerNotInCameraMode() async {
        await connectBothSessions()
        await becomeMonitor(mode: .Photo)

        monitorCoordinator.tell(UICmd.ToggleFlash())
        await drainBothSessions()

        XCTAssertTrue(monitorTransport.sentMessages.contains { $0 is RemoteCmd.ToggleFlash })
        XCTAssertTrue(cameraTransport.sentMessages.contains { $0 is RemoteCmd.ToggleFlashResp })
        // Error response unbecomes monitorTogglingFlash back to photo mode.
        let monitorState = await monitorCoordinator.currentStateName()
        XCTAssertEqual(monitorState, .monitor)
    }

    // MARK: - Video recording round trip

    func testStartRecordingRoundTripAgainstPeerNotInCameraMode() async {
        await connectBothSessions()
        await becomeMonitor(mode: .Video)

        monitorCoordinator.tell(UICmd.TakePicture(sender: nil, sendMediaToRemote: true))
        await drainBothSessions()

        XCTAssertTrue(monitorTransport.sentMessages.contains { $0 is RemoteCmd.StartRecordingVideo })
        XCTAssertTrue(cameraTransport.sentMessages.contains { $0 is RemoteCmd.StartRecordingVideoAck })
        // The error ack pops monitorRecordingVideo back to video mode.
        let monitorState = await monitorCoordinator.currentStateName()
        XCTAssertEqual(monitorState, .monitor)
    }

    // MARK: - Zoom round trip

    func testSetZoomRoundTripAgainstPeerNotInCameraMode() async {
        await connectBothSessions()
        await becomeMonitor(mode: .Photo)

        monitorCoordinator.tell(UICmd.SetZoom(zoomFactor: 2.5))
        await drainBothSessions()

        let sentZooms = monitorTransport.sentMessages.compactMap { $0 as? RemoteCmd.SetZoom }
        XCTAssertEqual(sentZooms.count, 1)
        XCTAssertEqual(sentZooms[0].zoomFactor, 2.5, accuracy: 0.001)
        XCTAssertTrue(cameraTransport.sentMessages.contains { $0 is RemoteCmd.SetZoomResp })
        let monitorState = await monitorCoordinator.currentStateName()
        XCTAssertEqual(monitorState, .monitor)
    }

    // MARK: - Peer disconnect

    func testPeerDisconnectPopsMonitorToScanning() async {
        await connectBothSessions()
        await becomeMonitor(mode: .Photo)

        monitorTransport.simulateRemoteDisconnected()
        await drainBothSessions()

        let monitorState = await monitorCoordinator.currentStateName()
        XCTAssertEqual(monitorState, .scanning)
    }

    // MARK: - Happy-path photo capture with a camera peer

    func testTakePictureHappyPathAcrossTheWire() async {
        await connectBothSessions()

        // Camera side: enter the camera state with a fake capture device.
        let fakeCamera = LoopbackFakeCamera()
        fakeCamera.coordinator = cameraCoordinator
        var cameraSaves: [Data] = []
        await cameraCoordinator.setPhotoLibrarySaver { data in cameraSaves.append(data) }
        cameraCoordinator.tell(UICmd.BecomeCamera(sender: nil, ctrl: fakeCamera))
        await drainBothSessions()
        let cameraStateAfterBecome = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraStateAfterBecome, .camera)

        await becomeMonitor(mode: .Photo)
        let monitorStateAfterBecome = await monitorCoordinator.currentStateName()
        XCTAssertEqual(monitorStateAfterBecome, .monitor)

        monitorCoordinator.tell(UICmd.TakePicture(sender: nil, sendMediaToRemote: true))
        await drainBothSessions()

        // The fake camera captured exactly once and the photo was saved camera-side.
        XCTAssertEqual(fakeCamera.takePictureCalls, [true])
        XCTAssertEqual(cameraSaves, [fakeCamera.photoBytes])

        // Ack + response carrying the picture crossed back to the monitor.
        XCTAssertTrue(cameraTransport.sentMessages.contains { $0 is RemoteCmd.TakePicAck })
        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.TakePicResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertEqual(resps.first?.pic, fakeCamera.photoBytes)

        // Both sides settled back into their steady states, with no errors surfaced.
        let monitorState = await monitorCoordinator.currentStateName()
        XCTAssertEqual(monitorState, .monitor)
        let cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .camera)
        XCTAssertTrue(monitorAlerts.shownErrors.isEmpty)
        XCTAssertTrue(cameraAlerts.shownErrors.isEmpty)
    }

    // MARK: - Happy-path camera-control round trips

    /// Wires a fake camera into the camera-side session and a photo-mode monitor
    /// on the other side; returns the fake.
    private func connectCameraAndMonitor(monitorMode: RecordingMode = .Photo) async -> LoopbackFakeCamera {
        await connectBothSessions()
        let fakeCamera = LoopbackFakeCamera()
        fakeCamera.coordinator = cameraCoordinator
        cameraCoordinator.tell(UICmd.BecomeCamera(sender: nil, ctrl: fakeCamera))
        await drainBothSessions()
        await becomeMonitor(mode: monitorMode)
        cameraTransport.sentMessages.removeAll()
        monitorTransport.sentMessages.removeAll()
        return fakeCamera
    }

    func testToggleFlashHappyPathAcrossTheWire() async {
        let fakeCamera = await connectCameraAndMonitor()

        monitorCoordinator.tell(UICmd.ToggleFlash())
        await drainBothSessions()

        // The fake flips .off -> .on and the mode crosses back in the response.
        XCTAssertEqual(fakeCamera.flashMode, .on)
        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.ToggleFlashResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertEqual(resps.first?.flashMode, .on)
        XCTAssertNil(resps.first?.error)
        // Response unbecomes monitorTogglingFlash back to photo mode.
        let monitorState = await monitorCoordinator.currentStateName()
        XCTAssertEqual(monitorState, .monitor)
        XCTAssertTrue(monitorAlerts.shownErrors.isEmpty)
    }

    func testToggleCameraHappyPathCarriesCapabilities() async {
        _ = await connectCameraAndMonitor()

        monitorCoordinator.tell(UICmd.ToggleCamera())
        await drainBothSessions()

        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.ToggleCameraResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertNil(resps.first?.error)
        XCTAssertNotNil(resps.first?.cameraCapabilities,
                        "toggle response must carry fresh capabilities")
        XCTAssertEqual(resps.first?.cameraCapabilities?.currentLens, .wideAngle)
        let monitorState = await monitorCoordinator.currentStateName()
        XCTAssertEqual(monitorState, .monitor)
    }

    func testSetZoomHappyPathEchoesFactorAndRange() async {
        let fakeCamera = await connectCameraAndMonitor()

        monitorCoordinator.tell(UICmd.SetZoom(zoomFactor: 2.5))
        await drainBothSessions()

        XCTAssertEqual(fakeCamera.zoomCalls, [2.5])
        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.SetZoomResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertEqual(resps.first?.zoomFactor ?? 0, 2.5, accuracy: 0.001)
        XCTAssertEqual(resps.first?.zoomRange?.maxZoom ?? 0, 10, accuracy: 0.001)
        let monitorState = await monitorCoordinator.currentStateName()
        XCTAssertEqual(monitorState, .monitor)
    }

    func testSwitchLensHappyPathAcrossTheWire() async {
        let fakeCamera = await connectCameraAndMonitor()

        monitorCoordinator.tell(UICmd.SwitchLens(lensType: .telephoto))
        await drainBothSessions()

        XCTAssertEqual(fakeCamera.lensSwitches, [.telephoto])
        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.SwitchLensResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertEqual(resps.first?.lensType, .telephoto)
        XCTAssertNil(resps.first?.error)
        // Response unbecomes monitorSwitchingLens back to photo mode.
        let monitorState = await monitorCoordinator.currentStateName()
        XCTAssertEqual(monitorState, .monitor)
    }

    /// The full 3-step stop protocol across both machines:
    /// StopRecordingVideo → StopRecordingVideoAck → StopRecordingVideoResp.
    func testVideoRecordingStartStopProtocolAcrossTheWire() async {
        let fakeCamera = await connectCameraAndMonitor(monitorMode: .Video)

        // Start: monitor's shutter sends StartRecordingVideo.
        monitorCoordinator.tell(UICmd.TakePicture(sender: nil, sendMediaToRemote: true))
        await drainBothSessions()

        XCTAssertEqual(fakeCamera.startRecordingCalls, 1)
        let cameraStateRecording = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraStateRecording, .cameraRecordingVideo)
        let monitorStateRecording = await monitorCoordinator.currentStateName()
        XCTAssertEqual(monitorStateRecording, .monitorRecordingVideo)

        // The success ack (recording start time, used for the monitor's timer
        // sync) must be forwarded to the peer, not just the error ack.
        let startAcks = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.StartRecordingVideoAck }
        XCTAssertEqual(startAcks.count, 1, "camera must forward the success StartRecordingVideoAck to the monitor")
        XCTAssertNotNil(startAcks.first?.recordingStartTime)

        // Stop: the same shutter now sends StopRecordingVideo.
        monitorCoordinator.tell(UICmd.TakePicture(sender: nil, sendMediaToRemote: true))
        await drainBothSessions()

        XCTAssertEqual(fakeCamera.stopRecordingCalls, [true])
        XCTAssertTrue(cameraTransport.sentMessages.contains { $0 is RemoteCmd.StopRecordingVideoAck })
        XCTAssertTrue(cameraTransport.sentMessages.contains { $0 is RemoteCmd.StopRecordingVideoResp })
        // Camera popped back to .camera after transmitting; monitor walked
        // monitorRecordingVideo → monitorWaitingForVideo → .monitor.
        let cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .camera)
        let monitorState = await monitorCoordinator.currentStateName()
        XCTAssertEqual(monitorState, .monitor)
        XCTAssertTrue(monitorAlerts.shownErrors.isEmpty)
        XCTAssertTrue(cameraAlerts.shownErrors.isEmpty)
    }
}
