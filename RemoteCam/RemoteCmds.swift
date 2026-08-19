//
//  RemoteCmds.swift
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


func getDeviceInfo() -> (Int, String, String) {
    if let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
       let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
        return (Int(bundleVersion) ?? 0, shortVersion, UIDevice.current.model)
    } else {
        return (0, "0", "UNKNOWN")
    }
}

public class RemoteCmd: Message, @unchecked Sendable {

    public class StartRecordingVideo: RemoteCmd, @unchecked Sendable {
        public override init(sender: AnyObject?) {
            super.init(sender: sender)
        }
    }

    public class StartRecordingVideoAck: RemoteCmd, @unchecked Sendable {
        let recordingStartTime: Date?
        let error: Error?

        public override init(sender: AnyObject?) {
            self.recordingStartTime = nil
            self.error = nil
            super.init(sender: sender)
        }

        public init(sender: AnyObject?, recordingStartTime: Date?) {
            self.recordingStartTime = recordingStartTime
            self.error = nil
            super.init(sender: sender)
        }

        public init(sender: AnyObject?, recordingStartTime: Date?, error: Error?) {
            self.recordingStartTime = recordingStartTime
            self.error = error
            super.init(sender: sender)
        }
    }

    public class StopRecordingVideo: RemoteCmd, @unchecked Sendable {
        let sendMediaToPeer: Bool

        public override init(sender: AnyObject?) {
            self.sendMediaToPeer = false
            super.init(sender: sender)
        }

        public init(sender: AnyObject?, sendMediaToPeer: Bool) {
            self.sendMediaToPeer = sendMediaToPeer
            super.init(sender: sender)
        }
    }

    public class StopRecordingVideoAck: RemoteCmd, @unchecked Sendable {
        public override init(sender: AnyObject? = nil) {
            super.init(sender: sender)
        }
    }

    public class StopRecordingVideoResp: Message, @unchecked Sendable {
        let video: Data?
        let error: Error?

        public init(sender: AnyObject?, video: Data) {
            self.video = video
            self.error = nil
            super.init(sender: sender)
        }

        public init(sender: AnyObject?, pic: Data?, error: Error?) {
            self.video = pic
            self.error = error
            super.init(sender: sender)
        }

        public init(sender: AnyObject?, error: Error) {
            self.video = nil
            self.error = error
            super.init(sender: sender)
        }
    }

    public class TakePic: RemoteCmd, @unchecked Sendable {
        let sendMediaToPeer: Bool

        public override init(sender: AnyObject?) {
            self.sendMediaToPeer = false
            super.init(sender: sender)
        }

        public init(sender: AnyObject?, sendMediaToPeer: Bool) {
            self.sendMediaToPeer = sendMediaToPeer
            super.init(sender: sender)
        }
    }

    public class TakePicAck: Message, @unchecked Sendable {
        public override init(sender: AnyObject?) {
            super.init(sender: sender)
        }
    }

    public class TakePicResp: Message, @unchecked Sendable {
        let pic: Data?
        let error: Error?

        public init(sender: AnyObject?, pic: Data) {
            self.pic = pic
            self.error = nil
            super.init(sender: sender)
        }

        public init(sender: AnyObject?, pic: Data?, error: Error?) {
            self.pic = pic
            self.error = error
            super.init(sender: sender)
        }

        public init(sender: AnyObject?, error: Error) {
            self.pic = nil
            self.error = error
            super.init(sender: sender)
        }
    }

    /// Payload format of a streamed preview frame. Mirrors the wire enum
    /// `RemoteShutter_StreamCodec`; frames from peers that predate the field
    /// arrive as `.jpeg`. `.hevc` is reserved for the video-codec follow-up.
    /// `.vp9` is a stateful video stream (videocall-codecs): keyframe first,
    /// then inter frames in order — used on the Watch preview channel.
    public enum StreamCodec {
        case jpeg
        case hevc
        case heic
        case vp9
    }

    public class SendFrame: Message, @unchecked Sendable {
        public let data: Data
        public let fps: NSInteger
        public let camPosition: AVCaptureDevice.Position
        public let camOrientation: UIInterfaceOrientation
        public let codec: StreamCodec
        public let sequenceNumber: UInt32

