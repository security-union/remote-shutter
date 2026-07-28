//
//  SessionTestSupport.swift
//  RemoteShutterTests
//
//  Shared fakes and helpers for driving SessionCoordinator in tests.
//

import Foundation
import XCTest
import MPCCompat
import Stormo
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

class FakeAlertHandle: AlertHandle, @unchecked Sendable {
    var currentTitle: String?
    var dismissed = false
    init(title: String) { self.currentTitle = title }
}

class FakeAlertPresenter: AlertPresenting, @unchecked Sendable {
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
class FakeScannerLobby: ScannerLobby, @unchecked Sendable {
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
class FakeCameraControlling: CameraControlling, @unchecked Sendable {
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
    var focusCalls: [CGPoint] = []
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
    func focusAtPoint(x: Float, y: Float) async throws {
        if let errorToThrow { throw errorToThrow }
        focusCalls.append(CGPoint(x: CGFloat(x), y: CGFloat(y)))
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

    /// iPhone-shaped by default; tests reshape this to a Mac (N devices,
    /// `.unspecified` positions) to exercise the device-selection paths.
    var availableDevices: [CameraDeviceDescriptor] = [
        CameraDeviceDescriptor(uniqueID: "fake-back", localizedName: "Back Camera",
                               position: .back, deviceType: .builtInWideAngleCamera),
        CameraDeviceDescriptor(uniqueID: "fake-front", localizedName: "Front Camera",
                               position: .front, deviceType: .builtInWideAngleCamera)
    ]
    var activeDeviceID = "fake-back"
    var deviceSelections: [String] = []

    func availableCameraDevices() async -> [CameraDeviceDescriptor] { availableDevices }
    func currentCameraDevice() async -> CameraDeviceDescriptor? {
        availableDevices.first { $0.uniqueID == activeDeviceID }
    }
    func selectCameraDevice(uniqueID: String) async throws -> CameraSelectionResult {
        if let errorToThrow { throw errorToThrow }
        deviceSelections.append(uniqueID)
        // Mirrors the engine: explicitly selecting a suspended device errors.
        if let requested = availableDevices.first(where: { $0.uniqueID == uniqueID }),
           requested.isSuspended {
            throw NSError(domain: "\(requested.localizedName) is unavailable (suspended)", code: 0, userInfo: nil)
        }
        let fallbackPosition = availableDevices.first { $0.uniqueID == activeDeviceID }?.position ?? .unspecified
        guard let device = CameraDeviceDescriptor.resolveSelection(
                requestedID: uniqueID, available: availableDevices, fallbackPosition: fallbackPosition) else {
            throw NSError(domain: "No camera device available", code: 0, userInfo: nil)
        }
        activeDeviceID = device.uniqueID
        return CameraSelectionResult(
            device: device,
            flashMode: device.position == .back ? flashMode : nil,
            availableLensTypes: [.wideAngle],
            zoomRange: RemoteCmd.ZoomRange(minZoom: 1, maxZoom: 10),
            currentZoom: 1.0)
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
    /// False simulates a legacy peer whose capabilities carry no device list
    /// — the monitor must never send SelectCameraDevice to it.
    var advertisesCameraDevices = true

    /// False simulates a peer whose capabilities omit focus-point support — the
    /// monitor must never send FocusAtPoint to it (old peers decode it as
    /// TakePicture).
    var advertisesFocusPoint = true

    /// Devices that accept the input swap but never deliver a frame (a
    /// wedged virtual camera). While one is active, awaitFrameDelivery fails.
    var stalledDeviceIDs: Set<String> = []

    func awaitFrameDelivery(timeout: TimeInterval) async -> Bool {
        !stalledDeviceIDs.contains(activeDeviceID)
    }

    func setAspectRatio(_ ratio: AspectRatio) async -> AspectRatio { ratio }
    func gatherAllCameraCapabilities() async { gatherCapabilitiesCalls += 1 }
    func gatherCurrentCameraCapabilities() async -> RemoteCmd.CameraCapabilitiesResp? {
        let entries: [RemoteCmd.CameraDeviceEntry] = advertisesCameraDevices
            ? availableDevices.map {
                RemoteCmd.CameraDeviceEntry(
                    uniqueID: $0.uniqueID,
                    localizedName: $0.localizedName,
                    positionRaw: $0.position.rawValue,
                    isActive: $0.uniqueID == activeDeviceID,
                    isSuspended: $0.isSuspended,
                    info: nil)
            }
            : []
        return RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, currentLens: .wideAngle, currentZoom: 1.0,
            cameraDevices: entries,
            activeDeviceID: advertisesCameraDevices ? activeDeviceID : nil,
            supportsFocusPoint: advertisesFocusPoint,
            error: nil)
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
