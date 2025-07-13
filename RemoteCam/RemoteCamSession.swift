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


            
        // MARK: - Zoom and Lens Command Handling
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
            return Success(Actor.Message())
        } catch let error as NSError {
            print("❌ Failed to send FlatBuffers torch toggle: \(error)")
            return Failure(error: error)
        }
    }
    
    /// Send FlatBuffers set zoom command
    public func sendFlatBuffersSetZoom(peer: [MCPeerID], zoomFactor: CGFloat) {
        assert(Thread.isMainThread == false, "can't be called from the main thread")
        
        do {
            let data = buildFlatBuffersSetZoomCommand(zoomFactor: zoomFactor)
            try self.session.send(data, toPeers: peer, with: .reliable)
            
        } catch let error as NSError {
            print("❌ Failed to send FlatBuffers set zoom: \(error)")
        }
    }
    
    /// Send FlatBuffers torch mode command
    public func sendFlatBuffersTorchMode(peer: [MCPeerID], mode: AVCaptureDevice.TorchMode) -> Try<Message> {
        assert(Thread.isMainThread == false, "can't be called from the main thread")
        
        do {
            let data = buildFlatBuffersTorchModeCommand(mode: mode)
            try self.session.send(data, toPeers: peer, with: .reliable)
            
            print("📤 Sent FlatBuffers torch mode command (\(data.count) bytes)")
            return Success(Actor.Message())
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
            return Success(Actor.Message())
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
    
    /// Build FlatBuffers set zoom command
    private func buildFlatBuffersSetZoomCommand(zoomFactor: CGFloat) -> Data {
        var builder = FlatBufferBuilder(initialSize: 256)
        
        // Create command ID and timestamp
        let commandId = UUID().uuidString
        let idOffset = builder.create(string: commandId)
        let senderOffset = builder.create(string: UIDevice.current.name)
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        
        // Create parameters with zoom factor
        let parametersOffset = RemoteShutter_CommandParameters.createCommandParameters(
            &builder,
            zoomFactor: Double(zoomFactor)
        )
        
        // Create camera command
        let commandOffset = RemoteShutter_CameraCommand.createCameraCommand(
            &builder,
            idOffset: idOffset,
            timestamp: timestamp,
            action: .setzoom,
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
    
    // MARK: - FlatBuffers Flash Toggle Methods
    
    /// Send FlatBuffers flash toggle command
    public func sendFlatBuffersFlashToggle(peer: [MCPeerID]) {
        let commandData = buildFlatBuffersFlashToggleCommand()
        
        do {
            try session.send(commandData, toPeers: peer, with: .reliable)
            print("📦 ✅ Successfully sent FlatBuffers flash toggle command")
        } catch {
            print("📦 ❌ Failed to send FlatBuffers flash toggle command: \(error)")
        }
    }
    
    /// Build FlatBuffers flash toggle command
    private func buildFlatBuffersFlashToggleCommand() -> Data {
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
            action: .toggleflash,
            parametersOffset: Offset() // No parameters needed for flash toggle
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
        
        print("📦 Building FlatBuffers flash toggle command")
        print("📦 Builder sizedBuffer size: \(builder.sizedBuffer.size)")
        
        return builder.data
    }
    
    /// Send FlatBuffers flash state response
    public func sendFlatBuffersFlashStateResponse(peer: [MCPeerID], commandId: String, flashMode: AVCaptureDevice.FlashMode?, error: Error?, capabilities: RemoteCmd.CameraCapabilitiesResp?) {
        let responseData = buildFlatBuffersFlashStateResponse(commandId: commandId, flashMode: flashMode, error: error, capabilities: capabilities)
        
        do {
            try session.send(responseData, toPeers: peer, with: .reliable)
            print("📦 ✅ Successfully sent FlatBuffers flash state response with capabilities")
        } catch {
            print("📦 ❌ Failed to send FlatBuffers flash state response: \(error)")
        }
    }
    
    /// Build FlatBuffers flash state response
    private func buildFlatBuffersFlashStateResponse(commandId: String, flashMode: AVCaptureDevice.FlashMode?, error: Error?, capabilities: RemoteCmd.CameraCapabilitiesResp?) -> Data {
        var builder = FlatBufferBuilder(initialSize: 512)
        
        // Create command ID and timestamp
        let commandIdOffset = builder.create(string: commandId)
        let senderOffset = builder.create(string: UIDevice.current.name)
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        
        // Create current state with flash mode
        var currentStateOffset = Offset()
        if let flashMode = flashMode {
            let flatBuffersFlashMode: RemoteShutter_FlashMode
            switch flashMode {
            case .off: flatBuffersFlashMode = .off
            case .on: flatBuffersFlashMode = .on
            case .auto: flatBuffersFlashMode = .auto
            @unknown default: flatBuffersFlashMode = .off
            }
            
            // Get current camera info for state
            let currentCamera: RemoteShutter_CameraPosition = capabilities?.currentCamera == .front ? .front : .back
            let currentLens: RemoteShutter_CameraLensType = convertLensTypeToFlatBuffers(capabilities?.currentLens ?? .wideAngle)
            let zoomFactor = capabilities?.currentZoom ?? 1.0
            
            currentStateOffset = RemoteShutter_CameraState.createCameraState(
                &builder,
                currentCamera: currentCamera,
                currentLens: currentLens,
                zoomFactor: zoomFactor,
                torchMode: .off, // Default torch mode
                flashMode: flatBuffersFlashMode,
                isRecording: false, // Default recording state
                connectionStatus: .connected
            )
        }
        
        // Create capabilities if available
        var capabilitiesOffset = Offset()
        if let capabilities = capabilities {
            capabilitiesOffset = buildFlatBuffersCameraCapabilities(builder: &builder, capabilities: capabilities)
        }
        
        // Create camera state response
        let responseOffset = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &builder,
            commandIdOffset: commandIdOffset,
            timestamp: timestamp,
            success: error == nil,
            errorOffset: error != nil ? builder.create(string: error!.localizedDescription) : Offset(),
            currentStateOffset: currentStateOffset,
            capabilitiesOffset: capabilitiesOffset
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
    
    /// Helper method to build FlatBuffers camera capabilities from legacy capabilities
    private func buildFlatBuffersCameraCapabilities(builder: inout FlatBufferBuilder, capabilities: RemoteCmd.CameraCapabilitiesResp) -> Offset {
        // Create front camera info if available
        var frontCameraOffset = Offset()
        if let frontCamera = capabilities.frontCamera {
            frontCameraOffset = buildFlatBuffersCameraInfo(builder: &builder, cameraInfo: frontCamera)
        }
        
        // Create back camera info if available
        var backCameraOffset = Offset()
        if let backCamera = capabilities.backCamera {
            backCameraOffset = buildFlatBuffersCameraInfo(builder: &builder, cameraInfo: backCamera)
        }
        
        // Create available actions vector
        let availableActions: [RemoteShutter_CommandAction] = [
            .takepicture, .toggleflash, .togglecamera, .toggletorch,
            .startrecording, .stoprecording, .requestcapabilities,
            .setzoom, .switchlens, .settorchmode, .setflashmode, .requestframe
        ]
        let availableActionsOffset = builder.createVector(availableActions)
        
        // Create current limits
        let currentCameraInfo = capabilities.getCurrentCameraInfo()
        let currentLimits = buildFlatBuffersCameraLimits(builder: &builder, cameraInfo: currentCameraInfo, currentLens: capabilities.currentLens, currentZoom: capabilities.currentZoom)
        
        // Create camera capabilities
        return RemoteShutter_CameraCapabilities.createCameraCapabilities(
            &builder,
            frontCameraOffset: frontCameraOffset,
            backCameraOffset: backCameraOffset,
            availableActionsVectorOffset: availableActionsOffset,
            currentLimitsOffset: currentLimits
        )
    }
    
    /// Helper method to build FlatBuffers camera info from legacy camera info
    private func buildFlatBuffersCameraInfo(builder: inout FlatBufferBuilder, cameraInfo: RemoteCmd.CameraInfo) -> Offset {
        // Create available lenses vector
        let availableLenses = cameraInfo.availableLenses.map { convertLensTypeToFlatBuffers($0) }
        let availableLensesOffset = builder.createVector(availableLenses)
        
        // Create zoom capabilities vector
        var zoomCapabilityOffsets: [Offset] = []
        for (lensType, zoomRange) in cameraInfo.getZoomCapabilities() {
            let zoomRangeOffset = RemoteShutter_ZoomRange.createZoomRange(
                &builder,
                minZoom: zoomRange.minZoom,
                maxZoom: zoomRange.maxZoom
            )
            
            let zoomCapabilityOffset = RemoteShutter_ZoomCapability.createZoomCapability(
                &builder,
                lensType: convertLensTypeToFlatBuffers(lensType),
                zoomRangeOffset: zoomRangeOffset
            )
            zoomCapabilityOffsets.append(zoomCapabilityOffset)
        }
        let zoomCapabilitiesOffset = builder.createVector(ofOffsets: zoomCapabilityOffsets)
        
        // Create camera info
        return RemoteShutter_CameraInfo.createCameraInfo(
            &builder,
            availableLensesVectorOffset: availableLensesOffset,
            hasFlash: cameraInfo.hasFlash,
            hasTorch: cameraInfo.hasTorch,
            zoomCapabilitiesVectorOffset: zoomCapabilitiesOffset
        )
    }
    
    /// Helper method to build FlatBuffers camera limits
    private func buildFlatBuffersCameraLimits(builder: inout FlatBufferBuilder, cameraInfo: RemoteCmd.CameraInfo?, currentLens: CameraLensType, currentZoom: CGFloat) -> Offset {
        // Create zoom range for current lens
        let zoomRange = cameraInfo?.getZoomCapabilities()[currentLens] ?? RemoteCmd.ZoomRange(minZoom: 1.0, maxZoom: 1.0)
        let zoomRangeOffset = RemoteShutter_ZoomRange.createZoomRange(
            &builder,
            minZoom: zoomRange.minZoom,
            maxZoom: zoomRange.maxZoom
        )
        
        // Create available lenses vector
        let availableLenses = cameraInfo?.availableLenses.map { convertLensTypeToFlatBuffers($0) } ?? []
        let availableLensesOffset = builder.createVector(availableLenses)
        
        // Create camera limits
        return RemoteShutter_CameraLimits.createCameraLimits(
            &builder,
            zoomRangeOffset: zoomRangeOffset,
            availableLensesVectorOffset: availableLensesOffset,
            supportsFlash: cameraInfo?.hasFlash ?? false,
            supportsTorch: cameraInfo?.hasTorch ?? false
        )
    }
    
    /// Helper method to convert legacy lens type to FlatBuffers lens type
    private func convertLensTypeToFlatBuffers(_ lensType: CameraLensType) -> RemoteShutter_CameraLensType {
        switch lensType {
        case .wideAngle: return .wideangle
        case .ultraWide: return .ultrawide
        case .telephoto: return .telephoto
        case .dualCamera: return .dualcamera
        }
    }
    
    // MARK: - FlatBuffers Photo Capture Methods
    
    /// Send FlatBuffers photo capture command
    public func sendFlatBuffersPhotoCapture(peer: [MCPeerID], sendToRemote: Bool) {
        let commandData = buildFlatBuffersPhotoCaptureCommand(sendToRemote: sendToRemote)
        
        do {
            try session.send(commandData, toPeers: peer, with: .reliable)
            print("📦 ✅ Successfully sent FlatBuffers photo capture command")
        } catch {
            print("📦 ❌ Failed to send FlatBuffers photo capture command: \(error)")
        }
    }
    
    /// Build FlatBuffers photo capture command
    private func buildFlatBuffersPhotoCaptureCommand(sendToRemote: Bool) -> Data {
        var builder = FlatBufferBuilder(initialSize: 256)
        
        // Create command ID and timestamp
        let commandId = UUID().uuidString
        let idOffset = builder.create(string: commandId)
        let senderOffset = builder.create(string: UIDevice.current.name)
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        
        // Create parameters with sendToRemote flag
        let parametersOffset = RemoteShutter_CommandParameters.createCommandParameters(
            &builder,
            sendToRemote: sendToRemote
        )
        
        // Create camera command
        let commandOffset = RemoteShutter_CameraCommand.createCameraCommand(
            &builder,
            idOffset: idOffset,
            timestamp: timestamp,
            action: .takepicture,
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
        
        print("📦 Building FlatBuffers photo capture command (sendToRemote: \(sendToRemote))")
        print("📦 Builder sizedBuffer size: \(builder.sizedBuffer.size)")
        
        return builder.data
    }
    
    /// Send FlatBuffers photo capture response
    public func sendFlatBuffersPhotoCaptureResponse(peer: [MCPeerID], commandId: String, photoData: Data?, error: Error?) {
        let responseData = buildFlatBuffersPhotoCaptureResponse(commandId: commandId, photoData: photoData, error: error)
        
        do {
            try session.send(responseData, toPeers: peer, with: .reliable)
            print("📦 ✅ Successfully sent FlatBuffers photo capture response")
        } catch {
            print("📦 ❌ Failed to send FlatBuffers photo capture response: \(error)")
        }
    }
    
    /// Build FlatBuffers photo capture response
    private func buildFlatBuffersPhotoCaptureResponse(commandId: String, photoData: Data?, error: Error?) -> Data {
        var builder = FlatBufferBuilder(initialSize: Int32(photoData?.count ?? 256 + 1024)) // Extra space for photo data
        
        // Create command ID and timestamp
        let commandIdOffset = builder.create(string: commandId)
        let senderOffset = builder.create(string: UIDevice.current.name)
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        
        // Create media data if photo data exists
        var mediaDataOffset = Offset()
        if let photoData = photoData {
            let dataVector = builder.createVector(bytes: photoData)
            mediaDataOffset = RemoteShutter_MediaData.createMediaData(
                &builder,
                dataVectorOffset: dataVector,
                type: .photo,
                timestamp: timestamp
            )
        }
        
        // Create camera state response
        let responseOffset = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &builder,
            commandIdOffset: commandIdOffset,
            success: error == nil,
            errorOffset: error != nil ? builder.create(string: error!.localizedDescription) : Offset(),
            capabilitiesOffset: Offset(), // TODO: Implement capabilities serialization
            mediaDataOffset: mediaDataOffset
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
    
    // MARK: - FlatBuffers Video Recording Methods
    
    /// Send FlatBuffers start recording command
    public func sendFlatBuffersStartRecording(peer: [MCPeerID]) {
        let commandData = buildFlatBuffersStartRecordingCommand()
        
        do {
            try session.send(commandData, toPeers: peer, with: .reliable)
            print("📦 ✅ Successfully sent FlatBuffers start recording command")
        } catch {
            print("📦 ❌ Failed to send FlatBuffers start recording command: \(error)")
        }
    }
    
    /// Build FlatBuffers start recording command
    private func buildFlatBuffersStartRecordingCommand() -> Data {
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
            action: .startrecording,
            parametersOffset: Offset() // No parameters needed for start recording
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
        
        print("📦 Building FlatBuffers start recording command")
        print("📦 Builder sizedBuffer size: \(builder.sizedBuffer.size)")
        
        return builder.data
    }
    
    /// Send FlatBuffers stop recording command
    public func sendFlatBuffersStopRecording(peer: [MCPeerID], sendToRemote: Bool) {
        let commandData = buildFlatBuffersStopRecordingCommand(sendToRemote: sendToRemote)
        
        do {
            try session.send(commandData, toPeers: peer, with: .reliable)
            print("📦 ✅ Successfully sent FlatBuffers stop recording command")
        } catch {
            print("📦 ❌ Failed to send FlatBuffers stop recording command: \(error)")
        }
    }
    
    /// Build FlatBuffers stop recording command
    private func buildFlatBuffersStopRecordingCommand(sendToRemote: Bool) -> Data {
        var builder = FlatBufferBuilder(initialSize: 256)
        
        // Create command ID and timestamp
        let commandId = UUID().uuidString
        let idOffset = builder.create(string: commandId)
        let senderOffset = builder.create(string: UIDevice.current.name)
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        
        // Create parameters with sendToRemote flag
        let parametersOffset = RemoteShutter_CommandParameters.createCommandParameters(
            &builder,
            sendToRemote: sendToRemote
        )
        
        // Create camera command
        let commandOffset = RemoteShutter_CameraCommand.createCameraCommand(
            &builder,
            idOffset: idOffset,
            timestamp: timestamp,
            action: .stoprecording,
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
        
        print("📦 Building FlatBuffers stop recording command (sendToRemote: \(sendToRemote))")
        print("📦 Builder sizedBuffer size: \(builder.sizedBuffer.size)")
        
        return builder.data
    }
    
    /// Send FlatBuffers video recording response
    public func sendFlatBuffersVideoRecordingResponse(peer: [MCPeerID], commandId: String, videoData: Data?, error: Error?) {
        let responseData = buildFlatBuffersVideoRecordingResponse(commandId: commandId, videoData: videoData, error: error)
        
        do {
            try session.send(responseData, toPeers: peer, with: .reliable)
            print("📦 ✅ Successfully sent FlatBuffers video recording response")
        } catch {
            print("📦 ❌ Failed to send FlatBuffers video recording response: \(error)")
        }
    }
    
    /// Build FlatBuffers video recording response
    private func buildFlatBuffersVideoRecordingResponse(commandId: String, videoData: Data?, error: Error?) -> Data {
        var builder = FlatBufferBuilder(initialSize: Int32(videoData?.count ?? 256 + 1024)) // Extra space for video data
        
        // Create command ID and timestamp
        let commandIdOffset = builder.create(string: commandId)
        let senderOffset = builder.create(string: UIDevice.current.name)
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        
        // Create media data if video data exists
        var mediaDataOffset = Offset()
        if let videoData = videoData {
            let dataVector = builder.createVector(bytes: videoData)
            mediaDataOffset = RemoteShutter_MediaData.createMediaData(
                &builder,
                dataVectorOffset: dataVector,
                type: .video,
                timestamp: timestamp
            )
        }
        
        // Create camera state response
        let responseOffset = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &builder,
            commandIdOffset: commandIdOffset,
            success: error == nil,
            errorOffset: error != nil ? builder.create(string: error!.localizedDescription) : Offset(),
            capabilitiesOffset: Offset(), // TODO: Implement capabilities serialization
            mediaDataOffset: mediaDataOffset
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
    
    // MARK: - FlatBuffers Frame Request Methods
    
    /// Send FlatBuffers frame request command
    public func sendFlatBuffersFrameRequest(peer: [MCPeerID]) {
//        print("🔍 DEBUG: sendFlatBuffersFrameRequest called for peers: \(peer.map { $0.displayName })")
        let commandData = buildFlatBuffersFrameRequestCommand()
        
        do {
            try session.send(commandData, toPeers: peer, with: .reliable)
//            print("🔍 DEBUG: Successfully sent FlatBuffers frame request")
        } catch {
//            print("📦 ❌ Failed to send FlatBuffers frame request command: \(error)")
        }
    }
    
    /// Build FlatBuffers frame request command
    private func buildFlatBuffersFrameRequestCommand() -> Data {
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
            action: .requestframe,
            parametersOffset: Offset() // No parameters needed for frame request
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
    
    /// Send FlatBuffers frame data response
    public func sendFlatBuffersFrameData(peer: [MCPeerID], frameData: Data, fps: Int, cameraPosition: AVCaptureDevice.Position, orientation: UIInterfaceOrientation) {
        let responseData = buildFlatBuffersFrameDataResponse(frameData: frameData, fps: fps, cameraPosition: cameraPosition, orientation: orientation)
        
        do {
            try session.send(responseData, toPeers: peer, with: .unreliable) // Use unreliable for frame data for better performance
        } catch {
            print("📦 ❌ Failed to send FlatBuffers frame data response: \(error)")
        }
    }
    
    /// Build FlatBuffers frame data response
    private func buildFlatBuffersFrameDataResponse(frameData: Data, fps: Int, cameraPosition: AVCaptureDevice.Position, orientation: UIInterfaceOrientation) -> Data {
        var builder = FlatBufferBuilder(initialSize: Int32(frameData.count + 1024)) // Extra space for frame data
        
        // Create strings
        let idOffset = builder.create(string: UUID().uuidString)
        let senderOffset = builder.create(string: UIDevice.current.name)
        let orientationOffset = builder.create(string: orientation.rawValue.description)
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        
        // Create byte vector for image data
        let imageDataOffset = builder.createVector(bytes: frameData)
        
        // Convert camera position
        let flatBuffersPosition: RemoteShutter_CameraPosition = cameraPosition == .back ? .back : .front
        
        // Create frame data
        let frameDataOffset = RemoteShutter_FrameData.createFrameData(
            &builder,
            imageDataVectorOffset: imageDataOffset,
            fps: Int32(fps),
            cameraPosition: flatBuffersPosition,
            orientationOffset: orientationOffset,
            timestamp: timestamp
        )
        
        // Create P2P message envelope
        let messageOffset = RemoteShutter_P2PMessage.createP2PMessage(
            &builder,
            idOffset: idOffset,
            timestamp: timestamp,
            type: .framedata,
            senderOffset: senderOffset,
            frameDataOffset: frameDataOffset
        )
        
        // Finish and return
        RemoteShutter_P2PMessage.finish(&builder, end: messageOffset)
        
        return builder.data
    }
    
    // MARK: - FlatBuffers Camera Toggle Methods
    
    /// Send FlatBuffers camera toggle command
    public func sendFlatBuffersCameraToggle(peer: [MCPeerID]) {
        let commandData = buildFlatBuffersCameraToggleCommand()
        
        do {
            try session.send(commandData, toPeers: peer, with: .reliable)
            print("📦 ✅ Successfully sent FlatBuffers camera toggle command")
        } catch {
            print("📦 ❌ Failed to send FlatBuffers camera toggle command: \(error)")
        }
    }
    
    /// Build FlatBuffers camera toggle command
    private func buildFlatBuffersCameraToggleCommand() -> Data {
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
            action: .togglecamera,
            parametersOffset: Offset() // No parameters needed for camera toggle
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
        
        print("📦 Building FlatBuffers camera toggle command")
        print("📦 Builder sizedBuffer size: \(builder.sizedBuffer.size)")
        
        return builder.data
    }
    
    /// Send FlatBuffers camera state response
    public func sendFlatBuffersCameraStateResponse(peer: [MCPeerID], commandId: String, capabilities: RemoteCmd.CameraCapabilitiesResp?, error: Error?) {
        let responseData = buildFlatBuffersCameraStateResponse(commandId: commandId, capabilities: capabilities, error: error)
        
        do {
            try session.send(responseData, toPeers: peer, with: .reliable)
            print("📦 ✅ Successfully sent FlatBuffers camera state response")
        } catch {
            print("📦 ❌ Failed to send FlatBuffers camera state response: \(error)")
        }
    }
    
    /// Build FlatBuffers camera state response
    private func buildFlatBuffersCameraStateResponse(commandId: String, capabilities: RemoteCmd.CameraCapabilitiesResp?, error: Error?) -> Data {
        var builder = FlatBufferBuilder(initialSize: 512)
        
        let commandIdOffset = builder.create(string: commandId)
        let senderOffset = builder.create(string: UIDevice.current.name)
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        
        // Create current state from capabilities if available
        var currentStateOffset = Offset()
        if let capabilities = capabilities {
            let currentCamera: RemoteShutter_CameraPosition = capabilities.currentCamera == .front ? .front : .back
            let currentLens: RemoteShutter_CameraLensType = convertLensTypeToFlatBuffers(capabilities.currentLens)
            let zoomFactor = capabilities.currentZoom
            
            currentStateOffset = RemoteShutter_CameraState.createCameraState(
                &builder,
                currentCamera: currentCamera,
                currentLens: currentLens,
                zoomFactor: zoomFactor,
                torchMode: .off, // Default torch mode
                flashMode: .off, // Default flash mode
                isRecording: false, // Default recording state
                connectionStatus: .connected
            )
        }
        
        // Create capabilities if available
        var capabilitiesOffset = Offset()
        if let capabilities = capabilities {
            capabilitiesOffset = buildFlatBuffersCameraCapabilities(builder: &builder, capabilities: capabilities)
        }
        
        // Create camera state response (no media data for generic responses)
        let responseOffset = RemoteShutter_CameraStateResponse.createCameraStateResponse(
            &builder,
            commandIdOffset: commandIdOffset,
            timestamp: timestamp,
            success: error == nil,
            errorOffset: error != nil ? builder.create(string: error!.localizedDescription) : Offset(),
            currentStateOffset: currentStateOffset,
            capabilitiesOffset: capabilitiesOffset,
            mediaDataOffset: Offset() // No media data for generic responses
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
    
    // MARK: - FlatBuffers Peer Role Commands
    
    /// Send FlatBuffers peer became camera command
    public func sendFlatBuffersPeerBecameCamera(peer: [MCPeerID]) {
        let commandData = buildFlatBuffersPeerBecameCameraCommand()
        
        do {
            try session.send(commandData, toPeers: peer, with: .reliable)
            print("📦 ✅ Successfully sent FlatBuffers peer became camera command")
        } catch {
            print("📦 ❌ Failed to send FlatBuffers peer became camera command: \(error)")
        }
    }
    
    /// Build FlatBuffers peer became camera command
    private func buildFlatBuffersPeerBecameCameraCommand() -> Data {
        var builder = FlatBufferBuilder(initialSize: 512)
        
        // Create command ID and timestamp
        let commandId = UUID().uuidString
        let idOffset = builder.create(string: commandId)
        let senderOffset = builder.create(string: UIDevice.current.name)
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        
        // Create version information
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let platform = UIDevice.current.systemName
        
        let shortVersionOffset = builder.create(string: shortVersion)
        let platformOffset = builder.create(string: platform)
        
        // Create command parameters with version info
        let parametersOffset = RemoteShutter_CommandParameters.createCommandParameters(
            &builder,
            bundleVersion: Int32(bundleVersion) ?? 0,
            shortVersionOffset: shortVersionOffset,
            platformOffset: platformOffset
        )
        
        // Create camera command
        let commandOffset = RemoteShutter_CameraCommand.createCameraCommand(
            &builder,
            idOffset: idOffset,
            timestamp: timestamp,
            action: .peerbecamecamera,
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
    
    /// Send FlatBuffers peer became monitor command
    public func sendFlatBuffersPeerBecameMonitor(peer: [MCPeerID]) {
        let commandData = buildFlatBuffersPeerBecameMonitorCommand()
        
        do {
            try session.send(commandData, toPeers: peer, with: .reliable)
            print("📦 ✅ Successfully sent FlatBuffers peer became monitor command")
        } catch {
            print("📦 ❌ Failed to send FlatBuffers peer became monitor command: \(error)")
        }
    }
    
    /// Build FlatBuffers peer became monitor command
    private func buildFlatBuffersPeerBecameMonitorCommand() -> Data {
        var builder = FlatBufferBuilder(initialSize: 512)
        
        // Create command ID and timestamp
        let commandId = UUID().uuidString
        let idOffset = builder.create(string: commandId)
        let senderOffset = builder.create(string: UIDevice.current.name)
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        
        // Create version information
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let platform = UIDevice.current.systemName
        
        let shortVersionOffset = builder.create(string: shortVersion)
        let platformOffset = builder.create(string: platform)
        
        // Create command parameters with version info
        let parametersOffset = RemoteShutter_CommandParameters.createCommandParameters(
            &builder,
            bundleVersion: Int32(bundleVersion) ?? 0,
            shortVersionOffset: shortVersionOffset,
            platformOffset: platformOffset
        )
        
        // Create camera command
        let commandOffset = RemoteShutter_CameraCommand.createCameraCommand(
            &builder,
            idOffset: idOffset,
            timestamp: timestamp,
            action: .peerbecamemonitor,
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
}
