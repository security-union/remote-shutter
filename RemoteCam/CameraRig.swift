//
//  CameraRig.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit

/**
Default fps, it would be neat if we would adjust this based on network conditions.
Lock-boxed: written on the engine's session queue (frame-rate changes), read
per-frame on the data queue by the frame streamer.
*/
let fpsSetting = Locked(30)

/**
 The camera device, as one non-UI object: owns the capture stack
 (`CaptureEngine` + `RecordingPipeline` + `FrameStreamingCoordinator`), the
 screen's view model, and the countdown chime/torch — and is the production
 `CameraControlling` conformer handed to the actor system. The view-controller
 shell (`CameraHostController`) owns navigation, permissions UI and lifecycle,
 and reaches back in through the closure seams below.

 `@unchecked Sendable`: state is confined to the capture queues, and the
 synchronous cross-thread members are lock-boxed (see `CameraControlling`).
 */
final class CameraRig: @unchecked Sendable {

    /// Owns the capture session, still-photo capture and all camera configuration.
    let engine = CaptureEngine()

    /// Owns the asset writer, recording state machine and per-frame writing.
    lazy var pipeline = RecordingPipeline(engine: engine)

    /// The capture session's sample-buffer delegate: routes frames to the
    /// preview streamers and, while recording, to the pipeline. The providers
    /// read state owned here; the sink captures the actor ref, not the rig.
    lazy var streamingCoordinator = FrameStreamingCoordinator(
        engine: engine,
        pipeline: pipeline,
        orientationProvider: { [weak self] in self?.orientation ?? .portrait },
        isWatchRemoteMode: { [weak self] in self?.isWatchRemoteMode ?? false },
        frameSink: { [frameSender] frame in frameSender.send(frame) },
        peerVP9Enabled: { [frameSender] in frameSender.peerSupportsVP9.value },
        frameCreditAvailable: { [frameSender] in frameSender.hasCredit() },
        takePeerKeyframeRequest: { [frameSender] in frameSender.takeKeyframeRequest() })

    var isRecording: Bool { pipeline.isRecording }

    /// Orientation used for the preview and the frame streamer. The engine
    /// keeps its own copy for the output/photo connections (kept in sync here).
    /// Lock-boxed: written on main (rotation), read per-frame on the data queue.
    private let orientationShared = Locked(UIInterfaceOrientation.portrait)
    var orientation: UIInterfaceOrientation {
        get { orientationShared.value }
        set { orientationShared.value = newValue }
    }

    /// Whether `startCameraOnce` has published the session (guards rotation).
    /// Lock-boxed: written on main, read on the actor mailbox (toggleCamera).
    private let sessionPublished = Locked(false)

    let session: SessionCoordinator
    let frameSender: FrameSender

    /// When true, this camera is controlled by an Apple Watch via WCSession.
    /// Suppresses MultipeerConnectivity-related actor messages (BecomeCamera/UnbecomeCamera).
    var isWatchRemoteMode = false

    /// One view model drives the whole SwiftUI screen: preview session,
    /// recording badge/timer, spinner, countdown, status and transfer overlays.
    let cameraViewModel = CameraViewModel()

    // MARK: - Sound Manager for Countdown Chimes
    let cameraSoundManager = SoundManager()

    // MARK: - Countdown Torch
    let countdownTorch = CameraCountdownTorch()

    /// Lock-boxed: written on the actor mailbox (mode changes) and main
    /// (recording chrome), read wherever the status overlay updates.
    private let currentCameraModeShared = Locked(RecordingMode.Photo)
    var currentCameraMode: RecordingMode {
        get { currentCameraModeShared.value }
        set { currentCameraModeShared.value = newValue }
    }

    // MARK: - Shell seams

    /// Hide/show the navigation bar for recording/idle mode. Main thread.
    var setNavigationBarHidden: ((Bool) -> Void)?
    /// Leave the camera screen (peer refused the role, etc.). Main thread.
    var onExit: (() -> Void)?
    /// Microphone permission denied while starting a recording. Main thread.
    var onMicrophoneDenied: (() -> Void)?

    init(session: SessionCoordinator, frameSender: FrameSender) {
        self.session = session
        self.frameSender = frameSender
        wireCallbacks()
    }

