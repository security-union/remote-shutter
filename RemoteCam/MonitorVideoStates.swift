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
                // Immediately transition to waiting state after sending stop command
                self.become(
                    name: self.states.monitorWaitingForVideo,
                    state: self.monitorWaitingForVideo(monitor: monitor, peer: peer, lobby: lobby)
                )

            case is RemoteCmd.StopRecordingVideoAck:
                // Legacy handler - should not be used with FlatBuffers
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
                
                // Handle FlatBuffers response directly without legacy conversion
                if fbResponse.response.success {
                    // Extract media data from FlatBuffers response
                    if let mediaData = fbResponse.response.mediaData {
                        let videoData = Data(mediaData.data)
                        print("🔍 DEBUG: Extracted video data: \(videoData.count) bytes")
                        print("🔍 DEBUG: Media data type: \(mediaData.type)")
                        
                        // Save video directly without legacy conversion
                        saveVideoDataWithCompletion(videoData) { [weak self] in
                            // Transition back to video mode after saving is complete
                            ^{alert?.dismiss(animated: true)}
                            guard let self = self else { return }
                            self.become(
                                name: self.states.monitorVideoMode,
                                state: self.monitorVideoMode(monitor: monitor, peer: peer, lobby: lobby)
                            )
                        }
                    } else {
                        print("🔍 DEBUG: No media data found in FlatBuffers response")
                        ^{alert?.dismiss(animated: true)}
                        showError("No video data received")
                        self.become(
                            name: self.states.monitorVideoMode,
                            state: self.monitorVideoMode(monitor: monitor, peer: peer, lobby: lobby)
                        )
                    }
                } else {
                    // Handle error case
                    let errorMessage = fbResponse.response.error ?? "Unknown video recording error"
                    print("🔍 DEBUG: Video recording failed: \(errorMessage)")
                    ^{alert?.dismiss(animated: true)}
                    showError(errorMessage)
                    self.become(
                        name: self.states.monitorVideoMode,
                        state: self.monitorVideoMode(monitor: monitor, peer: peer, lobby: lobby)
                    )
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
        saveVideoData(video)
    }
    
    func saveVideoData(_ videoData: Data) {
        saveVideoDataWithCompletion(videoData) { }
    }
    
    func saveVideoDataWithCompletion(_ videoData: Data, completion: @escaping () -> Void) {
        print("🔍 DEBUG: Saving video to monitor with \(videoData.count) bytes")
        PHPhotoLibrary.requestAuthorization { status in
            print("🔍 DEBUG: Video library authorization status: \(status.rawValue)")
            if status == .authorized {
                // 1. Save inbound video to a temp file.
                let fileURL = URL(fileURLWithPath: NSTemporaryDirectory(),
                        isDirectory: true).appendingPathComponent(tempFile)
                cleanupFileAt(fileURL)
                do {
                    _ = try videoData.write(to: fileURL, options: .atomic)
                    print("🔍 DEBUG: Video written to temp file: \(fileURL)")
                } catch {
                    print("🔍 DEBUG: Failed to write video to temp file: \(error)")
                    showError(NSLocalizedString("Unable to save video", comment: ""))
                    DispatchQueue.main.async {
                        completion()
                    }
                    return
                }

                // 2. Save the movie file to the camera roll.
                PHPhotoLibrary.shared().performChanges({
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = true
                    PHAssetCreationRequest.forAsset()
                        .addResource(with: .video, fileURL: fileURL, options: options)
                    print("🔍 DEBUG: Video asset creation request created")
                }, completionHandler: { success, error in

                    // 3. If saving fails, then show an error.
                    if !success {
                        print("🔍 DEBUG: Failed to save video to Photos app! Error: \(error?.localizedDescription ?? "Unknown error")")
                        showError(NSLocalizedString("Unable to save video to Photos app", comment: ""))
                    } else {
                        print("🔍 DEBUG: Successfully saved video to Photos app!")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            showReviewPromptIfAppropriate()
                        }
                    }

                    // 4. Delete temp file.
                    cleanupFileAt(fileURL)
                    
                    // 5. Call completion handler on main thread
                    DispatchQueue.main.async {
                        completion()
                    }
                })
            } else {
                print("🔍 DEBUG: Video library access not authorized")
                showError(NSLocalizedString("Remote Shutter has not access to the camera roll", comment: ""))
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }
}
