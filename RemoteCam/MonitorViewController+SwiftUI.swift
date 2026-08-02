import SwiftUI
import UIKit
import AVFoundation
import PhotosUI

// MARK: - MonitorViewController SwiftUI Integration
extension MonitorViewController {
    
    // MARK: - SwiftUI Setup
    func setupSwiftUIView() {
        // Create SwiftUI view with callbacks
        let monitorView = MonitorView(
            viewModel: viewModel,
            onTakePicture: { [weak self] in
                self?.handleTakePicture()
            },
            onToggleCamera: { [weak self] in
                self?.handleToggleCamera()
            },
            onSelectCameraDevice: { [weak self] uniqueID in
                self?.handleSelectCameraDevice(uniqueID)
            },
            onToggleFlash: { [weak self] in
                self?.handleToggleFlash()
            },
            onToggleTorch: { [weak self] in
                self?.handleToggleTorch()
            },
            onTimerChange: { [weak self] value in
                self?.handleTimerChange(value)
            },
            onModeChange: { [weak self] mode in
                self?.handleModeChange(mode)
            },
            onGalleryTapped: { [weak self] in
                self?.handleGalleryTapped()
            },
            onSettingsTapped: { [weak self] in
                self?.handleSettingsTapped()
            },
            onHelpTapped: { [weak self] in
                self?.presentHelpSheet()
            },
            onBackTapped: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onZoomChange: { [weak self] factor in
                self?.handleZoomChange(factor)
            },
            onVideoQualityChange: { [weak self] resolution, frameRate in
                self?.handleVideoQualityChange(resolution, frameRate)
            },
            onPhotoQualityChange: { [weak self] format, hdrMode in
                self?.handlePhotoQualityChange(format, hdrMode)
            },
            onAspectRatioChange: { [weak self] ratio in
                self?.handleAspectRatioChange(ratio)
            },
            onFocusTap: { [weak self] point in
                self?.handleFocusTap(point)
            },
            onToggleCameraStandby: { [weak self] in
                self?.handleToggleCameraStandby()
            }
        )

        self.swiftUIHostingController = embedSwiftUIView(monitorView)
    }
    
    // MARK: - Action Handlers
    private func handleTakePicture() {
        debugLog("🔴 DEBUG: handleTakePicture called - isRecording: \(viewModel.isRecording), uiState: \(viewModel.uiState)")
        
        // If timer is running, cancel it
        if viewModel.timerValue > 0 {
            debugLog("🔴 DEBUG: Canceling timer countdown")
            self.timer.cancel()
            self.soundManager.stopPlayer() // Stop any playing sound
            // Send cancellation to camera
            session ! UICmd.TimerCountdown(value: -1)

            resetTimerUI()
            return
        }
        
        let timerDuration = Int(viewModel.timerSliderValue)
        
        if timerDuration > 0 && (viewModel.uiState == .photoMode || viewModel.uiState == .videoMode) {
            // Start timer countdown for photo or video
            debugLog("🔴 DEBUG: Starting timer countdown: \(timerDuration) seconds")
            startTimerCountdown(duration: timerDuration)
        } else {
            // No timer or shorts mode - execute immediately
            debugLog("🔴 DEBUG: No timer - executing immediately")
            executeAction()
        }
    }
    
    private func startTimerCountdown(duration: Int) {
        // Update UI to show countdown starting
        viewModel.timerValue = duration
        viewModel.buttonPrompt = "\(duration)"

        // Play initial countdown beep
        if duration == 2 {
            soundManager.playBeepSound(.fast)
        } else if duration > 2 {
            // no op
        } else {
            soundManager.playBeepSound(.slow)
        }

        // Send initial countdown tick to camera
        session ! UICmd.TimerCountdown(value: duration)

        self.timer.start(duration: duration, onTick: { [weak self] timer in
            DispatchQueue.main.async {
                let remaining = timer.timeRemaining
                self?.viewModel.timerValue = remaining
                self?.viewModel.buttonPrompt = "\(remaining)"

                // Play countdown chimes
                if remaining == 2 {
                    // Fast beep only for final second
                    self?.soundManager.playBeepSound(.fast)
                } else if remaining < 2 {
                    // No op
                } else {
                    // Regular beep for all other countdown
                    self?.soundManager.playBeepSound(.slow)
                }

                // Send countdown tick to camera
                if let session = self?.session {
                    session ! UICmd.TimerCountdown(value: remaining)
                }

                debugLog("🔴 DEBUG: Timer tick - \(remaining) seconds remaining")
            }
        }, onCompletion: { [weak self] _ in
            DispatchQueue.main.async {
                debugLog("🔴 DEBUG: Timer completed - taking picture")
                // Send completion tick to camera
                if let session = self?.session {
                    session ! UICmd.TimerCountdown(value: 0)
                }
                self?.executeAction()
                self?.resetTimerUI()
            }
        })
    }
    
