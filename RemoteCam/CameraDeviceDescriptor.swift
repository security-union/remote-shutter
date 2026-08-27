//
//  CameraDeviceDescriptor.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union. All rights reserved.
//

import Foundation
import AVFoundation

/// One selectable physical camera, as the session and UI see it. Macs expose
/// N cameras (built-in, Continuity, Desk View, external) rather than a
/// front/back pair, so devices are identified by `uniqueID`; `position` is
/// `.unspecified` when the hardware has no front/back identity.
struct CameraDeviceDescriptor: Equatable {
    let uniqueID: String
    let localizedName: String
    let position: AVCaptureDevice.Position
    let deviceType: AVCaptureDevice.DeviceType
    /// Connected but delivering no frames (a Mac's built-in camera in
    /// clamshell mode). Shown grayed out in pickers; excluded from selection.
    var isSuspended: Bool = false
}

extension CameraDeviceDescriptor {
    init(device: AVCaptureDevice) {
        self.init(
            uniqueID: device.uniqueID,
            localizedName: device.localizedName,
            position: device.position,
            deviceType: device.deviceType,
            isSuspended: device.isSuspended)
    }

    /// Which device the front/back flip lands on. iOS flips position
    /// (`flipPosition: true`); a Mac has no front/back, so the flip cycles
    /// through the devices in list order. Suspended devices are skipped —
    /// they are connected but deliver no frames.
    static func nextToggleSelection(
        currentID: String?,
        available: [CameraDeviceDescriptor],
        flipPosition: Bool
    ) -> CameraDeviceDescriptor? {
        let eligible = available.filter { !$0.isSuspended }
        guard !eligible.isEmpty else { return nil }
        if flipPosition {
            guard let current = available.first(where: { $0.uniqueID == currentID }) else {
                return nil
            }
            let target: AVCaptureDevice.Position = current.position == .back ? .front : .back
            return eligible.first { $0.position == target }
        }
        guard let currentID,
              let index = eligible.firstIndex(where: { $0.uniqueID == currentID }) else {
            return eligible.first
        }
        return eligible[(index + 1) % eligible.count]
    }

    /// Which device a selection request should land on when the requested one
    /// may have vanished (unplugged mid-request): exact ID match, else a
    /// device at the same position, else the first available, else nil.
    /// Suspended devices are never eligible — a suspended camera is
    /// connected but delivers no frames.
    static func resolveSelection(
        requestedID: String,
        available: [CameraDeviceDescriptor],
        fallbackPosition: AVCaptureDevice.Position
    ) -> CameraDeviceDescriptor? {
        let eligible = available.filter { !$0.isSuspended }
        if let exact = eligible.first(where: { $0.uniqueID == requestedID }) {
            return exact
        }
        if let samePosition = eligible.first(where: { $0.position == fallbackPosition }) {
            return samePosition
        }
        return eligible.first
    }
}

/// What a completed device selection reports back to the session and UI: the
/// new device plus the capture facts the monitor needs to refresh its controls.
struct CameraSelectionResult {
    let device: CameraDeviceDescriptor
    /// nil when the device has no flash (every Mac camera).
    let flashMode: AVCaptureDevice.FlashMode?
    let availableLensTypes: [CameraLensType]
    /// Zoom truth lives in the `ControlState` snapshot the swap pushes;
    /// this result only identifies the device the swap landed on.
    let currentZoom: CGFloat
}
