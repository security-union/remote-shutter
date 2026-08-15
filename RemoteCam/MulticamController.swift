//
//  MulticamController.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

// swiftlint:disable cyclomatic_complexity function_body_length

import Foundation
import MPCCompat
import Photos
import Stormo
import UIKit

/// The director's aggregate posture across all cameras. One shutter drives
/// them all, so the capture states are aggregate, not per-camera.
enum MulticamState: Equatable {
    case monitoring(mode: MonitorMode)
    /// A synced photo is in flight: `acksRemaining` cameras have yet to accept
    /// or refuse `captureId`. Returns to `.monitoring` when it reaches zero.
    case capturingPhoto(captureId: String, acksRemaining: Int)
    /// The rig is recording (or still collecting start acks). `acksRemaining`
    /// counts cameras that have yet to confirm the scheduled start.
    case recording(captureId: String, acksRemaining: Int)
    /// A synced stop is in flight; returns to `.monitoring` when every camera
    /// has confirmed (or timed out).
    case stoppingRecording(captureId: String, acksRemaining: Int)
}

/// How a camera answered the last synced capture, for the tile badge.
enum CaptureOutcome: Equatable {
    case captured
    case failed
}

/// A UI-facing snapshot of one lane. Deliberately a value type carrying only
/// what the chrome/tile needs, so the actor never hands the UI a live
/// reference into its own state.
struct MulticamLaneInfo: Equatable {
    let peerID: MCPeerID
    let displayName: String
    let status: CameraLink.Status
    let isFocused: Bool
    /// Clock-offset estimate in ms (nil until the first pong), for a future
    /// sync-quality indicator; unused by PR3's UI beyond diagnostics.
    let clockOffsetMillis: Int64?
    /// How this camera answered the last synced capture, for the tile badge.
    let captureOutcome: CaptureOutcome?
    /// This camera is rolling as part of a synced recording (REC badge).
    let isRecording: Bool
    /// This camera can't match the running rig quality — tile badge + re-match.
    let needsQualityRematch: Bool
    /// Where this lane's footage is in the post-take auto-collect.
    let collection: CameraLink.LaneCollectionState
    /// This camera advertised both a front and a back camera in its last
    /// capabilities. Not the flip-button gate (that mirrors the 1:1 monitor and
    /// stays ungated); a projection of capabilities for diagnostics/tests.
    let canFlipCamera: Bool
    /// Zoom state for the focused zoom pill (the same values the 1:1 monitor
    /// builds its `ZoomScale` from). `zoomFactor` is the live hardware factor.
    let zoomFactor: CGFloat
    let maxZoomFactor: CGFloat
    let zoomStops: [CGFloat]
    let wideAngleZoomFactor: CGFloat
    /// Optimistic torch / flash state so the control-capsule glyphs tint like
    /// the 1:1 monitor's the instant they are tapped.
    let torchOn: Bool
    let flashOn: Bool
}

/// A Sendable pipe that carries one lane's decoded-preview frames from the
/// controller (actor domain) to exactly that lane's UI-side decoder. The view
/// controller hands one to the controller per lane at creation
/// (`setFrameSink(for:_:)`), so the ~20fps stream routes actor → closure —
/// never reaching into a `UIViewController` from the actor.
typealias MulticamFrameSink = @Sendable (RemoteCmd.OnFrame) -> Void

/// The main-actor bridge from the controller to the multicam screen — the
/// multicam analog of `MonitorDisplay`. Low-frequency lane changes go through
/// `applyLanes`; the ~20fps preview stream goes through per-lane frame sinks
/// (see `MulticamFrameSink`), each routing to exactly one lane's decoder so a
/// frame from camera B never re-renders camera A.
protocol MulticamDisplay: AnyObject {
    func applyLanes(_ lanes: [MulticamLaneInfo])
    /// Aggregate shutter state: `capturing` = a synced photo is in flight
    /// (activity ring); `recording` = the rig is rolling (record/stop button).
    func applyShutterState(capturing: Bool, recording: Bool)
    /// Cameras the browser has found that aren't in the rig — the add-camera
    /// sheet's list.
    func applyAvailablePeers(_ peers: [MCPeerID])
    /// The rig-wide settings (timer + quality intersection) for the tray.
    func applyRigSettings(_ settings: RigSettingsSnapshot)
    func exitMulticam()
}

