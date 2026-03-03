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
        print("🔍 DEBUG: Attempt \(attempt)/\(maxAttempts) to gather camera capabilities")
        
        ctrl.gatherAllCameraCapabilities()
        if let capabilities = ctrl.gatherCurrentCameraCapabilities() {
            print("✅ DEBUG: Successfully gathered capabilities on attempt \(attempt)")
            print("🔍 DEBUG: Sending camera capabilities - Available lenses: \(capabilities.getCurrentCameraInfo()?.availableLenses ?? [])")
            self.mailbox.addOperation(BlockOperation {
                self.sendCommandOrGoToScanning(peer: [peer], msg: capabilities)
            })
        } else if attempt < maxAttempts {
            let delay = Double(attempt) * 0.2 // 0.2s, 0.4s, 0.6s, 0.8s delays
            print("⏳ DEBUG: Attempt \(attempt) failed, retrying in \(delay)s")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.attemptToSendCapabilities(ctrl: ctrl, peer: peer, attempt: attempt + 1, maxAttempts: maxAttempts)
            }
        } else {
            print("❌ DEBUG: Failed to gather camera capabilities after \(maxAttempts) attempts")
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
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
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
                    self.popToState(name: self.states.scanning)
                    return
                }
                if self.sendMessage(
                    peer: [peer],
                    msg: RemoteCmd.TakePicResp(sender: self.this, pic: sendMediaToPeer ? t.pic : nil, error: t.error)).isFailure() {
                    self.popToState(name: self.states.scanning)
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
                print("🔍 DEBUG: Camera starting up")
                getFrameSender()?.tell(msg: SetSession(peer: peer, session: self))
                
            case is RemoteCmd.PeerBecameMonitor:
                // When a new monitor joins, immediately send camera capabilities
                print("🔍 DEBUG: Camera received PeerBecameMonitor - attempting to send capabilities")
                self.attemptToSendCapabilities(ctrl: ctrl, peer: peer, attempt: 1, maxAttempts: 5)
                
            case is RemoteCmd.RequestCameraCapabilities:
                // When monitor explicitly requests capabilities
                print("🔍 DEBUG: Camera received RequestCameraCapabilities - attempting to gather capabilities")
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
                ctrl.startRecordingVideo()
                self.become(
                        name: self.states.cameraRecordingVideo,
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
                ctrl.takePicture(cmd.sendMediaToPeer)
                self.become(name: self.states.cameraTakingPic,
                            state: self.cameraTakingPic(peer: peer, ctrl: ctrl, lobby: lobbyWrapper, sendMediaToPeer: cmd.sendMediaToPeer))

            case is RemoteCmd.ToggleCamera:
                print("🔍 DEBUG: Camera received ToggleCamera command")
                let result = ctrl.toggleCamera()
                var resp: Message?
                if let (_, position) = result.toOptional() {
                    print("✅ DEBUG: Camera toggle success - new position: \(position)")
                    // Send camera capabilities as part of the response
                    let capabilities = ctrl.gatherCurrentCameraCapabilities()
                    resp = RemoteCmd.ToggleCameraResp(cameraCapabilities: capabilities, error: nil)
                } else if let failure = result as? Failure {
                    print("❌ DEBUG: Camera toggle failed: \(failure.tryError.localizedDescription)")
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
                print("🔍 DEBUG: Camera received SetZoom: \(zoomCmd.zoomFactor)")
                let result = ctrl.setZoom(zoomFactor: zoomCmd.zoomFactor)
                var resp: Message?
                if let (zoomFactor, currentLens, zoomRange) = result.toOptional() {
                    resp = RemoteCmd.SetZoomResp(zoomFactor: zoomFactor, currentLens: currentLens, zoomRange: zoomRange, error: nil)
                } else if let failure = result as? Failure {
                    print("❌ DEBUG: Camera zoom failed: \(failure.tryError.localizedDescription)")
                    resp = RemoteCmd.SetZoomResp(zoomFactor: nil, currentLens: nil, zoomRange: nil, error: failure.tryError)
                }
                self.sendCommandOrGoToScanning(peer: [peer], msg: resp!)
                
            // MARK: - Lens Switching Command Handling  
            case let lensCmd as RemoteCmd.SwitchLens:
                print("🔍 DEBUG: Camera received SwitchLens command to \(lensCmd.lensType.displayName)")
                let result = ctrl.switchLens(to: lensCmd.lensType)
                var resp: Message?
                if let (lensType, availableLenses, currentZoom, zoomRange) = result.toOptional() {
                    print("✅ DEBUG: Camera lens switch success - new lens: \(lensType.displayName)")
                    resp = RemoteCmd.SwitchLensResp(lensType: lensType, availableLenses: availableLenses, currentZoom: currentZoom, zoomRange: zoomRange, error: nil)

                } else if let failure = result as? Failure {
                    print("❌ DEBUG: Camera lens switch failed: \(failure.tryError.localizedDescription)")
                    resp = RemoteCmd.SwitchLensResp(lensType: nil, availableLenses: nil, currentZoom: nil, zoomRange: nil, error: failure.error)
                    print("🔍 DEBUG: Created error response:")
//                    print("🔍 DEBUG: - error: \(failure.error.localizedDescription)")
                }
                

                self.sendCommandOrGoToScanning(peer: [peer], msg: resp!)

            case let c as DisconnectPeer:
                if c.peer?.displayName == peer.displayName && self.connectedPeers.count == 0 {
                    print("🔍 DEBUG: Camera disconnecting peer - going to scanning")
                    self.popAndStartScanning()
                }

            case is Disconnect:
                print("🔍 DEBUG: Camera disconnecting - going to scanning")
                self.popAndStartScanning()

            case is UICmd.UnbecomeCamera:
                print("🔍 DEBUG: Camera explicitly unbecoming - going to connected state")
                self.popToState(name: self.states.connected)

            default:
                self.receive(msg: msg)
            }
        }
    }

}
