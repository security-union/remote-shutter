import SwiftUI
import UIKit
import AVFoundation

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
            onZoomChange: { [weak self] factor in
                self?.handleZoomChange(factor)
            },
            onLensChange: { [weak self] lensType in
                self?.handleLensChange(lensType)
            },
            onVideoQualityChange: { [weak self] resolution, frameRate in
                self?.handleVideoQualityChange(resolution, frameRate)
            },
            onPhotoQualityChange: { [weak self] format, hdrMode in
                self?.handlePhotoQualityChange(format, hdrMode)
            },
            onAspectRatioChange: { [weak self] ratio in
                self?.handleAspectRatioChange(ratio)
            }
        )
        
        // Host SwiftUI view
        let hostingController = UIHostingController(rootView: monitorView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
        
        // Setup constraints
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Store reference to hosting controller
        self.swiftUIHostingController = hostingController
    }
    
    // MARK: - Action Handlers
    private func handleTakePicture() {
        print("🔴 DEBUG: handleTakePicture called - isRecording: \(viewModel.isRecording), uiState: \(viewModel.uiState)")
        
        // If timer is running, cancel it
        if viewModel.timerValue > 0 {
            print("🔴 DEBUG: Canceling timer countdown")
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
            print("🔴 DEBUG: Starting timer countdown: \(timerDuration) seconds")
            startTimerCountdown(duration: timerDuration)
        } else {
            // No timer or shorts mode - execute immediately
            print("🔴 DEBUG: No timer - executing immediately")
            executeAction()
        }
    }
    
    private func startTimerCountdown(duration: Int) {
        // Update UI to show countdown starting
        viewModel.timerValue = duration
        viewModel.buttonPrompt = "\(duration)"

        // Play initial countdown beep
        if duration == 2 {
            soundManager.playBeepSound(CPSoundManagerAudioTypeFast)
        }else  if duration > 2 {
            // no op
        } else {
            soundManager.playBeepSound(CPSoundManagerAudioTypeSlow)
        }

        // Send initial countdown tick to camera
        session ! UICmd.TimerCountdown(value: duration)

        self.timer.start(withDuration: duration, withTickHandler: { [weak self] timer in
            DispatchQueue.main.async {
                let remaining = timer!.timeRemaining()
                self?.viewModel.timerValue = Int(remaining)
                self?.viewModel.buttonPrompt = "\(remaining)"

                // Play countdown chimes
                if remaining == 2 {
                    // Fast beep only for final second
                    self?.soundManager.playBeepSound(CPSoundManagerAudioTypeFast)
                } else if remaining < 2 {
                    // No op
                } else {
                    // Regular beep for all other countdown
                    self?.soundManager.playBeepSound(CPSoundManagerAudioTypeSlow)
                }

                // Send countdown tick to camera
                if let session = self?.session {
                    session ! UICmd.TimerCountdown(value: Int(remaining))
                }

                print("🔴 DEBUG: Timer tick - \(remaining) seconds remaining")
            }
        }, andCompletionHandler: { [weak self] _ in
            DispatchQueue.main.async {
                print("🔴 DEBUG: Timer completed - taking picture")
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
    
    private func handleToggleCamera() {
        session ! UICmd.ToggleCamera()
    }
    
    private func handleToggleFlash() {
        session ! UICmd.ToggleFlash()
    }
    
    private func handleToggleTorch() {
        if StoreManager.shared.hasTorchFeature() {
            session ! UICmd.ToggleTorch()
        } else {
            handleSettingsTapped()
        }
    }
    
    private func handleTimerChange(_ value: Int) {
        viewModel.timerSliderValue = Double(value)
        // UserDefaults persistence is now handled in the view model
    }
    
    private func handleModeChange(_ mode: RecordingMode) {
        // Check permissions for video/shorts
        if mode == .Video || mode == .Shorts {
            if StoreManager.shared.hasVideoRecordingFeature() {
                session ! UICmd.BecomeMonitor(nil, mode: mode)

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
            session ! UICmd.BecomeMonitor(nil, mode: mode)
            sendSyncMonitorSettings()
        }
    }
    
    private func handleGalleryTapped() {
        showGallery()
    }
    
    private func handleSettingsTapped() {
        showSettings()
    }
    
    private func handleZoomChange(_ factor: CGFloat) {
        currentZoomFactor = factor
        session ! UICmd.SetZoom(zoomFactor: factor)
    }
    
    private func handleLensChange(_ lensType: CameraLensType) {
        currentLensType = lensType
        session ! UICmd.SwitchLens(lensType: lensType)
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
        let imagePickerController = UIImagePickerController()
        imagePickerController.delegate = self
        imagePickerController.sourceType = .photoLibrary
        imagePickerController.mediaTypes = ["public.image", "public.movie"]
        
        #if targetEnvironment(macCatalyst)
        imagePickerController.modalPresentationStyle = .pageSheet
        #else
        imagePickerController.modalPresentationStyle = .popover
        imagePickerController.popoverPresentationController?.sourceView = view
        imagePickerController.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        #endif
        
        present(imagePickerController, animated: true)
    }
    
    private func showSettings() {
        let ctrl = UIHostingController(rootView: SettingsView())
        ctrl.modalPresentationStyle = .pageSheet
        present(ctrl, animated: true)
    }
}

// MARK: - SwiftUI Configuration Methods
extension MonitorViewController {
    
    func swiftUIConfigurePhotoMode() {
        viewModel.configurePhotoMode()
        viewModel.currentMode = .Photo
        navigationController?.setNavigationBarHidden(false, animated: true)
        sendSyncMonitorSettings()
    }

    func swiftUIConfigureVideoMode() {
        viewModel.configureVideoMode()
        viewModel.currentMode = .Video
        navigationController?.setNavigationBarHidden(false, animated: true)
        sendSyncMonitorSettings()
    }

    func swiftUIConfigureVideoRecording() {
        viewModel.configureVideoRecording()
        navigationController?.setNavigationBarHidden(true, animated: true)
    }

    func swiftUIConfigureShortsMode() {
        viewModel.configureShortsMode()
        viewModel.currentMode = .Shorts
        navigationController?.setNavigationBarHidden(false, animated: true)
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
    // Video transfer progress is now handled directly via MonitorActor
    // using proper actor message passing instead of notifications
} 
