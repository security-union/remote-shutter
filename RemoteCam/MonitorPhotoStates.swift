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
import StoreKit

extension RemoteCamSession {

    // MARK: - Monitor-side Picture Saving (with review prompt)
    func savePictureOnMonitor(_ imageData: Data) {
        print("🔍 DEBUG: savePictureOnMonitor called with \(imageData.count) bytes")
        PHPhotoLibrary.requestAuthorization { status in
            print("🔍 DEBUG: Photo library authorization status: \(status.rawValue)")
            guard status == .authorized else {
                print("🔍 DEBUG: Photo library access not authorized")
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, data: imageData, options: nil)
                print("🔍 DEBUG: Photo asset creation request created")
            }) { (success: Bool, error: Error?) in
                if success {
                    print("🔍 DEBUG: Successfully saved photo on monitor!")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        showReviewPromptIfAppropriate()
                    }
                } else {
                    print("🔍 DEBUG: Failed to save photo on monitor! Error: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }
    
    func monitorPhotoMode(monitor: ActorRef,
                 peer: MCPeerID,
                 lobby: Weak<DeviceScannerViewController>) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter:
                monitor ! UICmd.RenderPhotoMode()
                self.requestFrame([peer])

            case let fbFrameData as FlatBuffersFrameData:
                // Handle FlatBuffers frame data - send directly to monitor
                monitor ! fbFrameData
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

            case is UICmd.FlatBuffersTorchToggle:
                // Handle torch toggle directly in photo mode using FlatBuffers
                print("🔍 DEBUG: Photo mode - attempting FlatBuffers torch toggle")
                if let f = self.sendFlatBuffersTorchToggle(peer: [peer]) as? Failure {
                    print("❌ DEBUG: Failed to send FlatBuffers torch toggle command in photo mode: \(f.tryError.localizedDescription)")
                } else {
                    print("✅ DEBUG: Successfully sent FlatBuffers torch toggle command in photo mode")
                }

            case is UICmd.TakePicture:
                self.become(name: self.states.monitorTakingPicture, state:
                self.monitorTakingPicture(monitor: monitor, peer: peer, lobby: lobby))
                self.this ! msg
                
            // MARK: - Camera Capabilities Handling
            case let capabilities as RemoteCmd.CameraCapabilitiesResp:
                print("🔍 DEBUG: Monitor received camera capabilities")
                if let cameraInfo = capabilities.getCurrentCameraInfo() {
                    print("🔍 DEBUG: Available lenses: \(cameraInfo.availableLenses)")
                }
                monitor ! capabilities
                
            // MARK: - FlatBuffers Message Handling
            case let fbCommand as FlatBuffersCameraCommand:
                print("🔍 DEBUG: Monitor received FlatBuffers camera command: \(fbCommand.command.action)")
                // FlatBuffers commands are handled by the camera, not the monitor
                // This case is here for completeness but shouldn't normally occur
                
            case let fbResponse as FlatBuffersCameraStateResponse:
                print("🔍 DEBUG: Monitor received FlatBuffers camera state response")
                print("🔍 DEBUG: Command success: \(fbResponse.response.success)")
                if let error = fbResponse.response.error {
                    print("🔍 DEBUG: Command error: \(error)")
                }
                
                // Convert FlatBuffers response to legacy format based on command type
                // We need to determine what command this response is for based on context
                // For now, we'll handle the most common case - camera toggle response
                
                // For now, we'll forward FlatBuffers responses to the monitor for UI updates
                // In the future, we could implement more sophisticated state-based routing
                monitor ! fbResponse
                print("🔍 DEBUG: Forwarded FlatBuffers state update to monitor")

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
                
            case is UICmd.RequestCameraCapabilities:
                // Request capabilities from camera
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.RequestCameraCapabilities())
                
            case is RemoteCmd.PeerBecameCamera:
                // When peer becomes camera, request fresh capabilities
                print("🔍 DEBUG: Monitor detected peer became camera - requesting fresh capabilities")
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.RequestCameraCapabilities())

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

            case let cmd as UICmd.TakePicture:
                ^{alert?.show(true) {
                    self.mailbox.addOperation(BlockOperation {
                        self.sendFlatBuffersPhotoCapture(peer: [peer], sendToRemote: cmd.sendMediaToRemote)
                    })
                }}



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

            case let fbResponse as FlatBuffersCameraStateResponse:
                print("🔍 DEBUG: Monitor taking picture received FlatBuffers camera state response")
                print("🔍 DEBUG: Command success: \(fbResponse.response.success)")
                
                // Handle FlatBuffers response directly without legacy conversion
                if fbResponse.response.success {
                    // Extract media data from FlatBuffers response
                    if let mediaData = fbResponse.response.mediaData {
                        let imageData = Data(mediaData.data)
                        print("🔍 DEBUG: Extracted image data: \(imageData.count) bytes")
                        print("🔍 DEBUG: Media data type: \(mediaData.type)")
                        
                        // Save photo directly without legacy conversion
                        savePictureOnMonitor(imageData)
                        ^{alert?.dismiss(animated: true)}
                    } else {
                        print("🔍 DEBUG: No media data found in FlatBuffers response")
                        ^{alert?.dismiss(animated: true)}
                    }
                } else {
                    // Handle error case
                    let errorMessage = fbResponse.response.error ?? "Unknown photo capture error"
                    print("🔍 DEBUG: Photo capture failed: \(errorMessage)")
                    
                    ^{alert?.dismiss(animated: true) { () in
                        let error = UIAlertController(title: "Photo Capture Error", message: errorMessage, preferredStyle: .alert)
                        error.simpleOkAction()
                        error.show(true)
                    }}
                }
                self.unbecome()

            default:
                ^{alert?.dismiss(animated: true, completion: nil)}
                print("ignoring message")
            }
        }
    }

}
