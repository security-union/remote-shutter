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
//        print("📨 Received data from \(peerID.displayName): \(data.count) bytes")
        
        // Try FlatBuffers first (modern system)
        if let flatBuffersMessage = tryParseFlatBuffersMessage(data) {
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
        }
        
        do {
            var buffer = ByteBuffer(data: data)
            let message: RemoteShutter_P2PMessage = try getCheckedRoot(byteBuffer: &buffer, fileId: RemoteShutter_P2PMessage.id)
            
            guard message.timestamp > 0 else { 
                print("🔍 Invalid timestamp, rejecting message")
                return nil 
            }
            
//            print("📥 Received FlatBuffers \(message.type) message (\(data.count) bytes)")
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
//        print("🎯 Processing FlatBuffers camera command: \(command.action)")
        
        switch command.action {
        case .toggletorch:
            // Handle directly with FlatBuffers (no legacy conversion needed)
            handleFlatBuffersTorchToggle(command, from: peerID)
            
        case .settorchmode:
            // Handle directly with FlatBuffers (no legacy conversion needed)
            handleFlatBuffersSetTorchMode(command, from: peerID)
            
        case .takepicture:
            // Handle directly with FlatBuffers (no legacy conversion needed)
            handleFlatBuffersPhotoCapture(command, from: peerID)
            
        case .togglecamera:
            // Handle directly with FlatBuffers (no legacy conversion needed)
            handleFlatBuffersCameraToggle(command, from: peerID)
            
        case .toggleflash:
            // Handle directly with FlatBuffers (no legacy conversion needed)
            handleFlatBuffersFlashToggle(command, from: peerID)
            
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
            // Handle directly with FlatBuffers (no legacy conversion needed)
            handleFlatBuffersStartRecording(command, from: peerID)
            
        case .stoprecording:
            // Handle directly with FlatBuffers (no legacy conversion needed)
            handleFlatBuffersStopRecording(command, from: peerID)
            
        case .requestcapabilities:
            let legacyCommand = RemoteCmd.RequestCameraCapabilities()
            this ! legacyCommand
            
        case .setflashmode:
            // Handle directly with FlatBuffers (no legacy conversion needed)
            this ! FlatBuffersCameraCommand(command: command)
            
        case .requestframe:
            // Handle directly with FlatBuffers (no legacy conversion needed)
            this ! FlatBuffersCameraCommand(command: command)
        }
    }
    
    /// Handle FlatBuffers camera state response (send directly to monitor)
    private func handleFlatBuffersCameraStateResponse(_ response: RemoteShutter_CameraStateResponse, from peerID: MCPeerID) {
        print("📥 Processing FlatBuffers camera state response")
        
        // Send FlatBuffers response directly to monitor states
        this ! FlatBuffersCameraStateResponse(response: response)
    }
    
    /// Handle FlatBuffers frame data
    private func handleFlatBuffersFrameData(_ frameData: RemoteShutter_FrameData, from peerID: MCPeerID) {
        // Send FlatBuffers frame data directly to monitor states
        this ! FlatBuffersFrameData(frameData: frameData)
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
    
    // MARK: - Direct FlatBuffers Command Handlers
    
    private func handleFlatBuffersTorchToggle(_ command: RemoteShutter_CameraCommand, from peerID: MCPeerID) {
        this ! FlatBuffersCameraCommand(command: command)
    }
    
    private func handleFlatBuffersPhotoCapture(_ command: RemoteShutter_CameraCommand, from peerID: MCPeerID) {
        this ! FlatBuffersCameraCommand(command: command)
    }
    
    private func handleFlatBuffersCameraToggle(_ command: RemoteShutter_CameraCommand, from peerID: MCPeerID) {
        this ! FlatBuffersCameraCommand(command: command)
    }
    
    private func handleFlatBuffersFlashToggle(_ command: RemoteShutter_CameraCommand, from peerID: MCPeerID) {
        this ! FlatBuffersCameraCommand(command: command)
    }
    
    private func handleFlatBuffersStartRecording(_ command: RemoteShutter_CameraCommand, from peerID: MCPeerID) {
        this ! FlatBuffersCameraCommand(command: command)
    }
    
    private func handleFlatBuffersStopRecording(_ command: RemoteShutter_CameraCommand, from peerID: MCPeerID) {
        this ! FlatBuffersCameraCommand(command: command)
    }
    
    private func handleFlatBuffersSetTorchMode(_ command: RemoteShutter_CameraCommand, from peerID: MCPeerID) {
        this ! FlatBuffersCameraCommand(command: command)
    }
}
