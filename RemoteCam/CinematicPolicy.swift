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
import CoreMedia
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

extension CinematicIntent {
    /// The director folds every Cinematic asked for while a `SetCinematic`
    /// is in flight into one queued intent with this. The newer intent
    /// wins, except that its aperture "keep" (`0`) keeps the queued one, so
    /// a toggle queued behind a drag doesn't lose the dragged aperture.
    func coalesced(with newer: CinematicIntent) -> CinematicIntent {
        CinematicIntent(enabled: newer.enabled,
                        aperture: newer.aperture > 0 ? newer.aperture : aperture,
                        output: newer.output)
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

    // MARK: - Camera-side decisions

    /// A camera device as the Cinematic decisions see it.
    struct DeviceCandidate: Equatable {
        enum Kind: Equatable { case dualWide, trueDepth, triple, dual, wide, other }
        enum Side: Equatable { case front, back, unspecified }
        var id: String
        var kind: Kind
        var side: Side
        var hasCinematicFormats: Bool
    }

    /// The device the session runs while Cinematic is on: the chosen
    /// (logical) camera when it has Cinematic formats, else a same-side
    /// sibling that does. Measured on an iPhone 14: only the back Dual Wide
    /// and the front TrueDepth have them, and the engine's front pick is the
    /// plain front camera. Nil = this camera can't do Cinematic.
    static func device(for logical: DeviceCandidate, among siblings: [DeviceCandidate]) -> DeviceCandidate? {
        if logical.hasCinematicFormats { return logical }
        let preference: [DeviceCandidate.Kind] = [.dualWide, .trueDepth, .triple, .dual, .wide, .other]
        return siblings
            .filter { $0.side == logical.side && $0.hasCinematicFormats && $0.id != logical.id }
            .min { preference.firstIndex(of: $0.kind)! < preference.firstIndex(of: $1.kind)! }
    }

    /// A Cinematic-capable format as the decisions see it.
    struct FormatCandidate: Equatable {
        var width: Int32
        var height: Int32
        var isEightBit: Bool
        /// The frame-rate range Cinematic allows on this format.
        var minFPS: Double
        var maxFPS: Double
    }

    /// Which Cinematic format to run: the quality setting's resolution, else
    /// 1080p, else the first; 8-bit (what the recorder and the preview
    /// encoder expect) before 10-bit. Nil only when there are none.
    static func formatIndex(_ formats: [FormatCandidate], resolution: VideoResolution) -> Int? {
        let hd = VideoResolution.hd1080p.dimensions
        let wanted = resolution.dimensions
        let ranked = formats.indices.sorted { lhs, rhs in
            func score(_ index: Int) -> Int {
                let format = formats[index]
                var score = format.isEightBit ? 0 : 1
                if format.width == wanted.width && format.height == wanted.height {
                    score += 0
                } else if format.width == hd.width && format.height == hd.height {
                    score += 10
                } else {
                    score += 20
                }
                return score
            }
            return (score(lhs), lhs) < (score(rhs), rhs)
        }
        return ranked.first
    }

    /// The resolution/fps pairs the Cinematic formats allow — what the
    /// quality menu offers while the effect is on.
    static func qualities(_ formats: [FormatCandidate]) -> [VideoResolution: [VideoFrameRate]] {
        var result: [VideoResolution: [VideoFrameRate]] = [:]
        for resolution in VideoResolution.selectableCases {
            let dims = resolution.dimensions
            let rates = formats
                .filter { $0.width == dims.width && $0.height == dims.height }
                .flatMap { format in
                    VideoFrameRate.selectableCases.filter {
                        Double($0.value) >= format.minFPS - 0.5 && Double($0.value) <= format.maxFPS + 0.5
                    }
                }
            let unique = VideoFrameRate.selectableCases.filter { rates.contains($0) }
            if !unique.isEmpty { result[resolution] = unique }
        }
        return result
    }

    /// The quality to run while Cinematic is on: the setting when Cinematic
    /// allows it, else the nearest allowed frame rate at the same resolution,
    /// else the same at 1080p, else anything allowed. Nil when nothing is.
    /// The result becomes the quality setting (reported, and restored when
    /// Cinematic goes off), so the director never shows a rate the camera
    /// isn't running.
    static func quality(fitting resolution: VideoResolution, _ frameRate: VideoFrameRate,
                        in qualities: [VideoResolution: [VideoFrameRate]]) -> (VideoResolution, VideoFrameRate)? {
        func nearest(_ rates: [VideoFrameRate]) -> VideoFrameRate? {
            rates.min { (abs($0.value - frameRate.value), -$0.value) < (abs($1.value - frameRate.value), -$1.value) }
        }
        for candidate in [resolution, .hd1080p] {
            if let rates = qualities[candidate], let rate = nearest(rates) { return (candidate, rate) }
        }
        for candidate in VideoResolution.selectableCases {
            if let rates = qualities[candidate], let rate = nearest(rates) { return (candidate, rate) }
        }
        return nil
    }

    /// Whether the effect should be on right now: asked for, in video mode,
    /// on a camera that can do it. The intent survives photo mode.
    static func isEffective(_ intent: CinematicIntent, isVideoMode: Bool, supported: Bool) -> Bool {
        intent.enabled && isVideoMode && supported
    }

    /// Why a Cinematic request can't be applied (nil = go ahead). Turning it
    /// off is always allowed outside a take.
    enum Refusal: Equatable {
        case recording
        case photoMode
        case unsupported(device: String)
        case editableNeedsSixteenNine

        var message: String {
            switch self {
            case .recording:
                return NSLocalizedString("Locked while recording", comment: "control refused while rolling")
            case .photoMode:
                return NSLocalizedString("Switch to video mode for Cinematic", comment: "cinematic refused in photo mode")
            case let .unsupported(device):
                return String(format: NSLocalizedString("%@ can't record Cinematic video",
                                                        comment: "cinematic refused: camera has no Cinematic formats"),
                              device)
            case .editableNeedsSixteenNine:
                return NSLocalizedString("Editable Cinematic records 16:9 only",
                                         comment: "cinematic editable refused: aspect is not 16:9")
            }
        }
    }

    static func refusal(for intent: CinematicIntent, isVideoMode: Bool, isRecording: Bool,
                        aspect: AspectRatio, supported: Bool, deviceName: String) -> Refusal? {
        if isRecording { return .recording }
        guard intent.enabled else { return nil }
        if !isVideoMode { return .photoMode }
        if !supported { return .unsupported(device: deviceName) }
        if !allows(aspect: aspect, output: intent.output) { return .editableNeedsSixteenNine }
        return nil
    }

    /// Manual exposure hops to a physical lens that has no Cinematic formats,
    /// so while Cinematic is on exposure is Auto; a bias the director set is
    /// kept.
    static func exposureIntent(_ current: ExposureIntent, cinematicOn: Bool) -> ExposureIntent {
        guard cinematicOn, case .manual = current else { return current }
        return .auto(bias: 0)
    }

    /// The aperture to apply: the request clamped into the format's range;
    /// 0 keeps the current value, or the format default the first time.
    static func aperture(requested: Float, current: Float, defaultValue: Float,
                         min minValue: Float, max maxValue: Float) -> Float {
        let wanted = requested > 0 ? requested : (current > 0 ? current : defaultValue)
        return Swift.min(Swift.max(wanted, minValue), maxValue)
    }
}
