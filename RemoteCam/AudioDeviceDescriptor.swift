//
//  AudioDeviceDescriptor.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union. All rights reserved.
//

import Foundation
import AVFoundation

/// One selectable audio input (microphone), as the session and UI see it.
/// Macs expose N inputs (built-in, USB, Continuity) identified by `uniqueID`;
/// mics have no front/back identity, so unlike `CameraDeviceDescriptor`
/// there is no position.
struct AudioDeviceDescriptor: Equatable {
    let uniqueID: String
    let localizedName: String
}

extension AudioDeviceDescriptor {
    init(device: AVCaptureDevice) {
        self.init(uniqueID: device.uniqueID, localizedName: device.localizedName)
    }

    /// Which device a selection request should land on when the requested one
    /// may have vanished (unplugged mid-request): exact ID match, else the
    /// first available, else nil.
    static func resolveSelection(
        requestedID: String,
        available: [AudioDeviceDescriptor]
    ) -> AudioDeviceDescriptor? {
        available.first { $0.uniqueID == requestedID } ?? available.first
    }
}
