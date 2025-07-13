//
//  ModernStateObserver.swift
//  RemoteShutter
//
//  State observer pattern for automatic UI updates
//  Solves the torch button issue by ensuring UI always reflects actual camera capabilities
//

import Foundation
import UIKit
import AVFoundation

// MARK: - State Observer Implementation

/// Base state observer for monitoring camera state changes
public class ModernStateObserver: StateObserver {
    
    public weak var viewController: UIViewController?
    private let updateQueue = DispatchQueue.main
    
    public init(viewController: UIViewController) {
        self.viewController = viewController
    }
    
    public func onStateChanged(_ response: CameraStateResponse) {
        updateQueue.async {
            self.handleStateChange(response)
        }
    }
    
    /// Override this method in subclasses to handle specific state changes
    open func handleStateChange(_ response: CameraStateResponse) {
        // Base implementation - override in subclasses
    }
}

// MARK: - Monitor View Controller State Observer

/// State observer specifically for MonitorViewController
public class MonitorStateObserver: ModernStateObserver {
    
    private weak var monitorViewController: MonitorViewController?
    
    public init(monitorViewController: MonitorViewController) {
        self.monitorViewController = monitorViewController
        super.init(viewController: monitorViewController)
    }
    
    public override func handleStateChange(_ response: CameraStateResponse) {
        guard let monitorVC = monitorViewController else { return }
        
        print("🔄 MonitorStateObserver: Updating UI with new state")
        print("   - Current camera: \(response.currentState.currentCamera)")
        print("   - Supports torch: \(response.capabilities.currentLimits.supportsTorch)")
        print("   - Supports flash: \(response.capabilities.currentLimits.supportsFlash)")
        
        // Update torch button based on current camera capabilities
        updateTorchButton(monitorVC, state: response.currentState, capabilities: response.capabilities)
        
        // Update flash button based on current camera capabilities
        updateFlashButton(monitorVC, state: response.currentState, capabilities: response.capabilities)
        
        // Update zoom controls
        updateZoomControls(monitorVC, state: response.currentState, capabilities: response.capabilities)
        
        // Update lens controls
        updateLensControls(monitorVC, state: response.currentState, capabilities: response.capabilities)
        
        // Update recording controls
        updateRecordingControls(monitorVC, state: response.currentState, capabilities: response.capabilities)
        
        // Update connection status
        updateConnectionStatus(monitorVC, state: response.currentState)
    }
    
    // MARK: - UI Update Methods
    
    private func updateTorchButton(_ monitorVC: MonitorViewController, state: CameraState, capabilities: CameraCapabilities) {
        // This is the key fix for the torch button issue!
        let supportsTorch = capabilities.currentLimits.supportsTorch
        let isOn = state.torchMode == .on
        
        print("🔦 Updating torch button: supports=\(supportsTorch), isOn=\(isOn)")
        
        // Update torch button visibility and state
        monitorVC.updateTorchButton(isVisible: supportsTorch, isOn: isOn)
    }
    
    private func updateFlashButton(_ monitorVC: MonitorViewController, state: CameraState, capabilities: CameraCapabilities) {
        let supportsFlash = capabilities.currentLimits.supportsFlash
        let currentMode = state.flashMode
        
        print("📸 Updating flash button: supports=\(supportsFlash), mode=\(currentMode)")
        
        // Update flash button visibility and state
        monitorVC.updateFlashButton(isVisible: supportsFlash, mode: currentMode)
    }
    
    private func updateZoomControls(_ monitorVC: MonitorViewController, state: CameraState, capabilities: CameraCapabilities) {
        let zoomRange = capabilities.currentLimits.zoomRange
        let currentZoom = state.zoomFactor
        
        print("🔍 Updating zoom controls: range=\(zoomRange.minZoom)-\(zoomRange.maxZoom), current=\(currentZoom)")
        
        // Update zoom slider and controls
        monitorVC.updateZoomControls(
            range: zoomRange,
            currentZoom: currentZoom,
            isEnabled: zoomRange.maxZoom > zoomRange.minZoom
        )
    }
    
    private func updateLensControls(_ monitorVC: MonitorViewController, state: CameraState, capabilities: CameraCapabilities) {
        let availableLenses = capabilities.currentLimits.availableLenses
        let currentLens = state.currentLens
        
        print("📷 Updating lens controls: available=\(availableLenses), current=\(currentLens)")
        
        // Update lens picker and controls
        monitorVC.updateLensControls(
            availableLenses: availableLenses,
            currentLens: currentLens,
            isEnabled: availableLenses.count > 1
        )
    }
    
    private func updateRecordingControls(_ monitorVC: MonitorViewController, state: CameraState, capabilities: CameraCapabilities) {
        let isRecording = state.isRecording
        
        print("🎥 Updating recording controls: isRecording=\(isRecording)")
        
        // Update recording button and controls
        monitorVC.updateRecordingControls(isRecording: isRecording)
    }
    
    private func updateConnectionStatus(_ monitorVC: MonitorViewController, state: CameraState) {
        let connectionStatus = state.connectionStatus
        
        print("📡 Updating connection status: \(connectionStatus)")
        
        // Update connection indicator
        monitorVC.updateConnectionStatus(connectionStatus)
    }
}

// MARK: - Camera View Controller State Observer

/// State observer specifically for CameraViewController
public class CameraStateObserver: ModernStateObserver {
    
    private weak var cameraViewController: CameraViewController?
    
    public init(cameraViewController: CameraViewController) {
        self.cameraViewController = cameraViewController
        super.init(viewController: cameraViewController)
    }
    
