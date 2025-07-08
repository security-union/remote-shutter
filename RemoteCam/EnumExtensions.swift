//
//  EnumExtensions.swift
//  Actors
//
//  Created by Dario Lencina on 11/3/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation
import AVFoundation
import Theater

// MARK: - Camera Lens Types
public enum CameraLensType: Int, CaseIterable {
    case wideAngle = 0
    case ultraWide = 1
    case telephoto = 2
    case dualCamera = 3
    
    public var displayName: String {
        switch self {
        case .wideAngle:
            return "Wide"
        case .ultraWide:
            return "Ultra Wide"
        case .telephoto:
            return "Telephoto"
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
