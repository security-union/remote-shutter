import SwiftUI
import UIKit
import Theater
import AVFoundation

// MARK: - MonitorViewController SwiftUI Integration
extension MonitorViewController {
    
    // MARK: - SwiftUI Setup
    func setupSwiftUIView() {
        // Remove all existing subviews (storyboard remnants)
        view.subviews.forEach { $0.removeFromSuperview() }
        
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
            onBackTapped: { [weak self] in
                self?.handleBackTapped()
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
        // Use existing UICmd.TakePicture logic
        session ! UICmd.TakePicture(sender: nil, sendMediaToRemote: false)
    }
    
    private func handleToggleCamera() {
        session ! UICmd.ToggleCamera()
    }
    
    private func handleToggleFlash() {
        session ! UICmd.ToggleFlash()
    }
    
    private func handleToggleTorch() {
        if InAppPurchasesManager.shared().hasTorchFeature() {
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
            if InAppPurchasesManager.shared().hasVideoRecordingFeature() {
                session ! UICmd.BecomeMonitor(nil, mode: mode)
                
                // Immediately configure the appropriate UI mode
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    switch mode {
                    case .Video:
                        self.swiftUIConfigureVideoMode()
                    case .Shorts:
                        self.swiftUIConfigureShortsMode()
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
        }
    }
    
    private func handleBackTapped() {
        navigationController?.popViewController(animated: true)
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
        // Navigate to settings - this should match the existing logic
        if let settingsVC = storyboard?.instantiateViewController(withIdentifier: "CMConfigurationsViewController") {
            navigationController?.pushViewController(settingsVC, animated: true)
        }
    }
}

// MARK: - SwiftUI Configuration Methods
extension MonitorViewController {
    
    func swiftUIConfigurePhotoMode() {
        viewModel.configurePhotoMode()
        viewModel.currentMode = .Photo
    }
    
    func swiftUIConfigureVideoMode() {
        viewModel.configureVideoMode()
        viewModel.currentMode = .Video
    }
    
    func swiftUIConfigureVideoRecording() {
        viewModel.configureVideoRecording()
    }
    
    func swiftUIConfigureShortsMode() {
        viewModel.configureShortsMode()
        viewModel.currentMode = .Shorts
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
} 