//
//  MonitorPresenter.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import Foundation
import AVFoundation

/// Weak box for the display — the display is deliberately a protocol
/// existential, owned by the monitor screen's view controller.
final class WeakMonitorDisplay {
    weak var value: MonitorDisplay?
    init(_ value: MonitorDisplay) { self.value = value }
}

/**
 The connection between the session and the monitor screen: every method hops
 to the main queue internally and pokes the `MonitorDisplay`/view model —
 except `show(frame:)`, which stays off-main because frame decode runs on the
 receiver's own queue.
 */
public final class MonitorPresenter {

    private var display: WeakMonitorDisplay?

    init() {}

    func setDisplay(_ display: MonitorDisplay) {
        self.display = WeakMonitorDisplay(display)
    }

    private func onMain(_ body: @escaping (MonitorDisplay) -> Void) {
        OperationQueue.main.addOperation { [weak self] in
            guard let display = self?.display?.value else { return }
            body(display)
        }
    }

    // MARK: - Mode rendering

    func renderPhotoMode() {
        onMain { $0.swiftUIConfigurePhotoMode() }
    }

    func renderVideoMode() {
        onMain { $0.swiftUIConfigureVideoMode() }
    }

    func renderVideoModeRecording() {
        onMain { $0.swiftUIConfigureVideoRecording() }
    }

    func renderShortsMode() {
        onMain { $0.swiftUIConfigureShortsMode() }
    }

    /// What the monitor is waiting on the camera for, or `nil` when nothing is.
    ///
    /// Written from the session's single transition point, so the indicator is
    /// a function of the state rather than a side effect that has to be
    /// balanced — the reason the old modal spinner could sit over the preview.
    func setActivity(_ activity: MonitorActivity?) {
        onMain { $0.viewModel.activity = activity }
    }

    func syncRecordingStartTime(_ startTime: Date?) {
        onMain { $0.viewModel.recordingStartTime = startTime }
    }

    func becomeMonitorFailed() {
        onMain { $0.exitMonitor() }
    }

    // MARK: - Live frames (off-main: decode runs on the receiver's queue)

    func show(frame: RemoteCmd.OnFrame) {
        display?.value?.frameStreamReceiver.receive(frame)
    }

    // MARK: - Control responses

    func updateFlashMode(_ flashMode: AVCaptureDevice.FlashMode?) {
        guard let flashMode else { return }
        onMain { $0.updateFlashModeInViewModel(flashMode) }
    }

    func updateTorchMode(_ torchMode: AVCaptureDevice.TorchMode?) {
        guard let torchMode else { return }
        onMain { $0.updateTorchModeInViewModel(torchMode) }
    }

    func updateZoom(_ zoomFactor: CGFloat?, zoomRange: RemoteCmd.ZoomRange?, currentLens: CameraLensType?) {
        guard let zoomFactor else { return }
        onMain { display in
            let maxZoom = zoomRange?.maxZoom ?? display.maxZoomFactor
            display.updateZoomInViewModel(zoomFactor, maxFactor: maxZoom)
            // Sync lens type so zoom and lens controls stay cohesive
            if let lens = currentLens {
                display.viewModel.updateAvailableLenses(display.viewModel.availableLensTypes, current: lens)
            }
        }
    }

    func updateLens(_ lensType: CameraLensType?,
                    availableLenses: [CameraLensType]?,
                    currentZoom: CGFloat?,
                    zoomRange: RemoteCmd.ZoomRange?) {
        guard let lensType, let availableLenses else { return }
        onMain { display in
            display.updateLensTypesInViewModel(availableLenses, current: lensType)
            if let currentZoom, let zoomRange {
                display.updateZoomInViewModel(currentZoom, maxFactor: zoomRange.maxZoom)
            }
        }
    }

    func updateCapabilities(_ capabilities: RemoteCmd.CameraCapabilitiesResp) {
        onMain { display in
            // Device list first: a Mac camera has no front/back info, so the
            // guard below would otherwise starve the device picker.
            display.viewModel.updateCameraDevices(
                capabilities.cameraDevices,
                activeID: capabilities.activeDeviceID)

            // Set before the cameraInfo guard below: preview-mode support is a
            // property of the peer, not of whichever camera it has selected, so
            // a peer that reports no current camera must not lose the flag.
            display.viewModel.supportsCameraStandby = capabilities.supportsPreviewMode

            guard let cameraInfo = capabilities.getCurrentCameraInfo() else { return }
            // Update lens controls in view model
            display.updateLensTypesInViewModel(
                cameraInfo.availableLenses,
                current: capabilities.currentLens
            )

            // Update zoom controls in view model
            if let zoomRange = cameraInfo.getZoomCapabilities()[capabilities.currentLens] {
                display.updateZoomInViewModel(
                    capabilities.currentZoom,
                    maxFactor: zoomRange.maxZoom
                )
            }

            // Update quality capabilities in view model
            display.viewModel.updateVideoCapabilities(
                resolutions: cameraInfo.supportedResolutions,
                frameRates: cameraInfo.supportedFrameRates,
                resolutionFrameRates: cameraInfo.getResolutionFrameRates())
            display.viewModel.updatePhotoCapabilities(
                supportsHEIF: cameraInfo.supportsHEIF,
                supportsHDR: cameraInfo.supportsHDR)

            // Sync current quality settings from camera
            display.viewModel.updateVideoQuality(
                resolution: capabilities.currentVideoResolution,
                frameRate: capabilities.currentVideoFrameRate)
            display.viewModel.updatePhotoQuality(
                format: capabilities.currentPhotoFormat,
                hdrMode: capabilities.currentHDRMode)

            // Update zoom stops from camera capabilities
            display.viewModel.updateZoomStops(
                cameraInfo.zoomStops,
                wideAngleZoomFactor: cameraInfo.wideAngleZoomFactor
            )
        }
    }

    func updateVideoQuality(resolution: VideoResolution?, frameRate: VideoFrameRate?) {
        guard let resolution, let frameRate else { return }
        onMain { $0.viewModel.updateVideoQuality(resolution: resolution, frameRate: frameRate) }
    }

    func updatePhotoQuality(format: PhotoFormat?, hdrMode: HDRMode?) {
        guard let format, let hdrMode else { return }
        onMain { $0.viewModel.updatePhotoQuality(format: format, hdrMode: hdrMode) }
    }

    func updateAspectRatio(_ ratio: AspectRatio?) {
        guard let ratio else { return }
        onMain { $0.viewModel.updateAspectRatio(ratio) }
    }

    /// Reflects the camera device's current local-preview mode so the operator
    /// can see whether the camera is showing a live preview or in standby.
    func updatePreviewMode(_ mode: CameraPreviewMode) {
        onMain { $0.viewModel.cameraPreviewMode = mode }
    }

    // MARK: - Video transfer progress

    func videoTransferStarted(totalBytes: Int64) {
        onMain { $0.viewModel.startVideoTransfer(totalBytes: totalBytes) }
    }

    func videoTransferProgress(completedBytes: Int64, totalBytes: Int64, transferSpeed: Double) {
        onMain { display in
            display.viewModel.updateVideoTransferProgress(
                completedBytes: completedBytes,
                totalBytes: totalBytes
            )
            display.viewModel.updateVideoTransferSpeed(transferSpeed)
        }
    }

    func videoTransferFinished() {
        onMain { $0.viewModel.finishVideoTransfer() }
    }
}
