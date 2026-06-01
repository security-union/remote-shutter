//
//  WatchSessionManager.swift
//  RemoteShutter
//
//  iPhone-side WCSession delegate for Apple Watch communication.
//  Receives FlatBuffer-encoded commands from Watch, dispatches to RemoteCamSession actor.
//  Pushes FlatBuffer-encoded camera state to Watch.
//

import Foundation
import WatchConnectivity
import FlatBuffers

class WatchSessionManager: NSObject, WCSessionDelegate {

    static let shared = WatchSessionManager()

    private var wcSession: WCSession?

    /// The active watch remote camera controller, if in Watch Remote mode.
    weak var cameraController: WatchRemoteCameraController?

    // MARK: - Activation

    func activate() {
        guard WCSession.isSupported() else { return }
        wcSession = WCSession.default
        wcSession?.delegate = self
        wcSession?.activate()
    }

    var isWatchPaired: Bool {
        wcSession?.isPaired ?? false
    }

    var isWatchReachable: Bool {
        wcSession?.isReachable ?? false
    }

    // MARK: - Push State to Watch (FlatBuffer-encoded)

    func pushCameraState(
        isReady: Bool,
        currentZoomFactor: Double,
        minZoomFactor: Double,
        maxZoomFactor: Double,
        isRecording: Bool,
        currentMode: RemoteShutter_RecordingModeEnum,
        currentLensType: RemoteShutter_CameraLensType,
        availableLensTypes: [RemoteShutter_CameraLensType],
        isFlashEnabled: Bool,
        isTorchEnabled: Bool,
        zoomStops: [Double],
        wideAngleZoomFactor: Double,
        lastEvent: String? = nil
    ) {
        guard let session = wcSession, session.isReachable else { return }

        let data = WatchStateEncoder.encode(
            isReady: isReady,
            currentZoomFactor: currentZoomFactor,
            minZoomFactor: minZoomFactor,
            maxZoomFactor: maxZoomFactor,
            isRecording: isRecording,
            currentMode: currentMode,
            currentLensType: currentLensType,
            availableLensTypes: availableLensTypes,
            isFlashEnabled: isFlashEnabled,
            isTorchEnabled: isTorchEnabled,
            zoomStops: zoomStops,
            wideAngleZoomFactor: wideAngleZoomFactor,
            lastEvent: lastEvent
        )
        session.sendMessageData(data, replyHandler: nil, errorHandler: { error in
            debugLog("WatchSessionManager: Failed to push state: \(error)")
        })
    }

    func pushDisconnectedState() {
        guard let session = wcSession, session.isReachable else { return }
        let data = WatchStateEncoder.encode(
            isReady: false,
            currentZoomFactor: 1.0,
            minZoomFactor: 1.0,
            maxZoomFactor: 10.0,
            isRecording: false,
            currentMode: .photo,
            currentLensType: .wideangle,
            availableLensTypes: [.wideangle],
            isFlashEnabled: false,
            isTorchEnabled: false,
            zoomStops: [1.0],
            wideAngleZoomFactor: 1.0
        )
        session.sendMessageData(data, replyHandler: nil, errorHandler: nil)
    }

    // MARK: - WCSessionDelegate — Activation

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        print(">>> WatchSessionManager: Activation complete, state=\(activationState.rawValue), paired=\(session.isPaired), reachable=\(session.isReachable), error=\(error?.localizedDescription ?? "none")")
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
        print(">>> WatchSessionManager: didReceiveMessageData WITH reply (\(messageData.count) bytes)")
        handleIncomingData(messageData)
    }

    func session(_ session: WCSession,
                 didReceiveMessageData messageData: Data) {
        print(">>> WatchSessionManager: didReceiveMessageData (\(messageData.count) bytes)")
        handleIncomingData(messageData)
    }

    private func handleIncomingData(_ messageData: Data) {
        guard let decoded = WatchCommandEncoder.decode(messageData) else {
            print(">>> WatchSessionManager: Failed to decode FlatBuffer command")
            return
        }

        print(">>> WatchSessionManager: Decoded command: \(decoded.action)")

        guard let controller = cameraController else {
            print(">>> WatchSessionManager: No cameraController! Not in Watch Remote mode.")
            return
        }

        controller.handleWatchCommand(
            action: decoded.action,
            zoomFactor: decoded.zoomFactor,
            lensType: decoded.lensType,
            timerSeconds: decoded.timerSeconds
        )
    }
}
