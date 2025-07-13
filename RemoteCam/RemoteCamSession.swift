//
//  RemoteCamSession.swift
//  Actors
//
//  Created by Dario on 10/7/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation
import Theater
import MultipeerConnectivity
import FlatBuffers

func getFrameSender() -> ActorRef? {
    RemoteCamSystem.shared.selectActor(actorPath: "RemoteCam/user/FrameSender")
}

func getRemoteCamSession() -> ActorRef? {
    RemoteCamSystem.shared.selectActor(actorPath: "RemoteCam/user/RemoteCam Session")
}

public class RemoteCamSession: ViewCtrlActor<DeviceScannerViewController>, MCSessionDelegate {

    let states = RemoteCamStates()

    var session: MCSession!

    var mcAdvertiserAssistant: MCAdvertiserAssistant!

    public required init(context: ActorSystem, ref: ActorRef) {
        super.init(context: context, ref: ref)
    }

    override public func willStop() {
        if let adv = self.mcAdvertiserAssistant {
            adv.stop()
        }
        if let session = self.session {
            session.disconnect()
            session.delegate = nil
        }
    }

    override public func receiveWithCtrl(ctrl: Weak<DeviceScannerViewController>) -> Receive {
        return { [unowned self](msg: Message) in
            switch msg {
            case is UICmd.StartScanning:
                self.become(name: self.states.scanning, state: self.scanning(ctrl))

            default:
                self.receive(msg: msg)
            }
        }
    }

    func popAndStartScanning() {
        self.popToState(name: self.states.scanning)
    }

