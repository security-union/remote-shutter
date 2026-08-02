//
//  CameraPreviewMode.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import Foundation

/// Whether the **camera** device drives its own on-screen live preview.
///
/// - `.on` — the shipping behavior: a full-screen live preview. This is the
///   default and must stay the default, so enabling standby is strictly opt-in
///   and nobody's existing experience changes.
/// - `.standby` — the camera stops compositing its *local* preview (which costs
///   battery and heat on a long tripod shoot) and shows a minimal status screen
///   instead. The capture session keeps running and preview frames keep
///   streaming to the monitor exactly as before — standby is a LOCAL-DISPLAY
///   concern only.
public enum CameraPreviewMode: String, Sendable, Equatable, CaseIterable {
    case on
    case standby

    /// The shipping default. Opt-in feature: never flip this to `.standby`.
    public static let `default`: CameraPreviewMode = .on
}

/// `UserDefaults`-backed persistence for `CameraPreviewMode`, stored on the
/// camera device so the choice survives relaunch.
///
/// There is exactly ONE preference. A remote `RemoteCmd.SetCameraPreviewMode`
/// writes the same store a local toggle does — the wire command is not a
/// session override layered on top of a stored value, it *is* the stored value.
public struct CameraPreviewModeStore {

    /// The `UserDefaults` key. Namespaced so it can't collide with the app's
    /// other loosely-typed preference keys.
    static let defaultsKey = "camera.previewMode"

    private let defaults: UserDefaults

    /// Injectable defaults so tests can round-trip against an isolated suite
    /// instead of `.standard`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The persisted mode, or `.default` (preview on) when nothing has been
    /// stored yet or a stored value is unreadable.
    public func load() -> CameraPreviewMode {
        guard let raw = defaults.string(forKey: Self.defaultsKey),
              let mode = CameraPreviewMode(rawValue: raw) else {
            return .default
        }
        return mode
    }

    /// Persists `mode` so it survives relaunch.
    public func save(_ mode: CameraPreviewMode) {
        defaults.set(mode.rawValue, forKey: Self.defaultsKey)
    }
}
