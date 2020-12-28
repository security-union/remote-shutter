//
//  SessionMonitorStates.swift
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
    
    func requestFrame(_ peer : [MCPeerID]) {
        self.sendCommandOrGoToScanning(peer: peer, msg: RemoteCmd.RequestFrame(sender: self.this))
    }
    
    func monitorTogglingFlash(monitor: ActorRef,
                              peer: MCPeerID,
                              lobby: Weak<DeviceScannerViewController>) -> Receive {
        var alert: UIAlertController?
        ^{
        alert = UIAlertController(title: "Requesting flash toggle",
                message: nil,
                preferredStyle: .alert)
        }
        return { [unowned self] (msg: Actor.Message) in
            switch msg {

            case is UICmd.ToggleFlash:
                ^{
                    alert?.show(true) {
                        mailbox.addOperation {
                            if let f = self.sendMessage(peer: [peer], msg: RemoteCmd.ToggleFlash()) as? Failure {
                                self.this ! RemoteCmd.ToggleFlashResp(flashMode: nil, error: f.error)
                            }
                        }
                    }
                }

            case let t as RemoteCmd.ToggleFlashResp:
                if let _ = t.flashMode {
                    monitor ! t
                    ^{
                        alert?.dismiss(animated: true) {
                            mailbox.addOperation {
                                self.unbecome()
                            }
                        }
                    }
                } else if let error = t.error {
                    ^{
                        alert?.dismiss(animated: true) {
                            let errorAlert = UIAlertController(title: error._domain,
                                                               message: nil,
                                                               preferredStyle: .alert)
                            errorAlert.simpleOkAction()
                            errorAlert.show(true)
                            mailbox.addOperation {
                                self.unbecome()
                            }
                        }
                    }
                }

            case let c as DisconnectPeer:
                if c.peer.displayName == peer.displayName && self.session.connectedPeers.count == 0 {
                    ^{
                        alert?.dismiss(animated: true) {
                            mailbox.addOperation {
                                self.popAndStartScanning()
                            }
                        }
                    }
                }

            case is Disconnect:
                ^{
                    alert?.dismiss(animated: true) {
                        mailbox.addOperation {
                            self.popAndStartScanning()
                        }
                    }
                }

            case is UICmd.UnbecomeMonitor:
                ^{
                    alert?.dismiss(animated: true) {
                        mailbox.addOperation {
                            self.popToState(name: self.states.connected)
                        }
                    }
                }

            default:
                print("ignoring message")
            }
        }
    }

    func monitorTogglingCamera(monitor: ActorRef,
                               peer: MCPeerID,
                               lobby: Weak<DeviceScannerViewController>) -> Receive {
        var alert: UIAlertController?
        ^{
            alert = UIAlertController(title: "Requesting camera toggle",
                    message: nil,
                    preferredStyle: .alert)
        }
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is UICmd.ToggleCamera:
                ^{
                    alert?.show(true) {
                        mailbox.addOperation {
                            if let f = self.sendMessage(
                                peer: [peer], msg: RemoteCmd.ToggleCamera()) as? Failure {
                                self.this ! RemoteCmd.ToggleCameraResp(
                                    flashMode: nil, camPosition: nil, error: f.error
                                )
                            }
                        }
                    }
                }
            case let t as RemoteCmd.ToggleCameraResp:
                // TODO: Fix this.
                monitor ! UICmd.ToggleCameraResp(
                    flashMode: t.flashMode,
                    camPosition: t.camPosition, error: t.error)
                ^{
                    if let _ = t.flashMode {
                        alert?.dismiss(animated: true) {
                            mailbox.addOperation {
                                self.unbecome()
                            }
                        }
                    } else if let error = t.error {
                        alert?.dismiss(animated: true, completion: {
                            let errorAlert = UIAlertController(title: error._domain, message: nil, preferredStyle: .alert)
                            errorAlert.simpleOkAction()
                            errorAlert.show(true)
                            mailbox.addOperation {
                                self.unbecome()
                            }
                        })
                    }
                }

            case let c as DisconnectPeer:
                if c.peer.displayName == peer.displayName && self.session.connectedPeers.count == 0 {
                    ^{
                        alert?.dismiss(animated: true) {
                            mailbox.addOperation {
                                self.popAndStartScanning()
                            }
                        }
                    }
                }

            case is Disconnect:
                ^{
                    alert?.dismiss(animated: true) {
                        mailbox.addOperation {
                            self.popAndStartScanning()
                        }
                    }
                }

            case is UICmd.UnbecomeMonitor:
                ^{
                    alert?.dismiss(animated: true) {
                        mailbox.addOperation {
                            self.popToState(name: self.states.connected)
                        }
                    }
                }

            default:
                print("ignoring message")
            }
        }
    }
}
