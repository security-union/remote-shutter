//
//  WatchRemoteCamStates.swift
//  RemoteShutter
//
//  Watch Remote camera state for RemoteCamSession.
//  Handles camera commands from WatchSessionManager without MultipeerConnectivity.
//

import Foundation

// MARK: - UICmd for Watch Remote Mode

extension UICmd {
    /// Sent by WatchRemoteCameraController to enter Watch Remote camera mode.
    public class BecomeWatchCamera: Actor.Message {
        let ctrl: CameraViewController

        public init(ctrl: CameraViewController) {
            self.ctrl = ctrl
            super.init(sender: nil)
        }
    }

    /// Sent by WatchRemoteCameraController when exiting Watch Remote mode.
    public class UnbecomeWatchCamera: Actor.Message {}
}

// MARK: - Watch Remote Camera State

extension RemoteCamSession {

    func watchRemoteCamera(ctrl: CameraViewController) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter:
                debugLog("Watch Remote: Camera state entered")
                self.pushWatchState(ctrl: ctrl)

            // MARK: - Photo Capture

            case let cmd as RemoteCmd.TakePic:
                ctrl.currentCameraMode = .Photo
                ctrl.updateCameraStatus()
                ctrl.takePicture(false) // Never send media to peer in Watch mode
                self.become(
                    name: .watchRemoteCameraTakingPic,
                    state: self.watchRemoteCameraTakingPic(ctrl: ctrl)
                )

            // MARK: - Video Recording

            case is RemoteCmd.StartRecordingVideo:
                ctrl.currentCameraMode = .Video
                ctrl.updateCameraStatus()
                ctrl.startRecordingVideo()
                self.become(
                    name: .watchRemoteCameraRecordingVideo,
                    state: self.watchRemoteCameraRecordingVideo(ctrl: ctrl)
                )

            case let micError as UICmd.MicrophoneAccessDenied:
                debugLog("Watch Remote: Microphone access denied: \(micError.error)")
                self.pushWatchState(ctrl: ctrl, event: "microphoneDenied")

            // MARK: - Zoom

            case let zoomCmd as RemoteCmd.SetZoom:
                let result = ctrl.setZoom(zoomFactor: zoomCmd.zoomFactor)
                if let (_, _, _) = result.toOptional() {
                    self.pushWatchState(ctrl: ctrl)
                }

            // MARK: - Lens Switching

            case let lensCmd as RemoteCmd.SwitchLens:
                let _ = ctrl.switchLens(to: lensCmd.lensType)
                self.pushWatchState(ctrl: ctrl)

            // MARK: - Flash & Torch

            case is RemoteCmd.ToggleFlash:
                let _ = ctrl.toggleFlash()
                self.pushWatchState(ctrl: ctrl)

            case is RemoteCmd.ToggleTorch:
                let _ = ctrl.toggleTorch()
                self.pushWatchState(ctrl: ctrl)

            // MARK: - Camera Toggle

            case is RemoteCmd.ToggleCamera:
                let _ = ctrl.toggleCamera()
                ctrl.gatherAllCameraCapabilities()
                self.pushWatchState(ctrl: ctrl)

            // MARK: - Capabilities Request

            case is RemoteCmd.RequestCameraCapabilities:
                ctrl.gatherAllCameraCapabilities()
                self.pushWatchState(ctrl: ctrl)

            // MARK: - Exit

            case is UICmd.UnbecomeWatchCamera:
                debugLog("Watch Remote: Exiting camera state")
                WatchSessionManager.shared.pushDisconnectedState()
                self.popToRootState()

            case is UICmd.UnbecomeCamera:
                // CameraViewController is being dismissed
                debugLog("Watch Remote: CameraViewController dismissed")
                WatchSessionManager.shared.pushDisconnectedState()
                self.popToRootState()

            default:
                self.receive(msg: msg)
            }
        }
    }

    // MARK: - Watch Remote Taking Picture Sub-state

    func watchRemoteCameraTakingPic(ctrl: CameraViewController) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case let t as UICmd.OnPicture:
                if t.error != nil {
                    debugLog("Watch Remote: Photo capture error: \(t.error!)")
                    self.pushWatchState(ctrl: ctrl, event: "photoError")
                } else {
                    debugLog("Watch Remote: Photo captured successfully")
                    self.pushWatchState(ctrl: ctrl, event: "photoTaken")
                }
                self.unbecome()

            default:
                self.receive(msg: msg)
            }
        }
    }

    // MARK: - Watch Remote Recording Video Sub-state

    func watchRemoteCameraRecordingVideo(ctrl: CameraViewController) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case let ack as RemoteCmd.StartRecordingVideoAck:
                debugLog("Watch Remote: Recording started at \(ack.recordingStartTime?.description ?? "unknown")")
                self.pushWatchState(ctrl: ctrl, event: "recordingStarted")

            case is RemoteCmd.StopRecordingVideo:
                ctrl.stopRecordingVideo(false)

            case is RemoteCmd.StopRecordingVideoResp:
                debugLog("Watch Remote: Recording stopped")
                self.pushWatchState(ctrl: ctrl, event: "recordingStopped")
                self.unbecome()

            case let sendVideo as UICmd.SendVideoResource:
                // In Watch mode, video is saved locally only
                debugLog("Watch Remote: Video saved at \(sendVideo.videoURL)")
                self.pushWatchState(ctrl: ctrl, event: "recordingStopped")
                self.unbecome()

            // Allow zoom/lens/flash/torch during recording
            case let zoomCmd as RemoteCmd.SetZoom:
                let _ = ctrl.setZoom(zoomFactor: zoomCmd.zoomFactor)
                self.pushWatchState(ctrl: ctrl)

            case let lensCmd as RemoteCmd.SwitchLens:
                let _ = ctrl.switchLens(to: lensCmd.lensType)
                self.pushWatchState(ctrl: ctrl)

            case is RemoteCmd.ToggleTorch:
                let _ = ctrl.toggleTorch()
                self.pushWatchState(ctrl: ctrl)

            default:
                self.receive(msg: msg)
            }
        }
    }

    // MARK: - Watch State Push Helper (FlatBuffer-encoded)

    private func pushWatchState(ctrl: CameraViewController, event: String? = nil) {
        let currentMode: RemoteShutter_RecordingModeEnum = ctrl.currentCameraMode == .Video ? .video : .photo
        let currentLens = RemoteShutter_CameraLensType(rawValue: Int8(ctrl.getCurrentLensType().rawValue)) ?? .wideangle
        let availableLenses = ctrl.getAvailableLensTypes().compactMap {
            RemoteShutter_CameraLensType(rawValue: Int8($0.rawValue))
        }

        WatchSessionManager.shared.pushCameraState(
            isReady: true,
            currentZoomFactor: Double(ctrl.getCurrentZoomFactor()),
            minZoomFactor: Double(ctrl.getMinZoomFactor()),
            maxZoomFactor: Double(ctrl.getMaxZoomFactor()),
            isRecording: ctrl.isRecording,
            currentMode: currentMode,
            currentLensType: currentLens,
            availableLensTypes: availableLenses,
            isFlashEnabled: false,
            isTorchEnabled: ctrl.videoDeviceInput?.device.isTorchActive ?? false,
            zoomStops: ctrl.getZoomStops().map { Double($0) },
            wideAngleZoomFactor: Double(ctrl.getWideAngleZoomFactor()),
            lastEvent: event
        )
    }
}
