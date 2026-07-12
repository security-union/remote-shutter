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

    /// Enable video/photo quality controls overlay on monitor
    static let ENABLE_QUALITY_CONTROLS = true
    
    /// Enable Apple Watch companion app as standalone remote control
    static let ENABLE_WATCH_APP = true

    /// Show the local camera-device picker on the camera screen. On for Mac
    /// Catalyst only (a Mac has N cameras — built-in, Continuity, USB);
    /// iPhone keeps its flip button.
    #if targetEnvironment(macCatalyst)
    static let ENABLE_LOCAL_CAMERA_PICKER = true
    #else
    static let ENABLE_LOCAL_CAMERA_PICKER = false
    #endif

    // MARK: - Future Feature Flags
    // Add new feature flags here as needed
    // Example:
    // static let ENABLE_AI_FILTERS = false
    // static let ENABLE_CLOUD_SYNC = false
} 