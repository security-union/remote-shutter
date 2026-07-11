//
//  SessionTestSupport.swift
//  RemoteShutterTests
//
//  Shared fakes and helpers for driving SessionCoordinator in tests.
//

import Foundation
import XCTest
import MultipeerConnectivity
import AVFoundation
import Combine

@testable import RemoteShutter

// MARK: - Fake transport

class FakeMultipeerService: MultipeerServiceProtocol {
    weak var delegate: MultipeerServiceDelegate?
    var session: MCSession!
    var connectedPeers: [MCPeerID] = []
    var progressCancellables = Set<AnyCancellable>()

    // Recording
    var sentMessages: [(msg: Message, peers: [MCPeerID], mode: MCSessionSendDataMode)] = []
    var stopSessionCalled = false
    var disconnectCalled = false
    var startAdvertisingAndBrowsingCalled = false
    var stopAdvertisingAndBrowsingCalled = false
    var invitedPeers: [(peer: MCPeerID, timeout: TimeInterval)] = []
    var sendResult: Try<Message> = Failure(error: NSError(domain: "test", code: 0))

    func startAdvertisingAndBrowsing() { startAdvertisingAndBrowsingCalled = true }
    func startAdvertisingOnly(discoveryInfo: [String: String]?) { startAdvertisingAndBrowsingCalled = true }
    func startBrowsingOnly() { startAdvertisingAndBrowsingCalled = true }
    func stopAdvertisingAndBrowsing() { stopAdvertisingAndBrowsingCalled = true }
    func disconnect() { disconnectCalled = true }
    func stopSession() { stopSessionCalled = true }
    func invitePeer(_ peer: MCPeerID, timeout: TimeInterval) {
        invitedPeers.append((peer, timeout))
    }
    func send(_ msg: Message, to peers: [MCPeerID],
              mode: MCSessionSendDataMode) -> Try<Message> {
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
        let handle = FakeAlertHandle(title: title)
        shownAlerts.append(handle)
        return handle
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

// MARK: - Fake camera (CameraControlling)

/// Async fake for the camera seam: records every call, returns canned
/// values, never touches AVFoundation. Shared by the session, loopback and
/// watch state tests.
class FakeCameraControlling: CameraControlling {
    var currentCameraMode: RecordingMode = .Photo
    var isRecording = false
    let cameraViewModel = CameraViewModel()

    var takePictureCalls: [Bool] = []
    var startRecordingCalls = 0
    var stopRecordingCalls: [Bool] = []
    var updateStatusCalls = 0
    var exitCameraCalls = 0
    var countdownTicks: [Int] = []
    var gatherCapabilitiesCalls = 0
    var zoomCalls: [CGFloat] = []
    var lensSwitches: [CameraLensType] = []
    var torchToggles = 0
    var chimes: [Int] = []
    var torchRestores = 0

    var photoBytes = Data([0xFF, 0xD8, 0xFF, 0xE0])
    var torchActive = false
    var flashMode: AVCaptureDevice.FlashMode = .off
    var errorToThrow: Error?

    func isTorchActive() async -> Bool { torchActive }
    func currentFlashMode() async -> AVCaptureDevice.FlashMode { flashMode }

    func updateCameraStatus() { updateStatusCalls += 1 }
    func takePicture(_ sendMediaToRemote: Bool) { takePictureCalls.append(sendMediaToRemote) }
    func startRecordingVideo() { startRecordingCalls += 1 }
    func stopRecordingVideo(_ shouldSendVideo: Bool) { stopRecordingCalls.append(shouldSendVideo) }

    // swiftlint:disable:next large_tuple
    func setZoom(zoomFactor: CGFloat) async throws -> (CGFloat, CameraLensType, RemoteCmd.ZoomRange) {
        if let errorToThrow { throw errorToThrow }
        zoomCalls.append(zoomFactor)
        return (zoomFactor, .wideAngle, RemoteCmd.ZoomRange(minZoom: 1, maxZoom: 10))
    }
    // swiftlint:disable:next large_tuple
    func switchLens(to lensType: CameraLensType) async throws -> (CameraLensType, [CameraLensType], CGFloat, RemoteCmd.ZoomRange) {
        if let errorToThrow { throw errorToThrow }
        lensSwitches.append(lensType)
        return (lensType, [.wideAngle, lensType], 1.0, RemoteCmd.ZoomRange(minZoom: 1, maxZoom: 10))
    }
    func toggleFlash() async throws -> AVCaptureDevice.FlashMode {
        if let errorToThrow { throw errorToThrow }
        flashMode = flashMode == .off ? .on : .off
        return flashMode
    }
    func toggleTorch() async throws -> AVCaptureDevice.TorchMode {
        if let errorToThrow { throw errorToThrow }
        torchToggles += 1
        torchActive.toggle()
        return torchActive ? .on : .off
    }
    func toggleCamera() async throws -> (AVCaptureDevice.FlashMode?, AVCaptureDevice.Position) {
        if let errorToThrow { throw errorToThrow }
        return (flashMode, .back)
    }
    func setTorchMode(mode: AVCaptureDevice.TorchMode) async throws -> AVCaptureDevice.TorchMode {
        if let errorToThrow { throw errorToThrow }
        torchActive = mode == .on
        return mode
    }
    func setVideoQuality(resolution: VideoResolution, frameRate: VideoFrameRate) async -> (VideoResolution, VideoFrameRate)? {
        (resolution, frameRate)
    }
    func setPhotoQuality(format: PhotoFormat, hdrMode: HDRMode) async -> (PhotoFormat, HDRMode)? {
        (format, hdrMode)
    }
    func setAspectRatio(_ ratio: AspectRatio) async -> AspectRatio { ratio }
    func gatherAllCameraCapabilities() async { gatherCapabilitiesCalls += 1 }
    func gatherCurrentCameraCapabilities() async -> RemoteCmd.CameraCapabilitiesResp? {
        RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, currentLens: .wideAngle, currentZoom: 1.0, error: nil)
    }

    func getCurrentZoomFactor() async -> CGFloat { zoomCalls.last ?? 1.0 }
    func getMinZoomFactor() async -> CGFloat { 1.0 }
    func getMaxZoomFactor() async -> CGFloat { 10.0 }
    func getCurrentLensType() async -> CameraLensType { .wideAngle }
    func getAvailableLensTypes() async -> [CameraLensType] { [.wideAngle] }
    func getZoomStops() async -> [CGFloat] { [1.0, 2.0] }
    func getWideAngleZoomFactor() async -> CGFloat { 1.0 }

    func updateTimerCountdown(value: Int) { countdownTicks.append(value) }
    func playCountdownChime(remaining: Int) { chimes.append(remaining) }
    func restoreTorchAfterCountdown() { torchRestores += 1 }
    func exitCamera() { exitCameraCalls += 1 }
}

// MARK: - Recording watch pusher

class RecordingWatchPusher: WatchStatePushing {
    var pushedSnapshots: [WatchCameraStateSnapshot] = []
    var disconnectedPushes = 0

