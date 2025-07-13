//
//  ModernCameraController.swift
//  RemoteShutter
//
//  Unified camera controller that handles all commands and maintains consistent state
//  Replaces the complex Actor-based system with a simpler, more maintainable approach
//

import Foundation
import AVFoundation
import UIKit

/// Unified camera controller that handles all commands and maintains state
public class ModernCameraController {
    
    // MARK: - Properties
    
    private var cameraViewController: CameraViewController?
    private var currentState: CameraState
    private var currentCapabilities: CameraCapabilities
    private var stateObservers: [StateObserver] = []
    
    // MARK: - Initialization
    
    public init(cameraViewController: CameraViewController? = nil) {
        self.cameraViewController = cameraViewController
        
        // Initialize with default state
        self.currentState = CameraState(
            currentCamera: .back,
            currentLens: .wideAngle,
            zoomFactor: 1.0,
            torchMode: .off,
            flashMode: .off,
            isRecording: false,
            connectionStatus: .disconnected
        )
        
        // Initialize with empty capabilities
        self.currentCapabilities = CameraCapabilities(
            frontCamera: nil,
            backCamera: nil,
            availableActions: [],
            currentLimits: CameraLimits(
                zoomRange: ZoomRange(minZoom: 1.0, maxZoom: 1.0),
                availableLenses: [],
                supportsFlash: false,
                supportsTorch: false
            )
        )
        
        // Refresh capabilities if camera is available
        if let cameraVC = cameraViewController {
            refreshCapabilities(from: cameraVC)
        }
    }
    
    // MARK: - State Management
    
    /// Update the camera view controller reference
    public func setCameraViewController(_ cameraViewController: CameraViewController) {
        self.cameraViewController = cameraViewController
        refreshCapabilities(from: cameraViewController)
    }
    
    /// Refresh capabilities from the camera view controller
    private func refreshCapabilities(from cameraVC: CameraViewController) {
        // Gather all camera capabilities
        cameraVC.gatherAllCameraCapabilities()
        
        // Get current device state
        guard let currentDevice = cameraVC.videoDeviceInput?.device else {
            print("❌ ModernCameraController: No camera device available")
            return
        }
        
        // Update current state
        currentState = CameraState(
            currentCamera: CameraPosition(from: currentDevice.position),
            currentLens: cameraVC.getCurrentLensType(),
            zoomFactor: Double(cameraVC.getCurrentZoomFactor()),
            torchMode: TorchMode(from: cameraVC.getCurrentTorchMode()),
            flashMode: FlashMode(from: cameraVC.cameraSettings.flashMode),
            isRecording: cameraVC.isRecording,
            connectionStatus: .connected
        )
        
        // Update capabilities
        if let legacyCapabilities = cameraVC.gatherCurrentCameraCapabilities() {
            let currentCameraInfo = legacyCapabilities.getCurrentCameraInfo()
            currentCapabilities = CameraCapabilities(
                frontCamera: legacyCapabilities.frontCamera,
                backCamera: legacyCapabilities.backCamera,
                availableActions: CommandAction.allCases,
                currentLimits: CameraLimits(
                    zoomRange: currentCameraInfo?.getZoomCapabilities()[currentState.currentLens] ?? ZoomRange(minZoom: 1.0, maxZoom: 1.0),
                    availableLenses: currentCameraInfo?.availableLenses ?? [],
                    supportsFlash: currentCameraInfo?.hasFlash ?? false,
                    supportsTorch: currentCameraInfo?.hasTorch ?? false
                )
            )
        }
        
        print("✅ ModernCameraController: Capabilities refreshed")
        print("   - Current camera: \(currentState.currentCamera)")
        print("   - Available lenses: \(currentCapabilities.currentLimits.availableLenses)")
        print("   - Supports torch: \(currentCapabilities.currentLimits.supportsTorch)")
        print("   - Supports flash: \(currentCapabilities.currentLimits.supportsFlash)")
    }
    
    // MARK: - Command Execution
    