        init(data: Data,
             sender: AnyObject?,
             fps: NSInteger,
             camPosition: AVCaptureDevice.Position,
             camOrientation: UIInterfaceOrientation,
             codec: StreamCodec = .jpeg,
             sequenceNumber: UInt32 = 0) {
            self.data = data
            self.fps = fps
            self.camPosition = camPosition
            self.camOrientation = camOrientation
            self.codec = codec
            self.sequenceNumber = sequenceNumber
            super.init(sender: sender)
        }
    }

    public class RequestFrame: Message, @unchecked Sendable {
        public override init(sender: AnyObject?) {
            super.init(sender: sender)
        }
    }

    /// Monitor -> camera: force the next VP9 preview frame to be a keyframe so a
    /// desynced decoder (joined mid-stream, dropped a delta frame) can re-sync
    /// without waiting for the camera's periodic keyframe. The monitor only
    /// sends this after it has received at least one VP9 frame, which proves the
    /// peer is a VP9-speaking build — old decoders read the unknown action as
    /// TakePicture, so the gate mirrors the SelectCameraDevice precedent.
    public class RequestKeyframe: Message, @unchecked Sendable {
        public override init(sender: AnyObject?) {
            super.init(sender: sender)
        }
    }

    /// Director → camera: clock-offset probe. `t0Millis` is the director's
    /// monotonic clock at send; the camera answers immediately with a
    /// `ClockSyncPong` echoing it. Only sent to peers advertising
    /// `supportsMulticam` (an old peer would decode it as Unknown and drop it).
    public class ClockSyncPing: Message, @unchecked Sendable {
        public let t0Millis: UInt64
        init(t0Millis: UInt64, sender: AnyObject? = nil) {
            self.t0Millis = t0Millis
            super.init(sender: sender)
        }
    }

    /// Camera → director: answer to `ClockSyncPing`. Echoes the director's
    /// `t0Millis` (so the director can compute RTT against its own clock) and
    /// carries the camera's monotonic clock at receipt — the pair the
    /// director's `ClockOffsetEstimator` turns into an offset sample.
    public class ClockSyncPong: Message, @unchecked Sendable {
        public let echoT0Millis: UInt64
        public let cameraClockMillis: UInt64
        init(echoT0Millis: UInt64, cameraClockMillis: UInt64, sender: AnyObject? = nil) {
            self.echoT0Millis = echoT0Millis
            self.cameraClockMillis = cameraClockMillis
            super.init(sender: sender)
        }
    }

    /// Director → camera: fire the shutter at `fireAtCameraClockMillis`, a
    /// wall-clock instant already translated into this camera's own
    /// `SyncClock` domain (the director applied the per-camera offset), so all
    /// cameras expose together. `anchorMillis` is the same instant in the
    /// director's clock — identical across every camera in the shot, so it is
    /// the alignment key each clip is stamped with. Only sent to peers that
    /// advertised `supportsMulticam`.
    public class ScheduledCapture: Message, @unchecked Sendable {
        public let fireAtCameraClockMillis: UInt64
        public let anchorMillis: UInt64
        public let captureId: String
        public let sessionId: String
        public let cameraIndex: Int

        public init(fireAtCameraClockMillis: UInt64,
                    anchorMillis: UInt64,
                    captureId: String,
                    sessionId: String,
                    cameraIndex: Int,
                    sender: AnyObject? = nil) {
            self.fireAtCameraClockMillis = fireAtCameraClockMillis
            self.anchorMillis = anchorMillis
            self.captureId = captureId
            self.sessionId = sessionId
            self.cameraIndex = cameraIndex
            super.init(sender: sender)
        }
    }

    /// Camera → director: the scheduled capture was accepted (or refused). Sent
    /// immediately on receipt — before the shutter actually fires — so the
    /// director can aggregate acks without waiting for N photos. `error` set =
    /// the camera could not schedule it (wrong state, fire time long past).
    public class ScheduledCaptureAck: Message, @unchecked Sendable {
        public let captureId: String
        public let error: Error?