/// Director side of a multicam session: one controller, several cameras.
///
/// A sibling of `SessionCoordinator`, not a replacement — `SessionCoordinator`
/// stays the sole brain for the camera role and for 1:1 monitoring, both
/// byte-identical to before. This actor is reached only when the director
/// starts a multicam session (≥2 cameras, behind `ENABLE_MULTICAM`). The
/// camera side is unchanged: a camera cannot tell a multicam director from a
/// single monitor.
///
/// Mirrors `SessionCoordinator`'s concurrency shape: a FIFO inbox fed by
/// `tell(_:)`, nonisolated transport-delegate callbacks that enqueue, and a
/// lock-boxed transport mirror for the sends that must not queue behind
/// state-machine work (frame acks, clock-sync answers).
public actor MulticamController {

    // MARK: Inbox (mirrors SessionCoordinator)

    private nonisolated let inboxContinuation: Locked<AsyncStream<Message>.Continuation?> = Locked(nil)
    private nonisolated let pendingCount = Locked(0)

    public init() {
        var continuation: AsyncStream<Message>.Continuation!
        let stream = AsyncStream<Message>(bufferingPolicy: .unbounded) { continuation = $0 }
        self.inboxContinuation.value = continuation
        let pending = pendingCount
        Task { [weak self] in
            for await msg in stream {
                guard let self else { break }
                await self.handle(msg)
                pending.mutate { $0 -= 1 }
            }
        }
    }

    public nonisolated func tell(_ msg: Message) {
        pendingCount.mutate { $0 += 1 }
        inboxContinuation.value?.yield(msg)
    }

    /// Test support: suspend until every enqueued message is processed.
    public nonisolated func waitForIdle() async {
        while pendingCount.value > 0 {
            await Task.yield()
        }
    }

    public nonisolated func stop() {
        clockSyncTask.value?.cancel()
        timerTask.value?.cancel()
        transportShared.value?.stopSession()
        inboxContinuation.value?.finish()
    }

    // MARK: Transport

    private var multipeerService: (any MultipeerServiceProtocol)?
    private let transportShared = Locked<(any MultipeerServiceProtocol)?>(nil)
    private nonisolated let clockSyncTask = Locked<Task<Void, Never>?>(nil)

    // MARK: State

    private var state: MulticamState = .monitoring(mode: .photo)
    /// Insertion-ordered peer ids, so the strip/grid order is stable as lanes
    /// come and go.
    private var order: [MCPeerID] = []
    private var links: [MCPeerID: CameraLink] = [:]
    private var focusedPeer: MCPeerID?

    /// Cameras the browser has found that are not in the rig yet — the source
    /// list for the in-session "add camera" sheet. Insertion-ordered.
    private var availableOrder: [MCPeerID] = []
    private var available: Set<MCPeerID> = []

    /// One id per director session, part of every capture's filename group.
    private let sessionID = UUID().uuidString
    /// Cameras that have yet to answer the in-flight synced capture. Empty
    /// unless `state` is `.capturingPhoto`.
    private var capturingLanes: Set<MCPeerID> = []
    private var currentCaptureID: String?
    /// The most recent photo/video capture id, used to name auto-collected
    /// footage on the director under the shared `RS_<sess>_<cap>_cam<k>` group.
    private var lastCaptureID: String?

    /// Lead time before a synced shutter fires — long enough to cover the
    /// worst-case one-way latency plus a retransmit and scheduling slop, so
    /// every camera has the command in hand before the instant arrives.
    private let captureLeadMillis: UInt64 = 150
    /// How long a camera has to answer before it is counted as failed.
    private var captureAckTimeout: TimeInterval = 3

    // MARK: Rig-wide settings ("the shot belongs to the rig")

    /// The rig's active video quality — applied to every lane. Nil until the
    /// first pick (or Automatic). Manual selection within the intersection is
    /// first-class; Automatic just recomputes best-in-intersection.
    private var activeVideoQuality: (resolution: VideoResolution, frameRate: VideoFrameRate)?
    private var activePhotoQuality: (format: PhotoFormat, hdr: HDRMode)?
    /// One rig self-timer (seconds); 0 = off. Fans out to every camera so
    /// subjects see the countdown, and its expiry triggers the synced capture.
    private var rigTimerSeconds: Int = 0
    /// The live countdown, or nil when not counting down.
    private var countdown: (remaining: Int, action: MulticamTimedAction)?
    /// The countdown tick interval — injectable so tests don't wait real seconds.
    private var timerTickInterval: TimeInterval = 1
    private nonisolated let timerTask = Locked<Task<Void, Never>?>(nil)

    private weak var display: MulticamDisplay?

    /// One preview-frame sink per lane, keyed by peer. The view controller
    /// registers one when it creates a lane; `handleFrame` routes each frame to
    /// its source's sink. Cleared when the link is dropped.
    private var frameSinks: [MCPeerID: MulticamFrameSink] = [:]

    /// The interval between clock-offset refreshes per camera.
    private let clockSyncInterval: TimeInterval = 30
    /// How far ahead a re-invite waits before re-browsing a dropped camera.
    private var reconnectRetryDelay: TimeInterval = 3
    private let reconnectInviteTimeout: TimeInterval = 10

    // MARK: Test / wiring seams

    func needsRematchForTesting(_ peer: MCPeerID) -> Bool { links[peer]?.needsQualityRematch ?? false }

    func setDisplay(_ display: MulticamDisplay) {
        self.display = display
        // Pre-pump setup: replay the current state directly (no pump epilogue
        // to flush a dirty flag). The display is wired after `install`, so the
        // first snapshot emitted during install would otherwise reach no one.
        publishRigSettingsNow()
        publishLanesNow()
    }
    func setReconnectRetryDelay(_ delay: TimeInterval) { reconnectRetryDelay = delay }

    /// Register (or replace) the preview-frame sink for a lane. Called by the
    /// view controller when it creates the lane; the sink is dropped when the
    /// link goes away (`handleRemoveCamera`).
    func setFrameSink(for peer: MCPeerID, _ sink: @escaping MulticamFrameSink) {
        frameSinks[peer] = sink
    }

    /// Test support.
    func lanesForTesting() -> [MulticamLaneInfo] { laneSnapshot() }
    func focusedPeerForTesting() -> MCPeerID? { focusedPeer }
    func statusForTesting(_ peer: MCPeerID) -> CameraLink.Status? { links[peer]?.status }
    func offsetForTesting(_ peer: MCPeerID) -> Int64? { links[peer]?.latestOffset?.offsetMillis }

    // MARK: - Handoff

    /// Take over a transport the scanner already connected to `initialPeers`.
    /// Becomes the transport delegate (the scanner's `SessionCoordinator`
    /// stops receiving callbacks from here on), seeds a lane per peer, kicks
    /// the capability handshake + clock sync, and keeps browsing so more
    /// cameras can be invited later.
    func install(transport: any MultipeerServiceProtocol,
                 initialPeers: [MCPeerID],
                 mode: MonitorMode) {
        multipeerService = transport
        transportShared.value = transport
        transport.delegate = self
        state = .monitoring(mode: mode)

        for peer in initialPeers where links[peer] == nil {
            order.append(peer)
            links[peer] = CameraLink(peerID: peer)
        }
        focusedPeer = focusedPeer ?? order.first

        // Keep discovering so the in-session "add camera" flow (PR7) has a
        // live peer list; a director that stopped browsing on connect could
        // never grow the rig.
        transport.startBrowsingOnly()

        for peer in order { beginHandshake(with: peer) }
        startClockSyncLoop()
        publishLanesNow() // pre-pump setup
    }

    /// The initial per-camera handshake: announce the director role (carries
    /// our version so the camera can gate us) and ask for capabilities. The
    /// camera answers with `CameraCapabilitiesResp`, at which point the lane
    /// goes live and its frame pump starts.
    private func beginHandshake(with peer: MCPeerID) {
        sendTo(peer, RemoteCmd.PeerBecameMonitor.createWithDefaults())
        sendTo(peer, RemoteCmd.RequestCameraCapabilities())
        // Prime the stream: the camera streams once it holds a frame credit.
        sendTo(peer, RemoteCmd.RequestFrame(sender: nil))
    }

    // MARK: - Message handling

    /// Derived publishing: handlers mark what changed instead of pushing to the
    /// UI themselves, and the pump flushes at most one lanes-publish and one
    /// rig-publish per message — so multiple mutations coalesce into one main hop.
    private var lanesDirty = false
    private var rigDirty = false
    private func markLanesDirty() { lanesDirty = true }
    private func markRigDirty() { rigDirty = true }

    func handle(_ msg: Message) async {
        await route(msg)
        if lanesDirty { lanesDirty = false; publishLanesNow() }
        if rigDirty { rigDirty = false; publishRigSettingsNow() }
    }

    private func route(_ msg: Message) async {
        switch msg {
        case let connected as OnConnectToDevice:
            handlePeerConnected(connected.peer)

        case let disconnected as DisconnectPeer:
            if let peer = disconnected.peer { handlePeerDisconnected(peer) }

        case let found as UICmd.BrowserFoundPeer:
            handleBrowserFound(found.peer)

        case let lost as UICmd.BrowserLostPeer:
            if available.remove(lost.peer) != nil {
                availableOrder.removeAll { $0 == lost.peer }
                publishAvailable()
            }

        case let routed as RoutedMessage:
            await handleRouted(routed.message, from: routed.peer)

        case let frame as RemoteCmd.OnFrame:
            handleFrame(frame)

        case let started as ResourceTransferStarted:
            handleResourceStarted(started)

        case let finished as ResourceTransferFinished:
            handleResourceFinished(finished)

        case let measured as ClockPongMeasured:
            storePong(measured.pong, t3: measured.t3, from: measured.peer)

        // --- UI commands (single-entry inbox) ---
        case is MCToggleFocusedCamera: handleToggleFocusedCamera()
        case is MCToggleTorch: handleToggleTorch()
        case is MCToggleFlash: handleToggleFlash()
        case let z as MCSetZoom: handleSetZoom(z.factor)
        case is MCCapturePhoto: handleCapturePhoto()
        case is MCStartRecording: handleStartRecording()
        case is MCStopRecording: handleStopRecording()
        case is MCAutomaticVideoQuality: handleAutomaticVideoQuality()
        case is MCAutomaticPhotoQuality: handleAutomaticPhotoQuality()
        case is MCTimerAdvance: advanceCountdown()
        case let q as MCSetVideoQuality: handleSetVideoQuality(resolution: q.resolution, frameRate: q.frameRate)
        case let q as MCSetPhotoQuality: handleSetPhotoQuality(format: q.format, hdr: q.hdr)
        case let t as MCSetRigTimer: handleSetRigTimer(t.seconds)
        case let c as MCPeerCommand:
            switch c.kind {
            case .focus: handleSetFocusedPeer(c.peer)
            case .invite: handleInviteCamera(c.peer)
            case .remove: handleRemoveCamera(c.peer)
            case .disconnect: handleDisconnectCamera(c.peer)
            case .retryCollection: handleRetryCollection(c.peer)
            case .nudgeFrame: handleNudgeFrame(c.peer)
            case .requestKeyframe: handleRequestKeyframe(c.peer)
            case .reconnectTick: reBrowseIfStillMissing(c.peer)
            }

        case is UICmd.AppForegrounded:
            // Clocks freeze while backgrounded; the estimates are stale. Drop
            // them and re-measure, mirroring the frame path's foreground rearm.
            for link in links.values { link.clockEstimator.reset() }
            pingClocks()

        default:
            break
        }
    }

    /// A camera-addressed message that arrived with its source peer (Seam A).
    private func handleRouted(_ message: Message, from peer: MCPeerID) async {
        guard let link = links[peer] else { return }

        switch message {
        case let became as RemoteCmd.PeerBecameCamera:
            // Same-major-or-refuse, per camera. A refused camera is dropped
            // from the rig rather than silently streaming a peer we can't
            // fully drive.
            if !isPeerCompatible(became) {
                link.status = .failed
                markLanesDirty()
            }

        case let caps as RemoteCmd.CameraCapabilitiesResp:
            link.capabilities = caps
            seedZoom(link, from: caps)
            if link.status != .failed { link.status = .linked }
            // A late joiner may not match the running rig quality: flag it (its
            // tile badges + the tray offers re-match) rather than silently
            // changing the rig. Also refreshes the intersection menu.
            refreshRematchFlags()
            markLanesDirty()
            markRigDirty()
            // A multicam-capable camera gets an immediate clock probe so its
            // offset is ready well before the first synced capture (PR4), and
            // its preview tier (full if focused, else thumbnail).
            if link.supportsMulticam {
                sendTo(peer, RemoteCmd.ClockSyncPing(t0Millis: SyncClock.nowMillis()))
                pushProfile(to: peer)
            }

        case let resp as RemoteCmd.ToggleCameraResp:
            // The focused camera flipped front/back (or picked a device — the
            // response type is shared). Its refreshed capabilities carry the
            // new position, lenses and zoom, so the lane's controls reflect it.
            if let caps = resp.cameraCapabilities {
                link.capabilities = caps
                seedZoom(link, from: caps)
            }
            refreshRematchFlags()
            markLanesDirty()
            markRigDirty()

        case let resp as RemoteCmd.SetZoomResp:
            // The focused camera settled on a zoom; reflect its factor and range
            // on that lane so the pill's thumb and ceiling track the hardware.
            if let factor = resp.zoomFactor { link.zoomFactor = factor }
            if let maxZoom = resp.zoomRange?.maxZoom {
                link.maxZoomFactor = ZoomScaleSeed.clampMaxZoom(maxZoom, wideAngle: link.wideAngleZoomFactor)
            }
            markLanesDirty()

        case let ack as RemoteCmd.ScheduledCaptureAck:
            resolvePhotoAck(from: peer, success: ack.error == nil)

        case is RemoteCmd.TakePicAck:
            // The fallback (plain TakePic) path's positive ack.
            resolvePhotoAck(from: peer, success: true)

        case let resp as RemoteCmd.TakePicResp:
            if resp.error != nil {
                resolvePhotoAck(from: peer, success: false)
            } else if let pic = resp.pic {
                // Auto-collect: the camera returned its (EXIF-stamped) still.
                // Save it to the director's library under the shared RS_ name.
                collectPhoto(pic, from: peer)
            }

        case let ack as RemoteCmd.ScheduledRecordingAck:
            resolveRecordingAck(from: peer, isStop: ack.isStop, success: ack.error == nil)

        case let ack as RemoteCmd.StartRecordingVideoAck:
            // The fallback (plain StartRecordingVideo) path's positive ack.
            if ack.error == nil { resolveRecordingAck(from: peer, isStop: false, success: true) }

        default:
            // Per-camera command responses (zoom/lens/flash/torch acks) update
            // only the focused lane's controls, wired to the UI in a later PR;
            // PR3 surfaces frames + status, so these are accepted and ignored.
            break
        }
    }

    private func handlePeerConnected(_ peer: MCPeerID) {
        if let existing = links[peer] {
            // A reconnecting lane came back — rehandshake and relight it.
            existing.status = .linked
        } else {
            order.append(peer)
            links[peer] = CameraLink(peerID: peer)
        }
        // It's in the rig now, so it's no longer an "available" candidate.
        if available.remove(peer) != nil {
            availableOrder.removeAll { $0 == peer }
            publishAvailable()
        }
        focusedPeer = focusedPeer ?? peer
        syncFocusFlags()
        beginHandshake(with: peer)
        markLanesDirty()
    }

    /// Mirror `focusedPeer` onto each lane's `isFocused` so `CameraLink.snapshot`
    /// stays the single source of truth for the tile.
    private func syncFocusFlags() {
        for (peer, link) in links { link.isFocused = (peer == focusedPeer) }
    }

    private func publishAvailable() {
        let peers = availableOrder
        let display = display
        OperationQueue.main.addOperation { display?.applyAvailablePeers(peers) }
    }

    private func handlePeerDisconnected(_ peer: MCPeerID) {
        guard let link = links[peer] else { return }
        // Degrade the tile, keep the rest of the rig recording/monitoring. The
        // controller stays browsing, so `browserDidFindPeer` re-invites.
        link.status = .reconnecting
        markLanesDirty()
        armReconnect(peer)
    }

    private func handleBrowserFound(_ peer: MCPeerID) {
        // A camera we are actively missing is auto-re-invited.
        if let link = links[peer], link.status == .reconnecting {
            multipeerService?.invitePeer(peer, timeout: reconnectInviteTimeout)
            return
        }
        // An unrelated fresh peer becomes a candidate for the "add camera"
        // sheet — it never auto-joins.
        guard links[peer] == nil, !available.contains(peer) else { return }
        available.insert(peer)
        availableOrder.append(peer)
        publishAvailable()
    }

    /// Invite a discovered camera into the rig (the "add camera" flow). The
    /// tier cap is enforced by the UI before this is called.
    public nonisolated func inviteCamera(_ peer: MCPeerID) { tell(MCPeerCommand(.invite, peer)) }

    private func handleInviteCamera(_ peer: MCPeerID) {
        guard available.contains(peer) else { return }
        multipeerService?.invitePeer(peer, timeout: reconnectInviteTimeout)
    }

    /// The current number of cameras in the rig — a pure query the UI reads
    /// (directly, not through the inbox) to gate the add-camera paywall.
    func cameraCount() -> Int { order.count }

    /// Schedule a reconnect tick; the tick itself runs in the pump (ordered),
    /// so the only thing off-actor is the one-shot sleep.
    private func armReconnect(_ peer: MCPeerID) {
        let delay = reconnectRetryDelay
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self?.tell(MCPeerCommand(.reconnectTick, peer))
        }
    }

    private func reBrowseIfStillMissing(_ peer: MCPeerID) {
        guard links[peer]?.status == .reconnecting else { return }
        // Rebuild the browse so the lost peer is re-reported at a live address.
        multipeerService?.startBrowsingOnly()
    }

    private func handleFrame(_ frame: RemoteCmd.OnFrame) {
        guard let link = links[frame.peerId] else { return }
        if frame.codec == .vp9 { link.sawVP9 = true }
        // Route to exactly this lane's decoder (rendering isolation), then ack
        // only this camera so its credit window advances and no other camera
        // sends on a frame it didn't produce (Seam B).
        frameSinks[frame.peerId]?(frame)
        sendTo(frame.peerId, RemoteCmd.RequestFrame(sender: nil))
    }

    // MARK: - Per-camera controls (focused peer only)

    /// Framing controls address the focused camera. Each is a message on the
    /// single inbox, like every other UI intent.
    public nonisolated func setZoom(_ factor: CGFloat) { tell(MCSetZoom(factor)) }
    public nonisolated func toggleTorch() { tell(MCToggleTorch()) }
    public nonisolated func toggleFlash() { tell(MCToggleFlash()) }

    private func handleSetZoom(_ factor: CGFloat) { focusedSend(RemoteCmd.SetZoom(zoomFactor: factor)) }

    private func handleToggleTorch() {
        guard let peer = focusedPeer, let link = links[peer] else { return }
        // Optimistic: reflect the tap immediately so the glyph tints like the
        // 1:1 monitor's; the camera is the source of truth for whether it took.
        link.torchOn.toggle()
        sendTo(peer, RemoteCmd.ToggleTorch())
        markLanesDirty()
    }

    private func handleToggleFlash() {
        guard let peer = focusedPeer, let link = links[peer] else { return }
        link.flashOn.toggle()
        sendTo(peer, RemoteCmd.ToggleFlash())
        markLanesDirty()
    }

    /// Disconnect one camera from the rig: a purposeful goodbye (`EndSession`)
    /// to that peer only, then drop its lane and refocus. Disconnecting the
    /// last camera leaves the director screen.
    public nonisolated func disconnectCamera(_ peer: MCPeerID) { tell(MCPeerCommand(.disconnect, peer)) }

    private func handleDisconnectCamera(_ peer: MCPeerID) {
        guard links[peer] != nil else { return }
        sendTo(peer, RemoteCmd.EndSession())
        handleRemoveCamera(peer)
        if order.isEmpty {
            let display = display
            OperationQueue.main.addOperation { display?.exitMulticam() }
        }
    }

    /// Flip the focused camera between front and back. Framing is per-camera,
    /// so only the focused peer flips; `ToggleCameraResp` carries its refreshed
    /// capabilities back to that lane.
    public nonisolated func toggleFocusedCamera() { tell(MCToggleFocusedCamera()) }

    private func handleToggleFocusedCamera() {
        // Sent whenever a camera is focused and linked — the camera decides
        // whether a flip does anything, exactly as in the 1:1 monitor. Never
        // gated on advertised positions (the payload doesn't reliably carry
        // both), which was why the button read as disabled on device.
        guard let peer = focusedPeer, links[peer]?.status == .linked else { return }
        sendTo(peer, RemoteCmd.ToggleCamera())
    }

    func focusAtPoint(x: Float, y: Float) {
        guard let peer = focusedPeer, links[peer]?.capabilities?.supportsFocusPoint == true else { return }
        sendTo(peer, RemoteCmd.FocusAtPoint(x: x, y: y))
    }

    func switchLens(_ lens: CameraLensType) { focusedSend(RemoteCmd.SwitchLens(lensType: lens)) }

    public nonisolated func setFocusedPeer(_ peer: MCPeerID) { tell(MCPeerCommand(.focus, peer)) }

    private func handleSetFocusedPeer(_ peer: MCPeerID) {
        guard links[peer] != nil else { return }
        focusedPeer = peer
        syncFocusFlags()
        // Retier previews: the newly focused camera goes full-size, the rest
        // (including the one that just lost focus) drop to thumbnail.
        for p in order { pushProfile(to: p) }
        markLanesDirty()
    }

    /// The preview tier a camera should be on: full for the focused lane,
    /// thumbnail for the rest.
    private func desiredProfile(for peer: MCPeerID) -> StreamProfile {
        peer == focusedPeer ? .focused : .thumbnail
    }

    /// Push a camera its preview profile, but only when it actually changes —
    /// and only to a multicam-capable peer (an old peer would misread the
    /// unknown action).
    private func pushProfile(to peer: MCPeerID) {
        guard let link = links[peer], link.supportsMulticam else { return }
        let profile = desiredProfile(for: peer)
        guard link.lastSentProfile != profile else { return }
        link.lastSentProfile = profile
        sendTo(peer, RemoteCmd.SetStreamProfile(
            maxLongEdge: Int(profile.maxLongEdge),
            bitrateKbps: Int(profile.bitrateKbps),
            fps: Int(profile.fps)))
    }

    /// Logically remove a camera from the rig. The QUIC session has no
    /// per-peer teardown, so this stops the lane (no more acks/handshakes) and
    /// drops it from the UI; the peer times out on its side. A true per-peer
    /// disconnect needs a transport API and is out of scope here.
    public nonisolated func removeCamera(_ peer: MCPeerID) { tell(MCPeerCommand(.remove, peer)) }

    private func handleRemoveCamera(_ peer: MCPeerID) {
        links[peer] = nil
        frameSinks[peer] = nil
        order.removeAll { $0 == peer }
        if focusedPeer == peer { focusedPeer = order.first; syncFocusFlags() }
        markLanesDirty()
    }

    private func focusedSend(_ msg: Message) {
        guard let peer = focusedPeer else { return }
        sendTo(peer, msg)
    }

    /// Seed a lane's zoom scale from a capabilities exchange via the shared
    /// `ZoomScaleSeed` — the same values the 1:1 monitor derives.
    private func seedZoom(_ link: CameraLink, from caps: RemoteCmd.CameraCapabilitiesResp) {
        guard let seed = ZoomScaleSeed.seed(from: caps) else { return }
        link.zoomStops = seed.zoomStops
        link.wideAngleZoomFactor = seed.wideAngleZoomFactor
        link.zoomFactor = seed.zoomFactor
        if let maxZoom = seed.maxZoomFactor { link.maxZoomFactor = maxZoom }
    }

    // MARK: - Synced photo capture (all cameras)

    /// Test seams.
    func setCaptureAckTimeout(_ t: TimeInterval) { captureAckTimeout = t }
    func captureStateForTesting() -> (id: String, remaining: Int)? {
        if case .capturingPhoto(let id, let remaining) = state { return (id, remaining) }
        return nil
    }
    func recordingStateForTesting() -> (id: String, remaining: Int)? {
        if case .recording(let id, let remaining) = state { return (id, remaining) }
        return nil
    }
    func stoppingStateForTesting() -> (id: String, remaining: Int)? {
        if case .stoppingRecording(let id, let remaining) = state { return (id, remaining) }
        return nil
    }
    func captureOutcomeForTesting(_ peer: MCPeerID) -> CaptureOutcome? { links[peer]?.captureOutcome }
    func isRecordingForTesting(_ peer: MCPeerID) -> Bool { links[peer]?.isRecording ?? false }
    func availablePeersForTesting() -> [MCPeerID] { availableOrder }
    func cameraCountForTesting() -> Int { order.count }

    /// Test seam: put a lane in the state a real handshake would — linked, with
    /// known multicam capability and (optionally) a known clock offset — so
    /// capture behavior can be asserted deterministically.
    func seedLaneForTesting(_ peer: MCPeerID, supportsMulticam: Bool, offsetMillis: Int64?) {
        guard let link = links[peer] else { return }
        link.status = .linked
        link.capabilities = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil, currentCamera: .back,
            currentLens: .wideAngle, currentZoom: 1.0,
            supportsMulticam: supportsMulticam, error: nil)
        if let offsetMillis {
            // t0 == t3 == 0 → rtt 0, midpoint 0, so offset == cameraClock.
            link.clockEstimator.recordExchange(
                t0Millis: 0, cameraClockMillis: UInt64(bitPattern: offsetMillis), t3Millis: 0)
        }
    }

    /// The ready multicam cameras, in strip order.
    private func readyMulticamLanes() -> [CameraLink] {
        order.compactMap { links[$0] }.filter { $0.status == .linked && $0.supportsMulticam }
    }

    /// Send a scheduled command to each ready camera at a shared instant, each
    /// translated into that camera's own clock by its offset. Returns the
    /// captureID and the lanes addressed. `build` makes the per-lane message.
    private func fanOutScheduled(
        _ build: (_ fireAtCameraClock: UInt64, _ anchor: UInt64, _ captureID: String,
                  _ index: Int) -> Message,
        fallback: (CameraLink) -> Message,
        lanes: [CameraLink]) -> String {
        let captureID = UUID().uuidString
        capturingLanes = Set(lanes.map(\.peerID))
        currentCaptureID = captureID
        lastCaptureID = captureID
        for link in lanes { link.collection = .idle }

        if lanes.allSatisfy({ $0.latestOffset != nil }) {
            let fireAt = SyncClock.nowMillis() + captureLeadMillis
            for (index, link) in lanes.enumerated() {
                let offset = link.latestOffset?.offsetMillis ?? 0
                let fireAtCameraClock = UInt64(Int64(fireAt) + offset)
                sendTo(link.peerID, build(fireAtCameraClock, fireAt, captureID, index + 1))
            }
        } else {
            // A missing offset means we can't promise a sub-frame instant — fire
            // now on each camera, under the same shot id.
            for link in lanes { sendTo(link.peerID, fallback(link)) }
        }
        return captureID
    }

    /// Fire a synced photo on every ready multicam camera. If the rig timer is
    /// set, run one director-side countdown first (fanned out so subjects see
    /// it), then fire. Scheduled at a shared instant when every clock offset is
    /// known; else a plain `TakePic` fan-out. No-op unless idle with a camera.
    public nonisolated func capturePhoto() { tell(MCCapturePhoto()) }

    private func handleCapturePhoto() {
        guard rigTimerSeconds > 0 else { performCapturePhoto(); return }
        beginCountdown(.photo)
    }

    private func performCapturePhoto() {
        guard case .monitoring = state else { return }
        let ready = readyMulticamLanes()
        guard !ready.isEmpty else { return }
        for link in ready { link.captureOutcome = nil }

        let captureID = fanOutScheduled(
            { fire, anchor, id, index in
                RemoteCmd.ScheduledCapture(fireAtCameraClockMillis: fire, anchorMillis: anchor,
                                           captureId: id, sessionId: self.sessionID, cameraIndex: index)
            },
            fallback: { _ in RemoteCmd.TakePic(sender: nil, sendMediaToPeer: false) },
            lanes: ready)

        state = .capturingPhoto(captureId: captureID, acksRemaining: capturingLanes.count)
        markLanesDirty()
        armAckTimeout(captureID)
    }

    /// Start a synced recording on every ready multicam camera (timer-gated).
    public nonisolated func startRecording() { tell(MCStartRecording()) }

    private func handleStartRecording() {
        guard rigTimerSeconds > 0 else { performStartRecording(); return }
        beginCountdown(.record)
    }

    private func performStartRecording() {
        guard case .monitoring = state else { return }
        let ready = readyMulticamLanes()
        guard !ready.isEmpty else { return }
        for link in ready { link.captureOutcome = nil }

        let captureID = fanOutScheduled(
            { fire, anchor, id, index in
                RemoteCmd.ScheduledStartRecording(fireAtCameraClockMillis: fire, anchorMillis: anchor,
                                                  captureId: id, sessionId: self.sessionID, cameraIndex: index)
            },
            fallback: { _ in RemoteCmd.StartRecordingVideo(sender: nil) },
            lanes: ready)

        state = .recording(captureId: captureID, acksRemaining: capturingLanes.count)
        markLanesDirty()
        armAckTimeout(captureID)
    }

    /// Stop the synced recording on every rolling camera, anchored so the clips
    /// end together.
    public nonisolated func stopRecording() { tell(MCStopRecording()) }

    private func handleStopRecording() {
        guard case .recording(_, _) = state else { return }
        let rolling = order.compactMap { links[$0] }.filter { $0.isRecording }
        guard !rolling.isEmpty else { return }

        let captureID = fanOutScheduled(
            { fire, anchor, id, index in
                RemoteCmd.ScheduledStopRecording(fireAtCameraClockMillis: fire, anchorMillis: anchor,
                                                 captureId: id, sessionId: self.sessionID, cameraIndex: index)
            },
            fallback: { _ in RemoteCmd.StopRecordingVideo(sender: nil, sendMediaToPeer: false) },
            lanes: rolling)

        state = .stoppingRecording(captureId: captureID, acksRemaining: capturingLanes.count)
        markLanesDirty()
        armAckTimeout(captureID)
    }

    // MARK: - Rig-wide quality ("the shot belongs to the rig")

    /// Test seams.
    func setTimerTickInterval(_ t: TimeInterval) { timerTickInterval = t }
    /// Advance the rig countdown one tick deterministically (production uses the
    /// one-shot Task; tests set a large interval and drive with this instead).
    func advanceTimerForTesting() { advanceCountdown() }
    func countdownRemainingForTesting() -> Int? { countdown?.remaining }
    func activeVideoQualityForTesting() -> (VideoResolution, VideoFrameRate)? {
        activeVideoQuality.map { ($0.resolution, $0.frameRate) }
    }
    func rigTimerForTesting() -> Int { rigTimerSeconds }

    /// The current rig quality menu, computed from every connected lane's
    /// current-camera capabilities (the intersection model).
    func rigQualityMenu() -> RigQualityMenu {
        let menuLanes: [RigQualityMenu.Lane] = order.enumerated().compactMap { index, peer in
            guard let link = links[peer], link.status != .failed,
                  let info = link.capabilities?.getCurrentCameraInfo() else { return nil }
            return RigQualityMenu.Lane(name: link.displayName.isEmpty ? "Camera \(index + 1)" : link.displayName,
                                       info: info)
        }
        return RigQualityMenu(lanes: menuLanes)
    }

    /// Manual video pick — fans the chosen quality to every lane and records it
    /// as the active rig setting (first-class; not a mode you leave).
    public nonisolated func setVideoQuality(resolution: VideoResolution, frameRate: VideoFrameRate) {
        tell(MCSetVideoQuality(resolution, frameRate))
    }

    private func handleSetVideoQuality(resolution: VideoResolution, frameRate: VideoFrameRate) {
        activeVideoQuality = (resolution, frameRate)
        for peer in order {
            sendTo(peer, RemoteCmd.SetVideoQuality(resolution: resolution, frameRate: frameRate))
        }
        refreshRematchFlags()
        markLanesDirty()
    }

    public nonisolated func setPhotoQuality(format: PhotoFormat, hdr: HDRMode) {
        tell(MCSetPhotoQuality(format, hdr))
    }

    private func handleSetPhotoQuality(format: PhotoFormat, hdr: HDRMode) {
        activePhotoQuality = (format, hdr)
        for peer in order {
            sendTo(peer, RemoteCmd.SetPhotoQuality(format: format, hdrMode: hdr))
        }
        markLanesDirty()
    }

    /// "Automatic" / re-match: recompute best-in-intersection and apply it.
    public nonisolated func applyAutomaticVideoQuality() { tell(MCAutomaticVideoQuality()) }

    private func handleAutomaticVideoQuality() {
        let auto = rigQualityMenu().automaticVideo()
        handleSetVideoQuality(resolution: auto.resolution, frameRate: auto.frameRate)
    }

    public nonisolated func applyAutomaticPhotoQuality() { tell(MCAutomaticPhotoQuality()) }

    private func handleAutomaticPhotoQuality() {
        let auto = rigQualityMenu().automaticPhoto()
        handleSetPhotoQuality(format: auto.format, hdr: auto.hdr)
    }

    /// After caps change (new lane, device switch), flag any lane that can't
    /// honor the running rig video setting — its tile is badged and the tray
    /// offers a re-match. Never silently changes the rig.
    private func refreshRematchFlags() {
        guard let active = activeVideoQuality else { return }
        let menu = rigQualityMenu()
        for peer in order {
            guard let link = links[peer], let info = link.capabilities?.getCurrentCameraInfo() else { continue }
            let lane = RigQualityMenu.Lane(name: link.displayName, info: info)
            link.needsQualityRematch = !menu.laneCanMatch(
                lane, resolution: active.resolution, frameRate: active.frameRate)
        }
    }

    // MARK: - Rig self-timer (inbox-driven countdown)

    public nonisolated func setRigTimer(_ seconds: Int) { tell(MCSetRigTimer(max(0, seconds))) }

    private func handleSetRigTimer(_ seconds: Int) {
        rigTimerSeconds = seconds
        markRigDirty()
    }

    /// Begin a director-side countdown, fanned out to every camera so subjects
    /// see it, then fire the synced capture at zero. Each tick is a `tell` on
    /// the inbox (so it is ordered with everything else and visible to
    /// `waitForIdle`); the only Task is a one-shot sleep between ticks.
    private func beginCountdown(_ action: MulticamTimedAction) {
        countdown = (remaining: rigTimerSeconds, action: action)
        fanOutTimerTick(rigTimerSeconds)
        scheduleNextTick()
    }

    /// Advance one tick (pump-driven). Fires the capture at zero.
    private func advanceCountdown() {
        guard let c = countdown else { return }
        let remaining = c.remaining - 1
        fanOutTimerTick(remaining)
        if remaining > 0 {
            countdown = (remaining: remaining, action: c.action)
            scheduleNextTick()
        } else {
            countdown = nil
            switch c.action {
            case .photo: performCapturePhoto()
            case .record: performStartRecording()
            }
        }
    }

    /// One-shot: after `timerTickInterval`, enqueue the next tick. Production
    /// only — tests drive `advanceCountdown` directly via `advanceTimerForTesting`.
    private func scheduleNextTick() {
        let interval = timerTickInterval
        timerTask.value?.cancel()
        timerTask.value = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            self?.tell(MCTimerAdvance())
        }
    }

    private func fanOutTimerTick(_ remaining: Int) {
        for peer in order { sendTo(peer, RemoteCmd.TimerCountdown(value: remaining)) }
        markRigDirty() // the countdown value is read from `countdown` state at publish
    }

    private func publishRigSettingsNow() {
        let menu = rigQualityMenu()
        let snapshot = RigSettingsSnapshot(
            timerSeconds: rigTimerSeconds,
            countdown: countdown?.remaining,
            activeVideo: activeVideoQuality.map {
                RigVideoSelection(resolution: $0.resolution, frameRate: $0.frameRate)
            },
            videoOptions: menu.videoPickerOptions(),
            heifAvailable: menu.supportsHEIF(),
            hdrAvailable: menu.supportsHDR(),
            heifBlockedBy: menu.lanesBlockingHEIF(),
            hdrBlockedBy: menu.lanesBlockingHDR(),
            activePhotoFormat: activePhotoQuality?.format,
            activeHDR: activePhotoQuality?.hdr)
        let display = display
        OperationQueue.main.addOperation { display?.applyRigSettings(snapshot) }
    }

    // MARK: Ack aggregation (shared across photo / start / stop)

    private func resolvePhotoAck(from peer: MCPeerID, success: Bool) {
        guard case .capturingPhoto = state, capturingLanes.contains(peer) else { return }
        links[peer]?.captureOutcome = success ? .captured : .failed
        finishLane(peer)
    }

    private func resolveRecordingAck(from peer: MCPeerID, isStop: Bool, success: Bool) {
        switch state {
        case .recording where !isStop:
            guard capturingLanes.contains(peer) else { return }
            if success { links[peer]?.isRecording = true } else { links[peer]?.captureOutcome = .failed }
            finishLane(peer)
        case .stoppingRecording where isStop:
            guard capturingLanes.contains(peer) else { return }
            links[peer]?.isRecording = false
            finishLane(peer)
        default:
            break
        }
    }

    /// Count one lane's answer and advance the aggregate. A photo or a stop
    /// that empties the set returns to monitoring; a start that empties it
    /// stays `.recording` (the rig is now rolling).
    private func finishLane(_ peer: MCPeerID) {
        capturingLanes.remove(peer)
        let remaining = capturingLanes.count
        switch state {
        case .capturingPhoto(let id, _):
            state = remaining == 0 ? .monitoring(mode: .photo) : .capturingPhoto(captureId: id, acksRemaining: remaining)
        case .recording(let id, _):
            state = .recording(captureId: id, acksRemaining: remaining)
        case .stoppingRecording(let id, _):
            state = remaining == 0 ? .monitoring(mode: .photo) : .stoppingRecording(captureId: id, acksRemaining: remaining)
        case .monitoring:
            break
        }
        markLanesDirty()
    }

    private func armAckTimeout(_ captureID: String) {
        let timeout = captureAckTimeout
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard let self else { return }
            await self.expireAcks(captureID)
        }
    }

    /// Any camera silent past the deadline is settled so the aggregate always
    /// resolves: a silent photo lane failed; a silent start lane failed (not
    /// rolling); a silent stop lane is forced stopped.
    private func expireAcks(_ captureID: String) {
        let matches: Bool
        switch state {
        case .capturingPhoto(let id, _), .recording(let id, _), .stoppingRecording(let id, _):
            matches = id == captureID
        case .monitoring:
            matches = false
        }
        guard matches else { return }

        for peer in capturingLanes {
            switch state {
            case .capturingPhoto: links[peer]?.captureOutcome = .failed
            case .recording: links[peer]?.captureOutcome = .failed
            case .stoppingRecording: links[peer]?.isRecording = false
            case .monitoring: break
            }
        }
        capturingLanes.removeAll()
        currentCaptureID = nil
        switch state {
        case .recording(let id, _):
            state = .recording(captureId: id, acksRemaining: 0) // rolling, start acks settled
        default:
            state = .monitoring(mode: .photo)
        }
        markLanesDirty()
    }

    // MARK: - Auto-collect (footage back to the director)

    /// Test seams.
    func collectionStateForTesting(_ peer: MCPeerID) -> CameraLink.LaneCollectionState? { links[peer]?.collection }

    /// The lane's 1-based index, for the shared RS_ filename group.
    private func cameraIndex(of peer: MCPeerID) -> Int {
        (order.firstIndex(of: peer) ?? 0) + 1
    }

    private func rigMetadata(for peer: MCPeerID) -> CaptureSyncMetadata {
        CaptureSyncMetadata(
            sessionID: sessionID, captureID: lastCaptureID ?? UUID().uuidString,
            cameraIndex: cameraIndex(of: peer), anchorMillis: 0,
            clockOffsetMillis: 0, roundTripMillis: 0)
    }

    /// Save a camera's returned still (already EXIF-stamped on the camera) to
    /// the director's library under the shared RS_ name, and mark the lane
    /// collected.
    private func collectPhoto(_ data: Data, from peer: MCPeerID) {
        guard let link = links[peer] else { return }
        let name = rigMetadata(for: peer).photoFilename(isHEIC: Self.isHEIC(data))
        link.collection = .collected
        markLanesDirty()
        Self.savePhotoToLibrary(data, originalFilename: name)
    }

    private func handleResourceStarted(_ started: ResourceTransferStarted) {
        guard let link = links[started.peer] else { return }
        link.collection = .transferring(0)
        markLanesDirty()
    }

    private func handleResourceFinished(_ finished: ResourceTransferFinished) {
        guard let link = links[finished.peer] else {
            // No lane owns this transfer any more (camera removed mid-flight);
            // still delete the temp file the transport handed us.
            finished.localURL.map(Self.discardTempFile)
            return
        }
        guard finished.error == nil, let localURL = finished.localURL else {
            // Footage is still safe on the camera; the tile offers a retry. Any
            // partial temp file is ours to clean up.
            finished.localURL.map(Self.discardTempFile)
            link.collection = .failed
            markLanesDirty()
            return
        }
        link.collection = .collected
        markLanesDirty()
        // The resource is named with the RS_ filename by the camera, so save it
        // under that; QuickTime sync metadata rides inside the .mov itself. The
        // controller owns `localURL` until `saveVideoToLibrary` either moves it
        // into the library or deletes it.
        Self.saveVideoToLibrary(at: localURL, originalFilename: finished.name)
    }

    /// The transport hands the director a temp file per received clip; the
    /// controller owns it and must not leak it on any path that doesn't move it
    /// into the photo library.
    private static func discardTempFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Re-request a failed lane's footage (the camera still holds it).
    public nonisolated func retryCollection(for peer: MCPeerID) { tell(MCPeerCommand(.retryCollection, peer)) }

    private func handleRetryCollection(_ peer: MCPeerID) {
        guard let link = links[peer], link.collection == .failed else { return }
        link.collection = .transferring(0)
        markLanesDirty()
        sendTo(peer, RemoteCmd.RequestVideoResend(captureId: lastCaptureID ?? ""))
    }

    private static func isHEIC(_ data: Data) -> Bool {
        data.count > 12 && data[4] == 0x66 && data[5] == 0x74 && data[6] == 0x79 && data[7] == 0x70
    }

    private static func savePhotoToLibrary(_ data: Data, originalFilename: String) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else { return }
            PHPhotoLibrary.shared().performChanges({
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = originalFilename
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: options)
            }, completionHandler: { ok, _ in
                print(ok ? "Director collected photo \(originalFilename)" : "collect photo failed")
            })
        }
    }

    private static func saveVideoToLibrary(at url: URL, originalFilename: String) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                discardTempFile(url) // never authorized to import — don't leak it
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = true
                options.originalFilename = originalFilename
                PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: options)
            }, completionHandler: { ok, _ in
                // `shouldMoveFile` consumes the file only on success; on failure
                // it stays behind, so the owner removes it.
                if !ok { discardTempFile(url) }
                print(ok ? "Director collected clip \(originalFilename)" : "collect clip failed")
            })
        }
    }

    /// A lane's stall watchdog fired — re-request a frame to unstick just that
    /// camera's pump (the others are unaffected).
    public nonisolated func nudgeFrame(for peer: MCPeerID) { tell(MCPeerCommand(.nudgeFrame, peer)) }

    private func handleNudgeFrame(_ peer: MCPeerID) {
        guard links[peer] != nil else { return }
        sendTo(peer, RemoteCmd.RequestFrame(sender: nil))
    }

    /// A lane's decoder desynced — force a keyframe, but only from a camera
    /// that has proven it speaks VP9 (else an old peer reads the unknown
    /// action as TakePicture). Mirrors the 1:1 `requestKeyframeIfVP9` gate.
    public nonisolated func requestKeyframe(for peer: MCPeerID) { tell(MCPeerCommand(.requestKeyframe, peer)) }

    private func handleRequestKeyframe(_ peer: MCPeerID) {
        guard links[peer]?.sawVP9 == true else { return }
        sendTo(peer, RemoteCmd.RequestKeyframe(sender: nil), mode: .reliable)
    }

    // MARK: - Clock sync

    private func startClockSyncLoop() {
        clockSyncTask.value?.cancel()
        let interval = clockSyncInterval
        clockSyncTask.value = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                await self.pingClocks()
            }
        }
    }

    private func pingClocks() {
        for peer in order where links[peer]?.supportsMulticam == true {
            sendTo(peer, RemoteCmd.ClockSyncPing(t0Millis: SyncClock.nowMillis()))
        }
    }

    // MARK: - Sending

    @discardableResult
    private func sendTo(_ peer: MCPeerID, _ msg: Message,
                        mode: MCSessionSendDataMode = .reliable) -> Bool {
        transportShared.value?.send(msg, to: [peer], mode: mode) ?? false
    }

    // MARK: - Snapshots

    // Each lane declares its own snapshot (see `CameraLink.snapshot`); the
    // controller just gathers them in order.
    private func laneSnapshot() -> [MulticamLaneInfo] {
        order.compactMap { links[$0]?.snapshot }
    }

    private func publishLanesNow() {
        let snapshot = laneSnapshot()
        let capturing: Bool
        if case .capturingPhoto = state { capturing = true } else { capturing = false }
        let recording: Bool
        switch state {
        case .recording, .stoppingRecording: recording = true
        default: recording = false
        }
        let display = display
        OperationQueue.main.addOperation {
            display?.applyLanes(snapshot)
            display?.applyShutterState(capturing: capturing, recording: recording)
        }
    }

    private func isPeerCompatible(_ became: RemoteCmd.RoleAnnouncement) -> Bool {
        guard let local = PeerAppCompatibility.localVersion else { return true }
        return PeerAppCompatibility.decide(local: local,
                                           remoteShortVersion: became.shortVersion) == .compatible
    }
}

