//
//  MultipeerMessages.swift
//  Actors
//
//  Created by Dario on 10/7/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation
import Theater
import MultipeerConnectivity
import AVFoundation

public class Disconnect : Actor.Message {}

public class ConnectToDevice : Actor.Message {
    public let peer : MCPeerID
    
    public init(peer : MCPeerID, sender : Optional<ActorRef>) {
        self.peer = peer
        super.init(sender: sender)
    }
}

public class UICmd {
    
    public class BecomeMonitorFailed: Actor.Message {}
    
    public class FailedToSaveImage : Actor.Message {
        let error : Error
        
        init(sender: Optional<ActorRef>, error : Error) {
            self.error = error
            super.init(sender: sender)
        }
    }
    
    public class AddMonitor : Actor.Message {}
    
    public class AddImageView : Actor.Message {
        let imageView : UIImageView
        
        public required init(imageView : UIImageView) {
            self.imageView = imageView
            super.init(sender: nil)
        }
    }
    
    public class StartScanning : Actor.Message {}
    
    public class UnbecomeCamera : Actor.Message {}
    
    public class ToggleConnect : Actor.Message {}
    
    public class UnbecomeMonitor : Actor.Message {}
    
    public class BecomeMonitor : Actor.Message {}

    public class BecomeCamera : Actor.Message {
        let ctrl : CameraViewController
        
        public init(sender: Optional<ActorRef>, ctrl : CameraViewController) {
            self.ctrl = ctrl
            super.init(sender: sender)
        }
    }
    
    public class TakePicture : Actor.Message {}
    
    public class OnPicture : Actor.Message {
        
        public let pic : Optional<Data>
        public let error : Optional<Error>
        
        public init(sender: Optional<ActorRef>, pic : Data) {
            self.pic = pic
            self.error = nil
            super.init(sender: sender)
        }
        
        public init(sender: Optional<ActorRef>, error : Error) {
            self.pic = nil
            self.error = error
            super.init(sender: sender)
        }
    }
    
    @objc(_TtCC10ActorsDemo5UICmd11ToggleFlash)public class ToggleFlash : Actor.Message, NSCoding {
        public func encode(with aCoder: NSCoder) {
        }
        
        public init() {
            super.init(sender : nil)
        }
        
        public required init?(coder aDecoder: NSCoder) {
            super.init(sender: nil)
        }
    }
    
