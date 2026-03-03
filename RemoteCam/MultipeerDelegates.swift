//
//  MultipeerDelegate.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 10/10/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
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
}

// MARK: - MultipeerServiceDelegate

extension RemoteCamSession: MultipeerServiceDelegate {

    func didReceiveMessage(_ message: Actor.Message) {
        mailbox.addOperation(BlockOperation {
            self.this ! message
        })
    }

    func didReceiveFrameRequest(_ request: RemoteCmd.RequestFrame) {
        getFrameSender()?.tell(msg: request)
    }

    func didReceiveFrame(_ frame: RemoteCmd.SendFrame, from peer: MCPeerID) {
        this ! RemoteCmd.OnFrame(data: frame.data,
            sender: nil,
            peerId: peer,
            fps: frame.fps,
            camPosition: frame.camPosition,
            camOrientation: frame.camOrientation)
    }

    func peerDidConnect(_ peer: MCPeerID) {
        mailbox.addOperation(BlockOperation {
            self.this ! OnConnectToDevice(peer: peer, sender: self.this)
        })
    }

    func peerDidDisconnect(_ peer: MCPeerID) {
        mailbox.addOperation(BlockOperation {
            self.this ! DisconnectPeer(peer: peer, sender: self.this)
        })
    }

    func didDetectIncompatibility() {
        showIncopatibilityMessage()
    }

    func didStartReceivingResource(name resourceName: String, progress: Progress) {
        mailbox.addOperation(BlockOperation {
            Log.debug("Started receiving resource: \(resourceName)")

            // Check if this is a video transfer
            if resourceName.hasPrefix("video_") {
                let totalBytes = progress.totalUnitCount
                Log.debug("Video transfer started - Total bytes: \(totalBytes)")

                // Send message through actor system
                let startedMsg = UICmd.VideoResourceTransferStarted(totalBytes: totalBytes, resourceName: resourceName, sender: self.this)
                self.this ! startedMsg

                class SpeedTracker {
                    var lastUpdateTime = Date()
                    var lastCompletedBytes: Int64 = 0
                    var lastCalculatedSpeed: Double = 0.0
                }
                let speedTracker = SpeedTracker()

                // Observe progress changes and send progress messages
                progress.publisher(for: \.fractionCompleted)
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] fractionCompleted in
                        let completedBytes = Int64(Double(progress.totalUnitCount) * fractionCompleted)

                        // Simple speed calculation
                        let currentTime = Date()
                        let timeElapsed = currentTime.timeIntervalSince(speedTracker.lastUpdateTime)
                        let bytesTransferred = completedBytes - speedTracker.lastCompletedBytes

                        Log.debug("Speed calc - timeElapsed: \(timeElapsed), bytesTransferred: \(bytesTransferred), lastCompleted: \(speedTracker.lastCompletedBytes), current: \(completedBytes)")

                        let transferSpeed: Double
                        if timeElapsed > 0.5 && bytesTransferred > 0 {
                            transferSpeed = Double(bytesTransferred) / timeElapsed
                            speedTracker.lastUpdateTime = currentTime
                            speedTracker.lastCompletedBytes = completedBytes
                            speedTracker.lastCalculatedSpeed = transferSpeed
                            Log.debug("Speed calculated: \(String(format: "%.1f", transferSpeed / 1024 / 1024)) MB/s")
                        } else {
                            transferSpeed = speedTracker.lastCalculatedSpeed
                            Log.debug("Speed calculation skipped - timeElapsed: \(timeElapsed), bytesTransferred: \(bytesTransferred), using last speed: \(String(format: "%.1f", speedTracker.lastCalculatedSpeed / 1024 / 1024)) MB/s")
                        }

                        Log.debug("Video transfer progress: \(Int(fractionCompleted * 100))% - Speed: \(String(format: "%.1f", transferSpeed / 1024 / 1024)) MB/s")

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
            }
        })
    }

    func didFinishReceivingResource(name resourceName: String, at localURL: URL?, error: Error?) {
        mailbox.addOperation(BlockOperation {
            Log.debug("Finished receiving resource: \(resourceName)")

            if let error = error {
                Log.error("Error receiving resource: \(error.localizedDescription)")

                // Send failure message through actor system
                let failedMsg = UICmd.VideoResourceTransferFailed(error: error, resourceName: resourceName, sender: self.this)
                self.this ! failedMsg
                return
            }

            // Check if this is a video transfer
            if resourceName.hasPrefix("video_") {
                Log.debug("Video transfer completed successfully")

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
                        Log.error("Error processing received video: \(error.localizedDescription)")
                        let videoResp = RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: error)
                        self.this ! videoResp
                    }
                }
            }
        })
    }
}
