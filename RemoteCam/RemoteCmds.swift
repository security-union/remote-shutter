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

    public class SendFrame: Actor.Message {
        public let data: Data
        public let fps: NSInteger
        public let camPosition: AVCaptureDevice.Position
        public let camOrientation: UIInterfaceOrientation

        init(data: Data, sender: ActorRef?, fps: NSInteger, camPosition: AVCaptureDevice.Position, camOrientation: UIInterfaceOrientation) {
            self.data = data
            self.fps = fps
            self.camPosition = camPosition
            self.camOrientation = camOrientation
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

        init(data: Data, sender: ActorRef?, peerId: MCPeerID, fps: NSInteger, camPosition: AVCaptureDevice.Position, camOrientation: UIInterfaceOrientation) {
            self.camPosition = camPosition
            self.data = data
            self.peerId = peerId
            self.fps = fps
            self.camOrientation = camOrientation
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

        public init(availableLenses: [CameraLensType], hasFlash: Bool, hasTorch: Bool, zoomCapabilities: [CameraLensType: ZoomRange]) {
            self.availableLenses = availableLenses
            self.hasFlash = hasFlash
            self.hasTorch = hasTorch
            self.zoomCapabilities = Dictionary(uniqueKeysWithValues: zoomCapabilities.map { key, value in (key.rawValue, value) })
        }

        public func getZoomCapabilities() -> [CameraLensType: ZoomRange] {
            return Dictionary(uniqueKeysWithValues: zoomCapabilities.compactMap { (rawValue, range) in
                guard let lensType = CameraLensType(rawValue: rawValue) else { return nil }
                return (lensType, range)
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
        public let error: Error?

        public init(frontCamera: CameraInfo?, backCamera: CameraInfo?,
                   currentCamera: AVCaptureDevice.Position, currentLens: CameraLensType,
                   currentZoom: CGFloat, error: Error?) {
            self.frontCamera = frontCamera
            self.backCamera = backCamera
            self.currentCamera = currentCamera
            self.currentLens = currentLens
            self.currentZoom = currentZoom
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
}