        public init(captureId: String, error: Error? = nil, sender: AnyObject? = nil) {
            self.captureId = captureId
            self.error = error
            super.init(sender: sender)
        }
    }

    /// Director → camera: begin recording at `fireAtCameraClockMillis` (this
    /// camera's clock domain), so every camera rolls together. Same fields and
    /// meaning as `ScheduledCapture`. Only sent to `supportsMulticam` peers.
    public class ScheduledStartRecording: Message, @unchecked Sendable {
        public let fireAtCameraClockMillis: UInt64
        public let anchorMillis: UInt64
        public let captureId: String
        public let sessionId: String
        public let cameraIndex: Int

        public init(fireAtCameraClockMillis: UInt64, anchorMillis: UInt64,
                    captureId: String, sessionId: String, cameraIndex: Int,
                    sender: AnyObject? = nil) {
            self.fireAtCameraClockMillis = fireAtCameraClockMillis
            self.anchorMillis = anchorMillis
            self.captureId = captureId
            self.sessionId = sessionId
            self.cameraIndex = cameraIndex
            super.init(sender: sender)
        }
    }

    /// Director → camera: stop recording at the fire instant, so clip lengths
    /// line up across the rig. Reuses the same params (index/anchor unused).
    public class ScheduledStopRecording: Message, @unchecked Sendable {
        public let fireAtCameraClockMillis: UInt64
        public let anchorMillis: UInt64
        public let captureId: String
        public let sessionId: String
        public let cameraIndex: Int

        public init(fireAtCameraClockMillis: UInt64, anchorMillis: UInt64,
                    captureId: String, sessionId: String, cameraIndex: Int,
                    sender: AnyObject? = nil) {
            self.fireAtCameraClockMillis = fireAtCameraClockMillis
            self.anchorMillis = anchorMillis
            self.captureId = captureId
            self.sessionId = sessionId
            self.cameraIndex = cameraIndex
            super.init(sender: sender)
        }
    }

    /// Camera → director: the scheduled record start/stop was accepted (or
    /// refused). Immediate, like `ScheduledCaptureAck`; `isStop` distinguishes
    /// the two so the director's start/stop aggregation stay separate.
    public class ScheduledRecordingAck: Message, @unchecked Sendable {
        public let captureId: String
        public let isStop: Bool
        public let error: Error?

        public init(captureId: String, isStop: Bool, error: Error? = nil,
                    sender: AnyObject? = nil) {
            self.captureId = captureId
            self.isStop = isStop
            self.error = error
            super.init(sender: sender)
        }
    }

    /// Director → camera: reconfigure the live preview encoder for tiered
    /// multicam previews (the focused lane full-size, the rest thumbnails).
    /// Only sent to `supportsMulticam` peers.
    public class SetStreamProfile: Message, @unchecked Sendable {
        public let maxLongEdge: Int
        public let bitrateKbps: Int
        public let fps: Int

        public init(maxLongEdge: Int, bitrateKbps: Int, fps: Int, sender: AnyObject? = nil) {
            self.maxLongEdge = maxLongEdge
            self.bitrateKbps = bitrateKbps
            self.fps = fps
            super.init(sender: sender)
        }
    }

    /// Director → camera: re-send the clip for `captureId` — the auto-collect
    /// retry after a failed transfer. The camera keeps its last multicam clip
    /// until collected, so it can honor this.
    public class RequestVideoResend: Message, @unchecked Sendable {
        public let captureId: String
        public init(captureId: String, sender: AnyObject? = nil) {
            self.captureId = captureId
            super.init(sender: sender)
        }
    }

    public class OnFrame: Message, @unchecked Sendable {
        public let data: Data
        public let peerId: MCPeerID
        public let fps: NSInteger
        public let camPosition: AVCaptureDevice.Position
        public let camOrientation: UIInterfaceOrientation
        public let codec: StreamCodec
        public let sequenceNumber: UInt32

