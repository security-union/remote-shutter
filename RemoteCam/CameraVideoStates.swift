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
                             lobby: Weak<DeviceScannerViewController>) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            
                        case is OnEnter:
                getFrameSender()?.tell(msg: SetSession(peer: peer, session: self))



            case let c as DisconnectPeer:
                if c.peer.displayName == peer.displayName && self.session.connectedPeers.count == 0 {
                    self.popAndStartScanning()
                    ctrl.stopRecordingVideo(false)
                }

            case is Disconnect:
                ctrl.stopRecordingVideo(false)
                self.popAndStartScanning()

            case is UICmd.UnbecomeCamera:
                ctrl.stopRecordingVideo(false)
                self.popToState(name: self.states.connected)

            default:
                self.receive(msg: msg)
            }
        }
    }

    func cameraTransmittingVideo(peer: MCPeerID,
                             ctrl: CameraViewController,
                             lobby: Weak<DeviceScannerViewController>) -> Receive {
        var alert: UIAlertController?
        ^{
        alert = UIAlertController(title: "Sending video to Monitor",
                message: nil,
                preferredStyle: .alert)
        }
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter:
                ^{
                    alert?.show(true)
                }
            case let c as RemoteCmd.StopRecordingVideoResp:
                // Send FlatBuffers response
                let _ = self.sendFlatBuffersVideoRecordingResponse(
                    peer: [peer],
                    commandId: UUID().uuidString,
                    videoData: c.video,
                    error: c.error
                )
                
                ^{
                    alert?.dismiss(animated: true) {
                        self.mailbox.addOperation {
                            self.popToState(name: self.states.camera)
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

            default:
                self.receive(msg: msg)
            }
        }
    }
}
