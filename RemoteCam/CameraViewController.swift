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
import Photos

/**
Default fps, it would be neat if we would adjust this based on network conditions.
*/

let fps = 30

/**
 We downsample fps to streamFps because it is not possible for phones to keep up with the 30 fps.
 */
let streamingFPS = 5

/**
  Camera UI
*/
public class CameraViewController: UIViewController,
        AVCapturePhotoCaptureDelegate {

    var captureSession: AVCaptureSession = AVCaptureSession()
    private let audioDataOutput = AVCaptureAudioDataOutput()
    private let audioDataOutputQueue = DispatchQueue(
        label: "recording audio data output queue", attributes: [], target: nil)
    private let cameraConfigQueue = DispatchQueue(
        label: "camera config queue", attributes: [], target: nil)

    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let videoDataOutputQueue = DispatchQueue(
        label: "recording video data output queue", attributes: [], target: nil)
    private let photoOutput = AVCapturePhotoOutput()
    let cameraSettings = AVCapturePhotoSettings()
    var videoConnection: AVCaptureConnection?
    var audioConnection: AVCaptureConnection?
    var videoDeviceInput: AVCaptureDeviceInput!

    var isRecording: Bool = false
    var recordingWillBeStarted: Bool = false
    var recordingWillBeStopped: Bool = false
    var readyToRecordVideo: Bool = false
    var readyToRecordAudio: Bool = false
    var assetWriter: AVAssetWriter?

    var captureVideoPreviewLayer: AVCaptureVideoPreviewLayer?
    var orientation: UIInterfaceOrientation = UIInterfaceOrientation.portrait
    var session: ActorRef = RemoteCamSystem.shared.selectActor(actorPath: "RemoteCam/user/RemoteCam Session")!
    private let writingQueue = DispatchQueue(label: "asset recorder writing queue", attributes: [], target: nil)

    private var videoInput: AVAssetWriterInput!
    private var audioInput: AVAssetWriterInput!

    // Variable used to downsample the camera preview, please use with care.
    private var frameCounter = 0

    @IBOutlet weak var back: UIButton!
    @IBOutlet var recordingView: UIImageView!

    override public func viewDidLoad() {
        super.viewDidLoad()
        recordingView.image = UIImage.gifImageWithName("recording")
        self.setupCamera()
        session ! UICmd.BecomeCamera(sender: nil, ctrl: self)
        configureIdleMode()
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.isNavigationBarHidden = true
        orientation = getOrientation()
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if self.isBeingDismissed || self.isMovingFromParent {
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
            session ! UICmd.UnbecomeCamera(sender: nil)
        }
    }

    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if captureVideoPreviewLayer != nil {
            captureVideoPreviewLayer!.frame = self.view.frame
        }
    }

    func configureIdleMode() {
        recordingView.isHidden = true
        back.isHidden = false
    }

    func configureVideoModeRecording() {
        recordingView.isHidden = false
        back.isHidden = true
    }

    public override var shouldAutorotate: Bool {
        // Disable autorotation of the interface when recording is in progress.
        return !isRecording
    }

    public override func willAnimateRotation(to toInterfaceOrientation: UIInterfaceOrientation, duration: TimeInterval) {
        orientation = getOrientation()
        self.rotateCameraToOrientation(orientation: toInterfaceOrientation)
    }

    @IBAction func goBack(sender: UIButton) {
        self.navigationController?.popViewController(animated: true)
    }

    func setupCamera() {
        self.videoDataOutput.setSampleBufferDelegate(self, queue: self.videoDataOutputQueue)
        self.videoDataOutput.videoSettings =
            [kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA)] as [String: Any]
        self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
        if self.captureSession.isRunning {
            self.captureSession.stopRunning()
        }
        self.captureSession.beginConfiguration()
        self.captureSession.sessionPreset = .high

        guard let videoDevice = AVCaptureDevice.default(for: AVMediaType.video) else {
            return
        }

        self.captureVideoPreviewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)

        self.captureVideoPreviewLayer!.videoGravity = AVLayerVideoGravity.resizeAspect
        DispatchQueue.main.async {
            self.captureVideoPreviewLayer!.frame = self.view.frame
            self.view.layer.insertSublayer(self.captureVideoPreviewLayer!, below: self.back.layer)
        }

        do {
            self.videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            self.captureSession.addInput(self.videoDeviceInput)
            self.captureSession.addOutput(self.videoDataOutput)

            self.setFrameRate(framerate: fps, videoDevice: videoDevice)

            self.session ! UICmd.ToggleCameraResp(
                    flashMode: (videoDevice.hasFlash) ? self.cameraSettings.flashMode : nil,
                    camPosition: videoDevice.position,
                    error: nil
            )

            let audioDevice = AVCaptureDevice.default(for: .audio)
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice!)

            if self.captureSession.canAddInput(audioDeviceInput) {
                self.captureSession.addInput(audioDeviceInput)
            } else {
                print("Could not add audio device input to the session")
            }

            if self.captureSession.canAddOutput(self.audioDataOutput) {
                self.captureSession.addOutput(self.audioDataOutput)
                self.audioDataOutput.setSampleBufferDelegate(self, queue: self.audioDataOutputQueue)
            }
            self.configSessionOutput()
            DispatchQueue.main.async {
                self.rotateCameraToOrientation(orientation: self.orientation)
            }
            self.captureSession.commitConfiguration()
            self.captureSession.startRunning()
        } catch let error as NSError {
            print("error \(error)")
        }
    }

    func toggleCamera() -> Try<(AVCaptureDevice.FlashMode?, AVCaptureDevice.Position)> {
        do {
            let captureSession = self.captureSession
            captureSession.beginConfiguration()
            let device = self.videoDeviceInput?.device
            let newPosition = device?.position.toggle().toOptional()
            let newDevice = cameraForPosition(position: newPosition!)
            let newInput = try AVCaptureDeviceInput(device: newDevice!)
            captureSession.removeInput(self.videoDeviceInput)
            captureSession.addInput(newInput)
            self.videoDeviceInput = newInput
            configSessionOutput()
            setFrameRate(framerate: fps, videoDevice: newDevice!)
            do {
                DispatchQueue.main.async {
                    self.rotateCameraToOrientation(orientation: self.orientation)
                }
                let newFlashMode: AVCaptureDevice.FlashMode? = (newInput.device.hasFlash) ? self.cameraSettings.flashMode : nil
                captureSession.commitConfiguration()
                return Success(value: (newFlashMode, newInput.device.position))
            }
        } catch let error as NSError {
            return Failure(error: error)
        }
    }

    private func configSessionOutput() {
        self.captureSession.beginConfiguration()
        captureSession.removeOutput(videoDataOutput)
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        } else {
            print("Could not add still image output to the session")
            return
        }

        captureSession.removeOutput(photoOutput)
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        } else {
            print("Could not add movie file output to the session")
            return
        }
        videoConnection = videoDataOutput.connection(with: .video)
        audioConnection = audioDataOutput.connection(with: .audio)
        self.captureSession.commitConfiguration()
    }

    func toggleFlash() -> Try<AVCaptureDevice.FlashMode> {
        let genericDevice = self.videoDeviceInput
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
            if let videoConnection = self.videoConnection {
                videoConnection.videoOrientation = o
            }
            if let photoConnection = self.photoOutput.connection(with: AVMediaType.video) {
                photoConnection.videoOrientation = o
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

    func cloneCameraSettings(_ settings: AVCapturePhotoSettings) -> AVCapturePhotoSettings {
        let newSettings = AVCapturePhotoSettings()
        newSettings.flashMode = settings.flashMode
        return newSettings
    }

    func takePicture() {
        OperationQueue.main.addOperation {
            let cameraSettings = self.cloneCameraSettings(self.cameraSettings)
            self.photoOutput.capturePhoto(with: cameraSettings, delegate: self)
        }
    }

    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if error != nil {
            session ! UICmd.OnPicture(sender: nil, error: error!)
            return
        }
        guard let photoData = photo.fileDataRepresentation() else {
            return
        }
        session ! UICmd.OnPicture(sender: nil, pic: photoData)
    }
}

