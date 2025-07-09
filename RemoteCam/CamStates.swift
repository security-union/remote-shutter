//
//  RemoteCamSessionCamStates.swift
//  Actors
//
//  Created by Dario Lencina on 11/1/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation
import Theater
import MultipeerConnectivity
import Photos

extension RemoteCamSession {

    func savePicture(_ imageData: Data) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
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
        var alert: UIAlertController?
        ^{
            alert = UIAlertController(title: "Taking picture",
                message: nil,
                preferredStyle: .alert)

            alert?.show(true)
        }
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case let t as UICmd.OnPicture:
                if let imageData = t.pic {
                    savePicture(imageData)
                }
                ^{
                    alert?.dismiss(animated: true, completion: nil)
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
                ^{
                    alert?.dismiss(animated: true, completion: nil)
                    if c.peer.displayName == peer.displayName && self.session.connectedPeers.count == 0 {
                        self.mailbox.addOperation(BlockOperation {
                            self.popAndStartScanning()
                        })
                    }
                }

            case is Disconnect:
                ^{
                    alert?.dismiss(animated: true)
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
        var capabilitiesSent = false
        
        return { [unowned self] (msg: Actor.Message) in
            guard lobbyWrapper.value != nil else {
                popAndStartScanning()
                return
            }
            
            // Helper function to send capabilities if not already sent
            func sendCapabilitiesIfNeeded() {
                if !capabilitiesSent {
                    print("🔍 DEBUG: First command received - gathering camera capabilities")
                    ctrl.gatherAllCameraCapabilities()
                    if let capabilities = ctrl.gatherCurrentCameraCapabilities() {
                        print("🔍 DEBUG: Sending camera capabilities to monitor")
                        print("🔍 DEBUG: Available lenses: \(capabilities.getCurrentCameraInfo()?.availableLenses ?? [])")
                        self.sendCommandOrGoToScanning(peer: [peer], msg: capabilities)
                        capabilitiesSent = true
                    }
                }
            }
            
            switch msg {
            case is OnEnter:
                print("🔍 DEBUG: Camera starting up")
                getFrameSender()?.tell(msg: SetSession(peer: peer, session: self))
                
                // Send capabilities after a brief delay to ensure camera is fully initialized
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print("🔍 DEBUG: Camera entered - gathering and sending capabilities (delayed)")
                    ctrl.gatherAllCameraCapabilities()
                    if let capabilities = ctrl.gatherCurrentCameraCapabilities() {
                        print("🔍 DEBUG: Sending camera capabilities to monitor")
                        print("🔍 DEBUG: Available lenses: \(capabilities.getCurrentCameraInfo()?.availableLenses ?? [])")
                        self.mailbox.addOperation(BlockOperation {
                            self.sendCommandOrGoToScanning(peer: [peer], msg: capabilities)
                            capabilitiesSent = true
                        })
                    } else {
                        print("❌ DEBUG: Failed to gather current camera capabilities in OnEnter")
                    }
                }
                
            case is RemoteCmd.RequestFrame:
                // Send capabilities on first frame request, then handle normally
                sendCapabilitiesIfNeeded()
                self.receive(msg: msg)
                
            case is RemoteCmd.SendFrame:
                // Send capabilities on first frame send, then handle normally
                sendCapabilitiesIfNeeded()
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

            case let cmd as RemoteCmd.TakePic:
                ctrl.takePicture(cmd.sendMediaToPeer)
                self.become(name: self.states.cameraTakingPic,
                            state: self.cameraTakingPic(peer: peer, ctrl: ctrl, lobby: lobbyWrapper, sendMediaToPeer: cmd.sendMediaToPeer))

            case is RemoteCmd.ToggleCamera:
                sendCapabilitiesIfNeeded() // Ensure capabilities are sent
                print("🔍 DEBUG: Camera received ToggleCamera command")
                let result = ctrl.toggleCamera()
                var resp: Message?
                if let (flashMode, position) = result.toOptional() {
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
                sendCapabilitiesIfNeeded() // Ensure capabilities are sent
                let result = ctrl.toggleFlash()
                var resp: Message?
                if let flashMode = result.toOptional() {
                    resp = RemoteCmd.ToggleFlashResp(flashMode: flashMode, error: nil)
                } else if let failure = result as? Failure {
                    resp = RemoteCmd.ToggleFlashResp(flashMode: nil, error: failure.error)
                }
                self.sendCommandOrGoToScanning(peer: [peer], msg: resp!)
                
            // MARK: - Zoom Command Handling
            case let zoomCmd as RemoteCmd.SetZoom:
                sendCapabilitiesIfNeeded() // Ensure capabilities are sent
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
                sendCapabilitiesIfNeeded() // Ensure capabilities are sent
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
                if c.peer.displayName == peer.displayName && self.session.connectedPeers.count == 0 {
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
