//
//  ShortsSession.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 2025.
//  Copyright © 2025 Security Union. All rights reserved.
//

import Foundation

/// Manages a collection of clips and tracks session state for shorts recording
class ShortsSession: ObservableObject {
    /// Configuration for this session
    let config: ShortsConfig
    
    /// Array of clips in recording order
    @Published private(set) var clips: [ShortsClip] = []
    
    /// Session creation time
    let createdAt: Date
    
    /// Unique session identifier
    let sessionId: UUID
    
    /// Current state of the session
    @Published var state: SessionState = .idle
    
    /// States the session can be in
    enum SessionState {
        case idle           // Ready to record
        case recording      // Currently recording a clip
        case processing     // Processing/transferring a clip
        case previewing     // Playing preview
        case finalizing     // Assembling final video
        case completed      // Session complete
    }
    
    /// Computed properties
    var totalDuration: TimeInterval {
        clips.reduce(0) { $0 + $1.duration }
    }
    
    var remainingDuration: TimeInterval {
        max(0, config.maxDuration - totalDuration)
    }
    
    var canAddClip: Bool {
        clips.count < config.maxClips && 
        remainingDuration >= config.minClipDuration &&
        state == .idle
    }
    
    var canRecord: Bool {
        canAddClip && state == .idle
    }
    
    var isComplete: Bool {
        !clips.isEmpty && (remainingDuration < config.minClipDuration || clips.count >= config.maxClips)
    }
    
    var progressPercentage: Double {
        guard config.maxDuration > 0 else { return 0 }
        return min(1.0, totalDuration / config.maxDuration)
    }
    
    /// Initialize with configuration
    init(config: ShortsConfig) {
        self.config = config
        self.createdAt = Date()
        self.sessionId = UUID()
    }
    
    /// Add a clip to the session
    func addClip(_ clip: ShortsClip) throws {
        guard canAddClip else {
            throw ShortsSessionError.cannotAddClip
        }
        
        guard clip.duration >= config.minClipDuration else {
            throw ShortsSessionError.clipTooShort
        }
        
        guard totalDuration + clip.duration <= config.maxDuration else {
            throw ShortsSessionError.exceedsMaxDuration
        }
        
        var updatedClip = clip
        updatedClip = ShortsClip(
            id: clip.id,
            duration: clip.duration,
            videoURL: clip.videoURL,
            thumbnailImage: clip.thumbnailImage,
            recordedAt: clip.recordedAt,
            order: clips.count,
            fileSize: clip.fileSize
        )
        
        clips.append(updatedClip)
    }
    
    /// Remove a clip by ID
    func removeClip(withId clipId: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == clipId }) else { return }
        clips.remove(at: index)
        
        // Reorder remaining clips
        for i in index..<clips.count {
            clips[i] = ShortsClip(
                id: clips[i].id,
                duration: clips[i].duration,
                videoURL: clips[i].videoURL,
                thumbnailImage: clips[i].thumbnailImage,
                recordedAt: clips[i].recordedAt,
                order: i,
                fileSize: clips[i].fileSize
            )
        }
    }
    
    /// Clear all clips
    func clearAllClips() {
        clips.removeAll()
        state = .idle
    }
    
    /// Get maximum duration for next clip
    func maxDurationForNextClip() -> TimeInterval {
        let remaining = remainingDuration
        return min(remaining, config.maxSingleClipDuration)
    }
}

// MARK: - Errors
enum ShortsSessionError: LocalizedError {
    case cannotAddClip
    case clipTooShort
    case exceedsMaxDuration
    case sessionNotReady
    
    var errorDescription: String? {
        switch self {
        case .cannotAddClip:
            return "Cannot add more clips to this session"
        case .clipTooShort:
            return "Clip is too short"
        case .exceedsMaxDuration:
            return "Adding this clip would exceed maximum duration"
        case .sessionNotReady:
            return "Session is not ready for this operation"
        }
    }
} 