extension CameraViewController {

    func startRecordingVideo() {
        writingQueue.async {[weak self] in
            guard let self = self else {return}
            if self.recordingWillBeStarted || self.isRecording {
                return
            }

            self.recordingWillBeStarted = true

            // Remove the file if one with the same name already exists
            let outputFilePath = movieUrl()
            cleanupFileAt(outputFilePath)
            // Create an asset writer
            do {
                self.assetWriter = try AVAssetWriter(outputURL: outputFilePath, fileType: .mov)
            } catch {
                showError(NSLocalizedString("Unable to start recording", comment: ""))
            }
            OperationQueue.main.addOperation {[weak self] in
                if let recordingWillBeStarted = self?.recordingWillBeStarted,
                   let isRecording = self?.isRecording {
                    if !recordingWillBeStarted && !isRecording {
                        self?.configureIdleMode()
                    } else {
                        self?.configureVideoModeRecording()
                    }
                }
            }
        }
    }

    func stopRecordingVideo() {
        writingQueue.async {[weak self] in
            guard let self = self else { return }
            if self.recordingWillBeStopped || !self.isRecording {
                return
            }
            self.isRecording = false
            self.recordingWillBeStopped = true
            self.assetWriter?.finishWriting {[weak self] in
                self?.assetWriter=nil
                self?.readyToRecordVideo = false
                self?.readyToRecordAudio = false
                self?.recordingWillBeStopped = false
                self?.saveMovieToPhotosApp()
            }
            OperationQueue.main.addOperation {[weak self] in
                if let recordingWillBeStopped = self?.recordingWillBeStopped,
                   let isRecording = self?.isRecording {
                    if recordingWillBeStopped && !isRecording {
                        self?.configureIdleMode()
                    } else {
                        self?.configureVideoModeRecording()
                    }
                }
            }
        }
    }
}

