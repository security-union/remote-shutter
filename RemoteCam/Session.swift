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

public class RemoteCamSession: ViewCtrlActor<RolePickerController>, MCSessionDelegate, MCBrowserViewControllerDelegate {

    let states = States()

    var session: MCSession!

    let service: String = "RemoteCam"

    let peerID = MCPeerID(displayName: UIDevice.current.name)

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

    func connected(lobby: RolePickerController,
                   peer: MCPeerID) -> Receive {
        ^{
            lobby.navigationItem.rightBarButtonItem?.title = lobby.states.disconnect
            lobby.navigationItem.prompt = "Select Camera or Remote"
            lobby.remote.alpha = 1
            lobby.camera.alpha = 1
            lobby.remote.isEnabled = true
            lobby.camera.isEnabled = true
            lobby.instructionLabel.text = "Pick a role: Camera or Remote"
        }
        return { [unowned self] (msg: Actor.Message) in
            switch (msg) {

            case let m as UICmd.BecomeCamera:
                self.become(name: self.states.camera, state: self.camera(peer: peer, ctrl: m.ctrl, lobby: lobby))
                self.sendAndForget(peer: [peer], msg: RemoteCmd.PeerBecameCamera())

            case let m as UICmd.BecomeMonitor:
                self.become(name: self.states.monitor, state: self.monitor(monitor: m.sender!, peer: peer, lobby: lobby))
                self.sendAndForget(peer: [peer], msg: RemoteCmd.PeerBecameMonitor())

            case is RemoteCmd.PeerBecameCamera:
                ^{
                    lobby.becomeMonitor()
                }

            case is RemoteCmd.PeerBecameMonitor:
                ^{
                    lobby.becomeCamera()
                }

            case is UICmd.ToggleConnect:
                self.popAndStartScanning()

            case let c as DisconnectPeer:
                if c.peer.displayName == peer.displayName {
                    self.popAndStartScanning()
                }

            case is Disconnect:
                self.popAndStartScanning()

            default:
                self.receive(msg: msg)
            }
        }
    }

    func popAndStartScanning() {
        self.popToState(name: self.states.scanning)
        self.this ! BLECentral.StartScanning(services: nil, sender: this)
    }

    func scanning(lobby: RolePickerController) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch (msg) {

            case is BLECentral.StartScanning:
                self.startScanning(lobby: lobby)
                ^{
                    lobby.navigationItem.rightBarButtonItem?.title = lobby.states.connect
                    lobby.self.navigationItem.prompt = "Connect to an iOS or macOS device"
                    lobby.remote.alpha = 0.3
                    lobby.camera.alpha = 0.3
                    lobby.remote.isEnabled = false
                    lobby.camera.isEnabled = false
                    lobby.instructionLabel.text = "Connect to an iOS or macOS device"
                }

            case let w as OnConnectToDevice:
                if let c = self.browser {
                    DispatchQueue.main.async {
                        c.dismiss(animated: true, completion: { [unowned self] in
                            self.browser = nil
                        })
                    }
                }
                self.become(name: self.states.connected, state: self.connected(lobby: lobby, peer: w.peer))
                self.mcAdvertiserAssistant.stop()

            case is Disconnect:
                self.this ! BLECentral.StartScanning(services: nil, sender: self.this)

            case is UICmd.BecomeCamera,
                 is UICmd.BecomeMonitor,
                 is UICmd.ToggleConnect:
                self.startScanning(lobby: lobby)

            default:
                self.receive(msg: msg)
            }
        }
    }

    override public func receiveWithCtrl(ctrl: RolePickerController) -> Receive {
        return { [unowned self](msg: Message) in
            switch (msg) {
            case is UICmd.StartScanning:
                self.become(name: self.states.scanning, state: self.scanning(lobby: ctrl))
                self.this ! BLECentral.StartScanning(services: nil, sender: self.this)

            default:
                self.receive(msg: msg)
            }
        }
    }

    var browser: MCBrowserViewController?

    func startScanning(lobby: RolePickerController) {
        ^{
            lobby.navigationController?.popToViewController(lobby, animated: true)
        }
        ^{
            self.session = MCSession(peer: self.peerID)
            self.session.delegate = self
            self.browser = MCBrowserViewController(serviceType: self.service, session: self.session)

            if let browser = self.browser {
                browser.delegate = self;
                browser.minimumNumberOfPeers = 2
                browser.maximumNumberOfPeers = 2
                browser.modalPresentationStyle = UIModalPresentationStyle.formSheet
                self.mcAdvertiserAssistant = MCAdvertiserAssistant(serviceType: self.service, discoveryInfo: nil, session: self.session)
                self.mcAdvertiserAssistant.start()
                lobby.present(browser, animated: true, completion: nil)
            }
        }
    }

    public func unableToProcessError(msg: Message) -> NSError {
        return NSError(domain: "Unable to process \(type(of: msg)) command, since \(UIDevice.current.name) is not in the camera screen.", code: 0, userInfo: nil)
    }

    override public func receive(msg: Actor.Message) {
        switch (msg) {

        case let m as UICmd.BecomeCamera:
            ^{
                m.ctrl.navigationController?.popViewController(animated: true)
            }

        case let m as UICmd.BecomeMonitor:
            m.sender! ! UICmd.BecomeMonitorFailed(sender: this)

        case is RemoteCmd.TakePic:
            let l = RemoteCmd.TakePicResp(sender: this, error: self.unableToProcessError(msg: msg))
            self.sendAndForget(peer: self.session.connectedPeers, msg: l)

        case is RemoteCmd.ToggleCamera:
            let l = RemoteCmd.ToggleCameraResp(flashMode: nil, camPosition: nil, error: self.unableToProcessError(msg: msg))
            self.sendAndForget(peer: self.session.connectedPeers, msg: l)

        case is RemoteCmd.ToggleFlash:
            let l = RemoteCmd.ToggleFlashResp(flashMode: nil, error: self.unableToProcessError(msg: msg))
            self.sendAndForget(peer: self.session.connectedPeers, msg: l)

        default:
            super.receive(msg: msg)
        }
    }

    @objc func image(image: UIImage, didFinishSavingWithError error: ErrorPointer, contextInfo: UnsafeRawPointer) {
        if let errorInstance = error,
           let nsError = errorInstance.pointee {
            this ! UICmd.FailedToSaveImage(sender: nil, error: nsError)
        }
    }

    public func sendMessage(peer: [MCPeerID], msg: Actor.Message, mode: MCSessionSendDataMode = .reliable) -> Try<Message> {
        do {
            let serializedMessage = try NSKeyedArchiver.archivedData(withRootObject: msg, requiringSecureCoding: false)
            try self.session.send(serializedMessage,
                    toPeers: peer,
                    with: mode)
            return Success(value: msg)
        } catch let error as NSError {
            print("error \(error)")
            return Failure(error: error)
        }
    }
    
    public func sendAndForget(peer: [MCPeerID], msg: Actor.Message, mode: MCSessionSendDataMode = .reliable) {
            let _ = sendMessage(peer: peer, msg: msg, mode: mode)
    }

    public func browserViewControllerDidFinish(_ browserViewController: MCBrowserViewController) {
        browserViewController.dismiss(animated: true) { () in
        }
    }

    public func browserViewControllerWasCancelled(_ browserViewController: MCBrowserViewController) {
        //TODO: add dialog to force the person to connect with a phone
        browserViewController.dismiss(animated: true) { () in
        }
    }

    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
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
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let inboundMessage = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data)
        switch (inboundMessage) {
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
