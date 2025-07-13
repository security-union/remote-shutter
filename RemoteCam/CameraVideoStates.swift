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
                // FrameSender no longer needed - frames are sent directly from CameraViewController
                break



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

            case let fbCommand as FlatBuffersCameraCommand:
                // Handle FlatBuffers commands while recording video
                print("🎯 Camera shooting video received FlatBuffers command: \(fbCommand.command.action)")
                
                switch fbCommand.command.action {
                case .stoprecording:
                    print("🛑 Camera shooting video handling FlatBuffers stop recording")
                    let sendToRemote = fbCommand.command.parameters?.sendToRemote ?? true
                    
                    // Trigger video recording stop
                    ctrl.stopRecordingVideo(sendToRemote)
                    
                    // Transition to video transmitting state to wait for video data
                    self.become(
                        name: self.states.cameraTransmittingVideo,
                        state: self.cameraTransmittingVideo(peer: peer, ctrl: ctrl, lobby: lobby, commandId: fbCommand.command.id)
                    )
                    
                default:
                    print("⚠️ Camera shooting video received unhandled FlatBuffers command: \(fbCommand.command.action)")
                }

            default:
                self.receive(msg: msg)
            }
        }
    }

    func cameraTransmittingVideo(peer: MCPeerID,
                             ctrl: CameraViewController,
                             lobby: Weak<DeviceScannerViewController>,
                             commandId: String? = nil) -> Receive {
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
            case let c as UICmd.OnVideo:
                // Send FlatBuffers response with correct command ID
                print("🎬 DEBUG: Camera sending FlatBuffers video recording response")
                print("🎬 DEBUG: Video data size: \(c.video?.count ?? 0) bytes")
                print("🎬 DEBUG: Error: \(c.error?.localizedDescription ?? "none")")
                
                let _ = self.sendFlatBuffersVideoRecordingResponse(
                    peer: [peer],
                    commandId: commandId ?? UUID().uuidString,
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
