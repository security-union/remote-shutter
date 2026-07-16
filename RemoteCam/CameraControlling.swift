//
//  CameraControlling.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union. All rights reserved.
//

import Foundation
import AVFoundation

/// Everything the session's camera states (phone and Watch paths) need from
/// the camera screen. `CameraRig` is the production implementation;
/// tests substitute a fake so the state machine can be exercised without
/// AVFoundation or a view hierarchy.
///
/// Commands and reads are `async` — the production rig hops onto the capture
/// engine's session queue without blocking the caller. Failable commands
/// `throw` instead of returning `Try` (the states pack the error into the
/// response message either way). The few synchronous members are backed by
/// lock-boxed values and are safe from any thread — which is also why the
/// protocol requires `Sendable` (the session actor captures the rig in
/// cross-queue hops).
protocol CameraControlling: AnyObject, Sendable {
    var currentCameraMode: RecordingMode { get set }
    var isRecording: Bool { get }
    var cameraViewModel: CameraViewModel { get }

    func isTorchActive() async -> Bool
    func currentFlashMode() async -> AVCaptureDevice.FlashMode

    func updateCameraStatus()
    func takePicture(_ sendMediaToRemote: Bool)
    func startRecordingVideo()
    func stopRecordingVideo(_ shouldSendVideo: Bool)

    func setZoom(zoomFactor: CGFloat) async throws -> (CGFloat, CameraLensType, RemoteCmd.ZoomRange)
    /// Sets the focus/exposure point of interest from a monitor tap. `x`/`y` are
    /// normalized (0..1) in the upright display image, origin top-left.
    /// Fire-and-forget: a no-op if the active device has no point of interest.
    func focusAtPoint(x: Float, y: Float) async throws
    func switchLens(to lensType: CameraLensType) async throws -> (CameraLensType, [CameraLensType], CGFloat, RemoteCmd.ZoomRange)
    func toggleFlash() async throws -> AVCaptureDevice.FlashMode
    func toggleTorch() async throws -> AVCaptureDevice.TorchMode
    func toggleCamera() async throws -> (AVCaptureDevice.FlashMode?, AVCaptureDevice.Position)
    /// All selectable local cameras, in stable discovery order (a Mac exposes
    /// N devices; an iPhone its front/back pair).
    func availableCameraDevices() async -> [CameraDeviceDescriptor]
    /// The active device, or nil before setup completes.
    func currentCameraDevice() async -> CameraDeviceDescriptor?
    /// Switches capture to the device with this uniqueID, falling back to a
    /// same-position or first-available device if it vanished (unplugged).
    func selectCameraDevice(uniqueID: String) async throws -> CameraSelectionResult
    /// Whether a video frame arrives within `timeout` from now. A camera can
    /// accept the input swap and still never deliver (a wedged virtual
    /// camera) — switch responses are only successful once this confirms.
    func awaitFrameDelivery(timeout: TimeInterval) async -> Bool
    func setTorchMode(mode: AVCaptureDevice.TorchMode) async throws -> AVCaptureDevice.TorchMode
    func setVideoQuality(resolution: VideoResolution, frameRate: VideoFrameRate) async -> (VideoResolution, VideoFrameRate)?
    func setPhotoQuality(format: PhotoFormat, hdrMode: HDRMode) async -> (PhotoFormat, HDRMode)?
    func setAspectRatio(_ ratio: AspectRatio) async -> AspectRatio
    func gatherAllCameraCapabilities() async
    func gatherCurrentCameraCapabilities() async -> RemoteCmd.CameraCapabilitiesResp?

    func getCurrentZoomFactor() async -> CGFloat
    func getMinZoomFactor() async -> CGFloat
    func getMaxZoomFactor() async -> CGFloat
    func getCurrentLensType() async -> CameraLensType
    func getAvailableLensTypes() async -> [CameraLensType]
    func getZoomStops() async -> [CGFloat]
    func getWideAngleZoomFactor() async -> CGFloat

    /// Drives the on-phone countdown overlay/chime for timer captures.
    /// value > 0: tick; 0: fired; < 0: cancelled.
    func updateTimerCountdown(value: Int)
    func playCountdownChime(remaining: Int)
    func restoreTorchAfterCountdown()

    /// Leave the camera screen (e.g. the peer refused the camera role).
    func exitCamera()
}

// The production implementation is `CameraRig` (CameraRig.swift) — a plain,
// non-UI object; the loopback tests drive these states through fakes.
