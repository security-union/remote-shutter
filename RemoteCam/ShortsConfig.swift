//
//  ShortsConfig.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 2025.
//  Copyright © 2025 Security Union. All rights reserved.
//

import Foundation

/// Configuration for a shorts recording session
public struct ShortsConfig: Codable, Equatable {
    /// Maximum total duration for the shorts video (15s, 30s, or 60s)
    public let maxDuration: TimeInterval
    
    /// Maximum number of clips allowed in a session
    public let maxClips: Int
    
    /// Minimum duration for a single clip
    public let minClipDuration: TimeInterval
    
    /// Maximum duration for a single clip (to prevent one clip taking all time)
    public let maxSingleClipDuration: TimeInterval
    
    /// Default configurations
    public static let fifteenSeconds = ShortsConfig(
        maxDuration: 15.0,
        maxClips: 10,
        minClipDuration: 0.5,
        maxSingleClipDuration: 8.0
    )
    
    public static let thirtySeconds = ShortsConfig(
        maxDuration: 30.0,
        maxClips: 15,
        minClipDuration: 0.5,
        maxSingleClipDuration: 15.0
    )
    
    public static let oneMinute = ShortsConfig(
        maxDuration: 60.0,
        maxClips: 20,
        minClipDuration: 0.5,
        maxSingleClipDuration: 30.0
    )
    
    /// All available configurations
    public static let availableConfigs = [fifteenSeconds, thirtySeconds, oneMinute]
    
    /// Display name for UI
    var displayName: String {
        if maxDuration == 15.0 {
            return "15s"
        } else if maxDuration == 30.0 {
            return "30s"
        } else if maxDuration == 60.0 {
            return "1min"
        } else {
            return "\(Int(maxDuration))s"
        }
    }
} 