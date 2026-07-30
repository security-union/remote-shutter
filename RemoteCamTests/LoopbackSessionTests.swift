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
import MPCCompat
import Stormo
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
    ///
    /// Lock-backed rather than a plain array: `send(_:to:mode:)` is called from the
    /// coordinator's actor context while the test body reads this from the test thread.
    /// As a bare `[Message]` that was a data race, which Thread Sanitizer turned into a
    /// crash (`sentMessages.modify`) on roughly half of all TSan runs of this suite.
    ///
    /// The public shape is unchanged — still a settable `[Message]` — so reads and the
    /// `removeAll()` calls throughout these tests keep working untouched.
    private let sentMessagesStorage = Locked<[Message]>([])
    var sentMessages: [Message] {
        get { sentMessagesStorage.value }
        set { sentMessagesStorage.value = newValue }
    }

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
        // One lock acquisition: going through the computed property would read, append to
        // a copy, then write back, losing a concurrent append.
        sentMessagesStorage.mutate { $0.append(msg) }

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

    // MARK: - Tap to focus

    func testFocusAtPointHappyPathAcrossTheWire() async {
        let fakeCamera = await connectCameraAndMonitor()

        monitorCoordinator.tell(UICmd.FocusAtPoint(x: 0.25, y: 0.75))
        await drainBothSessions()

        XCTAssertEqual(fakeCamera.focusCalls.count, 1)
        XCTAssertEqual(fakeCamera.focusCalls.first?.x ?? -1, 0.25, accuracy: 0.001)
        XCTAssertEqual(fakeCamera.focusCalls.first?.y ?? -1, 0.75, accuracy: 0.001)
        // Fire-and-forget: no response is sent, and it was never a TakePicture.
        XCTAssertTrue(fakeCamera.takePictureCalls.isEmpty)
        let monitorState = await monitorCoordinator.currentStateName()
        XCTAssertEqual(monitorState, .monitor)
    }

    /// Safety gate mirroring SelectCameraDevice: old peers decode the unknown
    /// FocusAtPoint action as TakePicture, so the monitor must never send it to a
    /// peer whose capabilities did not advertise focus-point support.
    func testFocusAtPointIsNeverSentToLegacyPeer() async {
        await connectBothSessions()
        let fakeCamera = LoopbackFakeCamera()
        fakeCamera.advertisesFocusPoint = false   // peer predates tap-to-focus
        fakeCamera.coordinator = cameraCoordinator
        cameraCoordinator.tell(UICmd.BecomeCamera(sender: nil, ctrl: fakeCamera))
        await drainBothSessions()
        await becomeMonitor(mode: .Photo)
        monitorTransport.sentMessages.removeAll()

        monitorCoordinator.tell(UICmd.FocusAtPoint(x: 0.4, y: 0.6))
        await drainBothSessions()

        XCTAssertFalse(monitorTransport.sentMessages.contains { $0 is RemoteCmd.FocusAtPoint },
                       "FocusAtPoint must be gated on advertised supports_focus_point")
        XCTAssertTrue(fakeCamera.focusCalls.isEmpty)
        XCTAssertTrue(fakeCamera.takePictureCalls.isEmpty,
                      "an ungated command would decode as TakePicture on an old peer")
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

    // MARK: - VP9 preview version gate

    /// Puts the camera-side session into `.camera` with a fake capture device.
    private func enterCameraState() async -> LoopbackFakeCamera {
        await connectBothSessions()
        let fakeCamera = LoopbackFakeCamera()
        fakeCamera.coordinator = cameraCoordinator
        cameraCoordinator.tell(UICmd.BecomeCamera(sender: nil, ctrl: fakeCamera))
        await drainBothSessions()
        cameraTransport.sentMessages.removeAll()
        return fakeCamera
    }

    /// A peer version on this build's own major, so `PeerAppCompatibility` stays
    /// out of the way and the VP9 tests below keep testing the VP9 gate rather
    /// than accidentally tripping the app-version gate.
    private var sameMajorVersion: String {
        "\(PeerAppCompatibility.localVersion?.major ?? 0).0.0"
    }

    /// A version-qualified monitor (bundleVersion >= threshold) is answered
    /// normally: the camera stays in `.camera` and broadcasts capabilities, then
    /// streams VP9 to it. No capability handshake, no incompatibility.
    func testQualifiedMonitorIsAcceptedAndAnswered() async {
        let threshold = VP9PreviewCompatibility.minimumPeerBundleVersion
        _ = await enterCameraState()

        cameraCoordinator.tell(RemoteCmd.PeerBecameMonitor(
            bundleVersion: threshold, shortVersion: sameMajorVersion, platform: "iPhone"))
        await drainBothSessions()

        let cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .camera, "a qualified monitor keeps the camera streaming")
        XCTAssertTrue(cameraTransport.sentMessages.contains { $0 is RemoteCmd.CameraCapabilitiesResp },
                      "the camera answers a qualified monitor with capabilities")
    }

    /// A monitor too old to decode VP9 (0 < bundleVersion < threshold) is sent to
    /// the update-required flow: the camera pops to scanning and never answers it
    /// (no stills fallback, no capability negotiation).
    func testOutOfDateMonitorIsToldToUpdate() async {
        let old = VP9PreviewCompatibility.minimumPeerBundleVersion - 1
        _ = await enterCameraState()

        cameraCoordinator.tell(RemoteCmd.PeerBecameMonitor(
            bundleVersion: old, shortVersion: sameMajorVersion, platform: "iPhone"))
        await drainBothSessions()

        let cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .scanning, "an out-of-date monitor sends the camera to update/scanning")
        XCTAssertFalse(cameraTransport.sentMessages.contains { $0 is RemoteCmd.CameraCapabilitiesResp },
                       "the camera must not answer a monitor that can't decode its VP9 stream")
    }

    /// An unknown build (`bundleVersion <= 0`) is incompatible even when its app
    /// version is on this major: the VP9 gate still rejects it.
    func testUnknownBuildMonitorStillTreatedAsIncompatible() async {
        _ = await enterCameraState()

        cameraCoordinator.tell(RemoteCmd.PeerBecameMonitor(
            bundleVersion: 0, shortVersion: sameMajorVersion, platform: "iPhone"))
        await drainBothSessions()

        let cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .scanning, "an unknown-build (<= 0) monitor is still incompatible")
    }

    // MARK: - App-version gate (semver major)

    /// A monitor on a different app major is refused before any feature gate
    /// runs: the camera pops to scanning and never answers with capabilities,
    /// even though its build number is new enough for VP9.
    func testMonitorOnDifferentAppMajorIsRefused() async {
        guard let local = PeerAppCompatibility.localVersion else {
            return XCTFail("the test host must carry a parseable CFBundleShortVersionString")
        }
        _ = await enterCameraState()

        cameraCoordinator.tell(RemoteCmd.PeerBecameMonitor(
            bundleVersion: VP9PreviewCompatibility.minimumPeerBundleVersion,
            shortVersion: "\(local.major + 1).0.0",
            platform: "iPhone"))
        await drainBothSessions()

        let cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .scanning, "a peer on another app major cannot hold a session")
        XCTAssertFalse(cameraTransport.sentMessages.contains { $0 is RemoteCmd.CameraCapabilitiesResp },
                       "the camera must not negotiate with a peer on another major")
    }

    /// Minor and patch differences are not breaking: a monitor on the same major
    /// but a higher minor is answered normally.
    func testMonitorOnHigherMinorIsAccepted() async {
        guard let local = PeerAppCompatibility.localVersion else {
            return XCTFail("the test host must carry a parseable CFBundleShortVersionString")
        }
        _ = await enterCameraState()

        cameraCoordinator.tell(RemoteCmd.PeerBecameMonitor(
            bundleVersion: VP9PreviewCompatibility.minimumPeerBundleVersion,
            shortVersion: "\(local.major).\(local.minor + 7).3",
            platform: "iPhone"))
        await drainBothSessions()

        let cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .camera, "a newer minor on the same major stays compatible")
        XCTAssertTrue(cameraTransport.sentMessages.contains { $0 is RemoteCmd.CameraCapabilitiesResp },
                      "the camera answers a same-major monitor with capabilities")
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
