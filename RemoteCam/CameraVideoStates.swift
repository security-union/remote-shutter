//
//  CameraVideoStates.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 10/10/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
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

            case let stop as RemoteCmd.StopRecordingVideo:
                ctrl.stopRecordingVideo(stop.sendMediaToPeer)
                let ack = RemoteCmd.StopRecordingVideoAck()
                self.sendCommandOrGoToScanning(peer: [peer], msg: ack, mode: .reliable)
                self.become(
                    name: self.states.cameraTransmittingVideo,
                    state: self.cameraTransmittingVideo(peer: peer, ctrl: ctrl, lobby: lobby)
                )

            case let c as DisconnectPeer:
                if c.peer?.displayName == peer.displayName && self.connectedPeers.count == 0 {
                    self.popAndStartScanning()
                    ctrl.stopRecordingVideo(false)
                }

            case is Disconnect:
                ctrl.stopRecordingVideo(false)
                self.popAndStartScanning()

            case is UICmd.UnbecomeCamera:
                ctrl.stopRecordingVideo(false)
                self.popToState(name: self.states.connected)
            
            case let micError as UICmd.MicrophoneAccessDenied:
                // Handle microphone access denied during recording
                let ack = RemoteCmd.StopRecordingVideoAck()
                self.sendCommandOrGoToScanning(peer: [peer], msg: ack, mode: .reliable)
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.StopRecordingVideoResp(sender: nil, error: micError.error), mode: .reliable)
                self.popToState(name: self.states.camera)

            default:
                self.receive(msg: msg)
            }
        }
    }

    func cameraTransmittingVideo(peer: MCPeerID,
                             ctrl: CameraViewController,
                             lobby: Weak<DeviceScannerViewController>) -> Receive {
        // Note: Progress UI is now handled by SwiftUI VideoTransferProgressView
        // Camera side progress updates are handled directly via ctrl reference
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter:
                // Progress UI handled by SwiftUI components
                break
                
            // MARK: - Video Transfer Progress Handling
            case let started as UICmd.VideoResourceTransferStarted:
                ctrl.cameraViewModel.startVideoTransfer(totalBytes: started.totalBytes)
                print("📤 DEBUG: Camera state - Video transfer started: \(started.totalBytes) bytes")
                
            case let progress as UICmd.VideoResourceTransferProgress:
                ctrl.cameraViewModel.updateVideoTransferProgress(
                    completedBytes: progress.completedBytes,
                    totalBytes: progress.totalBytes
                )
                ctrl.cameraViewModel.updateVideoTransferSpeed(progress.transferSpeed)
                print("📤 DEBUG: Camera state - Video transfer progress: \(Int(progress.progress * 100))% - Speed: \(String(format: "%.1f", progress.transferSpeed / 1024 / 1024)) MB/s")
                
            case _ as UICmd.VideoResourceTransferCompleted:
                ctrl.cameraViewModel.finishVideoTransfer()
                print("📤 DEBUG: Camera state - Video transfer completed")
                
            case let failed as UICmd.VideoResourceTransferFailed:
                ctrl.cameraViewModel.finishVideoTransfer()
                print("📤 DEBUG: Camera state - Video transfer failed: \(failed.error.localizedDescription)")
                break
            case let c as RemoteCmd.StopRecordingVideoResp:
                self.sendCommandOrGoToScanning(peer: [peer], msg: c)
                // Progress UI handled by SwiftUI - no alert to dismiss
                self.mailbox.addOperation {
                    self.popToState(name: self.states.camera)
                }
                
            case let c as DisconnectPeer:
                if c.peer?.displayName == peer.displayName && self.connectedPeers.count == 0 {
                    // Progress UI handled by SwiftUI - no alert to dismiss
                    self.mailbox.addOperation {
                        self.popAndStartScanning()
                    }
                }

            case is Disconnect:
                // Progress UI handled by SwiftUI - no alert to dismiss
                self.mailbox.addOperation {
                    self.popAndStartScanning()
                }

            default:
                self.receive(msg: msg)
            }
        }
    }
}