        init(data: Data,
             sender: AnyObject?,
             peerId: MCPeerID,
             fps: NSInteger,
             camPosition: AVCaptureDevice.Position,
             camOrientation: UIInterfaceOrientation,
             codec: StreamCodec = .jpeg,
             sequenceNumber: UInt32 = 0) {
            self.camPosition = camPosition
            self.data = data
            self.peerId = peerId
            self.fps = fps
            self.camOrientation = camOrientation
            self.codec = codec
            self.sequenceNumber = sequenceNumber
            super.init(sender: sender)
        }
    }

    // MARK: - Zoom Remote Commands

    public class SetZoom: Message, @unchecked Sendable {
        public let zoomFactor: CGFloat

        public init(zoomFactor: CGFloat) {
            self.zoomFactor = zoomFactor
            super.init(sender: nil)
        }
    }

    // MARK: - Focus Remote Commands

    /// Monitor -> camera: set the focus/exposure point of interest. `x`/`y` are
    /// normalized (0..1) in the monitor's upright-display image space, origin
    /// top-left. Fire-and-forget: the camera no-ops if the active device does
    /// not support a focus point. Only sent to peers that advertised
    /// `CameraCapabilitiesResp.supportsFocusPoint` (old decoders read the
    /// unknown action as `TakePicture`).
    public class FocusAtPoint: Message, @unchecked Sendable {
        public let x: Float
        public let y: Float

        public init(x: Float, y: Float) {
            self.x = x
            self.y = y
            super.init(sender: nil)
        }
    }

    /// "I am leaving on purpose." Sent by whichever side ends the session
    /// deliberately, so the peer stops reconnecting instead of chasing a
    /// session nobody is coming back to. Fire-and-forget: an unplanned
    /// disconnect simply never carries it, and the peer retries as usual.
    public class EndSession: Message, @unchecked Sendable {
        public init() {
            super.init(sender: nil)
        }
    }

    // MARK: - Camera Preview Mode Remote Commands

    /// Monitor -> camera: set the camera device's local-preview mode (on /
    /// standby). Standby stops the camera's own on-screen preview only — the
    /// capture session and the frames streamed back to the monitor are
    /// unaffected. Only sent to peers that advertised
    /// `CameraCapabilitiesResp.supportsPreviewMode` (old decoders read the
    /// unknown action as its enum default).
    public class SetCameraPreviewMode: Message, @unchecked Sendable {
        public let mode: CameraPreviewMode

        public init(mode: CameraPreviewMode) {
            self.mode = mode
            super.init(sender: nil)
        }
    }

    /// Camera -> monitor: the camera's current local-preview mode, sent as the
    /// ack to `SetCameraPreviewMode` and whenever the camera changes the mode
    /// on its own (a local toggle), so the monitor can reflect what the camera
    /// is doing.
    public class CameraPreviewModeResp: Message, @unchecked Sendable {
        public let mode: CameraPreviewMode

        public init(mode: CameraPreviewMode) {
            self.mode = mode
            super.init(sender: nil)
        }
    }

    // MARK: - Camera Capabilities Structure

    public struct CameraInfo: Codable, Equatable {
        public let availableLenses: [CameraLensType]
        public let hasFlash: Bool
        public let hasTorch: Bool
        public let zoomCapabilities: [Int: ZoomRange] // CameraLensType.rawValue -> ZoomRange
        public let supportedResolutions: [VideoResolution]
        public let supportedFrameRates: [VideoFrameRate]
        public let resolutionFrameRates: [Int: [VideoFrameRate]] // VideoResolution.rawValue -> supported FPS
        public let supportsHEIF: Bool
        public let supportsHDR: Bool
        public let zoomStops: [CGFloat] // Hardware zoom factors for each stop (e.g., [1.0, 2.0, 6.0])
        public let wideAngleZoomFactor: CGFloat // Hardware zoom factor for the wide-angle camera (the "1x" reference)

