//
//  WatchRemoteCamStates.swift
//  RemoteShutter
//
//  Watch Remote camera state for RemoteCamSession.
//  Handles camera commands from WatchSessionManager without MultipeerConnectivity.
//

import Foundation
import AVFoundation

// MARK: - Camera Control Seam

/// Everything the watch states need from the camera screen. `CameraViewController`
/// is the production implementation; tests substitute a fake so the state machine
/// can be exercised without AVFoundation or a view hierarchy.
protocol WatchCameraControlling: AnyObject {
    var currentCameraMode: RecordingMode { get set }
    var isRecording: Bool { get }
    var isTorchActive: Bool { get }
    var currentFlashMode: AVCaptureDevice.FlashMode { get }

    func updateCameraStatus()
    func takePicture(_ sendMediaToRemote: Bool)
    func startRecordingVideo()
    func stopRecordingVideo(_ shouldSendVideo: Bool)
    func setZoom(zoomFactor: CGFloat) -> Try<(CGFloat, CameraLensType, RemoteCmd.ZoomRange)>
    func switchLens(to lensType: CameraLensType) -> Try<(CameraLensType, [CameraLensType], CGFloat, RemoteCmd.ZoomRange)>
    func toggleFlash() -> Try<AVCaptureDevice.FlashMode>
    func toggleTorch() -> Try<AVCaptureDevice.TorchMode>
    func toggleCamera() -> Try<(AVCaptureDevice.FlashMode?, AVCaptureDevice.Position)>
    func gatherAllCameraCapabilities()

    func getCurrentZoomFactor() -> CGFloat
    func getMinZoomFactor() -> CGFloat
    func getMaxZoomFactor() -> CGFloat
    func getCurrentLensType() -> CameraLensType
    func getAvailableLensTypes() -> [CameraLensType]
    func getZoomStops() -> [CGFloat]
    func getWideAngleZoomFactor() -> CGFloat

    /// Drives the on-phone countdown overlay/chime for Watch-initiated timer
    /// captures. value > 0: tick; 0: fired; < 0: cancelled.
    func updateTimerCountdown(value: Int)
}

extension CameraViewController: WatchCameraControlling {
    var isTorchActive: Bool {
        videoDeviceInput?.device.isTorchActive ?? false
    }

    var currentFlashMode: AVCaptureDevice.FlashMode {
        cameraSettings.flashMode
    }

    func updateTimerCountdown(value: Int) {
        ^{
            if value > 0 {
                self.cameraViewModel.showCountdown(value)
                self.playCountdownChime(remaining: value)
            } else if value == 0 {
                self.cameraViewModel.clearCountdown()
                self.restoreTorchAfterCountdown()
            } else {
                self.cameraViewModel.cancelCountdown()
                self.restoreTorchAfterCountdown()
            }
        }
    }
}

// MARK: - UICmd for Watch Remote Mode

extension UICmd {
    /// Sent by WatchRemoteCameraController to enter Watch Remote camera mode.
    public class BecomeWatchCamera: Actor.Message {
        let ctrl: WatchCameraControlling

        init(ctrl: WatchCameraControlling) {
            self.ctrl = ctrl
            super.init(sender: nil)
        }
    }

    /// Sent by WatchRemoteCameraController when exiting Watch Remote mode.
    public class UnbecomeWatchCamera: Actor.Message {}

    /// Watch-initiated photo/video mode switch.
    public class SetWatchCameraMode: Actor.Message {
        let mode: RecordingMode

        init(mode: RecordingMode) {
            self.mode = mode
            super.init(sender: nil)
        }
    }
}

// MARK: - Watch Remote Camera State

extension RemoteCamSession {

    func watchRemoteCamera(ctrl: WatchCameraControlling) -> Receive {
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
                    name: .watchRemoteCameraStartingVideo,
                    state: self.watchRemoteCameraStartingVideo(ctrl: ctrl)
                )

