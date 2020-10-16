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

    let states = RemoteCamStates()

    var session: MCSession!

    let service: String = "RemoteCam"
    
    let userDefaultsPeerId = "peerID"

    var peerID: MCPeerID

    var mcAdvertiserAssistant: MCAdvertiserAssistant!
    
    var browser: MCBrowserViewController?
    
    public required init(context: ActorSystem, ref: ActorRef) {
        if let data = UserDefaults.standard.data(forKey: userDefaultsPeerId), let id = NSKeyedUnarchiver.unarchiveObject(with: data) as? MCPeerID {
              self.peerID = id
            } else {
              let peerID = MCPeerID(displayName: UIDevice.current.name)
              let data = NSKeyedArchiver.archivedData(withRootObject: peerID)
              UserDefaults.standard.set(data, forKey: userDefaultsPeerId)
              self.peerID = peerID
            }
        super.init(context: context, ref: ref)
        mailbox = OperationQueue()
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
    
    override public func receiveWithCtrl(ctrl: RolePickerController) -> Receive {
        return { [unowned self](msg: Message) in
            switch (msg) {
            case is UICmd.StartScanning,
                 is UICmd.ToggleConnect:
                self.become(name: self.states.scanning, state: self.scanning(lobby: ctrl))

            default:
                self.receive(msg: msg)
            }
        }
    }

    func popAndStartScanning() {
        self.popToState(name: self.states.scanning)
    }

    func startScanning(lobby: RolePickerController) {
        assert(Thread.isMainThread == false, "can't be called from the main thread")
        ^{
            CATransaction.begin()
            CATransaction.setCompletionBlock {
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
            lobby.navigationController?.popToViewController(lobby, animated: true)
            CATransaction.commit()
        }
    }

    public func unableToProcessError(msg: Message) -> NSError {
        return NSError(
            domain: "Unable to process \(type(of: msg)) command, since \(UIDevice.current.name) is not in the camera screen.", code: 0, userInfo: nil)
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
            sendCommandOrGoToScanning(peer: self.session.connectedPeers, msg: l)
        case is RemoteCmd.ToggleCamera:
            let l = RemoteCmd.ToggleCameraResp(
                flashMode: nil, camPosition: nil, error: self.unableToProcessError(msg: msg)
            )
            self.sendCommandOrGoToScanning(peer: self.session.connectedPeers, msg: l)

        case is RemoteCmd.ToggleFlash:
            let l = RemoteCmd.ToggleFlashResp(
                flashMode: nil, error: self.unableToProcessError(msg: msg)
            )
            self.sendCommandOrGoToScanning(peer: self.session.connectedPeers, msg: l)

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
            return Success(value: msg)
        } catch let error as NSError {
            print("sendMessage error \(error)")
            return Failure(error: error)
        }
    }
    
    public func sendCommandOrGoToScanning(peer: [MCPeerID],
                                          msg: Actor.Message,
                                          mode: MCSessionSendDataMode = .reliable) {
        assert(Thread.isMainThread == false, "can't be called from the main thread")
        if (self.sendMessage(peer: self.session.connectedPeers, msg: msg).isFailure()) {
            self.popToState(name: self.states.scanning)
            ^{
            let alert = UIAlertController(
                title: NSLocalizedString("Connection error", comment: ""),
                message: NSLocalizedString("Peer disconnected, please reconnect", comment: ""),
                preferredStyle: .alert)
            
                alert.simpleOkAction()
                alert.show(true)
            }
        }
    }
}
