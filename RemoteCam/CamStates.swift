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
            }) { (success: Bool, err: Error?) in
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
                         lobby: RolePickerController) -> Receive {
        var alert: UIAlertController?
        ^{
            alert = UIAlertController(title: "Taking picture",
                message: nil,
                preferredStyle: .alert)
        
            alert?.show(true)
        }
        return { [unowned self] (msg: Actor.Message) in
            switch (msg) {
            case let t as UICmd.OnPicture:
                if let imageData = t.pic {
                    savePicture(imageData)
                }
                ^{
                    alert?.dismiss(animated: true, completion: nil)
                }
                if(self.sendMessage(
                    peer: [peer],
                    msg: RemoteCmd.TakePicAck(sender: self.this)).isFailure()) {
                    self.popToState(name: self.states.scanning)
                    return
                }
                if(self.sendMessage(
                    peer: [peer],
                    msg: RemoteCmd.TakePicResp(sender: self.this, pic: t.pic, error: t.error)).isFailure()) {
                    self.popToState(name: self.states.scanning)
                    return
                }
                self.unbecome()
            case let c as DisconnectPeer:
                ^{
                    alert?.dismiss(animated: true, completion: nil)
                    if (c.peer.displayName == peer.displayName && self.session.connectedPeers.count == 0) {
                        mailbox.addOperation {
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
                lobby: RolePickerController) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch (msg) {
            case let m as UICmd.ToggleCameraResp:
                self.sendCommandOrGoToScanning(
                    peer: [peer],
                    msg: RemoteCmd.ToggleCameraResp(flashMode: m.flashMode,
                                                    camPosition: m.camPosition,
                                                    error: nil))

            case let s as RemoteCmd.SendFrame:
                self.sendCommandOrGoToScanning(peer: [peer], msg: s, mode: .unreliable)

            case is RemoteCmd.StartRecordingVideo:
                ctrl.startRecordingVideo()
                self.become(
                        name: self.states.cameraRecordingVideo,
                        state: self.cameraShootingVideo(peer: peer,
                                ctrl: ctrl,
                                lobby: lobby)
                )
                                    
            case is RemoteCmd.TakePic:
                ctrl.takePicture()
                self.become(name: self.states.cameraTakingPic,
                        state: self.cameraTakingPic(peer: peer, ctrl: ctrl, lobby: lobby))

            case is RemoteCmd.ToggleCamera:
                let result = ctrl.toggleCamera()
                var resp: Message?
                if let (flashMode, camPosition) = result.toOptional() {
                    resp = RemoteCmd.ToggleCameraResp(flashMode: flashMode, camPosition: camPosition, error: nil)
                } else if let failure = result as? Failure {
                    resp = RemoteCmd.ToggleCameraResp(flashMode: nil, camPosition: nil, error: failure.error)
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

            case is UICmd.UnbecomeCamera:
                self.popToState(name: self.states.connected)

            case let c as DisconnectPeer:
                if c.peer.displayName == peer.displayName && self.session.connectedPeers.count == 0 {
                    self.popAndStartScanning()
                }

            case is Disconnect:
                self.popAndStartScanning()

            default:
                self.receive(msg: msg)
            }
        }
    }

}
