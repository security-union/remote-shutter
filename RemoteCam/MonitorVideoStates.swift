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
                print("🔍 DEBUG: Entering monitorVideoMode - sending RenderVideoMode and requesting frame")
                monitor ! UICmd.RenderVideoMode()
                self.requestFrame([peer])
                print("🔍 DEBUG: monitorVideoMode OnEnter completed")

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

            case is UICmd.FlatBuffersCameraToggle:
                self.become(name: self.states.monitorTogglingCamera, state:
                self.monitorTogglingCamera(monitor: monitor, peer: peer, lobby: lobby))
                self.this ! msg

            case is UICmd.FlatBuffersTorchToggle:
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
                
            case let fbFrameData as FlatBuffersFrameData:
                // Handle FlatBuffers frame data - send directly to monitor
                monitor ! fbFrameData
                self.requestFrame([peer])
                
            // MARK: - Zoom and Lens Command Handling (FlatBuffers)
            case let zoomCmd as UICmd.SetZoom:
                // Send FlatBuffers zoom command directly without showing alert for immediate feedback
                self.sendFlatBuffersSetZoom(peer: [peer], zoomFactor: zoomCmd.zoomFactor)
                
            case let fbZoomCmd as UICmd.FlatBuffersSetZoom:
                // Send FlatBuffers zoom command directly without showing alert for immediate feedback
                self.sendFlatBuffersSetZoom(peer: [peer], zoomFactor: fbZoomCmd.zoomFactor)
                
            case let fbResponse as FlatBuffersCameraStateResponse:
                // Handle FlatBuffers camera state response - forward all responses to monitor
                print("🔍 DEBUG: Video mode received FlatBuffers camera state response")
                if fbResponse.response.success {
                    print("✅ DEBUG: Video mode received successful FlatBuffers response")
                } else {
                    print("❌ DEBUG: Video mode FlatBuffers response error: \(fbResponse.response.error ?? "Unknown error")")
                }
                monitor ! fbResponse
                
            case is UICmd.SwitchLens:
                self.become(
                    name: self.states.monitorSwitchingLens,
                    state: self.monitorSwitchingLens(monitor: monitor, peer: peer, lobby: lobby)
                )
                self.this ! msg
                
            case is UICmd.RequestCameraCapabilities:
                // Request capabilities from camera
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.RequestCameraCapabilities())
                
            case is FlatBuffersPeerBecameCamera:
                // When peer becomes camera, request fresh capabilities
                print("🔍 DEBUG: Monitor detected FlatBuffers peer became camera - requesting fresh capabilities")
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

            case let cmd as UICmd.TakePicture:
                self.sendFlatBuffersStopRecording(peer: [peer], sendToRemote: cmd.sendMediaToRemote)
                // Immediately transition to waiting state after sending stop command
                self.become(
                    name: self.states.monitorWaitingForVideo,
                    state: self.monitorWaitingForVideo(monitor: monitor, peer: peer, lobby: lobby)
                )

            // MARK: - Zoom Command Handling (FlatBuffers)
            case let zoomCmd as UICmd.SetZoom:
                // Send FlatBuffers zoom command directly without showing alert for immediate feedback
                self.sendFlatBuffersSetZoom(peer: [peer], zoomFactor: zoomCmd.zoomFactor)
                
            case let fbZoomCmd as UICmd.FlatBuffersSetZoom:
                // Send FlatBuffers zoom command directly without showing alert for immediate feedback
                self.sendFlatBuffersSetZoom(peer: [peer], zoomFactor: fbZoomCmd.zoomFactor)


            case let fbFrameData as FlatBuffersFrameData:
                // Handle FlatBuffers frame data - send directly to monitor
                monitor ! fbFrameData
                self.requestFrame([peer])

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

            case let fbFrameData as FlatBuffersFrameData:
                // Handle FlatBuffers frame data while waiting for video
                // We still want to show the preview while waiting
                monitor ! fbFrameData
                self.requestFrame([peer])

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
                        ^{alert?.title = "Saving video..."}
                        // Save video directly without legacy conversion
                        saveVideoDataWithCompletion(videoData) { [weak self, alert] in
                        }
                         ^{alert?.dismiss(animated: true)}
                    } else {
                        print("🔍 DEBUG: No media data found in FlatBuffers response")
                        ^{alert?.dismiss(animated: true)}
                        showError("No video data received")
                    }
                } else {
                    // Handle error case
                    let errorMessage = fbResponse.response.error ?? "Unknown video recording error"
                    print("🔍 DEBUG: Video recording failed: \(errorMessage)")
                    ^{alert?.dismiss(animated: true)}
                    showError(errorMessage)    
                }
                self.popToState(name: self.states.monitorVideoMode)

            default:
                self.receive(msg: msg)
            }
        }
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
                        print("🔍 DEBUG: Calling video saving completion handler (write error)")
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
                        print("🔍 DEBUG: Calling video saving completion handler")
                        completion()
                    }
                })
            } else {
                print("🔍 DEBUG: Video library access not authorized")
                showError(NSLocalizedString("Remote Shutter has not access to the camera roll", comment: ""))
                DispatchQueue.main.async {
                    print("🔍 DEBUG: Calling video saving completion handler (unauthorized)")
                    completion()
                }
            }
        }
    }
}
