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
final class LoopbackFakeCamera: FakeCameraControlling, @unchecked Sendable {
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

    // MARK: - Camera device selection

    func testSelectCameraDeviceHappyPathAcrossTheWire() async {
        let fakeCamera = await connectCameraAndMonitor()

        monitorCoordinator.tell(UICmd.SelectCameraDevice(uniqueID: "fake-front"))
        await drainBothSessions()

        // The camera switched devices and answered with fresh capabilities.
        XCTAssertEqual(fakeCamera.deviceSelections, ["fake-front"])
        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.SelectCameraDeviceResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertNil(resps.first?.error)
        XCTAssertEqual(resps.first?.cameraCapabilities?.activeDeviceID, "fake-front")
        XCTAssertEqual(resps.first?.cameraCapabilities?.cameraDevices.count, 2)
        XCTAssertEqual(
            resps.first?.cameraCapabilities?.cameraDevices.first { $0.isActive }?.uniqueID,
            "fake-front")

        let monitorState = await monitorCoordinator.currentStateName()
        XCTAssertEqual(monitorState, .monitor)
        XCTAssertTrue(monitorAlerts.shownErrors.isEmpty)
    }

    /// The safety gate: old peers decode unknown command actions as
    /// TakePicture, so a monitor must never emit SelectCameraDevice unless the
    /// peer's capabilities advertised a device list.
    func testSelectCameraDeviceIsNeverSentToLegacyPeer() async {
        await connectBothSessions()
        let fakeCamera = LoopbackFakeCamera()
        fakeCamera.advertisesCameraDevices = false   // legacy-shaped capabilities
        fakeCamera.coordinator = cameraCoordinator
        cameraCoordinator.tell(UICmd.BecomeCamera(sender: nil, ctrl: fakeCamera))
        await drainBothSessions()
        await becomeMonitor(mode: .Photo)
        monitorTransport.sentMessages.removeAll()

        monitorCoordinator.tell(UICmd.SelectCameraDevice(uniqueID: "fake-front"))
        await drainBothSessions()

        XCTAssertFalse(monitorTransport.sentMessages.contains { $0 is RemoteCmd.SelectCameraDevice },
                       "SelectCameraDevice must be gated on advertised camera_devices")
        XCTAssertTrue(fakeCamera.deviceSelections.isEmpty)
        XCTAssertTrue(fakeCamera.takePictureCalls.isEmpty,
                      "an ungated command would decode as TakePicture on an old peer")
        // The monitor quietly stays where it was.
        let monitorState = await monitorCoordinator.currentStateName()
        XCTAssertEqual(monitorState, .monitor)
    }

    /// A suspended camera (clamshell built-in: connected, zero frames) is
    /// advertised with its flag so the monitor grays it out — and if a peer
    /// selects it anyway (old UI, race), the camera answers with an error
    /// instead of switching to a dead device.
    func testSuspendedDeviceIsAdvertisedAndRejectedOnSelection() async {
        await connectBothSessions()
        let fakeCamera = LoopbackFakeCamera()
        fakeCamera.availableDevices.append(CameraDeviceDescriptor(
            uniqueID: "builtin-lid-closed", localizedName: "MacBook Pro Camera",
            position: .unspecified, deviceType: .builtInWideAngleCamera,
            isSuspended: true))
        fakeCamera.coordinator = cameraCoordinator
        cameraCoordinator.tell(UICmd.BecomeCamera(sender: nil, ctrl: fakeCamera))
        await drainBothSessions()
        await becomeMonitor(mode: .Photo)
        cameraTransport.sentMessages.removeAll()

        // The handshake capabilities already advertised the suspended device.
        monitorCoordinator.tell(UICmd.SelectCameraDevice(uniqueID: "builtin-lid-closed"))
        await drainBothSessions()

        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.SelectCameraDeviceResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertNotNil(resps.first?.error, "selecting a suspended camera must fail loudly")
        // The camera did not switch away from its healthy device.
        let current = await fakeCamera.currentCameraDevice()
        XCTAssertEqual(current?.uniqueID, "fake-back")
    }

