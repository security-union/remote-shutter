//
//  RemoteCamSession.swift
//  Actors
//
//  Created by Dario on 10/7/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation
import MultipeerConnectivity
import Combine

func getFrameSender() -> ActorRef? {
    RemoteCamSystem.shared.selectActor(actorPath: "RemoteCam/user/FrameSender")
}

func getRemoteCamSession() -> ActorRef? {
    RemoteCamSystem.shared.selectActor(actorPath: "RemoteCam/user/RemoteCam Session")
}

func getMonitorActor() -> ActorRef? {
    RemoteCamSystem.shared.selectActor(actorPath: "RemoteCam/user/MonitorActor")
}

func getRolePickerActor() -> ActorRef? {
    RemoteCamSystem.shared.selectActor(actorPath: "RemoteCam/user/RolePickerActor")
}

/// Creates a named actor, replacing any stale instance that may still exist.
/// Returns both the ActorRef and the ObjectIdentifier of the concrete instance,
/// so callers can later call stopActorIfCurrent in deinit without risking
/// killing a replacement actor at the same path.
func createOrReplaceActor(clz: Actor.Type, name: String) -> (ref: ActorRef, instanceId: ObjectIdentifier) {
    let ref = RemoteCamSystem.shared.actorOf(clz: clz, name: name, replace: true)!
    let instanceId = RemoteCamSystem.shared.instanceId(forRef: ref)!
    return (ref, instanceId)
}

/// Stops the actor at ref's path only if it is still the same instance
/// identified by instanceId. Safe to call from deinit — if the actor was
/// already replaced by createOrReplaceActor, this is a no-op.
func stopActorIfCurrent(ref: ActorRef?, instanceId: ObjectIdentifier?) {
    guard let ref = ref, let instanceId = instanceId else { return }
    RemoteCamSystem.shared.stopIfSameInstance(path: ref.path.asString, expectedId: instanceId)
}

public class RemoteCamSession: ViewCtrlActor<DeviceScannerViewController> {

    var alertPresenter: AlertPresenting = UIAlertPresenter()

    var multipeerService: (any MultipeerServiceProtocol)!

    var session: MCSession! { multipeerService?.session }

    var connectedPeers: [MCPeerID] { multipeerService?.connectedPeers ?? [] }

    var _timeoutGeneration: Int = 0

    // MARK: - Type-safe state machine wrappers

    func become(name: RemoteCamState, state: @escaping Receive) {
        become(name: name.rawValue, state: state)
    }

    func become(name: RemoteCamState, state: @escaping Receive, discardOld: Bool) {
        become(name: name.rawValue, state: state, discardOld: discardOld)
    }

    func popToState(name: RemoteCamState) {
        popToState(name: name.rawValue)
    }

    func currentStateName() -> RemoteCamState? {
        guard let name = currentState()?.0 else { return nil }
        return RemoteCamState(rawValue: name)
    }

    public required init(context: ActorSystem, ref: ActorRef) {
        super.init(context: context, ref: ref)
    }

    override public func willStop() {
        multipeerService?.stopSession()
    }

    override public func receiveWithCtrl(ctrl: Weak<DeviceScannerViewController>) -> Receive {
        return { [unowned self](msg: Message) in
            switch msg {
            case is UICmd.StartScanning:
                self.become(name: .scanning, state: self.scanning(ctrl))

            default:
                self.receive(msg: msg)
            }
        }
    }

    func popAndStartScanning() {
        self.popToState(name: .scanning)
    }

    func startScanning(lobby: DeviceScannerViewController) {
        assert(Thread.isMainThread == false, "can't be called from the main thread")

        if multipeerService == nil {
            multipeerService = MultipeerService(peerID: lobby.peerID)
            multipeerService.delegate = self
        } else {
            multipeerService.disconnect()
        }

        switch lobby.role {
        case .camera:
            multipeerService.startAdvertisingOnly(discoveryInfo: ["role": "camera"])
        case .monitor:
            multipeerService.startBrowsingOnly()
        }

        ^{
            lobby.navigationController?.popToViewController(lobby, animated: true)
            lobby.scannerViewModel.startedScanning()
        }
    }

