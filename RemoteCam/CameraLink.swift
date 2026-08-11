//
//  CameraLink.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import Foundation
import MPCCompat
import Stormo

/// One camera in a multicam director session. The director holds one of these
/// per connected camera, keyed by `MCPeerID`; it is the multicam analog of the
/// single link + single `FrameStreamReceiver` that `SessionCoordinator` holds
/// for a 1:1 monitor.
///
/// A reference type, not a struct: it owns a `FrameStreamReceiver` (a class
/// with a running decode timer) and the `MulticamController` actor mutates it
/// in place as frames, capabilities and clock samples arrive — a value type
/// would force a dictionary read-modify-write on every frame.
final class CameraLink {

    enum Status: Equatable {
        /// The session is up and frames are expected.
        case linked
        /// The link dropped; the director is re-browsing to invite it back.
        /// The tile stays on screen (last frame frozen) rather than vanishing.
        case reconnecting
        /// The peer is gone for good (removed by the user, or version-refused).
        case failed
    }

    let peerID: MCPeerID
    let displayName: String
    var status: Status = .linked

    /// The most recent capabilities the camera advertised, or nil until the
    /// first exchange completes. `supportsMulticam` gates the multicam-only
    /// wire messages (clock sync now; scheduled capture in later PRs).
    var capabilities: RemoteCmd.CameraCapabilitiesResp?
    var supportsMulticam: Bool { capabilities?.supportsMulticam ?? false }

    /// Rolling clock-offset estimate for this camera, fed by ClockSyncPong.
    /// Stored here so a future synced capture can schedule on the camera's own
    /// clock (PR4); PR3 only measures and surfaces it.
    var clockEstimator = ClockOffsetEstimator()
    var latestOffset: ClockOffsetSample? { clockEstimator.best }

    /// Monitor side: this lane has produced at least one VP9 frame, proving the
    /// camera speaks VP9 — the gate for sending it `RequestKeyframe` (mirrors
    /// `SessionCoordinator.monitorReceivedVP9Frame`, but per camera).
    var sawVP9 = false

    /// How this camera answered the most recent synced capture (nil before the
    /// first). Drives the tile's captured/failed badge.
    var captureOutcome: CaptureOutcome?

    /// This camera is rolling as part of a synced recording — drives the tile's
    /// REC badge.
    var isRecording = false

    /// This camera's own preview decoder + stall watchdog. Frames tagged with
    /// this peer's id are fed here; its `onImage` drives exactly this lane's
    /// tile, so a frame from another camera never touches it.
    let receiver = FrameStreamReceiver()

    init(peerID: MCPeerID) {
        self.peerID = peerID
        self.displayName = peerID.displayName
    }
}
