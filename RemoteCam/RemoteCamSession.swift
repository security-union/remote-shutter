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