    var lastEvent: RemoteShutter_WatchEventType? { pushedSnapshots.last(where: { $0.event != .unknown })?.event }
    var allEvents: [RemoteShutter_WatchEventType] { pushedSnapshots.map(\.event).filter { $0 != .unknown } }

    func pushCameraState(_ snapshot: WatchCameraStateSnapshot) {
        pushedSnapshots.append(snapshot)
    }
    func pushDisconnectedState() {
        disconnectedPushes += 1
    }
}

// MARK: - Coordinator test harness

/// A coordinator wired to fakes, plus the fakes themselves for assertions.
struct CoordinatorHarness {
    let coordinator: SessionCoordinator
    let fakeMP: FakeMultipeerService
    let alerts: FakeAlertPresenter
    let lobby: FakeScannerLobby
    let lobbyWrapper: WeakScannerLobby
    let peer: MCPeerID

    /// Enqueue-and-drain: delivers through the same FIFO inbox production uses.
    func deliver(_ msg: Message) async {
        coordinator.tell(msg)
        await coordinator.waitForIdle()
        // Pump main briefly for OperationQueue.main hops (alerts, lobby calls).
        await MainActor.run { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02)) }
    }

    func stateName() async -> RemoteCamState {
        await coordinator.currentStateName()
    }
}

func makeCoordinatorHarness() async -> CoordinatorHarness {
    let coordinator = SessionCoordinator()
    let fakeMP = FakeMultipeerService()
    let alerts = FakeAlertPresenter()
    let lobby = FakeScannerLobby()
    let peer = MCPeerID(displayName: "TestPeer")

    fakeMP.connectedPeers = [peer]
    fakeMP.sendResult = Success(Message())

    await coordinator.setMultipeerService(fakeMP)
    await coordinator.setAlertPresenter(alerts)

    return CoordinatorHarness(
        coordinator: coordinator,
        fakeMP: fakeMP,
        alerts: alerts,
        lobby: lobby,
        lobbyWrapper: WeakScannerLobby(lobby),
        peer: peer)
}
