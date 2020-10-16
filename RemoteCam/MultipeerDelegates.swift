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


extension RemoteCamSession {
    public func browserViewControllerDidFinish(_ browserViewController: MCBrowserViewController) {
        browserViewController.dismiss(animated: true)
    }

    public func browserViewControllerWasCancelled(_ browserViewController: MCBrowserViewController) {
        //TODO: add dialog to force the person to connect with a phone
        browserViewController.dismiss(animated: true)
    }
    
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        mailbox.addOperation {
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
