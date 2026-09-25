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

    /// Director side: this lane has produced at least one VP9 frame, proving the
    /// camera speaks VP9 — the gate for sending it `RequestKeyframe`.
    var sawVP9 = false

    /// How this camera answered the most recent synced capture (nil before the
    /// first). Drives the tile's captured/failed badge.
    var captureOutcome: CaptureOutcome?

    /// The camera's recording truth for this lane: non-nil exactly while it
    /// is rolling, carrying the camera's latest elapsed tick (ms) — the
    /// camera DRIVES the lane's timer; the director displays the last value
    /// received, never computes one. Seeded to 0 when a start is acked, then
    /// driven by the camera's `CameraStateReport` ticks. Drives the tile's
    /// REC badge and the rig shutter's union.
    var recordingElapsedMillis: UInt64?
    var isRecording: Bool { recordingElapsedMillis != nil }

    /// Newest `CameraStateReport.seq` absorbed from this lane; zeroed when the
    /// camera re-announces (its session, and seq domain, restarted). Stale
    /// reports are dropped, so a delayed push can never outrank fresh truth.
    var lastStateReportSeq: UInt64 = 0

    /// The preview profile most recently pushed to this camera, so the director
    /// only re-sends `SetStreamProfile` when the tier actually changes.
    var lastSentProfile: StreamProfile?

    /// Where this lane's footage is in the post-take auto-collect to the
    /// director. Drives the tile's transfer progress / done / failed badge.
    var collection: LaneCollectionState = .idle

    /// Control commands sent to this camera and not yet answered, counted per
    /// action. Every control command is answered exactly once (with the
    /// camera's full state, Docs/control-plane.md), so a count above zero
    /// means "in flight" for that control; a reply, a failed send, or the
    /// reply deadline each bring it down by one. Nothing about the camera is
    /// remembered from the tap — the glyphs read `capabilities`.
    var pending: [RemoteShutter_CommandAction: Int] = [:]
    /// Exposure asked for while a `SetExposure` was in flight, folded into
    /// one intent (`ExposureIntent.coalesced`) and sent when that command is
    /// settled. A ruler drag asks far faster than a camera can apply, so the
    /// camera only ever gets the newest value, one at a time, and never
    /// works through a backlog of stale ones.
    var queuedExposure: ExposureIntent?

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
            recordingElapsedMillis: recordingElapsedMillis,
            needsQualityRematch: needsQualityRematch,
            collection: collection,
            canFlipCamera: capabilities.map {
                $0.frontCamera != nil && $0.backCamera != nil
            } ?? false,
            cameraDevices: capabilities?.cameraDevices ?? [],
            activeDeviceID: capabilities?.activeDeviceID,
            supportsFocusPoint: capabilities?.supportsFocusPoint ?? false,
            hasTorch: capabilities?.getCurrentCameraInfo()?.hasTorch ?? false,
            zoomFactor: capabilities?.currentZoom ?? 1.0,
            maxZoomFactor: zoom?.maxZoomFactor ?? 10.0,
            zoomStops: zoom?.zoomStops ?? [1.0],
            wideAngleZoomFactor: zoom?.wideAngleZoomFactor ?? 1.0,
            torchOn: capabilities?.torchOn ?? false,
            flashOn: (capabilities?.flashMode ?? .off) != .off,
            inFlight: Set(pending.filter { $0.value > 0 }.keys),
            exposure: capabilities?.exposure)
    }

    /// The zoom scale as the camera last reported it — the same derivation
    /// for the seed and for every reply, so the pill can never disagree with
    /// the camera about its range.
    private var zoom: ZoomScaleSeed.Seed? { capabilities.flatMap { ZoomScaleSeed.seed(from: $0) } }
}
