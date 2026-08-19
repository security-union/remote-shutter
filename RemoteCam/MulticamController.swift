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
    case monitoring
    /// A synced photo is in flight: `acksRemaining` cameras have yet to accept
    /// or refuse `captureId`. Returns to `.monitoring` when it reaches zero.
    case capturingPhoto(captureId: String, acksRemaining: Int)
    /// A synced recording start is collecting acks — all-or-nothing: the
    /// shutter shows in-flight (not REC) until every target camera accepts;
    /// one refusal, silence past the deadline, or a target dropping aborts
    /// the whole take.
    case startingRecording(captureId: String, acksRemaining: Int)
    /// Every target camera accepted the synced start — the rig is rolling.
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
    /// This camera can focus at a point — gates the viewfinder's focus tap so
    /// the user never gets a reticle (or a paywall) for a camera that can't.
    let supportsFocusPoint: Bool
    /// This camera's current device has a torch (front cameras don't) — gates
    /// the torch glyph when this lane is focused.
    let hasTorch: Bool
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
    /// Aggregate shutter state: `capturing` = a synced photo or recording
    /// start is in flight (activity ring); `recording` = every target camera
    /// committed and the rig is rolling (record/stop button + timer counting
    /// from `recordingStartTime`, nil unless recording).
    func applyShutterState(capturing: Bool, recording: Bool, recordingStartTime: Date?)
    /// Cameras the browser has found that aren't in the rig — the add-camera
    /// sheet's list.
    func applyAvailablePeers(_ peers: [MCPeerID])
    /// The rig-wide settings (timer + quality intersection) for the tray.
    func applyRigSettings(_ settings: RigSettingsSnapshot)
    /// A brief, non-blocking error readout (a refused camera switch, e.g.).
    /// The screen shows it and clears it itself — the controller keeps none of it.
    func showTransientError(_ message: String)
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

    private var state: MulticamState = .monitoring
    /// Insertion-ordered peer ids, so the strip/grid order is stable as lanes
    /// come and go.
    private var order: [MCPeerID] = []
    private var links: [MCPeerID: CameraLink] = [:]
    private var focusedPeer: MCPeerID?

    /// Cameras the browser has found that are not in the rig yet — the source
    /// list for the in-session "add camera" sheet. Shares the scanner's
    /// name-resolution rule (`DiscoveredPeers.upsert`), so a re-delivered peer's
    /// resolved name reaches the sheet instead of the hash placeholder.
    private var available = DiscoveredPeers()

    /// One id per director session, part of every capture's filename group.
    private let sessionID = UUID().uuidString
    /// Cameras that have yet to answer the in-flight synced capture/start/stop.
    private var capturingLanes: Set<MCPeerID> = []
    /// The camera set locked when a countdown arms a shot: the ticks and the
    /// capture address exactly this set, so the cameras that count down are
    /// the cameras that shoot. Nil when no countdown is armed.
    private var armedTargets: Set<MCPeerID>?
    /// The in-flight recording take: its locked targets, which wire path the
    /// start went out on (scheduled vs plain fallback — the abort must stop
    /// through the same path), and the shared fire instant.
    private var takeTargets: [MCPeerID] = []
    private var takeScheduled = false
    private var takeAnchorMillis: UInt64?
    /// When the rig actually started rolling (every start ack in) — feeds the
    /// classic recording timer on the director.
    private var recordingStartedAt: Date?
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
    /// The rig's aspect ratio — a crop every camera can do, so it needs no
    /// intersection: it fans to every lane and is re-applied to late joiners.
    /// 16:9 is the cameras' own default.
    private var activeAspectRatio: AspectRatio = .sixteenNine
    /// The rig-wide camera-preview mode: standby blanks each camera's own
    /// on-screen preview (the director is the viewfinder; capture and the
    /// streamed frames are unaffected). Sent only to cameras that advertised
    /// `supportsPreviewMode`, including late joiners.
    private var rigPreviewMode: CameraPreviewMode = .on
    /// One rig self-timer (seconds); 0 = off. Fans out to every camera so
    /// subjects see the countdown, and its expiry triggers the synced capture.
    /// Seeded from the preference the classic remote persists, and written
    /// back on every change — one preset across both screens.
    private var rigTimerSeconds: Int = TimerPreference.seconds
    /// The live countdown, or nil when not counting down.
    private var countdown: (remaining: Int, action: MulticamTimedAction)?
    /// Bumped on every countdown begin/cancel; a tick carrying a stale
    /// generation is ignored, so a cancelled countdown can never fire late and
    /// a tick already in the inbox can never advance a newer countdown.
    private var countdownGeneration = 0
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
    /// How long to wait for a lane's capabilities before asking again.
    private var capsRetryDelay: TimeInterval = 2
    private let reconnectInviteTimeout: TimeInterval = 10

    // MARK: Test / wiring seams

    func needsRematchForTesting(_ peer: MCPeerID) -> Bool {
        laneSnapshot().first { $0.peerID == peer }?.needsQualityRematch ?? false
    }

    func setDisplay(_ display: MulticamDisplay) {
        self.display = display
        // A display may be wired after `install`: forget what was published so
        // the new screen receives the complete current state, not just diffs.
        publishedLanes = nil
        publishedShutter = nil
        publishedRig = nil
        publishedAvailable = nil
        publishChangedSnapshots()
    }
    func setReconnectRetryDelay(_ delay: TimeInterval) { reconnectRetryDelay = delay }
    func setCapsRetryDelay(_ delay: TimeInterval) { capsRetryDelay = delay }

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
                 initialPeers: [MCPeerID]) {
        multipeerService = transport
        transportShared.value = transport
        transport.delegate = self

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
        publishChangedSnapshots() // install runs outside the pump — publish directly
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
        armCapsRetry(peer)
    }

    /// Ask again until capabilities actually arrive. A one-shot request can
    /// miss: the camera's capture session may not be ready when it lands (the
    /// camera's own reply ladder gives up after ~3s), or the request can race
    /// the role handoff and be refused. The tick self-guards on "capabilities
    /// still missing", so it is fire-and-forget and stops the moment caps land
    /// or the lane leaves the rig — the controls always end up rendered from
    /// real capabilities, however late they are.
    private func armCapsRetry(_ peer: MCPeerID) {
        PeerReconnect.scheduleTick(after: capsRetryDelay) { [weak self] in
            self?.tell(MCPeerCommand(.capsRetryTick, peer))
        }
    }

    private func reRequestCapsIfStillMissing(_ peer: MCPeerID) {
        guard let link = links[peer], link.capabilities == nil, link.status == .linked else { return }
        logInfo("director: no caps from \(link.displayName) yet — re-requesting")
        beginHandshake(with: peer) // re-arms the tick
    }

    // MARK: - Message handling

    /// Derived publishing: handlers only mutate state. After every message the
    /// pump rebuilds each UI snapshot from that state and publishes the ones
    /// that changed (all snapshots are Equatable) — at most one main hop per
    /// message, and no per-handler publish bookkeeping. The settings tray is
    /// therefore always the intersection of the cameras actually in the rig:
    /// a lane joining, dropping, or changing capabilities republishes it on
    /// the same pump turn.
    private var publishedLanes: [MulticamLaneInfo]?
    private var publishedShutter: ShutterSnapshot?
    private var publishedRig: RigSettingsSnapshot?
    private var publishedAvailable: [MCPeerID]?

    private struct ShutterSnapshot: Equatable {
        let capturing: Bool
        let recording: Bool
        let recordingStartTime: Date?
    }

    func handle(_ msg: Message) async {
        await route(msg)
        publishChangedSnapshots()
    }

    private func publishChangedSnapshots() {
        let lanes = laneSnapshot()
        let shutter = shutterSnapshot()
        let rig = rigSettingsSnapshot()
        let availablePeers = available.peers

        let lanesChanged = lanes != publishedLanes
        let shutterChanged = shutter != publishedShutter
        let rigChanged = rig != publishedRig
        // MCPeerID equality is key-hash only, so a re-delivered peer carrying
        // its resolved name compares equal to its hash-placeholder self — the
        // add-camera sheet shows names, so the diff must see them too.
        let availableChanged = availablePeers != publishedAvailable
            || availablePeers.map(\.displayName) != publishedAvailable?.map(\.displayName)
        guard lanesChanged || shutterChanged || rigChanged || availableChanged else { return }
        publishedLanes = lanes
        publishedShutter = shutter
        publishedRig = rig
        publishedAvailable = availablePeers

        let display = display
        OperationQueue.main.addOperation {
            if lanesChanged { display?.applyLanes(lanes) }
            if shutterChanged {
                display?.applyShutterState(capturing: shutter.capturing, recording: shutter.recording,
                                           recordingStartTime: shutter.recordingStartTime)
            }
            if rigChanged { display?.applyRigSettings(rig) }
            if availableChanged { display?.applyAvailablePeers(availablePeers) }
        }
    }

    private func shutterSnapshot() -> ShutterSnapshot {
        // A photo in flight and a start-ack window both read as "working, not
        // yet done" on the shutter; REC (and its timer) appear only once every
        // target camera has committed.
        let capturing: Bool
        switch state {
        case .capturingPhoto, .startingRecording: capturing = true
        default: capturing = false
        }
        // The rig is recording iff ANY camera reports a live recording (the
        // union of lane truth) or a take is mid-protocol — fact ∨ intent,
        // never memory. A director that rejoined mid-take gets its Stop
        // control and timer back from the lanes alone. The timer counts from
        // the earliest camera-reported start, falling back to the local take
        // anchor until a capabilities refresh delivers the real one.
        let rolling = order.compactMap { links[$0] }.filter { $0.isRecording }
        let inTake: Bool
        switch state {
        case .recording, .stoppingRecording: inTake = true
        default: inTake = false
        }
        guard inTake || !rolling.isEmpty else {
            return ShutterSnapshot(capturing: capturing, recording: false, recordingStartTime: nil)
        }
        let start = rolling.compactMap(\.recordingStartedAt).min() ?? recordingStartedAt
        return ShutterSnapshot(capturing: capturing, recording: true, recordingStartTime: start)
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
            _ = available.remove(lost.peer)

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
        case let m as MCFlipCamera:
            logInfo("director: flip → \(m.target.displayName)")
            handleFlipCamera(target: m.target)
        case let m as MCFocusAtPoint:
            logInfo("director: focus tap (\(m.x), \(m.y)) → \(m.target.displayName)")
            handleFocusAtPoint(x: m.x, y: m.y, target: m.target)
        case let m as MCToggleTorch:
            logInfo("director: torch → \(m.target.displayName)")
            handleToggleTorch(target: m.target)
        case let m as MCToggleFlash:
            logInfo("director: flash → \(m.target.displayName)")
            handleToggleFlash(target: m.target)
        case let z as MCSetZoom:
            // A drag, not a press — firehose level.
            logDebug("director: zoom \(z.factor) → \(z.target.displayName)")
            handleSetZoom(z.factor, target: z.target)
        case is MCCapturePhoto:
            logInfo("director: shutter tap (photo)")
            handleCapturePhoto()
        case is MCStartRecording:
            logInfo("director: shutter tap (record)")
            handleStartRecording()
        case is MCStopRecording:
            logInfo("director: shutter tap (stop)")
            handleStopRecording()
        case is MCAutomaticVideoQuality:
            logInfo("director: automatic video quality")
            handleAutomaticVideoQuality()
        case is MCAutomaticPhotoQuality:
            logInfo("director: automatic photo quality")
            handleAutomaticPhotoQuality()
        case let tick as MCTimerAdvance: advanceCountdown(generation: tick.generation)
        case let expired as MCAckTimeout: expireAcks(expired.captureID)
        case let q as MCSetVideoQuality:
            logInfo("director: video quality \(q.resolution)/\(q.frameRate) → all")
            handleSetVideoQuality(resolution: q.resolution, frameRate: q.frameRate)
        case let q as MCSetPhotoQuality:
            logInfo("director: photo quality \(q.format)/\(q.hdr) → all")
            handleSetPhotoQuality(format: q.format, hdr: q.hdr)
        case let a as MCSetAspectRatio:
            logInfo("director: aspect \(a.ratio.displayName) → all")
            handleSetAspectRatio(a.ratio)
        case let t as MCSetRigTimer:
            logInfo("director: timer preset \(t.seconds)s")
            handleSetRigTimer(t.seconds)
        case let s as MCSetRigStandby:
            logInfo("director: standby \(s.on ? "on" : "off") → rig")
            handleSetRigStandby(s.on)
        case let c as MCPeerCommand:
            switch c.kind {
            case .focus, .invite, .remove, .disconnect, .retryCollection:
                logInfo("director: \(c.kind) → \(c.peer.displayName)")
            case .nudgeFrame, .requestKeyframe, .reconnectTick, .capsRetryTick:
                logDebug("director: \(c.kind) → \(c.peer.displayName)")
            }
            switch c.kind {
            case .focus: handleSetFocusedPeer(c.peer)
            case .invite: handleInviteCamera(c.peer)
            case .remove: handleRemoveCamera(c.peer)
            case .disconnect: handleDisconnectCamera(c.peer)
            case .retryCollection: handleRetryCollection(c.peer)
            case .nudgeFrame: handleNudgeFrame(c.peer)
            case .requestKeyframe: handleRequestKeyframe(c.peer)
            case .reconnectTick: reBrowseIfStillMissing(c.peer)
            case .capsRetryTick: reRequestCapsIfStillMissing(c.peer)
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
            }
            // A re-announce means the camera's session — and its report seq
            // domain — restarted; zero the cursor so its next report lands.
            link.lastStateReportSeq = 0
            // And its CLOCK samples are void: uptime clocks pause during
            // sleep, so offsets measured before a backgrounding are wrong by
            // the slept duration (the estimator's own contract — reset when
            // clocks may have moved). Fresh pings repopulate within seconds.
            link.clockEstimator.reset()

        case let report as RemoteCmd.CameraStateReport:
            // The lane's recording truth on its one channel — the REC badge
            // is DERIVED from it, never remembered from what was last
            // commanded. The instant is in the CAMERA's clock domain;
            // translate it with the lane's measured offset so the rig timer
            // never inherits cross-device wall-clock skew.
            guard report.seq > link.lastStateReportSeq else { break }
            link.lastStateReportSeq = report.seq
            switch report.state {
            case .recording(let startedAt):
                link.recordingStartedAt = directorClockDate(startedAt,
                                                            offsetMillis: link.latestOffset?.offsetMillis)
            case .idle:
                link.recordingStartedAt = nil
            }
            // Intent yields to unanimous fact: if the take machine still
            // believes a recording is running but every lane now reports
            // idle (cameras stop on their own — operator stop, disk full,
            // lock), the take is factually over: clear it, stop the rig
            // timer, re-arm the shutter. A stop mid-ack
            // (`.stoppingRecording`) is left to its own ack/timeout
            // machinery.
            if case .recording(let id, _) = state,
               !order.contains(where: { links[$0]?.isRecording == true }) {
                logInfo("director: every lane reports idle — take \(shortID(id)) ended without us")
                clearRecordingTake()
                state = .monitoring
            }

        case let caps as RemoteCmd.CameraCapabilitiesResp:
            logInfo("director: caps from \(link.displayName) — torch=\(caps.getCurrentCameraInfo()?.hasTorch ?? false), camera=\(caps.currentCamera)")
            link.capabilities = caps
            seedZoom(link, from: caps)
            if link.status != .failed { link.status = .linked }
            // A late joiner may not match the running rig quality: flag it (its
            // tile badges + the tray offers re-match) rather than silently
            // changing the rig. Also refreshes the intersection menu.
            // A multicam-capable camera gets an immediate clock probe so its
            // offset is ready well before the first synced capture (PR4), and
            // its preview tier (full if focused, else thumbnail).
            if link.supportsMulticam {
                sendTo(peer, RemoteCmd.ClockSyncPing(t0Millis: SyncClock.nowMillis()))
                pushProfile(to: peer)
            }
            // The rig's standby is a setting, not an event: a camera joining
            // (or re-advertising) while the rig is in standby is put there too.
            if rigPreviewMode == .standby, caps.supportsPreviewMode {
                sendTo(peer, RemoteCmd.SetCameraPreviewMode(mode: .standby))
            }
            // Aspect likewise: a camera arriving while the rig is off the 16:9
            // camera default is cropped to match the rest of the shot.
            if activeAspectRatio != .sixteenNine {
                sendTo(peer, RemoteCmd.SetAspectRatio(aspectRatio: activeAspectRatio))
            }

        case let resp as RemoteCmd.ToggleCameraResp:
            // The focused camera flipped front/back (or picked a device — the
            // response type is shared). Its refreshed capabilities carry the
            // new position, lenses and zoom, so the lane's controls reflect it.
            // A refusal (the camera couldn't run the requested device and
            // reverted) surfaces on screen — never silently swallowed.
            if let error = resp.error {
                logWarning("director: camera switch on \(link.displayName) failed — \(error._domain)")
                let display = display
                let message = error._domain
                OperationQueue.main.addOperation { display?.showTransientError(message) }
            }
            if let caps = resp.cameraCapabilities {
                link.capabilities = caps
                seedZoom(link, from: caps)
            }

        case let resp as RemoteCmd.SetZoomResp:
            // The focused camera settled on a zoom; reflect its factor and range
            // on that lane so the pill's thumb and ceiling track the hardware.
            if let factor = resp.zoomFactor { link.zoomFactor = factor }
            if let maxZoom = resp.zoomRange?.maxZoom {
                link.maxZoomFactor = ZoomScaleSeed.clampMaxZoom(maxZoom, wideAngle: link.wideAngleZoomFactor)
            }

        case let ack as RemoteCmd.ScheduledCaptureAck:
            resolvePhotoAck(from: peer, captureId: ack.captureId, success: ack.error == nil)

        case is RemoteCmd.TakePicAck:
            // The fallback (plain TakePic) path's positive ack (carries no id).
            resolvePhotoAck(from: peer, captureId: nil, success: true)

        case let resp as RemoteCmd.TakePicResp:
            if resp.error != nil {
                resolvePhotoAck(from: peer, captureId: nil, success: false)
            } else if let pic = resp.pic {
                // Auto-collect: the camera returned its (EXIF-stamped) still.
                // Save it to the director's library under the shared RS_ name.
                collectPhoto(pic, from: peer)
            }

        case let ack as RemoteCmd.ScheduledRecordingAck:
            resolveRecordingAck(from: peer, captureId: ack.captureId, isStop: ack.isStop,
                                success: ack.error == nil)

        case let ack as RemoteCmd.StartRecordingVideoAck:
            // The fallback (plain StartRecordingVideo) path's ack (no id).
            resolveRecordingAck(from: peer, captureId: nil, isStop: false, success: ack.error == nil)

        case is RemoteCmd.EndSession:
            // The camera is leaving on purpose — the goodbye ends its lane,
            // exactly as the 1:1 monitor treats it. Dropped without reconnect:
            // the transport disconnect that follows matches no lane and starts
            // no chase, and if the camera advertises again it becomes an
            // "available" candidate — never auto-rejoined.
            handleRemoveCamera(peer)
            if order.isEmpty {
                let display = display
                OperationQueue.main.addOperation { display?.exitMulticam() }
            }

        default:
            // Per-camera command responses (zoom/lens/flash/torch acks) update
            // only the focused lane's controls, wired to the UI in a later PR;
            // PR3 surfaces frames + status, so these are accepted and ignored.
            break
        }
    }

    private func handlePeerConnected(_ peer: MCPeerID) {
        if let existing = links[peer] {
            // A reconnecting lane came back — rehandshake and relight it. The
            // camera's session restarted, so anything cached about the OLD
            // session is stale: the stream tier must be re-pushed (the fresh
            // encoder starts at defaults), and the clock offset re-measured
            // (a rebooted device answers with a different clock).
            existing.status = .linked
            existing.lastSentProfile = nil
            existing.clockEstimator.reset()
        } else {
            order.append(peer)
            links[peer] = CameraLink(peerID: peer)
        }
        // It's in the rig now, so it's no longer an "available" candidate.
        _ = available.remove(peer)
        focusedPeer = focusedPeer ?? peer
        beginHandshake(with: peer)
    }

    private func handlePeerDisconnected(_ peer: MCPeerID) {
        guard let link = links[peer] else { return }
        // Degrade the tile, keep the rest of the rig recording/monitoring. The
        // controller stays browsing, so `browserDidFindPeer` re-invites.
        link.status = .reconnecting
        armReconnect(peer)
        laneLeftShot(peer)
    }

    /// A lane in play for a shot went away. A dead camera is never waited on:
    /// during the start-ack window the take is all-or-nothing, so the whole
    /// take aborts; during a photo or stop ack window the lane settles
    /// immediately instead of running out its timeout; during a countdown the
    /// locked set shrinks, and an emptied set cancels the countdown. (An
    /// established `.recording` is untouched — the rest of the rig keeps
    /// rolling, and the camera itself keeps recording through the drop.)
    private func laneLeftShot(_ peer: MCPeerID) {
        switch state {
        case .startingRecording:
            if takeTargets.contains(peer) {
                links[peer]?.captureOutcome = .failed
                abortRecordingStart()
            }
        case .capturingPhoto:
            if capturingLanes.contains(peer) {
                links[peer]?.captureOutcome = .failed
                finishLane(peer)
            }
        case .stoppingRecording:
            if capturingLanes.contains(peer) {
                links[peer]?.recordingStartedAt = nil
                finishLane(peer)
            }
        case .recording, .monitoring:
            break
        }
        if var armed = armedTargets, armed.remove(peer) != nil {
            armedTargets = armed
            if armed.isEmpty { cancelCountdown() }
        }
    }

    private func handleBrowserFound(_ peer: MCPeerID) {
        // A camera we are actively missing is auto-re-invited.
        if let link = links[peer], link.status == .reconnecting {
            multipeerService?.invitePeer(peer, timeout: reconnectInviteTimeout)
            return
        }
        // An unrelated fresh peer becomes a candidate for the "add camera"
        // sheet — it never auto-joins. `upsert` also handles a re-delivery
        // that upgrades the peer's name in place, so the sheet shows the
        // resolved name rather than the hash placeholder.
        guard links[peer] == nil else { return }
        available.upsert(peer)
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
    /// so the only thing off-actor is the shared one-shot delay. The tick
    /// self-guards on lane status, so the task is fire-and-forget.
    private func armReconnect(_ peer: MCPeerID) {
        PeerReconnect.scheduleTick(after: reconnectRetryDelay) { [weak self] in
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

    // MARK: - Per-camera controls (target carried by the command)

    /// Framing controls are pure functions of their arguments: the UI names
    /// the camera it rendered the control for, and the command carries that
    /// target all the way to the wire. No routing register to go stale —
    /// `focusedPeer` is presentation state (tile size, stream tier), never
    /// command routing.
    public nonisolated func setZoom(_ factor: CGFloat, on peer: MCPeerID) {
        tell(MCSetZoom(factor, target: peer))
    }
    public nonisolated func toggleTorch(on peer: MCPeerID) { tell(MCToggleTorch(target: peer)) }
    public nonisolated func toggleFlash(on peer: MCPeerID) { tell(MCToggleFlash(target: peer)) }

    private func handleSetZoom(_ factor: CGFloat, target: MCPeerID) {
        guard links[target] != nil else { return }
        sendTo(target, RemoteCmd.SetZoom(zoomFactor: factor))
    }

    private func handleToggleTorch(target: MCPeerID) {
        guard let link = links[target] else { return }
        // Optimistic: reflect the tap immediately so the glyph tints like the
        // 1:1 monitor's; the camera is the source of truth for whether it took.
        link.torchOn.toggle()
        sendTo(target, RemoteCmd.ToggleTorch())
    }

    private func handleToggleFlash(target: MCPeerID) {
        guard let link = links[target] else { return }
        link.flashOn.toggle()
        sendTo(target, RemoteCmd.ToggleFlash())
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

    /// Flip one camera between front and back. The camera decides whether a
    /// flip does anything, exactly as in the 1:1 monitor; `ToggleCameraResp`
    /// carries its refreshed capabilities back to that lane.
    public nonisolated func flipCamera(_ peer: MCPeerID) { tell(MCFlipCamera(target: peer)) }

    private func handleFlipCamera(target: MCPeerID) {
        guard links[target]?.status == .linked else { return }
        sendTo(target, RemoteCmd.ToggleCamera())
    }

    /// Tap-to-focus on one camera. The IAP gate lives on the view controller
    /// (mirrors the 1:1); here the command is dropped if that camera never
    /// advertised focus support.
    public nonisolated func focusCamera(_ peer: MCPeerID, x: Float, y: Float) {
        tell(MCFocusAtPoint(x: x, y: y, target: peer))
    }

    private func handleFocusAtPoint(x: Float, y: Float, target: MCPeerID) {
        guard links[target]?.capabilities?.supportsFocusPoint == true else { return }
        sendTo(target, RemoteCmd.FocusAtPoint(x: x, y: y))
    }

    func switchLens(_ lens: CameraLensType, on peer: MCPeerID) {
        guard links[peer] != nil else { return }
        sendTo(peer, RemoteCmd.SwitchLens(lensType: lens))
    }

    public nonisolated func setFocusedPeer(_ peer: MCPeerID) { tell(MCPeerCommand(.focus, peer)) }

    private func handleSetFocusedPeer(_ peer: MCPeerID) {
        guard links[peer] != nil else { return }
        focusedPeer = peer
        // Retier previews: the newly focused camera goes full-size, the rest
        // (including the one that just lost focus) drop to thumbnail.
        for p in order { pushProfile(to: p) }
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
        laneLeftShot(peer)
        links[peer] = nil
        frameSinks[peer] = nil
        order.removeAll { $0 == peer }
        if focusedPeer == peer { focusedPeer = order.first }
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
    func startingStateForTesting() -> (id: String, remaining: Int)? {
        if case .startingRecording(let id, let remaining) = state { return (id, remaining) }
        return nil
    }
    func recordingStartTimeForTesting() -> Date? { recordingStartedAt }
    func stoppingStateForTesting() -> (id: String, remaining: Int)? {
        if case .stoppingRecording(let id, let remaining) = state { return (id, remaining) }
        return nil
    }
    func captureOutcomeForTesting(_ peer: MCPeerID) -> CaptureOutcome? { links[peer]?.captureOutcome }
    func isRecordingForTesting(_ peer: MCPeerID) -> Bool { links[peer]?.isRecording ?? false }
    func availablePeersForTesting() -> [MCPeerID] { available.peers }
    func cameraCountForTesting() -> Int { order.count }
    func rigSettingsSnapshotForTesting() -> RigSettingsSnapshot { rigSettingsSnapshot() }

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

    /// Send a scheduled command to each target camera at a shared instant, each
    /// translated into that camera's own clock by its offset. Returns the
    /// captureID, whether the scheduled path was used, and the shared instant.
    /// `build` makes the per-lane message.
    private func fanOutScheduled(
        _ build: (_ fireAtCameraClock: UInt64, _ anchor: UInt64, _ captureID: String,
                  _ index: Int) -> Message,
        fallback: (CameraLink) -> Message,
        lanes: [CameraLink]) -> (captureID: String, scheduled: Bool, anchorMillis: UInt64?) {
        let captureID = UUID().uuidString
        capturingLanes = Set(lanes.map(\.peerID))
        lastCaptureID = captureID
        for link in lanes { link.collection = .idle }

        if lanes.allSatisfy({ $0.latestOffset != nil }) {
            let fireAt = SyncClock.nowMillis() + captureLeadMillis
            for (index, link) in lanes.enumerated() {
                let offset = link.latestOffset?.offsetMillis ?? 0
                let fireAtCameraClock = UInt64(Int64(fireAt) + offset)
                sendTo(link.peerID, build(fireAtCameraClock, fireAt, captureID, index + 1))
            }
            return (captureID, true, fireAt)
        } else {
            // A missing offset means we can't promise a sub-frame instant — fire
            // now on each camera, under the same shot id.
            for link in lanes { sendTo(link.peerID, fallback(link)) }
            return (captureID, false, nil)
        }
    }

    /// The lanes a firing shot addresses: the set the countdown locked (its
    /// still-ready members), or the ready lanes right now for an un-timed shot.
    private func shotLanes() -> [CameraLink] {
        let ready = readyMulticamLanes()
        guard let armed = armedTargets else { return ready }
        return ready.filter { armed.contains($0.peerID) }
    }

    /// Arm a timed shot: lock the target set and start the countdown. The
    /// ticks and the eventual capture address exactly this set.
    private func armCountdown(_ action: MulticamTimedAction) {
        armedTargets = Set(readyMulticamLanes().map(\.peerID))
        beginCountdown(action)
    }

    /// Fire a synced photo on every ready multicam camera. If the rig timer is
    /// set, run one director-side countdown first (fanned out so subjects see
    /// it), then fire. Scheduled at a shared instant when every clock offset is
    /// known; else a plain `TakePic` fan-out. No-op unless idle with a camera.
    public nonisolated func capturePhoto() { tell(MCCapturePhoto()) }

    private func handleCapturePhoto() {
        if countdown != nil { cancelCountdown(); return }
        // Nothing arms unless a camera is ready to shoot — a countdown must
        // never play on cameras that won't be asked to fire.
        guard case .monitoring = state, !readyMulticamLanes().isEmpty else { return }
        guard rigTimerSeconds > 0 else { performCapturePhoto(); return }
        armCountdown(.photo)
    }

    private func performCapturePhoto() {
        guard case .monitoring = state else { return }
        let targets = shotLanes()
        guard !targets.isEmpty else { return }
        for link in targets { link.captureOutcome = nil }

        let fan = fanOutScheduled(
            { fire, anchor, id, index in
                RemoteCmd.ScheduledCapture(fireAtCameraClockMillis: fire, anchorMillis: anchor,
                                           captureId: id, sessionId: self.sessionID, cameraIndex: index)
            },
            fallback: { _ in RemoteCmd.TakePic(sender: nil, sendMediaToPeer: false) },
            lanes: targets)

        logInfo("director: photo \(shortID(fan.captureID)) → [\(names(targets.map(\.peerID)))]")
        state = .capturingPhoto(captureId: fan.captureID, acksRemaining: capturingLanes.count)
        armAckTimeout(fan.captureID)
    }

    /// Start a synced recording on every ready multicam camera (timer-gated).
    public nonisolated func startRecording() { tell(MCStartRecording()) }

    private func handleStartRecording() {
        // A second tap while acks are still being collected backs out of the
        // take (the timeout would settle it anyway; don't make the user wait).
        if case .startingRecording = state { abortRecordingStart(); return }
        if countdown != nil { cancelCountdown(); return }
        guard case .monitoring = state, !readyMulticamLanes().isEmpty else { return }
        guard rigTimerSeconds > 0 else { performStartRecording(); return }
        armCountdown(.record)
    }

    private func performStartRecording() {
        guard case .monitoring = state else { return }
        let targets = shotLanes()
        guard !targets.isEmpty else { return }
        for link in targets { link.captureOutcome = nil }

        let fan = fanOutScheduled(
            { fire, anchor, id, index in
                RemoteCmd.ScheduledStartRecording(fireAtCameraClockMillis: fire, anchorMillis: anchor,
                                                  captureId: id, sessionId: self.sessionID, cameraIndex: index)
            },
            fallback: { _ in RemoteCmd.StartRecordingVideo(sender: nil) },
            lanes: targets)

        takeTargets = targets.map(\.peerID)
        takeScheduled = fan.scheduled
        takeAnchorMillis = fan.anchorMillis
        logInfo("director: record-start \(shortID(fan.captureID)) → [\(names(targets.map(\.peerID)))]")
        state = .startingRecording(captureId: fan.captureID, acksRemaining: capturingLanes.count)
        armAckTimeout(fan.captureID)
    }

    /// Stop the synced recording on every rolling camera, anchored so the clips
    /// end together.
    public nonisolated func stopRecording() { tell(MCStopRecording()) }

    private func handleStopRecording() {
        // Reachable from `.recording` (the normal take) AND from `.monitoring`
        // when lanes report a live recording the take machine doesn't know
        // about (a director that rejoined mid-take): the same union that
        // shows the Stop control lets it act.
        let rolling = order.compactMap { links[$0] }.filter { $0.isRecording }
        switch state {
        case .recording:
            break
        case .monitoring where !rolling.isEmpty:
            break
        default:
            return
        }
        guard !rolling.isEmpty else {
            // Nothing is actually rolling (every rolling lane has dropped) —
            // there is no take left to stop, only a state to put right.
            clearRecordingTake()
            state = .monitoring
            return
        }

        let fan = fanOutScheduled(
            { fire, anchor, id, index in
                RemoteCmd.ScheduledStopRecording(fireAtCameraClockMillis: fire, anchorMillis: anchor,
                                                 captureId: id, sessionId: self.sessionID, cameraIndex: index)
            },
            fallback: { _ in RemoteCmd.StopRecordingVideo(sender: nil, sendMediaToPeer: false) },
            lanes: rolling)

        // A lane we can't hear will never ack — settle it now instead of
        // holding the rig on its timeout. The stop was still sent above, so
        // the camera ends its clip the moment it can hear us again.
        for link in rolling where link.status != .linked {
            link.recordingStartedAt = nil
            capturingLanes.remove(link.peerID)
        }
        if capturingLanes.isEmpty {
            clearRecordingTake()
            state = .monitoring
        } else {
            logInfo("director: record-stop \(shortID(fan.captureID)) → [\(names(Array(capturingLanes)))]")
            state = .stoppingRecording(captureId: fan.captureID, acksRemaining: capturingLanes.count)
            armAckTimeout(fan.captureID)
        }
    }

    // MARK: - Rig-wide quality ("the shot belongs to the rig")

    /// Test seams.
    func setTimerTickInterval(_ t: TimeInterval) { timerTickInterval = t }
    /// Advance the rig countdown one tick deterministically (production uses the
    /// one-shot Task; tests set a large interval and drive with this instead).
    /// Runs through `handle` so the publish epilogue fires like a real tick.
    func advanceTimerForTesting() async { await handle(MCTimerAdvance(generation: countdownGeneration)) }
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
    }

    public nonisolated func setPhotoQuality(format: PhotoFormat, hdr: HDRMode) {
        tell(MCSetPhotoQuality(format, hdr))
    }

    private func handleSetPhotoQuality(format: PhotoFormat, hdr: HDRMode) {
        activePhotoQuality = (format, hdr)
        for peer in order {
            sendTo(peer, RemoteCmd.SetPhotoQuality(format: format, hdrMode: hdr))
        }
    }

    /// Rig aspect ratio — every camera crops the same way, so the shot cuts
    /// together. No intersection needed (aspect is a crop, not a capability).
    public nonisolated func setAspectRatio(_ ratio: AspectRatio) { tell(MCSetAspectRatio(ratio)) }

    private func handleSetAspectRatio(_ ratio: AspectRatio) {
        activeAspectRatio = ratio
        for peer in order {
            sendTo(peer, RemoteCmd.SetAspectRatio(aspectRatio: ratio))
        }
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
    // MARK: - Rig self-timer (inbox-driven countdown)

    public nonisolated func setRigTimer(_ seconds: Int) { tell(MCSetRigTimer(max(0, seconds))) }

    private func handleSetRigTimer(_ seconds: Int) {
        rigTimerSeconds = seconds
        TimerPreference.seconds = seconds
    }

    // MARK: - Rig standby (camera-side preview on / standby)

    public nonisolated func setRigStandby(_ on: Bool) { tell(MCSetRigStandby(on)) }

    private func handleSetRigStandby(_ on: Bool) {
        rigPreviewMode = on ? .standby : .on
        for (peer, link) in links where link.capabilities?.supportsPreviewMode == true {
            sendTo(peer, RemoteCmd.SetCameraPreviewMode(mode: rigPreviewMode))
        }
    }

    /// Begin a director-side countdown, fanned out to every camera so subjects
    /// see it, then fire the synced capture at zero. Each tick is a `tell` on
    /// the inbox (so it is ordered with everything else and visible to
    /// `waitForIdle`); the only Task is a one-shot sleep between ticks.
    private func beginCountdown(_ action: MulticamTimedAction) {
        countdownGeneration += 1
        countdown = (remaining: rigTimerSeconds, action: action)
        fanOutTimerTick(rigTimerSeconds)
        scheduleNextTick()
    }

    /// Cancel the running countdown: the shutter, tapped again while the rig is
    /// counting, is a cancel — the same gesture the 1:1 monitor honors. Every
    /// camera is told (a negative tick renders the "cancelled" overlay and
    /// restores its torch); nothing is captured.
    private func cancelCountdown() {
        countdownGeneration += 1
        timerTask.value?.cancel()
        countdown = nil
        for peer in countdownRecipients() { sendTo(peer, RemoteCmd.TimerCountdown(value: -1)) }
        armedTargets = nil
    }

    /// Advance one tick (pump-driven). Fires the capture at zero. A stale
    /// generation is a tick from a countdown that no longer exists — dropped.
    private func advanceCountdown(generation: Int) {
        guard generation == countdownGeneration, let c = countdown else { return }
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
            armedTargets = nil // the locked set has served its shot
        }
    }

    /// One-shot: after `timerTickInterval`, enqueue the next tick. Production
    /// only — tests drive `advanceCountdown` directly via `advanceTimerForTesting`.
    private func scheduleNextTick() {
        let interval = timerTickInterval
        let generation = countdownGeneration
        timerTask.value?.cancel()
        timerTask.value = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.tell(MCTimerAdvance(generation: generation))
        }
    }

    private func fanOutTimerTick(_ remaining: Int) {
        for peer in countdownRecipients() { sendTo(peer, RemoteCmd.TimerCountdown(value: remaining)) }
    }

    /// The countdown plays only on the cameras that will be asked to shoot —
    /// never on a lane the locked target set doesn't contain.
    private func countdownRecipients() -> [MCPeerID] {
        guard let armed = armedTargets else { return order }
        return order.filter { armed.contains($0) }
    }

    /// The tray's snapshot, derived on demand from the live lane set — never
    /// stored, so it cannot go stale when a camera joins or drops.
    private func rigSettingsSnapshot() -> RigSettingsSnapshot {
        let menu = rigQualityMenu()
        return RigSettingsSnapshot(
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
            activeHDR: activePhotoQuality?.hdr,
            aspectRatio: activeAspectRatio,
            standbyAvailable: order.contains { peer in
                guard let link = links[peer], link.status != .failed else { return false }
                return link.capabilities?.supportsPreviewMode == true
            },
            standbyOn: rigPreviewMode == .standby)
    }

    // MARK: Ack aggregation (shared across photo / start / stop)

    /// `captureId` nil = a fallback-path message that carries no id; a non-nil
    /// id must match the in-flight shot or the ack is a stray from a dead one.
    private func resolvePhotoAck(from peer: MCPeerID, captureId: String?, success: Bool) {
        guard case .capturingPhoto(let id, _) = state, capturingLanes.contains(peer),
              captureId == nil || captureId == id else { return }
        if success {
            logInfo("director: \(peer.displayName) acked photo \(shortID(id))")
        } else {
            logWarning("director: \(peer.displayName) NACKED photo \(shortID(id))")
        }
        links[peer]?.captureOutcome = success ? .captured : .failed
        finishLane(peer)
    }

    private func resolveRecordingAck(from peer: MCPeerID, captureId: String?,
                                     isStop: Bool, success: Bool) {
        switch state {
        case .startingRecording(let id, _) where !isStop:
            guard capturingLanes.contains(peer), captureId == nil || captureId == id else { return }
            guard success else {
                // All-or-nothing: one refusal voids the whole take.
                logWarning("director: \(peer.displayName) NACKED record-start \(shortID(id))")
                links[peer]?.captureOutcome = .failed
                abortRecordingStart()
                return
            }
            logInfo("director: \(peer.displayName) acked record-start \(shortID(id))")
            // Seed with the take's shared fire instant — the camera's own
            // report refines it on the next capabilities exchange.
            links[peer]?.recordingStartedAt = recordingStartDate()
            capturingLanes.remove(peer)
            if capturingLanes.isEmpty {
                // Every target committed — the rig is rolling, from the shared
                // fire instant.
                logInfo("director: rig rolling \(shortID(id))")
                state = .recording(captureId: id, acksRemaining: 0)
                recordingStartedAt = recordingStartDate()
            } else {
                state = .startingRecording(captureId: id, acksRemaining: capturingLanes.count)
            }
        case .stoppingRecording(let id, _) where isStop:
            guard capturingLanes.contains(peer), captureId == nil || captureId == id else { return }
            links[peer]?.recordingStartedAt = nil
            finishLane(peer)
        default:
            break
        }
    }

    /// Translates a camera-reported instant into the director's clock domain
    /// (`offsetMillis` = cameraClock − directorClock, the same convention
    /// `fanOutScheduled` applies in the opposite direction). Without an
    /// offset sample the raw report stands.
    private func directorClockDate(_ cameraDate: Date?, offsetMillis: Int64?) -> Date? {
        guard let cameraDate, let offsetMillis else { return cameraDate }
        return cameraDate.addingTimeInterval(-Double(offsetMillis) / 1000)
    }

    /// The take's shared fire instant as a wall-clock date (scheduled path),
    /// or now (fallback path) — so the recording timer counts from the moment
    /// the cameras actually rolled, not from when the last ack arrived.
    private func recordingStartDate() -> Date {
        guard let anchor = takeAnchorMillis else { return Date() }
        let deltaMillis = Int64(bitPattern: anchor &- SyncClock.nowMillis())
        return Date().addingTimeInterval(Double(deltaMillis) / 1000)
    }

    /// All-or-nothing abort: the take is void unless every target accepted.
    /// The stop goes to EVERY target — a camera whose ok-ack is still in
    /// flight gets stopped too, and one that never started refuses the stop
    /// harmlessly. Badging the lane that broke the take is the trigger site's
    /// job (nack, timeout, and disconnect know who to blame; the rest didn't fail).
    private func abortRecordingStart() {
        guard case .startingRecording(let id, _) = state else { return }
        logWarning("director: take \(shortID(id)) ABORTED — stop → [\(names(takeTargets))]")
        for peer in takeTargets {
            if takeScheduled {
                let fireAt = SyncClock.nowMillis() + captureLeadMillis
                let offset = links[peer]?.latestOffset?.offsetMillis ?? 0
                sendTo(peer, RemoteCmd.ScheduledStopRecording(
                    fireAtCameraClockMillis: UInt64(Int64(fireAt) + offset), anchorMillis: fireAt,
                    captureId: id, sessionId: sessionID, cameraIndex: cameraIndex(of: peer)))
            } else {
                sendTo(peer, RemoteCmd.StopRecordingVideo(sender: nil, sendMediaToPeer: false))
            }
            links[peer]?.recordingStartedAt = nil
        }
        clearRecordingTake()
        state = .monitoring
    }

    private func clearRecordingTake() {
        capturingLanes.removeAll()
        takeTargets = []
        takeScheduled = false
        takeAnchorMillis = nil
        recordingStartedAt = nil
    }

    /// Count one lane's answer and advance the aggregate. A photo or a stop
    /// that empties the set returns to monitoring. (Recording start acks are
    /// aggregated all-or-nothing in `resolveRecordingAck`, not here.)
    private func finishLane(_ peer: MCPeerID) {
        capturingLanes.remove(peer)
        let remaining = capturingLanes.count
        switch state {
        case .capturingPhoto(let id, _):
            state = remaining == 0 ? .monitoring : .capturingPhoto(captureId: id, acksRemaining: remaining)
        case .stoppingRecording(let id, _):
            if remaining == 0 {
                clearRecordingTake()
                state = .monitoring
            } else {
                state = .stoppingRecording(captureId: id, acksRemaining: remaining)
            }
        case .recording, .startingRecording, .monitoring:
            break
        }
    }

    private func armAckTimeout(_ captureID: String) {
        let timeout = captureAckTimeout
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            self?.tell(MCAckTimeout(captureID: captureID))
        }
    }

    /// Any camera silent past the deadline is settled so the aggregate always
    /// resolves: a silent photo lane failed; a silent recording-start lane
    /// voids the whole take (all-or-nothing); a silent stop lane is forced
    /// stopped.
    private func expireAcks(_ captureID: String) {
        let matches: Bool
        switch state {
        case .capturingPhoto(let id, _), .startingRecording(let id, _),
             .recording(let id, _), .stoppingRecording(let id, _):
            matches = id == captureID
        case .monitoring:
            matches = false
        }
        guard matches else { return }
        if !capturingLanes.isEmpty {
            logWarning("director: ack timeout \(shortID(captureID)) — silent: [\(names(Array(capturingLanes)))]")
        }

        switch state {
        case .startingRecording:
            for peer in capturingLanes { links[peer]?.captureOutcome = .failed }
            abortRecordingStart()
        case .capturingPhoto:
            for peer in capturingLanes { links[peer]?.captureOutcome = .failed }
            capturingLanes.removeAll()
            state = .monitoring
        case .stoppingRecording:
            for peer in capturingLanes { links[peer]?.recordingStartedAt = nil }
            clearRecordingTake()
            state = .monitoring
        case .recording, .monitoring:
            break // a rolling rig has no pending acks under all-or-nothing
        }
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
        Self.savePhotoToLibrary(data, originalFilename: name)
    }

    private func handleResourceStarted(_ started: ResourceTransferStarted) {
        guard let link = links[started.peer] else { return }
        link.collection = .transferring(0)
    }

    private func handleResourceFinished(_ finished: ResourceTransferFinished) {
        guard let link = links[finished.peer] else {
            // No lane owns this transfer any more (camera removed mid-flight);
            // still delete the temp file the transport handed us.
            finished.localURL.map(Self.discardTempFile)
            return
        }
        // The camera holds `.cameraTransmittingVideo` — where every capture
        // command is dropped — until the receiver confirms the transfer with
        // this echo (the 1:1 monitor's contract). Sent on failure too: the
        // camera returns to `.camera`, where the collection retry
        // (`RequestVideoResend`) is still answered.
        sendTo(finished.peer, RemoteCmd.StopRecordingVideoResp(
            sender: nil, pic: nil, error: finished.error.map { $0 as NSError }))
        guard finished.error == nil, let localURL = finished.localURL else {
            // Footage is still safe on the camera; the tile offers a retry. Any
            // partial temp file is ours to clean up.
            finished.localURL.map(Self.discardTempFile)
            link.collection = .failed
            return
        }
        link.collection = .collected
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
        let ok = transportShared.value?.send(msg, to: [peer], mode: mode) ?? false
        if !ok { logWarning("director: send \(type(of: msg)) → \(peer.displayName) FAILED") }
        return ok
    }

    /// Log helpers: peers by display name, capture ids by their first 8 chars.
    private func names(_ peers: [MCPeerID]) -> String {
        peers.map(\.displayName).joined(separator: ", ")
    }
    private func shortID(_ id: String) -> String { String(id.prefix(8)) }

    // MARK: - Snapshots

    // Each lane declares its own snapshot (see `CameraLink.snapshot`); the
    // controller gathers them in order, deriving the cross-cutting fields —
    // `isFocused` from `focusedPeer`, the re-match badge from the active rig
    // quality — at render time. Never stored, never synced.
    private func laneSnapshot() -> [MulticamLaneInfo] {
        order.compactMap { peer in
            guard let link = links[peer] else { return nil }
            let needsRematch: Bool
            if let active = activeVideoQuality,
               let info = link.capabilities?.getCurrentCameraInfo() {
                needsRematch = !RigQualityMenu.cameraCanMatch(
                    info, resolution: active.resolution, frameRate: active.frameRate)
            } else {
                needsRematch = false
            }
            return link.snapshot(isFocused: peer == focusedPeer, needsQualityRematch: needsRematch)
        }
    }

    private func isPeerCompatible(_ became: RemoteCmd.RoleAnnouncement) -> Bool {
        PeerAppCompatibility.isCompatible(remoteShortVersion: became.shortVersion)
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
    }

    public nonisolated func didReceiveFrameRequest(_ request: RemoteCmd.RequestFrame) {
        // The director never sends frames, so a frame-credit ack is a no-op.
    }

    public nonisolated func didReceiveFrame(_ frame: RemoteCmd.SendFrame, from peer: MCPeerID) {
        tell(RemoteCmd.OnFrame(forwarding: frame, from: peer))
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
final class MCFlipCamera: Message, @unchecked Sendable {
    let target: MCPeerID
    init(target: MCPeerID) { self.target = target; super.init(sender: nil) }
}
final class MCFocusAtPoint: Message, @unchecked Sendable {
    let x: Float
    let y: Float
    let target: MCPeerID
    init(x: Float, y: Float, target: MCPeerID) {
        self.x = x; self.y = y; self.target = target
        super.init(sender: nil)
    }
}
final class MCStartRecording: Message, @unchecked Sendable {}
final class MCStopRecording: Message, @unchecked Sendable {}
final class MCAutomaticVideoQuality: Message, @unchecked Sendable {}
final class MCAutomaticPhotoQuality: Message, @unchecked Sendable {}
final class MCTimerAdvance: Message, @unchecked Sendable {
    /// The countdown generation this tick belongs to (see `countdownGeneration`).
    let generation: Int
    init(generation: Int) { self.generation = generation; super.init(sender: nil) }
}

/// The capture-ack deadline for `captureID` passed — settle any silent lanes.
final class MCAckTimeout: Message, @unchecked Sendable {
    let captureID: String
    init(captureID: String) { self.captureID = captureID; super.init(sender: nil) }
}

final class MCPeerCommand: Message, @unchecked Sendable {
    enum Kind { case focus, invite, remove, disconnect, retryCollection, nudgeFrame, requestKeyframe, reconnectTick, capsRetryTick }
    let kind: Kind
    let peer: MCPeerID
    init(_ kind: Kind, _ peer: MCPeerID) { self.kind = kind; self.peer = peer; super.init(sender: nil) }
}

final class MCToggleTorch: Message, @unchecked Sendable {
    let target: MCPeerID
    init(target: MCPeerID) { self.target = target; super.init(sender: nil) }
}
final class MCToggleFlash: Message, @unchecked Sendable {
    let target: MCPeerID
    init(target: MCPeerID) { self.target = target; super.init(sender: nil) }
}
final class MCSetZoom: Message, @unchecked Sendable {
    let factor: CGFloat
    let target: MCPeerID
    init(_ factor: CGFloat, target: MCPeerID) {
        self.factor = factor; self.target = target
        super.init(sender: nil)
    }
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

final class MCSetAspectRatio: Message, @unchecked Sendable {
    let ratio: AspectRatio
    init(_ ratio: AspectRatio) { self.ratio = ratio; super.init(sender: nil) }
}

final class MCSetRigStandby: Message, @unchecked Sendable {
    let on: Bool
    init(_ on: Bool) { self.on = on; super.init(sender: nil) }
}
final class MCSetRigTimer: Message, @unchecked Sendable {
    let seconds: Int
    init(_ seconds: Int) { self.seconds = seconds; super.init(sender: nil) }
}