        public init(availableLenses: [CameraLensType], hasFlash: Bool, hasTorch: Bool,
                    zoomCapabilities: [CameraLensType: ZoomRange],
                    supportedResolutions: [VideoResolution] = [.hd1080p],
                    supportedFrameRates: [VideoFrameRate] = [.fps30],
                    resolutionFrameRates: [VideoResolution: [VideoFrameRate]] = [:],
                    supportsHEIF: Bool = false,
                    supportsHDR: Bool = false,
                    zoomStops: [CGFloat] = [1.0],
                    wideAngleZoomFactor: CGFloat = 1.0) {
            self.availableLenses = availableLenses
            self.hasFlash = hasFlash
            self.hasTorch = hasTorch
            self.zoomCapabilities = Dictionary(uniqueKeysWithValues: zoomCapabilities.map { key, value in (key.rawValue, value) })
            self.supportedResolutions = supportedResolutions
            self.supportedFrameRates = supportedFrameRates
            self.resolutionFrameRates = Dictionary(uniqueKeysWithValues: resolutionFrameRates.map { key, value in (key.rawValue, value) })
            self.supportsHEIF = supportsHEIF
            self.supportsHDR = supportsHDR
            self.zoomStops = zoomStops
            self.wideAngleZoomFactor = wideAngleZoomFactor
        }

        public func getZoomCapabilities() -> [CameraLensType: ZoomRange] {
            return Dictionary(uniqueKeysWithValues: zoomCapabilities.compactMap { (rawValue, range) in
                guard let lensType = CameraLensType(rawValue: rawValue) else { return nil }
                return (lensType, range)
            })
        }

        public func getResolutionFrameRates() -> [VideoResolution: [VideoFrameRate]] {
            return Dictionary(uniqueKeysWithValues: resolutionFrameRates.compactMap { (rawValue, rates) in
                guard let resolution = VideoResolution(rawValue: rawValue) else { return nil }
                return (resolution, rates)
            })
        }
    }

    public struct ZoomRange: Codable, Equatable {
        public let minZoom: CGFloat
        public let maxZoom: CGFloat

        public init(minZoom: CGFloat, maxZoom: CGFloat) {
            self.minZoom = minZoom
            self.maxZoom = maxZoom
        }
    }

    // MARK: - Camera Device List (N cameras; Macs have no front/back pair)

    /// One selectable camera on the camera peer, as advertised in
    /// `CameraCapabilitiesResp.cameraDevices`. An empty device list means the
    /// peer predates device selection — the monitor must not send
    /// `SelectCameraDevice` to it.
    public struct CameraDeviceEntry: Codable, Equatable {
        public let uniqueID: String
        public let localizedName: String
        /// AVCaptureDevice.Position.rawValue; `.unspecified` is preserved here
        /// (the wire carries Back + has_unspecified_position for old peers).
        public let positionRaw: Int
        public let isActive: Bool
        /// Connected but delivering no frames (Mac clamshell built-in camera):
        /// pickers show it grayed out; selection is rejected.
        public let isSuspended: Bool
        public let info: CameraInfo?

        public var position: AVCaptureDevice.Position {
            AVCaptureDevice.Position(rawValue: positionRaw) ?? .unspecified
        }

        public init(uniqueID: String, localizedName: String,
                    positionRaw: Int, isActive: Bool,
                    isSuspended: Bool = false, info: CameraInfo?) {
            self.uniqueID = uniqueID
            self.localizedName = localizedName
            self.positionRaw = positionRaw
            self.isActive = isActive
            self.isSuspended = isSuspended
            self.info = info
        }
    }

    // MARK: - Enhanced Camera Response