    /// Bridges the non-UI engine/pipeline back to the actor system and the screen.
    private func wireCallbacks() {
        // Captures the session ref (not self) so an in-flight capture still
        // reaches the actor if the rig deallocates before the delegate fires.
        engine.onPicture = { [session] pic, error in
            if let error {
                session ! UICmd.OnPicture(sender: nil, error: error)
            } else if let pic {
                session ! UICmd.OnPicture(sender: nil, pic: pic)
            }
        }
        engine.onStatusChanged = { [weak self] in
            self?.updateCameraStatus()
        }
        // Captures the session ref (not self) so recording acks/responses still
        // reach the actor if the rig deallocates mid-recording.
        pipeline.sendMessage = { [session] msg in
            session ! msg
        }
        pipeline.onRecordingStarted = { [weak self] startTime in
            self?.cameraViewModel.recordingStartTime = startTime
            self?.cameraViewModel.isRecordingTimerActive = true
        }
        pipeline.onRecordingStopped = { [weak self] in
            self?.cameraViewModel.recordingStartTime = nil
            self?.cameraViewModel.isRecordingTimerActive = false
        }
        pipeline.onModeChanged = { [weak self] idle in
            if idle {
                self?.configureIdleMode()
            } else {
                self?.configureVideoModeRecording()
            }
        }
        pipeline.onError = { message in
            showError(message)
        }
        pipeline.onPhotosAccessDenied = { [weak self] in
            self?.onPhotosAccessDenied?()
        }
        engine.onCameraDevicesChanged = { [weak self] in
            // Hot-plug (fires on the session queue): refresh the picker and,
            // when a monitor is connected, re-advertise capabilities.
            Task { [weak self] in
                guard let self else { return }
                await self.refreshCameraDeviceList()
                if !self.isWatchRemoteMode {
                    self.session ! RemoteCmd.RequestCameraCapabilities()
                }
            }
        }
    }

    // MARK: - First-frame watchdog

    /// A camera can be connected yet never deliver a frame (suspended
    /// clamshell built-in, stalled virtual camera). Without a watchdog that
    /// is an infinite spinner with no error. Armed after every session start
    /// and device switch; on stall it falls back to the next healthy device
    /// once, then surfaces an error.
    private let watchdogGeneration = Locked(0)
    private static let firstFrameTimeout: TimeInterval = 5

    func armFirstFrameWatchdog(allowFallback: Bool = true) {
        var generation = 0
        watchdogGeneration.mutate { $0 += 1; generation = $0 }
        let armedAt = Date().timeIntervalSinceReferenceDate
        DispatchQueue.global(qos: .userInitiated).asyncAfter(
            deadline: .now() + Self.firstFrameTimeout
        ) { [weak self] in
            guard let self,
                  self.watchdogGeneration.value == generation,
                  self.streamingCoordinator.lastVideoFrameAt.value < armedAt else { return }
            self.handleFrameStall(allowFallback: allowFallback)
        }
    }

    /// Cancels any armed watchdog (screen teardown).
    private func disarmFirstFrameWatchdog() {
        watchdogGeneration.mutate { $0 += 1 }
    }

    private func handleFrameStall(allowFallback: Bool) {
        Task { [weak self] in
            guard let self else { return }
            let current = await self.currentCameraDevice()
            debugLog("CameraRig: no frames from \(current?.localizedName ?? "unknown camera") within \(Self.firstFrameTimeout)s")
            let devices = await self.availableCameraDevices()
            let next = devices.first { !$0.isSuspended && $0.uniqueID != current?.uniqueID }
            guard allowFallback, let next,
                  (try? await self.selectCameraDevice(uniqueID: next.uniqueID)) != nil else {
                showError(NSLocalizedString("Camera is not delivering video", comment: ""))
                return
            }
            debugLog("CameraRig: fell back to \(next.localizedName)")
            // A session that started on the dead source can stay wedged
            // (running, valid graph, no buffers) — bounce it to revive
            // delivery on the fallback device.
            self.engine.restartSession()
            // One fallback attempt per stall — a second stall is an error.
            self.armFirstFrameWatchdog(allowFallback: false)
            if !self.isWatchRemoteMode {
                self.session ! RemoteCmd.RequestCameraCapabilities()
            }
        }
    }

