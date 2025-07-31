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

// MARK: - Robust Shorts Mode State Machine (following video recording pattern)

extension MonitorShortsStates {
    func monitorShortsMode(monitor: ActorRef,
                          peer: MCPeerID,
                          lobby: Weak<DeviceScannerViewController>) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter:
                print("📱 DEBUG: Remote entered shorts mode - checking camera connection")
                monitor ! UICmd.RenderShortsMode()
                self.requestFrame([peer])
                
                // Check if camera is connected before proceeding
                guard !self.session.connectedPeers.isEmpty else {
                    print("❌ DEBUG: No camera connected - cannot enter shorts mode")
                    let error = NSError(domain: "ShortsMode", code: 1, userInfo: [NSLocalizedDescriptionKey: "No camera connected. Please connect a camera device first."])
                    showError(error.localizedDescription)
                    // Return to photo mode as fallback
                    self.become(name: self.states.monitorPhotoMode,
                                state: self.monitorPhotoMode(monitor: monitor, peer: peer, lobby: lobby),
                                discardOld: true)
                    return
                }
                
                print("📱 DEBUG: Camera connected - sending StartShortsMode to Camera")
                // Send StartShortsMode command and transition to waiting state
                let config = ShortsConfig.thirtySeconds // Default config
                let startCmd = RemoteCmd.StartShortsMode(
                    maxDuration: config.maxDuration,
                    maxClips: config.maxClips,
                    sender: self.this
                )
                self.sendCommandOrGoToScanning(peer: [peer], msg: startCmd)
                
                // Transition to waiting state (like video recording pattern)
                self.become(
                    name: "monitorWaitingForShortsMode",
                    state: self.monitorWaitingForShortsMode(monitor: monitor, peer: peer, lobby: lobby)
                )

