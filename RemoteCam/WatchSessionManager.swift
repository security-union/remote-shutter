//
//  WatchSessionManager.swift
//  RemoteShutter
//
//  iPhone-side WCSession delegate for Apple Watch communication.
//  Receives FlatBuffer-encoded commands from Watch, dispatches to RemoteCamSession actor.
//  Pushes FlatBuffer-encoded camera state to Watch.
//

import Foundation
import UIKit
#if !targetEnvironment(macCatalyst)
import      WatchConnectivity
#endif
import FlatBuffers

/// Seam through which `RemoteCamSession`'s watch states publish camera state,
/// so state-machine tests can record pushes without WatchConnectivity.
protocol WatchStatePushing: AnyObject {
    func pushCameraState(_ snapshot: WatchCameraStateSnapshot)
    func pushDisconnectedState()
}

#if targetEnvironment(macCatalyst)

/// WatchConnectivity does not exist on the Mac. This stub keeps every call
/// site compiling; `watchPaired` stays false, so the Watch Remote role never
/// surfaces in the UI and the coordinator's watch states never fire.
class WatchSessionManager: NSObject, ObservableObject {

    static let shared = WatchSessionManager()

    @Published private(set) var watchPaired = false
    weak var cameraController: WatchRemoteCameraController?

    func activate() {}
    var isWatchPaired: Bool { false }
    var isWatchReachable: Bool { false }
    func pushCameraState(_ snapshot: WatchCameraStateSnapshot) {}
    func pushDisconnectedState() {}
    func pushPreviewFrame(payload: Data, codec: RemoteCmd.StreamCodec) {}
}

extension WatchSessionManager: WatchStatePushing {}

#else

class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {

    static let shared = WatchSessionManager()

    private var wcSession: WCSession?

    /// Live pairing state for SwiftUI (e.g. the role picker's Watch Remote
    /// button). `isPaired` is only valid after async activation completes, so a
    /// constructor-time snapshot raced it and hid the button on cold launch.
    @Published private(set) var watchPaired = false

    /// The active watch remote camera controller, if in Watch Remote mode.
    /// Written on the main thread, read from the WCSession delegate queue.
    private let controllerLock = NSLock()
    private weak var _cameraController: WatchRemoteCameraController?
    weak var cameraController: WatchRemoteCameraController? {
        get {
            controllerLock.lock(); defer { controllerLock.unlock() }
            return _cameraController
        }
        set {
            controllerLock.lock(); defer { controllerLock.unlock() }
            _cameraController = newValue
        }
    }

    // MARK: - Activation

    func activate() {
        guard WCSession.isSupported() else { return }
        wcSession = WCSession.default
        wcSession?.delegate = self
        wcSession?.activate()
        observeAppLifecycle()
    }

    /// While in Watch Remote mode, a backgrounded/locked iPhone can still receive
    /// commands but its capture session is stopped — tell the Watch the truth.
    private func observeAppLifecycle() {
        // The monitor owns the background flag (the state-snapshot builder reads it).
        // Its onChange fires *after* the flag flips, so re-pushing here always sends
        // the up-to-date readiness — and locking the device is covered exactly like
        // swiping home. In phone-to-phone mode `cameraController` is nil, so this is a
        // no-op there.
        AppActivityMonitor.shared.onChange = { [weak self] in
            self?.cameraController?.pushCurrentState()
        }
        AppActivityMonitor.shared.startObserving()
    }

    var isWatchPaired: Bool {
        wcSession?.isPaired ?? false
    }

    var isWatchReachable: Bool {
        wcSession?.isReachable ?? false
    }

    // MARK: - Push State to Watch (FlatBuffer-encoded)

    func pushCameraState(_ snapshot: WatchCameraStateSnapshot) {
        guard let session = wcSession else { return }

        var stamped = snapshot
        stamped.stateEpochMs = UInt64(Date().timeIntervalSince1970 * 1000)
        let data = WatchStateEncoder.encode(stamped)

        // Durable path: latest-wins state mirror that survives unreachability,
        // so a Watch that reconnects later never resumes on stale state.
        // The epoch keeps identical payloads from being deduplicated away.
        try? session.updateApplicationContext([
            WatchContextKeys.state: data,
            WatchContextKeys.epoch: stamped.stateEpochMs
        ])

        // Live path: low-latency delivery while the Watch app is reachable.
        guard session.isReachable else { return }
        session.sendMessageData(data, replyHandler: nil, errorHandler: { error in
            debugLog("WatchSessionManager: Failed to push state: \(error)")
        })
    }

    func pushDisconnectedState() {
        var snapshot = WatchCameraStateSnapshot()
        snapshot.readiness = .notinwatchmode
        pushCameraState(snapshot)
    }

    // MARK: - Live Preview Streaming