    /// Execute a camera command and return the updated state
    public func executeCommand(_ command: CameraCommand) -> CameraStateResponse {
        print("🎯 ModernCameraController: Executing command \(command.action)")
        
        guard let cameraVC = cameraViewController else {
            return CameraStateResponse(
                commandId: command.id,
                success: false,
                error: "Camera controller not available",
                currentState: currentState,
                capabilities: currentCapabilities
            )
        }
        
        var success = true
        var errorMessage: String?
        
        // Execute the command
        switch command.action {
        case .takePicture:
            success = executeTakePicture(command, cameraVC: cameraVC)
            
        case .toggleTorch:
            (success, errorMessage) = executeToggleTorch(cameraVC: cameraVC)
            
        case .setTorchMode:
            (success, errorMessage) = executeSetTorchMode(command, cameraVC: cameraVC)
            
        case .toggleFlash:
            (success, errorMessage) = executeToggleFlash(cameraVC: cameraVC)
            
        case .setFlashMode:
            (success, errorMessage) = executeSetFlashMode(command, cameraVC: cameraVC)
            
        case .toggleCamera:
            (success, errorMessage) = executeToggleCamera(cameraVC: cameraVC)
            
        case .setZoom:
            (success, errorMessage) = executeSetZoom(command, cameraVC: cameraVC)
            
        case .switchLens:
            (success, errorMessage) = executeSwitchLens(command, cameraVC: cameraVC)
            
        case .startRecording:
            success = executeStartRecording(cameraVC: cameraVC)
            
        case .stopRecording:
            success = executeStopRecording(command, cameraVC: cameraVC)
            
        case .requestCapabilities:
            success = true // Always successful
        }
        
        // Refresh state and capabilities after command execution
        refreshCapabilities(from: cameraVC)
        
        // Create response
        let response = CameraStateResponse(
            commandId: command.id,
            success: success,
            error: errorMessage,
            currentState: currentState,
            capabilities: currentCapabilities
        )
        
        // Notify observers
        notifyStateObservers(response)
        
        return response
    }
    
    // MARK: - Command Implementations
    
    private func executeTakePicture(_ command: CameraCommand, cameraVC: CameraViewController) -> Bool {
        let sendToRemote = command.parameters?["sendToRemote"]?.boolValue ?? true
        cameraVC.takePicture(sendToRemote)
        return true
    }
    
    private func executeToggleTorch(cameraVC: CameraViewController) -> (Bool, String?) {
        let result = cameraVC.toggleTorch()
        switch result {
        case .success(let mode):
            currentState = currentState.with(torchMode: TorchMode(from: mode))
            return (true, nil)
        case .failure(let error):
            return (false, error.localizedDescription)
        }
    }
    
    private func executeSetTorchMode(_ command: CameraCommand, cameraVC: CameraViewController) -> (Bool, String?) {
        guard let modeString = command.parameters?["mode"]?.stringValue,
              let mode = TorchMode(rawValue: modeString) else {
            return (false, "Invalid torch mode parameter")
        }
        
        let result = cameraVC.setTorchMode(mode: mode.avMode)
        switch result {
        case .success(let avMode):
            currentState = currentState.with(torchMode: TorchMode(from: avMode))
            return (true, nil)
        case .failure(let error):
            return (false, error.localizedDescription)
        }
    }
    
    private func executeToggleFlash(cameraVC: CameraViewController) -> (Bool, String?) {
        let result = cameraVC.toggleFlash()
        switch result {
        case .success(let mode):
            currentState = currentState.with(flashMode: FlashMode(from: mode))
            return (true, nil)
        case .failure(let error):
            return (false, error.localizedDescription)
        }
    }
    
    private func executeSetFlashMode(_ command: CameraCommand, cameraVC: CameraViewController) -> (Bool, String?) {
        guard let modeString = command.parameters?["mode"]?.stringValue,
              let mode = FlashMode(rawValue: modeString) else {
            return (false, "Invalid flash mode parameter")
        }
        
        guard let device = cameraVC.videoDeviceInput?.device else {
            return (false, "No camera device available")
        }
        
        let result = cameraVC.setFlashMode(mode: mode.avMode, device: device)
        switch result {
        case .success(let avMode):
            currentState = currentState.with(flashMode: FlashMode(from: avMode))
            return (true, nil)
        case .failure(let error):
            return (false, error.localizedDescription)
        }
    }
    
    private func executeToggleCamera(cameraVC: CameraViewController) -> (Bool, String?) {
        let result = cameraVC.toggleCamera()
        switch result {
        case .success(let (flashMode, position)):
            // Update state with new camera position
            currentState = currentState.with(
                currentCamera: CameraPosition(from: position),
                flashMode: flashMode != nil ? FlashMode(from: flashMode!) : .off
            )
            return (true, nil)
        case .failure(let error):
            return (false, error.localizedDescription)
        }
    }
    
