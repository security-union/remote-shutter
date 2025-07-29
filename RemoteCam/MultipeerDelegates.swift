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
import Combine
import UIKit

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
        guard let inboundMessage = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) else {
            showIncopatibilityMessage()
            return
        }
        // TODO: Add logic to determine frame destination.
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

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {

    }

    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        mailbox.addOperation(BlockOperation {
            print("📥 DEBUG: Started receiving resource: \(resourceName) from \(peerID.displayName)")
            
            // Check if this is a video transfer
            if resourceName.hasPrefix("video_") {
                let totalBytes = progress.totalUnitCount
                print("📊 DEBUG: Video transfer started - Total bytes: \(totalBytes)")
                
                // Send message through actor system
                let startedMsg = UICmd.VideoResourceTransferStarted(totalBytes: totalBytes, resourceName: resourceName, sender: self.this)
                self.this ! startedMsg
                
                // Observe progress changes and send progress messages
                progress.publisher(for: \.fractionCompleted)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] fractionCompleted in
                        let completedBytes = Int64(Double(progress.totalUnitCount) * fractionCompleted)
                        print("📊 DEBUG: Video transfer progress: \(Int(fractionCompleted * 100))%")
                        
                        let progressMsg = UICmd.VideoResourceTransferProgress(
                            completedBytes: completedBytes,
                            totalBytes: progress.totalUnitCount,
                            progress: fractionCompleted,
                            resourceName: resourceName,
                            sender: self?.this
                        )
                        if let this = self?.this {
                            this ! progressMsg
                        }
                    }
                    .store(in: &self.progressCancellables)
            }
        })
    }

    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        mailbox.addOperation(BlockOperation {
            print("📥 DEBUG: Finished receiving resource: \(resourceName) from \(peerID.displayName)")
            
            if let error = error {
                print("❌ DEBUG: Error receiving resource: \(error.localizedDescription)")
                
                // Send failure message through actor system
                let failedMsg = UICmd.VideoResourceTransferFailed(error: error, resourceName: resourceName, sender: self.this)
                self.this ! failedMsg
                return
            }
            
            // Check if this is a video transfer
            if resourceName.hasPrefix("video_") {
                print("✅ DEBUG: Video transfer completed successfully")
                
                // Send completion message through actor system
                let completedMsg = UICmd.VideoResourceTransferCompleted(resourceName: resourceName, success: true, sender: self.this)
                self.this ! completedMsg
                
                // Handle the received video file
                if let localURL = localURL {
                    do {
                        let videoData = try Data(contentsOf: localURL)
                        let videoResp = RemoteCmd.StopRecordingVideoResp(sender: nil, pic: videoData, error: nil)
                        self.this ! videoResp
                        
                        // Clean up the temporary file
                        try FileManager.default.removeItem(at: localURL)
                    } catch {
                        print("❌ DEBUG: Error processing received video: \(error.localizedDescription)")
                        let videoResp = RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: error)
                        self.this ! videoResp
                    }
                }
            }
        })
    }

    @nonobjc public func session(session: MCSession, didReceiveCertificate certificate: [AnyObject]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        certificateHandler(true)
    }
}