    /// Hot-plug contract: when a camera appears or vanishes, the rig tells its
    /// OWN coordinator RequestCameraCapabilities (CameraRig's
    /// onCameraDevicesChanged handler) — the camera state must answer by
    /// broadcasting fresh capabilities, so the monitor's picker updates live.
    func testHotPlugRebroadcastsCapabilitiesWithNewDeviceList() async {
        let fakeCamera = await connectCameraAndMonitor()

        // A USB camera appears…
        fakeCamera.availableDevices.append(CameraDeviceDescriptor(
            uniqueID: "usb-0", localizedName: "USB Camera",
            position: .unspecified, deviceType: .builtInWideAngleCamera))
        // …and the rig nudges its own coordinator, as the hot-plug observer does.
        cameraCoordinator.tell(RemoteCmd.RequestCameraCapabilities())
        await drainBothSessions()

        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.CameraCapabilitiesResp }
        XCTAssertEqual(resps.count, 1, "hot-plug must trigger exactly one capabilities broadcast")
        XCTAssertEqual(resps.first?.cameraDevices.count, 3)
        XCTAssertTrue(resps.first?.cameraDevices.contains { $0.uniqueID == "usb-0" } ?? false,
                      "the freshly plugged camera must be advertised to the monitor")
    }

    /// A camera can accept the input swap and then never deliver a frame (a
    /// wedged virtual camera, e.g. OBS in a sandboxed app). The selection
    /// must come back as a VISIBLE error naming the device — not a success
    /// followed by a silently black preview.
    func testSelectingCameraThatDeliversNoFramesReturnsError() async {
        await connectBothSessions()
        let fakeCamera = LoopbackFakeCamera()
        fakeCamera.availableDevices.append(CameraDeviceDescriptor(
            uniqueID: "obs-0", localizedName: "OBS Virtual Camera",
            position: .unspecified, deviceType: .builtInWideAngleCamera))
        fakeCamera.stalledDeviceIDs = ["obs-0"]
        fakeCamera.coordinator = cameraCoordinator
        cameraCoordinator.tell(UICmd.BecomeCamera(sender: nil, ctrl: fakeCamera))
        await drainBothSessions()
        await becomeMonitor(mode: .Photo)
        cameraTransport.sentMessages.removeAll()

        monitorCoordinator.tell(UICmd.SelectCameraDevice(uniqueID: "obs-0"))
        await drainBothSessions()

        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.SelectCameraDeviceResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertNotNil(resps.first?.error, "a no-frames camera must fail the selection")
        XCTAssertTrue(resps.first?.error?._domain.contains("OBS Virtual Camera") ?? false,
                      "the error must name the dead device")
        // The monitor surfaced it as an alert (the toggling state's error path).
        XCTAssertFalse(monitorAlerts.shownErrors.isEmpty)
    }

    func testSelectCameraDeviceWhileRecordingIsRejected() async {
        let fakeCamera = await connectCameraAndMonitor(monitorMode: .Video)

        // Start a recording so the camera sits in a busy state.
        monitorCoordinator.tell(UICmd.TakePicture(sender: nil, sendMediaToRemote: false))
        await drainBothSessions()
        let cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .cameraRecordingVideo)
        cameraTransport.sentMessages.removeAll()

        // Deliver the command straight to the busy camera (as a peer would).
        cameraCoordinator.tell(RemoteCmd.SelectCameraDevice(uniqueID: "fake-front"))
        await drainBothSessions()

        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.SelectCameraDeviceResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertNotNil(resps.first?.error, "busy camera must reject device selection")
        XCTAssertTrue(fakeCamera.deviceSelections.isEmpty)
        // Still recording — the request must not disturb the session.
        let stillRecording = await cameraCoordinator.currentStateName()
        XCTAssertEqual(stillRecording, .cameraRecordingVideo)
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

    // MARK: - VP9 preview negotiation

    /// A VP9-capable monitor advertises decode support on PeerBecameMonitor; the
    /// camera peer (also VP9-capable) enables VP9 streaming for the connection.
    func testVP9CapableMonitorEnablesVP9OnCameraPeer() async {
        await connectBothSessions()
        await cameraCoordinator.setLocalVP9Available(true)
        await monitorCoordinator.setLocalVP9Available(true)

        let fakeCamera = LoopbackFakeCamera()
        fakeCamera.coordinator = cameraCoordinator
        cameraCoordinator.tell(UICmd.BecomeCamera(sender: nil, ctrl: fakeCamera))
        await drainBothSessions()
        await becomeMonitor(mode: .Photo)   // sends PeerBecameMonitor advertising VP9

        let enabled = await cameraCoordinator.peerSupportsVP9PreviewForTesting()
        XCTAssertTrue(enabled, "camera must enable VP9 for a VP9-capable monitor")
        // The advertisement really crossed the wire (not a local shortcut).
        XCTAssertTrue(monitorTransport.sentMessages.contains {
            ($0 as? RemoteCmd.PeerBecameMonitor)?.supportsVP9Preview == true
        })
    }

    /// A legacy monitor (no VP9 decode) advertises false; the camera must keep
    /// streaming stills — sending VP9 bytes would render as a broken still.
    func testLegacyMonitorKeepsCameraOnStills() async {
        await connectBothSessions()
        await cameraCoordinator.setLocalVP9Available(true)
        await monitorCoordinator.setLocalVP9Available(false)   // legacy-shaped monitor

        let fakeCamera = LoopbackFakeCamera()
        fakeCamera.coordinator = cameraCoordinator
        cameraCoordinator.tell(UICmd.BecomeCamera(sender: nil, ctrl: fakeCamera))
        await drainBothSessions()
        await becomeMonitor(mode: .Photo)

        let enabled = await cameraCoordinator.peerSupportsVP9PreviewForTesting()
        XCTAssertFalse(enabled, "camera must not send VP9 to a monitor that can't decode it")
        XCTAssertTrue(monitorTransport.sentMessages.contains {
            ($0 as? RemoteCmd.PeerBecameMonitor)?.supportsVP9Preview == false
        })
    }

    /// Even a VP9-capable monitor gets stills if THIS camera can't encode VP9.
    func testCameraWithoutVP9StreamsStillsToVP9Monitor() async {
        await connectBothSessions()
        await cameraCoordinator.setLocalVP9Available(false)   // camera can't encode
        await monitorCoordinator.setLocalVP9Available(true)

        let fakeCamera = LoopbackFakeCamera()
        fakeCamera.coordinator = cameraCoordinator
        cameraCoordinator.tell(UICmd.BecomeCamera(sender: nil, ctrl: fakeCamera))
        await drainBothSessions()
        await becomeMonitor(mode: .Photo)

        let enabled = await cameraCoordinator.peerSupportsVP9PreviewForTesting()
        XCTAssertFalse(enabled, "no VP9 without a local encoder, even to a VP9 monitor")
    }

    // MARK: - VP9 keyframe recovery

    /// Once the monitor has received a VP9 frame, a decoder desync sends
    /// RequestKeyframe, which reaches the camera and forces a keyframe.
    func testKeyframeRequestRoundTripAfterVP9Frame() async {
        await connectBothSessions()
        let fakeCamera = LoopbackFakeCamera()
        fakeCamera.coordinator = cameraCoordinator
        cameraCoordinator.tell(UICmd.BecomeCamera(sender: nil, ctrl: fakeCamera))
        await drainBothSessions()
        await becomeMonitor(mode: .Photo)

        // The camera's FrameSender is where a keyframe request lands.
        let cameraFrameSender = FrameSender(coordinator: cameraCoordinator)
        cameraCoordinator.setFrameSender(cameraFrameSender)
        monitorTransport.sentMessages.removeAll()

        // The monitor received a VP9 frame (as the transport would deliver one).
        monitorCoordinator.tell(vp9Frame())
        await drainBothSessions()

        monitorCoordinator.tell(UICmd.RequestVideoKeyframe())
        await drainBothSessions()

        XCTAssertTrue(monitorTransport.sentMessages.contains { $0 is RemoteCmd.RequestKeyframe },
                      "a desync after a VP9 frame must send RequestKeyframe")
        XCTAssertTrue(cameraFrameSender.takeKeyframeRequest(),
                      "the camera must forward the request to its VP9 streamer")
        // The camera did not misread it as a photo request.
        XCTAssertTrue(fakeCamera.takePictureCalls.isEmpty)
        let cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .camera)
    }

    /// The old-peer gate: a keyframe request is NEVER sent before a VP9 frame has
    /// been seen — an old camera decodes the unknown action as TakePicture.
    func testKeyframeRequestGatedUntilVP9FrameSeen() async {
        let fakeCamera = await connectCameraAndMonitor()
        monitorTransport.sentMessages.removeAll()

        // No VP9 frame has arrived yet.
        monitorCoordinator.tell(UICmd.RequestVideoKeyframe())
        await drainBothSessions()

        XCTAssertFalse(monitorTransport.sentMessages.contains { $0 is RemoteCmd.RequestKeyframe },
                       "RequestKeyframe must be gated on having received a VP9 frame")
        XCTAssertTrue(fakeCamera.takePictureCalls.isEmpty,
                      "an ungated request would decode as TakePicture on an old peer")
        let monitorState = await monitorCoordinator.currentStateName()
        XCTAssertEqual(monitorState, .monitor)
    }

    /// Builds an OnFrame the way the transport delivers a camera VP9 frame.
    private func vp9Frame() -> RemoteCmd.OnFrame {
        RemoteCmd.OnFrame(
            data: Data([1, 2, 3]), sender: nil, peerId: cameraTransport.localPeerID,
            fps: 30, camPosition: .back, camOrientation: .portrait,
            codec: .vp9, sequenceNumber: 1)
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
