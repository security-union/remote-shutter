//
//  WatchSessionDelegate.swift
//  RemoteShutterWatch
//
//  Watch-side WCSession delegate.
//  Sends FlatBuffer-encoded commands to iPhone via sendMessageData.
//

import Foundation
import WatchConnectivity
import FlatBuffers

class WatchSessionDelegate: NSObject, ObservableObject, WCSessionDelegate {

    private let viewModel: WatchCameraViewModel
    private var wcSession: WCSession?
    private var retryCount = 0
    private let maxRetries = 10

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
        print("WatchSession: activation state=\(activationState.rawValue) reachable=\(reachable) error=\(error?.localizedDescription ?? "none")")
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.isSessionActive = activationState == .activated
            self?.viewModel.isPhoneReachable = reachable
        }
        if activationState == .activated && reachable {
            retryRequestState()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        print("WatchSession: reachability changed to \(session.isReachable)")
        DispatchQueue.main.async { [weak self] in
            self?.viewModel.isPhoneReachable = session.isReachable
        }
        if session.isReachable {
            retryCount = 0
            retryRequestState()
        }
    }

    // MARK: - Retry Logic

    private func retryRequestState() {
        guard retryCount < maxRetries else { return }
        guard let session = wcSession, session.isReachable else { return }

        let attempt = retryCount
        retryCount += 1
        print("WatchSession: requestState attempt \(attempt + 1)")

        let data = WatchCommandEncoder.encode(action: .requeststate)
        session.sendMessageData(data, replyHandler: nil, errorHandler: { [weak self] error in
            print("WatchSession: requestState attempt \(attempt + 1) failed: \(error.localizedDescription)")
            let delay = min(Double(attempt + 1) * 2.0, 10.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self?.retryRequestState()
            }
        })
    }

    func manualRetry() {
        retryCount = 0
        retryRequestState()
    }

    // MARK: - Receiving State from iPhone

    func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        print("WatchSession: received \(messageData.count) bytes")
        if let state = WatchStateEncoder.decode(messageData) {
            retryCount = 0
            DispatchQueue.main.async { [weak self] in
                self?.viewModel.update(from: state)
            }
        } else {
            // Preview frame
            DispatchQueue.main.async { [weak self] in
                self?.viewModel.updatePreviewFrame(messageData)
            }
        }
    }

    // MARK: - Send Commands

    private func sendCommand(action: RemoteShutter_WatchCommandAction,
                             zoomFactor: Double = 0,
                             lensType: RemoteShutter_CameraLensType = .wideangle) {
        guard let session = wcSession, session.isReachable else { return }
        let data = WatchCommandEncoder.encode(action: action, zoomFactor: zoomFactor, lensType: lensType)
        session.sendMessageData(data, replyHandler: nil, errorHandler: { error in
            print("WatchSession: \(action) failed: \(error.localizedDescription)")
        })
    }

    func requestState() { retryCount = 0; retryRequestState() }
    func setZoom(_ factor: Double) { sendCommand(action: .setzoom, zoomFactor: factor) }
    func takePicture() { sendCommand(action: .takepicture) }
    func startRecording() { sendCommand(action: .startrecording) }
    func stopRecording() { sendCommand(action: .stoprecording) }
    func switchLens(_ lensType: RemoteShutter_CameraLensType) { sendCommand(action: .switchlens, lensType: lensType) }
    func toggleFlash() { sendCommand(action: .toggleflash) }
    func toggleTorch() { sendCommand(action: .toggletorch) }
    func toggleCamera() { sendCommand(action: .togglecamera) }
}