    private func executeAction() {
        let defaults = UserDefaults.standard
        let shouldSendMedia = defaults.object(forKey: "sendMediaToRemote") == nil
            ? true
            : defaults.bool(forKey: "sendMediaToRemote")
        session ! UICmd.TakePicture(sender: nil, sendMediaToRemote: shouldSendMedia)
    }
    
    private func resetTimerUI() {
        viewModel.timerValue = 0
        switch viewModel.uiState {
        case .photoMode:
            viewModel.buttonPrompt = NSLocalizedString("Taking photo", comment: "")
        case .videoMode:
            viewModel.buttonPrompt = NSLocalizedString("Starting video", comment: "")
        case .videoRecording:
            viewModel.buttonPrompt = NSLocalizedString("Stopping video", comment: "")
        case .shortsMode:
            viewModel.buttonPrompt = NSLocalizedString("Recording shorts", comment: "")
        }
    }
    
    private func handleSelectCameraDevice(_ uniqueID: String) {
        session ! UICmd.SelectCameraDevice(uniqueID: uniqueID)
    }

    private func handleToggleCamera() {
        session ! UICmd.ToggleCamera()
    }
    
    // Internal rather than private: the nav-bar capsule is built in
    // MonitorViewController.swift, and `private` is file-scoped.
    func handleToggleFlash() {
        session ! UICmd.ToggleFlash()
    }

    func handleToggleTorch() {
        if StoreManager.shared.hasTorchFeature() {
            session ! UICmd.ToggleTorch()
        } else {
            handleSettingsTapped()
        }
    }

    /// Tap-to-focus. Gated behind its own entitlement; a locked user is routed to
    /// the paywall (mirrors torch). The coordinator additionally drops the command
    /// if the camera peer never advertised focus support.
    private func handleFocusTap(_ point: CGPoint) {
        guard StoreManager.shared.hasTapToFocusFeature() else {
            handleSettingsTapped()
            return
        }
        session ! UICmd.FocusAtPoint(x: Float(point.x), y: Float(point.y))
    }

    /// Toggles the peer camera's local-preview mode. The coordinator gates the
    /// send on the peer having advertised support, so a camera that predates the
    /// feature simply ignores the tap.
    private func handleToggleCameraStandby() {
        let target: CameraPreviewMode = viewModel.cameraPreviewMode == .standby ? .on : .standby
        session ! UICmd.SetCameraPreviewMode(mode: target)
    }

    private func handleTimerChange(_ value: Int) {
        viewModel.timerSliderValue = Double(value)
        // UserDefaults persistence is now handled in the view model
    }
    
