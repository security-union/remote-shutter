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

        public func encode(with aCoder: NSCoder) {
            if let flashMode = self.flashMode {
                aCoder.encode(flashMode.rawValue, forKey: "flashMode")
            }

            if let camPosition = self.camPosition {
                aCoder.encode(camPosition.rawValue, forKey: "camPosition")
            }

            if let e = self.error {
                aCoder.encode(e, forKey: "error")
            }
        }

        public required init?(coder aDecoder: NSCoder) {
            self.error = aDecoder.decodeObject(forKey: "error") as? Error
            if let _ = self.error {
                self.flashMode = nil
                self.camPosition = nil
            } else {
                self.flashMode = AVCaptureDevice.FlashMode(rawValue: aDecoder.decodeInteger(forKey: "flashMode"))
                self.camPosition = AVCaptureDevice.Position(rawValue: aDecoder.decodeInteger(forKey: "camPosition"))
            }
            super.init(sender: nil)
        }
    }
}
