//
//  MultipeerDelegate.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 10/10/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import Theater
import MultipeerConnectivity
import FlatBuffers

let AppStoreURL = URL(string: "https://apps.apple.com/us/app/remote-shutter/id633274861")!

extension RemoteCamSession {
    func showIncopatibilityMessage() {
        self.popAndStartScanning()
        ^{
            let alert = UIAlertController(
                title: "App is out of date",
                message: "Please update Remote Shutter on both devices.")
            alert.addAction(UIAlertAction.init(title: "Update", style: .default) {_ in
                UIApplication.shared.open(AppStoreURL, options: [:], completionHandler: nil)
                
            })
            alert.show(true)
        }
    }

    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        mailbox.addOperation(BlockOperation {
            switch state {
            case MCSessionState.connected:
                self.this ! OnConnectToDevice(peer: peerID, sender: self.this)
                print("Connected: \(peerID.displayName)")

            case MCSessionState.connecting:
                print("Connecting: \(peerID.displayName)")

            case MCSessionState.notConnected:
                self.this ! DisconnectPeer(peer: peerID, sender: self.this)
                print("Not Connected: \(peerID.displayName)")
            @unknown default:
                fatalError()
            }
        })
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        print("📨 Received data from \(peerID.displayName): \(data.count) bytes")
        
        // Try FlatBuffers first (modern system)
        if let flatBuffersMessage = tryParseFlatBuffersMessage(data) {
            print("✅ Successfully parsed as FlatBuffers message")
            handleFlatBuffersMessage(flatBuffersMessage, from: peerID)
            return
        }
        
        print("⚠️ FlatBuffers parsing failed, trying NSCoding...")
        