    // MARK: - Local camera-device picker

    /// Publishes the selectable-device list + active device on the view model
    /// (drives the camera screen's picker chrome).
    func refreshCameraDeviceList() async {
        let devices = await engine.availableCameraDevices()
        let active = await engine.currentCameraDevice()
        cameraViewModel.updateCameraDevices(devices, activeID: active?.uniqueID)
    }

    /// Device selection from the camera screen's own picker: switches the
    /// device, confirms frames actually flow, then pushes fresh capabilities
    /// to a connected monitor so its controls stay in sync. A camera that
    /// accepts the swap but never delivers gets a visible error (the
    /// watchdog restores a working device underneath).
    func selectCameraDeviceLocally(uniqueID: String) {
        Task { [weak self] in
            guard let self else { return }
            guard let result = try? await self.selectCameraDevice(uniqueID: uniqueID) else { return }
            if await !self.awaitFrameDelivery(timeout: Self.frameConfirmTimeout) {
                showError(String(
                    format: NSLocalizedString("%@ is not delivering video", comment: "dead camera"),
                    result.device.localizedName))
            }
            if !self.isWatchRemoteMode {
                // The coordinator's camera state answers this by broadcasting
                // capabilities — the same path a monitor's request takes.
                self.session ! RemoteCmd.RequestCameraCapabilities()
            }
        }
    }

    /// Shorter than the watchdog (5s), longer than any healthy camera's
    /// first frame (Continuity ≈ 2.6s measured).
    static let frameConfirmTimeout: TimeInterval = 4

    /// Photos-library access denied while saving a finished video. Main thread.
    var onPhotosAccessDenied: (() -> Void)?

    // MARK: - Lifecycle (driven by the shell)

    private var didInitializeCamera = false

