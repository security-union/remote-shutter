//
//  WatchSessionDelegate.swift
//  RemoteShutterWatch
//
//  Watch-side WCSession delegate.
//  Sends FlatBuffer-encoded commands to iPhone via sendMessageData with
//  per-command acks; receives state via live messages and applicationContext.
//
//  Threading: all mutable state (poll bookkeeping) is confined to the main
//  queue — WCSession delegate callbacks hop there before touching it.
//

import Foundation
import UIKit
import WatchConnectivity
import FlatBuffers

class WatchSessionDelegate: NSObject, ObservableObject, WCSessionDelegate {

    private let viewModel: WatchCameraViewModel
    private var wcSession: WCSession?

    /// Stateful VP9 stream decoder (owns its own serial queue). Never torn down:
    /// a new stream from the phone always opens with a keyframe, which re-syncs
    /// a stale decoder by itself.
    private let vp9Decoder = WatchVP9PreviewDecoder()

    // MARK: - Poll bookkeeping (main-queue confined)

    /// Whether the app is foreground-active. Polling only runs while active; the
    /// scene phase drives this via `setActive(_:)`.
    private var isActive = true
    /// True while a poll tick is scheduled, so overlapping kicks can't spin up a
    /// second concurrent loop.
    private var pollScheduled = false

    init(viewModel: WatchCameraViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        wcSession = WCSession.default
        wcSession?.delegate = self
        wcSession?.activate()
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        let reachable = session.isReachable
        debugLog("WatchSession: activation state=\(activationState.rawValue) reachable=\(reachable) "
            + "error=\(error?.localizedDescription ?? "none")")

        // Catch up on the last state the phone mirrored while we were away.
        let storedContext = session.receivedApplicationContext

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.viewModel.isSessionActive = activationState == .activated
            self.viewModel.isPhoneReachable = reachable
            if let stateData = storedContext[WatchContextKeys.state] as? Data,
               let state = WatchStateEncoder.decode(stateData) {
                self.viewModel.update(from: state)
            }
            if activationState == .activated && reachable {
                self.kickPolling()
            }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        debugLog("WatchSession: reachability changed to \(reachable)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.viewModel.isPhoneReachable = reachable
            if reachable {
                self.kickPolling()
            }
        }
    }

    // MARK: - State Polling (fixed-rate, infinite; main-queue confined)

