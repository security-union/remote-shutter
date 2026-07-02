//
//  RemoteCmds.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 10/7/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import MultipeerConnectivity


func getDeviceInfo() -> (Int, String, String) {
    if let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
       let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
        return (Int(bundleVersion) ?? 0, shortVersion, UIDevice.current.model)
    } else {
        return (0, "0", "UNKNOWN")
    }
}

public class RemoteCmd: Actor.Message {

    public class StartRecordingVideo: RemoteCmd {
        public override init(sender: ActorRef?) {
            super.init(sender: sender)
        }
    }

    public class StartRecordingVideoAck: RemoteCmd {
        let recordingStartTime: Date?
        let error: Error?

        public override init(sender: ActorRef?) {
            self.recordingStartTime = nil
            self.error = nil
            super.init(sender: sender)
        }

        public init(sender: ActorRef?, recordingStartTime: Date?) {
            self.recordingStartTime = recordingStartTime
            self.error = nil
            super.init(sender: sender)
        }

        public init(sender: ActorRef?, recordingStartTime: Date?, error: Error?) {
            self.recordingStartTime = recordingStartTime
            self.error = error
            super.init(sender: sender)
        }
    }

    public class StopRecordingVideo: RemoteCmd {
        let sendMediaToPeer: Bool

        public override init(sender: ActorRef?) {
            self.sendMediaToPeer = false
            super.init(sender: sender)
        }

        public init(sender: ActorRef?, sendMediaToPeer: Bool) {
            self.sendMediaToPeer = sendMediaToPeer
            super.init(sender: sender)
        }
    }

    public class StopRecordingVideoAck: RemoteCmd {
        public override init(sender: ActorRef? = nil) {
            super.init(sender: sender)
        }
    }

    public class StopRecordingVideoResp: Actor.Message {
        let video: Data?
        let error: Error?

        public init(sender: ActorRef?, video: Data) {
            self.video = video
            self.error = nil
            super.init(sender: sender)
        }

        public init(sender: ActorRef?, pic: Data?, error: Error?) {
            self.video = pic
            self.error = error
            super.init(sender: sender)
        }

        public init(sender: ActorRef?, error: Error) {
            self.video = nil
            self.error = error
            super.init(sender: sender)
        }
    }

    public class TakePic: RemoteCmd {
        let sendMediaToPeer: Bool

        public override init(sender: ActorRef?) {
            self.sendMediaToPeer = false
            super.init(sender: sender)
        }

        public init(sender: ActorRef?, sendMediaToPeer: Bool) {
            self.sendMediaToPeer = sendMediaToPeer
            super.init(sender: sender)
        }
    }

    public class TakePicAck: Actor.Message {
        public override init(sender: ActorRef?) {
            super.init(sender: sender)
        }
    }

    public class TakePicResp: Actor.Message {
        let pic: Data?
        let error: Error?

        public init(sender: ActorRef?, pic: Data) {
            self.pic = pic
            self.error = nil
            super.init(sender: sender)
        }

        public init(sender: ActorRef?, pic: Data?, error: Error?) {
            self.pic = pic
            self.error = error
            super.init(sender: sender)
        }

        public init(sender: ActorRef?, error: Error) {
            self.pic = nil
            self.error = error
            super.init(sender: sender)
        }
    }

    /// Payload format of a streamed preview frame. Mirrors the wire enum
    /// `RemoteShutter_StreamCodec`; frames from peers that predate the field
    /// arrive as `.jpeg`. `.hevc` is reserved for the video-codec follow-up.
    public enum StreamCodec {
        case jpeg
        case hevc
        case heic
    }

    public class SendFrame: Actor.Message {
        public let data: Data
        public let fps: NSInteger
        public let camPosition: AVCaptureDevice.Position
        public let camOrientation: UIInterfaceOrientation
        public let codec: StreamCodec
        public let sequenceNumber: UInt32

