//
//  MulticamController.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

// swiftlint:disable cyclomatic_complexity function_body_length

import Foundation
import MPCCompat
import Stormo
import UIKit

/// The director's aggregate posture across all cameras. One shutter drives
/// them all, so the capture states are aggregate, not per-camera.
enum MulticamState: Equatable {
    case monitoring(mode: MonitorMode)
    /// A synced photo is in flight: `acksRemaining` cameras have yet to accept
    /// or refuse `captureId`. Returns to `.monitoring` when it reaches zero.
    case capturingPhoto(captureId: String, acksRemaining: Int)
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
}

/// The main-actor bridge from the controller to the multicam screen — the
/// multicam analog of `MonitorDisplay`. Low-frequency lane changes go through
/// `applyLanes`; the ~20fps preview stream goes through `receiveFrame`, which
/// the view controller routes to exactly one lane's decoder so a frame from
/// camera B never re-renders camera A.
protocol MulticamDisplay: AnyObject {
    func applyLanes(_ lanes: [MulticamLaneInfo])
    /// A synced photo is (or is no longer) in flight — drives the shutter ring.
    func applyCaptureInFlight(_ inFlight: Bool)
    func receiveFrame(_ frame: RemoteCmd.OnFrame)
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

    /// One id per director session, part of every capture's filename group.
    private let sessionID = UUID().uuidString
    /// Cameras that have yet to answer the in-flight synced capture. Empty
    /// unless `state` is `.capturingPhoto`.
    private var capturingLanes: Set<MCPeerID> = []
    private var currentCaptureID: String?

    /// Lead time before a synced shutter fires — long enough to cover the
    /// worst-case one-way latency plus a retransmit and scheduling slop, so
    /// every camera has the command in hand before the instant arrives.
    private let captureLeadMillis: UInt64 = 150
    /// How long a camera has to answer before it is counted as failed.
    private var captureAckTimeout: TimeInterval = 3

    private weak var display: MulticamDisplay?

    /// The interval between clock-offset refreshes per camera.
    private let clockSyncInterval: TimeInterval = 30
    /// How far ahead a re-invite waits before re-browsing a dropped camera.
    private var reconnectRetryDelay: TimeInterval = 3
    private let reconnectInviteTimeout: TimeInterval = 10

    // MARK: Test / wiring seams

    func setDisplay(_ display: MulticamDisplay) {
        self.display = display
        // The display is wired after `install` (the screen is pushed only once
        // the handoff is done), so replay the current lanes now — otherwise the
        // first snapshot, emitted during install, reaches no one.
        publishLanes()
    }
    func setReconnectRetryDelay(_ delay: TimeInterval) { reconnectRetryDelay = delay }

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
        publishLanes()
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

    func handle(_ msg: Message) async {
        switch msg {
        case let connected as OnConnectToDevice:
            handlePeerConnected(connected.peer)

        case let disconnected as DisconnectPeer:
            if let peer = disconnected.peer { handlePeerDisconnected(peer) }

        case let found as UICmd.BrowserFoundPeer:
            handleBrowserFound(found.peer)

        case let routed as RoutedMessage:
            await handleRouted(routed.message, from: routed.peer)

        case let frame as RemoteCmd.OnFrame:
            handleFrame(frame)

        case let measured as ClockPongMeasured:
            storePong(measured.pong, t3: measured.t3, from: measured.peer)

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
                publishLanes()
            }

        case let caps as RemoteCmd.CameraCapabilitiesResp:
            link.capabilities = caps
            if link.status != .failed { link.status = .linked }
            publishLanes()
            // A multicam-capable camera gets an immediate clock probe so its
            // offset is ready well before the first synced capture (PR4).
            if link.supportsMulticam {
                sendTo(peer, RemoteCmd.ClockSyncPing(t0Millis: SyncClock.nowMillis()))
            }

        case let ack as RemoteCmd.ScheduledCaptureAck:
            recordCaptureAck(from: peer, outcome: ack.error == nil ? .captured : .failed)

        case is RemoteCmd.TakePicAck:
            // The fallback (plain TakePic) path's positive ack.
            recordCaptureAck(from: peer, outcome: .captured)

        case let resp as RemoteCmd.TakePicResp:
            // Fallback failure signal; a success here is a duplicate of the ack
            // and is ignored (the lane is already resolved).
            if resp.error != nil { recordCaptureAck(from: peer, outcome: .failed) }

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
        focusedPeer = focusedPeer ?? peer
        beginHandshake(with: peer)
        publishLanes()
    }