            case let micError as UICmd.MicrophoneAccessDenied:
                debugLog("Watch Remote: Microphone access denied: \(micError.error)")
                self.pushWatchState(ctrl: ctrl, event: "microphoneDenied")

            // MARK: - Photo/Video Mode Switch (Watch-initiated)

            case let m as UICmd.SetWatchCameraMode:
                ctrl.currentCameraMode = m.mode
                ctrl.updateCameraStatus()
                self.pushWatchState(ctrl: ctrl)

            // MARK: - Timer Countdown (Watch-initiated)

            case let countdown as RemoteCmd.TimerCountdown:
                ctrl.updateTimerCountdown(value: countdown.value)
                if countdown.value > 0 {
                    self.pushWatchState(ctrl: ctrl, event: "countdown:\(countdown.value)")
                }

            // MARK: - Late Arrivals (sub-state timed out before the callback landed)

            case let t as UICmd.OnPicture:
                // Capture completed after watchRemoteCameraTakingPic gave up —
                // save it anyway and correct the earlier error with the truth.
                debugLog("Watch Remote: late OnPicture (error: \(String(describing: t.error)))")
                if let imageData = t.pic, t.error == nil {
                    self.photoLibrarySaver(imageData)
                    self.pushWatchState(ctrl: ctrl, event: "photoTaken")
                } else {
                    self.pushWatchState(ctrl: ctrl, event: "photoError")
                }

            case is RemoteCmd.StartRecordingVideoAck,
                 is RemoteCmd.StopRecordingVideoResp:
                debugLog("Watch Remote: late recording callback in idle state")
                self.pushWatchState(ctrl: ctrl)

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
                self.watchStatePusher.pushDisconnectedState()
                self.popToRootState()

            case is UICmd.UnbecomeCamera:
                // CameraViewController is being dismissed
                debugLog("Watch Remote: CameraViewController dismissed")
                self.watchStatePusher.pushDisconnectedState()
                self.popToRootState()

            case is UICmd.StateTimeout:
                // Stale timeout from a sub-state that already completed — ignore.
                break