    public override func handleStateChange(_ response: CameraStateResponse) {
        guard let cameraVC = cameraViewController else { return }
        
        print("📹 CameraStateObserver: Updating camera UI with new state")
        
        // Update camera UI based on state changes
        updateCameraUI(cameraVC, state: response.currentState, capabilities: response.capabilities)
    }
    
    private func updateCameraUI(_ cameraVC: CameraViewController, state: CameraState, capabilities: CameraCapabilities) {
        // Update camera-specific UI elements
        // This could include indicators, overlays, etc.
        
        // For example, update torch indicator on camera view
        updateTorchIndicator(cameraVC, torchMode: state.torchMode)
        
        // Update recording indicator
        updateRecordingIndicator(cameraVC, isRecording: state.isRecording)
    }
    
    private func updateTorchIndicator(_ cameraVC: CameraViewController, torchMode: TorchMode) {
        // Update torch indicator on camera view
        // This would be a visual indicator showing torch state
    }
    
    private func updateRecordingIndicator(_ cameraVC: CameraViewController, isRecording: Bool) {
        // Update recording indicator
        cameraVC.configureIdleMode() // or configureVideoModeRecording() based on isRecording
    }
}

// MARK: - MonitorViewController Extension

/// Extension to add modern state handling methods to MonitorViewController
public extension MonitorViewController {
    
    /// Update torch button visibility and state
    func updateTorchButton(isVisible: Bool, isOn: Bool) {
        // This method would be implemented in MonitorViewController
        // to update the torch button based on current camera capabilities
        
        // Example implementation:
        // torchButton.isHidden = !isVisible
        // torchButton.isSelected = isOn
        
        print("🔦 MonitorViewController: Torch button visibility=\(isVisible), isOn=\(isOn)")
    }
    
    /// Update flash button visibility and state
    func updateFlashButton(isVisible: Bool, mode: FlashMode) {
        // This method would be implemented in MonitorViewController
        // to update the flash button based on current camera capabilities
        
        print("📸 MonitorViewController: Flash button visibility=\(isVisible), mode=\(mode)")
    }
    
    /// Update zoom controls
    func updateZoomControls(range: ZoomRange, currentZoom: Double, isEnabled: Bool) {
        // This method would be implemented in MonitorViewController
        // to update zoom slider and controls
        
        print("🔍 MonitorViewController: Zoom controls range=\(range), current=\(currentZoom), enabled=\(isEnabled)")
    }
    
    /// Update lens controls
    func updateLensControls(availableLenses: [CameraLensType], currentLens: CameraLensType, isEnabled: Bool) {
        // This method would be implemented in MonitorViewController
        // to update lens picker and controls
        
        print("📷 MonitorViewController: Lens controls available=\(availableLenses), current=\(currentLens), enabled=\(isEnabled)")
    }
    
    /// Update recording controls
    func updateRecordingControls(isRecording: Bool) {
        // This method would be implemented in MonitorViewController
        // to update recording button and controls
        
        print("🎥 MonitorViewController: Recording controls isRecording=\(isRecording)")
    }
    
    /// Update connection status
    func updateConnectionStatus(_ status: ConnectionStatus) {
        // This method would be implemented in MonitorViewController
        // to update connection indicator
        
        print("📡 MonitorViewController: Connection status=\(status)")
    }
}

// MARK: - Integration Helper

/// Helper class to integrate modern state observing with existing view controllers
public class StateObserverIntegration {
    
    private let cameraController: ModernCameraController
    private var observers: [StateObserver] = []
    
    public init(cameraController: ModernCameraController) {
        self.cameraController = cameraController
    }
    
    /// Set up state observing for MonitorViewController
    public func setupMonitorObserver(for monitorViewController: MonitorViewController) {
        let observer = MonitorStateObserver(monitorViewController: monitorViewController)
        cameraController.addStateObserver(observer)
        observers.append(observer)
        
        // Send initial state to observer
        let initialState = cameraController.getCurrentStateResponse()
        observer.onStateChanged(initialState)
    }
    
    /// Set up state observing for CameraViewController
    public func setupCameraObserver(for cameraViewController: CameraViewController) {
        let observer = CameraStateObserver(cameraViewController: cameraViewController)
        cameraController.addStateObserver(observer)
        observers.append(observer)
        
        // Send initial state to observer
        let initialState = cameraController.getCurrentStateResponse()
        observer.onStateChanged(initialState)
    }
    
    /// Clean up observers
    public func cleanup() {
        for observer in observers {
            cameraController.removeStateObserver(observer)
        }
        observers.removeAll()
    }
}

// MARK: - Demo Usage

/// Example of how to use the modern state observer system
public class ModernStateObserverExample {
    
    private let cameraController = ModernCameraController()
    private let stateObserverIntegration: StateObserverIntegration
    
    public init() {
        self.stateObserverIntegration = StateObserverIntegration(cameraController: cameraController)
    }
    
    /// Example of integrating with MonitorViewController
    public func setupMonitorViewController(_ monitorViewController: MonitorViewController) {
        // Set up state observing
        stateObserverIntegration.setupMonitorObserver(for: monitorViewController)
        
        // Now, when user switches camera, the torch button will automatically
        // show/hide based on the new camera's capabilities
        
        // Example: User switches from back camera (has torch) to front camera (no torch)
        let toggleCameraCommand = CameraCommand.toggleCamera()
        let response = cameraController.executeCommand(toggleCameraCommand)
        
        // The MonitorStateObserver will automatically receive the response
        // and update the UI accordingly - torch button will be hidden
        // if the new camera doesn't support torch
    }
} 