    private func handleModeChange(_ mode: RecordingMode) {
        // Check permissions for video/shorts
        if mode == .Video || mode == .Shorts {
            if StoreManager.shared.hasVideoRecordingFeature() {
                session ! UICmd.BecomeMonitor(presenter: presenter, mode: mode)

                // Immediately configure the appropriate UI mode
                // sendSyncMonitorSettings() is called inside each configure method
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    switch mode {
                    case .Video:
                        self?.swiftUIConfigureVideoMode()
                    case .Shorts:
                        self?.swiftUIConfigureShortsMode()
                    default:
                        break
                    }
                }
            } else {
                handleSettingsTapped()
                // Reset to photo mode
                viewModel.currentMode = .Photo
            }
        } else {
            session ! UICmd.BecomeMonitor(presenter: presenter, mode: mode)
            sendSyncMonitorSettings()
        }
    }
    
    private func handleGalleryTapped() {
        showGallery()
    }
    
    private func handleSettingsTapped() {
        showSettings()
    }
    
    /// Single entry point for user-driven zoom, from pinch or the Mac zoom pill.
    /// Throttled to 20Hz with a trailing-edge flush so the value the user released on is
    /// always delivered, mirroring how the Watch drives crown zoom.
    private func handleZoomChange(_ factor: CGFloat) {
        currentZoomFactor = factor

        switch zoomThrottle.update(value: Double(factor), now: Date()) {
        case .sendNow:
            session ! UICmd.SetZoom(zoomFactor: factor)
        case .scheduleTrailing:
            trailingZoomTimer?.invalidate()
            trailingZoomTimer = Timer.scheduledTimer(withTimeInterval: zoomThrottle.interval,
                                                     repeats: false) { [weak self] _ in
                guard let self,
                      let pending = self.zoomThrottle.fireTrailing(now: Date()) else { return }
                self.session ! UICmd.SetZoom(zoomFactor: CGFloat(pending))
            }
        }
    }
    
    private func handleVideoQualityChange(_ resolution: VideoResolution, _ frameRate: VideoFrameRate) {
        session ! UICmd.SetVideoQuality(resolution: resolution, frameRate: frameRate)
    }

    private func handlePhotoQualityChange(_ format: PhotoFormat, _ hdrMode: HDRMode) {
        session ! UICmd.SetPhotoQuality(format: format, hdrMode: hdrMode)
    }

    private func handleAspectRatioChange(_ ratio: AspectRatio) {
        session ! UICmd.SetAspectRatio(aspectRatio: ratio)
    }

    /// Sends the monitor's current mode to the camera device so its overlay shows the right mode
    func sendSyncMonitorSettings() {
        session ! UICmd.SyncMonitorSettings(mode: viewModel.currentMode)
    }
    
    // MARK: - Helper Methods
    
    private func showGallery() {
        var config = PHPickerConfiguration()
        config.filter = .any(of: [.images, .videos])
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        picker.modalPresentationStyle = .pageSheet
        present(picker, animated: true)
    }
    
    private func showSettings() {
        let ctrl = UIHostingController(rootView: SettingsView())
        ctrl.modalPresentationStyle = .pageSheet
        present(ctrl, animated: true)
    }
}

// MARK: - SwiftUI Configuration Methods
extension MonitorViewController {
    
    // Nav-bar visibility is a property of this screen, not of the capture mode:
    // viewWillAppear hides it, viewWillDisappear hands it back. Don't set it here.

    func swiftUIConfigurePhotoMode() {
        viewModel.configurePhotoMode()
        viewModel.currentMode = .Photo
        sendSyncMonitorSettings()
    }

    func swiftUIConfigureVideoMode() {
        viewModel.configureVideoMode()
        viewModel.currentMode = .Video
        sendSyncMonitorSettings()
    }

    func swiftUIConfigureVideoRecording() {
        viewModel.configureVideoRecording()
    }

    func swiftUIConfigureShortsMode() {
        viewModel.configureShortsMode()
        viewModel.currentMode = .Shorts
        sendSyncMonitorSettings()
    }
    
    // MARK: - Update Methods for Actor Integration
    func updateFlashModeInViewModel(_ flashMode: AVCaptureDevice.FlashMode) {
        let statusText: String
        switch flashMode {
        case .off:
            statusText = "Off"
        case .on:
            statusText = "On"
        case .auto:
            statusText = "Auto"
        @unknown default:
            statusText = "None"
        }
        viewModel.updateFlashStatus(statusText, isEnabled: flashMode != .off)
    }
    
    func updateTorchModeInViewModel(_ torchMode: AVCaptureDevice.TorchMode) {
        viewModel.updateTorchStatus(torchMode == .on)
    }
    
    func updateCameraImageInViewModel(_ image: UIImage) {
        viewModel.updateCameraImage(image)
    }
    
    func updateZoomInViewModel(_ factor: CGFloat, maxFactor: CGFloat) {
        viewModel.updateZoomFactor(factor, maxFactor: maxFactor)
    }

    func updateLensTypesInViewModel(_ lenses: [CameraLensType], current: CameraLensType) {
        viewModel.updateAvailableLenses(lenses, current: current)
    }
    
    // MARK: - Video Transfer Progress Methods
    func startVideoTransferInViewModel(totalBytes: Int64) {
        viewModel.startVideoTransfer(totalBytes: totalBytes)
    }
    
    func updateVideoTransferProgressInViewModel(completedBytes: Int64, totalBytes: Int64) {
        viewModel.updateVideoTransferProgress(completedBytes: completedBytes, totalBytes: totalBytes)
    }
    
    func updateVideoTransferSpeedInViewModel(_ bytesPerSecond: Double) {
        viewModel.updateVideoTransferSpeed(bytesPerSecond)
    }
    
    func finishVideoTransferInViewModel() {
        viewModel.finishVideoTransfer()
    }
    
    // MARK: - Video Transfer Progress
    // Video transfer progress is handled via MonitorPresenter
    // using proper actor message passing instead of notifications
} 
