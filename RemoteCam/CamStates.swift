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
                         sendMediaToPeer: Bool,
                         commandId: String? = nil) -> Receive {
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
                // Send FlatBuffers response with correct command ID
                let _ = self.sendFlatBuffersPhotoCaptureResponse(
                    peer: [peer],
                    commandId: commandId ?? UUID().uuidString,
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
                // FrameSender no longer needed - frames are sent directly from CameraViewController
                
            case let frameMsg as UICmd.OnFrame:
                // Handle frame data from CameraViewController and send to all connected peers
                self.sendFlatBuffersFrameData(
                    peer: self.session.connectedPeers,
                    frameData: frameMsg.frameData,
                    fps: frameMsg.fps,
                    cameraPosition: frameMsg.cameraPosition,
                    orientation: frameMsg.orientation
                )
                
            case is FlatBuffersPeerBecameMonitor:
                // When a new monitor joins, immediately send camera capabilities
                print("🔍 DEBUG: Camera received FlatBuffers PeerBecameMonitor - attempting to send capabilities")
                self.attemptToSendCapabilities(ctrl: ctrl, peer: peer, attempt: 1, maxAttempts: 5)
                
            case is RemoteCmd.RequestCameraCapabilities:
                // When monitor explicitly requests capabilities
                print("🔍 DEBUG: Camera received RequestCameraCapabilities - attempting to gather capabilities")
                self.attemptToSendCapabilities(ctrl: ctrl, peer: peer, attempt: 1, maxAttempts: 5)
                

                







                

                

                

                
            // MARK: - Legacy zoom command handling removed - now handled via FlatBuffers
                
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
//                print("🔍 DEBUG: Camera received FlatBuffers command: \(fbCommand.command.action)")
                self.handleFlatBuffersCameraCommand(fbCommand.command, ctrl: ctrl, peer: peer, lobbyWrapper: lobbyWrapper)

            default:
                self.receive(msg: msg)
            }
        }
    }
    
    // MARK: - FlatBuffers Command Handling
    
    /// Handle FlatBuffers camera commands
    private func handleFlatBuffersCameraCommand(_ command: RemoteShutter_CameraCommand, ctrl: CameraViewController, peer: MCPeerID, lobbyWrapper: Weak<DeviceScannerViewController>) {
//        print("🎯 Camera processing FlatBuffers command: \(command.action)")
        
        switch command.action {
        case .toggletorch:
            handleFlatBuffersTorchToggle(command, ctrl: ctrl, peer: peer)
            
        case .settorchmode:
            handleFlatBuffersSetTorchMode(command, ctrl: ctrl, peer: peer)
            
        case .toggleflash:
            handleFlatBuffersFlashToggle(command, ctrl: ctrl, peer: peer)
            
        case .togglecamera:
            handleFlatBuffersCameraToggle(command, ctrl: ctrl, peer: peer)
            
        case .takepicture:
            handleFlatBuffersPhotoCapture(command, ctrl: ctrl, peer: peer, lobbyWrapper: lobbyWrapper)
            
        case .startrecording:
            handleFlatBuffersStartRecording(command, ctrl: ctrl, peer: peer, lobbyWrapper: lobbyWrapper)
            
        case .stoprecording:
            handleFlatBuffersStopRecording(command, ctrl: ctrl, peer: peer, lobbyWrapper: lobbyWrapper)
            
        case .requestframe:
            handleFlatBuffersFrameRequest(command, ctrl: ctrl, peer: peer)
            
        case .setzoom:
            handleFlatBuffersSetZoom(command, ctrl: ctrl, peer: peer)
            
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
                torchMode: torchMode,
                ctrl: ctrl
            )
        } else if let failure = result as? Failure {
            print("❌ Camera torch toggle failed: \(failure.tryError)")
            let _ = self.sendFlatBuffersTorchStateResponse(
                peer: [peer],
                commandId: commandId,
                success: false,
                error: failure.tryError.localizedDescription,
                torchMode: .off,
                ctrl: ctrl
            )
        }
    }
    
    /// Handle FlatBuffers set torch mode command
    private func handleFlatBuffersSetTorchMode(_ command: RemoteShutter_CameraCommand, ctrl: CameraViewController, peer: MCPeerID) {
        print("🔦 Camera handling FlatBuffers set torch mode")
        
        guard let params = command.parameters else {
            print("❌ Camera set torch mode failed: missing parameters")
            return
        }
        
        let torchMode: AVCaptureDevice.TorchMode
        switch params.torchMode {
        case .off: torchMode = .off
        case .on: torchMode = .on
        case .auto: torchMode = .auto
        }
        
        let result = ctrl.setTorchMode(mode: torchMode)
        let commandId = command.id ?? UUID().uuidString
        
        if let resultTorchMode = result.toOptional() {
            print("✅ Camera set torch mode success: \(resultTorchMode)")
            let _ = self.sendFlatBuffersTorchStateResponse(
                peer: [peer],
                commandId: commandId,
                success: true,
                error: nil,
                torchMode: resultTorchMode,
                ctrl: ctrl
            )
        } else if let failure = result as? Failure {
            print("❌ Camera set torch mode failed: \(failure.tryError)")
            let _ = self.sendFlatBuffersTorchStateResponse(
                peer: [peer],
                commandId: commandId,
                success: false,
                error: failure.tryError.localizedDescription,
                torchMode: .off,
                ctrl: ctrl
            )
        }
    }
    
    /// Handle FlatBuffers flash toggle command
    private func handleFlatBuffersFlashToggle(_ command: RemoteShutter_CameraCommand, ctrl: CameraViewController, peer: MCPeerID) {
        print("⚡ Camera handling FlatBuffers flash toggle")
        
        let result = ctrl.toggleFlash()
        let commandId = command.id ?? UUID().uuidString
        
        // Gather current camera capabilities to include in response
        let capabilities = ctrl.gatherCurrentCameraCapabilities()
        
        if let flashMode = result.toOptional() {
            print("✅ Camera flash toggle success: \(flashMode)")
            self.sendFlatBuffersFlashStateResponse(
                peer: [peer],
                commandId: commandId,
                flashMode: flashMode,
                error: nil,
                capabilities: capabilities
            )
        } else if let failure = result as? Failure {
            print("❌ Camera flash toggle failed: \(failure.tryError)")
            self.sendFlatBuffersFlashStateResponse(
                peer: [peer],
                commandId: commandId,
                flashMode: nil,
                error: failure.tryError,
                capabilities: capabilities
            )
        }
    }
    
    /// Handle FlatBuffers camera toggle command
    private func handleFlatBuffersCameraToggle(_ command: RemoteShutter_CameraCommand, ctrl: CameraViewController, peer: MCPeerID) {
        print("📷 Camera handling FlatBuffers camera toggle")
        
        let result = ctrl.toggleCamera()
        let commandId = command.id ?? UUID().uuidString
        
        // Gather current camera capabilities to include in response
        let capabilities = ctrl.gatherCurrentCameraCapabilities()
        
        if let (_, _) = result.toOptional() {
            print("✅ Camera toggle success")
            self.sendFlatBuffersCameraStateResponse(
                peer: [peer],
                commandId: commandId,
                capabilities: capabilities,
                error: nil,
                cameraController: ctrl
            )
        } else if let failure = result as? Failure {
            print("❌ Camera toggle failed: \(failure.tryError)")
            self.sendFlatBuffersCameraStateResponse(
                peer: [peer],
                commandId: commandId,
                capabilities: capabilities,
                error: failure.tryError,
                cameraController: ctrl
            )
        }
    }
    
    /// Handle FlatBuffers photo capture command
    private func handleFlatBuffersPhotoCapture(_ command: RemoteShutter_CameraCommand, ctrl: CameraViewController, peer: MCPeerID, lobbyWrapper: Weak<DeviceScannerViewController>) {
        print("📸 Camera handling FlatBuffers photo capture")
        
        let sendToRemote = command.parameters?.sendToRemote ?? true
        let commandId = command.id ?? UUID().uuidString
        
        // Transition to taking picture state with FlatBuffers command context
        self.become(
            name: self.states.cameraTakingPic,
            state: self.cameraTakingPic(
                peer: peer,
                ctrl: ctrl,
                lobby: lobbyWrapper,
                sendMediaToPeer: sendToRemote,
                commandId: commandId  // Pass the command ID for FlatBuffers response
            )
        )
        
        // Trigger photo capture
        ctrl.takePicture(sendToRemote)
    }
    
    /// Handle FlatBuffers start recording command
    private func handleFlatBuffersStartRecording(_ command: RemoteShutter_CameraCommand, ctrl: CameraViewController, peer: MCPeerID, lobbyWrapper: Weak<DeviceScannerViewController>) {
        print("🎬 Camera handling FlatBuffers start recording")
        
        let commandId = command.id ?? UUID().uuidString
        
        // Trigger video recording start
        ctrl.startRecordingVideo()
        
        // Transition to video recording state
        self.become(
            name: self.states.cameraRecordingVideo,
            state: self.cameraShootingVideo(peer: peer, ctrl: ctrl, lobby: lobbyWrapper)
        )
        
        // Send acknowledgment that recording has started
        let _ = self.sendFlatBuffersVideoRecordingResponse(
            peer: [peer],
            commandId: commandId,
            videoData: nil,
            error: nil
        )
    }
    
    /// Handle FlatBuffers stop recording command
    private func handleFlatBuffersStopRecording(_ command: RemoteShutter_CameraCommand, ctrl: CameraViewController, peer: MCPeerID, lobbyWrapper: Weak<DeviceScannerViewController>) {
        print("🛑 Camera handling FlatBuffers stop recording")
        
        let sendToRemote = command.parameters?.sendToRemote ?? true
        let commandId = command.id ?? UUID().uuidString
        
        // Trigger video recording stop
        ctrl.stopRecordingVideo(sendToRemote)
        
        // Transition to video transmitting state to wait for video data
        self.become(
            name: self.states.cameraTransmittingVideo,
            state: self.cameraTransmittingVideo(peer: peer, ctrl: ctrl, lobby: lobbyWrapper, commandId: commandId)
        )
        
        // The actual response with video data will be sent from cameraTransmittingVideo state
        // when CameraViewController calls back with the video data
    }
    
    /// Handle FlatBuffers frame request command
    private func handleFlatBuffersFrameRequest(_ command: RemoteShutter_CameraCommand, ctrl: CameraViewController, peer: MCPeerID) {
        // Frame requests are handled automatically by the continuous frame sending in CameraViewController
        // No specific action needed - frames are sent continuously to all connected peers
//        print("📸 Camera received frame request - frames are sent continuously")
    }
    
    // MARK: - FlatBuffers Command State Tracking
    // Note: Extensions cannot have stored properties, so we'll track command IDs differently
    // For now, we'll use UUID().uuidString for responses until we implement proper state tracking
    
    private func handleFlatBuffersSetZoom(_ command: RemoteShutter_CameraCommand, ctrl: CameraViewController, peer: MCPeerID) {
        guard let params = command.parameters else {
            print("❌ DEBUG: FlatBuffers SetZoom command missing parameters")
            return
        }
        
        let result = ctrl.setZoom(zoomFactor: CGFloat(params.zoomFactor))
        
        if let (zoomFactor, currentLens, zoomRange) = result.toOptional() {
            
            // Get real camera capabilities
            let capabilities = ctrl.gatherCurrentCameraCapabilities()
            let currentCamera = capabilities?.currentCamera ?? .back
            let actualCurrentLens = capabilities?.currentLens ?? currentLens
            let actualCurrentZoom = capabilities?.currentZoom ?? zoomFactor
            
            // Create successful response with real camera data
            let responseData = buildFlatBuffersZoomResponse(
                commandId: command.id ?? "",
                success: true,
                zoomFactor: Float(actualCurrentZoom),
                currentLens: actualCurrentLens,
                currentCamera: currentCamera,
                zoomRange: zoomRange,
                capabilities: capabilities,
                cameraController: ctrl
            )
            
            // Parse the response data to get the FlatBuffers object
            let responseObj = parseFlatBuffersResponse(data: responseData)
            // Send FlatBuffers data directly
            do {
                try self.session.send(responseData, toPeers: [peer], with: .reliable)
            } catch {
                print("📤 ❌ Failed to send FlatBuffers zoom response: \(error)")
            }
        } else if let failure = result as? Failure {
            print("❌ DEBUG: Camera zoom failed: \(failure.tryError.localizedDescription)")
            
            // Create error response with real camera data
            let capabilities = ctrl.gatherCurrentCameraCapabilities()
            let responseData = buildFlatBuffersZoomResponse(
                commandId: command.id ?? "",
                success: false,
                errorMessage: failure.tryError.localizedDescription,
                capabilities: capabilities,
                cameraController: ctrl
            )
            
            // Parse the response data to get the FlatBuffers object
            let responseObj = parseFlatBuffersResponse(data: responseData)
            self.sendCommandOrGoToScanning(peer: [peer], msg: FlatBuffersCameraStateResponse(response: responseObj))
        }
    }
    
    /// Build FlatBuffers zoom response using real camera data
    private func buildFlatBuffersZoomResponse(
        commandId: String, 
        success: Bool, 
        zoomFactor: Float = 0.0, 
        currentLens: CameraLensType = .wideAngle,
        currentCamera: AVCaptureDevice.Position = .back,
        zoomRange: RemoteCmd.ZoomRange = RemoteCmd.ZoomRange(minZoom: 1.0, maxZoom: 1.0), 
        errorMessage: String = "",
        capabilities: RemoteCmd.CameraCapabilitiesResp? = nil,
        cameraController: CameraViewController? = nil
    ) -> Data {
        var builder = FlatBufferBuilder(initialSize: 512)
        
        let commandIdOffset = builder.create(string: commandId)
        let senderOffset = builder.create(string: UIDevice.current.name)
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        
        // Create current state with real camera data
        var currentStateOffset = Offset()
        if let capabilities = capabilities {
            // Use real camera data from capabilities
            let realCurrentCamera: RemoteShutter_CameraPosition = capabilities.currentCamera == .front ? .front : .back
            let realCurrentLens = convertLensTypeToFlatBuffers(capabilities.currentLens)
            let realZoomFactor = success ? Double(zoomFactor) : Double(capabilities.currentZoom)
            
            // Get real camera info for current camera
            let currentCameraInfo = capabilities.currentCamera == .front ? capabilities.frontCamera : capabilities.backCamera
            let _ = currentCameraInfo?.hasFlash ?? false  // TODO: Use for flash capability in response
            let _ = currentCameraInfo?.hasTorch ?? false  // TODO: Use for torch capability in response
            
            // Get real values from camera controller if available
            let realTorchMode: RemoteShutter_TorchMode
            let realFlashMode: RemoteShutter_FlashMode
            let realIsRecording: Bool
            
            if let cameraController = cameraController {
                // Get real torch mode
                let avTorchMode = cameraController.getCurrentTorchMode()
                switch avTorchMode {
                case .off: realTorchMode = .off
                case .on: realTorchMode = .on
                case .auto: realTorchMode = .auto
                @unknown default: realTorchMode = .off
                }
                
                // Get real flash mode
                let avFlashMode = cameraController.cameraSettings.flashMode
                switch avFlashMode {
                case .off: realFlashMode = .off
                case .on: realFlashMode = .on
                case .auto: realFlashMode = .auto
                @unknown default: realFlashMode = .off
                }
                
                // Get real recording state
                realIsRecording = cameraController.isRecording
            } else {
                // Fallback to defaults if no camera controller available
                realTorchMode = .off
                realFlashMode = .off
                realIsRecording = false
            }
            
            currentStateOffset = RemoteShutter_CameraState.createCameraState(
                &builder,
                currentCamera: realCurrentCamera,
                currentLens: realCurrentLens,
                zoomFactor: realZoomFactor,
                torchMode: realTorchMode,
                flashMode: realFlashMode,
                isRecording: realIsRecording,
                connectionStatus: .connected
            )
        } else if success {
            // Fallback with limited real data when capabilities unavailable
            let fbLensType = convertLensTypeToFlatBuffers(currentLens)
            let fbCamera: RemoteShutter_CameraPosition = currentCamera == .front ? .front : .back
            
            currentStateOffset = RemoteShutter_CameraState.createCameraState(
                &builder,
                currentCamera: fbCamera,
                currentLens: fbLensType,
                zoomFactor: Double(zoomFactor),
                torchMode: .off,
                flashMode: .off,
                isRecording: false,
                connectionStatus: .connected
            )
        }
        
        // Create error message if failed
        let errorOffset = builder.create(string: errorMessage)
        
        // Create response
        let responseOffset = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &builder,
            commandIdOffset: commandIdOffset,
            timestamp: timestamp,
            success: success,
            errorOffset: errorOffset,
            currentStateOffset: success ? currentStateOffset : Offset()
        )
        
        // Create message
        let messageOffset = RemoteShutter_P2PMessage.createP2PMessage(
            &builder,
            idOffset: Offset(),
            timestamp: timestamp,
            type: .camerastateresponse,
            senderOffset: senderOffset,
            responseOffset: responseOffset
        )
        
        RemoteShutter_P2PMessage.finish(&builder, end: messageOffset)
        return builder.data
    }
    
    /// Parse FlatBuffers response data back to RemoteShutter_CameraStateResponse
    private func parseFlatBuffersResponse(data: Data) -> RemoteShutter_CameraStateResponse {
        let buffer = ByteBuffer(data: data)
        let message = RemoteShutter_P2PMessage(buffer, o: Int32(buffer.read(def: UOffset.self, position: buffer.reader)) + Int32(buffer.reader))
        return message.response!
    }
    
    /// Convert lens type to FlatBuffers format
    private func convertLensTypeToFlatBuffers(_ lensType: CameraLensType) -> RemoteShutter_CameraLensType {
        switch lensType {
        case .wideAngle:
            return .wideangle
        case .telephoto:
            return .telephoto
        case .ultraWide:
            return .ultrawide
        case .dualCamera:
            return .dualcamera
        }
    }

}
