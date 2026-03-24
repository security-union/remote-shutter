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
    
    // MARK: - Multi-Camera

    /// Enable multi-camera support (1 monitor : N cameras)
    /// Set to true when multi-camera implementation is complete
    static let ENABLE_MULTI_CAMERA = true
} 