    /// Configures and starts the capture session once (on the engine's session
    /// queue); safe to call on every appearance. The busy spinner shows while
    /// the engine works.
    ///
    /// AVCam's ordering: the preview layer attaches to the (idle) session
    /// BEFORE configuration, so the first rendered frame IS session start.
    /// Attaching after `startRunning` mutates a live graph — trivial on an
    /// iPhone, but a slow renegotiation on Mac hardware (UVC/Continuity),
    /// which made the Mac preview lag iOS by seconds.
    func startCameraOnce() {
        guard !didInitializeCamera else { return }
        didInitializeCamera = true
        cameraViewModel.isBusy = true
        cameraViewModel.previewSession = engine.captureSession
        // Next main tick: the SwiftUI pass attaching the layer lands first,
        // preserving AVCam's attach → configure → start happens-before.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.engine.setupCamera(sampleBufferDelegate: self.streamingCoordinator) { [weak self] hasCamera in
                // Completion arrives on main.
                guard let self = self else { return }
                self.cameraViewModel.isBusy = false
                guard hasCamera else {
                    self.cameraViewModel.previewSession = nil
                    return
                }
                self.sessionPublished.value = true
                self.rotateCameraToOrientation(orientation: self.orientation)
                self.armFirstFrameWatchdog()
                Task { await self.refreshCameraDeviceList() }
            }
        }
    }

    /// Stops the capture session (screen teardown).
    func stopSession() {
        disarmFirstFrameWatchdog()
        engine.stopSession()
    }

    /// Rotates the preview connection (via the published orientation) and the
    /// engine's output/photo connections (cached there for still capture).
    /// Callable from main (rotation) or the actor mailbox (toggleCamera).
    func rotateCameraToOrientation(orientation: UIInterfaceOrientation) {
        // Rotation is meaningless until setupCamera has published the session.
        guard sessionPublished.value else { return }
        let videoOrientation = OrientationUtils.transform(o: orientation)
        DispatchQueue.main.async {
            // @Published — main thread only.
            self.cameraViewModel.previewVideoOrientation = videoOrientation
        }
        _ = engine.rotateOutputs(orientation: orientation)
    }

    // MARK: - Modes

    func configureIdleMode() {
        cameraViewModel.isRecordingIndicatorVisible = false
        setNavigationBarHidden?(false)
        updateCameraStatus()
    }

    func configureVideoModeRecording() {
        cameraViewModel.isRecordingIndicatorVisible = true
        setNavigationBarHidden?(true)
        currentCameraMode = .Video
        updateCameraStatus()
    }

    func updateCameraStatus() {
        let (resolution, frameRate, photoFormat, hdrMode) = engine.statusSnapshot()
        cameraViewModel.updateStatus(
            mode: currentCameraMode,
            resolution: resolution,
            frameRate: frameRate,
            photoFormat: photoFormat,
            hdrMode: hdrMode)
    }

    // MARK: - Countdown chime / torch

    func playCountdownChime(remaining: Int) {
        if remaining == 2 {
            cameraSoundManager.playBeepSound(.fast)
            countdownTorch.startStrobe(device: engine.currentDevice())
        } else if remaining > 2 {
            cameraSoundManager.playBeepSound(.slow)
            countdownTorch.blinkOnce(device: engine.currentDevice())
        }
    }

    /// Turns the torch off for good (screen teardown). Clears the user's intent so the
    /// torch doesn't silently come back when the camera is next configured.
    func ensureTorchOff() {
        engine.clearTorchIntent()
        countdownTorch.stop(device: engine.currentDevice())
        engine.applyDesiredTorch()
    }

    /// Called at the end/cancel of a self-timer countdown: stops the strobe and returns
    /// the torch to whatever the user actually wanted, instead of forcing it off. Keeps
    /// the Watch in sync since the phone changed torch state on its own.
    func restoreTorchAfterCountdown() {
        countdownTorch.stop(device: engine.currentDevice())
        engine.applyDesiredTorch()
        syncTorchToWatch()
    }

    /// Restores the user's torch intent after the capture pipeline reconfigures
    /// (iOS can drop the torch during rotation) and re-syncs the Watch.
    func restoreTorchAfterRotation() {
        engine.applyDesiredTorch()
        syncTorchToWatch()
    }

    /// Pushes a fresh state snapshot to the Watch after the phone changes torch on its own
    /// (rotation, timer), so the Watch's torch indicator never goes stale. No-op outside
    /// Watch Remote mode.
    func syncTorchToWatch() {
        guard isWatchRemoteMode else { return }
        WatchSessionManager.shared.cameraController?.pushCurrentState()
    }
}

// MARK: - CameraControlling (production implementation)

extension CameraRig: CameraControlling {

    func isTorchActive() async -> Bool {
        await engine.isTorchActive()
    }

    func currentFlashMode() async -> AVCaptureDevice.FlashMode {
        await engine.currentFlashModeValue()
    }

    // The session's camera states drive the camera through this surface; the
    // thin wrappers route calls to the engine/pipeline, which own the capture
    // session, recording, and all configuration concerns.

    func toggleCamera() async throws -> (AVCaptureDevice.FlashMode?, AVCaptureDevice.Position) {
        let orientation = self.orientation
        defer {
            // Rotate the preview to match the newly rotated output connections
            // (also after a failed toggle, matching the previous behavior).
            rotateCameraToOrientation(orientation: orientation)
        }
        let result = try await engine.toggleCamera(orientation: orientation)
        armFirstFrameWatchdog()
        await refreshCameraDeviceList()   // keep the local picker's checkmark honest
        return result
    }

    func availableCameraDevices() async -> [CameraDeviceDescriptor] {
        await engine.availableCameraDevices()
    }