    private func handlePeerDisconnected(_ peer: MCPeerID) {
        guard let link = links[peer] else { return }
        // Degrade the tile, keep the rest of the rig recording/monitoring. The
        // controller stays browsing, so `browserDidFindPeer` re-invites.
        link.status = .reconnecting
        publishLanes()
        armReconnect(peer)
    }

    private func handleBrowserFound(_ peer: MCPeerID) {
        // Re-invite only a camera we are actively missing; a fresh peer is a
        // job for the add-camera flow (PR7), not an auto-join.
        guard let link = links[peer], link.status == .reconnecting else { return }
        multipeerService?.invitePeer(peer, timeout: reconnectInviteTimeout)
    }

    private func armReconnect(_ peer: MCPeerID) {
        let delay = reconnectRetryDelay
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self else { return }
            await self.reBrowseIfStillMissing(peer)
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
        display?.receiveFrame(frame)
        sendTo(frame.peerId, RemoteCmd.RequestFrame(sender: nil))
    }

    // MARK: - Per-camera controls (focused peer only)

    /// PR3 wires these to the focused lane; capture (all-camera) lands in PR4.
    func setZoom(_ factor: CGFloat) { focusedSend(RemoteCmd.SetZoom(zoomFactor: factor)) }
    func toggleTorch() { focusedSend(RemoteCmd.ToggleTorch()) }

    func focusAtPoint(x: Float, y: Float) {
        guard let peer = focusedPeer, links[peer]?.capabilities?.supportsFocusPoint == true else { return }
        sendTo(peer, RemoteCmd.FocusAtPoint(x: x, y: y))
    }

    func switchLens(_ lens: CameraLensType) { focusedSend(RemoteCmd.SwitchLens(lensType: lens)) }

    func setFocusedPeer(_ peer: MCPeerID) {
        guard links[peer] != nil else { return }
        focusedPeer = peer
        publishLanes()
    }

    /// Logically remove a camera from the rig. The QUIC session has no
    /// per-peer teardown, so this stops the lane (no more acks/handshakes) and
    /// drops it from the UI; the peer times out on its side. A true per-peer
    /// disconnect needs a transport API and is out of scope here.
    func removeCamera(_ peer: MCPeerID) {
        links[peer] = nil
        order.removeAll { $0 == peer }
        if focusedPeer == peer { focusedPeer = order.first }
        publishLanes()
    }

    private func focusedSend(_ msg: Message) {
        guard let peer = focusedPeer else { return }
        sendTo(peer, msg)
    }

    // MARK: - Synced photo capture (all cameras)

    /// Test seam.
    func setCaptureAckTimeout(_ t: TimeInterval) { captureAckTimeout = t }
    func captureStateForTesting() -> (id: String, remaining: Int)? {
        if case .capturingPhoto(let id, let remaining) = state { return (id, remaining) }
        return nil
    }
    func captureOutcomeForTesting(_ peer: MCPeerID) -> CaptureOutcome? { links[peer]?.captureOutcome }

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

