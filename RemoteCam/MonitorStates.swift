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

    func monitorTogglingFlash(monitor: ActorRef,
                              peer: MCPeerID,
                              lobby: RolePickerController) -> Receive {
        let alert = UIAlertController(title: "Requesting flash toggle",
                message: nil,
                preferredStyle: .alert)
        return { [unowned self] (msg: Actor.Message) in
            switch (msg) {

            case is UICmd.ToggleFlash:
                ^{
                    lobby.present(alert, animated: true, completion: {
                        if let f = self.sendMessage(peer: [peer], msg: RemoteCmd.ToggleFlash()) as? Failure {
                            self.this ! RemoteCmd.ToggleFlashResp(flashMode: nil, error: f.error)
                        }
                    })
                }

            case let t as RemoteCmd.ToggleFlashResp:
                monitor ! UICmd.ToggleFlashResp(flashMode: t.flashMode, error: t.error)
                if let _ = t.flashMode {
                    monitor ! t
                    ^{
                        alert.dismiss(animated: true, completion: nil)
                    }
                } else if let error = t.error {
                    ^{
                        alert.dismiss(animated: true, completion: {
                            let a = UIAlertController(title: error._domain, message: nil, preferredStyle: .alert)

                            a.addAction(UIAlertAction(title: "Ok", style: .cancel) { (action) in
                                a.dismiss(animated: true, completion: nil)
                            })

                            lobby.present(a, animated: true, completion: nil)
                        })
                    }
                }
                self.unbecome()

            case let c as DisconnectPeer:
                if c.peer.displayName == peer.displayName {
                    ^{
                        alert.dismiss(animated: true, completion: nil)
                    }
                    self.popAndStartScanning()
                }

            case is Disconnect:
                ^{
                    alert.dismiss(animated: true, completion: nil)
                }
                self.popAndStartScanning()

            case is UICmd.UnbecomeMonitor:
                ^{
                    alert.dismiss(animated: true, completion: nil)
                }
                self.popToState(name: self.states.connected)

            default:
                print("ignoring message")
            }
        }
    }

    func monitorTogglingCamera(monitor: ActorRef,
                               peer: MCPeerID,
                               lobby: RolePickerController) -> Receive {
        let alert = UIAlertController(title: "Requesting camera toggle",
                message: nil,
                preferredStyle: .alert)

        return { [unowned self] (msg: Actor.Message) in
            switch (msg) {

            case is UICmd.ToggleCamera:
                ^{
                    lobby.present(alert, animated: true, completion: {
                        if let f = self.sendMessage(peer: [peer], msg: RemoteCmd.ToggleCamera()) as? Failure {
                            self.this ! RemoteCmd.ToggleCameraResp(flashMode: nil, camPosition: nil, error: f.error)
                        }
                    })
                }

            case let t as RemoteCmd.ToggleCameraResp:
                monitor ! UICmd.ToggleCameraResp(flashMode: t.flashMode, camPosition: t.camPosition, error: t.error)
                if let _ = t.flashMode {
                    ^{
                        alert.dismiss(animated: true, completion: nil)
                    }
                } else if let error = t.error {
                    ^{
                        alert.dismiss(animated: true, completion: {
                            let a = UIAlertController(title: error._domain, message: nil, preferredStyle: .alert)

                            a.addAction(UIAlertAction(title: "Ok", style: .cancel) { (action) in
                                a.dismiss(animated: true, completion: nil)
                            })

                            lobby.present(a, animated: true, completion: nil)
                        })
                    }
                }
                self.unbecome()

            case let c as DisconnectPeer:
                if c.peer.displayName == peer.displayName {
                    ^{
                        alert.dismiss(animated: true, completion: nil)
                    }
                    self.popAndStartScanning()
                }

            case is Disconnect:
                ^{
                    alert.dismiss(animated: true, completion: nil)
                }
                self.popAndStartScanning()

            case is UICmd.UnbecomeMonitor:
                ^{
                    alert.dismiss(animated: true, completion: nil)
                }
                self.popToState(name: self.states.connected)

            default:
                print("ignoring message")
            }
        }
    }

    func monitorTakingPicture(monitor: ActorRef,
                              peer: MCPeerID,
                              lobby: RolePickerController) -> Receive {
        let alert = UIAlertController(title: "Requesting picture",
                message: nil,
                preferredStyle: .alert)
        return { [unowned self] (msg: Actor.Message) in
            switch (msg) {

            case is RemoteCmd.TakePicAck:
                ^{
                    alert.title = "Receiving picture"
                }
                self.sendMessage(peer: [peer], msg: msg)

            case is UICmd.TakePicture:
                ^{
                    lobby.present(alert, animated: true, completion: {
                        self.sendMessage(peer: [peer], msg: RemoteCmd.TakePic(sender: self.this))
                    })
                }

            case let picResp as RemoteCmd.TakePicResp:
                if let imageData = picResp.pic {
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
                    ^{
                        alert.dismiss(animated: true, completion: nil)
                    }
                } else if let error = picResp.error {
                    ^{
                        alert.dismiss(animated: true, completion: { () in
                            let a = UIAlertController(title: error._domain, message: nil, preferredStyle: .alert)

                            a.addAction(UIAlertAction(title: "Ok", style: .cancel) { (action) in
                                a.dismiss(animated: true, completion: nil)
                            })

                            lobby.present(a, animated: true, completion: nil)
                        })
                    }
                }
                self.unbecome()

            case is UICmd.UnbecomeMonitor:
                ^{
                    alert.dismiss(animated: true, completion: nil)
                }
                self.popToState(name: self.states.connected)

            case let c as DisconnectPeer:
                if c.peer.displayName == peer.displayName {
                    ^{
                        alert.dismiss(animated: true, completion: nil)
                    }
                    self.popAndStartScanning()
                }

            case is Disconnect:
                ^{
                    alert.dismiss(animated: true, completion: nil)
                }
                self.popAndStartScanning()

            default:
                ^{
                    alert.dismiss(animated: true, completion: nil)
                }
                print("ignoring message")
            }
        }
    }

    func monitor(monitor: ActorRef,
                 peer: MCPeerID,
                 lobby: RolePickerController) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch (msg) {
            case is RemoteCmd.OnFrame:
                monitor ! msg

            case is UICmd.UnbecomeMonitor:
                self.popToState(name: self.states.connected)

            case let c as DisconnectPeer:
                if c.peer.displayName == peer.displayName {
                    self.popAndStartScanning()
                }

            case is UICmd.ToggleCamera:
                self.become(name: self.states.monitorTogglingCamera, state:
                self.monitorTogglingCamera(monitor: monitor, peer: peer, lobby: lobby))
                self.this ! msg

            case is UICmd.ToggleFlash:
                self.become(name: self.states.monitorTogglingFlash, state:
                self.monitorTogglingFlash(monitor: monitor, peer: peer, lobby: lobby))
                self.this ! msg

            case is UICmd.TakePicture:
                self.become(name: self.states.monitorTakingPicture, state:
                self.monitorTakingPicture(monitor: monitor, peer: peer, lobby: lobby))
                self.this ! msg

            case is Disconnect:
                self.popAndStartScanning()

            default:
                self.receive(msg: msg)
            }
        }
    }
}