            default:
                self.receive(msg: msg)
            }
        }
    }
    
        func monitorWaitingForShortsMode(monitor: ActorRef,
peer: MCPeerID,
                                   lobby: Weak<DeviceScannerViewController>) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter:
                print("📱 DEBUG: Remote waiting for StartShortsModeAck from Camera")
                self.requestFrame([peer])
                
                // Add timeout protection (5 seconds as per design document)
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                    guard let self = self else { return }
                    print("⏰ DEBUG: Timeout waiting for StartShortsModeAck - returning to photo mode")
                    let error = NSError(domain: "ShortsMode", code: 2, userInfo: [NSLocalizedDescriptionKey: "Camera did not respond to shorts mode request. Please try again."])
                    showError(error.localizedDescription)
                    self.become(name: self.states.monitorPhotoMode,
                                state: self.monitorPhotoMode(monitor: monitor, peer: peer, lobby: lobby),
                                discardOld: true)
                }

            case is RemoteCmd.OnFrame:
                monitor ! msg
                self.requestFrame([peer])
                
            case let ack as RemoteCmd.StartShortsModeAck:
                if let error = ack.error {
                    print("❌ DEBUG: StartShortsModeAck received with error: \(error.localizedDescription)")
                    showError(error.localizedDescription)
                    // Transition back to photo mode on error
                    self.become(name: self.states.monitorPhotoMode,
                                state: self.monitorPhotoMode(monitor: monitor, peer: peer, lobby: lobby),
                                discardOld: true)
                } else {
                    print("✅ DEBUG: StartShortsModeAck received successfully - entering active shorts mode")
                    // Transition to active shorts mode
                    self.become(
                        name: "monitorActiveShortsMode", 
                        state: self.monitorActiveShortsMode(monitor: monitor, peer: peer, lobby: lobby)
                    )
                }
                
            case let mode as UICmd.BecomeMonitor:
                // Handle mode switches while waiting - send exit command first
                print("📱 DEBUG: Mode switch requested while waiting for shorts mode ack - canceling")
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.ExitShortsMode(sender: nil))
                if mode.mode == RecordingMode.Photo {
                    self.become(name: self.states.monitorPhotoMode,
                                state: self.monitorPhotoMode(monitor: monitor, peer: peer, lobby: lobby),
                                discardOld: true)
                } else if mode.mode == RecordingMode.Video {
                    self.become(name: self.states.monitorVideoMode,
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
    
    func monitorActiveShortsMode(monitor: ActorRef,
                                peer: MCPeerID,
                                lobby: Weak<DeviceScannerViewController>) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter:
                print("📱 DEBUG: Remote in active shorts mode - ready for clip recording")
                self.requestFrame([peer])

            case is RemoteCmd.OnFrame:
                monitor ! msg
                self.requestFrame([peer])
                
            case _ as UICmd.StartShortsClip:
                print("📱 DEBUG: Remote requesting start shorts clip")
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.StartShortsClip(maxDuration: 30.0, sender: self.this))
                // Transition to recording state
                self.become(
                    name: "monitorRecordingShortsClip",
                    state: self.monitorRecordingShortsClip(monitor: monitor, peer: peer, lobby: lobby)
                )
                
            case _ as UICmd.StopShortsClip:
                print("📱 DEBUG: StopShortsClip received but not recording - ignoring")
                
            case let mode as UICmd.BecomeMonitor:
                // Handle mode switches from active shorts mode
                print("📱 DEBUG: Mode switch requested from active shorts mode")
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.ExitShortsMode(sender: self.this))
                self.become(
                    name: "monitorExitingShortsMode",
                    state: self.monitorExitingShortsMode(monitor: monitor, peer: peer, lobby: lobby, targetMode: mode.mode)
                )
                
            // MARK: - Camera Controls in Shorts Mode
            
            case is UICmd.ToggleCamera:
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.ToggleCamera())
                
            case let cam as RemoteCmd.ToggleCameraResp:
                // For now, pass nil values for flash mode and camera position
                // TODO: Extract proper values from capabilities when needed
                monitor ! UICmd.ToggleCameraResp(flashMode: nil, camPosition: nil, error: cam.error)
                
            case is UICmd.ToggleFlash:
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.ToggleFlash())
                
            case let flash as RemoteCmd.ToggleFlashResp:
                monitor ! flash
                
            case is UICmd.ToggleTorch:
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.ToggleTorch())
                
            case let torch as RemoteCmd.ToggleTorchResp:
                monitor ! torch
                
            case let setZoom as UICmd.SetZoom:
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.SetZoom(zoomFactor: setZoom.zoomFactor))
                
            case let lensCmd as UICmd.SwitchLens:
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.SwitchLens(lensType: lensCmd.lensType))
                
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
    
        func monitorRecordingShortsClip(monitor: ActorRef,
peer: MCPeerID,
                                  lobby: Weak<DeviceScannerViewController>) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter:
                print("📱 DEBUG: Remote waiting for shorts clip recording to start")
                monitor ! UICmd.RenderShortsRecording(sender: nil)
                self.requestFrame([peer])
                
                // Add timeout protection for clip start (3 seconds as per design document)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    guard let self = self else { return }
                    print("⏰ DEBUG: Timeout waiting for StartShortsClipAck - returning to active shorts mode")
                    let error = NSError(domain: "ShortsMode", code: 3, userInfo: [NSLocalizedDescriptionKey: "Camera did not start recording. Please try again."])
                    showError(error.localizedDescription)
                    self.become(
                        name: "monitorActiveShortsMode",
                        state: self.monitorActiveShortsMode(monitor: monitor, peer: peer, lobby: lobby)
                    )
                }

            case is RemoteCmd.OnFrame:
                monitor ! msg
                self.requestFrame([peer])
                
            case let ack as RemoteCmd.StartShortsClipAck:
                if let error = ack.error {
                    print("❌ DEBUG: StartShortsClipAck received with error: \(error.localizedDescription)")
                    showError(error.localizedDescription)
                    // Go back to active shorts mode
                    self.become(
                        name: "monitorActiveShortsMode",
                        state: self.monitorActiveShortsMode(monitor: monitor, peer: peer, lobby: lobby)
                    )
                } else if let startTime = ack.recordingStartTime {
                    print("✅ DEBUG: StartShortsClipAck received - clip recording started")
                    // Synchronize recording start time
                    monitor ! UICmd.SyncRecordingStartTime(startTime: startTime)
                }
                
            case _ as UICmd.StopShortsClip:
                print("📱 DEBUG: Remote requesting stop shorts clip recording")
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.StopShortsClip(sender: self.this))
                
                // Transition to waiting state for stop acknowledgment
                self.become(
                    name: "monitorWaitingForShortsClipStop",
                    state: self.monitorWaitingForShortsClipStop(monitor: monitor, peer: peer, lobby: lobby)
                )
                
            case let mode as UICmd.BecomeMonitor:
                // Handle mode switches while recording - stop recording first
                print("📱 DEBUG: Mode switch requested while recording shorts clip - stopping recording first")
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.StopShortsClip(sender: self.this))
                // Don't transition yet - wait for stop ack first
                
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
    
    func monitorExitingShortsMode(monitor: ActorRef,
                                peer: MCPeerID,
                                lobby: Weak<DeviceScannerViewController>,
                                targetMode: RecordingMode? = nil) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter:
                print("📱 DEBUG: Remote waiting for ExitShortsModeAck")
                self.requestFrame([peer])

            case is RemoteCmd.OnFrame:
                monitor ! msg
                self.requestFrame([peer])
                
            case let ack as RemoteCmd.ExitShortsModeAck:
                if let error = ack.error {
                    print("❌ DEBUG: ExitShortsModeAck received with error: \(error.localizedDescription)")
                    showError(error.localizedDescription)
                }
                print("✅ DEBUG: ExitShortsModeAck received - transitioning to target mode")
                
                // Transition to target mode or default to photo
                if let target = targetMode {
                    if target == .Video {
                        self.become(name: self.states.monitorVideoMode,
                                    state: self.monitorVideoMode(monitor: monitor, peer: peer, lobby: lobby),
                                    discardOld: true)
                    } else {
                        self.become(name: self.states.monitorPhotoMode,
                                    state: self.monitorPhotoMode(monitor: monitor, peer: peer, lobby: lobby),
                                    discardOld: true)
                    }
                } else {
                    self.become(name: self.states.monitorPhotoMode,
                                state: self.monitorPhotoMode(monitor: monitor, peer: peer, lobby: lobby),
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
    
    func monitorWaitingForShortsClipStop(monitor: ActorRef,
                                       peer: MCPeerID,
                                       lobby: Weak<DeviceScannerViewController>) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter:
                print("📱 DEBUG: Remote waiting for StopShortsClipAck from Camera")
                self.requestFrame([peer])
                
                // Add timeout protection for clip stop (10 seconds as per design document)
                DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                    guard let self = self else { return }
                    print("⏰ DEBUG: Timeout waiting for StopShortsClipAck - returning to active shorts mode")
                    let error = NSError(domain: "ShortsMode", code: 4, userInfo: [NSLocalizedDescriptionKey: "Camera did not confirm stop recording. Returning to shorts mode."])
                    showError(error.localizedDescription)
                    self.become(
                        name: "monitorActiveShortsMode",
                        state: self.monitorActiveShortsMode(monitor: monitor, peer: peer, lobby: lobby)
                    )
                }

            case is RemoteCmd.OnFrame:
                monitor ! msg
                self.requestFrame([peer])
                
            case let ack as RemoteCmd.StopShortsClipAck:
                if let error = ack.error {
                    print("❌ DEBUG: StopShortsClipAck received with error: \(error.localizedDescription)")
                    showError(error.localizedDescription)
                }
                print("✅ DEBUG: StopShortsClipAck received - clip recording stopped")
                // Go back to active shorts mode for next clip
                self.become(
                    name: "monitorActiveShortsMode",
                    state: self.monitorActiveShortsMode(monitor: monitor, peer: peer, lobby: lobby)
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
} 