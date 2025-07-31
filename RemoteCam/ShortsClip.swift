//
//  ShortsClip.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 2025.
//  Copyright © 2025 Security Union. All rights reserved.
//

import Foundation
import UIKit

/// Represents an individual video clip in a shorts session
struct ShortsClip: Codable, Identifiable, Equatable {
    /// Unique identifier for the clip
    let id: UUID
    
    /// Duration of the clip in seconds
    let duration: TimeInterval
    
    /// Local URL where the clip is stored
    /// On Camera: temporary file location
    /// On Remote: permanent storage location
    let videoURL: URL
    
    /// Thumbnail image data (optional, for UI display)
    /// Stored as Data to make it Codable
    let thumbnailImageData: Data?
    
    /// When the clip was recorded
    let recordedAt: Date
    
    /// Order/position in the timeline (0-based)
    let order: Int
    
    /// File size in bytes (for transfer progress tracking)
    let fileSize: Int64
    
    /// Creates a new clip
    init(id: UUID = UUID(),
         duration: TimeInterval,
         videoURL: URL,
         thumbnailImage: UIImage? = nil,
         recordedAt: Date = Date(),
         order: Int,
         fileSize: Int64) {
        self.id = id
        self.duration = duration
        self.videoURL = videoURL
        self.thumbnailImageData = thumbnailImage?.jpegData(compressionQuality: 0.7)
        self.recordedAt = recordedAt
        self.order = order
        self.fileSize = fileSize
    }
    
    /// Convenience property to get thumbnail as UIImage
    var thumbnailImage: UIImage? {
        guard let data = thumbnailImageData else { return nil }
        return UIImage(data: data)
    }
    
    /// Display duration as formatted string
    var durationString: String {
        if duration < 10 {
            return String(format: "%.1fs", duration)
        } else {
            return String(format: "%.0fs", duration)
        }
    }
}

// MARK: - Equatable (compare by ID only for performance)
extension ShortsClip {
    static func == (lhs: ShortsClip, rhs: ShortsClip) -> Bool {
        return lhs.id == rhs.id
    }
} 