//
//  RemoteCmds.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 10/7/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import Theater
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

    @objc(_TtCC10ActorsDemo9RemoteCmd7TStartRecordingVideo)public class StartRecordingVideo: RemoteCmd, NSCoding {
        public func encode(with aCoder: NSCoder) {
        }

        public override init(sender: ActorRef?) {
            super.init(sender: sender)
        }

        public required init?(coder aDecoder: NSCoder) {
            super.init(sender: nil)
        }
    }

    @objc(_TtCC10ActorsDemo9RemoteCmd7StartRecordingVideoAck)public class StartRecordingVideoAck: RemoteCmd, NSCoding {
        public func encode(with aCoder: NSCoder) {
        }

        public override init(sender: ActorRef?) {
            super.init(sender: sender)
        }

        public required init?(coder aDecoder: NSCoder) {
            super.init(sender: nil)
        }
    }

    @objc(_TtCC10ActorsDemo9RemoteCmd7StopRecordingVideo)public class StopRecordingVideo: RemoteCmd, NSCoding {
        let sendMediaToPeer: Bool;
        
        public func encode(with aCoder: NSCoder) {
            aCoder.encode(sendMediaToPeer, forKey: "sendMediaToPeer")
        }

        public override init(sender: ActorRef?) {
            self.sendMediaToPeer = false;
            super.init(sender: sender)
        }
        
        public init(sender: ActorRef?, sendMediaToPeer: Bool) {
            self.sendMediaToPeer = sendMediaToPeer;
            super.init(sender: sender)
        }

        public required init?(coder aDecoder: NSCoder) {
            self.sendMediaToPeer = aDecoder.decodeBool(forKey: "sendMediaToPeer")
            super.init(sender: nil)
        }
    
    }

    @objc(_TtCC10ActorsDemo9RemoteCmd7StopRecordingVideoAck)public class StopRecordingVideoAck: RemoteCmd, NSCoding {
        public func encode(with aCoder: NSCoder) {
        }

        public override init(sender: ActorRef? = nil) {
            super.init(sender: sender)
        }

        public required init?(coder aDecoder: NSCoder) {
            super.init(sender: nil)
        }
    }

    @objc(_TtCC10ActorsDemo9RemoteCmd11StopRecordingVideo)public class StopRecordingVideoResp: Actor.Message, NSCoding {

        let video: Data?
        let error: Error?

        public func encode(with aCoder: NSCoder) {
            if let pic = self.video {
                aCoder.encode(pic)
            }

            if let error = self.error {
                aCoder.encode(error, forKey: "error")
            }
        }

        public required init?(coder aDecoder: NSCoder) {
            self.video = aDecoder.decodeData()

            //TOFIX: This could be a flatmap
            if let error = aDecoder.decodeObject(forKey: "error") {
                self.error = error as? Error
            } else {
                self.error = nil
            }

            super.init(sender: nil)
        }

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

    @objc(_TtCC10ActorsDemo9RemoteCmd7TakePic)public class TakePic: RemoteCmd, NSCoding {
        let sendMediaToPeer: Bool;

        
        public func encode(with aCoder: NSCoder) {
            aCoder.encode(sendMediaToPeer, forKey: "sendMediaToPeer")

        }

        public override init(sender: ActorRef?) {
            self.sendMediaToPeer = false
            super.init(sender: sender)
        }

        public init(sender: ActorRef?, sendMediaToPeer: Bool) {
            self.sendMediaToPeer = sendMediaToPeer;
            super.init(sender: sender)
        }
        
        public required init?(coder aDecoder: NSCoder) {
            self.sendMediaToPeer = aDecoder.decodeBool(forKey: "sendMediaToPeer")
            super.init(sender: nil)
        }

    }

    @objc(_TtCC10ActorsDemo9RemoteCmd10TakePicAck)public class TakePicAck: Actor.Message, NSCoding {
        public override init(sender: ActorRef?) {
            super.init(sender: sender)
        }

        public func encode(with aCoder: NSCoder) {
        }

        public required init?(coder aDecoder: NSCoder) {
            super.init(sender: nil)
        }
        
    }

    @objc(_TtCC10ActorsDemo9RemoteCmd11TakePicResp)public class TakePicResp: Actor.Message, NSCoding {

        let pic: Data?
        let error: Error?

        public func encode(with aCoder: NSCoder) {
            if let pic = self.pic {
                aCoder.encode(pic)
            }

            if let error = self.error {
                aCoder.encode(error, forKey: "error")
            }
        }

        public required init?(coder aDecoder: NSCoder) {
            self.pic = aDecoder.decodeData()

            //TOFIX: This could be a flatmap
            if let error = aDecoder.decodeObject(forKey: "error") {
                self.error = error as? Error
            } else {
                self.error = nil
            }

            super.init(sender: nil)
        }

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

    @objc(_TtCC10ActorsDemo9RemoteCmd9SendFrame)public class SendFrame: Actor.Message, NSCoding {
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

        public func encode(with aCoder: NSCoder) {
            aCoder.encode(self.data)
            aCoder.encode(self.fps, forKey: "fps")
            aCoder.encode(self.camPosition.rawValue, forKey: "camPosition")
            aCoder.encode(self.camOrientation.rawValue, forKey: "camOrientation")
        }

        public required init?(coder aDecoder: NSCoder) {
            self.data = aDecoder.decodeData()!
            self.fps = aDecoder.decodeInteger(forKey: "fps")
            self.camPosition = AVCaptureDevice.Position(rawValue: aDecoder.decodeInteger(forKey: "camPosition"))!
            self.camOrientation = UIInterfaceOrientation.init(rawValue: aDecoder.decodeInteger(forKey: "camOrientation"))!
            super.init(sender: nil)
        }
    }
    
    @objc(_TtCC10ActorsDemo9RemoteCmd9SendFrameAck)public class RequestFrame: Actor.Message, NSCoding {
        public func encode(with aCoder: NSCoder) {
        }

        public override init(sender: ActorRef?) {
            super.init(sender: sender)
        }

        public required init?(coder aDecoder: NSCoder) {
            super.init(sender: nil)
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
    @objc(_TtCC10ActorsDemo9RemoteCmd7SetZoom)public class SetZoom: Actor.Message, NSCoding {
        public let zoomFactor: CGFloat
        
        public init(zoomFactor: CGFloat) {
            self.zoomFactor = zoomFactor
            super.init(sender: nil)
        }

        public func encode(with aCoder: NSCoder) {
            aCoder.encode(Float(zoomFactor), forKey: "zoomFactor")
        }

        public required init?(coder aDecoder: NSCoder) {
            self.zoomFactor = CGFloat(aDecoder.decodeFloat(forKey: "zoomFactor"))
            super.init(sender: nil)
        }
    }

    // MARK: - Camera Capabilities Structure
    public struct CameraInfo: Codable {
        public let availableLenses: [CameraLensType]
        public let hasFlash: Bool
        public let zoomCapabilities: [Int: ZoomRange] // CameraLensType.rawValue -> ZoomRange
        
        public init(availableLenses: [CameraLensType], hasFlash: Bool, zoomCapabilities: [CameraLensType: ZoomRange]) {
            self.availableLenses = availableLenses
            self.hasFlash = hasFlash
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

    // MARK: - Enhanced Camera Response (Breaking Change)
    @objc(_TtCC10ActorsDemo9RemoteCmd20CameraCapabilitiesResp)public class CameraCapabilitiesResp: Actor.Message, NSCoding {
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

        public func encode(with aCoder: NSCoder) {
            if let front = frontCamera, let frontData = try? JSONEncoder().encode(front) {
                aCoder.encode(frontData, forKey: "frontCamera")
            }
            if let back = backCamera, let backData = try? JSONEncoder().encode(back) {
                aCoder.encode(backData, forKey: "backCamera")
            }
            aCoder.encode(currentCamera.rawValue, forKey: "currentCamera")
            aCoder.encode(currentLens.rawValue, forKey: "currentLens")
            aCoder.encode(Float(currentZoom), forKey: "currentZoom")
            if let e = error {
                aCoder.encode(e, forKey: "error")
            }
        }

        public required init?(coder aDecoder: NSCoder) {
            if let frontData = aDecoder.decodeObject(forKey: "frontCamera") as? Data {
                self.frontCamera = try? JSONDecoder().decode(CameraInfo.self, from: frontData)
            } else {
                self.frontCamera = nil
            }
            
            if let backData = aDecoder.decodeObject(forKey: "backCamera") as? Data {
                self.backCamera = try? JSONDecoder().decode(CameraInfo.self, from: backData)
            } else {
                self.backCamera = nil
            }
            
            self.currentCamera = AVCaptureDevice.Position(rawValue: aDecoder.decodeInteger(forKey: "currentCamera")) ?? .back
            self.currentLens = CameraLensType(rawValue: aDecoder.decodeInteger(forKey: "currentLens")) ?? .wideAngle
            self.currentZoom = CGFloat(aDecoder.decodeFloat(forKey: "currentZoom"))
            self.error = aDecoder.decodeObject(forKey: "error") as? Error
            super.init(sender: nil)
        }
        
        public func getCurrentCameraInfo() -> CameraInfo? {
            return currentCamera == .front ? frontCamera : backCamera
        }
    }

    // MARK: - Lens Switching Remote Commands
    @objc(_TtCC10ActorsDemo9RemoteCmd10SwitchLens)public class SwitchLens: Actor.Message, NSCoding {
        public let lensType: CameraLensType
        
        public init(lensType: CameraLensType) {
            self.lensType = lensType
            super.init(sender: nil)
        }

        public func encode(with aCoder: NSCoder) {
            aCoder.encode(lensType.rawValue, forKey: "lensType")
        }

        public required init?(coder aDecoder: NSCoder) {
            let rawValue = aDecoder.decodeInteger(forKey: "lensType")
            self.lensType = CameraLensType(rawValue: rawValue) ?? .wideAngle
            super.init(sender: nil)
        }
    }

    @objc(_TtCC10ActorsDemo9RemoteCmd14SwitchLensResp)public class SwitchLensResp: Actor.Message, NSCoding {
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

        public func encode(with aCoder: NSCoder) {
            if let lens = self.lensType {
                aCoder.encode(lens.rawValue, forKey: "lensType")
            }
            if let lenses = self.availableLenses {
                aCoder.encode(lenses.map { $0.rawValue }, forKey: "availableLenses")
            }
            if let zoom = self.currentZoom {
                aCoder.encode(Float(zoom), forKey: "currentZoom")
            }
            if let range = self.zoomRange, let rangeData = try? JSONEncoder().encode(range) {
                aCoder.encode(rangeData, forKey: "zoomRange")
            }
            if let e = self.error {
                aCoder.encode(e, forKey: "error")
            }
        }

        public required init?(coder aDecoder: NSCoder) {
            // Fix: Don't exclude rawValue = 0, just check if decoding succeeds
            if aDecoder.containsValue(forKey: "lensType") {
                let lensRawValue = aDecoder.decodeInteger(forKey: "lensType")
                self.lensType = CameraLensType(rawValue: lensRawValue)
            } else {
                self.lensType = nil
            }
            
            if let lensRawValues = aDecoder.decodeObject(forKey: "availableLenses") as? [Int] {
                self.availableLenses = lensRawValues.compactMap { CameraLensType(rawValue: $0) }
            } else {
                self.availableLenses = nil
            }
            
            // Fix: Don't exclude zoom = 1.0, just check if key exists
            if aDecoder.containsValue(forKey: "currentZoom") {
                let zoomValue = aDecoder.decodeFloat(forKey: "currentZoom")
                self.currentZoom = CGFloat(zoomValue)
            } else {
                self.currentZoom = nil
            }
            
            if let rangeData = aDecoder.decodeObject(forKey: "zoomRange") as? Data {
                self.zoomRange = try? JSONDecoder().decode(ZoomRange.self, from: rangeData)
            } else {
                self.zoomRange = nil
            }
            
            self.error = aDecoder.decodeObject(forKey: "error") as? Error
            super.init(sender: nil)
        }
    }

    @objc(_TtCC10ActorsDemo9RemoteCmd16PeerBecameCamera)public class PeerBecameCamera: Actor.Message, NSCoding {
        
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

        public func encode(with aCoder: NSCoder) {
            aCoder.encode(bundleVersion, forKey: "bundleVersion")
            aCoder.encode(shortVersion, forKey: "shortVersion")
            aCoder.encode(platform, forKey: "platform")
        }

        public required init?(coder aDecoder: NSCoder) {
            self.bundleVersion = aDecoder.decodeInteger(forKey: "bundleVersion")
            self.shortVersion = aDecoder.decodeObject(forKey: "shortVersion") as? String ?? "0"
            self.platform = aDecoder.decodeObject(forKey: "platform") as? String ?? "0"
            super.init(sender: nil)
        }
        
    }

    @objc(_TtCC10ActorsDemo9RemoteCmd17PeerBecameMonitor)public class PeerBecameMonitor: Actor.Message, NSCoding {

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

        public func encode(with aCoder: NSCoder) {
            aCoder.encode(bundleVersion, forKey: "bundleVersion")
            aCoder.encode(shortVersion, forKey: "shortVersion")
            aCoder.encode(platform, forKey: "platform")
        }

        public required init?(coder aDecoder: NSCoder) {
            self.bundleVersion = aDecoder.decodeInteger(forKey: "bundleVersion")
            self.shortVersion = aDecoder.decodeObject(forKey: "shortVersion") as? String ?? "0"
            self.platform = aDecoder.decodeObject(forKey: "platform") as? String ?? "0"
            super.init(sender: nil)
        }
    }

    @objc(_TtCC10ActorsDemo9RemoteCmd11ToggleFlash)public class ToggleFlash: Actor.Message, NSCoding {
        public init() {
            super.init(sender: nil)
        }

        public func encode(with aCoder: NSCoder) {
        }

        public required init?(coder aDecoder: NSCoder) {
            super.init(sender: nil)
        }
    }

    @objc(_TtCC10ActorsDemo9RemoteCmd15ToggleFlashResp)public class ToggleFlashResp: Actor.Message, NSCoding {

        public let error: Error?
        public let flashMode: AVCaptureDevice.FlashMode?

        public init(flashMode: AVCaptureDevice.FlashMode?, error: Error?) {
            self.flashMode = flashMode
            self.error = error
            super.init(sender: nil)
        }

        public func encode(with aCoder: NSCoder) {
            if let f = self.flashMode {
                aCoder.encode(f.rawValue, forKey: "flashMode")
            }

            if let e = self.error {
                aCoder.encode(e, forKey: "error")
            }
        }

        public required init?(coder aDecoder: NSCoder) {
            self.error = aDecoder.decodeObject(forKey: "error") as? Error
            if let _ = self.error {
                self.flashMode = nil
            } else {
                self.flashMode = AVCaptureDevice.FlashMode(rawValue: aDecoder.decodeInteger(forKey: "flashMode"))!
            }
            super.init(sender: nil)
        }
    }

    @objc(_TtCC10ActorsDemo9RemoteCmd12ToggleCamera)public class ToggleCamera: Actor.Message, NSCoding {
        public init() {
            super.init(sender: nil)
        }

        public func encode(with aCoder: NSCoder) {
        }

        public required init?(coder aDecoder: NSCoder) {
            super.init(sender: nil)
        }

    }

    @objc(_TtCC10ActorsDemo9RemoteCmd16ToggleCameraResp)public class ToggleCameraResp: Actor.Message, NSCoding {

        public let error: Error?
        public let cameraCapabilities: CameraCapabilitiesResp?

        public init(cameraCapabilities: CameraCapabilitiesResp?, error: Error?) {
            self.cameraCapabilities = cameraCapabilities
            self.error = error
            super.init(sender: nil)
        }

        public func encode(with aCoder: NSCoder) {
            if let capabilities = self.cameraCapabilities {
                capabilities.encode(with: aCoder)
            }
            if let e = self.error {
                aCoder.encode(e, forKey: "error")
            }
        }

        public required init?(coder aDecoder: NSCoder) {
            self.error = aDecoder.decodeObject(forKey: "error") as? Error
            if error == nil {
                self.cameraCapabilities = CameraCapabilitiesResp(coder: aDecoder)
            } else {
                self.cameraCapabilities = nil
            }
            super.init(sender: nil)
        }
    }

    @objc(_TtCC10ActorsDemo9RemoteCmd11SetZoomResp)public class SetZoomResp: Actor.Message, NSCoding {
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

        public func encode(with aCoder: NSCoder) {
            if let zoom = self.zoomFactor {
                aCoder.encode(Float(zoom), forKey: "zoomFactor")
            }
            if let lens = self.currentLens {
                aCoder.encode(lens.rawValue, forKey: "currentLens")
            }
            if let range = self.zoomRange, let rangeData = try? JSONEncoder().encode(range) {
                aCoder.encode(rangeData, forKey: "zoomRange")
            }
            if let e = self.error {
                aCoder.encode(e, forKey: "error")
            }
        }

        public required init?(coder aDecoder: NSCoder) {
            let zoomValue = aDecoder.decodeFloat(forKey: "zoomFactor")
            self.zoomFactor = zoomValue > 0 ? CGFloat(zoomValue) : nil
            
            let lensRaw = aDecoder.decodeInteger(forKey: "currentLens")
            self.currentLens = lensRaw > 0 ? CameraLensType(rawValue: lensRaw) : nil
            
            if let rangeData = aDecoder.decodeObject(forKey: "zoomRange") as? Data {
                self.zoomRange = try? JSONDecoder().decode(ZoomRange.self, from: rangeData)
            } else {
                self.zoomRange = nil
            }
            
            self.error = aDecoder.decodeObject(forKey: "error") as? Error
            super.init(sender: nil)
        }
    }

    @objc(_TtCC10ActorsDemo9RemoteCmd23RequestCameraCapabilities)public class RequestCameraCapabilities: Actor.Message, NSCoding {
        public init() {
            super.init(sender: nil)
        }

        public func encode(with aCoder: NSCoder) {
        }

        public required init?(coder aDecoder: NSCoder) {
            super.init(sender: nil)
        }
    }
}
