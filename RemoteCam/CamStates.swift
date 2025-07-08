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
                        self.mailbox.addOperation {
                            self.popAndStartScanning()
                        }
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
        return { [unowned self] (msg: Actor.Message) in
            guard lobbyWrapper.value != nil else {
                popAndStartScanning()
                return
            }
            switch msg {
            case is OnEnter:
                getFrameSender()?.tell(msg: SetSession(peer: peer, session: self))
            case let m as UICmd.ToggleCameraResp:
                self.sendCommandOrGoToScanning(
                    peer: [peer],
                    msg: RemoteCmd.ToggleCameraResp(flashMode: m.flashMode,
                                                    camPosition: m.camPosition,
                                                    error: nil))

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
                let result = ctrl.toggleCamera()
                // Note: Camera capabilities are now sent automatically in CameraViewController.toggleCamera()
                // We don't need to send a separate response here as the capabilities are sent via sendCameraCapabilities()
                
            case is RemoteCmd.ToggleFlash:
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
                let result = ctrl.setZoom(zoomFactor: zoomCmd.zoomFactor)
                var resp: Message?
                if let (zoomFactor, currentLens, zoomRange) = result.toOptional() {
                    resp = RemoteCmd.SetZoomResp(zoomFactor: zoomFactor, currentLens: currentLens, zoomRange: zoomRange, error: nil)
                } else if let failure = result as? Failure {
                    resp = RemoteCmd.SetZoomResp(zoomFactor: nil, currentLens: nil, zoomRange: nil, error: failure.error)
                }
                self.sendCommandOrGoToScanning(peer: [peer], msg: resp!)
                
            // MARK: - Lens Switching Command Handling  
            case let lensCmd as RemoteCmd.SwitchLens:
                let result = ctrl.switchLens(to: lensCmd.lensType)
                var resp: Message?
                if let (lensType, availableLenses, currentZoom, zoomRange) = result.toOptional() {
                    resp = RemoteCmd.SwitchLensResp(lensType: lensType, availableLenses: availableLenses, currentZoom: currentZoom, zoomRange: zoomRange, error: nil)
                } else if let failure = result as? Failure {
                    resp = RemoteCmd.SwitchLensResp(lensType: nil, availableLenses: nil, currentZoom: nil, zoomRange: nil, error: failure.error)
                }
                self.sendCommandOrGoToScanning(peer: [peer], msg: resp!)

            case let c as DisconnectPeer:
                if c.peer.displayName == peer.displayName && self.session.connectedPeers.count == 0 {
                    self.popAndStartScanning()
                }

            case is Disconnect:
                self.popAndStartScanning()

            case is UICmd.UnbecomeCamera:
                self.popToState(name: self.states.connected)

            default:
                self.receive(msg: msg)
            }
        }
    }

}