    func startScanning(lobby: DeviceScannerViewController) {
        assert(Thread.isMainThread == false, "can't be called from the main thread")
        ^{
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                self.session = MCSession(peer: lobby.peerID)
                self.session.delegate = self
                self.mcAdvertiserAssistant = MCAdvertiserAssistant(
                    serviceType: service, discoveryInfo: nil, session: self.session)
                self.mcAdvertiserAssistant.start()
            }
            lobby.navigationController?.popToViewController(lobby, animated: true)
            lobby.startScanning()
            CATransaction.commit()
        }
    }

    public func unableToProcessError(msg: Message) -> NSError {
        return NSError(
            domain: "Unable to process \(type(of: msg)) command, since \(UIDevice.current.name) is not in the camera screen.", code: 0, userInfo: nil)
    }

    override public func receive(msg: Actor.Message) {
        switch msg {

        case let m as UICmd.BecomeCamera:
            ^{
                m.ctrl.navigationController?.popViewController(animated: true)
            }

        case let m as UICmd.BecomeMonitor:
            m.sender! ! UICmd.BecomeMonitorFailed(sender: this)

        case is RemoteCmd.TakePic:
            let l = RemoteCmd.TakePicResp(sender: this, error: self.unableToProcessError(msg: msg))
            sendCommandOrGoToScanning(peer: self.session.connectedPeers, msg: l)
        case is RemoteCmd.ToggleCamera:
            let l = RemoteCmd.ToggleCameraResp(
                cameraCapabilities: nil, error: self.unableToProcessError(msg: msg)
            )
            self.sendCommandOrGoToScanning(peer: self.session.connectedPeers, msg: l)

        case is RemoteCmd.ToggleFlash:
            let l = RemoteCmd.ToggleFlashResp(
                flashMode: nil, error: self.unableToProcessError(msg: msg)
            )
            self.sendCommandOrGoToScanning(peer: self.session.connectedPeers, msg: l)
            
        // MARK: - Zoom and Lens Command Handling
        case is RemoteCmd.SetZoom:
            let l = RemoteCmd.SetZoomResp(
                zoomFactor: nil, currentLens: nil, zoomRange: nil, error: self.unableToProcessError(msg: msg)
            )
            self.sendCommandOrGoToScanning(peer: self.session.connectedPeers, msg: l)
            
        case is RemoteCmd.SwitchLens:
            print("❌ DEBUG: Session default handler received SwitchLens - NOT in camera state!")
            let l = RemoteCmd.SwitchLensResp(
                lensType: nil, availableLenses: nil, currentZoom: nil, zoomRange: nil, error: self.unableToProcessError(msg: msg)
            )
            print("🔍 DEBUG: Default handler sending empty SwitchLensResp with error: \(self.unableToProcessError(msg: msg).localizedDescription)")
            self.sendCommandOrGoToScanning(peer: self.session.connectedPeers, msg: l)
            
        case let capabilities as RemoteCmd.CameraCapabilitiesResp:
            // Forward capabilities to connected peers (monitor)
            print("🔍 DEBUG: Base session forwarding capabilities to peers")
            self.sendCommandOrGoToScanning(peer: self.session.connectedPeers, msg: capabilities)

        default:
            super.receive(msg: msg)
        }
    }

    @objc func image(image: UIImage,
                     didFinishSavingWithError error: ErrorPointer,
                     contextInfo: UnsafeRawPointer) {
        if let errorInstance = error,
           let nsError = errorInstance.pointee {
            this ! UICmd.FailedToSaveImage(sender: nil, error: nsError)
        }
    }

    public func sendMessage(peer: [MCPeerID],
                            msg: Actor.Message,
                            mode: MCSessionSendDataMode = .reliable) -> Try<Message> {
        assert(Thread.isMainThread == false, "can't be called from the main thread")
        do {
            let serializedMessage = try NSKeyedArchiver.archivedData(
                withRootObject: msg, requiringSecureCoding: false)
            try self.session.send(serializedMessage,
                    toPeers: peer,
                    with: mode)
            return Success(msg)
        } catch let error as NSError {
            print("sendMessage error \(error)")
            return Failure(error: error)
        }
    }
    
    // MARK: - FlatBuffers Message Sending
    
    /// Send FlatBuffers torch toggle command
    public func sendFlatBuffersTorchToggle(peer: [MCPeerID]) -> Try<Message> {
        assert(Thread.isMainThread == false, "can't be called from the main thread")
        
        do {
            let data = buildFlatBuffersTorchToggleCommand()
            try self.session.send(data, toPeers: peer, with: .reliable)
            
            print("📤 Sent FlatBuffers torch toggle command (\(data.count) bytes)")
            return Success(RemoteCmd.ToggleTorch()) // Return equivalent legacy command for compatibility
        } catch let error as NSError {
            print("❌ Failed to send FlatBuffers torch toggle: \(error)")
            return Failure(error: error)
        }
    }
    
    /// Send FlatBuffers torch mode command
    public func sendFlatBuffersTorchMode(peer: [MCPeerID], mode: AVCaptureDevice.TorchMode) -> Try<Message> {
        assert(Thread.isMainThread == false, "can't be called from the main thread")
        
        do {
            let data = buildFlatBuffersTorchModeCommand(mode: mode)
            try self.session.send(data, toPeers: peer, with: .reliable)
            
            print("📤 Sent FlatBuffers torch mode command (\(data.count) bytes)")
            return Success(RemoteCmd.SetTorch(torchMode: mode)) // Return equivalent legacy command
        } catch let error as NSError {
            print("❌ Failed to send FlatBuffers torch mode: \(error)")
            return Failure(error: error)
        }
    }
    
    /// Send FlatBuffers torch state response
    public func sendFlatBuffersTorchStateResponse(peer: [MCPeerID], commandId: String, success: Bool, error: String?, torchMode: AVCaptureDevice.TorchMode) -> Try<Message> {
        assert(Thread.isMainThread == false, "can't be called from the main thread")
        
        do {
            let data = buildFlatBuffersTorchStateResponse(
                commandId: commandId,
                success: success,
                error: error,
                torchMode: torchMode
            )
            try self.session.send(data, toPeers: peer, with: .reliable)
            
            print("📤 Sent FlatBuffers torch state response (\(data.count) bytes)")
            return Success(RemoteCmd.ToggleTorchResp(torchMode: torchMode, error: error != nil ? NSError(domain: error!, code: 0, userInfo: nil) : nil))
        } catch let error as NSError {
            print("❌ Failed to send FlatBuffers torch state response: \(error)")
            return Failure(error: error)
        }
    }
    
    // MARK: - FlatBuffers Message Building
    
    /// Build FlatBuffers torch toggle command
    private func buildFlatBuffersTorchToggleCommand() -> Data {
        var builder = FlatBufferBuilder(initialSize: 256)
        
        // Create command ID and timestamp
        let commandId = UUID().uuidString
        let idOffset = builder.create(string: commandId)
        let senderOffset = builder.create(string: UIDevice.current.name)
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        
        // Create camera command
        let commandOffset = RemoteShutter_CameraCommand.createCameraCommand(
            &builder,
            idOffset: idOffset,
            timestamp: timestamp,
            action: .toggletorch
        )
        
        // Create P2P message envelope
        let messageOffset = RemoteShutter_P2PMessage.createP2PMessage(
            &builder,
            idOffset: idOffset,
            timestamp: timestamp,
            type: .cameracommand,
            senderOffset: senderOffset,
            commandOffset: commandOffset
        )
        // Finish and return
        RemoteShutter_P2PMessage.finish(&builder, end: messageOffset)
        
        print("📦 Building FlatBuffers torch toggle command")
        print("📦 Builder sizedBuffer size: \(builder.sizedBuffer.size)")
        
        return builder.data
      
    }


    
    /// Build FlatBuffers torch mode command
    private func buildFlatBuffersTorchModeCommand(mode: AVCaptureDevice.TorchMode) -> Data {
        var builder = FlatBufferBuilder(initialSize: 256)
        
        // Create command ID and timestamp
        let commandId = UUID().uuidString
        let idOffset = builder.create(string: commandId)
        let senderOffset = builder.create(string: UIDevice.current.name)
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        
        // Convert torch mode
        let flatBuffersTorchMode: RemoteShutter_TorchMode
        switch mode {
        case .off: flatBuffersTorchMode = .off
        case .on: flatBuffersTorchMode = .on
        case .auto: flatBuffersTorchMode = .auto
        @unknown default: flatBuffersTorchMode = .off
        }
        
        // Create parameters
        let parametersOffset = RemoteShutter_CommandParameters.createCommandParameters(
            &builder,
            torchMode: flatBuffersTorchMode
        )
        
        // Create camera command
        let commandOffset = RemoteShutter_CameraCommand.createCameraCommand(
            &builder,
            idOffset: idOffset,
            timestamp: timestamp,
            action: .settorchmode,
            parametersOffset: parametersOffset
        )
        
        // Create P2P message envelope
        let messageOffset = RemoteShutter_P2PMessage.createP2PMessage(
            &builder,
            idOffset: idOffset,
            timestamp: timestamp,
            type: .cameracommand,
            senderOffset: senderOffset,
            commandOffset: commandOffset
        )
        
        // Finish and return
        RemoteShutter_P2PMessage.finish(&builder, end: messageOffset)
        return builder.data
    }
    
    /// Build FlatBuffers torch state response
    private func buildFlatBuffersTorchStateResponse(commandId: String, success: Bool, error: String?, torchMode: AVCaptureDevice.TorchMode) -> Data {
        var builder = FlatBufferBuilder(initialSize: 512)
        
        // Create strings
        let commandIdOffset = builder.create(string: commandId)
        let senderOffset = builder.create(string: UIDevice.current.name)
        let errorOffset = error != nil ? builder.create(string: error!) : Offset()
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        
        // Convert torch mode
        let flatBuffersTorchMode: RemoteShutter_TorchMode
        switch torchMode {
        case .off: flatBuffersTorchMode = .off
        case .on: flatBuffersTorchMode = .on
        case .auto: flatBuffersTorchMode = .auto
        @unknown default: flatBuffersTorchMode = .off
        }
        
        // Create simplified camera state with just torch info
        let cameraStateOffset = RemoteShutter_CameraState.createCameraState(
            &builder,
            currentCamera: .back, // Default for now
            currentLens: .wideangle, // Default for now
            zoomFactor: 1.0, // Default for now
            torchMode: flatBuffersTorchMode,
            flashMode: .off, // Default for now
            isRecording: false, // Default for now
            connectionStatus: .connected
        )
        
        // Create camera state response
        let responseOffset = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &builder,
            commandIdOffset: commandIdOffset,
            timestamp: timestamp,
            success: success,
            errorOffset: errorOffset,
            currentStateOffset: cameraStateOffset
        )
        
        // Create P2P message envelope
        let messageOffset = RemoteShutter_P2PMessage.createP2PMessage(
            &builder,
            idOffset: commandIdOffset,
            timestamp: timestamp,
            type: .camerastateresponse,
            senderOffset: senderOffset,
            responseOffset: responseOffset
        )
        
        // Finish and return
        RemoteShutter_P2PMessage.finish(&builder, end: messageOffset)
        return builder.data
    }

    public func sendCommandOrGoToScanning(peer: [MCPeerID],
                                          msg: Actor.Message,
                                          mode: MCSessionSendDataMode = .reliable) {
        assert(Thread.isMainThread == false, "can't be called from the main thread")
        
        // Debug log for SwitchLensResp
        if let switchResp = msg as? RemoteCmd.SwitchLensResp {
            print("🔍 DEBUG: sendCommandOrGoToScanning - SwitchLensResp being sent:")
            print("🔍 DEBUG: - Transmission lensType: \(switchResp.lensType?.displayName ?? "nil")")
            print("🔍 DEBUG: - Transmission error: \(switchResp.error?.localizedDescription ?? "nil")")
        }
        
        if self.sendMessage(peer: self.session.connectedPeers, msg: msg).isFailure() {
            print("❌ DEBUG: sendCommandOrGoToScanning failed to send message")
            self.popToState(name: self.states.scanning)
            ^{
            let alert = UIAlertController(
                title: NSLocalizedString("Connection error", comment: ""),
                message: NSLocalizedString("Peer disconnected, please reconnect", comment: ""),
                preferredStyle: .alert)

                alert.simpleOkAction()
                alert.show(true)
            }
        } else {
//            print("✅ DEBUG: sendCommandOrGoToScanning successfully sent message")
        }
    }
}
