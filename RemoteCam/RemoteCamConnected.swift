//
//  RemoteCamConnected.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 10/11/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import Theater
import MultipeerConnectivity

extension RemoteCamSession {

    func connected(lobby: RolePickerController,
                   peer: MCPeerID) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter:
                ^ {
                    lobby.navigationItem.rightBarButtonItem?.title = lobby.states.disconnect
                    lobby.navigationItem.prompt = lobby.connectedPrompt
                    lobby.remote.alpha = 1
                    lobby.camera.alpha = 1
                    lobby.remote.isEnabled = true
                    lobby.camera.isEnabled = true
                    lobby.instructionLabel.text = lobby.connectedInstructionsLabel
                }

            case let m as UICmd.BecomeCamera:
                self.become(name: self.states.camera, state: self.camera(peer: peer, ctrl: m.ctrl, lobby: lobby))
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.PeerBecameCamera())

            case let m as UICmd.BecomeMonitor:
                switch m.mode {
                case .Video:
                    self.become(
                        name: self.states.monitor,
                        state: self.monitorVideoMode(monitor: m.sender!, peer: peer, lobby: lobby))
                default:
                    self.become(
                        name: self.states.monitor,
                        state: self.monitorPhotoMode(monitor: m.sender!, peer: peer, lobby: lobby))
                }

                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.PeerBecameMonitor())

            case is RemoteCmd.PeerBecameCamera:
                ^ {
                    lobby.becomeMonitor()
                }

            case is RemoteCmd.PeerBecameMonitor:
                ^ {
                    lobby.becomeCamera()
                }

            case is UICmd.ToggleConnect,
                 is Disconnect:
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
}
