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
 */
final class CameraRig {

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
        frameSink: { [frameSender] frame in frameSender ! frame })

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

    let session: ActorRef = getRemoteCamSession()!
    let frameSender: ActorRef = getFrameSender()!

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

    init() {
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
    }

    /// Photos-library access denied while saving a finished video. Main thread.
    var onPhotosAccessDenied: (() -> Void)?

    // MARK: - Lifecycle (driven by the shell)

    private var didInitializeCamera = false

    /// Configures and starts the capture session once (on the engine's session
    /// queue); safe to call on every appearance. The busy spinner shows while
    /// the engine works — and now actually renders, since setup is off main.
    func startCameraOnce() {
        guard !didInitializeCamera else { return }
        didInitializeCamera = true
        cameraViewModel.isBusy = true
        engine.setupCamera(sampleBufferDelegate: streamingCoordinator) { [weak self] hasCamera in
            // Completion arrives on main.
            guard let self = self else { return }
            self.cameraViewModel.isBusy = false
            guard hasCamera else { return }
            self.cameraViewModel.previewSession = self.engine.captureSession
            self.sessionPublished.value = true
            self.rotateCameraToOrientation(orientation: self.orientation)
        }
    }

    /// Stops the capture session (screen teardown).
    func stopSession() {
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

    var isTorchActive: Bool {
        engine.isTorchActive()
    }

    var currentFlashMode: AVCaptureDevice.FlashMode {
        engine.currentFlashModeValue()
    }

    // The session's camera states drive the camera through this surface; the
    // thin wrappers route calls to the engine/pipeline, which own the capture
    // session, recording, and all configuration concerns.

    func toggleCamera() -> Try<(AVCaptureDevice.FlashMode?, AVCaptureDevice.Position)> {
        let orientation = self.orientation
        let result = engine.toggleCamera(orientation: orientation)
        // Rotate the preview to match the newly rotated output connections.
        rotateCameraToOrientation(orientation: orientation)
        return result
    }

    func toggleFlash() -> Try<AVCaptureDevice.FlashMode> {
        engine.toggleFlash()
    }

    func toggleTorch() -> Try<AVCaptureDevice.TorchMode> {
        engine.toggleTorch()
    }

    func setTorchMode(mode: AVCaptureDevice.TorchMode) -> Try<AVCaptureDevice.TorchMode> {
        engine.setTorchMode(mode: mode)
    }

    func setZoom(zoomFactor: CGFloat) -> Try<(CGFloat, CameraLensType, RemoteCmd.ZoomRange)> {
        engine.setZoom(zoomFactor: zoomFactor)
    }

    func switchLens(to lensType: CameraLensType) -> Try<(CameraLensType, [CameraLensType], CGFloat, RemoteCmd.ZoomRange)> {
        engine.switchLens(to: lensType)
    }

    func setVideoQuality(resolution: VideoResolution, frameRate: VideoFrameRate) -> (VideoResolution, VideoFrameRate)? {
        engine.setVideoQuality(resolution: resolution, frameRate: frameRate, isRecording: isRecording)
    }

    func setPhotoQuality(format: PhotoFormat, hdrMode: HDRMode) -> (PhotoFormat, HDRMode)? {
        engine.setPhotoQuality(format: format, hdrMode: hdrMode)
    }

    func setAspectRatio(_ ratio: AspectRatio) -> AspectRatio {
        engine.setAspectRatio(ratio)
    }

    func gatherAllCameraCapabilities() {
        engine.gatherAllCameraCapabilities()
    }

    func gatherCurrentCameraCapabilities() -> RemoteCmd.CameraCapabilitiesResp? {
        engine.gatherCurrentCameraCapabilities()
    }

    func takePicture(_ sendMediaToRemote: Bool) {
        engine.takePicture(sendMediaToRemote)
    }

    func getCurrentZoomFactor() -> CGFloat { engine.getCurrentZoomFactor() }
    func getMaxZoomFactor() -> CGFloat { engine.getMaxZoomFactor() }
    func getMinZoomFactor() -> CGFloat { engine.getMinZoomFactor() }
    func getAvailableLensTypes() -> [CameraLensType] { engine.getAvailableLensTypes() }
    func getCurrentLensType() -> CameraLensType { engine.getCurrentLensType() }
    func getZoomStops() -> [CGFloat] { engine.getZoomStops() }
    func getWideAngleZoomFactor() -> CGFloat { engine.getWideAngleZoomFactor() }

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
        ^{
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
        ^{
            self.onExit?()
        }
    }

    /// The Watch acked the in-flight preview frame — let the streamer send the next.
    func acknowledgeWatchPreview() {
        streamingCoordinator.acknowledgeWatchPreview()
    }
}
