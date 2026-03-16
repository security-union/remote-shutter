//
//  EnumExtensions.swift
//  Actors
//
//  Created by Dario Lencina on 11/3/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation
import AVFoundation

// MARK: - Camera Lens Types
public enum CameraLensType: Int, CaseIterable, Codable {
    case wideAngle = 0
    case ultraWide = 1
    case telephoto = 2
    case dualCamera = 3
    
    public var displayName: String {
        switch self {
        case .wideAngle:
            return "1"
        case .ultraWide:
            return "0.5"
        case .telephoto:
            return "2x"
        case .dualCamera:
            return "Dual"
        }
    }
    
    public var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .wideAngle:
            return .builtInWideAngleCamera
        case .ultraWide:
            if #available(iOS 13.0, *) {
                return .builtInUltraWideCamera
            } else {
                return .builtInWideAngleCamera
            }
        case .telephoto:
            return .builtInTelephotoCamera
        case .dualCamera:
            return .builtInDualCamera
        }
    }
}

// MARK: - Video Resolution
public enum VideoResolution: Int, CaseIterable, Codable {
    case unknown = 0
    case hd1080p = 1
    case uhd4k = 2

    public var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .hd1080p: return "1080p"
        case .uhd4k: return "4K"
        }
    }

    public var sessionPreset: AVCaptureSession.Preset {
        switch self {
        case .unknown, .hd1080p: return .hd1920x1080
        case .uhd4k: return .hd4K3840x2160
        }
    }

    public var dimensions: CMVideoDimensions {
        switch self {
        case .unknown, .hd1080p: return CMVideoDimensions(width: 1920, height: 1080)
        case .uhd4k: return CMVideoDimensions(width: 3840, height: 2160)
        }
    }

    /// All user-selectable cases (excludes .unknown)
    public static var selectableCases: [VideoResolution] {
        return [.hd1080p, .uhd4k]
    }
}

// MARK: - Video Frame Rate
public enum VideoFrameRate: Int, CaseIterable, Codable {
    case unknown = 0
    case fps24 = 1
    case fps30 = 2
    case fps60 = 3

    public var value: Int {
        switch self {
        case .unknown, .fps30: return 30
        case .fps24: return 24
        case .fps60: return 60
        }
    }

    public var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .fps24: return "24"
        case .fps30: return "30"
        case .fps60: return "60"
        }
    }

    /// All user-selectable cases (excludes .unknown)
    public static var selectableCases: [VideoFrameRate] {
        return [.fps24, .fps30, .fps60]
    }
}

// MARK: - Photo Format
public enum PhotoFormat: Int, CaseIterable, Codable {
    case unknown = 0
    case jpeg = 1
    case heif = 2

    public var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .jpeg: return "JPEG"
        case .heif: return "HEIF"
        }
    }

    /// All user-selectable cases (excludes .unknown)
    public static var selectableCases: [PhotoFormat] {
        return [.jpeg, .heif]
    }
}

// MARK: - HDR Mode
public enum HDRMode: Int, CaseIterable, Codable {
    case unknown = 0
    case off = 1
    case on = 2

    public var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .off: return "Off"
        case .on: return "On"
        }
    }

    /// All user-selectable cases (excludes .unknown)
    public static var selectableCases: [HDRMode] {
        return [.off, .on]
    }
}

extension AVCaptureDevice.Position {
    public func toggle() -> Try<AVCaptureDevice.Position> {
        switch self {
        case .back:
            return Success(.front)
        case .front:
            return Success(.back)
        default:
            return Failure(error: NSError(domain: "Unable to find camera position", code: 0, userInfo: nil))
        }
    }
}

extension AVCaptureDevice.FlashMode {
    public func next() -> AVCaptureDevice.FlashMode {
        switch self {
        case .off:
            return .on
        case .on:
            return .auto
        case .auto:
            return .off
        default:
            return .off
        }
    }
}
