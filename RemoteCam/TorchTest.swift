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
        
        print("🔍 Torch Test: Found \(videoDevices.count) back camera devices")
        
        for device in videoDevices {
            print("🔍 Torch Test: \(device.localizedName)")
            print("   - Has Flash: \(device.hasFlash)")
            print("   - Has Torch: \(device.hasTorch)")
            print("   - Current Torch Mode: \(device.torchMode.rawValue)")
            print("   - Torch Level: \(device.torchLevel)")
        }
    }
}