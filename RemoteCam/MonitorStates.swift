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
                        self.mailbox.addOperation {
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
                            self.mailbox.addOperation {
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
                            self.mailbox.addOperation {
                                self.unbecome()
                            }
                        }
                    }
                }

            case let c as DisconnectPeer:
                if c.peer.displayName == peer.displayName && self.session.connectedPeers.count == 0 {
                    ^{
                        alert?.dismiss(animated: true) {
                            self.mailbox.addOperation {
                                self.popAndStartScanning()
                            }
                        }
                    }
                }

            case is Disconnect:
                ^{
                    alert?.dismiss(animated: true) {
                        self.mailbox.addOperation {
                            self.popAndStartScanning()
                        }
                    }
                }

            case is UICmd.UnbecomeMonitor:
                ^{
                    alert?.dismiss(animated: true) {
                        self.mailbox.addOperation {
                            self.popToState(name: self.states.connected)
                        }
                    }
                }

            default:
                print("ignoring message")
            }
        }
    }
    
    // MARK: - Zoom Setting State
    func monitorSettingZoom(monitor: ActorRef,
                           peer: MCPeerID,
                           lobby: Weak<DeviceScannerViewController>) -> Receive {
        var alert: UIAlertController?
        ^{
            alert = UIAlertController(title: "Setting zoom",
                    message: nil,
                    preferredStyle: .alert)
        }
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case let zoomCmd as UICmd.SetZoom:
                ^{
                    alert?.show(true) {
                        self.mailbox.addOperation {
                            if let f = self.sendMessage(
                                peer: [peer], msg: RemoteCmd.SetZoom(zoomFactor: zoomCmd.zoomFactor)) as? Failure {
                                self.this ! RemoteCmd.SetZoomResp(zoomFactor: nil, error: f.error)
                            }
                        }
                    }
                }
                
            case let zoomResp as RemoteCmd.SetZoomResp:
                ^{
                    alert?.dismiss(animated: true) {
                        self.mailbox.addOperation {
                            monitor ! zoomResp
                            self.popToState(name: self.states.monitorPhotoMode)
                        }
                    }
                }
                
            case let c as DisconnectPeer:
                ^{
                    alert?.dismiss(animated: true)
                    if c.peer.displayName == peer.displayName && self.session.connectedPeers.count == 0 {
                        self.mailbox.addOperation {
                            self.popAndStartScanning()
                        }
                    }
                }
                
            case is UICmd.UnbecomeMonitor:
                ^{
                    alert?.dismiss(animated: true) {
                        self.mailbox.addOperation {
                            self.popToState(name: self.states.connected)
                        }
                    }
                }
                
            default:
                print("ignoring zoom message")
            }
        }
    }
    
    // MARK: - Lens Switching State
    func monitorSwitchingLens(monitor: ActorRef,
                             peer: MCPeerID,
                             lobby: Weak<DeviceScannerViewController>) -> Receive {
        var alert: UIAlertController?
        ^{
            alert = UIAlertController(title: "Switching lens",
                    message: nil,
                    preferredStyle: .alert)
        }
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case let lensCmd as UICmd.SwitchLens:
                ^{
                    alert?.show(true) {
                        self.mailbox.addOperation {
                            if let f = self.sendMessage(
                                peer: [peer], msg: RemoteCmd.SwitchLens(lensType: lensCmd.lensType)) as? Failure {
                                self.this ! RemoteCmd.SwitchLensResp(lensType: nil, availableLenses: nil, error: f.error)
                            }
                        }
                    }
                }
                
            case let lensResp as RemoteCmd.SwitchLensResp:
                ^{
                    alert?.dismiss(animated: true) {
                        self.mailbox.addOperation {
                            monitor ! lensResp
                            self.popToState(name: self.states.monitorPhotoMode)
                        }
                    }
                }
                
            case let c as DisconnectPeer:
                ^{
                    alert?.dismiss(animated: true)
                    if c.peer.displayName == peer.displayName && self.session.connectedPeers.count == 0 {
                        self.mailbox.addOperation {
                            self.popAndStartScanning()
                        }
                    }
                }
                
            case is UICmd.UnbecomeMonitor:
                ^{
                    alert?.dismiss(animated: true) {
                        self.mailbox.addOperation {
                            self.popToState(name: self.states.connected)
                        }
                    }
                }
                
            default:
                print("ignoring lens message")
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
                        self.mailbox.addOperation {
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
                            self.mailbox.addOperation {
                                self.unbecome()
                            }
                        }
                    } else if let error = t.error {
                        alert?.dismiss(animated: true, completion: {
                            let errorAlert = UIAlertController(title: error._domain, message: nil, preferredStyle: .alert)
                            errorAlert.simpleOkAction()
                            errorAlert.show(true)
                            self.mailbox.addOperation {
                                self.unbecome()
                            }
                        })
                    }
                }

            case let c as DisconnectPeer:
                if c.peer.displayName == peer.displayName && self.session.connectedPeers.count == 0 {
                    ^{
                        alert?.dismiss(animated: true) {
                            self.mailbox.addOperation {
                                self.popAndStartScanning()
                            }
                        }
                    }
                }

            case is Disconnect:
                ^{
                    alert?.dismiss(animated: true) {
                        self.mailbox.addOperation {
                            self.popAndStartScanning()
                        }
                    }
                }

            case is UICmd.UnbecomeMonitor:
                ^{
                    alert?.dismiss(animated: true) {
                        self.mailbox.addOperation {
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
