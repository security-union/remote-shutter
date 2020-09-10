//
//  CameraViewController.swift
//  Actors
//
//  Created by Dario on 10/7/15.
//  Copyright © 2015 dario. All rights reserved.
//

import UIKit
import Theater
import AVFoundation
    
/**
ActorOutput is responsible for forwarding the images recorded in the AVCaptureSession of CameraViewController to the RemoteCam Session actor.
*/
    
public class ActorOutput : AVCaptureVideoDataOutput, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    let videoQueue : DispatchQueue = DispatchQueue(label: "VideoQueue")
    
    lazy var remoteCamSession : ActorRef? = RemoteCamSystem.shared.selectActor(actorPath: "RemoteCam/user/RemoteCam Session")
    
    public init(delegate : AVCaptureVideoDataOutputSampleBufferDelegate) {
        super.init()
        self.setSampleBufferDelegate(delegate, queue: videoQueue)
    }
}
    
/**
  Camera UI
*/

public class CameraViewController : UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    var captureSession : AVCaptureSession? = nil
    
    var captureVideoPreviewLayer : AVCaptureVideoPreviewLayer?
    
    @IBOutlet weak var back : UIButton!
    
    let stillImageOutput = AVCaptureStillImageOutput()
    
    var session : ActorRef = RemoteCamSystem.shared.selectActor(actorPath: "RemoteCam/user/RemoteCam Session")!
    
    /**
    Default fps, it would be neat if we would adjust this based on network conditions.
    */
    
    let fps = 3
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        self.setupCamera()
        session ! UICmd.BecomeCamera(sender: nil, ctrl: self)
    }
    
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.isNavigationBarHidden = true
    }
    
    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if self.isBeingDismissed || self.isMovingFromParent {
            if let cs = captureSession {
                cs.stopRunning()
            }
            session ! UICmd.UnbecomeCamera(sender : nil)
        }
    }
    
    public override func willAnimateRotation(to toInterfaceOrientation: UIInterfaceOrientation, duration: TimeInterval) {
        self.rotateCameraToOrientation(orientation: toInterfaceOrientation)
    }
    
    @IBAction func goBack(sender: UIButton) {
        self.navigationController?.popViewController(animated: true)
    }
    
    func setupCamera() -> Void {
        if let cs = self.captureSession {
            cs.stopRunning()
        }
        
        captureSession = AVCaptureSession()
        
        self.captureVideoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        
        captureVideoPreviewLayer!.videoGravity = AVLayerVideoGravity(rawValue: convertFromAVLayerVideoGravity(AVLayerVideoGravity.resizeAspectFill))
        captureVideoPreviewLayer!.frame = self.view.frame
        
        self.view.layer.insertSublayer(captureVideoPreviewLayer!, below: self.back.layer)
        
        stillImageOutput.outputSettings = [AVVideoCodecKey:AVVideoCodecJPEG]
        
        if captureSession!.canAddOutput(stillImageOutput) {
            captureSession!.addOutput(stillImageOutput)
        }
        
        if let videoDevice = AVCaptureDevice.default(for: AVMediaType(rawValue: convertFromAVMediaType(AVMediaType.video))),
            let captureSession = captureSession {
                do {
                    let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                    captureSession.addInput(videoDeviceInput)
                    
                    let output = ActorOutput(delegate: self)
                    captureSession.addOutput(output)
                    
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey : Int(kCVPixelFormatType_32BGRA)] as [String : Any]
                    output.alwaysDiscardsLateVideoFrames = true
                    
                    self.setFrameRate(framerate: self.fps,videoDevice:videoDevice)
                    
                    session ! UICmd.ToggleCameraResp(flashMode:(videoDevice.hasFlash) ? videoDevice.flashMode : nil, camPosition: videoDevice.position, error: nil)
                    
                    self.captureSession?.startRunning()
                    self.rotateCameraToOrientation(orientation: UIApplication.shared.statusBarOrientation)
                } catch let error as NSError {
                    print("error \(error)")
                }
        }
    }
    
    func toggleCamera() -> Try<(AVCaptureDevice.FlashMode?,AVCaptureDevice.Position)> {
        do {
            let captureSession = self.captureSession
            let genericDevice = captureSession?.inputs.first as? AVCaptureDeviceInput
            let device = genericDevice?.device
            let newPosition = device?.position.toggle().toOptional()
            let newDevice = cameraForPosition(position: newPosition!)
            let newInput = try AVCaptureDeviceInput(device: newDevice!)
            captureSession?.removeInput(genericDevice!)
            captureSession?.addInput(newInput)
            setFrameRate(framerate: self.fps,videoDevice:newDevice!); do {
                rotateCameraToOrientation(orientation: UIApplication.shared.statusBarOrientation)
                    let newFlashMode : AVCaptureDevice.FlashMode? = (newInput.device.hasFlash) ? newInput.device.flashMode : nil
                    return Success(value: (newFlashMode, newInput.device.position))
                }
        } catch let error as NSError {
            return Failure(error: error)
        }
    }
    
    func toggleFlash() -> Try<AVCaptureDevice.FlashMode> {
        let captureSession = self.captureSession
        let genericDevice = captureSession?.inputs.first as? AVCaptureDeviceInput
        let device = genericDevice?.device
        if (device?.hasFlash)! {
            return self.setFlashMode(mode: (device?.flashMode.next())!, device: device!)
        } else {
            return Failure(error: NSError(domain: "Current camera does not support flash.", code: 0, userInfo: nil))
        }
        return Failure(error: NSError(domain: "Unable to find camera", code: 0, userInfo: nil))
    }
    
    func setFlashMode(mode : AVCaptureDevice.FlashMode, device : AVCaptureDevice) -> Try<AVCaptureDevice.FlashMode> {
        if device.hasFlash {
            do {
                try device.lockForConfiguration()
                device.flashMode = mode
                device.unlockForConfiguration()
            } catch let error as NSError {
                return Failure(error: error)
            } catch {
               return Failure(error: NSError(domain: "Unknown error", code: 0, userInfo: nil))
            }
        }
        return Success(value: mode)
    }
    
    func cameraForPosition(position : AVCaptureDevice.Position) -> AVCaptureDevice? {
        if let videoDevices = AVCaptureDevice.devices(for: AVMediaType(rawValue: convertFromAVMediaType(AVMediaType.video))) as? [AVCaptureDevice] {
            let filtered : [AVCaptureDevice] = videoDevices.filter { return $0.position == position}
            return filtered.first
        } else {
            return nil
        }
    }

    private func rotateCameraToOrientation(orientation : UIInterfaceOrientation) {
        let o = OrientationUtils.transform(o: orientation)
        if let preview = self.captureVideoPreviewLayer {
            preview.connection?.videoOrientation = o
            if let videoConnection = stillImageOutput.connection(with: AVMediaType(rawValue: convertFromAVMediaType(AVMediaType.video))) {
                videoConnection.videoOrientation = o
                preview.frame = self.view.bounds
            }
        }        
        
//        self.stillImageOutput.connections.forEach {
//            (($0 ) as AnyObject).videoOrientation = o //stupid swift
//        }
    }
    
    func takePicture() -> Void {
        if let videoConnection = stillImageOutput.connection(with: AVMediaType(rawValue: convertFromAVMediaType(AVMediaType.video))) {
            stillImageOutput.captureStillImageAsynchronously(from: videoConnection) {[unowned self]
                (imageSampleBuffer, error) in
                if imageSampleBuffer == nil {
                    self.session ! UICmd.OnPicture(sender: nil, error: NSError(domain: "Unable to take picture", code: 0, userInfo: nil))
                } else {
                    if let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageSampleBuffer!) {
                        self.session ! UICmd.OnPicture(sender: nil, pic:imageData)
                    }
                }
            }
        }
    }
    
    func setFrameRate(framerate:Int, videoDevice: AVCaptureDevice) -> Try<Int> {
        do {
            try videoDevice.lockForConfiguration()
            videoDevice.activeVideoMaxFrameDuration = CMTimeMake(value: 1,timescale: Int32(framerate))
            videoDevice.activeVideoMinFrameDuration = CMTimeMake(value: 1,timescale: Int32(framerate))
            videoDevice.unlockForConfiguration()
            return Success(value:framerate)
        } catch let error as NSError {
            return Failure(error: error)
        } catch {
            return Failure(error: NSError(domain: "unknown error", code: 0, userInfo: nil))
        }
    }
    
    public func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if let cgBackedImage = UIImage(from: sampleBuffer, orientation: OrientationUtils.transformOrientationToImage(o: UIApplication.shared.statusBarOrientation)) {
            
            let imageData = cgBackedImage.jpegData(compressionQuality: 0.1)
        
            let captureSession = self.captureSession
            let genericDevice = captureSession?.inputs.first as? AVCaptureDeviceInput
            let device = genericDevice?.device
            _ = RemoteCmd.SendFrame(data: imageData!, sender: nil, fps:3, camPosition: (device?.position)!)
        }
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromAVLayerVideoGravity(_ input: AVLayerVideoGravity) -> String {
	return input.rawValue
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromAVMediaType(_ input: AVMediaType) -> String {
	return input.rawValue
}
