//
//  RemoteCamSessionCamStates.swift
//  Actors
//
//  Created by Dario Lencina on 11/1/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation
import Theater
import MultipeerConnectivity
import Photos
import FlatBuffers

extension RemoteCamSession {

    // MARK: - Camera Capabilities Retry Helper
    private func attemptToSendCapabilities(ctrl: CameraViewController, peer: MCPeerID, attempt: Int, maxAttempts: Int) {
        print("🔍 DEBUG: Attempt \(attempt)/\(maxAttempts) to gather camera capabilities")
        
        ctrl.gatherAllCameraCapabilities()
        if let capabilities = ctrl.gatherCurrentCameraCapabilities() {
            print("✅ DEBUG: Successfully gathered capabilities on attempt \(attempt)")
            print("🔍 DEBUG: Sending camera capabilities - Available lenses: \(capabilities.getCurrentCameraInfo()?.availableLenses ?? [])")
            self.mailbox.addOperation(BlockOperation {
                self.sendCommandOrGoToScanning(peer: [peer], msg: capabilities)
            })
        } else if attempt < maxAttempts {
            let delay = Double(attempt) * 0.2 // 0.2s, 0.4s, 0.6s, 0.8s delays
            print("⏳ DEBUG: Attempt \(attempt) failed, retrying in \(delay)s")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.attemptToSendCapabilities(ctrl: ctrl, peer: peer, attempt: attempt + 1, maxAttempts: maxAttempts)
            }
        } else {
            print("❌ DEBUG: Failed to gather camera capabilities after \(maxAttempts) attempts")
        }
    }

    func savePicture(_ imageData: Data) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, data: imageData, options: nil)
            }) { (success: Bool, _: Error?) in
                if success {
                    print("Saved photo!")
                } else {
                    print("Failed to save photo!")
                }
            }
        }
    }
    
    func cameraTakingPic(peer: MCPeerID,
                         ctrl: CameraViewController,
                         lobby: Weak<DeviceScannerViewController>,
                         sendMediaToPeer: Bool) -> Receive {
        var alert: UIAlertController?
        ^{
            alert = UIAlertController(title: "Taking picture",
                message: nil,
                preferredStyle: .alert)

            alert?.show(true)
        }
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case let t as UICmd.OnPicture:
                if let imageData = t.pic {
                    savePicture(imageData)
                }
                ^{
                    alert?.dismiss(animated: true, completion: nil)
                }
                // Send FlatBuffers response
                let _ = self.sendFlatBuffersPhotoCaptureResponse(
                    peer: [peer],
                    commandId: UUID().uuidString,
                    photoData: sendMediaToPeer ? t.pic : nil,
                    error: t.error
                )
                
                self.unbecome()
            case let c as DisconnectPeer:
                ^{
                    alert?.dismiss(animated: true, completion: nil)
                    if c.peer.displayName == peer.displayName && self.session.connectedPeers.count == 0 {
                        self.mailbox.addOperation(BlockOperation {
                            self.popAndStartScanning()
                        })
                    }
                }

            case is Disconnect:
                ^{
                    alert?.dismiss(animated: true)
                }
                self.popAndStartScanning()

            default:
                self.receive(msg: msg)
            }
        }
    }

    func camera(peer: MCPeerID,
                ctrl: CameraViewController,
                lobbyWrapper: Weak<DeviceScannerViewController>) -> Receive {
        
        return { [unowned self] (msg: Actor.Message) in
            guard lobbyWrapper.value != nil else {
                popAndStartScanning()
                return
            }
            
            switch msg {
            case is OnEnter:
                print("🔍 DEBUG: Camera starting up")
                getFrameSender()?.tell(msg: SetSession(peer: peer, session: self))
                
            case is RemoteCmd.PeerBecameMonitor:
                // When a new monitor joins, immediately send camera capabilities
                print("🔍 DEBUG: Camera received PeerBecameMonitor - attempting to send capabilities")
                self.attemptToSendCapabilities(ctrl: ctrl, peer: peer, attempt: 1, maxAttempts: 5)
                
            case is RemoteCmd.RequestCameraCapabilities:
                // When monitor explicitly requests capabilities
                print("🔍 DEBUG: Camera received RequestCameraCapabilities - attempting to gather capabilities")
                self.attemptToSendCapabilities(ctrl: ctrl, peer: peer, attempt: 1, maxAttempts: 5)
                
            case is RemoteCmd.RequestFrame:
                self.receive(msg: msg)
                
            case is RemoteCmd.SendFrame:
                self.receive(msg: msg)
                
            case let m as UICmd.ToggleCameraResp:
                self.sendCommandOrGoToScanning(
                    peer: [peer],
                    msg: RemoteCmd.ToggleCameraResp(cameraCapabilities: nil,
                                                    error: m.error))






                

                

                
            case let torchCmd as RemoteCmd.SetTorch:
                let result = ctrl.setTorchMode(mode: torchCmd.torchMode)
                var resp: Message?
                if let torchMode = result.toOptional() {
                    resp = RemoteCmd.SetTorchResp(torchMode: torchMode, error: nil)
                } else if let failure = result as? Failure {
                    resp = RemoteCmd.SetTorchResp(torchMode: nil, error: failure.error)
                }
                self.sendCommandOrGoToScanning(peer: [peer], msg: resp!)
                
            // MARK: - Zoom Command Handling
            case let zoomCmd as RemoteCmd.SetZoom:
                print("🔍 DEBUG: Camera received SetZoom: \(zoomCmd.zoomFactor)")
                let result = ctrl.setZoom(zoomFactor: zoomCmd.zoomFactor)
                var resp: Message?
                if let (zoomFactor, currentLens, zoomRange) = result.toOptional() {
                    resp = RemoteCmd.SetZoomResp(zoomFactor: zoomFactor, currentLens: currentLens, zoomRange: zoomRange, error: nil)
                } else if let failure = result as? Failure {
                    print("❌ DEBUG: Camera zoom failed: \(failure.tryError.localizedDescription)")
                    resp = RemoteCmd.SetZoomResp(zoomFactor: nil, currentLens: nil, zoomRange: nil, error: failure.tryError)
                }
                self.sendCommandOrGoToScanning(peer: [peer], msg: resp!)
                
            // MARK: - Lens Switching Command Handling  
            case let lensCmd as RemoteCmd.SwitchLens:
                print("🔍 DEBUG: Camera received SwitchLens command to \(lensCmd.lensType.displayName)")
                let result = ctrl.switchLens(to: lensCmd.lensType)
                var resp: Message?
                if let (lensType, availableLenses, currentZoom, zoomRange) = result.toOptional() {
                    print("✅ DEBUG: Camera lens switch success - new lens: \(lensType.displayName)")
                    resp = RemoteCmd.SwitchLensResp(lensType: lensType, availableLenses: availableLenses, currentZoom: currentZoom, zoomRange: zoomRange, error: nil)

                } else if let failure = result as? Failure {
                    print("❌ DEBUG: Camera lens switch failed: \(failure.tryError.localizedDescription)")
                    resp = RemoteCmd.SwitchLensResp(lensType: nil, availableLenses: nil, currentZoom: nil, zoomRange: nil, error: failure.error)
                    print("🔍 DEBUG: Created error response:")
//                    print("🔍 DEBUG: - error: \(failure.error.localizedDescription)")
                }
                

                self.sendCommandOrGoToScanning(peer: [peer], msg: resp!)

            case let c as DisconnectPeer:
                if c.peer.displayName == peer.displayName && self.session.connectedPeers.count == 0 {
                    print("🔍 DEBUG: Camera disconnecting peer - going to scanning")
                    self.popAndStartScanning()
                }

            case is Disconnect:
                print("🔍 DEBUG: Camera disconnecting - going to scanning")
                self.popAndStartScanning()

            case is UICmd.UnbecomeCamera:
                print("🔍 DEBUG: Camera explicitly unbecoming - going to connected state")
                self.popToState(name: self.states.connected)
                
            // MARK: - FlatBuffers Command Handling
            case let fbCommand as FlatBuffersCameraCommand:
                print("🔍 DEBUG: Camera received FlatBuffers command: \(fbCommand.command.action)")
                self.handleFlatBuffersCameraCommand(fbCommand.command, ctrl: ctrl, peer: peer)

            default:
                self.receive(msg: msg)
            }
        }
    }
    
    // MARK: - FlatBuffers Command Handling
    
    /// Handle FlatBuffers camera commands
    private func handleFlatBuffersCameraCommand(_ command: RemoteShutter_CameraCommand, ctrl: CameraViewController, peer: MCPeerID) {
        print("🎯 Camera processing FlatBuffers command: \(command.action)")
        
        switch command.action {
        case .toggletorch:
            handleFlatBuffersTorchToggle(command, ctrl: ctrl, peer: peer)
            
        case .toggleflash:
            handleFlatBuffersFlashToggle(command, ctrl: ctrl, peer: peer)
            
        case .togglecamera:
            handleFlatBuffersCameraToggle(command, ctrl: ctrl, peer: peer)
            
        case .takepicture:
            handleFlatBuffersPhotoCapture(command, ctrl: ctrl, peer: peer)
            
        case .startrecording:
            handleFlatBuffersStartRecording(command, ctrl: ctrl, peer: peer)
            
        case .stoprecording:
            handleFlatBuffersStopRecording(command, ctrl: ctrl, peer: peer)
            
        default:
            print("⚠️ Camera received unhandled FlatBuffers command: \(command.action)")
        }
    }
    
    /// Handle FlatBuffers torch toggle command
    private func handleFlatBuffersTorchToggle(_ command: RemoteShutter_CameraCommand, ctrl: CameraViewController, peer: MCPeerID) {
        print("🔦 Camera handling FlatBuffers torch toggle")
        
        let result = ctrl.toggleTorch()
        let commandId = command.id ?? UUID().uuidString
        
        if let torchMode = result.toOptional() {
            print("✅ Camera torch toggle success: \(torchMode)")
            let _ = self.sendFlatBuffersTorchStateResponse(
                peer: [peer],
                commandId: commandId,
                success: true,
                error: nil,
                torchMode: torchMode
            )
        } else if let failure = result as? Failure {
            print("❌ Camera torch toggle failed: \(failure.tryError)")
            let _ = self.sendFlatBuffersTorchStateResponse(
                peer: [peer],
                commandId: commandId,
                success: false,
                error: failure.tryError.localizedDescription,
                torchMode: .off
            )
        }
    }
    
    /// Handle FlatBuffers flash toggle command
    private func handleFlatBuffersFlashToggle(_ command: RemoteShutter_CameraCommand, ctrl: CameraViewController, peer: MCPeerID) {
        print("⚡ Camera handling FlatBuffers flash toggle")
        
        let result = ctrl.toggleFlash()
        let commandId = command.id ?? UUID().uuidString
        
        if let flashMode = result.toOptional() {
            print("✅ Camera flash toggle success: \(flashMode)")
            self.sendFlatBuffersFlashStateResponse(
                peer: [peer],
                commandId: commandId,
                flashMode: flashMode,
                error: nil
            )
        } else if let failure = result as? Failure {
            print("❌ Camera flash toggle failed: \(failure.tryError)")
            self.sendFlatBuffersFlashStateResponse(
                peer: [peer],
                commandId: commandId,
                flashMode: nil,
                error: failure.tryError
            )
        }
    }
    
    /// Handle FlatBuffers camera toggle command
    private func handleFlatBuffersCameraToggle(_ command: RemoteShutter_CameraCommand, ctrl: CameraViewController, peer: MCPeerID) {
        print("📷 Camera handling FlatBuffers camera toggle")
        
        let result = ctrl.toggleCamera()
        let commandId = command.id ?? UUID().uuidString
        
        if let (flashMode, position) = result.toOptional() {
            print("✅ Camera toggle success")
            // For now, we'll send a simple success response
            // TODO: Implement proper capabilities gathering for FlatBuffers
            self.sendFlatBuffersCameraStateResponse(
                peer: [peer],
                commandId: commandId,
                capabilities: nil,
                error: nil
            )
        } else if let failure = result as? Failure {
            print("❌ Camera toggle failed: \(failure.tryError)")
            self.sendFlatBuffersCameraStateResponse(
                peer: [peer],
                commandId: commandId,
                capabilities: nil,
                error: failure.tryError
            )
        }
    }
    
    /// Handle FlatBuffers photo capture command
    private func handleFlatBuffersPhotoCapture(_ command: RemoteShutter_CameraCommand, ctrl: CameraViewController, peer: MCPeerID) {
        print("📸 Camera handling FlatBuffers photo capture")
        
        let sendToRemote = command.parameters?.sendToRemote ?? true
        let commandId = command.id ?? UUID().uuidString
        
        // Trigger photo capture
        ctrl.takePicture(sendToRemote)
        
        // Note: Response will be sent from cameraTakingPic state when photo is captured
        // For now, we'll send a simple success response
        let _ = self.sendFlatBuffersPhotoCaptureResponse(
            peer: [peer],
            commandId: commandId,
            photoData: nil,
            error: nil
        )
    }
    
    /// Handle FlatBuffers start recording command
    private func handleFlatBuffersStartRecording(_ command: RemoteShutter_CameraCommand, ctrl: CameraViewController, peer: MCPeerID) {
        print("🎬 Camera handling FlatBuffers start recording")
        
        let commandId = command.id ?? UUID().uuidString
        
        // Trigger video recording start
        ctrl.startRecordingVideo()
        
        // Note: Response will be sent from video recording states
        // For now, we'll send a simple success response
        let _ = self.sendFlatBuffersVideoRecordingResponse(
            peer: [peer],
            commandId: commandId,
            videoData: nil,
            error: nil
        )
    }
    
    /// Handle FlatBuffers stop recording command
    private func handleFlatBuffersStopRecording(_ command: RemoteShutter_CameraCommand, ctrl: CameraViewController, peer: MCPeerID) {
        print("🛑 Camera handling FlatBuffers stop recording")
        
        let sendToRemote = command.parameters?.sendToRemote ?? true
        let commandId = command.id ?? UUID().uuidString
        
        // Trigger video recording stop
        ctrl.stopRecordingVideo(sendToRemote)
        
        // Note: Response will be sent from video recording states
        // For now, we'll send a simple success response
        let _ = self.sendFlatBuffersVideoRecordingResponse(
            peer: [peer],
            commandId: commandId,
            videoData: nil,
            error: nil
        )
    }
    
    // MARK: - FlatBuffers Command State Tracking
    // Note: Extensions cannot have stored properties, so we'll track command IDs differently
    // For now, we'll use UUID().uuidString for responses until we implement proper state tracking

}