            default:
                self.receive(msg: msg)
            }
        }
    }

    // MARK: - Watch Remote Taking Picture Sub-state

    func watchRemoteCameraTakingPic(ctrl: WatchCameraControlling) -> Receive {
        let gen = self.scheduleTimeout(stateName: .watchRemoteCameraTakingPic)
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter:
                break

            case let t as UICmd.OnPicture:
                if let imageData = t.pic, t.error == nil {
                    debugLog("Watch Remote: Photo captured, saving to library")
                    self.photoLibrarySaver(imageData)
                    self.pushWatchState(ctrl: ctrl, event: "photoTaken")
                } else {
                    debugLog("Watch Remote: Photo capture error: \(String(describing: t.error))")
                    self.pushWatchState(ctrl: ctrl, event: "photoError")
                }
                self.unbecome()

            case let timeout as UICmd.StateTimeout:
                if timeout.stateName == .watchRemoteCameraTakingPic && timeout.generation == gen {
                    debugLog("Watch Remote: photo capture timed out")
                    self.pushWatchState(ctrl: ctrl, event: "photoError")
                    self.unbecome()
                }
                // Stale generations are dropped silently.

            case is RemoteCmd.TakePic:
                debugLog("Watch Remote: capture already in flight, ignoring duplicate TakePic")

            case is RemoteCmd.StartRecordingVideo, is UICmd.SetWatchCameraMode:
                self.pushWatchState(ctrl: ctrl, event: "busy")

            // Zoom keeps working while a capture is in flight (crown turns mid-shot).
            case let zoomCmd as RemoteCmd.SetZoom:
                _ = ctrl.setZoom(zoomFactor: zoomCmd.zoomFactor)
                self.pushWatchState(ctrl: ctrl)

            case is RemoteCmd.RequestCameraCapabilities:
                ctrl.gatherAllCameraCapabilities()
                self.pushWatchState(ctrl: ctrl)

            case is UICmd.UnbecomeWatchCamera, is UICmd.UnbecomeCamera:
                debugLog("Watch Remote: exiting while capture in flight")
                self.watchStatePusher.pushDisconnectedState()
                self.popToRootState()

            default:
                self.receive(msg: msg)
            }
        }
    }

    // MARK: - Watch Remote Starting Video Sub-state (transient)

    /// Waits for the capture pipeline to confirm recording actually started.
    /// Without this, a failed start (mic denied, session interrupted) left the
    /// actor wedged in the recording state with no way out.
    func watchRemoteCameraStartingVideo(ctrl: WatchCameraControlling) -> Receive {
        let gen = self.scheduleTimeout(stateName: .watchRemoteCameraStartingVideo)
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter:
                break

            case let ack as RemoteCmd.StartRecordingVideoAck:
                if let error = ack.error {
                    debugLog("Watch Remote: recording failed to start: \(error)")
                    self.pushWatchState(ctrl: ctrl, event: "recordingFailed")
                    self.unbecome()
                } else {
                    debugLog("Watch Remote: Recording started at \(ack.recordingStartTime?.description ?? "unknown")")
                    self.pushWatchState(ctrl: ctrl, event: "recordingStarted")
                    self.become(
                        name: .watchRemoteCameraRecordingVideo,
                        state: self.watchRemoteCameraRecordingVideo(ctrl: ctrl),
                        discardOld: true
                    )
                }

            case let micError as UICmd.MicrophoneAccessDenied:
                debugLog("Watch Remote: Microphone access denied: \(micError.error)")
                self.pushWatchState(ctrl: ctrl, event: "microphoneDenied")
                self.unbecome()

            case let timeout as UICmd.StateTimeout:
                if timeout.stateName == .watchRemoteCameraStartingVideo && timeout.generation == gen {
                    debugLog("Watch Remote: recording never started, cleaning up")
                    ctrl.stopRecordingVideo(false)
                    self.pushWatchState(ctrl: ctrl, event: "recordingFailed")
                    self.unbecome()
                }

            // User can abort a start that hasn't been confirmed yet.
            case is RemoteCmd.StopRecordingVideo:
                ctrl.stopRecordingVideo(false)
                self.pushWatchState(ctrl: ctrl, event: "recordingStopped")
                self.unbecome()

            case is RemoteCmd.TakePic, is RemoteCmd.StartRecordingVideo, is UICmd.SetWatchCameraMode:
                self.pushWatchState(ctrl: ctrl, event: "busy")

            case let zoomCmd as RemoteCmd.SetZoom:
                _ = ctrl.setZoom(zoomFactor: zoomCmd.zoomFactor)
                self.pushWatchState(ctrl: ctrl)

            case is UICmd.UnbecomeWatchCamera, is UICmd.UnbecomeCamera:
                debugLog("Watch Remote: exiting while recording was starting")
                ctrl.stopRecordingVideo(false)
                self.watchStatePusher.pushDisconnectedState()
                self.popToRootState()

            default:
                self.receive(msg: msg)
            }
        }
    }

    // MARK: - Watch Remote Recording Video Sub-state

    func watchRemoteCameraRecordingVideo(ctrl: WatchCameraControlling) -> Receive {
        // No blanket timeout: recordings legitimately run for minutes. A timeout
        // is armed only once stop is requested, to catch a stop that never
        // completes (capture session interrupted mid-recording).
        var stopGeneration: Int?
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter:
                break

            case is RemoteCmd.StopRecordingVideo:
                if stopGeneration == nil {
                    stopGeneration = self.scheduleTimeout(stateName: .watchRemoteCameraRecordingVideo)
                    ctrl.stopRecordingVideo(false)
                }

            case is RemoteCmd.StopRecordingVideoResp:
                debugLog("Watch Remote: Recording stopped")
                self.pushWatchState(ctrl: ctrl, event: "recordingStopped")
                self.unbecome()

            case let sendVideo as UICmd.SendVideoResource:
                // In Watch mode, video is saved locally only
                debugLog("Watch Remote: Video saved at \(sendVideo.videoURL)")
                self.pushWatchState(ctrl: ctrl, event: "recordingStopped")
                self.unbecome()

            case let timeout as UICmd.StateTimeout:
                if timeout.stateName == .watchRemoteCameraRecordingVideo && timeout.generation == stopGeneration {
                    debugLog("Watch Remote: stop recording never completed")
                    self.pushWatchState(ctrl: ctrl, event: "recordingFailed")
                    self.unbecome()
                }

            case is RemoteCmd.TakePic, is RemoteCmd.StartRecordingVideo, is UICmd.SetWatchCameraMode:
                self.pushWatchState(ctrl: ctrl, event: "busyRecording")

            // Allow zoom/lens/flash/torch during recording
            case let zoomCmd as RemoteCmd.SetZoom:
                _ = ctrl.setZoom(zoomFactor: zoomCmd.zoomFactor)
                self.pushWatchState(ctrl: ctrl)

            case let lensCmd as RemoteCmd.SwitchLens:
                _ = ctrl.switchLens(to: lensCmd.lensType)
                self.pushWatchState(ctrl: ctrl)

            case is RemoteCmd.ToggleTorch:
                _ = ctrl.toggleTorch()
                self.pushWatchState(ctrl: ctrl)

            case is RemoteCmd.RequestCameraCapabilities:
                ctrl.gatherAllCameraCapabilities()
                self.pushWatchState(ctrl: ctrl)

            case is UICmd.UnbecomeWatchCamera, is UICmd.UnbecomeCamera:
                debugLog("Watch Remote: exiting while recording")
                ctrl.stopRecordingVideo(false)
                self.watchStatePusher.pushDisconnectedState()
                self.popToRootState()

            default:
                self.receive(msg: msg)
            }
        }
    }

    // MARK: - Watch State Push Helper (FlatBuffer-encoded)

    func pushWatchState(ctrl: WatchCameraControlling, event: String? = nil) {
        watchStatePusher.pushCameraState(
            Self.watchStateSnapshot(ctrl: ctrl, event: event, isBackgrounded: isPhoneBackgrounded())
        )
    }

    static func watchStateSnapshot(ctrl: WatchCameraControlling,
                                   event: String? = nil,
                                   isBackgrounded: Bool = false) -> WatchCameraStateSnapshot {
        var snapshot = WatchCameraStateSnapshot()
        // Readiness is decided here and nowhere else: the phone can only capture while
        // foregrounded. When backgrounded/locked, report not-ready with the reason the
        // Watch routes to its "app closed" screen — it takes precedence over any
        // transient capture event (e.g. a late "photoTaken") that was in flight.
        snapshot.isReady = !isBackgrounded
        snapshot.lastEvent = isBackgrounded ? WatchNotReadyReason.phoneBackgrounded : event
        snapshot.currentZoomFactor = Double(ctrl.getCurrentZoomFactor())
        snapshot.minZoomFactor = Double(ctrl.getMinZoomFactor())
        snapshot.maxZoomFactor = Double(ctrl.getMaxZoomFactor())
        snapshot.isRecording = ctrl.isRecording
        snapshot.currentMode = ctrl.currentCameraMode == .Video ? .video : .photo
        snapshot.currentLensType = RemoteShutter_CameraLensType(rawValue: Int8(ctrl.getCurrentLensType().rawValue)) ?? .wideangle
        snapshot.availableLensTypes = ctrl.getAvailableLensTypes().compactMap {
            RemoteShutter_CameraLensType(rawValue: Int8($0.rawValue))
        }
        snapshot.isFlashEnabled = ctrl.currentFlashMode != .off
        snapshot.flashMode = RemoteShutter_FlashMode(rawValue: Int8(ctrl.currentFlashMode.rawValue)) ?? .off
        snapshot.isTorchEnabled = ctrl.isTorchActive
        snapshot.zoomStops = ctrl.getZoomStops().map { Double($0) }
        snapshot.wideAngleZoomFactor = Double(ctrl.getWideAngleZoomFactor())
        return snapshot
    }
}