    /// Sends one codec-tagged preview frame (VP9/HEIC/JPEG) to the Watch on the live
    /// channel, fire-and-forget — the same proven delivery path as state pushes.
    /// Back-pressure is handled by the `WatchPreviewStreamer`, which waits for the
    /// Watch's explicit "request next frame" ack before releasing another. Never uses
    /// `updateApplicationContext`: that durable, coalesced mirror is reserved for
    /// camera state and would fight the stream.
    func pushPreviewFrame(payload: Data, codec: RemoteCmd.StreamCodec) {
        guard let session = wcSession, session.isReachable else { return }

        let epochMs = UInt64(Date().timeIntervalSince1970 * 1000)
        let data = WatchPreviewFrameEncoder.encode(payload: payload,
                                                   codec: toFBStreamCodec(codec),
                                                   epochMs: epochMs)
        debugLog("WatchSessionManager: pushing preview frame (\(data.count) bytes, codec \(codec))")
        session.sendMessageData(data, replyHandler: nil, errorHandler: { error in
            debugLog("WatchSessionManager: Failed to push preview frame: \(error)")
        })
    }

    // MARK: - WCSessionDelegate — Activation

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        debugLog("WatchSessionManager: Activation complete, state=\(activationState.rawValue), paired=\(session.isPaired), reachable=\(session.isReachable), error=\(error?.localizedDescription ?? "none")")
        let paired = session.isPaired
        DispatchQueue.main.async { [weak self] in
            self?.watchPaired = paired
        }
    }

    /// Pairing/app-install changes (e.g. user pairs a Watch while the app is open).
    func sessionWatchStateDidChange(_ session: WCSession) {
        let paired = session.isPaired
        debugLog("WatchSessionManager: watch state changed, paired=\(paired)")
        DispatchQueue.main.async { [weak self] in
            self?.watchPaired = paired
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        debugLog("WatchSessionManager: Session became inactive")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        debugLog("WatchSessionManager: Session deactivated, reactivating")
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        debugLog("WatchSessionManager: Reachability changed, isReachable=\(session.isReachable)")
        cameraController?.watchReachabilityChanged()
        // Push current state when Watch becomes reachable
        if session.isReachable, let controller = cameraController {
            controller.pushCurrentState()
        }
    }

    // MARK: - WCSessionDelegate — Receiving FlatBuffer Commands from Watch

    func session(_ session: WCSession,
                 didReceiveMessageData messageData: Data,
                 replyHandler: @escaping (Data) -> Void) {
        debugLog("WatchSessionManager: didReceiveMessageData WITH reply (\(messageData.count) bytes)")

        // The reply to `.requeststate` IS the state: route it into the coordinator
        // so the answer is computed from the machine's real state (Ok + snapshot in
        // a watch state, `.notinwatchmode` otherwise). This replaces the old
        // synchronous Ok, which could "lie" — acking before a state push that a
        // reachability race then silently dropped, stranding the Watch on "connecting".
        if let decoded = WatchCommandEncoder.decode(messageData), decoded.action == .requeststate {
            guard let controller = cameraController else {
                replyHandler(WatchStateReplyEncoder.encode(status: .notinwatchmode, snapshot: nil))
                return
            }
            controller.requestWatchStateReply(replyHandler)
            return
        }

        // Every other command keeps its fast synchronous ack — a dropped replyHandler
        // surfaces as a timeout error on the Watch.
        replyHandler(handleIncomingData(messageData))
    }

    func session(_ session: WCSession,
                 didReceiveMessageData messageData: Data) {
        debugLog("WatchSessionManager: didReceiveMessageData (\(messageData.count) bytes)")
        _ = handleIncomingData(messageData)
    }

    /// Decodes a command, dispatches it if a camera controller is active, and
    /// returns the FlatBuffer-encoded ack describing what happened.
    @discardableResult
    private func handleIncomingData(_ messageData: Data) -> Data {
        guard let decoded = WatchCommandEncoder.decode(messageData) else {
            debugLog("WatchSessionManager: Failed to decode FlatBuffer command")
            return WatchAckEncoder.encode(status: .failed, detail: "undecodable command")
        }

        guard let controller = cameraController else {
            debugLog("WatchSessionManager: No cameraController — not in Watch Remote mode")
            return WatchAckEncoder.encode(status: .notinwatchmode, action: decoded.action)
        }

        controller.handleWatchCommand(
            action: decoded.action,
            zoomFactor: decoded.zoomFactor,
            lensType: decoded.lensType,
            timerSeconds: decoded.timerSeconds,
            mode: decoded.mode
        )
        // Ok = decoded and dispatched to the state machine; capture completion
        // arrives separately as a state-push event.
        return WatchAckEncoder.encode(status: .ok, action: decoded.action)
    }
}

extension WatchSessionManager: WatchStatePushing {}

#endif
