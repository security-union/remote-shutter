//
//  MonitorPhotoStates.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 10/11/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import MultipeerConnectivity
import Photos
import StoreKit
import SwiftUI

extension RemoteCamSession {

    // MARK: - Monitor-side Picture Saving (with review prompt)
    func savePictureOnMonitor(_ imageData: Data) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    showPhotosAccessDeniedModal(for: .photo)
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, data: imageData, options: nil)
            }) { (success: Bool, _: Error?) in
                if success {
                    print("Saved photo on monitor!")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        showReviewPromptIfAppropriate()
                    }
                } else {
                    print("Failed to save photo on monitor!")
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

            case is RemoteCmd.OnFrame:
                monitor ! msg
                self.requestFrame([peer])

            case is UICmd.UnbecomeMonitor:
                self.popToState(name: .connected)

            case is UICmd.ToggleCamera:
                if self.sendMessage(peer: [peer], msg: RemoteCmd.ToggleCamera()).isSuccess() {
                    self.become(
                        name: .monitorTogglingCamera,
                        state: self.monitorTogglingCamera(monitor: monitor, peer: peer, lobby: lobby)
                    )
                } else {
                    self.popAndStartScanning()
                }

            case is UICmd.ToggleFlash:
                if self.sendMessage(peer: [peer], msg: RemoteCmd.ToggleFlash()).isSuccess() {
                    self.become(
                        name: .monitorTogglingFlash,
                        state: self.monitorTogglingFlash(monitor: monitor, peer: peer, lobby: lobby)
                    )
                } else {
                    self.popAndStartScanning()
                }

            case is UICmd.ToggleTorch:
                // Handle torch toggle directly in photo mode
                if let f = self.sendMessage(peer: [peer], msg: RemoteCmd.ToggleTorch()) as? Failure {
                    print("❌ DEBUG: Failed to send torch toggle command in photo mode: \(f.tryError.localizedDescription)")
                }

            case let countdown as UICmd.TimerCountdown:
                // Fire-and-forget: send timer countdown to camera
                let _ = self.sendMessage(peer: [peer], msg: RemoteCmd.TimerCountdown(value: countdown.value))

            case let sync as UICmd.SyncMonitorSettings:
                // Fire-and-forget: sync monitor mode to camera for display
                let _ = self.sendMessage(peer: [peer], msg: RemoteCmd.SyncMonitorSettings(mode: sync.mode))

            case let cmd as UICmd.TakePicture:
                if self.sendMessage(
                    peer: [peer],
                    msg: RemoteCmd.TakePic(sender: self.this, sendMediaToPeer: cmd.sendMediaToRemote)).isSuccess() {
                    self.become(name: .monitorTakingPicture, state:
                    self.monitorTakingPicture(monitor: monitor, peer: peer, lobby: lobby))
                } else {
                    self.popAndStartScanning()
                }
                
            // MARK: - Camera Capabilities Handling
            case let capabilities as RemoteCmd.CameraCapabilitiesResp:
                print("🔍 DEBUG: Monitor received camera capabilities")
                if let cameraInfo = capabilities.getCurrentCameraInfo() {
                    print("🔍 DEBUG: Available lenses: \(cameraInfo.availableLenses)")
                }
                monitor ! capabilities
                
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
                
            case let torchResp as RemoteCmd.ToggleTorchResp:
                // Handle torch response directly without alert
                if let error = torchResp.error {
                    print("❌ DEBUG: Photo mode torch response error: \(error.localizedDescription)")
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
                
            // MARK: - Photo Quality Command Handling
            case let cmd as UICmd.SetPhotoQuality:
                if let f = self.sendMessage(
                    peer: [peer], msg: RemoteCmd.SetPhotoQuality(format: cmd.format, hdrMode: cmd.hdrMode)) as? Failure {
                    print("Failed to send photo quality command: \(f.tryError)")
                }

            case let resp as RemoteCmd.SetPhotoQualityResp:
                if resp.error == nil {
                    monitor ! resp
                }

            // MARK: - Video Quality Command Handling (allow changing video settings from photo mode)
            case let cmd as UICmd.SetVideoQuality:
                if let f = self.sendMessage(
                    peer: [peer], msg: RemoteCmd.SetVideoQuality(resolution: cmd.resolution, frameRate: cmd.frameRate)) as? Failure {
                    print("Failed to send video quality command: \(f.tryError)")
                }

            case let resp as RemoteCmd.SetVideoQualityResp:
                if resp.error == nil {
                    monitor ! resp
                }

            // MARK: - Aspect Ratio Command Handling
            case let cmd as UICmd.SetAspectRatio:
                if let f = self.sendMessage(
                    peer: [peer], msg: RemoteCmd.SetAspectRatio(aspectRatio: cmd.aspectRatio)) as? Failure {
                    print("Failed to send aspect ratio command: \(f.tryError)")
                }

            case let resp as RemoteCmd.SetAspectRatioResp:
                monitor ! resp

            case is UICmd.RequestCameraCapabilities:
                // Request capabilities from camera
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.RequestCameraCapabilities())
                
            case is RemoteCmd.PeerBecameCamera:
                // When peer becomes camera, request fresh capabilities
                print("🔍 DEBUG: Monitor detected peer became camera - requesting fresh capabilities")
                self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.RequestCameraCapabilities())

            case let mode as UICmd.BecomeMonitor:
                if mode.mode == RecordingMode.Video || mode.mode == RecordingMode.Shorts {
                    self.become(name: .monitor,
                                state: self.monitorVideoMode(monitor: monitor, peer: peer, lobby: lobby),
                                discardOld: true)
                }

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

    func monitorTakingPicture(monitor: ActorRef,
                              peer: MCPeerID,
                              lobby: Weak<DeviceScannerViewController>) -> Receive {
        var alertHandle: AlertHandle?
        ^{ [weak self] in
            alertHandle = self?.alertPresenter.showAlert(title: "Requesting picture")
        }
        let gen = self.scheduleTimeout(stateName: .monitorTakingPicture)
        return { [unowned self] (msg: Actor.Message) in
            switch msg {

            case let timeout as UICmd.StateTimeout:
                if timeout.stateName == .monitorTakingPicture && timeout.generation == gen {
                    ^{ [weak self] in
                        if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                    }
                    self.unbecome()
                }

            case is RemoteCmd.TakePicAck:
                ^{ [weak self] in
                    if let h = alertHandle { self?.alertPresenter.updateAlert(h, title: "Receiving picture") }
                }
                self.sendCommandOrGoToScanning(peer: [peer], msg: msg)

            case let cmd as UICmd.TakePicture:
                self.sendCommandOrGoToScanning(
                    peer: [peer],
                    msg: RemoteCmd.TakePic(sender: self.this, sendMediaToPeer: cmd.sendMediaToRemote)
                )

            case let picResp as RemoteCmd.TakePicResp:
                if let imageData = picResp.pic {
                    savePictureOnMonitor(imageData)
                    ^{ [weak self] in
                        if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                    }
                } else if let error = picResp.error {
                    ^{ [weak self] in
                        if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                        self?.alertPresenter.showError(title: error._domain)
                    }
                }
                self.unbecome()

            case is UICmd.UnbecomeMonitor:
                ^{ [weak self] in
                    if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                }
                self.popToState(name: .connected)

            case let c as DisconnectPeer:
                if c.peer?.displayName == peer.displayName && self.connectedPeers.count == 0 {
                    ^{ [weak self] in
                        if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                    }
                    self.popAndStartScanning()
                }

            case is Disconnect:
                ^{ [weak self] in
                    if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                }
                self.popAndStartScanning()

            default:
                ^{ [weak self] in
                    if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                }
                print("ignoring message")
            }
        }
    }

}
