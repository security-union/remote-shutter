//
//  ExposurePolicy.swift
//  RemoteShutter
//
//  Exposure (EV bias in Auto; shutter speed + ISO in Manual) as pure values
//  and one decision function. The engine turns an `ExposureIntent` into
//  device calls; the policy decides what the device is allowed to receive.
//  No AVFoundation types cross this boundary, so every rule here is
//  table-testable. See Docs/pro-controls.md.
//

import Foundation

/// Auto vs. manual exposure, as reported by the camera and chosen by the director.
public enum ExposureMode: Equatable, Sendable {
    case auto
    case manual
}

/// What the director asked for. Seconds rather than `CMTime` because this
/// value rides the wire; the engine clamps it back into the device's own
/// `CMTime`s. In Manual, a duration or ISO of `0` (or less) means "keep the
/// device's current value" — the same convention as
/// `AVCaptureDevice.currentExposureDuration`. In Auto the bias is absolute
/// (0 = neutral, the ordinary auto exposure).
public enum ExposureIntent: Equatable, Sendable {
    case auto(bias: Float)
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
    var minBias: Float
    var maxBias: Float
}

/// What the engine should do to the device.
enum ExposurePlan: Equatable, Sendable {
    case auto(bias: Float)
    case manual(durationSeconds: Double, iso: Float)
    /// The active device cannot do custom exposure (virtual multi-lens
    /// devices, most Mac cameras): the engine falls back to auto and the
    /// state reply tells the director so.
    case unsupported
}

/// The camera's exposure truth, carried in every state reply so the
/// director's rulers always show this device's limits.
public struct ExposureState: Equatable, Sendable {
    public var mode: ExposureMode
    public var bias: Float
    public var minBias: Float
    public var maxBias: Float
    /// The light meter: how far the current frame is from the metered
    /// target, in stops.
    public var targetOffset: Float
    /// False = this device refuses custom exposure; the director offers
    /// bias only.
    public var supportsManual: Bool
    public var durationSeconds: Double
    public var iso: Float
    public var minDurationSeconds: Double
    public var maxDurationSeconds: Double
    public var minISO: Float
    public var maxISO: Float
    /// 1 / fps of the active format: the shutter ceiling while recording.
    public var maxFrameDurationSeconds: Double

    public init(mode: ExposureMode, bias: Float = 0, minBias: Float = 0, maxBias: Float = 0,
                targetOffset: Float = 0, supportsManual: Bool,
                durationSeconds: Double, iso: Float,
                minDurationSeconds: Double, maxDurationSeconds: Double, minISO: Float, maxISO: Float,
                maxFrameDurationSeconds: Double = 0) {
        self.mode = mode
        self.bias = bias
        self.minBias = minBias
        self.maxBias = maxBias
        self.targetOffset = targetOffset
        self.supportsManual = supportsManual
        self.durationSeconds = durationSeconds
        self.iso = iso
        self.minDurationSeconds = minDurationSeconds
        self.maxDurationSeconds = maxDurationSeconds
        self.minISO = minISO
        self.maxISO = maxISO
        self.maxFrameDurationSeconds = maxFrameDurationSeconds
    }
}

enum ExposurePolicy {

    /// The one decision: clamp the intent into what the device + format allow.
    ///
    /// - While recording the shutter is additionally capped at the frame
    ///   duration so the clip's frame rate never changes mid-take. In photo
    ///   mode a long shutter may legitimately slow the preview.
    /// - Zero/negative manual components keep the device's current value.
    /// - The bias is clamped into the device's range.
    static func resolve(_ intent: ExposureIntent,
                        facts: ExposureFacts,
                        isRecording: Bool) -> ExposurePlan {
        switch intent {
        case let .auto(bias):
            return .auto(bias: min(max(bias, facts.minBias), facts.maxBias))
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
