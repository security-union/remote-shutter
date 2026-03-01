//
//  FeatureFlags.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 2025.
//  Copyright © 2025 Security Union. All rights reserved.
//

import Foundation

// MARK: - Global Feature Flags
/// Centralized feature flag management for Remote Shutter app
/// All feature flags should be defined here for easy management and consistency
struct FeatureFlags {
    
    // MARK: - UI Features
    
    /// Enable Shorts mode (short-form video recording)
    /// Set to true when Shorts mode implementation is complete
    static let ENABLE_SHORTS_MODE = false
    
    // MARK: - Connectivity Features

    /// Enable auto-reconnect to previously paired devices.
    /// When enabled, the app auto-accepts invitations from known devices
    /// and auto-invites them when discovered during scanning.
    static let ENABLE_AUTO_RECONNECT = true

    // MARK: - Future Feature Flags
    // Add new feature flags here as needed
    // Example:
    // static let ENABLE_AI_FILTERS = false
    // static let ENABLE_CLOUD_SYNC = false
} 