    private func executeSetZoom(_ command: CameraCommand, cameraVC: CameraViewController) -> (Bool, String?) {
        guard let zoomFactor = command.parameters?["zoomFactor"]?.doubleValue else {
            return (false, "Invalid zoom factor parameter")
        }
        
        let result = cameraVC.setZoom(zoomFactor: CGFloat(zoomFactor))
        switch result {
        case .success(let (newZoom, lens, _)):
            currentState = currentState.with(
                zoomFactor: Double(newZoom),
                currentLens: lens
            )
            return (true, nil)
        case .failure(let error):
            return (false, error.localizedDescription)
        }
    }
    
    private func executeSwitchLens(_ command: CameraCommand, cameraVC: CameraViewController) -> (Bool, String?) {
        guard let lensRawValue = command.parameters?["lensType"]?.intValue,
              let lensType = CameraLensType(rawValue: lensRawValue) else {
            return (false, "Invalid lens type parameter")
        }
        
        let result = cameraVC.switchLens(to: lensType)
        switch result {
        case .success(let (newLens, _, newZoom, _)):
            currentState = currentState.with(
                currentLens: newLens,
                zoomFactor: Double(newZoom)
            )
            return (true, nil)
        case .failure(let error):
            return (false, error.localizedDescription)
        }
    }
    
    private func executeStartRecording(cameraVC: CameraViewController) -> Bool {
        cameraVC.startRecordingVideo()
        currentState = currentState.with(isRecording: true)
        return true
    }
    
    private func executeStopRecording(_ command: CameraCommand, cameraVC: CameraViewController) -> Bool {
        let sendToRemote = command.parameters?["sendToRemote"]?.boolValue ?? true
        cameraVC.stopRecordingVideo(sendToRemote)
        currentState = currentState.with(isRecording: false)
        return true
    }
    
    // MARK: - State Observers
    
    /// Add a state observer
    public func addStateObserver(_ observer: StateObserver) {
        stateObservers.append(observer)
    }
    
    /// Remove a state observer
    public func removeStateObserver(_ observer: StateObserver) {
        stateObservers.removeAll { $0 === observer }
    }
    
    /// Notify all state observers of a state change
    private func notifyStateObservers(_ response: CameraStateResponse) {
        for observer in stateObservers {
            observer.onStateChanged(response)
        }
    }
    
    // MARK: - Public State Access
    
    /// Get the current camera state
    public func getCurrentState() -> CameraState {
        return currentState
    }
    
    /// Get the current camera capabilities
    public func getCurrentCapabilities() -> CameraCapabilities {
        return currentCapabilities
    }
    
    /// Get a complete state response
    public func getCurrentStateResponse() -> CameraStateResponse {
        return CameraStateResponse(
            commandId: UUID(),
            success: true,
            currentState: currentState,
            capabilities: currentCapabilities
        )
    }
}

// MARK: - State Observer Protocol

/// Protocol for observing camera state changes
public protocol StateObserver: AnyObject {
    func onStateChanged(_ response: CameraStateResponse)
}

// MARK: - Helper Extensions

private extension CodableValue {
    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }
    
    var intValue: Int? {
        if case .int(let value) = self {
            return value
        }
        return nil
    }
    
    var doubleValue: Double? {
        if case .double(let value) = self {
            return value
        }
        return nil
    }
    
    var boolValue: Bool? {
        if case .bool(let value) = self {
            return value
        }
        return nil
    }
}

private extension CameraState {
    func with(
        currentCamera: CameraPosition? = nil,
        currentLens: CameraLensType? = nil,
        zoomFactor: Double? = nil,
        torchMode: TorchMode? = nil,
        flashMode: FlashMode? = nil,
        isRecording: Bool? = nil,
        connectionStatus: ConnectionStatus? = nil
    ) -> CameraState {
        return CameraState(
            currentCamera: currentCamera ?? self.currentCamera,
            currentLens: currentLens ?? self.currentLens,
            zoomFactor: zoomFactor ?? self.zoomFactor,
            torchMode: torchMode ?? self.torchMode,
            flashMode: flashMode ?? self.flashMode,
            isRecording: isRecording ?? self.isRecording,
            connectionStatus: connectionStatus ?? self.connectionStatus
        )
    }
} 