        // Fall back to NSCoding (legacy system)
        guard let inboundMessage = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) else {
            print("❌ NSCoding parsing also failed")
            showIncopatibilityMessage()
            return
        }
        
        print("✅ Successfully parsed as NSCoding message: \(type(of: inboundMessage))")
        
        // Handle legacy NSCoding messages
        switch inboundMessage {
        case let requestFrame as RemoteCmd.RequestFrame:
            getFrameSender()?.tell(msg: requestFrame)

        case let frame as RemoteCmd.SendFrame:
            this ! RemoteCmd.OnFrame(data: frame.data,
                sender: nil,
                peerId: peerID,
                fps: frame.fps,
                camPosition: frame.camPosition,
                camOrientation: frame.camOrientation)

        case let m as Message:
            this ! m

        default:
            print("unable to unarchive")
        }
    }
    
    // MARK: - FlatBuffers Support
    
    /// Try to parse incoming data as FlatBuffers message
    private func tryParseFlatBuffersMessage(_ data: Data) -> RemoteShutter_P2PMessage? {
        // Check if this looks like FlatBuffers data
        if data.count >= 8 {
            // FlatBuffers file ID is typically at the end of the buffer
            let lastFourBytes = data.suffix(4)
            let fileIdString = String(data: lastFourBytes, encoding: .ascii) ?? "N/A"
            print("🔍 Last 4 bytes as ASCII: '\(fileIdString)'")
            print("🔍 Last 4 bytes as hex: \(lastFourBytes.map { String(format: "%02x", $0) }.joined(separator: " "))")
        }
        
        // Quick heuristic: FlatBuffers messages should be at least 8 bytes and have proper alignment
        guard data.count >= 8 else {
            print("🔍 Data too small for FlatBuffers, skipping")
            return nil
        }
        
        // Check if this looks like NSCoding data (starts with common NSCoding magic bytes)
        let firstBytes = data.prefix(4)
        if firstBytes.starts(with: [0x62, 0x70, 0x6c, 0x69]) || // "bpli" - binary plist
           firstBytes.starts(with: [0x4e, 0x53, 0x4b, 0x65]) // "NSKe" - NSKeyedArchiver
            { // Common NSCoding indicator
            print("🔍 Data appears to be NSCoding format, skipping FlatBuffers")
            return nil
        }
        
        do {
            var buffer = ByteBuffer(data: data)
            let message: RemoteShutter_P2PMessage = try getCheckedRoot(byteBuffer: &buffer, fileId: RemoteShutter_P2PMessage.id)
            print("🔍 Successfully created P2PMessage")
            
            // Basic validation
            print("🔍 Message timestamp: \(message.timestamp)")
            print("🔍 Message type: \(message.type)")
            print("🔍 Message id: \(message.id ?? "nil")")
            print("🔍 Message sender: \(message.sender ?? "nil")")
            
            guard message.timestamp > 0 else { 
                print("🔍 Invalid timestamp, rejecting message")
                return nil 
            }
            
            print("📥 Received FlatBuffers \(message.type) message (\(data.count) bytes)")
            return message
        } catch {
            print("🔍 FlatBuffers deserialization failed: \(error)")
            print("🔍 Error type: \(type(of: error))")
            // Not a FlatBuffers message, will try NSCoding
            return nil
        }
    }
    
    /// Handle incoming FlatBuffers message
    private func handleFlatBuffersMessage(_ message: RemoteShutter_P2PMessage, from peerID: MCPeerID) {
        switch message.type {
        case .cameracommand:
            if let command = message.command {
                handleFlatBuffersCameraCommand(command, from: peerID)
            }
            
        case .camerastateresponse:
            if let response = message.response {
                handleFlatBuffersCameraStateResponse(response, from: peerID)
            }
            
        case .framedata:
            if let frameData = message.frameData {
                handleFlatBuffersFrameData(frameData, from: peerID)
            }
            
        default:
            print("⚠️ Unhandled FlatBuffers message type: \(message.type)")
        }
    }
    
    /// Convert FlatBuffers camera command to legacy command and route to state machine
    private func handleFlatBuffersCameraCommand(_ command: RemoteShutter_CameraCommand, from peerID: MCPeerID) {
        print("🎯 Processing FlatBuffers camera command: \(command.action)")
        
        switch command.action {
        case .toggletorch:
            // Convert to legacy command for now
            let legacyCommand = RemoteCmd.ToggleTorch()
            this ! legacyCommand
            
        case .settorchmode:
            // Convert to legacy command
            if let params = command.parameters {
                let torchMode = params.torchMode
                let avMode: AVCaptureDevice.TorchMode
                switch torchMode {
                case .off: avMode = .off
                case .on: avMode = .on
                case .auto: avMode = .auto
                }
                let legacyCommand = RemoteCmd.SetTorch(torchMode: avMode)
                this ! legacyCommand
            }
            
        case .takepicture:
            let sendToRemote = command.parameters?.sendToRemote ?? true
            let legacyCommand = RemoteCmd.TakePic(sender: nil, sendMediaToPeer: sendToRemote)
            this ! legacyCommand
            
        case .togglecamera:
            let legacyCommand = RemoteCmd.ToggleCamera()
            this ! legacyCommand
            
        case .toggleflash:
            let legacyCommand = RemoteCmd.ToggleFlash()
            this ! legacyCommand
            
        case .setzoom:
            if let params = command.parameters {
                let legacyCommand = RemoteCmd.SetZoom(zoomFactor: CGFloat(params.zoomFactor))
                this ! legacyCommand
            }
            
        case .switchlens:
            if let params = command.parameters {
                let lensType = convertFlatBuffersLensType(params.lensType)
                let legacyCommand = RemoteCmd.SwitchLens(lensType: lensType)
                this ! legacyCommand
            }
            
        case .startrecording:
            let legacyCommand = RemoteCmd.StartRecordingVideo(sender: nil)
            this ! legacyCommand
            
        case .stoprecording:
            let sendToRemote = command.parameters?.sendToRemote ?? true
            let legacyCommand = RemoteCmd.StopRecordingVideo(sender: nil, sendMediaToPeer: sendToRemote)
            this ! legacyCommand
            
        case .requestcapabilities:
            let legacyCommand = RemoteCmd.RequestCameraCapabilities()
            this ! legacyCommand
            
        case .setflashmode:
            // SetFlashMode doesn't exist in legacy system, use ToggleFlash instead
            let legacyCommand = RemoteCmd.ToggleFlash()
            this ! legacyCommand
        }
    }
    
    /// Handle FlatBuffers camera state response (convert to legacy response)
    private func handleFlatBuffersCameraStateResponse(_ response: RemoteShutter_CameraStateResponse, from peerID: MCPeerID) {
        print("📥 Processing FlatBuffers camera state response")
        
        // For now, we'll focus on torch responses
        if let _ = response.commandId,
           let currentState = response.currentState {
            
            // Convert torch mode response
            let torchMode = currentState.torchMode
            let avTorchMode: AVCaptureDevice.TorchMode
            switch torchMode {
            case .off: avTorchMode = .off
            case .on: avTorchMode = .on
            case .auto: avTorchMode = .auto
            }
            
            // Create legacy response
            let error = response.success ? nil : NSError(domain: response.error ?? "Unknown error", code: 0, userInfo: nil)
            let legacyResponse = RemoteCmd.ToggleTorchResp(torchMode: avTorchMode, error: error)
            this ! legacyResponse
        }
    }
    
    /// Handle FlatBuffers frame data
    private func handleFlatBuffersFrameData(_ frameData: RemoteShutter_FrameData, from peerID: MCPeerID) {
        let data = Data(frameData.imageData)
        let position = frameData.cameraPosition == .back ? AVCaptureDevice.Position.back : AVCaptureDevice.Position.front
        
        this ! RemoteCmd.OnFrame(
            data: data,
            sender: nil,
            peerId: peerID,
            fps: Int(frameData.fps),
            camPosition: position,
            camOrientation: .portrait // Default orientation for now
        )
    }
    
    /// Convert FlatBuffers lens type to legacy lens type
    private func convertFlatBuffersLensType(_ lensType: RemoteShutter_CameraLensType) -> CameraLensType {
        switch lensType {
        case .wideangle: return .wideAngle
        case .ultrawide: return .ultraWide
        case .telephoto: return .telephoto
        case .dualcamera: return .dualCamera
        }
    }
    
    /// Send FlatBuffers message to peers
    public func sendFlatBuffersMessage(_ data: Data, to peers: [MCPeerID]) -> Bool {
        do {
            try session.send(data, toPeers: peers, with: .reliable)
            return true
        } catch {
            print("❌ Failed to send FlatBuffers message: \(error)")
            return false
        }
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {

    }

    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {

    }

    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {

    }

    @nonobjc public func session(session: MCSession, didReceiveCertificate certificate: [AnyObject]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        certificateHandler(true)
    }
}
