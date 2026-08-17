//
//  FocusedCameraControlState.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

/// The enablement rules for the per-camera framing controls (flip, torch,
/// flash), derived purely from link status, capture mode and recording state.
/// One source of truth so the 1:1 monitor and the multicam director can never
/// gate these controls differently.
///
/// The multicam director consumes this directly. The 1:1 monitor still sets its
/// per-mode `@Published` flags imperatively in `configure{Photo,Video,Recording}Mode`;
/// folding those into this struct is a restructuring left to the post-9.1 pass
/// (see docs/multicam.md).
struct FocusedCameraControlState: Equatable {
    /// Whether a camera is linked and drivable at all.
    let isLinked: Bool
    let isPhotoMode: Bool
    let isRecording: Bool

    /// Flip is available whenever the camera is linked and not recording — the
    /// camera itself decides whether a flip does anything (never gated on
    /// advertised positions).
    var flipEnabled: Bool { isLinked && !isRecording }
    /// Torch is available whenever the camera is linked.
    var torchEnabled: Bool { isLinked }
    /// Flash is a photo-mode control and never available while recording.
    var flashEnabled: Bool { isLinked && isPhotoMode && !isRecording }
}