    @objc(_TtCC10ActorsDemo5UICmd15ToggleFlashResp)public class ToggleFlashResp : Actor.Message, NSCoding {
        
        public let error : Error?
        public let flashMode : AVCaptureDevice.FlashMode?
        
        public init(flashMode : AVCaptureDevice.FlashMode?, error : Error?) {
            self.flashMode = flashMode
            self.error = error
            super.init(sender : nil)
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
    
    @objc(_TtCC10ActorsDemo5UICmd12ToggleCamera)public class ToggleCamera : Actor.Message, NSCoding {
        
        public init() {
            super.init(sender : nil)
        }
        
        public func encode(with aCoder: NSCoder) {}
        
        public required init?(coder aDecoder: NSCoder) {
            super.init(sender: nil)
        }
        
    }
    
    @objc(_TtCC10ActorsDemo5UICmd16ToggleCameraResp)public class ToggleCameraResp : Actor.Message, NSCoding {
        
        public let error : Error?
        public let flashMode : AVCaptureDevice.FlashMode?
        public let camPosition : AVCaptureDevice.Position?
        
        public init(flashMode : AVCaptureDevice.FlashMode?,
            camPosition : AVCaptureDevice.Position?,
            error : Error?) {
                self.flashMode = flashMode
                self.camPosition = camPosition
                self.error = error
                super.init(sender : nil)
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

public class DisconnectPeer : Actor.Message {
    public let peer : MCPeerID
    
    public init(peer : MCPeerID, sender : Optional<ActorRef>) {
        self.peer = peer
        super.init(sender: sender)
    }
}

public class OnConnectToDevice : Actor.Message {
    public let peer : MCPeerID
    
    public init(peer : MCPeerID, sender : Optional<ActorRef>) {
        self.peer = peer
        super.init(sender: sender)
    }
}

public class RemoteCmd : Actor.Message {
    
    @objc(_TtCC10ActorsDemo9RemoteCmd7TakePic)public class TakePic : RemoteCmd, NSCoding {
        public func encode(with aCoder: NSCoder) {}
        
        public override init(sender: Optional<ActorRef>) {
            super.init(sender: sender)
        }
        
        public required init?(coder aDecoder: NSCoder) {
            super.init(sender: nil)
        }
        
    }
    
    @objc(_TtCC10ActorsDemo9RemoteCmd10TakePicAck)public class TakePicAck : Actor.Message, NSCoding {
        public override init(sender: Optional<ActorRef>) {
            super.init(sender: sender)
        }
        
        public func encode(with aCoder: NSCoder)  {}
        
        public required init?(coder aDecoder: NSCoder) {
            super.init(sender: nil)
        }
    }
    
    @objc(_TtCC10ActorsDemo9RemoteCmd11TakePicResp)public class TakePicResp : Actor.Message , NSCoding {
        
        let pic : Optional<Data>
        let error : Optional<Error>
        
        
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
            }else {
                self.error = nil
            }
            
            super.init(sender: nil)
        }
        
        public init(sender: Optional<ActorRef>, pic : Data) {
            self.pic = pic
            self.error = nil
            super.init(sender: sender)
        }
        
        public init(sender: Optional<ActorRef>, pic : Optional<Data>, error : Optional<Error>) {
            self.pic = pic
            self.error = error
            super.init(sender: sender)
        }
        
        public init(sender: Optional<ActorRef>, error : Error) {
            self.pic = nil
            self.error = error
            super.init(sender: sender)
        }
    }
    
    @objc(_TtCC10ActorsDemo9RemoteCmd9SendFrame)public class SendFrame : Actor.Message, NSCoding {
        public let data : Data
        public let fps : NSInteger
        public let camPosition : AVCaptureDevice.Position
        
        init(data : Data, sender : Optional<ActorRef>, fps : NSInteger, camPosition : AVCaptureDevice.Position) {
            self.data = data
            self.fps = fps
            self.camPosition = camPosition
            super.init(sender: sender)
        }
        
        public func encode(with aCoder: NSCoder) {
            aCoder.encode(self.data)
            aCoder.encode(self.fps, forKey: "fps")
            aCoder.encode(self.camPosition.rawValue, forKey: "camPosition")
        }
        
        public required init?(coder aDecoder: NSCoder) {
            self.data = aDecoder.decodeData()!
            self.fps = aDecoder.decodeInteger(forKey: "fps")
            self.camPosition = AVCaptureDevice.Position(rawValue: aDecoder.decodeInteger(forKey: "camPosition"))!
            super.init(sender: nil)
        }
    }
    
    public class OnFrame : Actor.Message {
        public let data : Data
        public let peerId : MCPeerID
        public let fps : NSInteger
        public let camPosition : AVCaptureDevice.Position
        
        init(data : Data, sender : Optional<ActorRef>, peerId : MCPeerID, fps:NSInteger, camPosition : AVCaptureDevice.Position) {
            self.camPosition = camPosition
            self.data = data
            self.peerId = peerId
            self.fps = fps
            super.init(sender: sender)
        }
    }
    
    @objc(_TtCC10ActorsDemo9RemoteCmd16PeerBecameCamera)public class PeerBecameCamera : Actor.Message , NSCoding {
        
        public init() {
            super.init(sender : nil)
        }
        
        public func encode(with aCoder: NSCoder) {}
        
        public required init?(coder aDecoder: NSCoder) {
            super.init(sender: nil)
        }
    }
    
    @objc(_TtCC10ActorsDemo9RemoteCmd17PeerBecameMonitor)public class PeerBecameMonitor : Actor.Message , NSCoding {
        
        public init() {
            super.init(sender : nil)
        }
        
        public func encode(with aCoder: NSCoder) {}
        
        public required init?(coder aDecoder: NSCoder) {
            super.init(sender: nil)
        }
    }
    
    @objc(_TtCC10ActorsDemo9RemoteCmd11ToggleFlash)public class ToggleFlash : Actor.Message, NSCoding {
        public init() {
            super.init(sender : nil)
        }
        
        public func encode(with aCoder: NSCoder) {}
        
        public required init?(coder aDecoder: NSCoder) {
            super.init(sender: nil)
        }
    }
    
    @objc(_TtCC10ActorsDemo9RemoteCmd15ToggleFlashResp)public class ToggleFlashResp : Actor.Message, NSCoding {
        
        public let error : Error?
        public let flashMode : AVCaptureDevice.FlashMode?
        
        public init(flashMode : AVCaptureDevice.FlashMode?, error : Error?) {
            self.flashMode = flashMode
            self.error = error
            super.init(sender : nil)
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
    
    @objc(_TtCC10ActorsDemo9RemoteCmd12ToggleCamera)public class ToggleCamera : Actor.Message, NSCoding {
        public init() {
            super.init(sender : nil)
        }
        
        public func encode(with aCoder: NSCoder) {}
        
        public required init?(coder aDecoder: NSCoder) {
            super.init(sender: nil)
        }
        
    }
    
    @objc(_TtCC10ActorsDemo9RemoteCmd16ToggleCameraResp)public class ToggleCameraResp : Actor.Message, NSCoding {
        
        public let error : Error?
        public let flashMode : AVCaptureDevice.FlashMode?
        public let camPosition : AVCaptureDevice.Position?
        
        public init(flashMode : AVCaptureDevice.FlashMode?,
            camPosition : AVCaptureDevice.Position?,
            error : Error?) {
            self.flashMode = flashMode
            self.camPosition = camPosition
            self.error = error
            super.init(sender : nil)
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



