//
//  ControlState.swift
//  RemoteShutter
//
//  The camera's complete control-plane truth — the pure core of the v11
//  control plane (Docs/control-plane.md). One value, produced by exactly one
//  engine function, carried whole on the wire (`ControlStateChanged`), and
//  absorbed by one fold. Every range in it is EFFECTIVE (already narrowed by
//  whatever is active — e.g. zoom under Cinematic), so no consumer ever
//  combines constraints itself, and remotes render `f(snapshot)` with no
//  stored derivations to go stale.
//

import CoreGraphics
import Foundation

/// A snapshot of everything the remote can control, as the camera has it now.
/// Capability IS presence: `exposure == nil` means the active device cannot do
/// manual exposure (no tiles, no `SetExposure`); same for `cinematic`.
public struct ControlState: Equatable, Sendable {
    /// Monotonic across camera restarts; `absorb` drops anything older.
    public var seq: UInt64
    public var mode: RecordingMode
    /// The LOGICAL device — the camera the user chose. The Manual-exposure
    /// lens hop is an implementation detail that never reaches this value.
    public var activeDeviceID: String?
    public var currentLens: CameraLensType
    public var availableLenses: [CameraLensType]
    /// Zoom: the factor plus the range the camera can honor RIGHT NOW.
    public var zoomFactor: CGFloat
    public var minZoom: CGFloat
    public var maxZoom: CGFloat
    public var zoomStops: [CGFloat]
    public var wideAngleZoomFactor: CGFloat
    /// Tap-to-focus is a property of the active device.
    public var supportsFocusPoint: Bool
    public var exposure: ExposureState?
    public var cinematic: CinematicState?

    public init(seq: UInt64,
                mode: RecordingMode = .Photo,
                activeDeviceID: String? = nil,
                currentLens: CameraLensType = .wideAngle,
                availableLenses: [CameraLensType] = [.wideAngle],
                zoomFactor: CGFloat = 1.0,
                minZoom: CGFloat = 1.0,
                maxZoom: CGFloat = 1.0,
                zoomStops: [CGFloat] = [1.0],
                wideAngleZoomFactor: CGFloat = 1.0,
                supportsFocusPoint: Bool = false,
                exposure: ExposureState? = nil,
                cinematic: CinematicState? = nil) {
        self.seq = seq
        self.mode = mode
        self.activeDeviceID = activeDeviceID
        self.currentLens = currentLens
        self.availableLenses = availableLenses
        self.zoomFactor = zoomFactor
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.zoomStops = zoomStops
        self.wideAngleZoomFactor = wideAngleZoomFactor
        self.supportsFocusPoint = supportsFocusPoint
        self.exposure = exposure
        self.cinematic = cinematic
    }

    // MARK: - The one write

    /// The ONLY way a remote updates its stored snapshot: newer wins, stale
    /// drops. Delivery order, duplicates, and races between a push and a
    /// requested refresh all collapse into this comparison.
    public static func absorb(_ current: ControlState?, _ incoming: ControlState) -> ControlState {
        guard let current else { return incoming }
        return incoming.seq >= current.seq ? incoming : current
    }

    // MARK: - Pure derivations

    /// The zoom pill's math, derived — never stored — so it can't disagree
    /// with the snapshot it came from. The display ceiling caps runaway
    /// digital-zoom maxima exactly as the old seed path did.
    var zoomScale: ZoomScale {
        ZoomScale(stops: zoomStops,
                  maxZoomFactor: ZoomScale.displayCapped(maxZoom, wideAngle: wideAngleZoomFactor),
                  wideAngleZoomFactor: wideAngleZoomFactor,
                  minZoomFactor: minZoom)
    }

    public var supportsManualExposure: Bool { exposure != nil }
    public var supportsCinematicVideo: Bool { cinematic != nil }
}

/// Why a control mutation did not take (`ControlStateChanged.refusal`).
/// A refusal always reaches the user's eyes — a refused control must never
/// look like a control that did nothing.
public enum ControlRefusalReason: Equatable, Sendable {
    /// Cinematic is a video effect; the camera is in photo mode.
    case photoMode
    /// This control is locked while a take is rolling.
    case recording
    /// The active device/OS cannot do this at all.
    case unsupported
    /// The device supports it, but the session configuration refuses.
    case sessionRefused

    /// What the remote shows. `detail` is the camera's diagnostic suffix
    /// (device, format, outputs), appended when present.
    public func message(detail: String?) -> String {
        let base: String
        switch self {
        case .photoMode:
            base = NSLocalizedString("Switch to video mode for Cinematic", comment: "control refusal")
        case .recording:
            base = NSLocalizedString("That control is locked while recording", comment: "control refusal")
        case .unsupported:
            base = NSLocalizedString("This camera can't do that", comment: "control refusal")
        case .sessionRefused:
            base = NSLocalizedString("The camera refused that setting", comment: "control refusal")
        }
        guard let detail, !detail.isEmpty else { return base }
        return "\(base) (\(detail))"
    }
}
