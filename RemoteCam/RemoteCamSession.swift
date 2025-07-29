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
import Combine

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
    
    // Progress tracking for video transfers
    var progressCancellables = Set<AnyCancellable>()

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

        // MARK: - Video Resource Transfer Handling
        case let sendVideo as UICmd.SendVideoResource:
            self.handleSendVideoResource(sendVideo)
            
        case let transferStarted as UICmd.VideoResourceTransferStarted:
            // Forward to UI controllers
            self.forwardToViewControllers(transferStarted)
            
        case let transferProgress as UICmd.VideoResourceTransferProgress:
            // Forward to UI controllers
            self.forwardToViewControllers(transferProgress)
            
        case let transferCompleted as UICmd.VideoResourceTransferCompleted:
            // Forward to UI controllers and send video response
            self.forwardToViewControllers(transferCompleted)
            self.handleVideoTransferCompleted(transferCompleted)
            
        case let transferFailed as UICmd.VideoResourceTransferFailed:
            // Forward to UI controllers and send error response
            self.forwardToViewControllers(transferFailed)
            self.handleVideoTransferFailed(transferFailed)

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
    
    // MARK: - Video Resource Transfer Implementation
    
    private func handleSendVideoResource(_ sendVideo: UICmd.SendVideoResource) {
        guard sendVideo.shouldSendToPeer else {
            // Send empty response when not sending video to peer
            let response = RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: nil)
            self.sendCommandOrGoToScanning(peer: self.session.connectedPeers, msg: response)
            return
        }
        
        // Use the session's connected peers instead of relying on the message
        let connectedPeers = self.session.connectedPeers
        guard !connectedPeers.isEmpty else {
            print("❌ DEBUG: No connected peers for video transfer")
            let error = NSError(domain: "VideoTransfer", code: 1, userInfo: [NSLocalizedDescriptionKey: "No connected peers"])
            let failedMsg = UICmd.VideoResourceTransferFailed(error: error, resourceName: "unknown", sender: self.this)
            self.this ! failedMsg
            return
        }
        
        // Get file size for progress tracking
        let fileSize: Int64
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: sendVideo.videoURL.path)
            fileSize = attributes[.size] as? Int64 ?? 0
        } catch {
            print("❌ DEBUG: Error getting video file size: \(error.localizedDescription)")
            let failedMsg = UICmd.VideoResourceTransferFailed(error: error, resourceName: "unknown", sender: self.this)
            self.this ! failedMsg
            return
        }
        
        // Generate unique resource name
        let resourceName = "video_\(UUID().uuidString).mov"
        
        // Notify about transfer start
        let startedMsg = UICmd.VideoResourceTransferStarted(totalBytes: fileSize, resourceName: resourceName, sender: self.this)
        self.this ! startedMsg
        
        // Send video file as resource to all connected peers
        for peer in connectedPeers {
            self.session.sendResource(
                at: sendVideo.videoURL,
                withName: resourceName,
                toPeer: peer
            ) { [weak self] error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ DEBUG: Error sending video resource: \(error.localizedDescription)")
                        let failedMsg = UICmd.VideoResourceTransferFailed(error: error, resourceName: resourceName, sender: self?.this)
                        if let this = self?.this {
                            this ! failedMsg
                        }
                    } else {
                        print("✅ DEBUG: Video resource sent successfully")
                        let completedMsg = UICmd.VideoResourceTransferCompleted(resourceName: resourceName, success: true, sender: self?.this)
                        if let this = self?.this {
                            this ! completedMsg
                        }
                    }
                }
            }
        }
    }
    
    private func handleVideoTransferCompleted(_ completed: UICmd.VideoResourceTransferCompleted) {
        if completed.success {
            // Send success response without data (data sent via resource transfer)
            let response = RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: nil)
            self.sendCommandOrGoToScanning(peer: self.session.connectedPeers, msg: response)
        }
    }
    
    private func handleVideoTransferFailed(_ failed: UICmd.VideoResourceTransferFailed) {
        // Send error response
        let response = RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: failed.error)
        self.sendCommandOrGoToScanning(peer: self.session.connectedPeers, msg: response)
    }
    
    private func forwardToViewControllers(_ message: Actor.Message) {
        // Forward progress messages to UI controllers for display
        // This will be handled by the view controllers that listen for these messages
        DispatchQueue.main.async { [weak self] in
            if let cameraVC = UIApplication.shared.keyWindow?.rootViewController?.navigationController?.visibleViewController as? CameraViewController {
                cameraVC.handleVideoTransferMessage(message)
            }
            
            if let monitorVC = UIApplication.shared.keyWindow?.rootViewController?.navigationController?.visibleViewController as? MonitorViewController {
                monitorVC.handleVideoTransferMessage(message)
            }
        }
    }
}