        init(data: Data,
             sender: ActorRef?,
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

    public class RequestFrame: Actor.Message {
        public override init(sender: ActorRef?) {
            super.init(sender: sender)
        }
    }

    public class OnFrame: Actor.Message {
        public let data: Data
        public let peerId: MCPeerID
        public let fps: NSInteger
        public let camPosition: AVCaptureDevice.Position
        public let camOrientation: UIInterfaceOrientation
        public let codec: StreamCodec
        public let sequenceNumber: UInt32

        init(data: Data,
             sender: ActorRef?,
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

    public class SetZoom: Actor.Message {
        public let zoomFactor: CGFloat

        public init(zoomFactor: CGFloat) {
            self.zoomFactor = zoomFactor
            super.init(sender: nil)
        }
    }

    // MARK: - Camera Capabilities Structure

    public struct CameraInfo: Codable {
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

    public struct ZoomRange: Codable {
        public let minZoom: CGFloat
        public let maxZoom: CGFloat

        public init(minZoom: CGFloat, maxZoom: CGFloat) {
            self.minZoom = minZoom
            self.maxZoom = maxZoom
        }
    }

    // MARK: - Enhanced Camera Response

    public class CameraCapabilitiesResp: Actor.Message {
        public let frontCamera: CameraInfo?
        public let backCamera: CameraInfo?
        public let currentCamera: AVCaptureDevice.Position
        public let currentLens: CameraLensType
        public let currentZoom: CGFloat
        public let currentVideoResolution: VideoResolution
        public let currentVideoFrameRate: VideoFrameRate
        public let currentPhotoFormat: PhotoFormat
        public let currentHDRMode: HDRMode
        public let error: Error?

        public init(frontCamera: CameraInfo?, backCamera: CameraInfo?,
                   currentCamera: AVCaptureDevice.Position, currentLens: CameraLensType,
                   currentZoom: CGFloat,
                   currentVideoResolution: VideoResolution = .hd1080p,
                   currentVideoFrameRate: VideoFrameRate = .fps30,
                   currentPhotoFormat: PhotoFormat = .jpeg,
                   currentHDRMode: HDRMode = .off,
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
            self.error = error
            super.init(sender: nil)
        }

        public func getCurrentCameraInfo() -> CameraInfo? {
            return currentCamera == .front ? frontCamera : backCamera
        }
    }

    // MARK: - Lens Switching Remote Commands

    public class SwitchLens: Actor.Message {
        public let lensType: CameraLensType

        public init(lensType: CameraLensType) {
            self.lensType = lensType
            super.init(sender: nil)
        }
    }

    public class SwitchLensResp: Actor.Message {
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

    public class PeerBecameCamera: Actor.Message {
        let bundleVersion: Int, shortVersion: String, platform: String

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

    public class PeerBecameMonitor: Actor.Message {
        let bundleVersion: Int, shortVersion: String, platform: String

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

    public class ToggleFlash: Actor.Message {
        public init() {
            super.init(sender: nil)
        }
    }

    public class ToggleFlashResp: Actor.Message {
        public let error: Error?
        public let flashMode: AVCaptureDevice.FlashMode?

        public init(flashMode: AVCaptureDevice.FlashMode?, error: Error?) {
            self.flashMode = flashMode
            self.error = error
            super.init(sender: nil)
        }
    }

    // MARK: - Torch Commands for Video Recording

    public class ToggleTorch: Actor.Message {
        public init() {
            super.init(sender: nil)
        }
    }

    public class ToggleTorchResp: Actor.Message {
        public let error: Error?
        public let torchMode: AVCaptureDevice.TorchMode?

        public init(torchMode: AVCaptureDevice.TorchMode?, error: Error?) {
            self.torchMode = torchMode
            self.error = error
            super.init(sender: nil)
        }
    }

    public class SetTorch: Actor.Message {
        public let torchMode: AVCaptureDevice.TorchMode

        public init(torchMode: AVCaptureDevice.TorchMode) {
            self.torchMode = torchMode
            super.init(sender: nil)
        }
    }

    public class SetTorchResp: Actor.Message {
        public let error: Error?
        public let torchMode: AVCaptureDevice.TorchMode?

        public init(torchMode: AVCaptureDevice.TorchMode?, error: Error?) {
            self.torchMode = torchMode
            self.error = error
            super.init(sender: nil)
        }
    }

    public class ToggleCamera: Actor.Message {
        public init() {
            super.init(sender: nil)
        }
    }

    public class ToggleCameraResp: Actor.Message {
        public let error: Error?
        public let cameraCapabilities: CameraCapabilitiesResp?

        public init(cameraCapabilities: CameraCapabilitiesResp?, error: Error?) {
            self.cameraCapabilities = cameraCapabilities
            self.error = error
            super.init(sender: nil)
        }
    }

    public class SetZoomResp: Actor.Message {
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

    public class RequestCameraCapabilities: Actor.Message {
        public init() {
            super.init(sender: nil)
        }
    }

    // MARK: - Video Quality Commands

    public class SetVideoQuality: Actor.Message {
        public let resolution: VideoResolution
        public let frameRate: VideoFrameRate

        public init(resolution: VideoResolution, frameRate: VideoFrameRate) {
            self.resolution = resolution
            self.frameRate = frameRate
            super.init(sender: nil)
        }
    }

    public class SetVideoQualityResp: Actor.Message {
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

    public class SetPhotoQuality: Actor.Message {
        public let format: PhotoFormat
        public let hdrMode: HDRMode

        public init(format: PhotoFormat, hdrMode: HDRMode) {
            self.format = format
            self.hdrMode = hdrMode
            super.init(sender: nil)
        }
    }

    public class SetPhotoQualityResp: Actor.Message {
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

    public class TimerCountdown: Actor.Message {
        public let value: Int

        public init(value: Int) {
            self.value = value
            super.init(sender: nil)
        }
    }

    // MARK: - Sync Monitor Settings Command

    public class SyncMonitorSettings: Actor.Message {
        let mode: RecordingMode

        init(mode: RecordingMode) {
            self.mode = mode
            super.init(sender: nil)
        }
    }

    // MARK: - Aspect Ratio Commands

    public class SetAspectRatio: Actor.Message {
        public let aspectRatio: AspectRatio

        public init(aspectRatio: AspectRatio) {
            self.aspectRatio = aspectRatio
            super.init(sender: nil)
        }
    }

    public class SetAspectRatioResp: Actor.Message {
        public let aspectRatio: AspectRatio?
        public let error: Error?

        public init(aspectRatio: AspectRatio?, error: Error?) {
            self.aspectRatio = aspectRatio
            self.error = error
            super.init(sender: nil)
        }
    }
}
