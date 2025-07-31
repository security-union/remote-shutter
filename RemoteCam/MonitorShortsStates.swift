//
//  MonitorShortsStates.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 2025.
//  Copyright © 2025 Security Union. All rights reserved.
//

import Foundation
import Theater
import MultipeerConnectivity
import Photos
import StoreKit
import SwiftUI

private typealias MonitorShortsStates = RemoteCamSession

extension MonitorShortsStates {
    func monitorShortsMode(monitor: ActorRef,
                          peer: MCPeerID,
                          lobby: Weak<DeviceScannerViewController>) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter:
                print("📱 DEBUG: Remote entered shorts mode - configuring UI and sending StartShortsMode to camera")
                
                // Configure Remote UI for shorts mode
                monitor ! UICmd.RenderShortsMode()
                
                // Send StartShortsMode command to Camera with default config
                let shortsConfig = RemoteCmd.StartShortsMode(
                    maxDuration: 30.0,      // Default to 30 seconds
                    maxClips: 10,
                    sender: nil
                )
                print("📱 DEBUG: Remote sending StartShortsMode command to camera")
                self.sendCommandOrGoToScanning(peer: [peer], msg: shortsConfig, mode: .reliable)
                
                // Start requesting frames for preview
                self.requestFrame([peer])

            case is RemoteCmd.OnFrame:
                // Forward frame to monitor for preview
                monitor ! msg
                self.requestFrame([peer])

            case is UICmd.UnbecomeMonitor:
                // Exit shorts mode
                print("📱 DEBUG: Remote exiting shorts mode - sending ExitShortsMode to camera")
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.ExitShortsMode(sender: nil), mode: .reliable)
                self.popToState(name: self.states.connected)

            case let mode as UICmd.BecomeMonitor:
                // Handle mode switches from shorts mode
                if mode.mode == RecordingMode.Photo {
                    print("📱 DEBUG: Remote switching from shorts to photo mode")
                    self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.ExitShortsMode(sender: nil), mode: .reliable)
                    self.become(name: states.monitorPhotoMode,
                                state: self.monitorPhotoMode(monitor: monitor, peer: peer, lobby: lobby),
                                discardOld: true)
                } else if mode.mode == RecordingMode.Video {
                    print("📱 DEBUG: Remote switching from shorts to video mode")
                    self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.ExitShortsMode(sender: nil), mode: .reliable)
                    self.become(name: states.monitorVideoMode,
                                state: self.monitorVideoMode(monitor: monitor, peer: peer, lobby: lobby),
                                discardOld: true)
                }
                // If already in Shorts mode, stay in shorts mode

            // MARK: - Shorts-Specific Commands
            
            case is UICmd.TakePicture:
                // In shorts mode, this becomes "start recording clip"
                print("📱 DEBUG: Remote starting shorts clip recording")
                let startClipCmd = RemoteCmd.StartShortsClip(maxDuration: 15.0, sender: nil) // Default clip duration
                self.sendCommandOrGoToScanning(peer: [peer], msg: startClipCmd, mode: .reliable)
                
            case is UICmd.TakePicture:
                // Stop current clip recording
                print("📱 DEBUG: Remote stopping shorts clip recording")
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.StopShortsClip(sender: nil), mode: .reliable)
                
            // MARK: - Camera Response Handling
            
            case let response as RemoteCmd.ShortsCommandResponse:
                print("📱 DEBUG: Remote received ShortsCommandResponse - success: \(response.success)")
                if !response.success, let error = response.error {
                    print("📱 ERROR: Shorts command failed: \(error)")
                    // Could show error to user here
                }
                
            case let clipData as RemoteCmd.ShortsClipData:
                print("📱 DEBUG: Remote received shorts clip data - clipId: \(clipData.clipId)")
                // Handle received clip data - store locally, update timeline UI
                // This would integrate with the ShortsSession and timeline management
                
            // MARK: - Standard Monitor Commands
            
            case is RemoteCmd.ToggleCamera:
                print("🔍 DEBUG: Shorts mode received ToggleCamera command")
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.ToggleCamera())
                
            case let cam as RemoteCmd.ToggleCameraResp:
                // Update camera capabilities on UI
                if let capabilities = cam.cameraCapabilities {
                    monitor ! UICmd.ToggleCameraResp(flashMode: nil, camPosition: nil, error: cam.error)
                } else {
                                          monitor ! UICmd.ToggleCameraResp(flashMode: nil, camPosition: nil, error: cam.error)
                }
                
            case is RemoteCmd.ToggleFlash:
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.ToggleFlash())
                
            case let flash as RemoteCmd.ToggleFlashResp:
                monitor ! flash
                
            case is RemoteCmd.ToggleTorch:
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.ToggleTorch())
                
            case let torch as RemoteCmd.ToggleTorchResp:
                monitor ! torch
                
            case let zoomCmd as UICmd.SetZoom:
                print("🔍 DEBUG: Shorts mode received SetZoom: \(zoomCmd.zoomFactor)")
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.SetZoom(zoomFactor: zoomCmd.zoomFactor))
                
            case let zoom as RemoteCmd.SetZoomResp:
                // Forward zoom response to monitor
                monitor ! zoom
                
            case let lensCmd as UICmd.SwitchLens:
                print("🔍 DEBUG: Shorts mode received SwitchLens to \(lensCmd.lensType.displayName)")
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.SwitchLens(lensType: lensCmd.lensType))
                
            case let lensResp as RemoteCmd.SwitchLensResp:
                // Forward lens response to monitor
                monitor ! lensResp
                
            case is UICmd.RequestCameraCapabilities:
                // Request capabilities from camera
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.RequestCameraCapabilities())
                
            case let capabilities as RemoteCmd.CameraCapabilitiesResp:
                print("🔍 DEBUG: Shorts mode received camera capabilities")
                monitor ! capabilities
                
            case is RemoteCmd.PeerBecameCamera:
                // When peer becomes camera, request fresh capabilities
                print("🔍 DEBUG: Shorts mode detected peer became camera - requesting fresh capabilities")
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.RequestCameraCapabilities())

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
} 