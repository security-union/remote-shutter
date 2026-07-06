//
//  CameraControlling.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union. All rights reserved.
//

import Foundation
import AVFoundation

/// Everything the session's camera states (phone and Watch paths) need from
/// the camera screen. `CameraViewController` is the production implementation;
/// tests substitute a fake so the state machine can be exercised without
/// AVFoundation or a view hierarchy.
protocol CameraControlling: AnyObject {
    var currentCameraMode: RecordingMode { get set }
    var isRecording: Bool { get }
    var isTorchActive: Bool { get }
    var currentFlashMode: AVCaptureDevice.FlashMode { get }
    var cameraViewModel: CameraViewModel { get }

    func updateCameraStatus()
    func takePicture(_ sendMediaToRemote: Bool)
    func startRecordingVideo()
    func stopRecordingVideo(_ shouldSendVideo: Bool)
    func setZoom(zoomFactor: CGFloat) -> Try<(CGFloat, CameraLensType, RemoteCmd.ZoomRange)>
    func switchLens(to lensType: CameraLensType) -> Try<(CameraLensType, [CameraLensType], CGFloat, RemoteCmd.ZoomRange)>
    func toggleFlash() -> Try<AVCaptureDevice.FlashMode>
    func toggleTorch() -> Try<AVCaptureDevice.TorchMode>
    func toggleCamera() -> Try<(AVCaptureDevice.FlashMode?, AVCaptureDevice.Position)>
    func setTorchMode(mode: AVCaptureDevice.TorchMode) -> Try<AVCaptureDevice.TorchMode>
    func setVideoQuality(resolution: VideoResolution, frameRate: VideoFrameRate) -> (VideoResolution, VideoFrameRate)?
    func setPhotoQuality(format: PhotoFormat, hdrMode: HDRMode) -> (PhotoFormat, HDRMode)?
    func setAspectRatio(_ ratio: AspectRatio) -> AspectRatio
    func gatherAllCameraCapabilities()
    func gatherCurrentCameraCapabilities() -> RemoteCmd.CameraCapabilitiesResp?

    func getCurrentZoomFactor() -> CGFloat
    func getMinZoomFactor() -> CGFloat
    func getMaxZoomFactor() -> CGFloat
    func getCurrentLensType() -> CameraLensType
    func getAvailableLensTypes() -> [CameraLensType]
    func getZoomStops() -> [CGFloat]
    func getWideAngleZoomFactor() -> CGFloat

    /// Drives the on-phone countdown overlay/chime for timer captures.
    /// value > 0: tick; 0: fired; < 0: cancelled.
    func updateTimerCountdown(value: Int)
    func playCountdownChime(remaining: Int)
    func restoreTorchAfterCountdown()

    /// Leave the camera screen (e.g. the peer refused the camera role).
    func exitCamera()
}

// MARK: - Production implementation

extension CameraViewController: CameraControlling {
    var isTorchActive: Bool {
        videoDeviceInput?.device.isTorchActive ?? false
    }

    var currentFlashMode: AVCaptureDevice.FlashMode {
        cameraSettings.flashMode
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
            self.navigationController?.popViewController(animated: true)
        }
    }
}
