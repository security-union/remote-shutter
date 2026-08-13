//
//  RigQualityMenu.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import Foundation

/// The rig-wide quality menu: "the shot belongs to the rig", so video/photo
/// quality is the **intersection** of what every connected camera can do. A
/// pure value type — the picker UI and the fan-out both read it, and it is
/// unit-tested without any transport.
///
/// Built from each lane's current-camera `CameraInfo` (resolution/fps matrix,
/// HEIF, HDR). An option is offered only when *every* camera supports it; a
/// non-intersection option is still listed, greyed, naming the camera(s) that
/// block it.
struct RigQualityMenu: Equatable {

    /// One lane's contribution: a display name + the camera it is currently on.
    struct Lane: Equatable {
        let name: String
        let info: RemoteCmd.CameraInfo
    }

    /// The universal floor every iPhone camera supports — used when the
    /// intersection is empty and as the Automatic fallback.
    static let floor: (resolution: VideoResolution, frameRate: VideoFrameRate) = (.hd1080p, .fps30)

    private let lanes: [Lane]

    init(lanes: [Lane]) {
        self.lanes = lanes
    }

    // MARK: - Video

    /// Every (resolution, frame-rate) pair the whole rig supports. An empty rig
    /// has no cameras to agree on, so no options (Automatic then uses the floor).
    func videoOptions() -> [(resolution: VideoResolution, frameRate: VideoFrameRate)] {
        guard !lanes.isEmpty else { return [] }
        return allVideoPairs().filter { blockingLanes(resolution: $0.resolution, frameRate: $0.frameRate).isEmpty }
    }

    /// Cameras that cannot do this (resolution, fps) — empty means it is in the
    /// rig intersection. Used to grey and annotate a picker row.
    func blockingLanes(resolution: VideoResolution, frameRate: VideoFrameRate) -> [String] {
        lanes.filter { !laneSupports($0, resolution: resolution, frameRate: frameRate) }.map(\.name)
    }

    /// Automatic = the best pair every camera can do: highest resolution, then
    /// highest frame rate. Falls back to the 1080p30 floor when the rig shares
    /// nothing (heterogeneous cameras) or there are no lanes.
    func automaticVideo() -> (resolution: VideoResolution, frameRate: VideoFrameRate) {
        let best = videoOptions().max { a, b in
            if a.resolution.rawValue != b.resolution.rawValue {
                return a.resolution.rawValue < b.resolution.rawValue
            }
            return a.frameRate.rawValue < b.frameRate.rawValue
        }
        return best ?? Self.floor
    }

    // MARK: - Photo

    /// HEIF is a rig option only when every camera can encode it.
    func supportsHEIF() -> Bool {
        !lanes.isEmpty && lanes.allSatisfy { $0.info.supportsHEIF }
    }

    /// HDR is a rig option only when every camera can do it.
    func supportsHDR() -> Bool {
        !lanes.isEmpty && lanes.allSatisfy { $0.info.supportsHDR }
    }

    /// Cameras blocking HEIF / HDR, for greying the photo tiles.
    func lanesBlockingHEIF() -> [String] { lanes.filter { !$0.info.supportsHEIF }.map(\.name) }
    func lanesBlockingHDR() -> [String] { lanes.filter { !$0.info.supportsHDR }.map(\.name) }

    /// Automatic photo = HEIF if the whole rig can, else JPEG; HDR on if all can.
    func automaticPhoto() -> (format: PhotoFormat, hdr: HDRMode) {
        (supportsHEIF() ? .heif : .jpeg, supportsHDR() ? .on : .off)
    }

    // MARK: - Late joiner

    /// Whether a lane can honor a currently-applied rig video setting. A late
    /// joiner that can't is badged and offered a "re-match" (re-run Automatic)
    /// rather than silently changing the running rig.
    func laneCanMatch(_ lane: Lane,
                      resolution: VideoResolution,
                      frameRate: VideoFrameRate) -> Bool {
        laneSupports(lane, resolution: resolution, frameRate: frameRate)
    }

    // MARK: - Internals

    private func allVideoPairs() -> [(resolution: VideoResolution, frameRate: VideoFrameRate)] {
        var pairs: [(VideoResolution, VideoFrameRate)] = []
        for resolution in [VideoResolution.uhd4k, .hd1080p] {
            for frameRate in [VideoFrameRate.fps60, .fps30, .fps24] {
                pairs.append((resolution, frameRate))
            }
        }
        return pairs.map { (resolution: $0.0, frameRate: $0.1) }
    }

    private func laneSupports(_ lane: Lane,
                              resolution: VideoResolution,
                              frameRate: VideoFrameRate) -> Bool {
        let matrix = lane.info.getResolutionFrameRates()
        if let rates = matrix[resolution] { return rates.contains(frameRate) }
        // A camera that never advertised the matrix (older build) is treated as
        // the universal floor only.
        return resolution == .hd1080p && frameRate == .fps30
    }

    // MARK: - View-facing picker rows

    /// Every listed video option (highest first), each flagged enabled (in the
    /// rig intersection) or greyed with the cameras that block it. Manual
    /// selection of any enabled row is first-class.
    func videoPickerOptions() -> [RigVideoOption] {
        allVideoPairs().map { pair in
            let blockers = blockingLanes(resolution: pair.resolution, frameRate: pair.frameRate)
            return RigVideoOption(resolution: pair.resolution, frameRate: pair.frameRate,
                                  enabled: blockers.isEmpty, blockedBy: blockers)
        }
    }
}

/// One row of the rig video-quality picker.
struct RigVideoOption: Equatable, Identifiable {
    let resolution: VideoResolution
    let frameRate: VideoFrameRate
    let enabled: Bool
    let blockedBy: [String]

    var id: String { "\(resolution.rawValue):\(frameRate.rawValue)" }
    var label: String { "\(resolution.displayName)\(frameRate.displayName)" }
}

/// The rig's active video quality, or nil for Automatic (best-in-intersection).
/// Typed so the tray matches the running quality by value, not by comparing
/// rendered label strings.
struct RigVideoSelection: Equatable {
    let resolution: VideoResolution
    let frameRate: VideoFrameRate

    var label: String { "\(resolution.displayName)\(frameRate.displayName)" }
    func matches(_ option: RigVideoOption) -> Bool {
        resolution == option.resolution && frameRate == option.frameRate
    }
}

/// The rig-settings snapshot the director hands the tray UI.
struct RigSettingsSnapshot: Equatable {
    var timerSeconds: Int = 0
    var countdown: Int?
    var activeVideo: RigVideoSelection?
    var videoOptions: [RigVideoOption] = []
    var heifAvailable: Bool = false
    var hdrAvailable: Bool = false
    var heifBlockedBy: [String] = []
    var hdrBlockedBy: [String] = []
    var activePhotoFormat: PhotoFormat?
    var activeHDR: HDRMode?
}
