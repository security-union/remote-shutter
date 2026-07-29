//
//  SessionCoordinator.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

// swiftlint:disable file_length cyclomatic_complexity function_body_length type_body_length
// The per-state message switches ARE the state machine — their width is the
// protocol's width, previously spread across seven Theater state files.

import Foundation
import MPCCompat
import Stormo
import Combine
import UIKit
import Photos

// MARK: - State

/// Which monitor screen mode the `.monitor` state is showing.
enum MonitorMode: Equatable {
    case photo
    case video
}

/// Where a lens-switch transient returns when it completes (it can be entered
/// from either monitor mode or from an active recording).
enum LensSwitchReturn: Equatable {
    case mode(MonitorMode)
    case recording
}

/// The session's complete state space — every `become` state of the old
/// Theater machine as a compiler-checked case. Transient states carry their
/// timeout generation; states whose "stack parent" varies carry where they
/// return to.
enum SessionState: Equatable {
    case waitingForLobby
    case lobby
    case scanning
    case connected

    // Camera family
    case camera
    case cameraTakingPic(sendMediaToPeer: Bool, generation: Int)
    case cameraRecordingVideo
    case cameraTransmittingVideo

    // Monitor family
    case monitor(mode: MonitorMode)
    case monitorTakingPicture(generation: Int)
    case monitorTogglingFlash(generation: Int)
    case monitorTogglingCamera(mode: MonitorMode, generation: Int)
    case monitorSwitchingLens(returnTo: LensSwitchReturn, generation: Int)
    case monitorRecordingVideo
    case monitorWaitingForVideo

    // Watch family (no transport, no lobby)
    case watchCamera
    case watchCameraTakingPic(generation: Int)
    case watchCameraStartingVideo(generation: Int)
    case watchCameraRecordingVideo(stopGeneration: Int?)

    /// The old state-name vocabulary, for tests and logs.
    var name: RemoteCamState {
        switch self {
        case .waitingForLobby: return .idle
        case .lobby: return .idle
        case .scanning: return .scanning
        case .connected: return .connected
        case .camera: return .camera
        case .cameraTakingPic: return .cameraTakingPic
        case .cameraRecordingVideo: return .cameraRecordingVideo
        case .cameraTransmittingVideo: return .cameraTransmittingVideo
        case .monitor: return .monitor
        case .monitorTakingPicture: return .monitorTakingPicture
        case .monitorTogglingFlash: return .monitorTogglingFlash
        case .monitorTogglingCamera: return .monitorTogglingCamera
        case .monitorSwitchingLens: return .monitorSwitchingLens
        case .monitorRecordingVideo: return .monitorRecordingVideo
        case .monitorWaitingForVideo: return .monitorWaitingForVideo
        case .watchCamera: return .watchRemoteCamera
        case .watchCameraTakingPic: return .watchRemoteCameraTakingPic
        case .watchCameraStartingVideo: return .watchRemoteCameraStartingVideo
        case .watchCameraRecordingVideo: return .watchRemoteCameraRecordingVideo
        }
    }
}

// MARK: - Internal messages

/// Deferred transitions — the old machine enqueued these back onto its mailbox
/// so already-queued messages could land in the current state first. The FIFO
/// inbox reproduces that exactly.
final class DeferredPopToCamera: Message, @unchecked Sendable {}
final class DeferredPopAndScan: Message, @unchecked Sendable {}
/// Incompatibility detected by the transport (routed through the inbox — the
/// old code mutated state directly on the delegate thread).
final class IncompatibilityDetected: Message, @unchecked Sendable {}
/// Retry tick for the capabilities ladder.
final class RetryCapabilities: Message, @unchecked Sendable {
    let attempt: Int
    init(attempt: Int) {
        self.attempt = attempt
        super.init()
    }
}

// MARK: - Coordinator

/**
 The session state machine: a Swift actor with a FIFO inbox.

 Messages enter through `tell(_:)` (any thread, ordered) and are processed
 one at a time by the pump task — the same serialization contract as the
 Theater mailbox it replaces, but with the state space as a compiler-checked
 enum: adding an event and forgetting a state is now a build error, and
 dropped messages are explicit `default` branches instead of silent falls
 through a closure stack.
 */