    public class CameraCapabilitiesResp: Message, @unchecked Sendable {
        public let frontCamera: CameraInfo?
        public let backCamera: CameraInfo?
        public let currentCamera: AVCaptureDevice.Position
        public let currentLens: CameraLensType
        public let currentZoom: CGFloat
        public let currentVideoResolution: VideoResolution
        public let currentVideoFrameRate: VideoFrameRate
        public let currentPhotoFormat: PhotoFormat
        public let currentHDRMode: HDRMode
        public let cameraDevices: [CameraDeviceEntry]
        public let activeDeviceID: String?
        /// True when this peer's build understands `RemoteCmd.FocusAtPoint`. The
        /// monitor's tap-to-focus gate reads this so it never sends the command
        /// to a peer that would decode it as `TakePicture`.
        public let supportsFocusPoint: Bool
        /// True when this peer's build understands
        /// `RemoteCmd.SetCameraPreviewMode`. The monitor's standby gate reads
        /// this so it never sends the command to a peer that would misread it.
        public let supportsPreviewMode: Bool
        /// True when this peer's build can join a multicam director session
        /// (scheduled capture, stream profiles). A director must not send
        /// multicam commands to a peer that doesn't advertise this.
        public let supportsMulticam: Bool
        /// The camera's current local-preview mode, so the monitor can reflect
        /// it from the first capabilities exchange.
        public let previewMode: CameraPreviewMode
        /// The camera's recording truth, straight from its pipeline: non-nil
        /// exactly while a clip is being written, carrying the real
        /// first-frame instant. Wire: `recording_start_unix_ms` (0 ⇔ nil) —
        /// every v10+ camera reports it on every capabilities exchange, and
        /// monitors DERIVE their recording UI from it instead of remembering.
        public let recordingStartedAt: Date?
        public let error: Error?

        public init(frontCamera: CameraInfo?, backCamera: CameraInfo?,
                   currentCamera: AVCaptureDevice.Position, currentLens: CameraLensType,
                   currentZoom: CGFloat,
                   currentVideoResolution: VideoResolution = .hd1080p,
                   currentVideoFrameRate: VideoFrameRate = .fps30,
                   currentPhotoFormat: PhotoFormat = .jpeg,
                   currentHDRMode: HDRMode = .off,
                   cameraDevices: [CameraDeviceEntry] = [],
                   activeDeviceID: String? = nil,
                   supportsFocusPoint: Bool = false,
                   supportsPreviewMode: Bool = false,
                   supportsMulticam: Bool = false,
                   previewMode: CameraPreviewMode = .on,
                   recordingStartedAt: Date? = nil,
                   error: Error?) {
            self.frontCamera = frontCamera
            self.backCamera = backCamera
            self.currentCamera = currentCamera
            self.currentLens = currentLens
            self.currentZoom = currentZoom
            self.currentVideoResolution = currentVideoResolution
            self.currentVideoFrameRate = currentVideoFrameRate
            self.currentPhotoFormat = currentPhotoFormat
            self.currentHDRMode = currentHDRMode
            self.cameraDevices = cameraDevices
            self.activeDeviceID = activeDeviceID
            self.supportsFocusPoint = supportsFocusPoint
            self.supportsPreviewMode = supportsPreviewMode
            self.supportsMulticam = supportsMulticam
            self.previewMode = previewMode
            self.recordingStartedAt = recordingStartedAt
            self.error = error
            super.init(sender: nil)
        }

        public func getCurrentCameraInfo() -> CameraInfo? {
            return currentCamera == .front ? frontCamera : backCamera
        }
    }

    // MARK: - Lens Switching Remote Commands

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

    /// What the two role announcements have in common: who the peer says it is.
    /// `shortVersion` is the pairing gate (see `PeerAppCompatibility`); the other
    /// two are diagnostics, carried so a refusal in the field can be read back
    /// from a log rather than guessed at.
    public protocol RoleAnnouncement {
        var bundleVersion: Int { get }
        var shortVersion: String { get }
        var platform: String { get }
    }

    public class PeerBecameCamera: Message, RoleAnnouncement, @unchecked Sendable {
        public let bundleVersion: Int, shortVersion: String, platform: String

        class func createWithDefaults() -> PeerBecameCamera {
            let (bundleVersion, shortVersion, platform) = getDeviceInfo()
            return PeerBecameCamera(bundleVersion: bundleVersion, shortVersion: shortVersion, platform: platform)
        }

        public init(bundleVersion: Int, shortVersion: String, platform: String) {
            self.bundleVersion = bundleVersion
            self.shortVersion = shortVersion
            self.platform = platform
            super.init(sender: nil)
        }
    }

    public class PeerBecameMonitor: Message, RoleAnnouncement, @unchecked Sendable {
        public let bundleVersion: Int, shortVersion: String, platform: String

