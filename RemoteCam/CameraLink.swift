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
/// single link that `SessionCoordinator` holds for a 1:1 monitor. (Frame
/// decoding lives entirely on the UI side, one `FrameStreamReceiver` per
/// `CameraLane`; this actor-domain link never touches pixels.)
///
/// A reference type, not a struct: the `MulticamController` actor mutates it in
/// place as capabilities and clock samples arrive — a value type would force a
/// dictionary read-modify-write on every update.
final class CameraLink {

    /// Progress of one lane's footage transfer to the director after a take.
    enum LaneCollectionState: Equatable {
        case idle
        case transferring(Double) // 0…1
        case collected
        case failed
    }

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

    /// The preview profile most recently pushed to this camera, so the director
    /// only re-sends `SetStreamProfile` when the tier actually changes.
    var lastSentProfile: StreamProfile?

    /// Where this lane's footage is in the post-take auto-collect to the
    /// director. Drives the tile's transfer progress / done / failed badge.
    var collection: LaneCollectionState = .idle

    /// Optimistic torch / flash state, flipped when the director sends the
    /// toggle to this (focused) camera. The camera decides what actually
    /// happens; this just tints the glyph immediately, like the 1:1 monitor.
    var torchOn = false
    var flashOn = false

    /// Zoom state for the focused zoom pill, seeded from the capabilities
    /// exchange and refined by each `SetZoomResp` — the same values the 1:1
    /// monitor tracks (`zoomStops`/`wideAngleZoomFactor`/`maxZoomFactor` build
    /// the `ZoomScale`; `zoomFactor` is the live hardware factor).
    var zoomFactor: CGFloat = 1.0
    var maxZoomFactor: CGFloat = 10.0
    var zoomStops: [CGFloat] = [1.0]
    var wideAngleZoomFactor: CGFloat = 1.0

    init(peerID: MCPeerID) {
        self.peerID = peerID
        self.displayName = peerID.displayName
    }

    /// The single source of the UI snapshot for this lane — every displayed
    /// field is declared exactly once, here. The cross-cutting fields
    /// (`isFocused`, the re-match badge) are derived by the caller from the
    /// rig-level inputs, never stored on the lane.
    func snapshot(isFocused: Bool, needsQualityRematch: Bool) -> MulticamLaneInfo {
        MulticamLaneInfo(
            peerID: peerID,
            displayName: displayName,
            status: status,
            isFocused: isFocused,
            clockOffsetMillis: latestOffset?.offsetMillis,
            captureOutcome: captureOutcome,
            isRecording: isRecording,
            needsQualityRematch: needsQualityRematch,
            collection: collection,
            canFlipCamera: capabilities.map {
                $0.frontCamera != nil && $0.backCamera != nil
            } ?? false,
            supportsFocusPoint: capabilities?.supportsFocusPoint ?? false,
            zoomFactor: zoomFactor,
            maxZoomFactor: maxZoomFactor,
            zoomStops: zoomStops,
            wideAngleZoomFactor: wideAngleZoomFactor,
            torchOn: torchOn,
            flashOn: flashOn)
    }
}