public actor SessionCoordinator {

    // MARK: Inbox

    private nonisolated let inboxContinuation: Locked<AsyncStream<Message>.Continuation?> = Locked(nil)
    private nonisolated let pendingCount = Locked(0)

    public init() {
        var continuation: AsyncStream<Message>.Continuation!
        let stream = AsyncStream<Message>(bufferingPolicy: .unbounded) { continuation = $0 }
        self.inboxContinuation.value = continuation
        let pending = pendingCount
        // The pump task keeps itself alive until the stream finishes (stop()),
        // so no reference is retained here.
        Task { [weak self] in
            for await msg in stream {
                guard let self else { break }
                await self.handle(msg)
                pending.mutate { $0 -= 1 }
            }
        }
    }

    /// Fire-and-forget, callable from any thread; delivery order is the call
    /// order (the stream continuation is the serialization point).
    public nonisolated func tell(_ msg: Message) {
        pendingCount.mutate { $0 += 1 }
        inboxContinuation.value?.yield(msg)
    }

    /// Test support: suspends until every message enqueued so far is processed.
    public nonisolated func waitForIdle() async {
        while pendingCount.value > 0 {
            await Task.yield()
        }
    }

    /// Shuts the session down: stops the transport and closes the inbox.
    /// Callable from deinit paths (any thread).
    public nonisolated func stop() {
        transportShared.value?.stopSession()
        inboxContinuation.value?.finish()
    }

    // MARK: State & context

    private(set) var state: SessionState = .waitingForLobby

    private var lobby: WeakScannerLobby?
    private var peer: MCPeerID?
    private var ctrl: CameraControlling?
    private var monitor: MonitorPresenter?

    /// Whether the connected camera peer advertised a camera-device list in
    /// its capabilities — the feature gate for `RemoteCmd.SelectCameraDevice`.
    /// Never send that command otherwise: old decoders read unknown command
    /// actions as TakePicture (the FlatBuffers field default).
    private var peerAdvertisedCameraDevices = false

    /// Whether the connected camera peer advertised focus-point support in its
    /// capabilities — the feature gate for `RemoteCmd.FocusAtPoint`. Never send
    /// that command otherwise: old decoders read unknown command actions as
    /// TakePicture (same precedent as SelectCameraDevice).
    private var peerSupportsFocusPoint = false

    /// Test support.
    func peerSupportsFocusPointForTesting() -> Bool { peerSupportsFocusPoint }

    /// Monitor side: at least one VP9 preview frame has arrived. Proves the
    /// camera peer speaks VP9, which gates sending `RemoteCmd.RequestKeyframe`
    /// (old decoders read that unknown action as TakePicture — same precedent as
    /// SelectCameraDevice).
    private var monitorReceivedVP9Frame = false

    /// Test support.
    func monitorReceivedVP9FrameForTesting() -> Bool { monitorReceivedVP9Frame }

    /// Test support: the generation of the most recently armed timeout.
    func currentTimeoutGeneration() -> Int { timeoutGeneration }

    /// Test support: the old state-name vocabulary.
    func currentStateName() -> RemoteCamState {
        state.name
    }

    /// Test support: place the machine directly into a state with context.
    func seed(state: SessionState,
              lobby: WeakScannerLobby? = nil,
              peer: MCPeerID? = nil,
              ctrl: CameraControlling? = nil,
              monitor: MonitorPresenter? = nil) {
        self.state = state
        if let lobby { self.lobby = lobby }
        if let peer { self.peer = peer }
        if let ctrl { self.ctrl = ctrl }
        if let monitor { self.monitor = monitor }
    }

    // MARK: Seams (injectable for tests)

    var alertPresenter: AlertPresenting = UIAlertPresenter()
    var watchStatePusher: WatchStatePushing = WatchSessionManager.shared
    var isPhoneBackgrounded: () -> Bool = { AppActivityMonitor.shared.isBackgrounded }
    lazy var photoLibrarySaver: (Data) -> Void = { [weak self] data in
        self?.savePictureToLibrary(data)
    }
    /// Seconds left on a Watch-initiated self-timer (0 = none). Mirrored from
    /// `TimerCountdown` ticks so every watch push carries the live countdown.
    var watchCountdownRemaining: Int32 = 0

    func setAlertPresenter(_ presenter: AlertPresenting) { alertPresenter = presenter }
    func setReconnectRetryDelay(_ delay: TimeInterval) { reconnectRetryDelay = delay }
    func setPeerLinkStatus(_ status: PeerLinkStatus) { peerLinkStatus = status }
    func setWatchStatePusher(_ pusher: WatchStatePushing) { watchStatePusher = pusher }
    func setIsPhoneBackgrounded(_ provider: @escaping () -> Bool) { isPhoneBackgrounded = provider }
    func setPhotoLibrarySaver(_ saver: @escaping (Data) -> Void) { photoLibrarySaver = saver }
    func setMultipeerService(_ service: any MultipeerServiceProtocol) {
        multipeerService = service
        transportShared.value = service
    }

    // MARK: Transport

    var multipeerService: (any MultipeerServiceProtocol)?
    /// Lock-boxed mirror for the frame path (FrameSender sends from the
    /// capture data queue without entering the actor).
    let transportShared = Locked<(any MultipeerServiceProtocol)?>(nil)

    /// The frame streamer, wired by whichever screen owns the session's
    /// lifetime. Lock-boxed: the transport delegate routes `RequestFrame`
    /// acks to it directly from the delegate thread, bypassing the inbox
    /// (frame pacing must not queue behind state-machine work).
    let frameSenderShared = Locked<FrameSender?>(nil)
    var frameSender: FrameSender? { frameSenderShared.value }
    nonisolated func setFrameSender(_ sender: FrameSender?) { frameSenderShared.value = sender }

    var connectedPeers: [MCPeerID] { multipeerService?.connectedPeers ?? [] }

    private func unableToProcessError(_ msg: Message) async -> NSError {
        let deviceName = await MainActor.run { UIDevice.current.name }
        return NSError(
            domain: "Unable to process \(type(of: msg)) command, since \(deviceName) is not in the camera screen.", code: 0, userInfo: nil)
    }

    @discardableResult
    func sendMessage(_ msg: Message, mode: MCSessionSendDataMode = .reliable) -> Bool {
        guard let multipeerService else {
            // Watch Remote mode never starts a multipeer session.
            return false
        }
        return !multipeerService.send(msg, to: connectedPeers, mode: mode).isFailure()
    }

    /// Send, or pop to scanning with a connection-error alert on failure —
    /// the old `sendCommandOrGoToScanning`.
    func sendOrGoToScanning(_ msg: Message, mode: MCSessionSendDataMode = .reliable) async {
        guard multipeerService != nil else {
            // Watch Remote mode: there is no peer and no scanning state to fall back to.
            debugLog("sendOrGoToScanning: no multipeer session, dropping \(type(of: msg))")
            return
        }
        if !sendMessage(msg, mode: mode) {
            await popToScanning()
            let presenter = alertPresenter
            OperationQueue.main.addOperation {
                presenter.showError(title: NSLocalizedString("Connection error", comment: ""))
            }
        }
    }

    // MARK: Connect retry

    /// In-flight invite bookkeeping. MC reports a declined or timed-out
    /// invitation only as the peer flipping to `.notConnected`, so the
    /// scanning state tracks whom it invited to tell that apart from a stray
    /// disconnect. One automatic retry rides the AWDL link the first attempt
    /// already warmed up — off-network, link bring-up alone can eat most of
    /// the first invite's timeout.
    private var pendingConnect: (peer: MCPeerID, attempt: Int)?

    // MARK: Peer-backgrounded reconnect (C-5)

    /// The peer we are waiting on, if any. Single source of truth: the
    /// overlay is rendered from `peerLinkStatus`, which only `setReconnecting`
    /// writes, so the UI cannot disagree with the machine.
    private var reconnecting: MCPeerID?
    private var peerLinkStatus: PeerLinkStatus = .shared
    private var reconnectRetryTask: Task<Void, Never>?
    /// Fixed retry cadence (no backoff by design); injectable for tests.
    private var reconnectRetryDelay: TimeInterval = 1
    private let reconnectInviteTimeout: TimeInterval = 5
    private let inviteTimeout: TimeInterval = 20
    private let maxConnectAttempts = 2

    private func startScanning(lobby: ScannerLobby) {
        pendingConnect = nil
        if multipeerService == nil {
            let service = MultipeerService(peerID: lobby.peerID)
            service.delegate = self
            multipeerService = service
            transportShared.value = service
        } else {
            multipeerService?.disconnect()
        }

        switch lobby.role {
        case .camera:
            multipeerService?.startAdvertisingOnly(discoveryInfo: ["role": "camera"])
        case .monitor:
            multipeerService?.startBrowsingOnly()
        }

        OperationQueue.main.addOperation {
            lobby.returnToLobby()
            lobby.scannerViewModel.startedScanning()
        }

        // Landed here mid-reconnect (grace expired, connection died): keep
        // the dialog up and start the fixed-cadence retry loop.
        if let waitingOn = reconnecting {
            armReconnectRetry(waitingOn)
        }
    }

    // MARK: Timeouts

    private var timeoutGeneration = 0

    /// Arms a 10s watchdog; the generation invalidates stale timers.
    private func scheduleTimeout(_ name: RemoteCamState) -> Int {
        timeoutGeneration += 1
        let generation = timeoutGeneration
        DispatchQueue.global().asyncAfter(deadline: .now() + 10.0) { [weak self] in
            self?.tell(UICmd.StateTimeout(stateName: name, generation: generation))
        }
        return generation
    }

    // MARK: Transitions

    /// Enter a state and run its entry behavior. Used for pushes, pops and
    /// in-place swaps alike — the old machine delivered `OnEnter` after every
    /// `become` AND every `unbecome`, and that re-entry behavior (re-render,
    /// re-request frames, re-bind the frame sender) is load-bearing.
    private func transition(to newState: SessionState) async {
        state = newState
        await didEnter(newState)
    }

    private func didEnter(_ newState: SessionState) async {
        switch newState {
        case .waitingForLobby, .lobby:
            break

        case .scanning:
            if let lobby = lobby?.value {
                startScanning(lobby: lobby)
            }

        case .connected:
            multipeerService?.stopAdvertisingAndBrowsing()
            if let lobby = lobby?.value {
                OperationQueue.main.addOperation {
                    lobby.scannerViewModel.stoppedScanning()
                    lobby.scannerViewModel.clearPeers()
                }
            }

        case .camera, .cameraRecordingVideo:
            if let peer, let transport = multipeerService {
                frameSender?.setSession(peer: peer, transport: transport)
            }

        case .cameraTakingPic, .cameraTransmittingVideo:
            break

        case .monitor(let mode):
            switch mode {
            case .photo: monitor?.renderPhotoMode()
            case .video: monitor?.renderVideoMode()
            }
            await requestFrame()

        case .monitorRecordingVideo:
            monitor?.renderVideoModeRecording()
            await requestFrame()

        case .monitorWaitingForVideo:
            monitor?.renderVideoMode()

        case .monitorTakingPicture, .monitorTogglingFlash, .monitorTogglingCamera, .monitorSwitchingLens:
            break

        case .watchCamera:
            watchCountdownRemaining = 0
            await pushWatchState()

        case .watchCameraTakingPic, .watchCameraStartingVideo, .watchCameraRecordingVideo:
            break
        }
    }

    private func requestFrame() async {
        await sendOrGoToScanning(RemoteCmd.RequestFrame(sender: nil))
    }

    /// Pop to scanning (stops at the lobby floor like the old machine) and
    /// restart discovery via `.scanning`'s entry behavior.
    func popToScanning() async {
        peerAdvertisedCameraDevices = false
        peerSupportsFocusPoint = false
        monitorReceivedVP9Frame = false
        switch state {
        case .scanning:
            // Already there — re-entering would restart discovery and reset
            // the lobby UI on every straggler failure after a disconnect.
            break
        case .waitingForLobby, .lobby, .watchCamera, .watchCameraTakingPic,
             .watchCameraStartingVideo, .watchCameraRecordingVideo:
            // No scanning below these states — nothing to pop to.
            break
        default:
            await transition(to: .scanning)
        }
    }

    // MARK: Message dispatch

    func handle(_ msg: Message) async {
        switch state {
        case .waitingForLobby:
            await inWaitingForLobby(msg)
        case .lobby:
            await inLobby(msg)
        case .scanning:
            await inScanning(msg)
        case .connected:
            await inConnected(msg)
        case .camera:
            await inCamera(msg)
        case .cameraTakingPic(let sendMediaToPeer, let generation):
            await inCameraTakingPic(msg, sendMediaToPeer: sendMediaToPeer, generation: generation)
        case .cameraRecordingVideo:
            await inCameraRecordingVideo(msg)
        case .cameraTransmittingVideo:
            await inCameraTransmittingVideo(msg)
        case .monitor(let mode):
            await inMonitor(msg, mode: mode)
        case .monitorTakingPicture(let generation):
            await inMonitorTakingPicture(msg, generation: generation)
        case .monitorTogglingFlash(let generation):
            await inMonitorToggling(msg, kind: .flash, mode: .photo, generation: generation)
        case .monitorTogglingCamera(let mode, let generation):
            await inMonitorToggling(msg, kind: .camera, mode: mode, generation: generation)
        case .monitorSwitchingLens(let returnTo, let generation):
            await inMonitorSwitchingLens(msg, returnTo: returnTo, generation: generation)
        case .monitorRecordingVideo:
            await inMonitorRecordingVideo(msg)
        case .monitorWaitingForVideo:
            await inMonitorWaitingForVideo(msg)
        case .watchCamera:
            await inWatchCamera(msg)
        case .watchCameraTakingPic(let generation):
            await inWatchCameraTakingPic(msg, generation: generation)
        case .watchCameraStartingVideo(let generation):
            await inWatchCameraStartingVideo(msg, generation: generation)
        case .watchCameraRecordingVideo(let stopGeneration):
            await inWatchCameraRecordingVideo(msg, stopGeneration: stopGeneration)
        }
    }

    // MARK: - Floor states

    private func inWaitingForLobby(_ msg: Message) async {
        switch msg {
        case let setLobby as SetScannerLobby:
            lobby = WeakScannerLobby(setLobby.lobby)
            state = .lobby
        default:
            await handleRoot(msg)
        }
    }

    private func inLobby(_ msg: Message) async {
        switch msg {
        case is UICmd.StartScanning:
            await transition(to: .scanning)
        default:
            await handleRoot(msg)
        }
    }

    // MARK: - Scanning / connected

    private func inScanning(_ msg: Message) async {
        guard let liveLobby = lobby?.value else { return } // dead lobby: drop

        switch msg {
        case is UICmd.BecomeCamera, is UICmd.BecomeMonitor, is UICmd.StartScanning:
            startScanning(lobby: liveLobby)

        case let connect as ConnectToDevice:
            pendingConnect = (connect.peer, 1)
            multipeerService?.invitePeer(connect.peer, timeout: inviteTimeout)
            OperationQueue.main.addOperation {
                liveLobby.scannerViewModel.connectingToPeer()
            }

        case let disconnected as DisconnectPeer:
            if let waitingOn = reconnecting, waitingOn == disconnected.peer {
                // Peer-backgrounded retry: fixed cadence, no attempt cap —
                // ends only on reconnect or the dialog's Cancel.
                armReconnectRetry(waitingOn)
                break
            }
            guard let pending = pendingConnect, pending.peer == disconnected.peer else {
                startScanning(lobby: liveLobby)
                break
            }
            if pending.attempt < maxConnectAttempts {
                pendingConnect = (pending.peer, pending.attempt + 1)
                multipeerService?.invitePeer(pending.peer, timeout: inviteTimeout)
            } else {
                pendingConnect = nil
                OperationQueue.main.addOperation {
                    liveLobby.scannerViewModel.connectionFailed()
                }
            }

        case let retry as UICmd.RetryReconnect:
            guard let waitingOn = reconnecting, waitingOn == retry.peer else { break }
            // Only the monitor invites; the camera's retry is advertising and
            // auto-accepting, which scanning already does.
            if liveLobby.role == .monitor {
                pendingConnect = (waitingOn, 1)
                multipeerService?.invitePeer(waitingOn, timeout: reconnectInviteTimeout)
            }

        case is UICmd.CancelConnect:
            pendingConnect = nil
            // Tearing the session down is the only way to abort an in-flight
            // invite; the next invite starts from a fresh session anyway.
            multipeerService?.disconnect()
            OperationQueue.main.addOperation {
                liveLobby.scannerViewModel.connectCancelled()
            }

        case is Disconnect:
            pendingConnect = nil

        case let connected as OnConnectToDevice:
            pendingConnect = nil
            endReconnect(ifPeer: connected.peer)
            peer = connected.peer
            OperationQueue.main.addOperation {
                liveLobby.scannerViewModel.connectedToPeer()
            }
            await transition(to: .connected)
            OperationQueue.main.addOperation {
                liveLobby.goToRole()
            }

        case let found as UICmd.BrowserFoundPeer:
            OperationQueue.main.addOperation {
                liveLobby.scannerViewModel.addPeer(found.peer)
            }

        case let lost as UICmd.BrowserLostPeer:
            OperationQueue.main.addOperation {
                liveLobby.scannerViewModel.removePeer(lost.peer)
            }

        case is UICmd.BrowserFailed:
            OperationQueue.main.addOperation {
                liveLobby.scannerViewModel.scanningFailed()
                liveLobby.presentScanningError()
            }

        default:
            await handleRoot(msg)
        }
    }

    private func inConnected(_ msg: Message) async {
        guard lobby?.value != nil else {
            await popToScanning()
            return
        }

        switch msg {
        case let become as UICmd.BecomeCamera:
            ctrl = become.ctrl
            await transition(to: .camera)
            await sendOrGoToScanning(RemoteCmd.PeerBecameCamera.createWithDefaults())

        case let become as UICmd.BecomeMonitor:
            monitor = become.presenter
            await transition(to: .monitor(mode: become.mode == .Photo ? .photo : .video))
            await sendOrGoToScanning(RemoteCmd.PeerBecameMonitor.createWithDefaults())

        case let became as RemoteCmd.PeerBecameCamera:
            if became.bundleVersion <= 0 {
                await showIncompatibilityMessage()
            }
            // NOTE: a monitor never version-gates the camera — an old camera
            // streams HEIC/JPEG stills, which this monitor still decodes. Only
            // the `<= 0` incompatibility (unknown build) is reported, as before.
            // (Auto-role-follow forwarding was wired to an actor that was never
            // registered; the dead send is not reproduced.)

        case let became as RemoteCmd.PeerBecameMonitor:
            // This device is the camera-to-be; a monitor too old to decode VP9
            // must update rather than see a broken preview. One check covers
            // both the legacy (`<= 0`) and too-old cases.
            await enforceMonitorVP9Compatibility(became)

        case is Disconnect:
            await popToScanning()

        case let disconnected as DisconnectPeer:
            if disconnected.peer == peer && connectedPeers.isEmpty {
                await popToScanning()
            }

        default:
            await handleRoot(msg)
        }
    }

    // MARK: - Camera family

    private func inCamera(_ msg: Message) async {
        guard let ctrl else { return }
        guard lobby?.value != nil else {
            await popToScanning()
            return
        }

        switch msg {
        case let became as RemoteCmd.PeerBecameMonitor:
            // Version-gate the monitor before answering: a monitor too old to
            // decode VP9 is sent to the update-required flow (this pops out of
            // the camera state), so we don't stream it an undecodable preview.
            guard await enforceMonitorVP9Compatibility(became) else { break }
            await attemptToSendCapabilities(attempt: 0)

        case is RemoteCmd.RequestCameraCapabilities:
            await attemptToSendCapabilities(attempt: 0)

        case is RemoteCmd.RequestKeyframe:
            // The monitor's VP9 decoder desynced — force the next preview frame
            // to be a keyframe. Straight to the streamer; no state change.
            frameSender?.requestKeyframe()

        case is RemoteCmd.RequestFrame, is RemoteCmd.SendFrame:
            break // frame plumbing is FrameSender's job

        case is UICmd.ToggleCameraResp:
            await sendOrGoToScanning(RemoteCmd.ToggleCameraResp(
                cameraCapabilities: nil, error: unableToProcessError(msg)))

        case is RemoteCmd.StartRecordingVideo:
            ctrl.currentCameraMode = .Video
            ctrl.updateCameraStatus()
            ctrl.startRecordingVideo()
            await transition(to: .cameraRecordingVideo)

        case is UICmd.MicrophoneAccessDenied:
            await sendOrGoToScanning(RemoteCmd.StopRecordingVideoAck(sender: nil), mode: .reliable)
            await sendOrGoToScanning(RemoteCmd.StopRecordingVideoResp(
                sender: nil, pic: nil, error: unableToProcessError(msg)), mode: .reliable)

        case let pic as RemoteCmd.TakePic:
            ctrl.currentCameraMode = .Photo
            ctrl.updateCameraStatus()
            ctrl.takePicture(pic.sendMediaToPeer)
            let generation = scheduleTimeout(.cameraTakingPic)
            await showCameraAlert(NSLocalizedString("Taking picture", comment: ""))
            await transition(to: .cameraTakingPic(sendMediaToPeer: pic.sendMediaToPeer, generation: generation))

        case is RemoteCmd.ToggleCamera:
            do {
                _ = try await ctrl.toggleCamera()
                try await confirmFrameDelivery(ctrl)
                await ctrl.gatherAllCameraCapabilities()
                let capabilities = await ctrl.gatherCurrentCameraCapabilities()
                await sendOrGoToScanning(RemoteCmd.ToggleCameraResp(
                    cameraCapabilities: capabilities, error: nil))
            } catch {
                await sendOrGoToScanning(RemoteCmd.ToggleCameraResp(
                    cameraCapabilities: nil, error: error as NSError))
            }

        case let select as RemoteCmd.SelectCameraDevice:
            do {
                _ = try await ctrl.selectCameraDevice(uniqueID: select.uniqueID)
                try await confirmFrameDelivery(ctrl)
                await ctrl.gatherAllCameraCapabilities()
                let capabilities = await ctrl.gatherCurrentCameraCapabilities()
                await sendOrGoToScanning(RemoteCmd.SelectCameraDeviceResp(
                    cameraCapabilities: capabilities, error: nil))
            } catch {
                await sendOrGoToScanning(RemoteCmd.SelectCameraDeviceResp(
                    cameraCapabilities: nil, error: error as NSError))
            }

        case is RemoteCmd.ToggleFlash:
            do {
                let flashMode = try await ctrl.toggleFlash()
                await sendOrGoToScanning(RemoteCmd.ToggleFlashResp(flashMode: flashMode, error: nil))
            } catch {
                await sendOrGoToScanning(RemoteCmd.ToggleFlashResp(flashMode: nil, error: error as NSError))
            }

        case is RemoteCmd.ToggleTorch:
            do {
                let torchMode = try await ctrl.toggleTorch()
                await sendOrGoToScanning(RemoteCmd.ToggleTorchResp(torchMode: torchMode, error: nil))
            } catch {
                await sendOrGoToScanning(RemoteCmd.ToggleTorchResp(torchMode: nil, error: error as NSError))
            }

        case let torch as RemoteCmd.SetTorch:
            do {
                let torchMode = try await ctrl.setTorchMode(mode: torch.torchMode)
                await sendOrGoToScanning(RemoteCmd.SetTorchResp(torchMode: torchMode, error: nil))
            } catch {
                await sendOrGoToScanning(RemoteCmd.SetTorchResp(torchMode: nil, error: error as NSError))
            }

        case let zoom as RemoteCmd.SetZoom:
            do {
                let (factor, lens, range) = try await ctrl.setZoom(zoomFactor: zoom.zoomFactor)
                await sendOrGoToScanning(RemoteCmd.SetZoomResp(
                    zoomFactor: factor, currentLens: lens, zoomRange: range, error: nil))
            } catch {
                await sendOrGoToScanning(RemoteCmd.SetZoomResp(
                    zoomFactor: nil, currentLens: nil, zoomRange: nil, error: error as NSError))
            }

        case let focus as RemoteCmd.FocusAtPoint:
            // Fire-and-forget: the monitor already showed its reticle. A device
            // without a focus point simply ignores it.
            try? await ctrl.focusAtPoint(x: focus.x, y: focus.y)

        case let lens as RemoteCmd.SwitchLens:
            do {
                let (lensType, available, zoom, range) = try await ctrl.switchLens(to: lens.lensType)
                await sendOrGoToScanning(RemoteCmd.SwitchLensResp(
                    lensType: lensType, availableLenses: available, currentZoom: zoom, zoomRange: range, error: nil))
            } catch {
                await sendOrGoToScanning(RemoteCmd.SwitchLensResp(
                    lensType: nil, availableLenses: nil, currentZoom: nil, zoomRange: nil, error: error as NSError))
            }

        case let sync as RemoteCmd.SyncMonitorSettings:
            let mode = sync.mode
            OperationQueue.main.addOperation {
                ctrl.currentCameraMode = mode
                ctrl.updateCameraStatus()
            }

        case let countdown as RemoteCmd.TimerCountdown:
            ctrl.updateTimerCountdown(value: countdown.value)

        case let quality as RemoteCmd.SetVideoQuality:
            if let (resolution, frameRate) = await ctrl.setVideoQuality(
                resolution: quality.resolution, frameRate: quality.frameRate) {
                await sendOrGoToScanning(RemoteCmd.SetVideoQualityResp(
                    resolution: resolution, frameRate: frameRate, error: nil))
            } else {
                await sendOrGoToScanning(RemoteCmd.SetVideoQualityResp(
                    resolution: nil, frameRate: nil, error: unableToProcessError(msg)))
            }

        case let quality as RemoteCmd.SetPhotoQuality:
            if let (format, hdrMode) = await ctrl.setPhotoQuality(
                format: quality.format, hdrMode: quality.hdrMode) {
                await sendOrGoToScanning(RemoteCmd.SetPhotoQualityResp(
                    format: format, hdrMode: hdrMode, error: nil))
            } else {
                await sendOrGoToScanning(RemoteCmd.SetPhotoQualityResp(
                    format: nil, hdrMode: nil, error: unableToProcessError(msg)))
            }

        case let ratio as RemoteCmd.SetAspectRatio:
            let applied = await ctrl.setAspectRatio(ratio.aspectRatio)
            await sendOrGoToScanning(RemoteCmd.SetAspectRatioResp(aspectRatio: applied, error: nil))

        case let disconnected as DisconnectPeer:
            if disconnected.peer == peer && connectedPeers.isEmpty {
                await popToScanning()
            }

        case is Disconnect:
            await popToScanning()

        case is UICmd.UnbecomeCamera:
            await transition(to: .connected)

        default:
            await handleRoot(msg)
        }
    }

    /// A camera can accept an input swap and still never deliver a frame (a
    /// wedged virtual camera): a switch is only *successful* once a frame
    /// actually arrives, so the monitor gets a real error instead of a
    /// silently black preview. Bounded wait — shorter than the rig watchdog
    /// (5s, which restores a working device) and the monitor's state timeout
    /// (10s). Deliberately blocks this camera's inbox meanwhile: the peer is
    /// waiting on this exact response, and busy states already reject
    /// concurrent commands.
    private func confirmFrameDelivery(_ ctrl: CameraControlling) async throws {
        guard await ctrl.awaitFrameDelivery(timeout: 4) else {
            let name = await ctrl.currentCameraDevice()?.localizedName ?? "Camera"
            throw NSError(
                domain: String(format: NSLocalizedString("%@ is not delivering video", comment: "dead camera"), name),
                code: 0, userInfo: nil)
        }
    }

    /// Capabilities retry ladder: the capture device isn't ready right after
    /// setup, so retry with growing delays (0.2s × attempt, max 5).
    private func attemptToSendCapabilities(attempt: Int) async {
        guard let ctrl else { return }
        await ctrl.gatherAllCameraCapabilities()
        if let capabilities = await ctrl.gatherCurrentCameraCapabilities() {
            await sendOrGoToScanning(capabilities)
        } else if attempt < 5 {
            let next = attempt + 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2 * Double(next)) { [weak self] in
                self?.tell(RetryCapabilities(attempt: next))
            }
        }
    }

    /// Camera side: a new camera always streams VP9, so a monitor too old to
    /// decode it must be told to update rather than shown a broken preview.
    /// Routes an out-of-date (or unknown-build, `<= 0`) monitor to the existing
    /// incompatibility flow — a single, version-in/verdict-out policy
    /// (`VP9PreviewCompatibility.peerCanDecodeVP9Preview`). Returns true when the
    /// monitor is compatible and the caller should continue, false when it
    /// popped to scanning. No per-connection capability handshake.
    @discardableResult
    private func enforceMonitorVP9Compatibility(_ became: RemoteCmd.PeerBecameMonitor) async -> Bool {
        guard VP9PreviewCompatibility.peerCanDecodeVP9Preview(bundleVersion: became.bundleVersion) else {
            StreamLog.encode.info("""
                monitor bundleVersion \(became.bundleVersion) < \
                \(VP9PreviewCompatibility.minimumPeerBundleVersion) — too old for VP9 preview, requesting update
                """)
            await showIncompatibilityMessage()
            return false
        }
        return true
    }

    /// Monitor side: latch that a VP9 frame arrived, which proves the camera
    /// peer speaks VP9 and unlocks `RemoteCmd.RequestKeyframe`.
    private func noteMonitorFrame(_ frame: RemoteCmd.OnFrame) {
        if frame.codec == .vp9 { monitorReceivedVP9Frame = true }
    }

    /// Monitor side: ask the camera for a keyframe, but only once it has proven
    /// itself a VP9-speaking peer (else the unknown action decodes as
    /// TakePicture on an old camera). Sent `.reliable` so recovery isn't lost.
    private func requestKeyframeIfVP9() {
        guard monitorReceivedVP9Frame else {
            debugLog("RequestKeyframe dropped: peer has not sent a VP9 frame")
            return
        }
        sendMessage(RemoteCmd.RequestKeyframe(sender: nil), mode: .reliable)
    }

    private func inCameraTakingPic(_ msg: Message, sendMediaToPeer: Bool, generation: Int) async {
        switch msg {
        case is RemoteCmd.RequestKeyframe:
            // The preview keeps streaming while a picture is taken, so a monitor
            // can desync here — and without this case the request falls through to
            // handleRoot's unhandled default and is dropped silently.
            frameSender?.requestKeyframe()

        case let timeout as UICmd.StateTimeout:
            guard timeout.stateName == .cameraTakingPic && timeout.generation == generation else { break }
            await dismissCameraAlert()
            let sent = sendMessage(RemoteCmd.TakePicResp(
                sender: nil,
                error: NSError(domain: "Timed out taking picture", code: 0, userInfo: nil)))
            if sent {
                await transition(to: .camera)
            } else {
                await popToScanning()
            }

        case let picture as UICmd.OnPicture:
            if let pic = picture.pic {
                photoLibrarySaver(pic)
            }
            await dismissCameraAlert()
            guard sendMessage(RemoteCmd.TakePicAck(sender: nil)) else {
                await popToScanning()
                return
            }
            let resp = RemoteCmd.TakePicResp(
                sender: nil,
                pic: sendMediaToPeer ? picture.pic : nil,
                error: picture.error)
            guard sendMessage(resp) else {
                await popToScanning()
                return
            }
            await transition(to: .camera)

        case let disconnected as DisconnectPeer:
            if disconnected.peer == peer && connectedPeers.isEmpty {
                await dismissCameraAlert()
                await popToScanning()
            }

        case is Disconnect:
            await dismissCameraAlert()
            await popToScanning()

        default:
            await handleRoot(msg)
        }
    }

    private func inCameraRecordingVideo(_ msg: Message) async {
        guard let ctrl else { return }

        switch msg {
        case let zoom as RemoteCmd.SetZoom:
            do {
                let (factor, lens, range) = try await ctrl.setZoom(zoomFactor: zoom.zoomFactor)
                await sendOrGoToScanning(RemoteCmd.SetZoomResp(
                    zoomFactor: factor, currentLens: lens, zoomRange: range, error: nil))
            } catch {
                await sendOrGoToScanning(RemoteCmd.SetZoomResp(
                    zoomFactor: nil, currentLens: nil, zoomRange: nil, error: error as NSError))
            }

        case let focus as RemoteCmd.FocusAtPoint:
            // Fire-and-forget; focusing is allowed while recording too.
            try? await ctrl.focusAtPoint(x: focus.x, y: focus.y)

        case let lens as RemoteCmd.SwitchLens:
            do {
                let (lensType, available, zoom, range) = try await ctrl.switchLens(to: lens.lensType)
                await sendOrGoToScanning(RemoteCmd.SwitchLensResp(
                    lensType: lensType, availableLenses: available, currentZoom: zoom, zoomRange: range, error: nil))
            } catch {
                await sendOrGoToScanning(RemoteCmd.SwitchLensResp(
                    lensType: nil, availableLenses: nil, currentZoom: nil, zoomRange: nil, error: error as NSError))
            }

        case is RemoteCmd.RequestKeyframe:
            // The preview stream keeps flowing while recording, so a desynced
            // monitor decoder can ask for a keyframe here too.
            frameSender?.requestKeyframe()

        case let ack as RemoteCmd.StartRecordingVideoAck:
            // The pipeline's success ack, carrying the recording start time for
            // the monitor's timer sync — forward across the wire.
            await sendOrGoToScanning(ack, mode: .reliable)

        case let stop as RemoteCmd.StopRecordingVideo:
            ctrl.stopRecordingVideo(stop.sendMediaToPeer)
            await sendOrGoToScanning(RemoteCmd.StopRecordingVideoAck(sender: nil), mode: .reliable)
            await transition(to: .cameraTransmittingVideo)

        case let disconnected as DisconnectPeer:
            if disconnected.peer == peer && connectedPeers.isEmpty {
                ctrl.stopRecordingVideo(false)
                await popToScanning()
            }

        case is Disconnect:
            ctrl.stopRecordingVideo(false)
            await popToScanning()

        case is UICmd.UnbecomeCamera:
            ctrl.stopRecordingVideo(false)
            await transition(to: .connected)

        case is UICmd.MicrophoneAccessDenied:
            await sendOrGoToScanning(RemoteCmd.StopRecordingVideoAck(sender: nil), mode: .reliable)
            await sendOrGoToScanning(RemoteCmd.StopRecordingVideoResp(
                sender: nil, pic: nil, error: unableToProcessError(msg)), mode: .reliable)
            await transition(to: .camera)

        default:
            await handleRoot(msg)
        }
    }

    private func inCameraTransmittingVideo(_ msg: Message) async {
        switch msg {
        case is RemoteCmd.RequestKeyframe:
            // A video file transfer saturates the link while the preview keeps
            // streaming, so this is one of the likeliest places to desync — and
            // the one place the request used to be dropped on the floor.
            frameSender?.requestKeyframe()

        case let started as UICmd.VideoResourceTransferStarted:
            ctrl?.cameraViewModel.startVideoTransfer(totalBytes: started.totalBytes)

        case let progress as UICmd.VideoResourceTransferProgress:
            ctrl?.cameraViewModel.updateVideoTransferProgress(
                completedBytes: progress.completedBytes, totalBytes: progress.totalBytes)
            ctrl?.cameraViewModel.updateVideoTransferSpeed(progress.transferSpeed)

        case is UICmd.VideoResourceTransferCompleted, is UICmd.VideoResourceTransferFailed:
            ctrl?.cameraViewModel.finishVideoTransfer()

        case let resp as RemoteCmd.StopRecordingVideoResp:
            await sendOrGoToScanning(resp)
            // Deferred so already-enqueued messages land in this state first.
            tell(DeferredPopToCamera())

        case is DeferredPopToCamera:
            await transition(to: .camera)

        case is DeferredPopAndScan:
            await popToScanning()

        case let disconnected as DisconnectPeer:
            if disconnected.peer == peer && connectedPeers.isEmpty {
                tell(DeferredPopAndScan())
            }

        case is Disconnect:
            tell(DeferredPopAndScan())

        default:
            await handleRoot(msg)
        }
    }

    // MARK: - Progress alerts (camera "Taking picture" and monitor transients)

    private var alertHandle: AlertHandle?

    private func showCameraAlert(_ title: String) async {
        let presenter = alertPresenter
        alertHandle = await withCheckedContinuation { continuation in
            OperationQueue.main.addOperation {
                continuation.resume(returning: presenter.showAlert(title: title))
            }
        }
    }

    private func updateCameraAlert(_ title: String) {
        guard let handle = alertHandle else { return }
        let presenter = alertPresenter
        OperationQueue.main.addOperation {
            presenter.updateAlert(handle, title: title)
        }
    }

    private func dismissCameraAlert() async {
        guard let handle = alertHandle else { return }
        alertHandle = nil
        let presenter = alertPresenter
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            OperationQueue.main.addOperation {
                presenter.dismissAlert(handle)
                continuation.resume()
            }
        }
    }

    private func showErrorAlert(_ title: String) {
        let presenter = alertPresenter
        OperationQueue.main.addOperation {
            presenter.showError(title: title)
        }
    }

    // MARK: - Peer-backgrounded reconnect flow (C-5)

    /// The only writer of the waiting state: model and published UI move
    /// together, so a live link and a visible overlay cannot coexist.
    private func setReconnecting(_ waitingOn: MCPeerID?) {
        reconnecting = waitingOn
        if waitingOn == nil {
            reconnectRetryTask?.cancel()
            reconnectRetryTask = nil
        }
        let status = peerLinkStatus
        let name = waitingOn?.displayName
        Task { @MainActor in
            if let name {
                status.setReconnecting(peerName: name)
            } else {
                status.setLinked()
            }
        }
    }

    /// The session peer announced suspension: start waiting. Within the grace
    /// the transport reconnects by itself (the app sees `PeerResumed`); past
    /// it, `DisconnectPeer` drops us to scanning where the retry loop takes
    /// over. Cancel is the only user exit.
    private func beginReconnect(with suspendedPeer: MCPeerID) {
        guard reconnecting == nil, suspendedPeer == peer else { return }
        setReconnecting(suspendedPeer)
    }

    /// Reconnected (resume within grace, or a scanning-loop invite landed).
    /// `nil` matches any peer.
    private func endReconnect(ifPeer resumedPeer: MCPeerID?) {
        guard let current = reconnecting,
              resumedPeer == nil || current == resumedPeer else { return }
        setReconnecting(nil)
    }

    private func cancelReconnect() async {
        guard reconnecting != nil else { return }
        setReconnecting(nil)
        pendingConnect = nil
        if case .scanning = state {
            if let liveLobby = lobby?.value {
                OperationQueue.main.addOperation {
                    liveLobby.scannerViewModel.connectCancelled()
                }
            }
        } else {
            // Still connected under grace: the user chose to leave now.
            multipeerService?.disconnect()
            await popToScanning()
        }
    }

    /// One fixed-cadence tick; each tick re-arms from the scanning handlers,
    /// so the loop dies with `reconnecting`.
    private func armReconnectRetry(_ peer: MCPeerID) {
        reconnectRetryTask?.cancel()
        let delay = reconnectRetryDelay
        reconnectRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.tell(UICmd.RetryReconnect(peer: peer))
        }
    }

    // MARK: - Root (any state whose handler delegates here)

    private func handleRoot(_ msg: Message) async {
        switch msg {
        case let suspended as UICmd.PeerSuspended:
            beginReconnect(with: suspended.peer)

        case let resumed as UICmd.PeerResumed:
            endReconnect(ifPeer: resumed.peer)

        case is UICmd.CancelReconnect:
            await cancelReconnect()

        case let become as UICmd.BecomeWatchCamera:
            ctrl = become.ctrl
            await transition(to: .watchCamera)

        case let request as UICmd.RequestWatchStateReply:
            await replyWithWatchState(request)

        case let rejected as UICmd.BecomeCamera:
            rejected.ctrl.exitCamera()

        case let rejected as UICmd.BecomeMonitor:
            rejected.presenter.becomeMonitorFailed()

        case is RemoteCmd.TakePic:
            await sendOrGoToScanning(RemoteCmd.TakePicResp(sender: nil, error: unableToProcessError(msg)))
        case is RemoteCmd.ToggleCamera:
            await sendOrGoToScanning(RemoteCmd.ToggleCameraResp(cameraCapabilities: nil, error: unableToProcessError(msg)))
        case is RemoteCmd.SelectCameraDevice:
            await sendOrGoToScanning(RemoteCmd.SelectCameraDeviceResp(cameraCapabilities: nil, error: unableToProcessError(msg)))
        case is RemoteCmd.ToggleFlash:
            await sendOrGoToScanning(RemoteCmd.ToggleFlashResp(flashMode: nil, error: unableToProcessError(msg)))
        case is RemoteCmd.SetZoom:
            await sendOrGoToScanning(RemoteCmd.SetZoomResp(zoomFactor: nil, currentLens: nil, zoomRange: nil, error: unableToProcessError(msg)))
        case is RemoteCmd.SwitchLens:
            await sendOrGoToScanning(RemoteCmd.SwitchLensResp(lensType: nil, availableLenses: nil, currentZoom: nil, zoomRange: nil, error: unableToProcessError(msg)))
        case is RemoteCmd.SetAspectRatio:
            await sendOrGoToScanning(RemoteCmd.SetAspectRatioResp(aspectRatio: nil, error: unableToProcessError(msg)))
        case is RemoteCmd.StartRecordingVideo:
            await sendOrGoToScanning(RemoteCmd.StartRecordingVideoAck(sender: nil, recordingStartTime: nil, error: unableToProcessError(msg)))
        case is RemoteCmd.StopRecordingVideo:
            await sendOrGoToScanning(RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: unableToProcessError(msg)))

        case let capabilities as RemoteCmd.CameraCapabilitiesResp:
            // Forward capabilities to the connected monitor.
            await sendOrGoToScanning(capabilities)

        case let retry as RetryCapabilities:
            await attemptToSendCapabilities(attempt: retry.attempt)

        case let sendVideo as UICmd.SendVideoResource:
            await handleSendVideoResource(sendVideo)

        case let started as UICmd.VideoResourceTransferStarted:
            monitor?.videoTransferStarted(totalBytes: started.totalBytes)

        case let progress as UICmd.VideoResourceTransferProgress:
            monitor?.videoTransferProgress(
                completedBytes: progress.completedBytes,
                totalBytes: progress.totalBytes,
                transferSpeed: progress.transferSpeed)

        case let completed as UICmd.VideoResourceTransferCompleted:
            monitor?.videoTransferFinished()
            if completed.success {
                await sendOrGoToScanning(RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: nil))
            }

        case let failed as UICmd.VideoResourceTransferFailed:
            monitor?.videoTransferFinished()
            await sendOrGoToScanning(RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: failed.error))

        case is IncompatibilityDetected:
            await showIncompatibilityMessage()

        case is FrameSendFailed:
            await popToScanning()
            showErrorAlert(NSLocalizedString("Connection error", comment: ""))

        default:
            debugLog("SessionCoordinator: message not handled \(type(of: msg)) in state \(state.name)")
        }
    }

    // MARK: - Video resource transfer (camera side)

    private func handleSendVideoResource(_ sendVideo: UICmd.SendVideoResource) async {
        guard sendVideo.shouldSendToPeer else {
            await sendOrGoToScanning(RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: nil))
            return
        }

        let peers = connectedPeers
        guard !peers.isEmpty, let multipeerService else {
            let error = NSError(domain: "VideoTransfer", code: 1, userInfo: [NSLocalizedDescriptionKey: "No connected peers"])
            tell(UICmd.VideoResourceTransferFailed(error: error, resourceName: "unknown", sender: nil))
            return
        }

        let fileSize: Int64
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: sendVideo.videoURL.path)
            fileSize = attributes[.size] as? Int64 ?? 0
        } catch {
            tell(UICmd.VideoResourceTransferFailed(error: error, resourceName: "unknown", sender: nil))
            return
        }

        let resourceName = "video_\(UUID().uuidString).mov"
        tell(UICmd.VideoResourceTransferStarted(totalBytes: fileSize, resourceName: resourceName, sender: nil))

        for peer in peers {
            let sendProgress = multipeerService.sendResource(
                at: sendVideo.videoURL,
                withName: resourceName,
                toPeer: peer
            ) { [weak self] error in
                if let error {
                    self?.tell(UICmd.VideoResourceTransferFailed(error: error, resourceName: resourceName, sender: nil))
                } else {
                    self?.tell(UICmd.VideoResourceTransferCompleted(resourceName: resourceName, success: true, sender: nil))
                }
            }

            if let progress = sendProgress {
                trackSendProgress(progress, resourceName: resourceName, into: multipeerService)
            }
        }
    }

    private nonisolated func trackSendProgress(_ progress: Progress,
                                               resourceName: String,
                                               into service: any MultipeerServiceProtocol) {
        final class SpeedTracker {
            var lastUpdateTime = Date()
            var lastCompletedBytes: Int64 = 0
            var lastCalculatedSpeed: Double = 0.0
        }
        let speedTracker = SpeedTracker()

        let service = service
        progress.publisher(for: \.fractionCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] fractionCompleted in
                let completedBytes = Int64(Double(progress.totalUnitCount) * fractionCompleted)
                let currentTime = Date()
                let timeElapsed = currentTime.timeIntervalSince(speedTracker.lastUpdateTime)
                let bytesTransferred = completedBytes - speedTracker.lastCompletedBytes

                let transferSpeed: Double
                if timeElapsed > 0.5 && bytesTransferred > 0 {
                    transferSpeed = Double(bytesTransferred) / timeElapsed
                    speedTracker.lastUpdateTime = currentTime
                    speedTracker.lastCompletedBytes = completedBytes
                    speedTracker.lastCalculatedSpeed = transferSpeed
                } else {
                    transferSpeed = speedTracker.lastCalculatedSpeed
                }

                self?.tell(UICmd.VideoResourceTransferProgress(
                    completedBytes: completedBytes,
                    totalBytes: progress.totalUnitCount,
                    progress: fractionCompleted,
                    resourceName: resourceName,
                    transferSpeed: transferSpeed,
                    sender: nil))
            }
            .store(in: &service.progressCancellables)
    }

    // MARK: - Monitor family

    private func inMonitor(_ msg: Message, mode: MonitorMode) async {
        switch msg {
        case let frame as RemoteCmd.OnFrame:
            noteMonitorFrame(frame)
            monitor?.show(frame: frame)
            await requestFrame()

        case is UICmd.StreamStalled:
            await requestFrame()

        case is UICmd.RequestVideoKeyframe:
            requestKeyframeIfVP9()

        case is UICmd.UnbecomeMonitor:
            await transition(to: .connected)

        case is UICmd.ToggleCamera:
            if sendMessage(RemoteCmd.ToggleCamera()) {
                await showCameraAlert("Requesting camera toggle")
                let generation = scheduleTimeout(.monitorTogglingCamera)
                await transition(to: .monitorTogglingCamera(mode: mode, generation: generation))
            } else {
                await popToScanning()
            }

        case let select as UICmd.SelectCameraDevice:
            guard peerAdvertisedCameraDevices else {
                debugLog("SelectCameraDevice dropped: peer did not advertise camera devices")
                break
            }
            if sendMessage(RemoteCmd.SelectCameraDevice(uniqueID: select.uniqueID)) {
                await showCameraAlert(NSLocalizedString("Switching camera", comment: ""))
                let generation = scheduleTimeout(.monitorTogglingCamera)
                await transition(to: .monitorTogglingCamera(mode: mode, generation: generation))
            } else {
                await popToScanning()
            }

        case is UICmd.ToggleFlash where mode == .photo:
            if sendMessage(RemoteCmd.ToggleFlash()) {
                await showCameraAlert("Requesting flash toggle")
                let generation = scheduleTimeout(.monitorTogglingFlash)
                await transition(to: .monitorTogglingFlash(generation: generation))
            } else {
                await popToScanning()
            }

        case is UICmd.ToggleTorch:
            sendMessage(RemoteCmd.ToggleTorch())

        case let countdown as UICmd.TimerCountdown:
            sendMessage(RemoteCmd.TimerCountdown(value: countdown.value))

        case let sync as UICmd.SyncMonitorSettings:
            sendMessage(RemoteCmd.SyncMonitorSettings(mode: sync.mode))

        case let take as UICmd.TakePicture:
            switch mode {
            case .photo:
                if sendMessage(RemoteCmd.TakePic(sender: nil, sendMediaToPeer: take.sendMediaToRemote)) {
                    await showCameraAlert(NSLocalizedString("Requesting picture", comment: ""))
                    let generation = scheduleTimeout(.monitorTakingPicture)
                    await transition(to: .monitorTakingPicture(generation: generation))
                } else {
                    await popToScanning()
                }
            case .video:
                if sendMessage(RemoteCmd.StartRecordingVideo(sender: nil)) {
                    await transition(to: .monitorRecordingVideo)
                } else {
                    await popToScanning()
                }
            }

        case let capabilities as RemoteCmd.CameraCapabilitiesResp:
            peerAdvertisedCameraDevices = !capabilities.cameraDevices.isEmpty
            peerSupportsFocusPoint = capabilities.supportsFocusPoint
            monitor?.updateCapabilities(capabilities)

        case let zoom as UICmd.SetZoom:
            sendMessage(RemoteCmd.SetZoom(zoomFactor: zoom.zoomFactor))

        case let focus as UICmd.FocusAtPoint:
            // Wire-safety gate: never send to a peer that would decode action 21
            // as TakePicture. Silently dropped otherwise (reticle already shown).
            guard peerSupportsFocusPoint else {
                debugLog("FocusAtPoint dropped: peer did not advertise focus-point support")
                break
            }
            sendMessage(RemoteCmd.FocusAtPoint(x: focus.x, y: focus.y))

        case let zoomResp as RemoteCmd.SetZoomResp:
            monitor?.updateZoom(zoomResp.zoomFactor, zoomRange: zoomResp.zoomRange, currentLens: zoomResp.currentLens)

        case let torchResp as RemoteCmd.ToggleTorchResp:
            monitor?.updateTorchMode(torchResp.torchMode)

        case let lens as UICmd.SwitchLens:
            if sendMessage(RemoteCmd.SwitchLens(lensType: lens.lensType)) {
                await showCameraAlert("Switching lens")
                let generation = scheduleTimeout(.monitorSwitchingLens)
                await transition(to: .monitorSwitchingLens(returnTo: .mode(mode), generation: generation))
            } else {
                await popToScanning()
            }

        case let quality as UICmd.SetVideoQuality:
            sendMessage(RemoteCmd.SetVideoQuality(resolution: quality.resolution, frameRate: quality.frameRate))

        case let quality as UICmd.SetPhotoQuality:
            sendMessage(RemoteCmd.SetPhotoQuality(format: quality.format, hdrMode: quality.hdrMode))

        case let ratio as UICmd.SetAspectRatio:
            sendMessage(RemoteCmd.SetAspectRatio(aspectRatio: ratio.aspectRatio))

        case let videoQualityResp as RemoteCmd.SetVideoQualityResp:
            if videoQualityResp.error == nil {
                monitor?.updateVideoQuality(resolution: videoQualityResp.resolution, frameRate: videoQualityResp.frameRate)
            }

        case let photoQualityResp as RemoteCmd.SetPhotoQualityResp:
            if photoQualityResp.error == nil {
                monitor?.updatePhotoQuality(format: photoQualityResp.format, hdrMode: photoQualityResp.hdrMode)
            }

        case let ratioResp as RemoteCmd.SetAspectRatioResp:
            monitor?.updateAspectRatio(ratioResp.aspectRatio)

        case is UICmd.RequestCameraCapabilities, is RemoteCmd.PeerBecameCamera:
            sendMessage(RemoteCmd.RequestCameraCapabilities())

        case let become as UICmd.BecomeMonitor:
            // Photo↔video mode swap in place (the old discardOld become).
            let newMode: MonitorMode = become.mode == .Photo ? .photo : .video
            if newMode != mode {
                await transition(to: .monitor(mode: newMode))
            }

        case is Disconnect:
            await popToScanning()

        case let disconnected as DisconnectPeer:
            if disconnected.peer == peer && connectedPeers.isEmpty {
                await popToScanning()
            }

        default:
            await handleRoot(msg)
        }
    }

    private func inMonitorTakingPicture(_ msg: Message, generation: Int) async {
        switch msg {
        case let timeout as UICmd.StateTimeout:
            guard timeout.stateName == .monitorTakingPicture && timeout.generation == generation else { break }
            await dismissCameraAlert()
            await transition(to: .monitor(mode: .photo))

        case is RemoteCmd.TakePicAck:
            updateCameraAlert(NSLocalizedString("Receiving picture", comment: ""))
            // Quirk preserved from the old machine: the ack is echoed back to
            // the peers (the camera drops it via its root default).
            await sendOrGoToScanning(msg)

        case let take as UICmd.TakePicture:
            sendMessage(RemoteCmd.TakePic(sender: nil, sendMediaToPeer: take.sendMediaToRemote))

        case let resp as RemoteCmd.TakePicResp:
            if let pic = resp.pic {
                savePictureOnMonitor(pic)
                await dismissCameraAlert()
            } else if let error = resp.error {
                await dismissCameraAlert()
                showErrorAlert(error._domain)
            }
            await transition(to: .monitor(mode: .photo))

        case is UICmd.UnbecomeMonitor:
            await dismissCameraAlert()
            await transition(to: .connected)

        case let disconnected as DisconnectPeer:
            await dismissCameraAlert()
            if disconnected.peer?.displayName == peer?.displayName && connectedPeers.isEmpty {
                await popToScanning()
            }

        case is Disconnect:
            await dismissCameraAlert()
            await popToScanning()

        default:
            // The old state dismissed the alert and dropped unhandled messages
            // (deliberately NOT the root handler — no error-resp synthesis here).
            await dismissCameraAlert()
            debugLog("monitorTakingPicture: ignoring \(type(of: msg))")
        }
    }

    enum ToggleKind { case flash, camera }

    private func inMonitorToggling(_ msg: Message, kind: ToggleKind, mode: MonitorMode, generation: Int) async {
        let ownName: RemoteCamState = kind == .flash ? .monitorTogglingFlash : .monitorTogglingCamera

        switch msg {
        case let timeout as UICmd.StateTimeout:
            guard timeout.stateName == ownName && timeout.generation == generation else { break }
            await dismissCameraAlert()
            await transition(to: .monitor(mode: mode))

        case is UICmd.ToggleFlash where kind == .flash:
            break // Already sent from parent state; ignore duplicate taps
        case is UICmd.ToggleCamera where kind == .camera:
            break // Already sent from parent state; ignore duplicate taps
        case is UICmd.SelectCameraDevice where kind == .camera:
            break // A selection is already in flight; ignore duplicate taps

        case let flashResp as RemoteCmd.ToggleFlashResp where kind == .flash:
            if flashResp.flashMode != nil {
                monitor?.updateFlashMode(flashResp.flashMode)
                await dismissCameraAlert()
            } else if let error = flashResp.error {
                await dismissCameraAlert()
                showErrorAlert(error._domain)
            } else {
                await dismissCameraAlert()
            }
            await transition(to: .monitor(mode: mode))

        case let toggleResp as RemoteCmd.ToggleCameraResp where kind == .camera:
            // Also matches SelectCameraDeviceResp (a subclass): a completed
            // device selection re-syncs the monitor exactly like a toggle.
            // Forward the fresh capabilities so the monitor UI re-syncs to the
            // new camera (lens list, zoom range, quality).
            if let capabilities = toggleResp.cameraCapabilities {
                peerAdvertisedCameraDevices = !capabilities.cameraDevices.isEmpty
                peerSupportsFocusPoint = capabilities.supportsFocusPoint
                monitor?.updateCapabilities(capabilities)
                await dismissCameraAlert()
            } else if let error = toggleResp.error {
                await dismissCameraAlert()
                showErrorAlert(error._domain)
            } else {
                await dismissCameraAlert()
            }
            await transition(to: .monitor(mode: mode))

        case let disconnected as DisconnectPeer:
            await dismissCameraAlert()
            if disconnected.peer?.displayName == peer?.displayName && connectedPeers.isEmpty {
                await popToScanning()
            }

        case is Disconnect:
            await dismissCameraAlert()
            await popToScanning()

        case is UICmd.UnbecomeMonitor:
            await dismissCameraAlert()
            await transition(to: .connected)

        default:
            debugLog("monitorToggling: ignoring \(type(of: msg))")
        }
    }

    private func inMonitorSwitchingLens(_ msg: Message, returnTo: LensSwitchReturn, generation: Int) async {
        func returnState() -> SessionState {
            switch returnTo {
            case .mode(let mode): return .monitor(mode: mode)
            case .recording: return .monitorRecordingVideo
            }
        }

        switch msg {
        case let timeout as UICmd.StateTimeout:
            guard timeout.stateName == .monitorSwitchingLens && timeout.generation == generation else { break }
            await dismissCameraAlert()
            await transition(to: returnState())

        case is UICmd.SwitchLens:
            break // Already sent from parent state; ignore duplicate taps

        case let lensResp as RemoteCmd.SwitchLensResp:
            if lensResp.lensType != nil {
                monitor?.updateLens(lensResp.lensType,
                                    availableLenses: lensResp.availableLenses,
                                    currentZoom: lensResp.currentZoom,
                                    zoomRange: lensResp.zoomRange)
                await dismissCameraAlert()
            } else if let error = lensResp.error {
                await dismissCameraAlert()
                showErrorAlert(error._domain)
            } else {
                await dismissCameraAlert()
            }
            await transition(to: returnState())

        case let disconnected as DisconnectPeer:
            await dismissCameraAlert()
            if disconnected.peer?.displayName == peer?.displayName && connectedPeers.isEmpty {
                await popToScanning()
            }

        case is Disconnect:
            await dismissCameraAlert()
            await popToScanning()

        case is UICmd.UnbecomeMonitor:
            await dismissCameraAlert()
            await transition(to: .connected)

        default:
            debugLog("monitorSwitchingLens: ignoring \(type(of: msg))")
        }
    }

    private func inMonitorRecordingVideo(_ msg: Message) async {
        switch msg {
        case let frame as RemoteCmd.OnFrame:
            noteMonitorFrame(frame)
            monitor?.show(frame: frame)
            await requestFrame()

        case is UICmd.StreamStalled:
            await requestFrame()

        case is UICmd.RequestVideoKeyframe:
            requestKeyframeIfVP9()

        case let ack as RemoteCmd.StartRecordingVideoAck:
            if let error = ack.error {
                showErrorAlert(error._domain)
                await transition(to: .monitor(mode: .video))
            } else if let startTime = ack.recordingStartTime {
                monitor?.syncRecordingStartTime(startTime)
            }

        case let take as UICmd.TakePicture:
            sendMessage(RemoteCmd.StopRecordingVideo(sender: nil, sendMediaToPeer: take.sendMediaToRemote))

        case let zoom as UICmd.SetZoom:
            sendMessage(RemoteCmd.SetZoom(zoomFactor: zoom.zoomFactor))

        case let focus as UICmd.FocusAtPoint:
            guard peerSupportsFocusPoint else {
                debugLog("FocusAtPoint dropped: peer did not advertise focus-point support")
                break
            }
            sendMessage(RemoteCmd.FocusAtPoint(x: focus.x, y: focus.y))

        case let zoomResp as RemoteCmd.SetZoomResp:
            monitor?.updateZoom(zoomResp.zoomFactor, zoomRange: zoomResp.zoomRange, currentLens: zoomResp.currentLens)

        case let lens as UICmd.SwitchLens:
            if sendMessage(RemoteCmd.SwitchLens(lensType: lens.lensType)) {
                await showCameraAlert("Switching lens")
                let generation = scheduleTimeout(.monitorSwitchingLens)
                await transition(to: .monitorSwitchingLens(returnTo: .recording, generation: generation))
            }

        case is UICmd.ToggleTorch:
            sendMessage(RemoteCmd.ToggleTorch())

        case let torchResp as RemoteCmd.ToggleTorchResp:
            monitor?.updateTorchMode(torchResp.torchMode)

        case is RemoteCmd.StopRecordingVideoAck:
            await transition(to: .monitorWaitingForVideo)

        case let resp as RemoteCmd.StopRecordingVideoResp where resp.error != nil:
            saveVideoOnMonitor(resp)
            await transition(to: .monitor(mode: .video))

        case is UICmd.UnbecomeMonitor:
            await transition(to: .connected)

        case is Disconnect:
            await popToScanning()

        case let disconnected as DisconnectPeer:
            if disconnected.peer == peer && connectedPeers.isEmpty {
                await popToScanning()
            }

        default:
            await handleRoot(msg)
        }
    }

    private func inMonitorWaitingForVideo(_ msg: Message) async {
        switch msg {
        case let resp as RemoteCmd.StopRecordingVideoResp:
            saveVideoOnMonitor(resp)
            await transition(to: .monitor(mode: .video))

        case is Disconnect:
            await popToScanning()

        case let disconnected as DisconnectPeer:
            if disconnected.peer == peer && connectedPeers.isEmpty {
                await popToScanning()
            }

        case is UICmd.UnbecomeMonitor:
            await transition(to: .connected)

        default:
            await handleRoot(msg)
        }
    }

    // MARK: - Watch family

    private func inWatchCamera(_ msg: Message) async {
        guard let ctrl else { return }

        switch msg {
        case is RemoteCmd.TakePic:
            ctrl.currentCameraMode = .Photo
            ctrl.takePicture(false)
            let generation = scheduleTimeout(.watchRemoteCameraTakingPic)
            await transition(to: .watchCameraTakingPic(generation: generation))

        case is RemoteCmd.StartRecordingVideo:
            ctrl.currentCameraMode = .Video
            ctrl.startRecordingVideo()
            let generation = scheduleTimeout(.watchRemoteCameraStartingVideo)
            await transition(to: .watchCameraStartingVideo(generation: generation))

        case is UICmd.MicrophoneAccessDenied:
            await pushWatchState(event: .microphonedenied)

        case let mode as UICmd.SetWatchCameraMode:
            ctrl.currentCameraMode = mode.mode
            ctrl.updateCameraStatus()
            await pushWatchState()

        case let countdown as RemoteCmd.TimerCountdown:
            ctrl.updateTimerCountdown(value: countdown.value)
            watchCountdownRemaining = Int32(max(0, countdown.value))
            await pushWatchState()

        case let picture as UICmd.OnPicture:
            // A capture finished after its sub-state already timed out —
            // correct the Watch with a truthful event.
            if let pic = picture.pic {
                photoLibrarySaver(pic)
                await pushWatchState(event: .phototaken)
            } else {
                await pushWatchState(event: .photoerror)
            }

        case is RemoteCmd.StartRecordingVideoAck, is RemoteCmd.StopRecordingVideoResp:
            await pushWatchState()

        case let zoom as RemoteCmd.SetZoom:
            if (try? await ctrl.setZoom(zoomFactor: zoom.zoomFactor)) != nil {
                await pushWatchState()
            }

        case let lens as RemoteCmd.SwitchLens:
            _ = try? await ctrl.switchLens(to: lens.lensType)
            await pushWatchState()

        case is RemoteCmd.ToggleFlash:
            _ = try? await ctrl.toggleFlash()
            await pushWatchState()

        case is RemoteCmd.ToggleTorch:
            _ = try? await ctrl.toggleTorch()
            await pushWatchState()

        case is RemoteCmd.ToggleCamera:
            _ = try? await ctrl.toggleCamera()
            await ctrl.gatherAllCameraCapabilities()
            await pushWatchState()

        case is RemoteCmd.RequestCameraCapabilities:
            await ctrl.gatherAllCameraCapabilities()
            await pushWatchState()

        case is UICmd.UnbecomeWatchCamera, is UICmd.UnbecomeCamera:
            watchStatePusher.pushDisconnectedState()
            await transition(to: .waitingForLobby)

        case is UICmd.StateTimeout:
            break // stale timeout from a completed sub-state

        default:
            await handleRoot(msg)
        }
    }

    private func inWatchCameraTakingPic(_ msg: Message, generation: Int) async {
        guard let ctrl else { return }

        switch msg {
        case let picture as UICmd.OnPicture:
            if let pic = picture.pic {
                photoLibrarySaver(pic)
                await pushWatchState(event: .phototaken)
            } else {
                await pushWatchState(event: .photoerror)
            }
            await transition(to: .watchCamera)

        case let timeout as UICmd.StateTimeout:
            guard timeout.stateName == .watchRemoteCameraTakingPic && timeout.generation == generation else { break }
            await pushWatchState(event: .photoerror)
            await transition(to: .watchCamera)

        case is RemoteCmd.TakePic:
            break // duplicate; a capture is in flight

        case is RemoteCmd.StartRecordingVideo, is UICmd.SetWatchCameraMode:
            await pushWatchState(event: .busy)

        case let zoom as RemoteCmd.SetZoom:
            if (try? await ctrl.setZoom(zoomFactor: zoom.zoomFactor)) != nil {
                await pushWatchState()
            }

        case is RemoteCmd.RequestCameraCapabilities:
            await ctrl.gatherAllCameraCapabilities()
            await pushWatchState()

        case is UICmd.UnbecomeWatchCamera, is UICmd.UnbecomeCamera:
            watchStatePusher.pushDisconnectedState()
            await transition(to: .waitingForLobby)

        default:
            await handleRoot(msg)
        }
    }

    private func inWatchCameraStartingVideo(_ msg: Message, generation: Int) async {
        guard let ctrl else { return }

        switch msg {
        case let ack as RemoteCmd.StartRecordingVideoAck:
            if ack.error != nil {
                await pushWatchState(event: .recordingfailed)
                await transition(to: .watchCamera)
            } else {
                await pushWatchState(event: .recordingstarted)
                // In-place replacement (the old discardOld swap).
                state = .watchCameraRecordingVideo(stopGeneration: nil)
            }

        case is UICmd.MicrophoneAccessDenied:
            await pushWatchState(event: .microphonedenied)
            await transition(to: .watchCamera)

        case let timeout as UICmd.StateTimeout:
            guard timeout.stateName == .watchRemoteCameraStartingVideo && timeout.generation == generation else { break }
            ctrl.stopRecordingVideo(false)
            await pushWatchState(event: .recordingfailed)
            await transition(to: .watchCamera)

        case is RemoteCmd.StopRecordingVideo:
            ctrl.stopRecordingVideo(false)
            await pushWatchState(event: .recordingstopped)
            await transition(to: .watchCamera)

        case is RemoteCmd.TakePic, is RemoteCmd.StartRecordingVideo, is UICmd.SetWatchCameraMode:
            await pushWatchState(event: .busy)

        case let zoom as RemoteCmd.SetZoom:
            if (try? await ctrl.setZoom(zoomFactor: zoom.zoomFactor)) != nil {
                await pushWatchState()
            }

        case is UICmd.UnbecomeWatchCamera, is UICmd.UnbecomeCamera:
            ctrl.stopRecordingVideo(false)
            watchStatePusher.pushDisconnectedState()
            await transition(to: .waitingForLobby)

        default:
            await handleRoot(msg)
        }
    }

    private func inWatchCameraRecordingVideo(_ msg: Message, stopGeneration: Int?) async {
        guard let ctrl else { return }

        switch msg {
        case is RemoteCmd.StopRecordingVideo:
            guard stopGeneration == nil else { break } // stop already in flight
            let generation = scheduleTimeout(.watchRemoteCameraRecordingVideo)
            state = .watchCameraRecordingVideo(stopGeneration: generation)
            ctrl.stopRecordingVideo(false)

        case is RemoteCmd.StopRecordingVideoResp:
            await pushWatchState(event: .recordingstopped)
            await transition(to: .watchCamera)

        case is UICmd.SendVideoResource:
            // Watch mode saves locally; the resource message doubles as the
            // "recording finished" signal.
            await pushWatchState(event: .recordingstopped)
            await transition(to: .watchCamera)

        case let timeout as UICmd.StateTimeout:
            guard timeout.stateName == .watchRemoteCameraRecordingVideo,
                  let stopGeneration, timeout.generation == stopGeneration else { break }
            await pushWatchState(event: .recordingfailed)
            await transition(to: .watchCamera)

        case is RemoteCmd.TakePic, is RemoteCmd.StartRecordingVideo, is UICmd.SetWatchCameraMode:
            await pushWatchState(event: .busyrecording)

        case let zoom as RemoteCmd.SetZoom:
            if (try? await ctrl.setZoom(zoomFactor: zoom.zoomFactor)) != nil {
                await pushWatchState()
            }

        case let lens as RemoteCmd.SwitchLens:
            _ = try? await ctrl.switchLens(to: lens.lensType)
            await pushWatchState()

        case is RemoteCmd.ToggleTorch:
            _ = try? await ctrl.toggleTorch()
            await pushWatchState()

        case is RemoteCmd.RequestCameraCapabilities:
            await ctrl.gatherAllCameraCapabilities()
            await pushWatchState()

        case is UICmd.UnbecomeWatchCamera, is UICmd.UnbecomeCamera:
            ctrl.stopRecordingVideo(false)
            watchStatePusher.pushDisconnectedState()
            await transition(to: .waitingForLobby)

        default:
            await handleRoot(msg)
        }
    }

    // MARK: - Watch state snapshot

    /// True while the machine is in any Watch Remote camera state.
    private var isInWatchState: Bool {
        switch state {
        case .watchCamera, .watchCameraTakingPic, .watchCameraStartingVideo, .watchCameraRecordingVideo:
            return true
        default:
            return false
        }
    }

    /// Answers a Watch `.requeststate` command authoritatively. In a watch state the
    /// reply carries `Ok` plus the full camera snapshot (freshly epoch-stamped, like
    /// `pushCameraState`); otherwise it truthfully reports `.notinwatchmode`. This is
    /// the one place the "phone is ready" verdict and the snapshot travel together, so
    /// the Watch never receives an Ok that isn't backed by state.
    private func replyWithWatchState(_ request: UICmd.RequestWatchStateReply) async {
        guard isInWatchState, let ctrl else {
            request.reply(WatchStateReplyEncoder.encode(status: .notinwatchmode, snapshot: nil))
            return
        }
        var snapshot = await Self.watchStateSnapshot(
            ctrl: ctrl,
            isBackgrounded: isPhoneBackgrounded(),
            countdownRemaining: watchCountdownRemaining)
        snapshot.stateEpochMs = UInt64(Date().timeIntervalSince1970 * 1000)
        request.reply(WatchStateReplyEncoder.encode(status: .ok, snapshot: snapshot))
    }

    func pushWatchState(event: RemoteShutter_WatchEventType = .unknown) async {
        guard let ctrl else { return }
        let snapshot = await Self.watchStateSnapshot(
            ctrl: ctrl,
            event: event,
            isBackgrounded: isPhoneBackgrounded(),
            countdownRemaining: watchCountdownRemaining)
        watchStatePusher.pushCameraState(snapshot)
    }

    static func watchStateSnapshot(ctrl: CameraControlling,
                                   event: RemoteShutter_WatchEventType = .unknown,
                                   isBackgrounded: Bool = false,
                                   countdownRemaining: Int32 = 0) async -> WatchCameraStateSnapshot {
        var snapshot = WatchCameraStateSnapshot()
        // Readiness is decided here and nowhere else: the phone can only capture while
        // foregrounded. A backgrounded/locked phone reports not-ready (routed to the
        // Watch's "app closed" screen), suppressing any transient capture event or
        // countdown that was in flight — the timer is suspended with the app anyway.
        snapshot.readiness = isBackgrounded ? .phonebackgrounded : .ready
        snapshot.event = isBackgrounded ? .unknown : event
        snapshot.countdownRemainingSecs = isBackgrounded ? 0 : countdownRemaining
        snapshot.currentZoomFactor = Double(await ctrl.getCurrentZoomFactor())
        snapshot.minZoomFactor = Double(await ctrl.getMinZoomFactor())
        snapshot.maxZoomFactor = Double(await ctrl.getMaxZoomFactor())
        snapshot.isRecording = ctrl.isRecording
        snapshot.currentMode = ctrl.currentCameraMode == .Video ? .video : .photo
        snapshot.currentLensType = RemoteShutter_CameraLensType(rawValue: Int8(await ctrl.getCurrentLensType().rawValue)) ?? .wideangle
        snapshot.availableLensTypes = await ctrl.getAvailableLensTypes().compactMap {
            RemoteShutter_CameraLensType(rawValue: Int8($0.rawValue))
        }
        snapshot.flashMode = RemoteShutter_FlashMode(rawValue: Int8(await ctrl.currentFlashMode().rawValue)) ?? .off
        snapshot.isTorchEnabled = await ctrl.isTorchActive()
        snapshot.zoomStops = await ctrl.getZoomStops().map { Double($0) }
        snapshot.wideAngleZoomFactor = Double(await ctrl.getWideAngleZoomFactor())
        return snapshot
    }

    // MARK: - Incompatibility

    private func showIncompatibilityMessage() async {
        await popToScanning()
        OperationQueue.main.addOperation {
            let alert = UIAlertController(
                title: "App is out of date",
                message: "Please update Remote Shutter on both devices.")
            alert.addAction(UIAlertAction(title: "Update", style: .default) { _ in
                UIApplication.shared.open(AppStoreURL, options: [:], completionHandler: nil)
            })
            alert.show(true)
        }
    }

    // MARK: - Photo/video library

    private nonisolated func savePictureToLibrary(_ data: Data) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    showPhotosAccessDeniedModal(for: .photo)
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, data: data, options: nil)
            }) { (success: Bool, _: Error?) in
                if success {
                    print("Saved photo!")
                } else {
                    print("Failed to save photo!")
                }
            }
        }
    }

    /// Monitor-side picture save (with the App Store review prompt).
    private nonisolated func savePictureOnMonitor(_ imageData: Data) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    showPhotosAccessDeniedModal(for: .photo)
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, data: imageData, options: nil)
            }) { (success: Bool, _: Error?) in
                if success {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        showReviewPromptIfAppropriate()
                    }
                } else {
                    print("Failed to save photo on monitor!")
                }
            }
        }
    }

    /// Monitor-side video save (inbound data → temp file → camera roll).
    private nonisolated func saveVideoOnMonitor(_ videoResp: RemoteCmd.StopRecordingVideoResp) {
        if let error = videoResp.error {
            showError(error.localizedDescription)
        }
        guard let video = videoResp.video else {
            return
        }
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                let fileURL = URL(fileURLWithPath: NSTemporaryDirectory(),
                        isDirectory: true).appendingPathComponent(tempFile)
                cleanupFileAt(fileURL)
                do {
                    _ = try video.write(to: fileURL, options: .atomic)
                } catch {
                    showError(NSLocalizedString("Unable to save video", comment: ""))
                    return
                }

                PHPhotoLibrary.shared().performChanges({
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = true
                    PHAssetCreationRequest.forAsset()
                        .addResource(with: .video, fileURL: fileURL, options: options)
                }, completionHandler: { success, _ in
                    if !success {
                        showError(NSLocalizedString("Unable to save video to Photos app", comment: ""))
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            showReviewPromptIfAppropriate()
                        }
                    }
                    cleanupFileAt(fileURL)
                })
            } else {
                DispatchQueue.main.async {
                    showPhotosAccessDeniedModal(for: .video)
                }
            }
        }
    }
}

