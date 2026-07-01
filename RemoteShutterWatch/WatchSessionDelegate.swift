//
//  WatchSessionDelegate.swift
//  RemoteShutterWatch
//
//  Watch-side WCSession delegate.
//  Sends FlatBuffer-encoded commands to iPhone via sendMessageData with
//  per-command acks; receives state via live messages and applicationContext.
//
//  Threading: all mutable state (retry bookkeeping) is confined to the main
//  queue — WCSession delegate callbacks hop there before touching it.
//

import Foundation
import UIKit
import WatchConnectivity
import FlatBuffers

class WatchSessionDelegate: NSObject, ObservableObject, WCSessionDelegate {

    private let viewModel: WatchCameraViewModel
    private var wcSession: WCSession?

    // Main-queue confined.
    private var retryCount = 0
    private let maxRetries = 10
    /// Armed after a requestState is acked Ok; fires if no state arrives.
    private var stateArrivalCheck: DispatchWorkItem?

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
        print("WatchSession: activation state=\(activationState.rawValue) reachable=\(reachable) "
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
                self.retryCount = 0
                self.retryRequestState()
            }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        print("WatchSession: reachability changed to \(reachable)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.viewModel.isPhoneReachable = reachable
            if reachable {
                self.retryCount = 0
                self.retryRequestState()
            }
        }
    }

    // MARK: - Retry Logic (main-queue confined)

    private func retryRequestState() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard retryCount < maxRetries else { return }
        guard let session = wcSession, session.isReachable else { return }

        let attempt = retryCount
        retryCount += 1
        print("WatchSession: requestState attempt \(attempt + 1)")

        let data = WatchCommandEncoder.encode(action: .requeststate)
        session.sendMessageData(data, replyHandler: { [weak self] reply in
            self?.handleAck(reply, action: .requeststate)
        }, errorHandler: { [weak self] error in
            print("WatchSession: requestState attempt \(attempt + 1) failed: \(error.localizedDescription)")
            let delay = min(Double(attempt + 1) * 2.0, 10.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self?.retryRequestState()
            }
        })
    }

    func manualRetry() {
        DispatchQueue.main.async { [weak self] in
            self?.retryCount = 0
            // Drop any stale readiness verdict — back to "connecting" until the
            // phone answers.
            self?.viewModel.readiness = .unknown
            self?.retryRequestState()
        }
    }

    /// The phone acked a state request but never pushed state — ask again.
    private func armStateArrivalCheck() {
        dispatchPrecondition(condition: .onQueue(.main))
        stateArrivalCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            print("WatchSession: state never arrived after Ok ack, re-requesting")
            self?.retryRequestState()
        }
        stateArrivalCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    // MARK: - Receiving State from iPhone

    /// Both preview frames and state arrive here (all sent fire-and-forget). Route by
    /// message type. A preview frame is rendered and then acked so the phone releases the
    /// next one — the same explicit-request back-pressure the peer monitor uses.
    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        if let frame = WatchPreviewFrameEncoder.decode(messageData) {
            print("WatchSession: received preview frame (\(messageData.count) bytes)")
            renderPreview(jpeg: frame.jpeg, epochMs: frame.epochMs)
            requestNextPreviewFrame()
            return
        }

        print("WatchSession: received \(messageData.count) bytes")
        guard let state = WatchStateEncoder.decode(messageData) else {
            print("WatchSession: failed to decode camera state (\(messageData.count) bytes) — ignoring")
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.retryCount = 0
            self.stateArrivalCheck?.cancel()
            self.viewModel.update(from: state)
        }
    }

    /// Decodes the tiny JPEG off the main thread, then hands the image to the view model.
    private func renderPreview(jpeg: Data, epochMs: UInt64) {
        guard let image = UIImage(data: jpeg) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.updatePreview(image: image, epochMs: epochMs)
        }
    }

    /// Durable state mirror — delivered even if the Watch app was unreachable
    /// when the phone pushed. The view model's epoch check keeps an old context
    /// from clobbering newer live state.
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let stateData = applicationContext[WatchContextKeys.state] as? Data,
              let state = WatchStateEncoder.decode(stateData) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stateArrivalCheck?.cancel()
            self.viewModel.update(from: state)
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
                if action == .requeststate {
                    self.armStateArrivalCheck()
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
                print("WatchSession: \(action) failed: \(error.localizedDescription)")
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
            print("WatchSession: \(action) failed: \(error.localizedDescription)")
            DispatchQueue.main.async { self?.viewModel.noteSendFailure() }
        })
    }

    func requestState() {
        DispatchQueue.main.async { [weak self] in
            self?.retryCount = 0
            self?.retryRequestState()
        }
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
