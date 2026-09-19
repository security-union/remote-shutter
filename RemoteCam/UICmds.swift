//
//  UICmds.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 10/7/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import MPCCompat
import Stormo
import UIKit
import AVFoundation

enum RecordingMode {
    case Photo
    case Video
    case Shorts
}

/// Commands that travel within one device: a screen to the session coordinator,
/// or the coordinator to itself. They are never serialized — anything that has
/// to reach the peer crosses as a `RemoteCmd`, in FlatBuffers — so a UICmd is
/// a plain in-process value with no wire representation to keep in step.
public class UICmd {

    /// Sent by a transient state to itself after a delay to prevent getting stuck
    /// waiting for a response that never arrives. The generation counter ensures
    /// stale timeouts from a previous entry into the same state are ignored.
    public class StateTimeout: Message, @unchecked Sendable {
        let stateName: RemoteCamState
        let generation: Int
        init(stateName: RemoteCamState, generation: Int) {
            self.stateName = stateName
            self.generation = generation
            super.init(sender: nil)
        }
    }

    public class MicrophoneAccessDenied: Message, @unchecked Sendable {
        let error: Error

        init(error: Error) {
            self.error = error
            super.init(sender: nil)
        }
    }

    /// The camera's pipeline ended a recording abnormally — storage gate
    /// refusal, a writer that could not start, or a writer that died mid-take
    /// (disk full). By the time this is sent the pipeline has already reset
    /// its state and saved any salvageable footage; the coordinator's job is
    /// to report the error to the remote and return the camera to idle.
    public class RecordingTerminated: Message, @unchecked Sendable {
        let error: NSError

        init(error: NSError) {
            self.error = error
            super.init(sender: nil)
        }
    }

    /// The on-camera stop button, available whenever a recording is running.
    /// Finalizes and saves the clip locally; the remote observes the state
    /// change through the camera's report.
    public class StopRecordingLocally: Message, @unchecked Sendable {
        init() { super.init(sender: nil) }
    }

    public class StartScanning: Message, @unchecked Sendable {
    }

    /// The scanner screen is on display. Reported as the fact it is, because
    /// two things cause it: the user navigating out of a session, and the
    /// machine popping back here itself. Only the states that hold a session
    /// act on it, and those can only be the first.
    public class ScannerDidAppear: Message, @unchecked Sendable {
    }

    /// The user stopped looking for peers, which also abandons a peer we were
    /// waiting for — you cannot wait for one while not looking.
    public class StopScanning: Message, @unchecked Sendable {
    }

    /// The user dismissed the connecting overlay while an invite was in flight.
    public class CancelConnect: Message, @unchecked Sendable {
    }

    public class UnbecomeCamera: Message, @unchecked Sendable {
    }

    public class BecomeCamera: Message, @unchecked Sendable {
        let ctrl: CameraControlling

        init(sender: AnyObject?, ctrl: CameraControlling) {
            self.ctrl = ctrl
            super.init(sender: sender)
        }
    }

    public class OnPicture: Message, @unchecked Sendable {

        public let pic: Data?
        public let error: Error?

        public init(sender: AnyObject?, pic: Data) {
            self.pic = pic
            self.error = nil
            super.init(sender: sender)
        }

        public init(sender: AnyObject?, error: Error) {
            self.pic = nil
            self.error = error
            super.init(sender: sender)
        }
    }

    // MARK: - Camera Preview Mode Commands

    /// Set the camera device's local-preview mode (on / standby). Role-directed
    /// by whoever holds the coordinator:
    /// - on the **camera** device it applies + persists the mode locally (a
    ///   local toggle from the camera's own chrome), then reports back;
    /// - on the **monitor** device it forwards to the camera peer as
    ///   `RemoteCmd.SetCameraPreviewMode` (capability-gated).
    /// Either way there is one persisted preference on the camera phone.
    public class SetCameraPreviewMode: Message, @unchecked Sendable {
        public let mode: CameraPreviewMode

        public init(mode: CameraPreviewMode) {
            self.mode = mode
            super.init(sender: nil)
        }
    }

    // MARK: - Video Resource Transfer Messages

    public class SendVideoResource: Message, @unchecked Sendable {
        public let videoURL: URL
        public let peers: [MCPeerID]
        public let shouldSendToPeer: Bool

        public init(videoURL: URL, peers: [MCPeerID], shouldSendToPeer: Bool, sender: AnyObject?) {
            self.videoURL = videoURL
            self.peers = peers
            self.shouldSendToPeer = shouldSendToPeer
            super.init(sender: sender)
        }
    }

    public class VideoResourceTransferStarted: Message, @unchecked Sendable {
        public let totalBytes: Int64
        public let resourceName: String