// MARK: - MultipeerServiceDelegate

extension SessionCoordinator: MultipeerServiceDelegate {

    public nonisolated func didReceiveMessage(_ message: Message) {
        tell(message)
    }

    public nonisolated func didReceiveFrameRequest(_ request: RemoteCmd.RequestFrame) {
        // Straight to the frame streamer — pacing must not queue behind
        // state-machine work.
        frameSenderShared.value?.receiveAck(request)
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
        // Warm the transport's unreliable datagram channel: it
        // negotiates lazily on first use (~10s) and silently drops sends
        // until ready ("giving up for participant" in the MC logs). One
        // no-op ping here starts that clock at connect, so negotiation
        // finishes while the user is still picking roles and the live
        // preview flows from its very first frame. RequestFrame is the safe
        // no-op: a stray one is treated as a frame-credit ack, and the
        // credit window clamps at zero.
        _ = transportShared.value?.send(
            RemoteCmd.RequestFrame(sender: nil), to: [peer], mode: .unreliable)
        tell(OnConnectToDevice(peer: peer, sender: nil))
    }

    public nonisolated func peerDidDisconnect(_ peer: MCPeerID) {
        tell(DisconnectPeer(peer: peer, sender: nil))
    }

    public nonisolated func peerDidSuspend(_ peer: MCPeerID) {
        tell(UICmd.PeerSuspended(peer: peer))
    }

