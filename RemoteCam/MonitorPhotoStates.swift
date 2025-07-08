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
                 lobby: Weak<DeviceScannerViewController>) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter:
                monitor ! UICmd.RenderPhotoMode()
                self.requestFrame([peer])

            case is RemoteCmd.OnFrame:
                monitor ! msg
                self.requestFrame([peer])

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
                
            // MARK: - Zoom and Lens Command Handling
            case let zoomCmd as UICmd.SetZoom:
                // Send zoom command directly without showing alert for immediate feedback
                if let f = self.sendMessage(
                    peer: [peer], msg: RemoteCmd.SetZoom(zoomFactor: zoomCmd.zoomFactor)) as? Failure {
                    print("❌ DEBUG: Failed to send zoom command: \(f.tryError.localizedDescription)")
                }
                
            case let zoomResp as RemoteCmd.SetZoomResp:
                // Handle zoom response directly without alert
                if let error = zoomResp.error {
                    print("❌ DEBUG: Zoom response error: \(error.localizedDescription)")
                }
                monitor ! zoomResp
                
            case is UICmd.SwitchLens:
                self.become(
                    name: self.states.monitorSwitchingLens,
                    state: self.monitorSwitchingLens(monitor: monitor, peer: peer, lobby: lobby)
                )
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
                              lobby: Weak<DeviceScannerViewController>) -> Receive {
        var alert: UIAlertController?
        ^{
            alert = UIAlertController(title: "Requesting picture",
                message: nil,
                preferredStyle: .alert)
        }
        return { [unowned self] (msg: Actor.Message) in
            switch msg {

            case is RemoteCmd.TakePicAck:
                ^{alert?.title = "Receiving picture"}
                self.sendCommandOrGoToScanning(peer: [peer], msg: msg)

            case let cmd as UICmd.TakePicture:
                ^{alert?.show(true) {
                    self.mailbox.addOperation(BlockOperation {
                        self.sendCommandOrGoToScanning(
                            peer: [peer],
                            msg: RemoteCmd.TakePic(sender: self.this, sendMediaToPeer:cmd.sendMediaToRemote)
                        )
                    })
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
                ^{alert?.dismiss(animated: true) {
                    self.mailbox.addOperation(BlockOperation {
                        self.popToState(name: self.states.connected)
                    })
                }}

            case let c as DisconnectPeer:
                if c.peer.displayName == peer.displayName && self.session.connectedPeers.count == 0 {
                    ^{alert?.dismiss(animated: true) {
                        self.mailbox.addOperation(BlockOperation {
                            self.popAndStartScanning()
                        })
                    }}
                }

            case is Disconnect:
                ^{alert?.dismiss(animated: true) {
                    self.mailbox.addOperation(BlockOperation {
                        self.popAndStartScanning()
                    })
                }}

            default:
                ^{alert?.dismiss(animated: true, completion: nil)}
                print("ignoring message")
            }
        }
    }

}