/// Wraps a camera-addressed inbound message with its source peer, so the
/// nonisolated delegate can enqueue routing work onto the FIFO inbox without
/// losing the `from` that Seam A preserved.
final class RoutedMessage: Message, @unchecked Sendable {
    let message: Message
    let peer: MCPeerID
    init(message: Message, peer: MCPeerID) {
        self.message = message
        self.peer = peer
        super.init(sender: nil)
    }
}

/// A clock-sync pong with its arrival time already stamped at receipt, so the
/// RTT is measured before inbox queuing but the record is still ordered.
final class ClockPongMeasured: Message, @unchecked Sendable {
    let pong: RemoteCmd.ClockSyncPong
    let t3: UInt64
    let peer: MCPeerID
    init(pong: RemoteCmd.ClockSyncPong, t3: UInt64, peer: MCPeerID) {
        self.pong = pong
        self.t3 = t3
        self.peer = peer
        super.init(sender: nil)
    }
}

// MARK: - MultipeerServiceDelegate

extension MulticamController: MultipeerServiceDelegate {

    public nonisolated func didReceiveMessage(_ message: Message, from peer: MCPeerID) {
        // Stamp the pong's arrival time (`t3`) here, at receipt, so the RTT is
        // measured before any queuing — then route it through the inbox like
        // everything else, so ordering and `waitForIdle` hold. Everything else
        // carries its source through `RoutedMessage`.
        if let pong = message as? RemoteCmd.ClockSyncPong {
            tell(ClockPongMeasured(pong: pong, t3: SyncClock.nowMillis(), peer: peer))
            return
        }
        tell(RoutedMessage(message: message, peer: peer))
    }