    /// Starts the poll loop if it isn't already running. Idempotent — the
    /// `pollScheduled` guard keeps overlapping kicks from spinning up a second loop.
    private func kickPolling() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !pollScheduled else { return }
        pollTick()
    }

    /// One poll tick: if the policy still says to poll, send `.requeststate` and
    /// schedule the next tick at the fixed cadence. When the policy says stop
    /// (state applied, unreachable, or inactive), the loop simply ends.
    private func pollTick() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard WatchStatePollPolicy.shouldPoll(
            phase: viewModel.phase,
            isReachable: wcSession?.isReachable ?? false,
            isActive: isActive) else {
            pollScheduled = false
            return
        }

        sendRequestState()
        pollScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + WatchStatePollPolicy.interval) { [weak self] in
            self?.pollTick()
        }
    }

    private func sendRequestState() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let session = wcSession, session.isReachable else { return }
        let data = WatchCommandEncoder.encode(action: .requeststate)
        session.sendMessageData(data, replyHandler: { [weak self] reply in
            self?.handleStateReply(reply)
        }, errorHandler: { error in
            // No manual re-arm: the fixed-rate poll loop sends again on its own tick.
            debugLog("WatchSession: requestState failed: \(error.localizedDescription)")
        })
    }

    /// Foreground/background from the scene phase. Deactivating stops the loop on
    /// its next tick; reactivating re-kicks it.
    func setActive(_ active: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isActive = active
            if active { self.kickPolling() }
        }
    }

    func manualRetry() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Drop any stale readiness verdict — back to "connecting" until the
            // phone answers.
            self.viewModel.readiness = .unknown
            self.kickPolling()
        }
    }

    /// The authoritative reply to `.requeststate`: an Ok carries the full snapshot
    /// (apply it exactly like a live push, honoring the epoch guard); a
    /// `.notinwatchmode` reply carries no state and falls through to the ack path.
    private func handleStateReply(_ data: Data) {
        if let snapshot = WatchStateReplyEncoder.decodeState(data) {
            DispatchQueue.main.async { [weak self] in
                self?.viewModel.update(from: snapshot)
            }
            return
        }
        handleAck(data, action: .requeststate)
    }

    // MARK: - Receiving State from iPhone

    /// Both preview frames and state arrive here (all sent fire-and-forget). Route by
    /// message type. A preview frame is rendered and then acked so the phone releases the
    /// next one — the same explicit-request back-pressure the peer monitor uses.
    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        if let frame = WatchPreviewFrameEncoder.decode(messageData) {
            debugLog("WatchSession: received preview frame (\(messageData.count) bytes, codec \(frame.codec))")
            renderPreview(payload: frame.payload, codec: frame.codec, epochMs: frame.epochMs)
            return
        }

        debugLog("WatchSession: received \(messageData.count) bytes")
        guard let state = WatchStateEncoder.decode(messageData) else {
            debugLog("WatchSession: failed to decode camera state (\(messageData.count) bytes) — ignoring")
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.update(from: state)
        }
    }

    /// Routes the payload to its codec's decoder off the main thread, hands the image to
    /// the view model, and acks so the phone releases the next frame. An undecodable VP9
    /// frame is dropped but STILL acked (drop-but-ack): the stream keeps flowing and the
    /// phone's periodic keyframe re-syncs it.
    private func renderPreview(payload: Data, codec: RemoteShutter_StreamCodec, epochMs: UInt64) {
        switch codec {
        case .vp9:
            vp9Decoder.decode(frame: payload) { [weak self] image in
                guard let self else { return }
                if let image {
                    DispatchQueue.main.async { [weak self] in
                        self?.viewModel.updatePreview(image: image, epochMs: epochMs)
                    }
                }
                self.requestNextPreviewFrame()
            }
        default:
            // Stills (HEIC/JPEG) and legacy codec-less senders: UIImage sniffs the container.
            if let image = UIImage(data: payload) {
                DispatchQueue.main.async { [weak self] in
                    self?.viewModel.updatePreview(image: image, epochMs: epochMs)
                }
            }
            requestNextPreviewFrame()
        }
    }

    /// Durable state mirror — delivered even if the Watch app was unreachable
    /// when the phone pushed. The view model's epoch check keeps an old context
    /// from clobbering newer live state.
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let stateData = applicationContext[WatchContextKeys.state] as? Data,
              let state = WatchStateEncoder.decode(stateData) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.update(from: state)
        }
    }

    // MARK: - Acks

    private func handleAck(_ data: Data, action: RemoteShutter_WatchCommandAction) {
        guard let ack = WatchAckEncoder.decode(data) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch ack.status {
            case .ok:
                // An Ok ack contradicts a "not in watch mode" verdict — the phone
                // answered from the Watch Remote screen; its state push follows.
                if self.viewModel.readiness == .notinwatchmode {
                    self.viewModel.readiness = .unknown
                }
            case .notinwatchmode:
                self.viewModel.notePhoneNotInWatchMode()
            case .busy, .failed, .unknown:
                self.viewModel.noteSendFailure()
            }
        }
    }

    // MARK: - Send Commands

    /// Critical commands (shutter, toggles, lens) demand an ack so a silent drop
    /// becomes visible feedback. Zoom stays fire-and-forget — it streams at 20Hz
    /// and the next state push corrects any loss.
    private func sendCommand(action: RemoteShutter_WatchCommandAction,
                             zoomFactor: Double = 0,
                             lensType: RemoteShutter_CameraLensType = .wideangle,
                             timerSeconds: Int32 = 0,
                             mode: RemoteShutter_RecordingModeEnum = .unknown,
                             critical: Bool = true) {
        guard let session = wcSession else { return }
        let data = WatchCommandEncoder.encode(
            action: action, zoomFactor: zoomFactor, lensType: lensType,
            timerSeconds: timerSeconds, mode: mode)

        guard critical else {
            guard session.isReachable else { return }
            session.sendMessageData(data, replyHandler: nil, errorHandler: { error in
                debugLog("WatchSession: \(action) failed: \(error.localizedDescription)")
            })
            return
        }

        guard session.isReachable else {
            // Don't swallow a shutter press — tell the user it didn't go through.
            DispatchQueue.main.async { [weak self] in self?.viewModel.noteSendFailure() }
            return
        }

        session.sendMessageData(data, replyHandler: { [weak self] reply in
            self?.handleAck(reply, action: action)
        }, errorHandler: { [weak self] error in
            debugLog("WatchSession: \(action) failed: \(error.localizedDescription)")
            DispatchQueue.main.async { self?.viewModel.noteSendFailure() }
        })
    }

    func setZoom(_ factor: Double) { sendCommand(action: .setzoom, zoomFactor: factor, critical: false) }
    func takePicture(timerSeconds: Int = 0) { sendCommand(action: .takepicture, timerSeconds: Int32(timerSeconds)) }
    func startRecording(timerSeconds: Int = 0) {
        sendCommand(action: .startrecording, timerSeconds: Int32(timerSeconds))
    }
    func stopRecording() { sendCommand(action: .stoprecording) }
    func switchLens(_ lensType: RemoteShutter_CameraLensType) { sendCommand(action: .switchlens, lensType: lensType) }
    func setMode(_ mode: RemoteShutter_RecordingModeEnum) { sendCommand(action: .setmode, mode: mode) }
    func toggleFlash() { sendCommand(action: .toggleflash) }
    func toggleTorch() { sendCommand(action: .toggletorch) }
    func toggleCamera() { sendCommand(action: .togglecamera) }
    func cancelTimer() { sendCommand(action: .canceltimer) }

    /// Asks the phone for the next preview frame after rendering the current one. The
    /// phone's `WatchPreviewStreamer` treats this as the back-pressure ack. Fire-and-forget
    /// (non-critical): a dropped ack is recovered by the streamer's watchdog.
    func requestNextPreviewFrame() { sendCommand(action: .requestpreviewframe, critical: false) }
}
