//
//  MonitorVideoStates.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 10/10/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import MultipeerConnectivity
import Photos
import StoreKit
import SwiftUI

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
                self.popToState(name: .connected)

            case let mode as UICmd.BecomeMonitor:
                if mode.mode == RecordingMode.Photo {
                    self.become(name: .monitor,
                                state: self.monitorPhotoMode(monitor: monitor, peer: peer, lobby: lobby),
                                discardOld: true)
                }
                // Video and Shorts modes stay in video state
                // UI differences are handled in SwiftUI view

            case is UICmd.TakePicture:
                if self.sendMessage(peer: [peer], msg: RemoteCmd.StartRecordingVideo(sender: self.this)).isSuccess() {
                    self.become(
                        name: .monitorRecordingVideo,
                        state: self.monitorRecordingVideo(monitor: monitor, peer: peer, lobby: lobby)
                    )
                } else {
                    self.popAndStartScanning()
                }

            case is UICmd.ToggleCamera:
                if self.sendMessage(peer: [peer], msg: RemoteCmd.ToggleCamera()).isSuccess() {
                    self.become(name: .monitorTogglingCamera, state:
                    self.monitorTogglingCamera(monitor: monitor, peer: peer, lobby: lobby))
                } else {
                    self.popAndStartScanning()
                }

            case is UICmd.ToggleTorch:
                // Handle torch toggle directly in video mode
                if let f = self.sendMessage(peer: [peer], msg: RemoteCmd.ToggleTorch()) as? Failure {
                    print("❌ DEBUG: Failed to send torch toggle command in video mode: \(f.tryError.localizedDescription)")
                }
                
            // MARK: - Camera Capabilities Handling
            case let capabilities as RemoteCmd.CameraCapabilitiesResp:
                print("🔍 DEBUG: Monitor video mode received camera capabilities")
                if let cameraInfo = capabilities.getCurrentCameraInfo() {
                    print("🔍 DEBUG: Video mode available lenses: \(cameraInfo.availableLenses)")
                }
                monitor ! capabilities
                
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
                
            case let lensCmd as UICmd.SwitchLens:
                if self.sendMessage(
                    peer: [peer], msg: RemoteCmd.SwitchLens(lensType: lensCmd.lensType)).isSuccess() {
                    self.become(
                        name: .monitorSwitchingLens,
                        state: self.monitorSwitchingLens(monitor: monitor, peer: peer, lobby: lobby)
                    )
                } else {
                    self.popAndStartScanning()
                }
                
            // MARK: - Video Quality Command Handling
            case let cmd as UICmd.SetVideoQuality:
                if let f = self.sendMessage(
                    peer: [peer], msg: RemoteCmd.SetVideoQuality(resolution: cmd.resolution, frameRate: cmd.frameRate)) as? Failure {
                    print("Failed to send video quality command: \(f.tryError)")
                }

            case let resp as RemoteCmd.SetVideoQualityResp:
                if resp.error == nil {
                    monitor ! resp
                }

            // MARK: - Photo Quality Command Handling (allow changing photo settings from video mode)
            case let cmd as UICmd.SetPhotoQuality:
                if let f = self.sendMessage(
                    peer: [peer], msg: RemoteCmd.SetPhotoQuality(format: cmd.format, hdrMode: cmd.hdrMode)) as? Failure {
                    print("Failed to send photo quality command: \(f.tryError)")
                }

            case let resp as RemoteCmd.SetPhotoQualityResp:
                if resp.error == nil {
                    monitor ! resp
                }

            case is UICmd.RequestCameraCapabilities:
                // Request capabilities from camera
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.RequestCameraCapabilities())
                
            case is RemoteCmd.PeerBecameCamera:
                // When peer becomes camera, request fresh capabilities
                print("🔍 DEBUG: Monitor detected peer became camera - requesting fresh capabilities")
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.RequestCameraCapabilities())

            case let c as DisconnectPeer:
                if c.peer?.displayName == peer.displayName && self.connectedPeers.count == 0 {
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
                
            case let ack as RemoteCmd.StartRecordingVideoAck:
                // Check if this is an error response
                if let error = ack.error {
                    print("❌ DEBUG: StartRecordingVideoAck received with error - device not in camera mode")
                    showError(error.localizedDescription)
                    // Transition back to video mode state
                    self.popToState(name: .monitor)
                } else if let startTime = ack.recordingStartTime {
                    // Synchronize recording start time with camera
                    monitor ! UICmd.SyncRecordingStartTime(startTime: startTime)
                }

            case let cmd as UICmd.TakePicture:
                print("🔴 DEBUG: TakePicture received in monitorRecordingVideo state - stopping recording")
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.StopRecordingVideo(sender: self.this,  sendMediaToPeer: cmd.sendMediaToRemote))

            case is UICmd.ToggleTorch:
                // Handle torch toggle during video recording
                if let f = self.sendMessage(peer: [peer], msg: RemoteCmd.ToggleTorch()) as? Failure {
                    print("❌ DEBUG: Failed to send torch toggle command during video recording: \(f.tryError.localizedDescription)")
                }
                
            case let torchResp as RemoteCmd.ToggleTorchResp:
                // Handle torch response during video recording
                if let error = torchResp.error {
                    print("❌ DEBUG: Video recording torch response error: \(error.localizedDescription)")
                }
                monitor ! torchResp

            case is RemoteCmd.StopRecordingVideoAck:
                self.become(
                    name: .monitorWaitingForVideo,
                    state: self.monitorWaitingForVideo(monitor: monitor, peer: peer, lobby: lobby)
                )
            
            case let errorResp as RemoteCmd.StopRecordingVideoResp:
                // Handle immediate error response (e.g., microphone access denied)
                if errorResp.error != nil {
                    saveVideo(errorResp)
                    self.popToState(name: .monitor)
                }
                
            case is UICmd.UnbecomeMonitor:
                self.popToState(name: .connected)

            case is Disconnect:
                self.popAndStartScanning()

            case let c as DisconnectPeer:
                if c.peer?.displayName == peer.displayName && self.connectedPeers.count == 0 {
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
        // Note: Progress UI is now handled by SwiftUI VideoTransferProgressView
        // No need for old UIAlertController
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter:
                monitor ! UICmd.RenderVideoMode()  // Reset UI to responsive state
                // Progress UI handled by SwiftUI components

            case let w as RemoteCmd.StopRecordingVideoResp:
                // Progress UI will be dismissed by SwiftUI when transfer completes
                saveVideo(w)
                self.popToState(name: .monitor)

            case is Disconnect:
                // Progress UI handled by SwiftUI - no alert to dismiss
                self.popAndStartScanning()

            case is UICmd.UnbecomeMonitor:
                self.popToState(name: .connected)

            case let c as DisconnectPeer:
                if c.peer?.displayName == peer.displayName && self.connectedPeers.count == 0 {
                    // Progress UI handled by SwiftUI - no alert to dismiss
                    self.popAndStartScanning()
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
                DispatchQueue.main.async {
                    showPhotosAccessDeniedModal(for: .video)
                }
            }
        }
    }
}
