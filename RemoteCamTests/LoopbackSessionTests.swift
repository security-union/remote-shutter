//
//  LoopbackSessionTests.swift
//  RemoteShutterTests
//
//  A camera `SessionCoordinator` and a `MulticamController` (the director)
//  wired to each other through an in-process transport that passes every
//  message through the real FlatBuffers encode/decode path. This exercises
//  full protocol round trips across BOTH machines — the closest thing to a
//  two-device test that can run in CI.
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
    /// Lock-backed rather than a plain array: `send(_:to:mode:)` is called from an
    /// actor context while the test body reads this from the test thread. As a
    /// bare `[Message]` that was a data race, which Thread Sanitizer turned into a
    /// crash on roughly half of all TSan runs of this suite.
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

    func startAdvertisingOnly(discoveryInfo: [String: String]?) {}
    func startBrowsingOnly() {}
    func stopAdvertisingAndBrowsing() {}
    func disconnect() {}
    func stopSession() {}
    func invitePeer(_ peer: MCPeerID, timeout: TimeInterval) {}

    /// Resources sent from this side: (source file, wire name).
    let sentResources = Locked<[(url: URL, name: String)]>([])

    /// Mirrors Stormo's resource transfer: the file is copied to a fresh temp
    /// URL on the receiving side and handed to its delegate, exactly as
    /// `didFinishReceivingResource` sees it in production.
    func sendResource(at url: URL, withName name: String,
                      toPeer peer: MCPeerID,
                      completion: @escaping (Error?) -> Void) -> Progress? {
        sentResources.mutate { $0.append((url, name)) }
        guard let remote, let remoteDelegate = remote.delegate else {
            completion(NSError(domain: "loopback", code: 1)); return nil
        }
        let landed = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(name)")
        do {
            try FileManager.default.copyItem(at: url, to: landed)
        } catch {
            completion(error); return nil
        }
        remoteDelegate.didFinishReceivingResource(name: name, from: localPeerID, at: landed, error: nil)
        completion(nil)
        return nil
    }

    func send(_ msg: Message, to peers: [MCPeerID],
              mode: MCSessionSendDataMode) -> Bool {
        // One lock acquisition: going through the computed property would read, append to
        // a copy, then write back, losing a concurrent append.
        sentMessagesStorage.mutate { $0.append(msg) }
        guard let data = serializeToFlatBuffer(msg) else { return false }
        guard let remote, let remoteDelegate = remote.delegate else { return false }
        guard let decoded = RemoteCmd.fromFlatBuffer(data) else {
            remoteDelegate.didDetectIncompatibility()
            return true
        }
        // Mirror MultipeerService.session(_:didReceive:fromPeer:) routing.
        switch decoded {
        case let requestFrame as RemoteCmd.RequestFrame:
            remoteDelegate.didReceiveFrameRequest(requestFrame)
        case let frame as RemoteCmd.SendFrame:
            remoteDelegate.didReceiveFrame(frame, from: localPeerID)
        default:
            remoteDelegate.didReceiveMessage(decoded, from: localPeerID)
        }
        return true
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

    /// The clip this camera "recorded"; written on demand so a test can
    /// compare bytes across the transfer.
    let clipBytes = Data(repeating: 0xC1, count: 128)
    private(set) var clipURL: URL?
    deinit { clipURL.map { try? FileManager.default.removeItem(at: $0) } }

    /// Mirrors `RecordingPipeline.saveMovieToPhotosAppAndRemotePeer`: with
    /// send-media on, the finished file goes out as a resource and the stop
    /// reply follows the transfer; with it off, the reply goes out at once.
    override func stopRecordingVideo(_ shouldSendVideo: Bool) {
        super.stopRecordingVideo(shouldSendVideo)
        guard shouldSendVideo else {
            coordinator?.tell(RemoteCmd.StopRecordingVideoResp())
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loopback_\(UUID().uuidString).mov")
        try? clipBytes.write(to: url)
        clipURL = url
        coordinator?.tell(UICmd.SendVideoResource(videoURL: url, peers: [], shouldSendToPeer: true, sender: nil))
    }
}

// MARK: - Tests

class LoopbackSessionTests: XCTestCase {

    private var director: MulticamController!
    private var directorTransport: LoopbackMultipeerService!
    private var directorDisplay: FakeMulticamDisplay!
    /// Clips the director handed to its library importer: (landed file, wire name).
    private var directorImports: Locked<[(url: URL, name: String)]>!

    private var cameraCoordinator: SessionCoordinator!
    private var cameraTransport: LoopbackMultipeerService!
    private var cameraAlerts: FakeAlertPresenter!

    private var lobby: FakeScannerLobby!
    private var lobbyWrapper: WeakScannerLobby!

    private var cameraPeer: MCPeerID { cameraTransport.localPeerID }
    private var directorPeer: MCPeerID { directorTransport.localPeerID }

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: TimerPreference.key)
        UserDefaults.standard.removeObject(forKey: SendMediaPreference.key)

        director = MulticamController()
        cameraCoordinator = SessionCoordinator()

        directorTransport = LoopbackMultipeerService(peerName: "DirectorDevice")
        cameraTransport = LoopbackMultipeerService(peerName: "CameraDevice")
        directorTransport.remote = cameraTransport
        cameraTransport.remote = directorTransport
        cameraTransport.delegate = cameraCoordinator
        // The director is the transport delegate from the start (install
        // re-asserts it): a send to a peer with no delegate fails, and the
        // camera answers a failed send by leaving for scanning.
        directorTransport.delegate = director
        await cameraCoordinator.setMultipeerService(cameraTransport)

        cameraAlerts = FakeAlertPresenter()
        await cameraCoordinator.setAlertPresenter(cameraAlerts)

        directorDisplay = FakeMulticamDisplay()
        await director.setDisplay(directorDisplay)
        directorImports = Locked<[(url: URL, name: String)]>([])
        let imports = directorImports!
        await director.setVideoImporter { url, name, completion in
            imports.mutate { $0.append((url, name)) }
            completion(.saved)
        }
        // No timer may fire inside a test: retries are the production loop's
        // business and would re-handshake under the assertions.
        await director.setCapsRetryDelay(60)
        await director.setReconnectRetryDelay(60)

        lobby = FakeScannerLobby()
        lobbyWrapper = WeakScannerLobby(lobby)
        await drainBoth()
    }

    override func tearDown() async throws {
        await drainBoth()
        director.stop()
        cameraCoordinator.stop()
        director = nil
        cameraCoordinator = nil
        directorTransport = nil
        cameraTransport = nil
        directorDisplay = nil
        cameraAlerts = nil
        directorImports?.value.forEach { try? FileManager.default.removeItem(at: $0.url) }
        directorImports = nil
        lobby = nil
        lobbyWrapper = nil
        UserDefaults.standard.removeObject(forKey: SendMediaPreference.key)
        try await super.tearDown()
    }

    // MARK: - Helpers

    /// A message hop lands on the peer's inbox, and replies hop back. Drain
    /// both inboxes several times so multi-hop exchanges settle.
    private func drainBoth(hops: Int = 6) async {
        for _ in 0..<hops {
            await director.waitForIdle()
            await cameraCoordinator.waitForIdle()
            await MainActor.run { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02)) }
        }
    }

    /// Keeps draining until `condition` holds. Scheduled captures fire on an
    /// off-actor delay (`captureLeadMillis`), so a fixed drain is not enough.
    @discardableResult
    private func waitUntil(timeout: TimeInterval = 3,
                           _ condition: () async -> Bool) async -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if await condition() { return true }
            await drainBoth(hops: 1)
        }
        return await condition()
    }

    /// The camera side as the scanner leaves it: connected, pointing at the
    /// director's peer ID.
    private func connectCamera() async {
        await cameraCoordinator.seed(state: .connected, lobby: lobbyWrapper, peer: directorPeer)
        await drainBoth()
        directorTransport.sentMessages.removeAll()
        cameraTransport.sentMessages.removeAll()
    }

    /// The scanner's handoff: the director takes over the transport that is
    /// already connected to the camera and runs its handshake.
    private func installDirector() async {
        await director.install(transport: directorTransport, initialPeers: [cameraPeer])
        await drainBoth()
    }

    /// Puts the camera-side session into `.camera` with a fake capture device.
    private func enterCameraState() async -> LoopbackFakeCamera {
        await connectCamera()
        let fakeCamera = LoopbackFakeCamera()
        fakeCamera.coordinator = cameraCoordinator
        cameraCoordinator.tell(UICmd.BecomeCamera(sender: nil, ctrl: fakeCamera))
        await drainBoth()
        cameraTransport.sentMessages.removeAll()
        return fakeCamera
    }

    /// A camera with a fake capture device on one side, the director installed
    /// and handshaken on the other; returns the fake.
    private func connectCameraAndDirector(
        configure: (LoopbackFakeCamera) -> Void = { _ in }) async -> LoopbackFakeCamera {
        await connectCamera()
        let fakeCamera = LoopbackFakeCamera()
        configure(fakeCamera)
        fakeCamera.coordinator = cameraCoordinator
        cameraCoordinator.tell(UICmd.BecomeCamera(sender: nil, ctrl: fakeCamera))
        await drainBoth()
        await installDirector()
        cameraTransport.sentMessages.removeAll()
        directorTransport.sentMessages.removeAll()
        return fakeCamera
    }

    private func lane() async -> MulticamLaneInfo? {
        await director.lanesForTesting().first { $0.peerID == cameraPeer }
    }

    /// No shot in flight on the director: every transient state has settled.
    private func directorIsSettled() async -> Bool {
        let capturing = await director.captureStateForTesting()
        let starting = await director.startingStateForTesting()
        let recording = await director.recordingStateForTesting()
        let stopping = await director.stoppingStateForTesting()
        return capturing == nil && starting == nil && recording == nil && stopping == nil
    }

    /// Sends a command from the director's transport to the camera — the wire
    /// path a director command takes, for commands the director only issues
    /// to a lane it has already handshaken.
    private func sendFromDirector(_ msg: Message) {
        _ = directorTransport.send(msg, to: [cameraPeer], mode: .reliable)
    }

    // MARK: - Handshake

    func testDirectorHandshakeCrossesTheWire() async {
        await connectCamera()
        await installDirector()

        // The role announcement, the capabilities request and the frame
        // request all crossed the wire.
        XCTAssertTrue(directorTransport.sentMessages.contains { $0 is RemoteCmd.PeerBecameMonitor })
        XCTAssertTrue(directorTransport.sentMessages.contains { $0 is RemoteCmd.RequestCameraCapabilities })
        XCTAssertTrue(directorTransport.sentMessages.contains { $0 is RemoteCmd.RequestFrame })

        // The peer decoded PeerBecameMonitor without tripping the incompatibility path.
        let cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .connected)
        XCTAssertTrue(cameraAlerts.shownErrors.isEmpty)
        let status = await director.statusForTesting(cameraPeer)
        XCTAssertEqual(status, .linked)
    }

    /// v10 reactive contract in one round trip: the camera's recording truth
    /// crosses the wire with the capabilities exchange, and the director
    /// DERIVES the lane's recording state from it — without ever having sent
    /// a start.
    func testCameraRecordingTruthDerivedByDirectorAcrossTheWire() async {
        await connectCamera()
        let fakeCamera = LoopbackFakeCamera()
        fakeCamera.coordinator = cameraCoordinator
        fakeCamera.reportedRecordingStartedAt = Date(timeIntervalSinceNow: -42)
        cameraCoordinator.tell(UICmd.BecomeCamera(sender: nil, ctrl: fakeCamera))
        await drainBoth()

        await installDirector()
        let recording = await director.isRecordingForTesting(cameraPeer)
        XCTAssertTrue(recording, "the director derives recording from the camera's report")

        // And the reconciliation in reverse: the camera now reports idle —
        // the lane cannot stay recording when the camera isn't.
        fakeCamera.reportedRecordingStartedAt = nil
        cameraCoordinator.tell(RemoteCmd.RequestCameraCapabilities())
        await drainBoth()
        let settled = await director.isRecordingForTesting(cameraPeer)
        XCTAssertFalse(settled)
    }

    /// The keep-rolling round trip: mid-recording the link dies — the camera
    /// holds its recording state in place while the director degrades the
    /// lane to `.reconnecting` — then the transports re-link, the director
    /// re-handshakes, and DERIVES the still-running recording from the
    /// camera's report. No message asks anyone to resume; the camera's
    /// reported truth is the whole mechanism.
    func testRecordingSurvivesDropAndDirectorRederivesOnRejoin() async {
        let fakeCamera = await connectCameraAndDirector()

        director.startRecording()
        await waitUntil { fakeCamera.startRecordingCalls == 1 }
        await waitUntil { await self.director.isRecordingForTesting(self.cameraPeer) }
        var cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .cameraRecordingVideo)

        // The link dies on both sides.
        fakeCamera.reportedRecordingStartedAt = Date(timeIntervalSinceNow: -12)
        directorTransport.simulateRemoteDisconnected()
        cameraTransport.simulateRemoteDisconnected()
        await drainBoth()

        cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .cameraRecordingVideo, "the take keeps rolling in place")
        XCTAssertTrue(fakeCamera.stopRecordingCalls.isEmpty)
        let status = await director.statusForTesting(cameraPeer)
        XCTAssertEqual(status, .reconnecting, "the lane waits exactly as before")

        // The transports re-link and both sides learn of the connection.
        directorTransport.remote = cameraTransport
        cameraTransport.remote = directorTransport
        cameraCoordinator.tell(OnConnectToDevice(peer: directorPeer, sender: nil))
        director.peerDidConnect(cameraPeer)
        await drainBoth()

        let rejoined = await director.statusForTesting(cameraPeer)
        XCTAssertEqual(rejoined, .linked)
        let stillRecording = await director.isRecordingForTesting(cameraPeer)
        XCTAssertTrue(stillRecording, "the director derives the live recording from the handshake")
        XCTAssertTrue(fakeCamera.stopRecordingCalls.isEmpty, "still rolling after the rejoin")
    }

    /// The field bug this pins: the camera STOPPED ON ITS OWN while unlinked
    /// (operator's on-camera stop / writer death), so the response the
    /// director would normally learn from died with the link. The rejoin
    /// must PULL camera state — the lane lands idle, not on a phantom
    /// recording.
    func testCameraStoppedWhileUnlinkedRederivedAsIdleOnRejoin() async {
        let fakeCamera = await connectCameraAndDirector()

        director.startRecording()
        await waitUntil { fakeCamera.startRecordingCalls == 1 }
        await waitUntil { await self.director.isRecordingForTesting(self.cameraPeer) }

        // The link dies; while unlinked, the operator stops on the camera.
        fakeCamera.reportedRecordingStartedAt = Date(timeIntervalSinceNow: -12)
        directorTransport.simulateRemoteDisconnected()
        cameraTransport.simulateRemoteDisconnected()
        await drainBoth()
        cameraCoordinator.tell(UICmd.StopRecordingLocally())
        fakeCamera.reportedRecordingStartedAt = nil
        await drainBoth()
        let cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .camera, "stopped and idle, still advertising")

        // Rejoin: the director's pull reconciles it to the camera's truth.
        directorTransport.remote = cameraTransport
        cameraTransport.remote = directorTransport
        cameraCoordinator.tell(OnConnectToDevice(peer: directorPeer, sender: nil))
        director.peerDidConnect(cameraPeer)
        await drainBoth()

        let recording = await director.isRecordingForTesting(cameraPeer)
        XCTAssertFalse(recording, "the director re-derives the camera's idle truth — no phantom recording")
        let settled = await directorIsSettled()
        XCTAssertTrue(settled)
    }

    // MARK: - Commands against a peer that is not in camera mode

    /// The director only fires at lanes it has handshaken, so these go out
    /// through its transport exactly as the wire would carry them: the peer
    /// (not in camera mode) must answer each with an error, not swallow it.

    func testTakePictureRoundTripAgainstPeerNotInCameraMode() async {
        await connectCamera()
        await installDirector()
        sendFromDirector(RemoteCmd.TakePic(sender: nil, sendMediaToPeer: true))
        await drainBoth()

        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.TakePicResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertNotNil(resps.first?.error)
        let cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .connected)
        let settled = await directorIsSettled()
        XCTAssertTrue(settled)
    }

    func testToggleFlashRoundTripAgainstPeerNotInCameraMode() async {
        await connectCamera()
        await installDirector()
        sendFromDirector(RemoteCmd.ToggleFlash())
        await drainBoth()

        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.ToggleFlashResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertNotNil(resps.first?.error)
    }

    func testStartRecordingRoundTripAgainstPeerNotInCameraMode() async {
        await connectCamera()
        await installDirector()
        sendFromDirector(RemoteCmd.StartRecordingVideo(sender: nil))
        await drainBoth()

        let acks = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.StartRecordingVideoAck }
        XCTAssertEqual(acks.count, 1)
        XCTAssertNotNil(acks.first?.error)
        let settled = await directorIsSettled()
        XCTAssertTrue(settled)
    }

    func testSetZoomRoundTripAgainstPeerNotInCameraMode() async {
        await connectCamera()
        await installDirector()
        sendFromDirector(RemoteCmd.SetZoom(zoomFactor: 2.5))
        await drainBoth()

        XCTAssertTrue(cameraTransport.sentMessages.contains { $0 is RemoteCmd.SetZoomResp })
        let cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .connected)
    }

    // MARK: - Peer disconnect

    func testPeerDisconnectDegradesTheLaneToReconnecting() async {
        _ = await connectCameraAndDirector()
        directorTransport.simulateRemoteDisconnected()
        await drainBoth()

        let status = await director.statusForTesting(cameraPeer)
        XCTAssertEqual(status, .reconnecting,
                       "an unannounced drop is a camera to wait for, not a lane to forget")
    }

    // MARK: - Happy-path photo capture with a camera peer

    func testTakePictureHappyPathAcrossTheWire() async {
        let fakeCamera = await connectCameraAndDirector()
        let cameraStateAfterBecome = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraStateAfterBecome, .camera)

        director.capturePhoto()
        // A synced capture acks at once and fires after the lead; the still
        // comes back once the fire has run.
        await waitUntil { fakeCamera.takePictureCalls == [true] }
        await waitUntil {
            self.cameraTransport.sentMessages.contains { $0 is RemoteCmd.TakePicResp }
        }
        await waitUntil { await self.directorIsSettled() }

        // The fake camera captured exactly once. (A synced capture saves its
        // stamped still straight to Photos under the rig filename — no seam
        // observes that here; the camera-side unit tests pin the metadata.)
        XCTAssertEqual(fakeCamera.takePictureCalls, [true])

        // Ack + response carrying the still crossed back to the director.
        XCTAssertTrue(cameraTransport.sentMessages.contains { $0 is RemoteCmd.TakePicAck })
        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.TakePicResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertEqual(resps.first?.pic, fakeCamera.photoBytes)

        // Both sides settled back into their steady states, with no errors surfaced.
        let outcome = await director.captureOutcomeForTesting(cameraPeer)
        XCTAssertEqual(outcome, .captured)
        let cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .camera)
        XCTAssertTrue(directorDisplay.transientErrors.isEmpty)
        XCTAssertTrue(cameraAlerts.shownErrors.isEmpty)
    }

    // MARK: - Happy-path camera-control round trips

    func testToggleFlashHappyPathAcrossTheWire() async {
        let fakeCamera = await connectCameraAndDirector()
        director.toggleFlash(on: cameraPeer)
        await drainBoth()

        // The fake flips .off -> .on and the mode crosses back in the response.
        XCTAssertEqual(fakeCamera.flashMode, .on)
        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.ToggleFlashResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertEqual(resps.first?.flashMode, .on)
        XCTAssertNil(resps.first?.error)
        let flashOn = await lane()?.flashOn
        XCTAssertEqual(flashOn, true)
        XCTAssertTrue(directorDisplay.transientErrors.isEmpty)
    }

    func testToggleCameraHappyPathCarriesCapabilities() async {
        _ = await connectCameraAndDirector()
        director.flipCamera(cameraPeer)
        await drainBoth()

        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.ToggleCameraResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertNil(resps.first?.error)
        XCTAssertNotNil(resps.first?.cameraCapabilities,
                        "toggle response must carry fresh capabilities")
        XCTAssertEqual(resps.first?.cameraCapabilities?.currentLens, .wideAngle)
        XCTAssertTrue(directorDisplay.transientErrors.isEmpty)
    }

    // MARK: - Camera device selection (camera side)

    /// The director issues no device selection of its own, so these pin the
    /// camera's answer to `SelectCameraDevice` arriving over the wire.

    func testSelectCameraDeviceHappyPathAcrossTheWire() async {
        let fakeCamera = await connectCameraAndDirector()
        sendFromDirector(RemoteCmd.SelectCameraDevice(uniqueID: "fake-front"))
        await drainBoth()

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
    }

    /// A suspended camera (clamshell built-in: connected, zero frames) is
    /// advertised with its flag so the director can gray it out — and if a
    /// peer selects it anyway (old UI, race), the camera answers with an
    /// error instead of switching to a dead device.
    func testSuspendedDeviceIsAdvertisedAndRejectedOnSelection() async {
        let fakeCamera = await connectCameraAndDirector { fake in
            fake.availableDevices.append(CameraDeviceDescriptor(
                uniqueID: "builtin-lid-closed", localizedName: "MacBook Pro Camera",
                position: .unspecified, deviceType: .builtInWideAngleCamera,
                isSuspended: true))
        }
        let advertised = await lane().map { _ in true } ?? false
        XCTAssertTrue(advertised)

        sendFromDirector(RemoteCmd.SelectCameraDevice(uniqueID: "builtin-lid-closed"))
        await drainBoth()

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
    /// broadcasting fresh capabilities, so the director's lane updates live.
    func testHotPlugRebroadcastsCapabilitiesWithNewDeviceList() async {
        let fakeCamera = await connectCameraAndDirector()
        // A USB camera appears…
        fakeCamera.availableDevices.append(CameraDeviceDescriptor(
            uniqueID: "usb-0", localizedName: "USB Camera",
            position: .unspecified, deviceType: .builtInWideAngleCamera))
        // …and the rig nudges its own coordinator, as the hot-plug observer does.
        cameraCoordinator.tell(RemoteCmd.RequestCameraCapabilities())
        await drainBoth()

        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.CameraCapabilitiesResp }
        XCTAssertEqual(resps.count, 1, "hot-plug must trigger exactly one capabilities broadcast")
        XCTAssertEqual(resps.first?.cameraDevices.count, 3)
        XCTAssertTrue(resps.first?.cameraDevices.contains { $0.uniqueID == "usb-0" } ?? false,
                      "the freshly plugged camera must be advertised to the director")
    }

    /// A camera can accept the input swap and then never deliver a frame (a
    /// wedged virtual camera, e.g. OBS in a sandboxed app). The selection
    /// must come back as a VISIBLE error naming the device — not a success
    /// followed by a silently black preview.
    func testSelectingCameraThatDeliversNoFramesReturnsError() async {
        _ = await connectCameraAndDirector { fake in
            fake.availableDevices.append(CameraDeviceDescriptor(
                uniqueID: "obs-0", localizedName: "OBS Virtual Camera",
                position: .unspecified, deviceType: .builtInWideAngleCamera))
            fake.stalledDeviceIDs = ["obs-0"]
        }
        sendFromDirector(RemoteCmd.SelectCameraDevice(uniqueID: "obs-0"))
        await drainBoth()

        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.SelectCameraDeviceResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertNotNil(resps.first?.error, "a no-frames camera must fail the selection")
        XCTAssertTrue(resps.first?.error?._domain.contains("OBS Virtual Camera") ?? false,
                      "the error must name the dead device")
    }

    func testSelectCameraDeviceWhileRecordingIsRejected() async {
        let fakeCamera = await connectCameraAndDirector()
        // Start a recording so the camera sits in a busy state.
        director.startRecording()
        await waitUntil { fakeCamera.startRecordingCalls == 1 }
        await waitUntil { await self.cameraCoordinator.currentStateName() == .cameraRecordingVideo }
        cameraTransport.sentMessages.removeAll()

        sendFromDirector(RemoteCmd.SelectCameraDevice(uniqueID: "fake-front"))
        await drainBoth()

        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.SelectCameraDeviceResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertNotNil(resps.first?.error, "busy camera must reject device selection")
        XCTAssertTrue(fakeCamera.deviceSelections.isEmpty)
        // Still recording — the request must not disturb the session.
        let stillRecording = await cameraCoordinator.currentStateName()
        XCTAssertEqual(stillRecording, .cameraRecordingVideo)
    }

    func testSetZoomHappyPathEchoesFactorAndRange() async {
        let fakeCamera = await connectCameraAndDirector()
        director.setZoom(2.5, on: cameraPeer)
        await drainBoth()

        XCTAssertEqual(fakeCamera.zoomCalls, [2.5])
        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.SetZoomResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertEqual(resps.first?.zoomFactor ?? 0, 2.5, accuracy: 0.001)
        XCTAssertEqual(resps.first?.zoomRange?.maxZoom ?? 0, 10, accuracy: 0.001)
        let zoom = await lane()?.zoomFactor ?? 0
        XCTAssertEqual(zoom, 2.5, accuracy: 0.001)
    }

    // MARK: - Tap to focus

    func testFocusAtPointHappyPathAcrossTheWire() async {
        let fakeCamera = await connectCameraAndDirector()
        director.focusCamera(cameraPeer, x: 0.25, y: 0.75)
        await drainBoth()

        XCTAssertEqual(fakeCamera.focusCalls.count, 1)
        XCTAssertEqual(fakeCamera.focusCalls.first?.x ?? -1, 0.25, accuracy: 0.001)
        XCTAssertEqual(fakeCamera.focusCalls.first?.y ?? -1, 0.75, accuracy: 0.001)
        // Fire-and-forget: no response is sent, and it was never a TakePicture.
        XCTAssertTrue(fakeCamera.takePictureCalls.isEmpty)
    }

    /// Safety gate: old peers decode the unknown FocusAtPoint action as
    /// TakePicture, so the director must never send it to a peer whose
    /// capabilities did not advertise focus-point support.
    func testFocusAtPointIsNeverSentToLegacyPeer() async {
        let fakeCamera = await connectCameraAndDirector { fake in
            fake.advertisesFocusPoint = false   // peer predates tap-to-focus
        }
        director.focusCamera(cameraPeer, x: 0.4, y: 0.6)
        await drainBoth()

        XCTAssertFalse(directorTransport.sentMessages.contains { $0 is RemoteCmd.FocusAtPoint },
                       "FocusAtPoint must be gated on advertised supports_focus_point")
        XCTAssertTrue(fakeCamera.focusCalls.isEmpty)
        XCTAssertTrue(fakeCamera.takePictureCalls.isEmpty,
                      "an ungated command would decode as TakePicture on an old peer")
    }

    func testSwitchLensHappyPathAcrossTheWire() async {
        let fakeCamera = await connectCameraAndDirector()
        await director.switchLens(.telephoto, on: cameraPeer)
        await drainBoth()

        XCTAssertEqual(fakeCamera.lensSwitches, [.telephoto])
        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.SwitchLensResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertEqual(resps.first?.lensType, .telephoto)
        XCTAssertNil(resps.first?.error)
    }

    // MARK: - App-version gate (semver major)

    /// A peer version on this build's own major, so the pairing gate stays out
    /// of the way of whatever else a test is exercising.
    private var sameMajorVersion: String {
        "\(PeerAppCompatibility.localVersion?.major ?? 0).0.0"
    }

    /// A director announcing itself. `bundleVersion` and `platform` are
    /// diagnostics — no gate reads them — so the tests vary only the version
    /// the single gate does read.
    private func directorAnnouncing(_ shortVersion: String,
                                    build: Int = 110) -> RemoteCmd.PeerBecameMonitor {
        RemoteCmd.PeerBecameMonitor(
            bundleVersion: build, shortVersion: shortVersion, platform: "iPhone")
    }

    /// A director on this major is answered normally: the camera stays in
    /// `.camera` and broadcasts capabilities, then streams VP9 to it. No
    /// capability handshake, no incompatibility.
    func testSameMajorDirectorIsAcceptedAndAnswered() async {
        _ = await enterCameraState()
        cameraCoordinator.tell(directorAnnouncing(sameMajorVersion))
        await drainBoth()

        let cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .camera, "a same-major director keeps the camera streaming")
        XCTAssertTrue(cameraTransport.sentMessages.contains { $0 is RemoteCmd.CameraCapabilitiesResp },
                      "the camera answers a same-major director with capabilities")
    }

    /// The major is the whole gate: a build number cannot refuse a peer the
    /// version policy accepted, not even the `0` an absent `CFBundleVersion`
    /// decodes to. Pinned so a build threshold cannot quietly reappear as a
    /// second policy.
    func testBuildNumberDoesNotGateAPeerOnThisMajor() async {
        _ = await enterCameraState()
        cameraCoordinator.tell(directorAnnouncing(sameMajorVersion, build: 0))
        await drainBoth()

        let cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .camera, "an unknown build number is not a refusal")
        XCTAssertTrue(cameraTransport.sentMessages.contains { $0 is RemoteCmd.CameraCapabilitiesResp })
    }

    /// A director on a different app major is refused: the camera leaves for
    /// scanning and never answers with capabilities, whatever its build number.
    func testDirectorOnDifferentAppMajorIsRefused() async {
        guard let local = PeerAppCompatibility.localVersion else {
            return XCTFail("the test host must carry a parseable CFBundleShortVersionString")
        }
        _ = await enterCameraState()
        cameraCoordinator.tell(directorAnnouncing("\(local.major + 1).0.0"))
        await drainBoth()

        let cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .scanning, "a peer on another app major cannot hold a session")
        XCTAssertFalse(cameraTransport.sentMessages.contains { $0 is RemoteCmd.CameraCapabilitiesResp },
                       "the camera must not negotiate with a peer on another major")
    }

    /// Refusing a peer is a goodbye on the wire, not a silent drop: `EndSession`
    /// crosses the real encode/decode path, so the director reads the
    /// disconnect that follows as a lane that left on purpose and never starts
    /// the reconnect chase that would land it in the same refusal a second
    /// later.
    func testRefusedPeerIsSentAProperDisconnect() async {
        guard let local = PeerAppCompatibility.localVersion else {
            return XCTFail("the test host must carry a parseable CFBundleShortVersionString")
        }
        _ = await connectCameraAndDirector()
        cameraCoordinator.tell(directorAnnouncing("\(local.major + 1).0.0"))
        await drainBoth()

        XCTAssertTrue(cameraTransport.sentMessages.contains { $0 is RemoteCmd.EndSession },
                      "the camera announces the exit while the link is still up")
        let status = await director.statusForTesting(cameraPeer)
        XCTAssertNil(status, "a goodbye ends the lane")

        // The link ends the way the transport reports it.
        directorTransport.simulateRemoteDisconnected()
        await drainBoth()
        let afterDrop = await director.statusForTesting(cameraPeer)
        XCTAssertNil(afterDrop, "a peer that said goodbye is not chased")
        XCTAssertTrue(directorDisplay.didExit, "the last camera leaving closes the director")
    }

    /// Minor and patch differences are not breaking: a director on the same
    /// major but a higher minor is answered normally.
    func testDirectorOnHigherMinorIsAccepted() async {
        guard let local = PeerAppCompatibility.localVersion else {
            return XCTFail("the test host must carry a parseable CFBundleShortVersionString")
        }
        _ = await enterCameraState()
        cameraCoordinator.tell(directorAnnouncing("\(local.major).\(local.minor + 7).3"))
        await drainBoth()

        let cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .camera, "a newer minor on the same major stays compatible")
        XCTAssertTrue(cameraTransport.sentMessages.contains { $0 is RemoteCmd.CameraCapabilitiesResp },
                      "the camera answers a same-major director with capabilities")
    }

    // MARK: - VP9 keyframe recovery

    /// Builds a SendFrame the way the camera's transport delivers a VP9 frame.
    private func vp9Frame() -> RemoteCmd.SendFrame {
        RemoteCmd.SendFrame(
            data: Data([1, 2, 3]), sender: nil, fps: 30,
            camPosition: .back, camOrientation: .portrait, codec: .vp9)
    }

    /// Once the director has received a VP9 frame on a lane, a decoder desync
    /// sends RequestKeyframe, which reaches the camera and forces a keyframe.
    func testKeyframeRequestRoundTripAfterVP9Frame() async {
        let fakeCamera = await connectCameraAndDirector()
        // The camera's FrameSender is where a keyframe request lands.
        let cameraFrameSender = FrameSender(coordinator: cameraCoordinator)
        cameraCoordinator.setFrameSender(cameraFrameSender)

        // The director received a VP9 frame (as the transport would deliver one).
        director.didReceiveFrame(vp9Frame(), from: cameraPeer)
        await drainBoth()
        director.requestKeyframe(for: cameraPeer)
        await drainBoth()

        XCTAssertTrue(directorTransport.sentMessages.contains { $0 is RemoteCmd.RequestKeyframe },
                      "a desync after a VP9 frame must send RequestKeyframe")
        XCTAssertTrue(cameraFrameSender.takeKeyframeRequest(),
                      "the camera must forward the request to its VP9 streamer")
        // The camera did not misread it as a photo request.
        XCTAssertTrue(fakeCamera.takePictureCalls.isEmpty)
        let cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .camera)
    }

    /// The old-peer gate: a keyframe request is NEVER sent before a VP9 frame
    /// has been seen on that lane — an old camera decodes the unknown action
    /// as TakePicture.
    func testKeyframeRequestGatedUntilVP9FrameSeen() async {
        let fakeCamera = await connectCameraAndDirector()
        // No VP9 frame has arrived yet.
        director.requestKeyframe(for: cameraPeer)
        await drainBoth()

        XCTAssertFalse(directorTransport.sentMessages.contains { $0 is RemoteCmd.RequestKeyframe },
                       "RequestKeyframe must be gated on having received a VP9 frame")
        XCTAssertTrue(fakeCamera.takePictureCalls.isEmpty,
                      "an ungated request would decode as TakePicture on an old peer")
    }

    // MARK: - Video recording

    /// The full stop protocol across both machines:
    /// StopRecordingVideo → StopRecordingVideoAck → StopRecordingVideoResp,
    /// with the clip crossing as a resource.
    func testVideoRecordingStartStopProtocolAcrossTheWire() async {
        SendMediaPreference.isEnabled = true
        let fakeCamera = await connectCameraAndDirector()

        // Start: the director's shutter.
        director.startRecording()
        await waitUntil { fakeCamera.startRecordingCalls == 1 }
        await waitUntil { await self.director.isRecordingForTesting(self.cameraPeer) }
        XCTAssertEqual(fakeCamera.startRecordingCalls, 1)
        let cameraStateRecording = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraStateRecording, .cameraRecordingVideo)
        // The success ack (recording start time, used for the timer sync)
        // must be forwarded to the peer, not just the error ack.
        let startAcks = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.StartRecordingVideoAck }
        XCTAssertEqual(startAcks.count, 1, "camera must forward the success StartRecordingVideoAck to the director")
        XCTAssertNotNil(startAcks.first?.recordingStartTime)

        // Stop: the same shutter now stops, with "Send Media to Remote" ON.
        director.stopRecording()
        await waitUntil { fakeCamera.stopRecordingCalls == [true] }
        await waitUntil { await self.directorIsSettled() }
        XCTAssertEqual(fakeCamera.stopRecordingCalls, [true])
        // A synced stop is acked as a ScheduledRecordingAck(isStop); the
        // response with the clip follows the transfer as before.
        let stopAcks = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.ScheduledRecordingAck }
        XCTAssertEqual(stopAcks.filter(\.isStop).count, 1)
        XCTAssertNil(stopAcks.first { $0.isStop }?.error)
        XCTAssertTrue(cameraTransport.sentMessages.contains { $0 is RemoteCmd.StopRecordingVideoResp })

        // The clip went out as ONE resource transfer, never inside a message.
        XCTAssertEqual(cameraTransport.sentResources.value.map(\.url), [fakeCamera.clipURL])
        XCTAssertFalse(cameraTransport.sentMessages.contains { $0 is UICmd.SendVideoResource })

        // The director handed its library the landed file — a different file
        // from the camera's, with the same bytes — by URL.
        let landed = directorImports.value
        XCTAssertEqual(landed.count, 1)
        XCTAssertNotEqual(landed.first?.url, fakeCamera.clipURL)
        XCTAssertEqual(landed.first.flatMap { try? Data(contentsOf: $0.url) }, fakeCamera.clipBytes)

        // Camera popped back to .camera after transmitting; the lane is idle.
        let cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .camera)
        let recording = await director.isRecordingForTesting(cameraPeer)
        XCTAssertFalse(recording)
        XCTAssertTrue(directorDisplay.transientErrors.isEmpty)
    }

    /// "Send Media to Remote" OFF: the director's stop carries the preference,
    /// the camera keeps the clip to itself, and the director's library never
    /// hears about it. Both machines still settle.
    func testStopWithSendMediaOffTransfersNothing() async {
        SendMediaPreference.isEnabled = false
        let fakeCamera = await connectCameraAndDirector()

        director.startRecording()
        await waitUntil { fakeCamera.startRecordingCalls == 1 }
        await waitUntil { await self.director.isRecordingForTesting(self.cameraPeer) }
        director.stopRecording()
        await waitUntil { fakeCamera.stopRecordingCalls == [false] }
        await waitUntil { await self.directorIsSettled() }

        XCTAssertEqual(fakeCamera.stopRecordingCalls, [false])
        XCTAssertNil(fakeCamera.clipURL, "no clip is even offered for transfer")
        XCTAssertTrue(cameraTransport.sentResources.value.isEmpty)
        XCTAssertTrue(directorImports.value.isEmpty)
        XCTAssertTrue(cameraTransport.sentMessages.contains { $0 is RemoteCmd.StopRecordingVideoResp })
        let cameraState = await cameraCoordinator.currentStateName()
        XCTAssertEqual(cameraState, .camera)
        let recording = await director.isRecordingForTesting(cameraPeer)
        XCTAssertFalse(recording)
        XCTAssertTrue(directorDisplay.transientErrors.isEmpty)
        XCTAssertTrue(cameraAlerts.shownErrors.isEmpty)
    }

    // MARK: - Camera preview mode (standby)

    /// The director puts the rig in standby; the camera applies + persists the
    /// mode and reports it back across the wire.
    func testSetCameraPreviewModeHappyPathAcrossTheWire() async {
        let fakeCamera = await connectCameraAndDirector()
        director.setRigStandby(true)
        await drainBoth()

        // Camera applied standby exactly once.
        XCTAssertEqual(fakeCamera.previewModeCalls, [.standby])
        // Never confused with a capture: standby is display-only.
        XCTAssertTrue(fakeCamera.takePictureCalls.isEmpty)
        // The camera reported the new mode back to the director.
        let resps = cameraTransport.sentMessages.compactMap { $0 as? RemoteCmd.CameraPreviewModeResp }
        XCTAssertEqual(resps.count, 1)
        XCTAssertEqual(resps.first?.mode, .standby)

        // Restoring the preview round-trips the same way.
        director.setRigStandby(false)
        await drainBoth()
        XCTAssertEqual(fakeCamera.previewModeCalls, [.standby, .on])
        XCTAssertTrue(directorDisplay.transientErrors.isEmpty)
        XCTAssertTrue(cameraAlerts.shownErrors.isEmpty)
    }

    /// Safety gate mirroring FocusAtPoint: a peer that did not advertise
    /// preview-mode support must never be sent action 24 (it would misread it).
    func testSetCameraPreviewModeIsNeverSentToLegacyPeer() async {
        let fakeCamera = await connectCameraAndDirector { fake in
            fake.advertisesPreviewMode = false   // peer predates the feature
        }
        director.setRigStandby(true)
        await drainBoth()

        XCTAssertFalse(directorTransport.sentMessages.contains { $0 is RemoteCmd.SetCameraPreviewMode },
                       "SetCameraPreviewMode must be gated on advertised supports_preview_mode")
        XCTAssertTrue(fakeCamera.previewModeCalls.isEmpty)
        XCTAssertTrue(fakeCamera.takePictureCalls.isEmpty,
                      "an ungated command could decode as a capture on an old peer")
    }

    /// Standby does not gate the *transport*: with the camera in standby, a
    /// frame handed to a real FrameSender still crosses the wire and reaches
    /// the lane's frame sink.
    ///
    /// SCOPE: calls `sender.send(...)` directly, so it covers only FrameSender
    /// outward. It says nothing about whether frames are still *produced* —
    /// `AVCaptureVideoDataOutput` → `CaptureEngine` → `FrameStreamingCoordinator`
    /// is bypassed. That needs real capture hardware; cover it in
    /// `CaptureIntegrationTests`.
    func testStandbyDoesNotBlockTheFrameTransport() async {
        let fakeCamera = await connectCameraAndDirector()
        // Wire a real FrameSender into the camera's session, pointed at the
        // director peer — exactly what the camera rig does in production.
        let sender = FrameSender(coordinator: cameraCoordinator)
        sender.setSession(peer: directorPeer, transport: cameraTransport)
        cameraCoordinator.setFrameSender(sender)
        let framesSeen = Locked<Int>(0)
        await director.setFrameSink(for: cameraPeer) { _ in framesSeen.mutate { $0 += 1 } }

        // Put the camera into standby over the wire.
        director.setRigStandby(true)
        await drainBoth()
        XCTAssertEqual(fakeCamera.previewModeCalls, [.standby], "standby must have been applied")
        cameraTransport.sentMessages.removeAll()

        // Produce a preview frame the way the capture pipeline would. If standby
        // had touched the streaming path this frame would never leave.
        sender.send(RemoteCmd.SendFrame(
            data: Data([0xFF, 0xD8, 0xFF, 0xE0]),
            sender: nil,
            fps: 30,
            camPosition: .back,
            camOrientation: .portrait,
            codec: .jpeg))
        // FrameSender streams on its own serial queue; give it a moment to flush.
        let streamed = await waitUntil {
            self.cameraTransport.sentMessages.contains { $0 is RemoteCmd.SendFrame }
        }
        XCTAssertTrue(streamed,
                      "frame streaming to the director must continue while the camera is in standby")
        // The loopback transport delivered that SendFrame to the director
        // (didReceiveFrame → the lane's sink), so the live preview kept going.
        await waitUntil { framesSeen.value >= 1 }
        XCTAssertGreaterThanOrEqual(framesSeen.value, 1)
        let status = await director.statusForTesting(cameraPeer)
        XCTAssertEqual(status, .linked)
    }
}
