//
//  CinematicPolicy.swift
//  RemoteShutter
//
//  Cinematic video (iOS 26 simulated aperture) as pure values and one decision
//  function, mirroring ExposurePolicy: the engine turns a `CinematicIntent`
//  into session calls; the policy decides what is allowed. No AVFoundation
//  types cross this boundary. See Docs/pro-controls.md.
//

import Foundation

/// What the monitor asked for. `aperture` nil (or ≤ 0 on the wire) means
/// "keep the camera's current value" (the format default on first enable).
public enum CinematicIntent: Equatable, Sendable {
    case off
    case on(aperture: Float?)
}

/// The booleans and ranges the policy needs from the device + session.
struct CinematicFacts: Equatable, Sendable {
    /// iOS 26+ and the active device has a Cinematic-capable format.
    var supported: Bool
    var enabled: Bool
    /// 0 when the device cannot adjust the simulated aperture.
    var minAperture: Float
    var maxAperture: Float
    var defaultAperture: Float
    var currentAperture: Float
}

/// What the engine should do to the session.
enum CinematicPlan: Equatable, Sendable {
    case noop
    /// Session reconfiguration (begin/commitConfiguration) + aperture.
    case enable(aperture: Float?)
    /// The effect is already on; only the aperture moves (no reconfig).
    case apertureOnly(Float)
    case disable
    case rejected(CinematicRejection)
}

enum CinematicRejection: Equatable, Sendable {
    /// Cinematic is a video-recording effect; the camera is in photo mode.
    case photoMode
    /// Apple rejects enable/disable/aperture changes while a take is rolling.
    case recording
    /// Device or OS cannot do Cinematic video.
    case unsupported
}

/// Snapshot of the camera's Cinematic truth, echoed after every command and
/// carried in capabilities.
public struct CinematicState: Equatable, Sendable {
    public var enabled: Bool
    public var simulatedAperture: Float
    /// 0 = the device cannot adjust the aperture (hide the dial).
    public var minSimulatedAperture: Float
    public var maxSimulatedAperture: Float
    public var defaultSimulatedAperture: Float
    /// True while recording: the aperture is set before a take, never during.
    public var apertureLocked: Bool
    /// The camera reports the scene is too dark for a good Cinematic result.
    public var notEnoughLight: Bool

    public init(enabled: Bool, simulatedAperture: Float,
                minSimulatedAperture: Float, maxSimulatedAperture: Float,
                defaultSimulatedAperture: Float, apertureLocked: Bool, notEnoughLight: Bool) {
        self.enabled = enabled
        self.simulatedAperture = simulatedAperture
        self.minSimulatedAperture = minSimulatedAperture
        self.maxSimulatedAperture = maxSimulatedAperture
        self.defaultSimulatedAperture = defaultSimulatedAperture
        self.apertureLocked = apertureLocked
        self.notEnoughLight = notEnoughLight
    }
}

enum CinematicPolicy {

    /// The one decision. Order matters: an unsupported device is unsupported in
    /// every mode; a supported one is then bounded by mode and recording.
    static func resolve(_ intent: CinematicIntent,
                        facts: CinematicFacts,
                        isRecording: Bool,
                        isVideoMode: Bool) -> CinematicPlan {
        switch intent {
        case .off:
            guard facts.enabled else { return .noop }
            guard !isRecording else { return .rejected(.recording) }
            return .disable

        case let .on(requestedAperture):
            guard facts.supported else { return .rejected(.unsupported) }
            guard isVideoMode else { return .rejected(.photoMode) }
            guard !isRecording else { return .rejected(.recording) }

            let aperture = clampedAperture(requestedAperture, facts: facts)
            if facts.enabled {
                guard let aperture, aperture != facts.currentAperture else { return .noop }
                return .apertureOnly(aperture)
            }
            return .enable(aperture: aperture)
        }
    }

    /// nil when the device cannot adjust the aperture (min == 0) or nothing
    /// was requested and nothing is set yet (the format default applies).
    static func clampedAperture(_ requested: Float?, facts: CinematicFacts) -> Float? {
        guard facts.minAperture > 0 else { return nil }
        guard let requested, requested > 0 else { return nil }
        return min(max(requested, facts.minAperture), facts.maxAperture)
    }
}

// MARK: - Dial stops

/// The detents the monitor's dials snap to, in values a photographer
/// recognizes, filtered to what the connected camera's format allows.
enum ProDialStops {

    /// Standard shutter stops from 1/8000 s up to 1 s.
    static let allShutterSeconds: [Double] = [
        1.0 / 8000, 1.0 / 4000, 1.0 / 2000, 1.0 / 1000, 1.0 / 500, 1.0 / 250,
        1.0 / 125, 1.0 / 60, 1.0 / 30, 1.0 / 15, 1.0 / 8, 1.0 / 4, 1.0 / 3,
        1.0 / 2, 1.0
    ]

    /// ISO in ⅓-stops.
    static let allISO: [Float] = [
        25, 32, 40, 50, 64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640,
        800, 1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000, 10_000
    ]

    /// f-numbers in ⅓-stops (the Camera-app Depth Control range).
    static let allApertures: [Float] = [
        1.4, 1.6, 1.8, 2.0, 2.2, 2.5, 2.8, 3.2, 3.5, 4.0, 4.5, 5.0, 5.6,
        6.3, 7.1, 8.0, 9.0, 10, 11, 13, 14, 16
    ]

    static func shutterStops(min: Double, max: Double) -> [Double] {
        allShutterSeconds.filter { $0 >= min && $0 <= max }
    }

    static func isoStops(min: Float, max: Float) -> [Float] {
        allISO.filter { $0 >= min && $0 <= max }
    }

    static func apertureStops(min: Float, max: Float) -> [Float] {
        guard min > 0 else { return [] }
        return allApertures.filter { $0 >= min && $0 <= max }
    }

    /// Index of the stop closest to `value` (the dial's resting detent).
    static func nearestIndex<T: BinaryFloatingPoint>(of value: T, in stops: [T]) -> Int? {
        guard !stops.isEmpty else { return nil }
        return stops.enumerated().min { abs($0.element - value) < abs($1.element - value) }?.offset
    }

    /// "1/125" below a second, "0.5s" / "1s" at or above.
    static func shutterLabel(_ seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        if seconds < 0.25 {
            return "1/\(Int((1.0 / seconds).rounded()))"
        }
        let formatted = seconds == seconds.rounded()
            ? String(Int(seconds)) : String(format: "%.1f", seconds)
        return "\(formatted)s"
    }

    static func isoLabel(_ iso: Float) -> String {
        "ISO \(Int(iso.rounded()))"
    }

    static func apertureLabel(_ aperture: Float) -> String {
        let value = aperture == aperture.rounded()
            ? String(Int(aperture)) : String(format: "%.1f", aperture)
        return "f/\(value)"
    }
}