    public func unableToProcessError(msg: Message) -> NSError {
        return NSError(
            domain: "Unable to process \(type(of: msg)) command, since \(UIDevice.current.name) is not in the camera screen.", code: 0, userInfo: nil)
    }

    override public func receive(msg: Actor.Message) {
        switch msg {

        case let m as UICmd.BecomeWatchCamera:
            self.become(name: .watchRemoteCamera, state: self.watchRemoteCamera(ctrl: m.ctrl))

        case let m as UICmd.BecomeCamera:
            ^{
                m.ctrl.navigationController?.popViewController(animated: true)
            }

        case let m as UICmd.BecomeMonitor:
            m.sender! ! UICmd.BecomeMonitorFailed(sender: this)

        case is RemoteCmd.TakePic:
            let l = RemoteCmd.TakePicResp(sender: this, error: self.unableToProcessError(msg: msg))
            sendCommandOrGoToScanning(peer: self.connectedPeers, msg: l)
        case is RemoteCmd.ToggleCamera:
            let l = RemoteCmd.ToggleCameraResp(
                cameraCapabilities: nil, error: self.unableToProcessError(msg: msg)
            )
            self.sendCommandOrGoToScanning(peer: self.connectedPeers, msg: l)

        case is RemoteCmd.ToggleFlash:
            let l = RemoteCmd.ToggleFlashResp(
                flashMode: nil, error: self.unableToProcessError(msg: msg)
            )
            self.sendCommandOrGoToScanning(peer: self.connectedPeers, msg: l)
            
        // MARK: - Zoom and Lens Command Handling
        case is RemoteCmd.SetZoom:
            let l = RemoteCmd.SetZoomResp(
                zoomFactor: nil, currentLens: nil, zoomRange: nil, error: self.unableToProcessError(msg: msg)
            )
            self.sendCommandOrGoToScanning(peer: self.connectedPeers, msg: l)
            
        case is RemoteCmd.SwitchLens:
            debugLog("❌ DEBUG: Session default handler received SwitchLens - NOT in camera state!")
            let l = RemoteCmd.SwitchLensResp(
                lensType: nil, availableLenses: nil, currentZoom: nil, zoomRange: nil, error: self.unableToProcessError(msg: msg)
            )
            debugLog("🔍 DEBUG: Default handler sending empty SwitchLensResp with error: \(self.unableToProcessError(msg: msg).localizedDescription)")
            self.sendCommandOrGoToScanning(peer: self.connectedPeers, msg: l)

        case is RemoteCmd.SetAspectRatio:
            let l = RemoteCmd.SetAspectRatioResp(aspectRatio: nil, error: self.unableToProcessError(msg: msg))
            self.sendCommandOrGoToScanning(peer: self.connectedPeers, msg: l)

        // MARK: - Video Recording Command Handling
        case is RemoteCmd.StartRecordingVideo:
            debugLog("❌ DEBUG: Session default handler received StartRecordingVideo - NOT in camera state!")
            let l = RemoteCmd.StartRecordingVideoAck(sender: this, recordingStartTime: nil, error: self.unableToProcessError(msg: msg))
            debugLog("🔍 DEBUG: Default handler sending StartRecordingVideoAck with error: \(self.unableToProcessError(msg: msg).localizedDescription)")
            self.sendCommandOrGoToScanning(peer: self.connectedPeers, msg: l)
            
        case is RemoteCmd.StopRecordingVideo:
            debugLog("❌ DEBUG: Session default handler received StopRecordingVideo - NOT in camera state!")
            let l = RemoteCmd.StopRecordingVideoResp(sender: this, pic: nil, error: self.unableToProcessError(msg: msg))
            debugLog("🔍 DEBUG: Default handler sending StopRecordingVideoResp with error: \(self.unableToProcessError(msg: msg).localizedDescription)")
            self.sendCommandOrGoToScanning(peer: self.connectedPeers, msg: l)
            
        case let capabilities as RemoteCmd.CameraCapabilitiesResp:
            // Forward capabilities to connected peers (monitor)
            debugLog("🔍 DEBUG: Base session forwarding capabilities to peers")
            self.sendCommandOrGoToScanning(peer: self.connectedPeers, msg: capabilities)

        // MARK: - Video Resource Transfer Handling
        case let sendVideo as UICmd.SendVideoResource:
            self.handleSendVideoResource(sendVideo)
            
        case let transferStarted as UICmd.VideoResourceTransferStarted:
            // Forward to MonitorActor using actor system
            self.forwardToActors(transferStarted)
            // Also forward to current state (for camera states that have ctrl reference)
            super.receive(msg: transferStarted)
            
        case let transferProgress as UICmd.VideoResourceTransferProgress:
            // Forward to MonitorActor using actor system
            self.forwardToActors(transferProgress)
            // Also forward to current state (for camera states that have ctrl reference)
            super.receive(msg: transferProgress)
            
        case let transferCompleted as UICmd.VideoResourceTransferCompleted:
            // Forward to MonitorActor and send video response
            self.forwardToActors(transferCompleted)
            self.handleVideoTransferCompleted(transferCompleted)
            // Also forward to current state (for camera states that have ctrl reference)
            super.receive(msg: transferCompleted)
            
        case let transferFailed as UICmd.VideoResourceTransferFailed:
            // Forward to MonitorActor and send error response
            self.forwardToActors(transferFailed)
            self.handleVideoTransferFailed(transferFailed)
            // Also forward to current state (for camera states that have ctrl reference)
            super.receive(msg: transferFailed)

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
        return multipeerService.send(msg, to: peer, mode: mode)
    }

    public func sendCommandOrGoToScanning(peer: [MCPeerID],
                                          msg: Actor.Message,
                                          mode: MCSessionSendDataMode = .reliable) {
        assert(Thread.isMainThread == false, "can't be called from the main thread")
        
        // Debug log for SwitchLensResp
        if let switchResp = msg as? RemoteCmd.SwitchLensResp {
            debugLog("🔍 DEBUG: sendCommandOrGoToScanning - SwitchLensResp being sent:")
            debugLog("🔍 DEBUG: - Transmission lensType: \(switchResp.lensType?.displayName ?? "nil")")
            debugLog("🔍 DEBUG: - Transmission error: \(switchResp.error?.localizedDescription ?? "nil")")
        }
        
        if self.sendMessage(peer: self.connectedPeers, msg: msg).isFailure() {
            debugLog("❌ DEBUG: sendCommandOrGoToScanning failed to send message")
            self.popToState(name: .scanning)
            ^{ [weak self] in
                self?.alertPresenter.showError(
                    title: NSLocalizedString("Connection error", comment: "")
                )
            }
        } else {
//            debugLog("✅ DEBUG: sendCommandOrGoToScanning successfully sent message")
        }
    }
    
    // MARK: - Video Resource Transfer Implementation
    
    private func handleSendVideoResource(_ sendVideo: UICmd.SendVideoResource) {
        guard sendVideo.shouldSendToPeer else {
            // Send empty response when not sending video to peer
            let response = RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: nil)
            self.sendCommandOrGoToScanning(peer: self.connectedPeers, msg: response)
            return
        }
        
        // Use the session's connected peers instead of relying on the message
        let connectedPeers = self.connectedPeers
        guard !connectedPeers.isEmpty else {
            debugLog("❌ DEBUG: No connected peers for video transfer")
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
            debugLog("❌ DEBUG: Error getting video file size: \(error.localizedDescription)")
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
            // Capture the Progress object returned by sendResource to track sending progress
            let sendProgress = self.multipeerService.sendResource(
                at: sendVideo.videoURL,
                withName: resourceName,
                toPeer: peer
            ) { [weak self] error in
                DispatchQueue.main.async {
                    if let error = error {
                        debugLog("❌ DEBUG: Error sending video resource: \(error.localizedDescription)")
                        let failedMsg = UICmd.VideoResourceTransferFailed(error: error, resourceName: resourceName, sender: self?.this)
                        if let this = self?.this {
                            this ! failedMsg
                        }
                    } else {
                        debugLog("✅ DEBUG: Video resource sent successfully")
                        let completedMsg = UICmd.VideoResourceTransferCompleted(resourceName: resourceName, success: true, sender: self?.this)
                        if let this = self?.this {
                            this ! completedMsg
                        }
                    }
                }
            }
            
            // Track sending progress using Combine (similar to receiving side)
            if let progress = sendProgress {
                debugLog("📤 DEBUG: Started tracking sending progress for resource: \(resourceName)")
                
                class SpeedTracker {
                    var lastUpdateTime = Date()
                    var lastCompletedBytes: Int64 = 0
                    var lastCalculatedSpeed: Double = 0.0
                }
                let speedTracker = SpeedTracker()
                
                progress.publisher(for: \.fractionCompleted)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] fractionCompleted in
                        let completedBytes = Int64(Double(progress.totalUnitCount) * fractionCompleted)
                        
                        // Simple speed calculation
                        let currentTime = Date()
                        let timeElapsed = currentTime.timeIntervalSince(speedTracker.lastUpdateTime)
                        let bytesTransferred = completedBytes - speedTracker.lastCompletedBytes
                        
                        debugLog("📤 DEBUG: Speed calc - timeElapsed: \(timeElapsed), bytesTransferred: \(bytesTransferred), lastCompleted: \(speedTracker.lastCompletedBytes), current: \(completedBytes)")
                        
                        let transferSpeed: Double
                        if timeElapsed > 0.5 && bytesTransferred > 0 {
                            transferSpeed = Double(bytesTransferred) / timeElapsed
                            speedTracker.lastUpdateTime = currentTime
                            speedTracker.lastCompletedBytes = completedBytes
                            speedTracker.lastCalculatedSpeed = transferSpeed
                            debugLog("📤 DEBUG: Speed calculated: \(String(format: "%.1f", transferSpeed / 1024 / 1024)) MB/s")
                        } else {
                            transferSpeed = speedTracker.lastCalculatedSpeed
                            debugLog("📤 DEBUG: Speed calculation skipped - timeElapsed: \(timeElapsed), bytesTransferred: \(bytesTransferred), using last speed: \(String(format: "%.1f", speedTracker.lastCalculatedSpeed / 1024 / 1024)) MB/s")
                        }
                        
                        debugLog("📤 DEBUG: Camera sending progress: \(Int(fractionCompleted * 100))% - Speed: \(String(format: "%.1f", transferSpeed / 1024 / 1024)) MB/s")
                        let progressMsg = UICmd.VideoResourceTransferProgress(
                            completedBytes: completedBytes,
                            totalBytes: progress.totalUnitCount,
                            progress: fractionCompleted,
                            resourceName: resourceName,
                            transferSpeed: transferSpeed,
                            sender: self?.this
                        )
                        if let this = self?.this {
                            this ! progressMsg
                        }
                    }
                    .store(in: &self.multipeerService.progressCancellables)
            } else {
                debugLog("⚠️ DEBUG: No progress object returned from sendResource")
            }
        }
    }
    
    private func handleVideoTransferCompleted(_ completed: UICmd.VideoResourceTransferCompleted) {
        if completed.success {
            // Send success response without data (data sent via resource transfer)
            let response = RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: nil)
            self.sendCommandOrGoToScanning(peer: self.connectedPeers, msg: response)
        }
    }
    
    private func handleVideoTransferFailed(_ failed: UICmd.VideoResourceTransferFailed) {
        // Send error response
        let response = RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: failed.error)
        self.sendCommandOrGoToScanning(peer: self.connectedPeers, msg: response)
    }
    
    private func forwardToActors(_ message: Actor.Message) {
        // Send directly to MonitorActor using actor system
        if let monitorActor = getMonitorActor() {
            monitorActor ! message
        }
        
        // For camera side, we'll handle this in the camera states where we have the ctrl reference
        // This is cleaner than notifications and maintains the actor pattern
    }
}