    public nonisolated func peerDidResume(_ peer: MCPeerID) {
        tell(UICmd.PeerResumed(peer: peer))
    }

    public nonisolated func didDetectIncompatibility() {
        // Routed through the inbox — the old code mutated the state stack
        // directly on the delegate thread (a pre-existing race, now gone).
        tell(IncompatibilityDetected())
    }

    public nonisolated func browserDidFindPeer(_ peer: MCPeerID) {
        tell(UICmd.BrowserFoundPeer(peer: peer))
    }

    public nonisolated func browserDidLosePeer(_ peer: MCPeerID) {
        tell(UICmd.BrowserLostPeer(peer: peer))
    }

    public nonisolated func browserDidFail(_ error: Error) {
        print("Browser failed to start browsing: \(error.localizedDescription)")
        tell(UICmd.BrowserFailed(error: error))
    }

    public nonisolated func advertiserDidFail(_ error: Error) {
        // Same user-facing failure as a dead browser: discovery isn't running.
        tell(UICmd.BrowserFailed(error: error))
    }

    public nonisolated func didStartReceivingResource(name resourceName: String, progress: Progress) {
        debugLog("📥 DEBUG: Started receiving resource: \(resourceName)")
        guard resourceName.hasPrefix("video_") else { return }

        tell(UICmd.VideoResourceTransferStarted(
            totalBytes: progress.totalUnitCount, resourceName: resourceName, sender: nil))

        guard let service = transportShared.value else { return }
        trackReceiveProgress(progress, resourceName: resourceName, into: service)
    }

