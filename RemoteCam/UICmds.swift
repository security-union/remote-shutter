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

// MARK: - Shared Types (matching RemoteCmds.swift)
public struct ZoomRange: Codable {
    public let minZoom: CGFloat
    public let maxZoom: CGFloat
    
    public init(minZoom: CGFloat, maxZoom: CGFloat) {
        self.minZoom = minZoom
        self.maxZoom = maxZoom
    }
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

    public class RenderPhotoMode: Message, @unchecked Sendable {}

    public class RenderVideoMode: Message, @unchecked Sendable {}

    public class RenderVideoModeRecording: Message, @unchecked Sendable {}
    
    public class RenderShortsMode: Message, @unchecked Sendable {}

    public class BecomeMonitorFailed: Message, @unchecked Sendable {}

    public class FailedToSaveImage: Message, @unchecked Sendable {
        let error: Error

        init(sender: AnyObject?, error: Error) {
            self.error = error
            super.init(sender: sender)
        }
    }
    
    public class MicrophoneAccessDenied: Message, @unchecked Sendable {
        let error: Error

        init(error: Error) {
            self.error = error
            super.init(sender: nil)
        }
    }

    public class AddMonitor: Message, @unchecked Sendable {

    }

    public class AddImageView: Message, @unchecked Sendable {
        let imageView: UIImageView

        public required init(imageView: UIImageView) {
            self.imageView = imageView
            super.init(sender: nil)
        }
    }

    public class StartScanning: Message, @unchecked Sendable {
    }

    /// The user dismissed the connecting overlay while an invite was in flight.
    public class CancelConnect: Message, @unchecked Sendable {
    }

    public class UnbecomeCamera: Message, @unchecked Sendable {
    }

    public class UnbecomeMonitor: Message, @unchecked Sendable {
    }

    public class BecomeMonitor: Message, @unchecked Sendable {
        let presenter: MonitorPresenter
        let mode: RecordingMode

        init(presenter: MonitorPresenter, mode: RecordingMode) {
            self.presenter = presenter
            self.mode = mode
            super.init(sender: nil)
        }
    }

    public class BecomeCamera: Message, @unchecked Sendable {
        let ctrl: CameraControlling

        init(sender: AnyObject?, ctrl: CameraControlling) {
            self.ctrl = ctrl
            super.init(sender: sender)
        }
    }

    public class TakePicture: Message, @unchecked Sendable {
        let sendMediaToRemote: Bool

        public init(sender: AnyObject?, sendMediaToRemote: Bool) {
            self.sendMediaToRemote = sendMediaToRemote
            super.init(sender: sender)
        }
    }
    
    class SyncRecordingStartTime: Message, @unchecked Sendable {
        let startTime: Date
        
