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
import StoreKit
import SwiftUI

/**
Default fps, it would be neat if we would adjust this based on network conditions.
*/

let fps = 30


/**
  Camera UI
*/
public class CameraViewController: UIViewController,
        AVCapturePhotoCaptureDelegate {
    
    private struct AssociatedKeys {
        static var microphonePromptController = "microphonePromptController"
    }

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
    let session: ActorRef = getRemoteCamSession()!
    let frameSender: ActorRef = getFrameSender()!
    
    // MARK: - Zoom and Lens Properties
    private var currentZoomFactor: CGFloat = 1.0
    private var currentLensType: CameraLensType = .wideAngle
    private var availableLensTypes: [CameraLensType] = []
    
    // MARK: - Camera Capabilities
    private var frontCameraInfo: RemoteCmd.CameraInfo?
    private var backCameraInfo: RemoteCmd.CameraInfo?
    
    private let writingQueue = DispatchQueue(label: "asset recorder writing queue", attributes: [], target: nil)

    private var videoInput: AVAssetWriterInput!
    private var audioInput: AVAssetWriterInput!

    // Variable used to downsample the camera preview, please use with care.
    private var sendFrame = true
    
    // MARK: - Recording Timer Properties
    private var recordingStartTime: Date?
    private var recordingTimerController: CameraRecordingTimerViewController?

    @IBOutlet weak var back: UIButton!
    @IBOutlet var recordingView: UIImageView!
    @IBOutlet var activityIndicator: UIActivityIndicatorView!

    override public func viewDidLoad() {
        super.viewDidLoad()
        recordingView.image = UIImage.gifImageWithName("recording")
        session ! UICmd.BecomeCamera(sender: nil, ctrl: self)
        configureIdleMode()
        setupRecordingTimerOverlay()
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.isNavigationBarHidden = true
        orientation = getOrientation()
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        checkPermissionsAndSetupCamera()
    }
    
    private func checkPermissionsAndSetupCamera() {
        let permissionManager = PermissionManager.shared
        permissionManager.updatePermissionStatuses()
        
        if permissionManager.areCameraAndPhotosGranted {
            let _ = self.didInitializeCamera
        } else {
            showPermissionErrorView()
        }
    }
    
    // MARK: - Recording Timer Methods
    private func setupRecordingTimerOverlay() {
        recordingTimerController = CameraRecordingTimerViewController()
        
        if let timerController = recordingTimerController {
            addChild(timerController)
            view.addSubview(timerController.view)
            timerController.didMove(toParent: self)
            
            // Setup constraints to fill the entire view
            timerController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                timerController.view.topAnchor.constraint(equalTo: view.topAnchor),
                timerController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                timerController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                timerController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
    }
    
    private func updateRecordingTimerDisplay() {
        recordingTimerController?.updateRecordingState(
            startTime: recordingStartTime,
            isRecording: isRecording
        )
    }
    
    private func showPermissionErrorView() {
        let errorView = CameraPermissionErrorView(
            onOpenSettings: { [weak self] in
                PermissionManager.shared.openAppSettings()
            },
            onGoBack: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
        )
        
        let hostingController = UIHostingController(rootView: errorView)
        hostingController.view.backgroundColor = UIColor.black
        
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hostingController.didMove(toParent: self)
    }
    
    lazy var didInitializeCamera: Bool = {
        activityIndicator.startAnimating()
        self.setupCamera()
        activityIndicator.stopAnimating()
        return true
    }()

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
        activityIndicator.style = .whiteLarge
        activityIndicator.color = UIColor.white
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
        self.cameraSettings.isHighResolutionPhotoEnabled = true
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
            
            // Gather complete camera capabilities for both front and back cameras
            self.gatherAllCameraCapabilities()
            
            // Initialize current state
            self.updateAvailableLensTypes(for: videoDevice.position)
            self.currentZoomFactor = videoDevice.videoZoomFactor

            // Camera capabilities are now sent through peer-to-peer communication in CamStates.swift
            // No need to send to session actor directly here

            // Audio setup will be done only when starting video recording
            // This prevents requesting microphone permission upfront
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
            
            // Update available lens types for new camera position
            self.updateAvailableLensTypes(for: newPosition!)
            
            do {
                self.rotateCameraToOrientation(orientation: self.orientation)
                let newFlashMode: AVCaptureDevice.FlashMode? = (newInput.device.hasFlash) ? self.cameraSettings.flashMode : nil
                captureSession.commitConfiguration()
                
                // Camera capabilities are now sent via RemoteCmd.ToggleCameraResp in CamStates.swift
                // No need to send separate capabilities message here
                
                return Success((newFlashMode, newInput.device.position))
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
            photoOutput.isHighResolutionCaptureEnabled = true
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
            return Success(newFlashMode)
        } else {
            return Failure(error: NSError(domain: "Current camera does not support flash.", code: 0, userInfo: nil))
        }
    }

    // MARK: - Torch Methods for Video Recording
    func toggleTorch() -> Try<AVCaptureDevice.TorchMode> {
        let genericDevice = self.videoDeviceInput
        let device = genericDevice?.device
        if let hasTorch = device?.hasTorch, hasTorch {
            do {
                try device?.lockForConfiguration()
                let currentTorchMode = device?.torchMode ?? .off
                let newTorchMode: AVCaptureDevice.TorchMode
                
                switch currentTorchMode {
                case .off:
                    newTorchMode = .on
                case .on:
                    newTorchMode = .off
                case .auto:
                    newTorchMode = .off
                @unknown default:
                    newTorchMode = .off
                }
                
                device?.torchMode = newTorchMode
                device?.unlockForConfiguration()
                return Success(newTorchMode)
            } catch let error as NSError {
                return Failure(error: error)
            }
        } else {
            return Failure(error: NSError(domain: "Current camera does not support torch.", code: 0, userInfo: nil))
        }
    }
    
    func setTorchMode(mode: AVCaptureDevice.TorchMode) -> Try<AVCaptureDevice.TorchMode> {
        let genericDevice = self.videoDeviceInput
        let device = genericDevice?.device
        if let hasTorch = device?.hasTorch, hasTorch {
            do {
                try device?.lockForConfiguration()
                device?.torchMode = mode
                device?.unlockForConfiguration()
                return Success(mode)
            } catch let error as NSError {
                return Failure(error: error)
            }
        } else {
            return Failure(error: NSError(domain: "Current camera does not support torch.", code: 0, userInfo: nil))
        }
    }
    
    func getCurrentTorchMode() -> AVCaptureDevice.TorchMode {
        return videoDeviceInput?.device.torchMode ?? .off
    }
    
    func hasTorch() -> Bool {
        return videoDeviceInput?.device.hasTorch ?? false
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
        return Success(mode)
    }

    func cameraForPosition(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        return cameraForPositionAndLens(position: position, lensType: currentLensType)
    }
    
    func cameraForPositionAndLens(position: AVCaptureDevice.Position, lensType: CameraLensType) -> AVCaptureDevice? {
        let deviceTypes = getAllDeviceTypes()
        let videoDevices = AVCaptureDevice.DiscoverySession.init(
                deviceTypes: deviceTypes,
                mediaType: .video, position: position).devices
        
        // First try to find the specific lens type
        var filteredDevices = videoDevices.filter {
            return $0.position == position && $0.deviceType == lensType.deviceType
        }
        
        // If no specific lens found, fall back to wide angle
        if filteredDevices.isEmpty {
            filteredDevices = videoDevices.filter {
                return $0.position == position && $0.deviceType == .builtInWideAngleCamera
            }
        }
        
        return filteredDevices.first
    }
    
    func getAllDeviceTypes() -> [AVCaptureDevice.DeviceType] {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInDualCamera,
            .builtInTelephotoCamera
        ]
        
        if #available(iOS 13.0, *) {
            deviceTypes.append(.builtInUltraWideCamera)
            deviceTypes.append(.builtInTripleCamera)
        }
        
        return deviceTypes
    }
    
    func updateAvailableLensTypes(for position: AVCaptureDevice.Position) {
        let deviceTypes = getAllDeviceTypes()
        let videoDevices = AVCaptureDevice.DiscoverySession.init(
                deviceTypes: deviceTypes,
                mediaType: .video, position: position).devices
        
        availableLensTypes = CameraLensType.allCases.filter { lensType in
            return videoDevices.contains { $0.deviceType == lensType.deviceType }
        }
    }

    // MARK: - Camera Capabilities Gathering
    func gatherAllCameraCapabilities() {
        print("🔍 DEBUG: gatherAllCameraCapabilities called")
        
        // Gather front camera capabilities
        frontCameraInfo = gatherCameraInfo(for: .front)
        print("🔍 DEBUG: Front camera info: \(frontCameraInfo != nil ? "available" : "nil")")
        
        // Gather back camera capabilities  
        backCameraInfo = gatherCameraInfo(for: .back)
        print("🔍 DEBUG: Back camera info: \(backCameraInfo != nil ? "available" : "nil")")
        
        if let backInfo = backCameraInfo {
            print("🔍 DEBUG: - Back camera available lenses: \(backInfo.availableLenses)")
            print("🔍 DEBUG: - Back camera has flash: \(backInfo.hasFlash)")
        }
        
        if let frontInfo = frontCameraInfo {
            print("🔍 DEBUG: - Front camera available lenses: \(frontInfo.availableLenses)")
            print("🔍 DEBUG: - Front camera has flash: \(frontInfo.hasFlash)")
        }
    }
    
    func gatherCameraInfo(for position: AVCaptureDevice.Position) -> RemoteCmd.CameraInfo? {
        let positionName = position == .front ? "Front" : "Back"
        print("🔍 DEBUG: gatherCameraInfo for \(positionName) camera")
        
        let deviceTypes = getAllDeviceTypes()
        let videoDevices = AVCaptureDevice.DiscoverySession.init(
                deviceTypes: deviceTypes,
                mediaType: .video, position: position).devices
        
        print("🔍 DEBUG: - Found \(videoDevices.count) devices for \(positionName) position")
        for device in videoDevices {
            print("🔍 DEBUG: - \(device.localizedName) (\(device.deviceType.rawValue))")
        }
        
        guard !videoDevices.isEmpty else { 
            print("🔍 DEBUG: - No devices found for \(positionName) position")
            return nil 
        }
        
        // Find available lens types for this position
        let availableLenses = CameraLensType.allCases.filter { lensType in
            return videoDevices.contains { $0.deviceType == lensType.deviceType }
        }
        
        print("🔍 DEBUG: - Final available lenses: \(availableLenses.map { $0.displayName })")
        
        // Check if any camera on this position has flash
        let hasFlash = videoDevices.contains { $0.hasFlash }
        
        // Check if any camera on this position has torch
        let hasTorch = videoDevices.contains { $0.hasTorch }
        
        // Gather zoom capabilities for each lens type
        var zoomCapabilities: [CameraLensType: RemoteCmd.ZoomRange] = [:]
        
        for lensType in availableLenses {
            if let device = videoDevices.first(where: { $0.deviceType == lensType.deviceType }) {
                let zoomRange = RemoteCmd.ZoomRange(
                    minZoom: device.minAvailableVideoZoomFactor,
                    maxZoom: device.maxAvailableVideoZoomFactor
                )
                zoomCapabilities[lensType] = zoomRange
            }
        }
        
        return RemoteCmd.CameraInfo(
            availableLenses: availableLenses,
            hasFlash: hasFlash,
            hasTorch: hasTorch,
            zoomCapabilities: zoomCapabilities
        )
    }
    
    func sendCameraCapabilities() {
        guard let currentDevice = self.videoDeviceInput?.device else { return }
        
        let currentZoomRange = RemoteCmd.ZoomRange(
            minZoom: currentDevice.minAvailableVideoZoomFactor,
            maxZoom: currentDevice.maxAvailableVideoZoomFactor
        )
        
        let capabilities = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: frontCameraInfo,
            backCamera: backCameraInfo,
            currentCamera: currentDevice.position,
            currentLens: currentLensType,
            currentZoom: currentZoomFactor,
            error: nil
        )
        
        session ! capabilities
    }

    // MARK: - Current Camera Capabilities for Toggle Response
    func gatherCurrentCameraCapabilities() -> RemoteCmd.CameraCapabilitiesResp? {
        print("🔍 DEBUG: gatherCurrentCameraCapabilities called")
        
        guard let currentDevice = self.videoDeviceInput?.device else { 
            print("❌ DEBUG: No videoDeviceInput.device available")
            print("❌ DEBUG: videoDeviceInput is \(self.videoDeviceInput != nil ? "not nil" : "nil")")
            return nil 
        }
        
        print("🔍 DEBUG: Current device: \(currentDevice.localizedName)")
        print("🔍 DEBUG: frontCameraInfo: \(frontCameraInfo != nil ? "available" : "nil")")
        print("🔍 DEBUG: backCameraInfo: \(backCameraInfo != nil ? "available" : "nil")")
        
        let capabilities = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: frontCameraInfo,
            backCamera: backCameraInfo,
            currentCamera: currentDevice.position,
            currentLens: currentLensType,
            currentZoom: currentZoomFactor,
            error: nil
        )
        
        print("🔍 DEBUG: Created capabilities response successfully")
        return capabilities
    }
    
    // MARK: - Enhanced Zoom Control Methods
    func setZoom(zoomFactor: CGFloat) -> Try<(CGFloat, CameraLensType, RemoteCmd.ZoomRange)> {
        print("🔍 DEBUG: setZoom called with factor: \(zoomFactor)")
        
        guard let device = self.videoDeviceInput?.device else {
            print("❌ DEBUG: No camera device available")
            return Failure(error: NSError(domain: "No camera device available", code: 0, userInfo: nil))
        }
        
        print("🔍 DEBUG: Current device: \(device.localizedName), position: \(device.position.rawValue)")
        print("🔍 DEBUG: Zoom range: \(device.minAvailableVideoZoomFactor) - \(device.maxAvailableVideoZoomFactor)")
        print("🔍 DEBUG: Current zoom: \(device.videoZoomFactor)")
        
        do {
            try device.lockForConfiguration()
            
            let clampedZoom = max(device.minAvailableVideoZoomFactor, 
                                 min(zoomFactor, device.maxAvailableVideoZoomFactor))
            
            print("🔍 DEBUG: Setting zoom from \(device.videoZoomFactor) to \(clampedZoom)")
            device.videoZoomFactor = clampedZoom
            currentZoomFactor = clampedZoom
            
            device.unlockForConfiguration()
            
            print("✅ DEBUG: Zoom set successfully to \(device.videoZoomFactor)")
            
            let zoomRange = RemoteCmd.ZoomRange(
                minZoom: device.minAvailableVideoZoomFactor,
                maxZoom: device.maxAvailableVideoZoomFactor
            )
            
            return Success((clampedZoom, currentLensType, zoomRange))
        } catch let error as NSError {
            print("❌ DEBUG: Error setting zoom: \(error.localizedDescription)")
            return Failure(error: error)
        }
    }
    
    func getCurrentZoomFactor() -> CGFloat {
        return videoDeviceInput?.device.videoZoomFactor ?? 1.0
    }
    
    func getMaxZoomFactor() -> CGFloat {
        return videoDeviceInput?.device.maxAvailableVideoZoomFactor ?? 1.0
    }
    
    func getMinZoomFactor() -> CGFloat {
        return videoDeviceInput?.device.minAvailableVideoZoomFactor ?? 1.0
    }

    // MARK: - Enhanced Lens Switching Methods
    func switchLens(to lensType: CameraLensType) -> Try<(CameraLensType, [CameraLensType], CGFloat, RemoteCmd.ZoomRange)> {
        guard let currentDevice = self.videoDeviceInput?.device else {
            return Failure(error: NSError(domain: "No camera device available", code: 0, userInfo: nil))
        }
        
        let position = currentDevice.position
        guard let newDevice = cameraForPositionAndLens(position: position, lensType: lensType) else {
            return Failure(error: NSError(domain: "Requested lens type not available", code: 0, userInfo: nil))
        }
        
        do {
            let captureSession = self.captureSession
            captureSession.beginConfiguration()
            
            let newInput = try AVCaptureDeviceInput(device: newDevice)
            captureSession.removeInput(self.videoDeviceInput)
            captureSession.addInput(newInput)
            self.videoDeviceInput = newInput
            self.currentLensType = lensType
            
            // Reset zoom to 1.0 when switching lenses
            currentZoomFactor = 1.0
            
            configSessionOutput()
            setFrameRate(framerate: fps, videoDevice: newDevice)
            
            DispatchQueue.main.async {
                self.rotateCameraToOrientation(orientation: self.orientation)
            }
            
            captureSession.commitConfiguration()
            
            let zoomRange = RemoteCmd.ZoomRange(
                minZoom: newDevice.minAvailableVideoZoomFactor,
                maxZoom: newDevice.maxAvailableVideoZoomFactor
            )
            
            return Success((lensType, availableLensTypes, currentZoomFactor, zoomRange))
        } catch let error as NSError {
            return Failure(error: error)
        }
    }
    
    func getAvailableLensTypes() -> [CameraLensType] {
        return availableLensTypes
    }
    
    func getCurrentLensType() -> CameraLensType {
        return currentLensType
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
            return Success(framerate)
        } catch let error as NSError {
            return Failure(error: error)
        } catch {
            return Failure(error: NSError(domain: "unknown error", code: 0, userInfo: nil))
        }
    }

    func cloneCameraSettings(_ settings: AVCapturePhotoSettings) -> AVCapturePhotoSettings {
        let newSettings = AVCapturePhotoSettings()
        newSettings.flashMode = settings.flashMode
        newSettings.isHighResolutionPhotoEnabled = settings.isHighResolutionPhotoEnabled
        return newSettings
    }

    func takePicture(_ sendMediaToRemote: Bool) {
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
        // Check microphone permission before starting video recording
        PermissionManager.shared.requestMicrophonePermission { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.setupAudioAndStartRecording()
                } else {
                    // Microphone denied - show prompt and send error to remote
                    self?.handleMicrophoneDenied()
                }
            }
        }
    }
    
    private func handleMicrophoneDenied() {
        // Store the error to be handled by the state machine
        let microphoneError = NSError(
            domain: "RemoteShutterError",
            code: 1001,
            userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("microphone_access_denied_error", comment: "")]
        )
        
        // Send the error through the session actor using a custom message
        session ! UICmd.MicrophoneAccessDenied(error: microphoneError)
        
        // Show microphone permission prompt to user
        showMicrophonePermissionPrompt()
    }
    
    private func showMicrophonePermissionPrompt() {
        let promptView = MicrophonePermissionPromptView(
            onOpenSettings: { [weak self] in
                self?.dismissMicrophonePrompt()
                PermissionManager.shared.openAppSettings()
            },
            onCancel: { [weak self] in
                self?.dismissMicrophonePrompt()
            }
        )
        
        let hostingController = UIHostingController(rootView: promptView)
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.view.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        
        present(hostingController, animated: true)
        
        // Store reference to dismiss later
        objc_setAssociatedObject(self, &AssociatedKeys.microphonePromptController, hostingController, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    private func dismissMicrophonePrompt() {
        if let promptController = objc_getAssociatedObject(self, &AssociatedKeys.microphonePromptController) as? UIViewController {
            promptController.dismiss(animated: true)
            objc_setAssociatedObject(self, &AssociatedKeys.microphonePromptController, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private func setupAudioAndStartRecording() {
        writingQueue.async { [weak self] in
            guard let self = self else { return }
            if self.recordingWillBeStarted || self.isRecording {
                return
            }
            
            // Setup audio input for video recording
            do {
                let audioDevice = AVCaptureDevice.default(for: .audio)
                let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice!)
                
                self.captureSession.beginConfiguration()
                
                if self.captureSession.canAddInput(audioDeviceInput) {
                    self.captureSession.addInput(audioDeviceInput)
                } else {
                    print("Could not add audio device input to the session")
                }
                
                if self.captureSession.canAddOutput(self.audioDataOutput) {
                    self.captureSession.addOutput(self.audioDataOutput)
                    self.audioDataOutput.setSampleBufferDelegate(self, queue: self.audioDataOutputQueue)
                }
                
                self.captureSession.commitConfiguration()
                
                // Update audio connection
                self.audioConnection = self.audioDataOutput.connection(with: .audio)
                
                self.startVideoRecordingProcess()
                
            } catch {
                print("Error setting up audio for video recording: \(error)")
                // Start recording without audio
                self.startVideoRecordingWithoutAudio()
            }
        }
    }
    
    private func startVideoRecordingWithoutAudio() {
        writingQueue.async { [weak self] in
            self?.startVideoRecordingProcess()
        }
    }
    
    private func startVideoRecordingProcess() {
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

    func stopRecordingVideo(_ shouldSendVideo:Bool) {
        writingQueue.async {[weak self] in
            guard let self = self else { return }
            if self.recordingWillBeStopped || !self.isRecording {
                return
            }
            self.isRecording = false
            self.recordingWillBeStopped = true
            
            // Stop recording timer
            DispatchQueue.main.async { [weak self] in
                self?.recordingStartTime = nil
                self?.updateRecordingTimerDisplay()
            }
            self.assetWriter?.finishWriting {[weak self] in
                self?.assetWriter=nil
                self?.readyToRecordVideo = false
                self?.readyToRecordAudio = false
                self?.recordingWillBeStopped = false
                self?.saveMovieToPhotosAppAndRemotePeer(shouldSendVideo)
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
        sendFrame = !sendFrame
        if !sendFrame {
            return
        }
        if let cgBackedImage = imageFromSampleBuffer(sampleBuffer: sampleBuffer),
           let imageData = cgBackedImage.jpegData(compressionQuality: 0.1),
           let device = self.videoDeviceInput?.device {
            frameSender ! RemoteCmd.SendFrame(data: imageData,
                    sender: nil,
                    fps: fps,
                    camPosition: device.position,
                    camOrientation: self.orientation)
        }
    }

    func saveMovieToPhotosAppAndRemotePeer(_ sendVideoToPeer:Bool) {
        let outputFileURL = movieUrl()
        if let data = try? Data(contentsOf: outputFileURL) {
            // Send video to the monitor
            let data_if_needed = sendVideoToPeer ? data : nil
            session ! RemoteCmd.StopRecordingVideoResp(sender: nil, pic: data_if_needed, error: nil)
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
                    DispatchQueue.main.async {[weak self] in
                        self?.showPhotosAccessDeniedModal(for: .video)
                    }
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
                
                // Start recording timer and notify monitor
                DispatchQueue.main.async { [weak self] in
                    let startTime = Date()
                    self?.recordingStartTime = startTime
                    self?.updateRecordingTimerDisplay()
                    
                    // Send recording start time to monitor for synchronization
                    if let session = self?.session {
                        session ! RemoteCmd.StartRecordingVideoAck(sender: nil, recordingStartTime: startTime)
                    }
                    
                }
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
