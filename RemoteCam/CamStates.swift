//
//  RemoteCamSessionCamStates.swift
//  Actors
//
//  Created by Dario Lencina on 11/1/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation
import MultipeerConnectivity
import Photos
import SwiftUI

extension RemoteCamSession {

    // MARK: - Camera Capabilities Retry Helper
    private func attemptToSendCapabilities(ctrl: CameraViewController, peer: MCPeerID, attempt: Int, maxAttempts: Int) {
        debugLog("🔍 DEBUG: Attempt \(attempt)/\(maxAttempts) to gather camera capabilities")
        
        ctrl.gatherAllCameraCapabilities()
        if let capabilities = ctrl.gatherCurrentCameraCapabilities() {
            debugLog("✅ DEBUG: Successfully gathered capabilities on attempt \(attempt)")
            debugLog("🔍 DEBUG: Sending camera capabilities - Available lenses: \(capabilities.getCurrentCameraInfo()?.availableLenses ?? [])")
            self.mailbox.addOperation(BlockOperation {
                self.sendCommandOrGoToScanning(peer: [peer], msg: capabilities)
            })
        } else if attempt < maxAttempts {
            let delay = Double(attempt) * 0.2 // 0.2s, 0.4s, 0.6s, 0.8s delays
            debugLog("⏳ DEBUG: Attempt \(attempt) failed, retrying in \(delay)s")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.attemptToSendCapabilities(ctrl: ctrl, peer: peer, attempt: attempt + 1, maxAttempts: maxAttempts)
            }
        } else {
            debugLog("❌ DEBUG: Failed to gather camera capabilities after \(maxAttempts) attempts")
        }
    }

    func savePicture(_ imageData: Data) {
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
                    print("Saved photo!")
                } else {
                    print("Failed to save photo!")
                }
            }
        }
    }
    
    func cameraTakingPic(peer: MCPeerID,
                         ctrl: CameraViewController,
                         lobby: Weak<DeviceScannerViewController>,
                         sendMediaToPeer: Bool) -> Receive {
        var alertHandle: AlertHandle?
        ^{ [weak self] in
            alertHandle = self?.alertPresenter.showAlert(title: "Taking picture")
        }
        let gen = self.scheduleTimeout(stateName: .cameraTakingPic)
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case let timeout as UICmd.StateTimeout:
                if timeout.stateName == .cameraTakingPic && timeout.generation == gen {
                    ^{ [weak self] in
                        if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                    }
                    let error = NSError(domain: "Photo capture timed out", code: 0)
                    if self.sendMessage(
                        peer: [peer],
                        msg: RemoteCmd.TakePicResp(sender: self.this, error: error)).isSuccess() {
                        self.unbecome()
                    } else {
                        self.popAndStartScanning()
                    }
                }

            case let t as UICmd.OnPicture:
                if let imageData = t.pic {
                    savePicture(imageData)
                }
                ^{ [weak self] in
                    if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                }
                if self.sendMessage(
                    peer: [peer],
                    msg: RemoteCmd.TakePicAck(sender: self.this)).isFailure() {
                    self.popToState(name: .scanning)
                    return
                }
                if self.sendMessage(
                    peer: [peer],
                    msg: RemoteCmd.TakePicResp(sender: self.this, pic: sendMediaToPeer ? t.pic : nil, error: t.error)).isFailure() {
                    self.popToState(name: .scanning)
                    return
                }
                self.unbecome()

            case let c as DisconnectPeer:
                ^{ [weak self] in
                    if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                }
                if c.peer?.displayName == peer.displayName && self.connectedPeers.count == 0 {
                    self.popAndStartScanning()
                }

            case is Disconnect:
                ^{ [weak self] in
                    if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                }
                self.popAndStartScanning()

            default:
                self.receive(msg: msg)
            }
        }
    }

    func camera(peer: MCPeerID,
                ctrl: CameraViewController,
                lobbyWrapper: Weak<DeviceScannerViewController>) -> Receive {
        
        return { [unowned self] (msg: Actor.Message) in
            guard lobbyWrapper.value != nil else {
                popAndStartScanning()
                return
            }
            
            switch msg {
            case is OnEnter:
                debugLog("🔍 DEBUG: Camera starting up")
                getFrameSender()?.tell(msg: SetSession(peer: peer, session: self))
                
            case is RemoteCmd.PeerBecameMonitor:
                // When a new monitor joins, immediately send camera capabilities
                debugLog("🔍 DEBUG: Camera received PeerBecameMonitor - attempting to send capabilities")
                self.attemptToSendCapabilities(ctrl: ctrl, peer: peer, attempt: 1, maxAttempts: 5)
                
            case is RemoteCmd.RequestCameraCapabilities:
                // When monitor explicitly requests capabilities
                debugLog("🔍 DEBUG: Camera received RequestCameraCapabilities - attempting to gather capabilities")
                self.attemptToSendCapabilities(ctrl: ctrl, peer: peer, attempt: 1, maxAttempts: 5)
                
            case is RemoteCmd.RequestFrame:
                self.receive(msg: msg)
                
            case is RemoteCmd.SendFrame:
                self.receive(msg: msg)
                
            case let m as UICmd.ToggleCameraResp:
                self.sendCommandOrGoToScanning(
                    peer: [peer],
                    msg: RemoteCmd.ToggleCameraResp(cameraCapabilities: nil,
                                                    error: m.error))

            case is RemoteCmd.StartRecordingVideo:
                ctrl.currentCameraMode = .Video
                ctrl.updateCameraStatus()
                ctrl.startRecordingVideo()
                self.become(
                        name: .cameraRecordingVideo,
                        state: self.cameraShootingVideo(peer: peer,
                                ctrl: ctrl,
                                lobby: lobbyWrapper)
                )
            
            case let micError as UICmd.MicrophoneAccessDenied:
                // Handle microphone access denied during recording setup
                let ack = RemoteCmd.StopRecordingVideoAck()
                self.sendCommandOrGoToScanning(peer: [peer], msg: ack, mode: .reliable)
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.StopRecordingVideoResp(sender: nil, error: micError.error), mode: .reliable)

            case let cmd as RemoteCmd.TakePic:
                ctrl.currentCameraMode = .Photo
                ctrl.updateCameraStatus()
                ctrl.takePicture(cmd.sendMediaToPeer)
                self.become(name: .cameraTakingPic,
                            state: self.cameraTakingPic(peer: peer, ctrl: ctrl, lobby: lobbyWrapper, sendMediaToPeer: cmd.sendMediaToPeer))

            case is RemoteCmd.ToggleCamera:
                debugLog("🔍 DEBUG: Camera received ToggleCamera command")
                let result = ctrl.toggleCamera()
                var resp: Message?
                if let (_, position) = result.toOptional() {
                    debugLog("✅ DEBUG: Camera toggle success - new position: \(position)")
                    // Send camera capabilities as part of the response
                    let capabilities = ctrl.gatherCurrentCameraCapabilities()
                    resp = RemoteCmd.ToggleCameraResp(cameraCapabilities: capabilities, error: nil)
                } else if let failure = result as? Failure {
                    debugLog("❌ DEBUG: Camera toggle failed: \(failure.tryError.localizedDescription)")
                    resp = RemoteCmd.ToggleCameraResp(cameraCapabilities: nil, error: failure.tryError)
                }
                self.sendCommandOrGoToScanning(peer: [peer], msg: resp!)
                
            case is RemoteCmd.ToggleFlash:
                let result = ctrl.toggleFlash()
                var resp: Message?
                if let flashMode = result.toOptional() {
                    resp = RemoteCmd.ToggleFlashResp(flashMode: flashMode, error: nil)
                } else if let failure = result as? Failure {
                    resp = RemoteCmd.ToggleFlashResp(flashMode: nil, error: failure.error)
                }
                self.sendCommandOrGoToScanning(peer: [peer], msg: resp!)
                
            // MARK: - Torch Command Handling
            case is RemoteCmd.ToggleTorch:
                let result = ctrl.toggleTorch()
                var resp: Message?
                if let torchMode = result.toOptional() {
                    resp = RemoteCmd.ToggleTorchResp(torchMode: torchMode, error: nil)
                } else if let failure = result as? Failure {
                    resp = RemoteCmd.ToggleTorchResp(torchMode: nil, error: failure.error)
                }
                self.sendCommandOrGoToScanning(peer: [peer], msg: resp!)
                
            case let torchCmd as RemoteCmd.SetTorch:
                let result = ctrl.setTorchMode(mode: torchCmd.torchMode)
                var resp: Message?
                if let torchMode = result.toOptional() {
                    resp = RemoteCmd.SetTorchResp(torchMode: torchMode, error: nil)
                } else if let failure = result as? Failure {
                    resp = RemoteCmd.SetTorchResp(torchMode: nil, error: failure.error)
                }
                self.sendCommandOrGoToScanning(peer: [peer], msg: resp!)
                
            // MARK: - Zoom Command Handling
            case let zoomCmd as RemoteCmd.SetZoom:
                debugLog("🔍 DEBUG: Camera received SetZoom: \(zoomCmd.zoomFactor)")
                let result = ctrl.setZoom(zoomFactor: zoomCmd.zoomFactor)
                var resp: Message?
                if let (zoomFactor, currentLens, zoomRange) = result.toOptional() {
                    resp = RemoteCmd.SetZoomResp(zoomFactor: zoomFactor, currentLens: currentLens, zoomRange: zoomRange, error: nil)
                } else if let failure = result as? Failure {
                    debugLog("❌ DEBUG: Camera zoom failed: \(failure.tryError.localizedDescription)")
                    resp = RemoteCmd.SetZoomResp(zoomFactor: nil, currentLens: nil, zoomRange: nil, error: failure.tryError)
                }
                self.sendCommandOrGoToScanning(peer: [peer], msg: resp!)
                
            // MARK: - Lens Switching Command Handling  
            case let lensCmd as RemoteCmd.SwitchLens:
                debugLog("🔍 DEBUG: Camera received SwitchLens command to \(lensCmd.lensType.displayName)")
                let result = ctrl.switchLens(to: lensCmd.lensType)
                var resp: Message?
                if let (lensType, availableLenses, currentZoom, zoomRange) = result.toOptional() {
                    debugLog("✅ DEBUG: Camera lens switch success - new lens: \(lensType.displayName)")
                    resp = RemoteCmd.SwitchLensResp(lensType: lensType, availableLenses: availableLenses, currentZoom: currentZoom, zoomRange: zoomRange, error: nil)

                } else if let failure = result as? Failure {
                    debugLog("❌ DEBUG: Camera lens switch failed: \(failure.tryError.localizedDescription)")
                    resp = RemoteCmd.SwitchLensResp(lensType: nil, availableLenses: nil, currentZoom: nil, zoomRange: nil, error: failure.error)
                    debugLog("🔍 DEBUG: Created error response:")
//                    debugLog("🔍 DEBUG: - error: \(failure.error.localizedDescription)")
                }
                

                self.sendCommandOrGoToScanning(peer: [peer], msg: resp!)

            // MARK: - Sync Monitor Settings
            case let sync as RemoteCmd.SyncMonitorSettings:
                ^{
                    ctrl.currentCameraMode = sync.mode
                    ctrl.updateCameraStatus()
                }

            // MARK: - Timer Countdown Handling
            case let countdown as RemoteCmd.TimerCountdown:
                ^{
                    if countdown.value > 0 {
                        ctrl.cameraViewModel.showCountdown(countdown.value)
                        ctrl.playCountdownChime(remaining: countdown.value)
                    } else if countdown.value == 0 {
                        ctrl.cameraViewModel.clearCountdown()
                        ctrl.restoreTorchAfterCountdown()
                    } else {
                        ctrl.cameraViewModel.cancelCountdown()
                        ctrl.restoreTorchAfterCountdown()
                    }
                }

            // MARK: - Video Quality Command Handling
            case let cmd as RemoteCmd.SetVideoQuality:
                if let (resolution, frameRate) = ctrl.setVideoQuality(resolution: cmd.resolution, frameRate: cmd.frameRate) {
                    self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.SetVideoQualityResp(resolution: resolution, frameRate: frameRate, error: nil))
                } else {
                    let error = NSError(domain: "RemoteShutter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video quality not supported"])
                    self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.SetVideoQualityResp(resolution: nil, frameRate: nil, error: error))
                }

            // MARK: - Photo Quality Command Handling
            case let cmd as RemoteCmd.SetPhotoQuality:
                if let (format, hdrMode) = ctrl.setPhotoQuality(format: cmd.format, hdrMode: cmd.hdrMode) {
                    self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.SetPhotoQualityResp(format: format, hdrMode: hdrMode, error: nil))
                } else {
                    let error = NSError(domain: "RemoteShutter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Photo quality not supported"])
                    self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.SetPhotoQualityResp(format: nil, hdrMode: nil, error: error))
                }

            // MARK: - Aspect Ratio Command Handling
            case let cmd as RemoteCmd.SetAspectRatio:
                let result = ctrl.setAspectRatio(cmd.aspectRatio)
                self.sendCommandOrGoToScanning(peer: [peer],
                    msg: RemoteCmd.SetAspectRatioResp(aspectRatio: result, error: nil))

            case let c as DisconnectPeer:
                if c.peer?.displayName == peer.displayName && self.connectedPeers.count == 0 {
                    debugLog("🔍 DEBUG: Camera disconnecting peer - going to scanning")
                    self.popAndStartScanning()
                }

            case is Disconnect:
                debugLog("🔍 DEBUG: Camera disconnecting - going to scanning")
                self.popAndStartScanning()

            case is UICmd.UnbecomeCamera:
                debugLog("🔍 DEBUG: Camera explicitly unbecoming - going to connected state")
                self.popToState(name: .connected)

            default:
                self.receive(msg: msg)
            }
        }
    }

}