    /// Fire a synced photo on every ready multicam camera. When each camera's
    /// clock offset is known, the shutter is scheduled at a shared instant
    /// (`ScheduledCapture`) so the exposures line up sub-frame; if any offset
    /// is still missing it falls back to a plain fan-out (`TakePic`) — the same
    /// shot id groups both paths. No-op if nothing is ready or a capture is
    /// already in flight.
    func capturePhoto() {
        guard case .monitoring = state else { return }
        let ready = order.compactMap { links[$0] }
            .filter { $0.status == .linked && $0.supportsMulticam }
        guard !ready.isEmpty else { return }

        let captureID = UUID().uuidString
        capturingLanes = Set(ready.map(\.peerID))
        currentCaptureID = captureID
        for link in ready { link.captureOutcome = nil }

        let everyOffsetKnown = ready.allSatisfy { $0.latestOffset != nil }
        if everyOffsetKnown {
            let fireAt = SyncClock.nowMillis() + captureLeadMillis
            for (index, link) in ready.enumerated() {
                let offset = link.latestOffset?.offsetMillis ?? 0
                let fireAtCameraClock = UInt64(Int64(fireAt) + offset)
                sendTo(link.peerID, RemoteCmd.ScheduledCapture(
                    fireAtCameraClockMillis: fireAtCameraClock,
                    anchorMillis: fireAt,
                    captureId: captureID,
                    sessionId: sessionID,
                    cameraIndex: index + 1))
            }
        } else {
            // Fallback: not every clock is measured yet, so we can't promise a
            // sub-frame shutter — take the shot immediately on each camera.
            for link in ready {
                sendTo(link.peerID, RemoteCmd.TakePic(sender: nil, sendMediaToPeer: false))
            }
        }

        state = .capturingPhoto(captureId: captureID, acksRemaining: capturingLanes.count)
        publishLanes()
        armCaptureTimeout(captureID)
    }

    /// A camera answered the in-flight capture (accepted or refused). Counts it
    /// once; later duplicate acks (e.g. a scheduled camera also sends TakePic
    /// acks after it fires) are ignored.
    private func recordCaptureAck(from peer: MCPeerID, outcome: CaptureOutcome) {
        guard case .capturingPhoto(let captureID, _) = state,
              capturingLanes.contains(peer) else { return }
        links[peer]?.captureOutcome = outcome
        capturingLanes.remove(peer)
        let remaining = capturingLanes.count
        state = remaining == 0
            ? .monitoring(mode: .photo)
            : .capturingPhoto(captureId: captureID, acksRemaining: remaining)
        publishLanes()
    }

    private func armCaptureTimeout(_ captureID: String) {
        let timeout = captureAckTimeout
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard let self else { return }
            await self.expireCaptureAcks(captureID)
        }
    }

    /// Any camera that never answered by the deadline is counted as failed, so
    /// the aggregate always resolves back to monitoring.
    private func expireCaptureAcks(_ captureID: String) {
        guard case .capturingPhoto(let inFlight, _) = state, inFlight == captureID else { return }
        for peer in capturingLanes { links[peer]?.captureOutcome = .failed }
        capturingLanes.removeAll()
        currentCaptureID = nil
        state = .monitoring(mode: .photo)
        publishLanes()
    }

    /// A lane's stall watchdog fired — re-request a frame to unstick just that
    /// camera's pump (the others are unaffected).
    func nudgeFrame(for peer: MCPeerID) {
        guard links[peer] != nil else { return }
        sendTo(peer, RemoteCmd.RequestFrame(sender: nil))
    }

    /// A lane's decoder desynced — force a keyframe, but only from a camera
    /// that has proven it speaks VP9 (else an old peer reads the unknown
    /// action as TakePicture). Mirrors the 1:1 `requestKeyframeIfVP9` gate.
    func requestKeyframe(for peer: MCPeerID) {
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

    private func laneSnapshot() -> [MulticamLaneInfo] {
        order.compactMap { peer in
            guard let link = links[peer] else { return nil }
            return MulticamLaneInfo(
                peerID: peer,
                displayName: link.displayName,
                status: link.status,
                isFocused: peer == focusedPeer,
                clockOffsetMillis: link.latestOffset?.offsetMillis,
                captureOutcome: link.captureOutcome)
        }
    }

    private func publishLanes() {
        let snapshot = laneSnapshot()
        let inFlight: Bool
        if case .capturingPhoto = state { inFlight = true } else { inFlight = false }
        let display = display
        OperationQueue.main.addOperation {
            display?.applyLanes(snapshot)
            display?.applyCaptureInFlight(inFlight)
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
        publishLanes()
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
    public nonisolated func didStartReceivingResource(name: String, progress: Progress) {}
    public nonisolated func didFinishReceivingResource(name: String, at localURL: URL?, error: Error?) {}
}
