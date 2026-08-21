//
//  ExposurePolicy.swift
//  RemoteShutter
//
//  Manual exposure (shutter speed + ISO) as pure values and one decision
//  function. The engine turns an `ExposureIntent` into device calls; the policy
//  decides what the device is allowed to receive. No AVFoundation types cross
//  this boundary, so every rule here is table-testable. See
//  Docs/pro-controls.md.
//

import Foundation

/// Auto vs. manual exposure, as reported by the camera and chosen by the monitor.
public enum ExposureMode: Equatable, Sendable {
    case auto
    case manual
}

/// What the monitor asked for. Seconds rather than `CMTime` because this value
/// rides the wire; the engine clamps it back into the device's own `CMTime`s.
/// A duration or ISO of `0` (or less) means "keep the device's current value"
/// — the same convention as `AVCaptureDevice.currentExposureDuration`.
public enum ExposureIntent: Equatable, Sendable {
    case auto
    case manual(durationSeconds: Double, iso: Float)
}

/// The ranges and booleans the policy needs from the active device + format.
struct ExposureFacts: Equatable, Sendable {
    var supportsCustom: Bool
    var minDurationSeconds: Double
    var maxDurationSeconds: Double
    var minISO: Float
    var maxISO: Float
    /// The active max frame duration (1 / fps). A manual shutter longer than
    /// this lengthens it — which changes the recorded frame rate mid-clip.
    var maxFrameDurationSeconds: Double
    var currentDurationSeconds: Double
    var currentISO: Float
}

/// What the engine should do to the device.
enum ExposurePlan: Equatable, Sendable {
    case auto
    case manual(durationSeconds: Double, iso: Float)
    /// The active device cannot do custom exposure (virtual multi-lens
    /// devices, most Mac cameras): the engine falls back to auto and the
    /// response tells the monitor so.
    case unsupported
}

/// Snapshot of the device's exposure truth, echoed to the monitor after every
/// command and carried in capabilities so the panel opens populated.
public struct ExposureState: Equatable, Sendable {
    public var mode: ExposureMode
    public var durationSeconds: Double
    public var iso: Float
    public var minDurationSeconds: Double
    public var maxDurationSeconds: Double
    public var minISO: Float
    public var maxISO: Float

    public init(mode: ExposureMode, durationSeconds: Double, iso: Float,
                minDurationSeconds: Double, maxDurationSeconds: Double, minISO: Float, maxISO: Float) {
        self.mode = mode
        self.durationSeconds = durationSeconds
        self.iso = iso
        self.minDurationSeconds = minDurationSeconds
        self.maxDurationSeconds = maxDurationSeconds
        self.minISO = minISO
        self.maxISO = maxISO
    }
}

enum ExposurePolicy {

    /// The one decision: clamp the intent into what the device + format allow.
    ///
    /// - While recording the shutter is additionally capped at the frame
    ///   duration so the clip's frame rate never changes mid-take. In photo
    ///   mode a long shutter may legitimately slow the preview.
    /// - Zero/negative components keep the device's current value.
    static func resolve(_ intent: ExposureIntent,
                        facts: ExposureFacts,
                        isRecording: Bool) -> ExposurePlan {
        switch intent {
        case .auto:
            return .auto
        case let .manual(requestedDuration, requestedISO):
            guard facts.supportsCustom else { return .unsupported }

            var durationCeiling = facts.maxDurationSeconds
            if isRecording, facts.maxFrameDurationSeconds > 0 {
                durationCeiling = min(durationCeiling, facts.maxFrameDurationSeconds)
            }
            durationCeiling = max(durationCeiling, facts.minDurationSeconds)

            let wantedDuration = requestedDuration > 0 ? requestedDuration : facts.currentDurationSeconds
            let wantedISO = requestedISO > 0 ? requestedISO : facts.currentISO

            let duration = min(max(wantedDuration, facts.minDurationSeconds), durationCeiling)
            let iso = min(max(wantedISO, facts.minISO), facts.maxISO)
            return .manual(durationSeconds: duration, iso: iso)
        }
    }
}