    private nonisolated func trackReceiveProgress(_ progress: Progress,
                                                  resourceName: String,
                                                  into service: any MultipeerServiceProtocol) {
        final class SpeedTracker {
            var lastUpdateTime = Date()
            var lastCompletedBytes: Int64 = 0
            var lastCalculatedSpeed: Double = 0.0
        }
        let speedTracker = SpeedTracker()

        let service = service
        progress.publisher(for: \.fractionCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] fractionCompleted in
                let completedBytes = Int64(Double(progress.totalUnitCount) * fractionCompleted)
                let currentTime = Date()
                let timeElapsed = currentTime.timeIntervalSince(speedTracker.lastUpdateTime)
                let bytesTransferred = completedBytes - speedTracker.lastCompletedBytes

                let transferSpeed: Double
                if timeElapsed > 0.5 && bytesTransferred > 0 {
                    transferSpeed = Double(bytesTransferred) / timeElapsed
                    speedTracker.lastUpdateTime = currentTime
                    speedTracker.lastCompletedBytes = completedBytes
                    speedTracker.lastCalculatedSpeed = transferSpeed
                } else {
                    transferSpeed = speedTracker.lastCalculatedSpeed
                }

                self?.tell(UICmd.VideoResourceTransferProgress(
                    completedBytes: completedBytes,
                    totalBytes: progress.totalUnitCount,
                    progress: fractionCompleted,
                    resourceName: resourceName,
                    transferSpeed: transferSpeed,
                    sender: nil))
            }
            .store(in: &service.progressCancellables)
    }

    public nonisolated func didFinishReceivingResource(name resourceName: String, at localURL: URL?, error: Error?) {
        debugLog("📥 DEBUG: Finished receiving resource: \(resourceName)")

        if let error {
            tell(UICmd.VideoResourceTransferFailed(error: error, resourceName: resourceName, sender: nil))
            return
        }

        guard resourceName.hasPrefix("video_") else { return }
        tell(UICmd.VideoResourceTransferCompleted(resourceName: resourceName, success: true, sender: nil))

        if let localURL {
            do {
                let videoData = try Data(contentsOf: localURL)
                tell(RemoteCmd.StopRecordingVideoResp(sender: nil, pic: videoData, error: nil))
                try FileManager.default.removeItem(at: localURL)
            } catch {
                debugLog("❌ DEBUG: Error processing received video: \(error.localizedDescription)")
                tell(RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: error))
            }
        }
    }
}
