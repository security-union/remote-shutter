//
//  TorchTest.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 2024.
//  Copyright © 2024 Security Union LLC. All rights reserved.
//

import Foundation
import AVFoundation

/**
Simple test to verify torch functionality
*/
class TorchTest {
    
    static func testTorchCapabilities() {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInDualCamera,
            .builtInTelephotoCamera
        ]
        
        if #available(iOS 13.0, *) {
            deviceTypes.append(.builtInUltraWideCamera)
            deviceTypes.append(.builtInTripleCamera)
        }
        
        let videoDevices = AVCaptureDevice.DiscoverySession.init(
            deviceTypes: deviceTypes,
            mediaType: .video, position: .back).devices
        
        Log.debug("Torch Test: Found \(videoDevices.count) back camera devices")

        for device in videoDevices {
            Log.debug("Torch Test: \(device.localizedName)")
            Log.debug("   - Has Flash: \(device.hasFlash)")
            Log.debug("   - Has Torch: \(device.hasTorch)")
            Log.debug("   - Current Torch Mode: \(device.torchMode.rawValue)")
            Log.debug("   - Torch Level: \(device.torchLevel)")
        }
    }
}