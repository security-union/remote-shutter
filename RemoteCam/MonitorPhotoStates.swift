//
//  MonitorPhotoStates.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 10/11/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import Theater
import MultipeerConnectivity
import Photos

extension RemoteCamSession {
    func monitorPhotoMode(monitor: ActorRef,
                 peer: MCPeerID,
                 lobby: RolePickerController) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch (msg) {
            case is OnEnter:
                monitor ! UICmd.RenderPhotoMode()
                
            case is RemoteCmd.OnFrame:
                monitor ! msg

            case is UICmd.UnbecomeMonitor:
                self.popToState(name: self.states.connected)

            case is UICmd.ToggleCamera:
                self.become(
                    name: self.states.monitorTogglingCamera,
                    state: self.monitorTogglingCamera(monitor: monitor, peer: peer, lobby: lobby)
                )
                self.this ! msg

            case is UICmd.ToggleFlash:
                self.become(
                    name: self.states.monitorTogglingFlash,
                    state: self.monitorTogglingFlash(monitor: monitor, peer: peer, lobby: lobby)
                )
                self.this ! msg

            case is UICmd.TakePicture:
                self.become(name: self.states.monitorTakingPicture, state:
                self.monitorTakingPicture(monitor: monitor, peer: peer, lobby: lobby))
                self.this ! msg
                
            case let mode as UICmd.BecomeMonitor:
                if mode.mode == RecordingMode.Video {
                    self.become(name: states.monitorVideoMode,
                                state: self.monitorVideoMode(monitor: monitor, peer: peer, lobby: lobby),
                                discardOld: true)
                }

            case is Disconnect:
                self.popAndStartScanning()
                
            case let c as DisconnectPeer:
                if c.peer.displayName == peer.displayName && self.session.connectedPeers.count == 0 {
                    self.popAndStartScanning()
                }

            default:
                self.receive(msg: msg)
            }
        }
    }
    
    func monitorTakingPicture(monitor: ActorRef,
                              peer: MCPeerID,
                              lobby: RolePickerController) -> Receive {
        var alert: UIAlertController?
        ^{
            alert = UIAlertController(title: "Requesting picture",
                message: nil,
                preferredStyle: .alert)
        }
        return { [unowned self] (msg: Actor.Message) in
            switch (msg) {

            case is RemoteCmd.TakePicAck:
                ^{alert?.title = "Receiving picture"}
                self.sendCommandOrGoToScanning(peer: [peer], msg: msg)

            case is UICmd.TakePicture:
                ^{alert?.show(true) {
                    mailbox.addOperation {
                        self.sendCommandOrGoToScanning(
                            peer: [peer],
                            msg: RemoteCmd.TakePic(sender: self.this)
                        )
                    }
                }}

            case let picResp as RemoteCmd.TakePicResp:
                if let imageData = picResp.pic {
                    savePicture(imageData)
                    ^{alert?.dismiss(animated: true)}
                } else if let error = picResp.error {
                    ^{alert?.dismiss(animated: true) { () in
                        let error = UIAlertController(title: error._domain, message: nil, preferredStyle: .alert)
                        error.simpleOkAction()
                        error.show(true)
                    }}
                }
                self.unbecome()

            case is UICmd.UnbecomeMonitor:
                ^{alert?.dismiss(animated: true){
                    mailbox.addOperation {
                        self.popToState(name: self.states.connected)
                    }
                }}
                

            case let c as DisconnectPeer:
                if c.peer.displayName == peer.displayName && self.session.connectedPeers.count == 0 {
                    ^{alert?.dismiss(animated: true) {
                        mailbox.addOperation {
                            self.popAndStartScanning()
                        }
                    }}
                }

            case is Disconnect:
                ^{alert?.dismiss(animated: true){
                    mailbox.addOperation {
                        self.popAndStartScanning()
                    }
                }}

            default:
                ^{alert?.dismiss(animated: true, completion: nil)}
                print("ignoring message")
            }
        }
    }
    
}
