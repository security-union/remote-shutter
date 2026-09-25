//
//  CinematicPolicy.swift
//  RemoteShutter
//
//  Cinematic video (iOS 26+) as pure values and the rules both sides share.
//  The camera turns a `CinematicIntent` into AVFoundation calls; the director
//  reads a `CinematicState` and never offers what these rules refuse. No
//  AVFoundation types cross this boundary, so every rule is table-testable.
//  See Docs/cinematic.md.
//

import CoreGraphics
import Foundation

/// Which file a Cinematic take produces. One or the other, never both.
public enum CinematicOutput: Equatable, Sendable {
    /// The blur is rendered into the video by our asset writer: every player
    /// shows it; multicam sync, aspect crops and the preview are unchanged.
    case baked
    /// The movie file output's clean video + disparity + Cinematic metadata:
    /// re-focusable in Photos, but the blur exists only in Apple's renderers.
    /// 16:9 only (the metadata describes the full frame).
    case editable
}

/// What the director asked for. `aperture` 0 = keep the current value (the
/// format default the first time); the camera clamps into its range.
public struct CinematicIntent: Equatable, Sendable {
    public var enabled: Bool
    public var aperture: Float
    public var output: CinematicOutput

    public init(enabled: Bool, aperture: Float = 0, output: CinematicOutput = .baked) {
        self.enabled = enabled
        self.aperture = aperture
        self.output = output
    }
}

/// The camera's Cinematic truth, carried in every state reply. Present =
/// this camera can do Cinematic; absent = no tile, no `SetCinematic`.
public struct CinematicState: Equatable, Sendable {
    /// The effect is on right now (false in photo mode even if asked for).
    public var enabled: Bool
    public var output: CinematicOutput
    public var aperture: Float
    public var minAperture: Float
    public var maxAperture: Float
    public var defaultAperture: Float
    /// The resolution/fps pairs Cinematic formats allow.
    public var qualities: [VideoResolution: [VideoFrameRate]]

    public init(enabled: Bool, output: CinematicOutput, aperture: Float,
                minAperture: Float, maxAperture: Float, defaultAperture: Float,
                qualities: [VideoResolution: [VideoFrameRate]]) {
        self.enabled = enabled
        self.output = output
        self.aperture = aperture
        self.minAperture = minAperture
        self.maxAperture = maxAperture
        self.defaultAperture = defaultAperture
        self.qualities = qualities
    }
}

/// Strong: stay on the subject until it leaves the frame. Weak: the camera
/// may move to a more prominent subject.
public enum CinematicFocusStrength: Equatable, Sendable {
    case weak
    case strong
}

/// A director focus request. Points are normalized (0..1) in the upright
/// display image, origin top-left — the `FocusAtPoint` space.
public enum CinematicFocus: Equatable, Sendable {
    case subject(id: Int, strength: CinematicFocusStrength)
    case trackPoint(x: Float, y: Float, strength: CinematicFocusStrength)
    case fixedPoint(x: Float, y: Float)
}

public enum CinematicSubjectKind: Equatable, Sendable {
    case face, humanBody, catHead, catBody, dogHead, dogBody, salientObject
}

/// One detected subject, boxed in upright display space.
public struct CinematicSubject: Equatable, Sendable {
    public var id: Int
    /// A face and a body of one person share it.
    public var groupID: Int
    public var kind: CinematicSubjectKind
    public var rect: CGRect
    /// nil = not the focus.
    public var focus: CinematicFocusStrength?
    public var isFixedFocus: Bool

    public init(id: Int, groupID: Int, kind: CinematicSubjectKind, rect: CGRect,
                focus: CinematicFocusStrength?, isFixedFocus: Bool) {
        self.id = id
        self.groupID = groupID
        self.kind = kind
        self.rect = rect
        self.focus = focus
        self.isFixedFocus = isFixedFocus
    }
}

/// The camera's live Cinematic report, pushed ~10 Hz while the effect is on.
public struct CinematicSubjectsReport: Equatable, Sendable {
    public var subjects: [CinematicSubject]
    public var notEnoughLight: Bool

    public init(subjects: [CinematicSubject], notEnoughLight: Bool) {
        self.subjects = subjects
        self.notEnoughLight = notEnoughLight
    }
}

/// The rules both the camera (to refuse) and the director (to never offer)
/// read, so the two can't disagree.
enum CinematicPolicy {

    /// The editable file's metadata describes the full sensor frame, so it is
    /// recorded 16:9 only; baked Cinematic takes any aspect (we crop pixels).
    static func allows(aspect: AspectRatio, output: CinematicOutput) -> Bool {
        output == .baked || aspect == .sixteenNine
    }

    /// While the effect is on, only the Cinematic formats' qualities apply.
    static func allows(resolution: VideoResolution, frameRate: VideoFrameRate,
                       in state: CinematicState) -> Bool {
        guard state.enabled else { return true }
        return state.qualities[resolution]?.contains(frameRate) ?? false
    }
}
