//
//  CameraViewController.swift
//  RemoteShutter
//
//  Created by Dario on 10/7/15.
//  Copyright © 2020 Security Union LLC. All rights reserved.
//

import UIKit
import Theater
import AVFoundation

/**
ActorOutput is responsible for forwarding the images recorded in the AVCaptureSession of CameraViewController to the RemoteCam Session actor.
*/

public class ActorOutput: AVCaptureVideoDataOutput, AVCaptureVideoDataOutputSampleBufferDelegate {

    let videoQueue: DispatchQueue = DispatchQueue(label: "VideoQueue")

    lazy var remoteCamSession: ActorRef? = RemoteCamSystem.shared.selectActor(actorPath: "RemoteCam/user/RemoteCam Session")

    public init(delegate: AVCaptureVideoDataOutputSampleBufferDelegate) {
        super.init()
        self.setSampleBufferDelegate(delegate, queue: videoQueue)
    }
}

/**
Default fps, it would be neat if we would adjust this based on network conditions.
*/

let fps = 30

/**
 We downsample fps to streamFps because it is not possible for phones to keep up with the 30 fps.
 */
let streammingFPS = 5

/**
  Camera UI
*/

public class CameraViewController:
        UIViewController,
        AVCaptureVideoDataOutputSampleBufferDelegate,
        AVCapturePhotoCaptureDelegate {

    var captureSession: AVCaptureSession? = nil

    let cameraOutput = AVCapturePhotoOutput()

    let cameraSettings = AVCapturePhotoSettings()

    var captureVideoPreviewLayer: AVCaptureVideoPreviewLayer?

    var orientation: UIInterfaceOrientation = UIInterfaceOrientation.portrait

    @IBOutlet weak var back: UIButton!

    var session: ActorRef = RemoteCamSystem.shared.selectActor(actorPath: "RemoteCam/user/RemoteCam Session")!
    
    // Variable used to downsample the camera preview, please use with care.
    private var frameCounter = 0

    override public func viewDidLoad() {
        super.viewDidLoad()
        self.setupCamera()
        session ! UICmd.BecomeCamera(sender: nil, ctrl: self)
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.isNavigationBarHidden = true
        orientation = getOrientation()
    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if self.isBeingDismissed || self.isMovingFromParent {
            if let cs = captureSession {
                cs.stopRunning()
            }
            session ! UICmd.UnbecomeCamera(sender: nil)
        }
    }

    public override func willAnimateRotation(to toInterfaceOrientation: UIInterfaceOrientation, duration: TimeInterval) {
        orientation = getOrientation()
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

        guard let previewPixelType = self.cameraSettings.__availablePreviewPhotoPixelFormatTypes.first else {
            return
        }
        let previewFormat = [kCVPixelBufferPixelFormatTypeKey as String: previewPixelType,
                             kCVPixelBufferWidthKey as String: 160,
                             kCVPixelBufferHeightKey as String: 160]
        self.cameraSettings.previewPhotoFormat = previewFormat

        self.captureVideoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)

        captureVideoPreviewLayer!.videoGravity = AVLayerVideoGravity.resizeAspectFill
        captureVideoPreviewLayer!.frame = self.view.frame

        self.view.layer.insertSublayer(captureVideoPreviewLayer!, below: self.back.layer)

        if captureSession!.canAddOutput(cameraOutput) {
            captureSession!.addOutput(cameraOutput)
        }

        if let videoDevice = AVCaptureDevice.default(for: AVMediaType.video),
           let captureSession = captureSession {
            do {
                let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                captureSession.addInput(videoDeviceInput)

                let output = ActorOutput(delegate: self)
                captureSession.addOutput(output)

                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA)] as [String: Any]
                output.alwaysDiscardsLateVideoFrames = true

                self.setFrameRate(framerate: fps, videoDevice: videoDevice)

                session ! UICmd.ToggleCameraResp(
                        flashMode: (videoDevice.hasFlash) ? self.cameraSettings.flashMode : nil,
                        camPosition: videoDevice.position,
                        error: nil
                )

                self.captureSession?.startRunning()
                self.rotateCameraToOrientation(orientation: getOrientation())
            } catch let error as NSError {
                print("error \(error)")
            }
        }
    }

    func toggleCamera() -> Try<(AVCaptureDevice.FlashMode?, AVCaptureDevice.Position)> {
        do {
            let captureSession = self.captureSession
            let genericDevice = captureSession?.inputs.first as? AVCaptureDeviceInput
            let device = genericDevice?.device
            let newPosition = device?.position.toggle().toOptional()
            let newDevice = cameraForPosition(position: newPosition!)
            let newInput = try AVCaptureDeviceInput(device: newDevice!)
            captureSession?.removeInput(genericDevice!)
            captureSession?.addInput(newInput)
            setFrameRate(framerate: fps, videoDevice: newDevice!)
            do {
                DispatchQueue.main.async {
                    self.rotateCameraToOrientation(orientation: self.orientation)
                }
                let newFlashMode: AVCaptureDevice.FlashMode? = (newInput.device.hasFlash) ? self.cameraSettings.flashMode : nil
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
        if let hasFlash = device?.hasFlash, hasFlash {
            let newFlashMode = self.cameraSettings.flashMode.next()
            self.cameraSettings.flashMode = newFlashMode
            return Success(value: newFlashMode)
        } else {
            return Failure(error: NSError(domain: "Current camera does not support flash.", code: 0, userInfo: nil))
        }
    }

    func setFlashMode(mode: AVCaptureDevice.FlashMode, device: AVCaptureDevice) -> Try<AVCaptureDevice.FlashMode> {
        if device.hasFlash {
            do {
                try device.lockForConfiguration()
                self.cameraSettings.flashMode = mode
                device.unlockForConfiguration()
            } catch let error as NSError {
                return Failure(error: error)
            } catch {
                return Failure(error: NSError(domain: "Unknown error", code: 0, userInfo: nil))
            }
        }
        return Success(value: mode)
    }

    func cameraForPosition(position: AVCaptureDevice.Position) -> AVCaptureDevice? {

        let videoDevices = AVCaptureDevice.DiscoverySession.init(
                deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera],
                mediaType: .video, position: position).devices
        let filtered: [AVCaptureDevice] = videoDevices.filter {
            return $0.position == position
        }
        return filtered.first
    }

    private func rotateCameraToOrientation(orientation: UIInterfaceOrientation) {
        let o = OrientationUtils.transform(o: orientation)
        if let preview = self.captureVideoPreviewLayer {
            preview.connection?.videoOrientation = o
            if let videoConnection = self.cameraOutput.connection(with: AVMediaType.video) {
                videoConnection.videoOrientation = o
                DispatchQueue.main.async {
                    preview.frame = self.view.bounds
                }
            }
        }
    }

    func setFrameRate(framerate: Int, videoDevice: AVCaptureDevice) -> Try<Int> {
        do {
            try videoDevice.lockForConfiguration()
            videoDevice.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: Int32(framerate))
            videoDevice.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(framerate))
            videoDevice.unlockForConfiguration()
            return Success(value: framerate)
        } catch let error as NSError {
            return Failure(error: error)
        } catch {
            return Failure(error: NSError(domain: "unknown error", code: 0, userInfo: nil))
        }
    }

    func imageFromSampleBuffer(sampleBuffer: CMSampleBuffer) -> UIImage? {
        if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
            let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
            let width = CVPixelBufferGetWidth(imageBuffer)
            let height = CVPixelBufferGetHeight(imageBuffer)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(data: baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
                return nil
            }

            let quartzImage = context.makeImage()
            CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))

            if let quartzImage = quartzImage {
                let image = UIImage(cgImage: quartzImage)
                return image
            }
        }
        return nil
    }

    public func captureOutput(_ captureOutput: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        frameCounter = frameCounter + 1
        if frameCounter < (fps / streammingFPS) {
            return
        } else {
            frameCounter = 0
        }
        if let cgBackedImage = imageFromSampleBuffer(sampleBuffer: sampleBuffer),
           let imageData = cgBackedImage.jpegData(compressionQuality: 0.1),
           let genericDevice = captureSession?.inputs.first as? AVCaptureDeviceInput {

            let device = genericDevice.device
            self.session ! RemoteCmd.SendFrame(data: imageData,
                    sender: nil,
                    fps: fps,
                    camPosition: device.position,
                    camOrientation: self.orientation)
        }
    }

    func cloneCameraSettings(_ settings: AVCapturePhotoSettings) -> AVCapturePhotoSettings {
        let newSettings = AVCapturePhotoSettings()
        newSettings.flashMode = settings.flashMode
        return newSettings
    }

    func takePicture() -> Void {
        let cameraSettings = cloneCameraSettings(self.cameraSettings)
        self.cameraOutput.capturePhoto(with: cameraSettings, delegate: self)
    }

    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if error != nil {
            self.session ! UICmd.OnPicture(sender: nil, error: error!)
            return
        }
        guard let photoData = photo.fileDataRepresentation() else {
            return
        }
        self.session ! UICmd.OnPicture(sender: nil, pic: photoData)
    }
}