    private func storePong(_ pong: RemoteCmd.ClockSyncPong, t3: UInt64, from peer: MCPeerID) {
        guard let link = links[peer] else { return }
        link.clockEstimator.recordExchange(
            t0Millis: pong.echoT0Millis,
            cameraClockMillis: pong.cameraClockMillis,
            t3Millis: t3)
        markLanesDirty()
    }

    public nonisolated func didReceiveFrameRequest(_ request: RemoteCmd.RequestFrame) {
        // The director never sends frames, so a frame-credit ack is a no-op.
    }

    public nonisolated func didReceiveFrame(_ frame: RemoteCmd.SendFrame, from peer: MCPeerID) {
        tell(RemoteCmd.OnFrame(data: frame.data,
                               sender: nil,
                               peerId: peer,
                               fps: frame.fps,
                               camPosition: frame.camPosition,
                               camOrientation: frame.camOrientation,
                               codec: frame.codec,
                               sequenceNumber: frame.sequenceNumber))
    }

    public nonisolated func peerDidConnect(_ peer: MCPeerID) {
        tell(OnConnectToDevice(peer: peer, sender: nil))
    }

    public nonisolated func peerDidDisconnect(_ peer: MCPeerID) {
        tell(DisconnectPeer(peer: peer, sender: nil))
    }

