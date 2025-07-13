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
    
    func rolePicker() -> ActorRef? {
        RemoteCamSystem.shared.selectActor(actorPath: "RemoteCam/user/RolePickerActor")
    }

    func connected(lobbyWrapper: Weak<DeviceScannerViewController>,
                   peer: MCPeerID) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            guard let lobby = lobbyWrapper.value else {
                popAndStartScanning()
                return
            }
            switch msg {
            case is OnEnter:
                ^{
                    lobby.stopScanning()
                }

            case let m as UICmd.BecomeCamera:
                self.become(name: self.states.camera, state: self.camera(peer: peer, ctrl: m.ctrl, lobbyWrapper: lobbyWrapper))
                self.sendFlatBuffersPeerBecameCamera(peer: [peer])

            case let m as UICmd.BecomeMonitor:
                switch m.mode {
                case .Video:
                    self.become(
                        name: self.states.monitor,
                        state: self.monitorVideoMode(monitor: m.sender!, peer: peer, lobby: lobbyWrapper))
                default:
                    self.become(
                        name: self.states.monitor,
                        state: self.monitorPhotoMode(monitor: m.sender!, peer: peer, lobby: lobbyWrapper))
                }

                self.sendFlatBuffersPeerBecameMonitor(peer: [peer])

            case let cmd as FlatBuffersPeerBecameCamera:
                // Extract version info from FlatBuffers command
                if let parameters = cmd.command.parameters {
                    let bundleVersion = parameters.bundleVersion
                    if bundleVersion > 0 {
                        if let rolePicker = rolePicker() {
                            rolePicker ! cmd
                        }
                    } else {
                        showIncopatibilityMessage()
                    }
                } else {
                    showIncopatibilityMessage()
                }

            case let cmd as FlatBuffersPeerBecameMonitor:
                // Extract version info from FlatBuffers command
                if let parameters = cmd.command.parameters {
                    let bundleVersion = parameters.bundleVersion
                    if bundleVersion > 0 {
                        if let rolePicker = rolePicker() {
                            rolePicker ! cmd
                        }
                    } else {
                        showIncopatibilityMessage()
                    }
                } else {
                    showIncopatibilityMessage()
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
}
