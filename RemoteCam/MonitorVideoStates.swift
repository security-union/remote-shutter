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
import StoreKit

private typealias MonitorVideoStates = RemoteCamSession

extension MonitorVideoStates {
    func monitorVideoMode(monitor: ActorRef,
                 peer: MCPeerID,
                 lobby: Weak<DeviceScannerViewController>) -> Receive {
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
                self.sendFlatBuffersStartRecording(peer: [peer])
                self.become(
                    name: self.states.monitorRecordingVideo,
                    state: self.monitorRecordingVideo(monitor: monitor, peer: peer, lobby: lobby)
                )

            case is UICmd.ToggleCamera:
                self.become(name: self.states.monitorTogglingCamera, state:
                self.monitorTogglingCamera(monitor: monitor, peer: peer, lobby: lobby))
                self.this ! msg

            case is UICmd.ToggleTorch:
                // Handle torch toggle directly in video mode using FlatBuffers
                print("🔍 DEBUG: Video mode - attempting FlatBuffers torch toggle")
                if let f = self.sendFlatBuffersTorchToggle(peer: [peer]) as? Failure {
                    print("❌ DEBUG: Failed to send FlatBuffers torch toggle command in video mode: \(f.tryError.localizedDescription)")
                } else {
                    print("✅ DEBUG: Successfully sent FlatBuffers torch toggle command in video mode")
                }
                
            // MARK: - Camera Capabilities Handling
            case let capabilities as RemoteCmd.CameraCapabilitiesResp:
                print("🔍 DEBUG: Monitor video mode received camera capabilities")
                if let cameraInfo = capabilities.getCurrentCameraInfo() {
                    print("🔍 DEBUG: Video mode available lenses: \(cameraInfo.availableLenses)")
                }
                monitor ! capabilities
                
            // MARK: - FlatBuffers Message Handling
            case let fbCommand as FlatBuffersCameraCommand:
                print("🔍 DEBUG: Monitor video mode received FlatBuffers camera command: \(fbCommand.command.action)")
                // FlatBuffers commands are handled by the camera, not the monitor
                // This case is here for completeness but shouldn't normally occur
                
            case let fbResponse as FlatBuffersCameraStateResponse:
                print("🔍 DEBUG: Monitor video mode received FlatBuffers camera state response")
                print("🔍 DEBUG: Command success: \(fbResponse.response.success)")
                if let error = fbResponse.response.error {
                    print("🔍 DEBUG: Command error: \(error)")
                }
                
                // Convert FlatBuffers response to legacy format based on command type
                // For now, we'll forward FlatBuffers responses to the monitor for UI updates
                // In the future, we could implement more sophisticated state-based routing
                monitor ! fbResponse
                print("🔍 DEBUG: Forwarded FlatBuffers state update to monitor in video mode")
                
            // MARK: - Zoom and Lens Command Handling
            case let zoomCmd as UICmd.SetZoom:
                // Send zoom command directly without showing alert for immediate feedback
                if let f = self.sendMessage(
                    peer: [peer], msg: RemoteCmd.SetZoom(zoomFactor: zoomCmd.zoomFactor)) as? Failure {
                    print("❌ DEBUG: Failed to send zoom command in video mode: \(f.tryError.localizedDescription)")
                }
                
            case let zoomResp as RemoteCmd.SetZoomResp:
                // Handle zoom response directly without alert
                if let error = zoomResp.error {
                    print("❌ DEBUG: Video mode zoom response error: \(error.localizedDescription)")
                }
                monitor ! zoomResp
                
            case let torchResp as RemoteCmd.ToggleTorchResp:
                // Handle torch response directly without alert
                if let error = torchResp.error {
                    print("❌ DEBUG: Video mode torch response error: \(error.localizedDescription)")
                }
                monitor ! torchResp
                
            case is UICmd.SwitchLens:
                self.become(
                    name: self.states.monitorSwitchingLens,
                    state: self.monitorSwitchingLens(monitor: monitor, peer: peer, lobby: lobby)
                )
                self.this ! msg
                
            case is UICmd.RequestCameraCapabilities:
                // Request capabilities from camera
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.RequestCameraCapabilities())
                
            case is RemoteCmd.PeerBecameCamera:
                // When peer becomes camera, request fresh capabilities
                print("🔍 DEBUG: Monitor detected peer became camera - requesting fresh capabilities")
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.RequestCameraCapabilities())

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
                               lobby: Weak<DeviceScannerViewController>) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter:
                monitor ! UICmd.RenderVideoModeRecording()
                self.requestFrame([peer])

            case is RemoteCmd.OnFrame:
                monitor ! msg
                self.requestFrame([peer])

            case let cmd as UICmd.TakePicture:
                self.sendFlatBuffersStopRecording(peer: [peer], sendToRemote: cmd.sendMediaToRemote)

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
                               lobby: Weak<DeviceScannerViewController>) -> Receive {
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

            case let fbResponse as FlatBuffersCameraStateResponse:
                print("🔍 DEBUG: Monitor waiting for video received FlatBuffers camera state response")
                print("🔍 DEBUG: Command success: \(fbResponse.response.success)")
                
                // Convert FlatBuffers response to legacy StopRecordingVideoResp format
                if fbResponse.response.success {
                    // For video recording, we don't have the video data in the state response
                    // The camera should send the video data separately or we need to handle it differently
                    // For now, we'll simulate a successful response without video data
                    let legacyResponse = RemoteCmd.StopRecordingVideoResp(
                        sender: nil, // No sender in FlatBuffers response
                        pic: nil, // Video data not included in state response
                        error: nil
                    )
                    self.this ! legacyResponse
                } else {
                    // Handle error case
                    let error = fbResponse.response.error != nil ? 
                        NSError(domain: "VideoRecordingError", code: 1, userInfo: [NSLocalizedDescriptionKey: fbResponse.response.error!]) : 
                        NSError(domain: "VideoRecordingError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown video recording error"])
                    
                    let legacyResponse = RemoteCmd.StopRecordingVideoResp(
                        sender: nil, // No sender in FlatBuffers response
                        pic: nil,
                        error: error
                    )
                    self.this ! legacyResponse
                }

            default:
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
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            showReviewPromptIfAppropriate()
                        }
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
