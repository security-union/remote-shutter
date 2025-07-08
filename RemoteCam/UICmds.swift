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

// MARK: - Shared Types (matching RemoteCmds.swift)
public struct ZoomRange: Codable {
    public let minZoom: CGFloat
    public let maxZoom: CGFloat
    
    public init(minZoom: CGFloat, maxZoom: CGFloat) {
        self.minZoom = minZoom
        self.maxZoom = maxZoom
    }
}

public class UICmd {

    public class RenderPhotoMode: Actor.Message {}

    public class RenderVideoMode: Actor.Message {}

    public class RenderVideoModeRecording: Actor.Message {}

    public class BecomeMonitorFailed: Actor.Message {}

    public class FailedToSaveImage: Actor.Message {
        let error: Error

        init(sender: ActorRef?, error: Error) {
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

    public class UnbecomeMonitor: Actor.Message {
    }

    public class BecomeMonitor: Actor.Message {
        let mode: RecordingMode

        init(_ sender: ActorRef?, mode: RecordingMode) {
            self.mode = mode
            super.init(sender: sender)
        }
    }

    public class BecomeCamera: Actor.Message {
        let ctrl: CameraViewController

        public init(sender: ActorRef?, ctrl: CameraViewController) {
            self.ctrl = ctrl
            super.init(sender: sender)
        }
    }

    public class TakePicture: Actor.Message {
        let sendMediaToRemote: Bool
        
        public init(sender: ActorRef?, sendMediaToRemote: Bool) {
            self.sendMediaToRemote = sendMediaToRemote
            super.init(sender: sender)
        }
    }

    public class OnPicture: Actor.Message {

        public let pic: Data?
        public let error: Error?

        public init(sender: ActorRef?, pic: Data) {
            self.pic = pic
            self.error = nil
            super.init(sender: sender)
        }

        public init(sender: ActorRef?, error: Error) {
            self.pic = nil
            self.error = error
            super.init(sender: sender)
        }
    }

    // MARK: - Zoom Commands
    @objc(_TtCC10ActorsDemo5UICmd8SetZoom)public class SetZoom: Actor.Message, NSCoding {
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

    @objc(_TtCC10ActorsDemo5UICmd12SetZoomResp)public class SetZoomResp: Actor.Message, NSCoding {
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

    // MARK: - Lens Switching Commands
    @objc(_TtCC10ActorsDemo5UICmd10SwitchLens)public class SwitchLens: Actor.Message, NSCoding {
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

    @objc(_TtCC10ActorsDemo5UICmd14SwitchLensResp)public class SwitchLensResp: Actor.Message, NSCoding {
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
            let lensRawValue = aDecoder.decodeInteger(forKey: "lensType")
            self.lensType = lensRawValue > 0 ? CameraLensType(rawValue: lensRawValue) : nil
            
            if let lensRawValues = aDecoder.decodeObject(forKey: "availableLenses") as? [Int] {
                self.availableLenses = lensRawValues.compactMap { CameraLensType(rawValue: $0) }
            } else {
                self.availableLenses = nil
            }
            
            let zoomValue = aDecoder.decodeFloat(forKey: "currentZoom")
            self.currentZoom = zoomValue > 0 ? CGFloat(zoomValue) : nil
            
            if let rangeData = aDecoder.decodeObject(forKey: "zoomRange") as? Data {
                self.zoomRange = try? JSONDecoder().decode(ZoomRange.self, from: rangeData)
            } else {
                self.zoomRange = nil
            }
            
            self.error = aDecoder.decodeObject(forKey: "error") as? Error
            super.init(sender: nil)
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
