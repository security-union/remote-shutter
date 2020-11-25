//
//  MonitorVideoStates.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 10/10/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import Theater
import MultipeerConnectivity
import Photos

private typealias MonitorVideoStates = RemoteCamSession

extension MonitorVideoStates {
    func monitorVideoMode(monitor: ActorRef,
                 peer: MCPeerID,
                 lobby: RolePickerController) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter:
                monitor ! UICmd.RenderVideoMode()
                self.requestFrame([peer])

            case is RemoteCmd.OnFrame:
                monitor ! msg
                self.requestFrame([peer])

            case is UICmd.UnbecomeMonitor:
                self.popToState(name: self.states.connected)

            case let mode as UICmd.BecomeMonitor:
                if mode.mode == RecordingMode.Photo {
                    self.become(name: states.monitorPhotoMode,
                                state: self.monitorPhotoMode(monitor: monitor, peer: peer, lobby: lobby),
                                discardOld: true)
                }

            case is UICmd.TakePicture:
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.StartRecordingVideo(sender: self.this))
                self.become(
                    name: self.states.monitorRecordingVideo,
                    state: self.monitorRecordingVideo(monitor: monitor, peer: peer, lobby: lobby)
                )

            case is UICmd.ToggleCamera:
                self.become(name: self.states.monitorTogglingCamera, state:
                self.monitorTogglingCamera(monitor: monitor, peer: peer, lobby: lobby))
                self.this ! msg

            case let c as DisconnectPeer:
                if c.peer.displayName == peer.displayName && self.session.connectedPeers.count == 0 {
                    self.popAndStartScanning()
                }

            case is Disconnect:
                self.popAndStartScanning()

            default:
                self.receive(msg: msg)
            }
        }
    }

    func monitorRecordingVideo(monitor: ActorRef,
                               peer: MCPeerID,
                               lobby: RolePickerController) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter:
                monitor ! UICmd.RenderVideoModeRecording()
                self.requestFrame([peer])

            case is RemoteCmd.OnFrame:
                monitor ! msg
                self.requestFrame([peer])

            case is UICmd.TakePicture:
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.StopRecordingVideo(sender: self.this))

            case is RemoteCmd.StopRecordingVideoAck:
                self.become(
                    name: self.states.monitorWaitingForVideo,
                    state: self.monitorWaitingForVideo(monitor: monitor, peer: peer, lobby: lobby)
                )
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

    func monitorWaitingForVideo(monitor: ActorRef,
                               peer: MCPeerID,
                               lobby: RolePickerController) -> Receive {
        var alert: UIAlertController?
        ^{
            alert = UIAlertController(title: "Waiting for video file...",
                    message: nil,
                    preferredStyle: .alert)
        }
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter:
                ^{alert?.show(true)}

            case let w as RemoteCmd.StopRecordingVideoResp:
                ^{alert?.title = "Saving video..."}
                saveVideo(w)
                ^{alert?.dismiss(animated: true)}
                self.popToState(name: self.states.monitorVideoMode)

            case is Disconnect:
                ^{alert?.dismiss(animated: true)}
                self.popAndStartScanning()

            case let c as DisconnectPeer:
                if c.peer.displayName == peer.displayName && self.session.connectedPeers.count == 0 {
                    ^{alert?.dismiss(animated: true)}
                    self.popAndStartScanning()
                }

            default:
                ^{alert?.dismiss(animated: true)}
                self.receive(msg: msg)
            }
        }
    }

    func saveVideo(_ videoResp: RemoteCmd.StopRecordingVideoResp) {
        if let error = videoResp.error {
            showError(error.localizedDescription)
        }
        guard let video = videoResp.video else {
            return
        }
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                // 1. Save inbound video to a temp file.
                let fileURL = URL(fileURLWithPath: NSTemporaryDirectory(),
                        isDirectory: true).appendingPathComponent(tempFile)
                cleanupFileAt(fileURL)
                do {
                    _ = try video.write(to: fileURL, options: .atomic)
                } catch {
                    showError(NSLocalizedString("Unable to save video", comment: ""))
                    return
                }

                // 2. Save the movie file to the camera roll.
                PHPhotoLibrary.shared().performChanges({
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = true
                    PHAssetCreationRequest.forAsset()
                        .addResource(with: .video, fileURL: fileURL, options: options)
                }, completionHandler: { success, _ in

                    // 3. If saving fails, then show an error.
                    if !success {
                        showError(NSLocalizedString("Unable to save video to Photos app", comment: ""))
                    }

                    // 4. Delete temp file.
                    cleanupFileAt(fileURL)
                })
            } else {
                showError(NSLocalizedString("Remote Shutter has not access to the camera roll", comment: ""))
            }
        }
    }
}
