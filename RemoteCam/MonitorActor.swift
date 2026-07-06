//
//  MonitorActor.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union. All rights reserved.
//

import Foundation
import AVFoundation

/// Binds a `MonitorDisplay` to `MonitorActor`. The protocol-typed counterpart
/// of Theater's `SetViewCtrl` (whose generic parameter requires a concrete class).
public class SetMonitorDisplay: Actor.Message {
    let display: MonitorDisplay

    init(display: MonitorDisplay) {
        self.display = display
        super.init(sender: nil)
    }
}

/// Weak box for the display — `Weak<T>` requires a concrete class type, and
/// the display is deliberately a protocol existential.
final class WeakMonitorDisplay {
    weak var value: MonitorDisplay?
    init(_ value: MonitorDisplay) { self.value = value }
}

/**
Monitor actor has a reference to the session actor and to the monitor screen
(via `MonitorDisplay`); it acts as the connection between the model and the
UI from an MVC perspective.
*/

public class MonitorActor: Actor {

    let waitingForDisplayState = "waitingForDisplay"
    let withDisplayState = "withDisplay"

    public required init(context: ActorSystem, ref: ActorRef) {
        super.init(context: context, ref: ref)
        mailbox = OperationQueue()
        let session: ActorRef? = RemoteCamSystem.shared.selectActor(actorPath: "RemoteCam/user/RemoteCam Session")
        session! ! UICmd.BecomeMonitor(ref, mode: .Photo)
    }

    override public func preStart() {
        super.preStart()
        become(name: waitingForDisplayState, state: waitingForDisplay)
    }

    lazy var waitingForDisplay: Receive = { [unowned self] (msg: Actor.Message) in
        switch msg {
        case let m as SetMonitorDisplay:
            self.become(name: self.withDisplayState,
                        state: self.receiveWithDisplay(ctrl: WeakMonitorDisplay(m.display)))
        default:
            self.receive(msg: msg)
        }
    }

    func receiveWithDisplay(ctrl: WeakMonitorDisplay) -> Receive {

        return { [unowned self](msg: Message) in
            switch msg {

            case is UICmd.RenderPhotoMode:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.swiftUIConfigurePhotoMode()
                }

            case is UICmd.RenderVideoMode:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.swiftUIConfigureVideoMode()
                }

            case is UICmd.RenderVideoModeRecording:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.swiftUIConfigureVideoRecording()
                }

