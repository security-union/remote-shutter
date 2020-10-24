//
//  UICmds.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 10/7/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import Theater
import MultipeerConnectivity

enum RecordingMode {
    case Photo
    case Video
}

public class UICmd {
    
    public class RenderPhotoMode: Actor.Message {}
        
    public class RenderVideoMode: Actor.Message {}
        
    public class RenderVideoModeRecording: Actor.Message {}

    public class BecomeMonitorFailed: Actor.Message {}

    public class FailedToSaveImage: Actor.Message {
        let error: Error

        init(sender: Optional<ActorRef>, error: Error) {
            self.error = error
            super.init(sender: sender)
        }
    }

    public class AddMonitor: Actor.Message {
        
    }

    public class AddImageView: Actor.Message {
        let imageView: UIImageView

        public required init(imageView: UIImageView) {
            self.imageView = imageView
            super.init(sender: nil)
        }
    }

    public class StartScanning: Actor.Message {
    }

    public class UnbecomeCamera: Actor.Message {
    }

    public class ToggleConnect: Actor.Message {
    }

    public class UnbecomeMonitor: Actor.Message {
    }

    public class BecomeMonitor: Actor.Message {
        let mode: RecordingMode
        
        init(_ sender: Optional<ActorRef>, mode: RecordingMode) {
            self.mode = mode
            super.init(sender: sender)
        }
    }

    public class BecomeCamera: Actor.Message {
        let ctrl: CameraViewController

        public init(sender: Optional<ActorRef>, ctrl: CameraViewController) {
            self.ctrl = ctrl
            super.init(sender: sender)
        }
    }

    public class TakePicture: Actor.Message {
    }

    public class OnPicture: Actor.Message {

        public let pic: Optional<Data>
        public let error: Optional<Error>

        public init(sender: Optional<ActorRef>, pic: Data) {
            self.pic = pic
            self.error = nil
            super.init(sender: sender)
        }

        public init(sender: Optional<ActorRef>, error: Error) {
            self.pic = nil
            self.error = error
            super.init(sender: sender)
        }
    }

    @objc(_TtCC10ActorsDemo5UICmd11ToggleFlash)public class ToggleFlash: Actor.Message, NSCoding {
        public func encode(with aCoder: NSCoder) {
        }

        public init() {
            super.init(sender: nil)
        }

        public required init?(coder aDecoder: NSCoder) {
            super.init(sender: nil)
        }
    }

    @objc(_TtCC10ActorsDemo5UICmd15ToggleFlashResp)public class ToggleFlashResp: Actor.Message, NSCoding {

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
            self.flashMode = AVCaptureDevice.FlashMode(rawValue: aDecoder.decodeInteger(forKey: "flashMode"))!
            self.error = aDecoder.decodeObject(forKey: "error") as? Error
            super.init(sender: nil)
        }
    }

    @objc(_TtCC10ActorsDemo5UICmd12ToggleCamera)public class ToggleCamera: Actor.Message, NSCoding {

        public init() {
            super.init(sender: nil)
        }

        public func encode(with aCoder: NSCoder) {
        }

        public required init?(coder aDecoder: NSCoder) {
            super.init(sender: nil)
        }

    }

    @objc(_TtCC10ActorsDemo5UICmd16ToggleCameraResp)public class ToggleCameraResp: Actor.Message, NSCoding {

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
            self.flashMode = AVCaptureDevice.FlashMode(rawValue: aDecoder.decodeInteger(forKey: "flashMode"))
            self.camPosition = AVCaptureDevice.Position(rawValue: aDecoder.decodeInteger(forKey: "camPosition"))
            self.error = aDecoder.decodeObject(forKey: "error") as? Error

            super.init(sender: nil)
        }
    }
}