        public init(startTime: Date) {
            self.startTime = startTime
            super.init(sender: nil)
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

    public class RequestCameraCapabilities: Message, @unchecked Sendable {
        public init() {
            super.init(sender: nil)
        }
    }

    // MARK: - Zoom Commands
    public class SetZoom: Message, @unchecked Sendable {
        public let zoomFactor: CGFloat
        
        public init(zoomFactor: CGFloat) {
            self.zoomFactor = zoomFactor
            super.init(sender: nil)
        }
    }

    // MARK: - Focus Commands

    /// Monitor-local: the preview tap point, normalized (0..1) in the upright
    /// display image, origin top-left. Dispatched in-process to the coordinator,
    /// which forwards it to the camera peer as `RemoteCmd.FocusAtPoint`.
    public class FocusAtPoint: Message, @unchecked Sendable {
        public let x: Float
        public let y: Float

        public init(x: Float, y: Float) {
            self.x = x
            self.y = y
            super.init(sender: nil)
        }
    }

    public class SetZoomResp: Message, @unchecked Sendable {
        public let zoomFactor: CGFloat?
        public let currentLens: CameraLensType?
        public let zoomRange: ZoomRange?
        public let error: Error?

        public init(zoomFactor: CGFloat?, currentLens: CameraLensType?, zoomRange: ZoomRange?, error: Error?) {
            self.zoomFactor = zoomFactor
            self.currentLens = currentLens
            self.zoomRange = zoomRange
            self.error = error
            super.init(sender: nil)
        }
    }

    // MARK: - Lens Switching Commands
    public class SwitchLens: Message, @unchecked Sendable {
        public let lensType: CameraLensType
        
        public init(lensType: CameraLensType) {
            self.lensType = lensType
            super.init(sender: nil)
        }
    }

    public class SwitchLensResp: Message, @unchecked Sendable {
        public let lensType: CameraLensType?
        public let availableLenses: [CameraLensType]?
        public let currentZoom: CGFloat?
        public let zoomRange: ZoomRange?
        public let error: Error?

        public init(lensType: CameraLensType?, availableLenses: [CameraLensType]?, 
                   currentZoom: CGFloat?, zoomRange: ZoomRange?, error: Error?) {
            self.lensType = lensType
            self.availableLenses = availableLenses
            self.currentZoom = currentZoom
            self.zoomRange = zoomRange
            self.error = error
            super.init(sender: nil)
        }
    }

    public class ToggleFlash: Message, @unchecked Sendable {

        public init() {
            super.init(sender: nil)
        }
    }

    public class ToggleTorch: Message, @unchecked Sendable {

        public init() {
            super.init(sender: nil)
        }
    }

    public class ToggleFlashResp: Message, @unchecked Sendable {

        public let error: Error?
        public let flashMode: AVCaptureDevice.FlashMode?

        public init(flashMode: AVCaptureDevice.FlashMode?, error: Error?) {
            self.flashMode = flashMode
            self.error = error
            super.init(sender: nil)
        }
    }

    public class ToggleCamera: Message, @unchecked Sendable {

        public init() {
            super.init(sender: nil)
        }

    }

    public class ToggleCameraResp: Message, @unchecked Sendable {

        public let error: Error?
        public let flashMode: AVCaptureDevice.FlashMode?
        public let camPosition: AVCaptureDevice.Position?

        public init(flashMode: AVCaptureDevice.FlashMode?,
                    camPosition: AVCaptureDevice.Position?,
                    error: Error?) {
            self.flashMode = flashMode
            self.camPosition = camPosition
            self.error = error
            super.init(sender: nil)
        }
    }

    /// Monitor UI asks the camera peer to switch to a specific device
    /// (by uniqueID from the advertised `cameraDevices` list).
    public class SelectCameraDevice: Message, @unchecked Sendable {
        public let uniqueID: String

        public init(uniqueID: String) {
            self.uniqueID = uniqueID
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
    
    // MARK: - Video Quality Commands

    public class SetVideoQuality: Message, @unchecked Sendable {
        public let resolution: VideoResolution
        public let frameRate: VideoFrameRate

        public init(resolution: VideoResolution, frameRate: VideoFrameRate) {
            self.resolution = resolution
            self.frameRate = frameRate
            super.init(sender: nil)
        }
    }

    // MARK: - Photo Quality Commands

    public class SetPhotoQuality: Message, @unchecked Sendable {
        public let format: PhotoFormat
        public let hdrMode: HDRMode

        public init(format: PhotoFormat, hdrMode: HDRMode) {
            self.format = format
            self.hdrMode = hdrMode
            super.init(sender: nil)
        }
    }

    // MARK: - Timer Countdown Command

    public class TimerCountdown: Message, @unchecked Sendable {
        public let value: Int

        public init(value: Int) {
            self.value = value
            super.init(sender: nil)
        }
    }

    // MARK: - Sync Monitor Settings Command

    public class SyncMonitorSettings: Message, @unchecked Sendable {
        let mode: RecordingMode

        init(mode: RecordingMode) {
            self.mode = mode
            super.init(sender: nil)
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

    // MARK: - Aspect Ratio

    public class SetAspectRatio: Message, @unchecked Sendable {
        public let aspectRatio: AspectRatio

        public init(aspectRatio: AspectRatio) {
            self.aspectRatio = aspectRatio
            super.init(sender: nil)
        }
    }

    // MARK: - Streaming

    /// Raised by the monitor's frame receiver when no frame has arrived for
    /// `StreamingConfig.stallTimeout`. Monitor states respond by re-sending
    /// `RemoteCmd.RequestFrame`, re-arming the one-frame-in-flight ping-pong
    /// after a lost message on either side.
    public class StreamStalled: Message, @unchecked Sendable {
        public init() {
            super.init(sender: nil)
        }
    }

    /// Raised by the monitor's frame receiver when the VP9 preview decoder
    /// desyncs (an undecodable frame, or a sequence gap on the stateful stream).
    /// The monitor state forwards it as `RemoteCmd.RequestKeyframe` — but only to
    /// a peer that has already delivered a VP9 frame.
    public class RequestVideoKeyframe: Message, @unchecked Sendable {
        public init() {
            super.init(sender: nil)
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
}
