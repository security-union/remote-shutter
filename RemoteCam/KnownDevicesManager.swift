//
//  KnownDevicesManager.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 2025.
//  Copyright © 2025 Security Union. All rights reserved.
//

import Foundation

/// Manages a list of known (previously connected) device display names.
/// Stores up to 10 entries in MRU (most-recently-used) order via UserDefaults.
/// Uses display names because remote MCPeerID instances are different each session.
class KnownDevicesManager {

    static let shared = KnownDevicesManager()

    private let key = "knownDeviceDisplayNames"
    private let maxDevices = 10

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Adds a device to the known list. If already present, moves it to the front (MRU).
    func addDevice(displayName: String) {
        var devices = allDevices()
        devices.removeAll { $0 == displayName }
        devices.insert(displayName, at: 0)
        if devices.count > maxDevices {
            devices = Array(devices.prefix(maxDevices))
        }
        defaults.set(devices, forKey: key)
    }

    /// Returns true if the display name is in the known devices list.
    func isKnown(displayName: String) -> Bool {
        return allDevices().contains(displayName)
    }

    /// Returns all known device display names in MRU order.
    func allDevices() -> [String] {
        return defaults.stringArray(forKey: key) ?? []
    }

    /// Removes a specific device from the known list.
    func removeDevice(displayName: String) {
        var devices = allDevices()
        devices.removeAll { $0 == displayName }
        defaults.set(devices, forKey: key)
    }

    /// Clears all known devices.
    func clearAll() {
        defaults.removeObject(forKey: key)
    }
}
