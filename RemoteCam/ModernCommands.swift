//
//  ModernCommands.swift
//  RemoteShutter
//
//  Modern command system using Codable for P2P communication
//  Replaces NSCoding-based system for better performance and maintainability
//

import Foundation
import AVFoundation

// MARK: - Command Envelope

/// Unified command structure for all camera operations
public struct CameraCommand: Codable {
    public let id: UUID
    public let timestamp: Date
    public let action: CommandAction
    public let parameters: [String: CodableValue]?
    
    public init(action: CommandAction, parameters: [String: CodableValue]? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.action = action
        self.parameters = parameters
    }
}

/// All available camera actions
public enum CommandAction: String, Codable, CaseIterable {
    case takePicture = "takePicture"
    case toggleTorch = "toggleTorch"
    case toggleFlash = "toggleFlash"
    case toggleCamera = "toggleCamera"
    case setZoom = "setZoom"
    case switchLens = "switchLens"
    case startRecording = "startRecording"
    case stopRecording = "stopRecording"
    case requestCapabilities = "requestCapabilities"
    case setTorchMode = "setTorchMode"
    case setFlashMode = "setFlashMode"
}

/// Type-safe parameter values for commands
public enum CodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case data(Data)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Data.self) {
            self = .data(value)
        } else {
            throw DecodingError.typeMismatch(CodableValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Cannot decode CodableValue"))
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .data(let value):
            try container.encode(value)
        }
    }
}

// MARK: - Command Extensions for Type Safety

public extension CameraCommand {
    /// Create a take picture command
    static func takePicture(sendToRemote: Bool = true) -> CameraCommand {
        return CameraCommand(action: .takePicture, parameters: [
            "sendToRemote": .bool(sendToRemote)
        ])
    }
    
    /// Create a toggle torch command
    static func toggleTorch() -> CameraCommand {
        return CameraCommand(action: .toggleTorch)
    }
    
    /// Create a set torch mode command
    static func setTorchMode(_ mode: TorchMode) -> CameraCommand {
        return CameraCommand(action: .setTorchMode, parameters: [
            "mode": .string(mode.rawValue)
        ])
    }
    
    /// Create a toggle flash command
    static func toggleFlash() -> CameraCommand {
        return CameraCommand(action: .toggleFlash)
    }
    
    /// Create a set flash mode command
    static func setFlashMode(_ mode: FlashMode) -> CameraCommand {
        return CameraCommand(action: .setFlashMode, parameters: [
            "mode": .string(mode.rawValue)
        ])
    }
    
    /// Create a toggle camera command
    static func toggleCamera() -> CameraCommand {
        return CameraCommand(action: .toggleCamera)
    }
    
    /// Create a set zoom command
    static func setZoom(_ factor: Double) -> CameraCommand {
        return CameraCommand(action: .setZoom, parameters: [
            "zoomFactor": .double(factor)
        ])
    }
    
    /// Create a switch lens command
    static func switchLens(_ lensType: CameraLensType) -> CameraCommand {
        return CameraCommand(action: .switchLens, parameters: [
            "lensType": .int(lensType.rawValue)
        ])
    }
    
    /// Create a start recording command
    static func startRecording() -> CameraCommand {
        return CameraCommand(action: .startRecording)
    }
    
    /// Create a stop recording command
    static func stopRecording(sendToRemote: Bool = true) -> CameraCommand {
        return CameraCommand(action: .stopRecording, parameters: [
            "sendToRemote": .bool(sendToRemote)
        ])
    }
    
    /// Create a request capabilities command
    static func requestCapabilities() -> CameraCommand {
        return CameraCommand(action: .requestCapabilities)
    }
}

// MARK: - Response Structure

/// Unified response structure containing complete camera state
public struct CameraStateResponse: Codable {
    public let commandId: UUID
    public let timestamp: Date
    public let success: Bool
    public let error: String?
    public let currentState: CameraState
    public let capabilities: CameraCapabilities
    
    public init(commandId: UUID, success: Bool, error: String? = nil, currentState: CameraState, capabilities: CameraCapabilities) {
        self.commandId = commandId
        self.timestamp = Date()
        self.success = success
        self.error = error
        self.currentState = currentState
        self.capabilities = capabilities
    }
}

// MARK: - State Structures

/// Complete current camera state
public struct CameraState: Codable {
    public let currentCamera: CameraPosition
    public let currentLens: CameraLensType
    public let zoomFactor: Double
    public let torchMode: TorchMode
    public let flashMode: FlashMode
    public let isRecording: Bool
    public let connectionStatus: ConnectionStatus
    
    public init(currentCamera: CameraPosition, currentLens: CameraLensType, zoomFactor: Double, torchMode: TorchMode, flashMode: FlashMode, isRecording: Bool, connectionStatus: ConnectionStatus) {
        self.currentCamera = currentCamera
        self.currentLens = currentLens
        self.zoomFactor = zoomFactor
        self.torchMode = torchMode
        self.flashMode = flashMode
        self.isRecording = isRecording
        self.connectionStatus = connectionStatus
    }
}