        class func createWithDefaults() -> PeerBecameMonitor {
            let (bundleVersion, shortVersion, platform) = getDeviceInfo()
            return PeerBecameMonitor(bundleVersion: bundleVersion, shortVersion: shortVersion, platform: platform)
        }

        public init(bundleVersion: Int, shortVersion: String, platform: String) {
            self.bundleVersion = bundleVersion
            self.shortVersion = shortVersion
            self.platform = platform
            super.init(sender: nil)
        }
    }

    public class ToggleFlash: Message, @unchecked Sendable {
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

    // MARK: - Torch Commands for Video Recording

    public class ToggleTorch: Message, @unchecked Sendable {
        public init() {
            super.init(sender: nil)
        }
    }

    public class ToggleTorchResp: Message, @unchecked Sendable {
        public let error: Error?
        public let torchMode: AVCaptureDevice.TorchMode?

        public init(torchMode: AVCaptureDevice.TorchMode?, error: Error?) {
            self.torchMode = torchMode
            self.error = error
            super.init(sender: nil)
        }
    }

    public class SetTorch: Message, @unchecked Sendable {
        public let torchMode: AVCaptureDevice.TorchMode

        public init(torchMode: AVCaptureDevice.TorchMode) {
            self.torchMode = torchMode
            super.init(sender: nil)
        }
    }

    public class SetTorchResp: Message, @unchecked Sendable {
        public let error: Error?
        public let torchMode: AVCaptureDevice.TorchMode?

        public init(torchMode: AVCaptureDevice.TorchMode?, error: Error?) {
            self.torchMode = torchMode
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
        public let cameraCapabilities: CameraCapabilitiesResp?

        public init(cameraCapabilities: CameraCapabilitiesResp?, error: Error?) {
            self.cameraCapabilities = cameraCapabilities
            self.error = error
            super.init(sender: nil)
        }
    }

    // MARK: - Camera Device Selection (guarded by capability advertising)

    /// Switch the camera peer to the device with this uniqueID. Only valid
    /// against peers whose capabilities carried a non-empty `cameraDevices`
    /// list.
    public class SelectCameraDevice: Message, @unchecked Sendable {
        public let uniqueID: String

        public init(uniqueID: String) {
            self.uniqueID = uniqueID
            super.init(sender: nil)
        }
    }

    /// Subclasses ToggleCameraResp: the monitor treats a completed device
    /// selection exactly like a completed front/back toggle — fresh
    /// capabilities in, UI re-synced — so it shares that state's handling.
    public class SelectCameraDeviceResp: ToggleCameraResp, @unchecked Sendable {}

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

    public class RequestCameraCapabilities: Message, @unchecked Sendable {
        public init() {
            super.init(sender: nil)
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

    public class SetVideoQualityResp: Message, @unchecked Sendable {
        public let resolution: VideoResolution?
        public let frameRate: VideoFrameRate?
        public let error: Error?

        public init(resolution: VideoResolution?, frameRate: VideoFrameRate?, error: Error?) {
            self.resolution = resolution
            self.frameRate = frameRate
            self.error = error
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

    public class SetPhotoQualityResp: Message, @unchecked Sendable {
        public let format: PhotoFormat?
        public let hdrMode: HDRMode?
        public let error: Error?

        public init(format: PhotoFormat?, hdrMode: HDRMode?, error: Error?) {
            self.format = format
            self.hdrMode = hdrMode
            self.error = error
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

    // MARK: - Aspect Ratio Commands

    public class SetAspectRatio: Message, @unchecked Sendable {
        public let aspectRatio: AspectRatio

        public init(aspectRatio: AspectRatio) {
            self.aspectRatio = aspectRatio
            super.init(sender: nil)
        }
    }

    public class SetAspectRatioResp: Message, @unchecked Sendable {
        public let aspectRatio: AspectRatio?
        public let error: Error?

        public init(aspectRatio: AspectRatio?, error: Error?) {
            self.aspectRatio = aspectRatio
            self.error = error
            super.init(sender: nil)
        }
    }
}