    func awaitFrameDelivery(timeout: TimeInterval) async -> Bool {
        let since = Date().timeIntervalSinceReferenceDate
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if streamingCoordinator.lastVideoFrameAt.value > since { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    func currentCameraDevice() async -> CameraDeviceDescriptor? {
        await engine.currentCameraDevice()
    }

    func selectCameraDevice(uniqueID: String) async throws -> CameraSelectionResult {
        let orientation = self.orientation
        defer {
            // Same post-swap preview rotation as toggleCamera.
            rotateCameraToOrientation(orientation: orientation)
        }
        let result = try await engine.selectCameraDevice(uniqueID: uniqueID, orientation: orientation)
        armFirstFrameWatchdog()
        await refreshCameraDeviceList()   // keep the local picker's checkmark honest
        return result
    }

    func toggleFlash() async throws -> AVCaptureDevice.FlashMode {
        try await engine.toggleFlash()
    }

    func toggleTorch() async throws -> AVCaptureDevice.TorchMode {
        try await engine.toggleTorch()
    }

    func setTorchMode(mode: AVCaptureDevice.TorchMode) async throws -> AVCaptureDevice.TorchMode {
        try await engine.setTorchMode(mode: mode)
    }

    func setZoom(zoomFactor: CGFloat) async throws -> (CGFloat, CameraLensType, RemoteCmd.ZoomRange) {
        try await engine.setZoom(zoomFactor: zoomFactor)
    }

    func switchLens(to lensType: CameraLensType) async throws -> (CameraLensType, [CameraLensType], CGFloat, RemoteCmd.ZoomRange) {
        try await engine.switchLens(to: lensType)
    }

    func setVideoQuality(resolution: VideoResolution, frameRate: VideoFrameRate) async -> (VideoResolution, VideoFrameRate)? {
        await engine.setVideoQuality(resolution: resolution, frameRate: frameRate, isRecording: isRecording)
    }

    func setPhotoQuality(format: PhotoFormat, hdrMode: HDRMode) async -> (PhotoFormat, HDRMode)? {
        await engine.setPhotoQuality(format: format, hdrMode: hdrMode)
    }

    func setAspectRatio(_ ratio: AspectRatio) async -> AspectRatio {
        await engine.setAspectRatio(ratio)
    }

    func gatherAllCameraCapabilities() async {
        await engine.gatherAllCameraCapabilities()
    }

    func gatherCurrentCameraCapabilities() async -> RemoteCmd.CameraCapabilitiesResp? {
        await engine.gatherCurrentCameraCapabilities()
    }

    func takePicture(_ sendMediaToRemote: Bool) {
        engine.takePicture(sendMediaToRemote)
    }

    func getCurrentZoomFactor() async -> CGFloat { await engine.getCurrentZoomFactor() }
    func getMaxZoomFactor() async -> CGFloat { await engine.getMaxZoomFactor() }
    func getMinZoomFactor() async -> CGFloat { await engine.getMinZoomFactor() }
    func getAvailableLensTypes() async -> [CameraLensType] { await engine.getAvailableLensTypes() }
    func getCurrentLensType() async -> CameraLensType { await engine.getCurrentLensType() }
    func getZoomStops() async -> [CGFloat] { await engine.getZoomStops() }
    func getWideAngleZoomFactor() async -> CGFloat { await engine.getWideAngleZoomFactor() }

    func startRecordingVideo() {
        // Check microphone permission before starting video recording
        PermissionManager.shared.requestMicrophonePermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if granted {
                    self.pipeline.startRecording(audioSampleBufferDelegate: self.streamingCoordinator)
                } else {
                    // Microphone denied - notify the remote and prompt the user.
                    let microphoneError = NSError(
                        domain: "RemoteShutterError",
                        code: 1001,
                        userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("microphone_access_denied_error", comment: "")]
                    )
                    self.session ! UICmd.MicrophoneAccessDenied(error: microphoneError)
                    self.onMicrophoneDenied?()
                }
            }
        }
    }

    func stopRecordingVideo(_ shouldSendVideo: Bool) {
        pipeline.stopRecording(shouldSendVideo)
    }

    func updateTimerCountdown(value: Int) {
        OperationQueue.main.addOperation {
            if value > 0 {
                self.cameraViewModel.showCountdown(value)
                self.playCountdownChime(remaining: value)
            } else if value == 0 {
                self.cameraViewModel.clearCountdown()
                self.restoreTorchAfterCountdown()
            } else {
                self.cameraViewModel.cancelCountdown()
                self.restoreTorchAfterCountdown()
            }
        }
    }

    func exitCamera() {
        OperationQueue.main.addOperation {
            self.onExit?()
        }
    }

    /// The Watch acked the in-flight preview frame — let the streamer send the next.
    func acknowledgeWatchPreview() {
        streamingCoordinator.acknowledgeWatchPreview()
    }
}