/// Complete camera capabilities for both front and back cameras
public struct CameraCapabilities: Codable {
    public let frontCamera: CameraInfo?
    public let backCamera: CameraInfo?
    public let availableActions: [CommandAction]
    public let currentLimits: CameraLimits
    
    public init(frontCamera: CameraInfo?, backCamera: CameraInfo?, availableActions: [CommandAction], currentLimits: CameraLimits) {
        self.frontCamera = frontCamera
        self.backCamera = backCamera
        self.availableActions = availableActions
        self.currentLimits = currentLimits
    }
    
    /// Get capabilities for the current camera
    public func getCurrentCameraInfo(position: CameraPosition) -> CameraInfo? {
        switch position {
        case .front:
            return frontCamera
        case .back:
            return backCamera
        }
    }
}

/// Current camera limitations based on active camera
public struct CameraLimits: Codable {
    public let zoomRange: ZoomRange
    public let availableLenses: [CameraLensType]
    public let supportsFlash: Bool
    public let supportsTorch: Bool
    
    public init(zoomRange: ZoomRange, availableLenses: [CameraLensType], supportsFlash: Bool, supportsTorch: Bool) {
        self.zoomRange = zoomRange
        self.availableLenses = availableLenses
        self.supportsFlash = supportsFlash
        self.supportsTorch = supportsTorch
    }
}

// MARK: - Enum Definitions

/// Camera position enum
public enum CameraPosition: String, Codable {
    case front = "front"
    case back = "back"
    
    public init(from avPosition: AVCaptureDevice.Position) {
        switch avPosition {
        case .front:
            self = .front
        case .back:
            self = .back
        default:
            self = .back
        }
    }
    
    public var avPosition: AVCaptureDevice.Position {
        switch self {
        case .front:
            return .front
        case .back:
            return .back
        }
    }
}

/// Torch mode enum
public enum TorchMode: String, Codable {
    case off = "off"
    case on = "on"
    case auto = "auto"
    
    public init(from avMode: AVCaptureDevice.TorchMode) {
        switch avMode {
        case .off:
            self = .off
        case .on:
            self = .on
        case .auto:
            self = .auto
        @unknown default:
            self = .off
        }
    }
    
    public var avMode: AVCaptureDevice.TorchMode {
        switch self {
        case .off:
            return .off
        case .on:
            return .on
        case .auto:
            return .auto
        }
    }
}

/// Flash mode enum
public enum FlashMode: String, Codable {
    case off = "off"
    case on = "on"
    case auto = "auto"
    
    public init(from avMode: AVCaptureDevice.FlashMode) {
        switch avMode {
        case .off:
            self = .off
        case .on:
            self = .on
        case .auto:
            self = .auto
        @unknown default:
            self = .off
        }
    }
    
    public var avMode: AVCaptureDevice.FlashMode {
        switch self {
        case .off:
            return .off
        case .on:
            return .on
        case .auto:
            return .auto
        }
    }
}

/// Connection status enum
public enum ConnectionStatus: String, Codable {
    case disconnected = "disconnected"
    case connecting = "connecting"
    case connected = "connected"
    case scanning = "scanning"
    case error = "error"
}

// MARK: - Legacy Compatibility

/// Extension to convert from legacy NSCoding-based responses
public extension CameraStateResponse {
    init(from legacyResponse: RemoteCmd.CameraCapabilitiesResp) {
        self.commandId = UUID() // Generate new ID for legacy responses
        self.timestamp = Date()
        self.success = legacyResponse.error == nil
        self.error = legacyResponse.error?.localizedDescription
        
        // Convert current state
        self.currentState = CameraState(
            currentCamera: CameraPosition(from: legacyResponse.currentCamera),
            currentLens: legacyResponse.currentLens,
            zoomFactor: Double(legacyResponse.currentZoom),
            torchMode: .off, // Would need to be passed separately in legacy system
            flashMode: .off, // Would need to be passed separately in legacy system
            isRecording: false, // Would need to be passed separately in legacy system
            connectionStatus: .connected
        )
        
        // Convert capabilities
        let currentCameraInfo = legacyResponse.getCurrentCameraInfo()
        self.capabilities = CameraCapabilities(
            frontCamera: legacyResponse.frontCamera,
            backCamera: legacyResponse.backCamera,
            availableActions: CommandAction.allCases,
            currentLimits: CameraLimits(
                zoomRange: currentCameraInfo?.getZoomCapabilities()[legacyResponse.currentLens] ?? ZoomRange(minZoom: 1.0, maxZoom: 1.0),
                availableLenses: currentCameraInfo?.availableLenses ?? [],
                supportsFlash: currentCameraInfo?.hasFlash ?? false,
                supportsTorch: currentCameraInfo?.hasTorch ?? false
            )
        )
    }
} 