            case let cmd as UICmd.SyncRecordingStartTime:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.viewModel.recordingStartTime = cmd.startTime
                }

            case is UICmd.RenderShortsMode:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.swiftUIConfigureShortsMode()
                }

            case is UICmd.BecomeMonitorFailed:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.exitMonitor()
                }

            case let cam as UICmd.ToggleCameraResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ctrl = ctrl?.value, let flashMode = cam.flashMode {
                        ctrl.updateFlashModeInViewModel(flashMode)
                    }
                }

            case let flash as RemoteCmd.ToggleFlashResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ctrl = ctrl?.value, let flashMode = flash.flashMode {
                        ctrl.updateFlashModeInViewModel(flashMode)
                    }
                }

            case let torch as RemoteCmd.ToggleTorchResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ctrl = ctrl?.value, let torchMode = torch.torchMode {
                        ctrl.updateTorchModeInViewModel(torchMode)
                    }
                }

            case let torchSet as RemoteCmd.SetTorchResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ctrl = ctrl?.value, let torchMode = torchSet.torchMode {
                        ctrl.updateTorchModeInViewModel(torchMode)
                    }
                }

            case let f as RemoteCmd.OnFrame:
                // Decode off the mailbox: the receiver's queue handles JPEG and
                // HEIC alike and drives the stall watchdog.
                ctrl.value?.frameStreamReceiver.receive(f)

            // MARK: - Camera Capabilities Response Handling
            case let capabilities as RemoteCmd.CameraCapabilitiesResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ctrl = ctrl?.value, let cameraInfo = capabilities.getCurrentCameraInfo() {
                        // Update lens controls in view model
                        ctrl.updateLensTypesInViewModel(
                            cameraInfo.availableLenses,
                            current: capabilities.currentLens
                        )

                        // Update zoom controls in view model
                        if let zoomRange = cameraInfo.getZoomCapabilities()[capabilities.currentLens] {
                            ctrl.updateZoomInViewModel(
                                capabilities.currentZoom,
                                maxFactor: zoomRange.maxZoom
                            )
                        }

                        // Update quality capabilities in view model
                        ctrl.viewModel.updateVideoCapabilities(
                            resolutions: cameraInfo.supportedResolutions,
                            frameRates: cameraInfo.supportedFrameRates,
                            resolutionFrameRates: cameraInfo.getResolutionFrameRates())
                        ctrl.viewModel.updatePhotoCapabilities(
                            supportsHEIF: cameraInfo.supportsHEIF,
                            supportsHDR: cameraInfo.supportsHDR)

                        // Sync current quality settings from camera
                        ctrl.viewModel.updateVideoQuality(
                            resolution: capabilities.currentVideoResolution,
                            frameRate: capabilities.currentVideoFrameRate)
                        ctrl.viewModel.updatePhotoQuality(
                            format: capabilities.currentPhotoFormat,
                            hdrMode: capabilities.currentHDRMode)

                        // Update zoom stops from camera capabilities
                        ctrl.viewModel.updateZoomStops(
                            cameraInfo.zoomStops,
                            wideAngleZoomFactor: cameraInfo.wideAngleZoomFactor
                        )
                    }
                }

            // MARK: - Zoom Response Handling
            case let zoom as UICmd.SetZoomResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ctrl = ctrl?.value, let zoomFactor = zoom.zoomFactor {
                        let maxZoom = zoom.zoomRange?.maxZoom ?? ctrl.maxZoomFactor
                        ctrl.updateZoomInViewModel(zoomFactor, maxFactor: maxZoom)
                        // Sync lens type so zoom and lens controls stay cohesive
                        if let lens = zoom.currentLens {
                            ctrl.viewModel.updateAvailableLenses(ctrl.viewModel.availableLensTypes, current: lens)
                        }
                    }
                }

            case let zoomRemote as RemoteCmd.SetZoomResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ctrl = ctrl?.value, let zoomFactor = zoomRemote.zoomFactor {
                        let maxZoom = zoomRemote.zoomRange?.maxZoom ?? ctrl.maxZoomFactor
                        ctrl.updateZoomInViewModel(zoomFactor, maxFactor: maxZoom)
                        // Sync lens type so zoom and lens controls stay cohesive
                        if let lens = zoomRemote.currentLens {
                            ctrl.viewModel.updateAvailableLenses(ctrl.viewModel.availableLensTypes, current: lens)
                        }
                    }
                }

            // MARK: - Lens Response Handling
            case let lens as UICmd.SwitchLensResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ctrl = ctrl?.value,
                       let lensType = lens.lensType,
                       let availableLenses = lens.availableLenses {
                        ctrl.updateLensTypesInViewModel(availableLenses, current: lensType)
                        if let currentZoom = lens.currentZoom,
                           let zoomRange = lens.zoomRange {
                            ctrl.updateZoomInViewModel(currentZoom, maxFactor: zoomRange.maxZoom)
                        }
                    }
                }

            case let lensRemote as RemoteCmd.SwitchLensResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ctrl = ctrl?.value,
                       let lensType = lensRemote.lensType,
                       let availableLenses = lensRemote.availableLenses {
                        ctrl.updateLensTypesInViewModel(availableLenses, current: lensType)
                        if let currentZoom = lensRemote.currentZoom,
                           let zoomRange = lensRemote.zoomRange {
                            ctrl.updateZoomInViewModel(currentZoom, maxFactor: zoomRange.maxZoom)
                        }
                    }
                }

            // MARK: - Video Quality Response Handling
            case let videoQuality as RemoteCmd.SetVideoQualityResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let resolution = videoQuality.resolution,
                       let frameRate = videoQuality.frameRate {
                        ctrl?.value?.viewModel.updateVideoQuality(resolution: resolution, frameRate: frameRate)
                    }
                }

            // MARK: - Photo Quality Response Handling
            case let photoQuality as RemoteCmd.SetPhotoQualityResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let format = photoQuality.format,
                       let hdrMode = photoQuality.hdrMode {
                        ctrl?.value?.viewModel.updatePhotoQuality(format: format, hdrMode: hdrMode)
                    }
                }

            // MARK: - Aspect Ratio Response Handling
            case let ratioResp as RemoteCmd.SetAspectRatioResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ratio = ratioResp.aspectRatio {
                        ctrl?.value?.viewModel.updateAspectRatio(ratio)
                    }
                }

            // MARK: - Video Transfer Progress Handling
            case let started as UICmd.VideoResourceTransferStarted:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.viewModel.startVideoTransfer(totalBytes: started.totalBytes)
                    print("📺 DEBUG: MonitorActor - Video transfer started: \(started.totalBytes) bytes")
                }

            case let progress as UICmd.VideoResourceTransferProgress:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.viewModel.updateVideoTransferProgress(
                        completedBytes: progress.completedBytes,
                        totalBytes: progress.totalBytes
                    )
                    ctrl?.value?.viewModel.updateVideoTransferSpeed(progress.transferSpeed)
                    print("📺 DEBUG: MonitorActor - Video transfer progress: \(Int(progress.progress * 100))% - Speed: \(String(format: "%.1f", progress.transferSpeed / 1024 / 1024)) MB/s")
                }

            case is UICmd.VideoResourceTransferCompleted:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.viewModel.finishVideoTransfer()
                    print("📺 DEBUG: MonitorActor - Video transfer completed")
                }

            case let failed as UICmd.VideoResourceTransferFailed:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.viewModel.finishVideoTransfer()
                    print("📺 DEBUG: MonitorActor - Video transfer failed: \(failed.error.localizedDescription)")
                }

            default:
                self.receive(msg: msg)
            }
        }
    }
}
