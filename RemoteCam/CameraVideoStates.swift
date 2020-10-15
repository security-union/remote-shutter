//
//  CameraVideoStates.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 10/10/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import Theater
import MultipeerConnectivity
import Photos

extension RemoteCamSession {

    func cameraShootingVideo(peer: MCPeerID,
                             ctrl: CameraViewController,
                             lobby: RolePickerController) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch (msg) {

            case is RemoteCmd.StopRecordingVideo:
                ctrl.stopRecordingVideo()
                let ack = RemoteCmd.StopRecordingVideoAck()
                self.sendCommandOrGoToScanning(peer: [peer], msg: ack, mode: .unreliable)
                self.become(
                    name: self.states.cameraTransmittingVideo,
                    state: self.cameraTransmittingVideo(peer: peer, ctrl: ctrl, lobby: lobby)
                )

            case let s as RemoteCmd.SendFrame:
                self.sendCommandOrGoToScanning(peer: [peer], msg: s, mode: .unreliable)

            case let c as DisconnectPeer:
                if c.peer.displayName == peer.displayName && self.session.connectedPeers.count == 0 {
                    self.popAndStartScanning()
                    ctrl.stopRecordingVideo()
                }

            case is Disconnect:
                ctrl.stopRecordingVideo()
                self.popAndStartScanning()

            case is UICmd.UnbecomeCamera:
                ctrl.stopRecordingVideo()
                self.popToState(name: self.states.connected)

            default:
                self.receive(msg: msg)
            }
        }
    }
    
    func cameraTransmittingVideo(peer: MCPeerID,
                             ctrl: CameraViewController,
                             lobby: RolePickerController) -> Receive {
        let alert = UIAlertController(title: "Sending video to Monitor",
                message: nil,
                preferredStyle: .alert)

        return { [unowned self] (msg: Actor.Message) in
            switch (msg) {
            case is OnEnter:
                ^{
                    alert.show(true)
                }
            case let c as RemoteCmd.StopRecordingVideoResp:
                self.sendCommandOrGoToScanning(peer: [peer], msg: c)
                ^{
                    alert.dismiss(animated:true) {
                        mailbox.addOperation {
                            self.popToState(name: self.states.camera)
                        }
                    }
                }
                
            case let c as DisconnectPeer:
                if c.peer.displayName == peer.displayName && self.session.connectedPeers.count == 0 {
                    ^{
                        alert.dismiss(animated:true) {
                            mailbox.addOperation {
                                self.popAndStartScanning()
                            }
                        }
                    }
                }

            case is Disconnect:
                ^{
                    alert.dismiss(animated:true) {
                        mailbox.addOperation {
                            self.popAndStartScanning()
                        }
                    }
                }
                
            default:
                self.receive(msg: msg)
            }
        }
    }
}
