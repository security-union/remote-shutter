//
//  PortraitPreviewBlur.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union. All rights reserved.
//

import Foundation
import AVFoundation
import CoreVideo

/// Blurs a streamed preview frame from live depth at the rig's aperture, so
/// the director frames Portrait shots with the effect. Today it returns the
/// frame unchanged.
final class PortraitPreviewBlur {
    func blurred(_ pixelBuffer: CVPixelBuffer, disparity: AVDepthData?, aperture: Float) -> CVPixelBuffer {
        pixelBuffer
    }
}