extension CameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(_ captureOutput: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        if connection == videoConnection {
            sendFrameToMonitor(captureOutput, didOutput: sampleBuffer, from: connection)
        }
        if (recordingWillBeStarted || isRecording) && !recordingWillBeStopped {
            self.processFrame(captureOutput, didOutput: sampleBuffer, from: connection)
        }
    }

    public func sendFrameToMonitor(_ captureOutput: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        frameCounter = frameCounter + 1
        if frameCounter < (fps / streamingFPS) {
            return
        }
        frameCounter = 0
        if let cgBackedImage = imageFromSampleBuffer(sampleBuffer: sampleBuffer),
           let imageData = cgBackedImage.jpegData(compressionQuality: 0.1),
           let device = self.videoDeviceInput?.device {
            session ! RemoteCmd.SendFrame(data: imageData,
                    sender: nil,
                    fps: fps,
                    camPosition: device.position,
                    camOrientation: self.orientation)
        }
    }

    func saveMovieToPhotosApp() {
        let outputFileURL = movieUrl()
        if let data = try? Data(contentsOf: outputFileURL) {
            // Send video to the monitor
            session ! RemoteCmd.StopRecordingVideoResp(sender: nil, pic: data, error: nil)
            // Check the authorization status.
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    // Save the movie file to the photo library and cleanup.
                    PHPhotoLibrary.shared().performChanges({
                        let options = PHAssetResourceCreationOptions()
                        options.shouldMoveFile = true
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.addResource(with: .video, fileURL: outputFileURL, options: options)
                    }, completionHandler: { success, error in
                        if !success {
                            print("AVCam couldn't save the movie to your photo library: \(String(describing: error))")
                        }
                        cleanupFileAt(outputFileURL)
                    }
                    )
                } else {
                    cleanupFileAt(outputFileURL)
                }
            }
        } else {
            cleanupFileAt(movieUrl())
        }
    }

    func setupAssetWriterVideoInput(_ formatDescription: CMVideoFormatDescription,
                                    assetWriter: AVAssetWriter) -> Bool {
        var videoSettings = self.videoDataOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov)
        if #available(iOS 13, *) {
            videoSettings = self.videoDataOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov)
        } else {
            // Please do not remove this code unless we drop iOS 12.
            let dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
            var bitsPerPixel: Float
            let numPixels = dimensions.width * dimensions.height
            var bitsPerSecond: Int

            // Assume that lower-than-SD resolutions are intended for streaming, and use a lower bitrate
            if numPixels < 640 * 480 {
                bitsPerPixel = 4.05 // This bitrate approximately matches the quality produced by AVCaptureSessionPresetMedium or Low.
            } else {
                bitsPerPixel = 10.1 // This bitrate approximately matches the quality produced by AVCaptureSessionPresetHigh.
            }

            bitsPerSecond = Int(Float(numPixels) * bitsPerPixel)

            let compressionProperties: NSDictionary = [AVVideoAverageBitRateKey: bitsPerSecond,
                                                       AVVideoExpectedSourceFrameRateKey: 24,
                                                       AVVideoMaxKeyFrameIntervalKey: 24]

            videoSettings = [AVVideoCodecKey: AVVideoCodecType.h264,
                             AVVideoWidthKey: dimensions.width,
                             AVVideoHeightKey: dimensions.height,
                             AVVideoCompressionPropertiesKey: compressionProperties]
        }

        if assetWriter.canApply(outputSettings: videoSettings, forMediaType: .video) {
            videoInput = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true

            if assetWriter.canAdd(videoInput) {
                assetWriter.add(videoInput)
            } else {
                // TODO: manage
                return false
            }
        } else {
            // TODO: manage
            return false
        }
        return true
    }

    func setupAssetWriterAudioInput(_ formatDescription: CMFormatDescription,
                                    assetWriter: AVAssetWriter) -> Bool {
        let audioSettings = [AVFormatIDKey: kAudioFormatMPEG4AAC]
        if assetWriter.canApply(outputSettings: audioSettings, forMediaType: .audio) {
            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings, sourceFormatHint: formatDescription)
            audioInput.expectsMediaDataInRealTime = true

            if assetWriter.canAdd(audioInput) {
                assetWriter.add(audioInput)
            } else {
                print("Cannot add audio input to asset writer")
                return false
            }
        } else {
            print("Cannot apply audio settings to asset writer")
            return false
        }
        return true
    }

    public func processFrame(_ captureOutput: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {

        if let assetWriter = self.assetWriter {
            let wasReadyToRecord = (readyToRecordAudio && readyToRecordVideo)
            if connection == self.videoConnection {
                if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer), !readyToRecordVideo {
                    readyToRecordVideo = self.setupAssetWriterVideoInput(formatDescription, assetWriter: assetWriter)
                }

                if readyToRecordVideo && readyToRecordAudio {
                    self.writeSampleBuffer(sampleBuffer: sampleBuffer, ofType: .video)
                }
            } else if connection == self.audioConnection {
                if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer), !readyToRecordAudio {
                    readyToRecordAudio = self.setupAssetWriterAudioInput(formatDescription,
                                                                         assetWriter: assetWriter)
                }

                if readyToRecordAudio && readyToRecordVideo {
                    self.writeSampleBuffer(sampleBuffer: sampleBuffer, ofType: .audio)
                }
            }
            let isReadyToRecord = readyToRecordAudio && readyToRecordVideo
            if !wasReadyToRecord && isReadyToRecord {
                recordingWillBeStarted = false
                self.isRecording = true
            }
        }
    }

    func writeSampleBuffer(sampleBuffer: CMSampleBuffer,
                           ofType mediaType: AVMediaType) {
        if !isRecording {
            return
        }
        writingQueue.async { [weak self] in
            guard let self = self else { return }
            guard let assetWriter = self.assetWriter else {
                return
            }
            if assetWriter.status == .unknown {
                if assetWriter.startWriting() {
                    assetWriter.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                } else {
                    // TODO: Show error
                }
            }

            if let input = (mediaType == .video) ? self.videoInput : self.audioInput {
                if input.isReadyForMoreMediaData {
                    let success = input.append(sampleBuffer)
                    if !success {
                        // TODO: Error
                    }
                }
            }
        }
    }
}