    public nonisolated func didDetectIncompatibility() {}

    public nonisolated func browserDidFindPeer(_ peer: MCPeerID) {
        tell(UICmd.BrowserFoundPeer(peer: peer))
    }

    public nonisolated func browserDidLosePeer(_ peer: MCPeerID) {
        tell(UICmd.BrowserLostPeer(peer: peer))
    }

    public nonisolated func browserDidFail(_ error: Error) {}
    public nonisolated func advertiserDidFail(_ error: Error) {}

    public nonisolated func didStartReceivingResource(name: String, from peer: MCPeerID, progress: Progress) {
        tell(ResourceTransferStarted(peer: peer, name: name, progress: progress))
    }

    public nonisolated func didFinishReceivingResource(name: String, from peer: MCPeerID, at localURL: URL?, error: Error?) {
        tell(ResourceTransferFinished(peer: peer, name: name, localURL: localURL, error: error))
    }
}

/// A footage transfer from one camera started (carries a `Progress` to observe).
final class ResourceTransferStarted: Message, @unchecked Sendable {
    let peer: MCPeerID
    let name: String
    let progress: Progress
    init(peer: MCPeerID, name: String, progress: Progress) {
        self.peer = peer; self.name = name; self.progress = progress
        super.init(sender: nil)
    }
}

