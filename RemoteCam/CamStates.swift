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

    func cameraTakingPic(peer: MCPeerID,
                         ctrl: CameraViewController,
                         lobby: RolePickerController) -> Receive {
        let alert = UIAlertController(title: "Taking picture",
                message: nil,
                preferredStyle: .alert)

        ^{
            lobby.present(alert, animated: true, completion: nil)
        }

        return { [unowned self] (msg: Actor.Message) in
            switch (msg) {

            case let t as UICmd.OnPicture:

                if let imageData = t.pic {
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
                ^{
                    alert.dismiss(animated: true, completion: nil)
                }

                self.sendMessage(peer: [peer], msg: RemoteCmd.TakePicAck(sender: self.this))

                let result = self.sendMessage(peer: [peer], msg: RemoteCmd.TakePicResp(sender: self.this, pic: t.pic, error: t.error))

                if let failure = result as? Failure {
                    ^{
                        let a = UIAlertController(title: "Error sending picture",
                                message: failure.error.debugDescription,
                                preferredStyle: .alert)

                        a.addAction(UIAlertAction(title: "Ok", style: .cancel) { (action) in
                            a.dismiss(animated: true, completion: nil)
                        })

                        ctrl.present(a, animated: true, completion: nil)
                    }
                }

                self.unbecome()

            case let c as DisconnectPeer:
                ^{
                    alert.dismiss(animated: true, completion: nil)
                }
                if (c.peer.displayName == peer.displayName) {
                    self.popAndStartScanning()
                }

            case is Disconnect:
                ^{
                    alert.dismiss(animated: true, completion: nil)
                }
                self.popAndStartScanning()

            case is UICmd.UnbecomeCamera:
                ^{
                    alert.dismiss(animated: true, completion: nil)
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
                self.sendMessage(peer: [peer], msg: RemoteCmd.ToggleCameraResp(flashMode: m.flashMode, camPosition: m.camPosition, error: nil))

            case let s as RemoteCmd.SendFrame:
                self.sendMessage(peer: [peer], msg: s, mode: .unreliable)

            case is RemoteCmd.TakePic:
                ^{
                    ctrl.takePicture()
                }
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
                self.sendMessage(peer: [peer], msg: resp!)

            case is RemoteCmd.ToggleFlash:
                let result = ctrl.toggleFlash()
                var resp: Message?
                if let flashMode = result.toOptional() {
                    resp = RemoteCmd.ToggleFlashResp(flashMode: flashMode, error: nil)
                } else if let failure = result as? Failure {
                    resp = RemoteCmd.ToggleFlashResp(flashMode: nil, error: failure.error)
                }
                self.sendMessage(peer: [peer], msg: resp!)

            case is UICmd.UnbecomeCamera:
                self.popToState(name: self.states.connected)

            case let c as DisconnectPeer:
                if (c.peer.displayName == peer.displayName) {
                    self.popAndStartScanning()
                }

            case is Disconnect:
                self.popAndStartScanning()

            default:
                self.receive(msg: msg)
            }
        }
    }

    private func handlePhotoSaveError() {
        print("Failed to save photo")
    }

}