        public init(totalBytes: Int64, resourceName: String, sender: AnyObject?) {
            self.totalBytes = totalBytes
            self.resourceName = resourceName
            super.init(sender: sender)
        }
    }

    public class VideoResourceTransferProgress: Message, @unchecked Sendable {
        public let completedBytes: Int64
        public let totalBytes: Int64
        public let progress: Double
        public let resourceName: String
        public let transferSpeed: Double // bytes per second

        public init(completedBytes: Int64, totalBytes: Int64, progress: Double, resourceName: String, transferSpeed: Double = 0.0, sender: AnyObject?) {
            self.completedBytes = completedBytes
            self.totalBytes = totalBytes
            self.progress = progress
            self.resourceName = resourceName
            self.transferSpeed = transferSpeed
            super.init(sender: sender)
        }
    }

    public class VideoResourceTransferCompleted: Message, @unchecked Sendable {
        public let resourceName: String
        public let success: Bool

        public init(resourceName: String, success: Bool, sender: AnyObject?) {
            self.resourceName = resourceName
            self.success = success
            super.init(sender: sender)
        }
    }

    // MARK: - Browser Events

    public class BrowserFoundPeer: Message, @unchecked Sendable {
        public let peer: MCPeerID

        public init(peer: MCPeerID) {
            self.peer = peer
            super.init(sender: nil)
        }
    }

    /// Inbound traffic arrived from the peer — proof the link is alive.
    public class PeerTrafficObserved: Message, @unchecked Sendable {
    }

    /// The app came back to the foreground. Suspension kills the peer session
    /// within seconds and the notice lands on a frozen process, so this is the
    /// session's cue to distrust what it believes and re-arm the radios.
    public class AppForegrounded: Message, @unchecked Sendable {
    }

    /// The user cancelled the peer-backgrounded reconnect dialog.
    public class CancelReconnect: Message, @unchecked Sendable {
    }

    /// Fixed-cadence tick of the reconnect retry loop (scanning state only).
    public class RetryReconnect: Message, @unchecked Sendable {
        public let peer: MCPeerID

        public init(peer: MCPeerID) {
            self.peer = peer
            super.init(sender: nil)
        }
    }

    public class BrowserLostPeer: Message, @unchecked Sendable {
        public let peer: MCPeerID

        public init(peer: MCPeerID) {
            self.peer = peer
            super.init(sender: nil)
        }
    }

    public class BrowserFailed: Message, @unchecked Sendable {
        public let error: Error

        public init(error: Error) {
            self.error = error
            super.init(sender: nil)
        }
    }

    public class VideoResourceTransferFailed: Message, @unchecked Sendable {
        public let error: Error
        public let resourceName: String

        public init(error: Error, resourceName: String, sender: AnyObject?) {
            self.error = error
            self.resourceName = resourceName
            super.init(sender: sender)
        }
    }

}

// MARK: - Watch Remote Mode commands

extension UICmd {
    /// Sent by WatchRemoteCameraController to enter Watch Remote camera mode.
    public class BecomeWatchCamera: Message, @unchecked Sendable {
        let ctrl: CameraControlling

        init(ctrl: CameraControlling) {
            self.ctrl = ctrl
            super.init(sender: nil)
        }
    }

    /// Sent by WatchRemoteCameraController when exiting Watch Remote mode.
    public class UnbecomeWatchCamera: Message, @unchecked Sendable {}

    /// A Watch `.requeststate` command routed into the coordinator so the reply is
    /// authoritative: the coordinator answers `reply` with an encoded ack+state
    /// message (Ok + snapshot in a watch state, `.notinwatchmode` otherwise). The
    /// FIFO inbox guarantees the answer reflects the machine's real state, so an
    /// Ok can never precede — and then lose — a separately-channelled state push.
    public class RequestWatchStateReply: Message, @unchecked Sendable {
        let reply: (Data) -> Void

        init(reply: @escaping (Data) -> Void) {
            self.reply = reply
            super.init(sender: nil)
        }
    }

    /// Watch-initiated photo/video mode switch.
    public class SetWatchCameraMode: Message, @unchecked Sendable {
        let mode: RecordingMode

        init(mode: RecordingMode) {
            self.mode = mode
            super.init(sender: nil)
        }
    }

    /// Multicam director "collecting" mode: while set, the scanner accumulates
    /// connected cameras instead of advancing on the first connect. Sent by
    /// the scanner for the monitor role.
    public class SetMulticamCollecting: Message, @unchecked Sendable {
        let on: Bool
        init(on: Bool) {
            self.on = on
            super.init(sender: nil)
        }
    }

}