/// A footage transfer from one camera finished (or failed).
final class ResourceTransferFinished: Message, @unchecked Sendable {
    let peer: MCPeerID
    let name: String
    let localURL: URL?
    let error: Error?
    init(peer: MCPeerID, name: String, localURL: URL?, error: Error?) {
        self.peer = peer; self.name = name; self.localURL = localURL; self.error = error
        super.init(sender: nil)
    }
}

// MARK: - Director UI-command messages (single-entry inbox)
//
// Every UI intent is a message on the same FIFO inbox as transport events, so
// there is one arrival-ordered stream and one place state changes — the pump.
// (`install`/`setDisplay` stay direct: they run before the pump matters.)

enum MulticamTimedAction { case photo, record }

final class MCCapturePhoto: Message, @unchecked Sendable {}
final class MCToggleFocusedCamera: Message, @unchecked Sendable {}
final class MCStartRecording: Message, @unchecked Sendable {}
final class MCStopRecording: Message, @unchecked Sendable {}
final class MCAutomaticVideoQuality: Message, @unchecked Sendable {}
final class MCAutomaticPhotoQuality: Message, @unchecked Sendable {}
final class MCTimerAdvance: Message, @unchecked Sendable {}

final class MCPeerCommand: Message, @unchecked Sendable {
    enum Kind { case focus, invite, remove, disconnect, retryCollection, nudgeFrame, requestKeyframe, reconnectTick }
    let kind: Kind
    let peer: MCPeerID
    init(_ kind: Kind, _ peer: MCPeerID) { self.kind = kind; self.peer = peer; super.init(sender: nil) }
}

final class MCToggleTorch: Message, @unchecked Sendable {}
final class MCToggleFlash: Message, @unchecked Sendable {}
final class MCSetZoom: Message, @unchecked Sendable {
    let factor: CGFloat
    init(_ factor: CGFloat) { self.factor = factor; super.init(sender: nil) }
}

final class MCSetVideoQuality: Message, @unchecked Sendable {
    let resolution: VideoResolution
    let frameRate: VideoFrameRate
    init(_ resolution: VideoResolution, _ frameRate: VideoFrameRate) {
        self.resolution = resolution; self.frameRate = frameRate; super.init(sender: nil)
    }
}

final class MCSetPhotoQuality: Message, @unchecked Sendable {
    let format: PhotoFormat
    let hdr: HDRMode
    init(_ format: PhotoFormat, _ hdr: HDRMode) { self.format = format; self.hdr = hdr; super.init(sender: nil) }
}

final class MCSetRigTimer: Message, @unchecked Sendable {
    let seconds: Int
    init(_ seconds: Int) { self.seconds = seconds; super.init(sender: nil) }
}
