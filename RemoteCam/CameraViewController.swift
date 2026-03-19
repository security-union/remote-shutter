//
//  CameraViewController.swift
//  RemoteShutter
//
//  Created by Dario on 10/7/15.
//  Copyright © 2020 Security Union LLC. All rights reserved.
//

import UIKit
import AVFoundation
import Photos
import StoreKit
import SwiftUI
import Combine

/**
Default fps, it would be neat if we would adjust this based on network conditions.
*/

var fps = 30


/**
  Camera UI
*/
public class CameraViewController: UIViewController,
        AVCapturePhotoCaptureDelegate {
    
    private enum AssociatedKeys {
        nonisolated(unsafe) static var microphonePromptController: UInt8 = 0
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
    var currentVideoResolution: VideoResolution = .hd1080p
    var currentVideoFrameRate: VideoFrameRate = .fps30
    var currentPhotoFormat: PhotoFormat = .jpeg
    var currentHDRMode: HDRMode = .off
    let session: ActorRef = getRemoteCamSession()!
    let frameSender: ActorRef = getFrameSender()!
    
    // MARK: - Zoom and Lens Properties
    private var currentZoomFactor: CGFloat = 1.0
    private var currentLensType: CameraLensType = .wideAngle
    private var availableLensTypes: [CameraLensType] = []
    private var zoomStops: [CGFloat] = [1.0]

    // MARK: - Camera Capabilities
    private var frontCameraInfo: RemoteCmd.CameraInfo?
    private var backCameraInfo: RemoteCmd.CameraInfo?

    // MARK: - Aspect Ratio
    var currentAspectRatio: AspectRatio = .sixteenNine
    
    private let writingQueue = DispatchQueue(label: "asset recorder writing queue", attributes: [], target: nil)

    private var videoInput: AVAssetWriterInput!
    private var audioInput: AVAssetWriterInput!

    // Variable used to downsample the camera preview, please use with care.
    private var sendFrame = true
    
    // MARK: - Recording Timer Properties
    private var recordingStartTime: Date?
    private var recordingTimerController: CameraRecordingTimerViewController?
    
    // MARK: - Video Transfer Progress Properties
    let cameraViewModel = CameraViewModel()
    private var progressOverlayController: UIHostingController<CameraProgressOverlayView>?

    // MARK: - Sound Manager for Countdown Chimes
    let cameraSoundManager = CPSoundManager()

    let recordingView = UIImageView()
    let activityIndicator = UIActivityIndicatorView(style: .large)

    public override func loadView() {
        let root = UIView()
        root.backgroundColor = .black

        recordingView.contentMode = .scaleAspectFit
        recordingView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(recordingView)

        activityIndicator.color = .white
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            recordingView.widthAnchor.constraint(equalToConstant: 45),
            recordingView.heightAnchor.constraint(equalToConstant: 45),
            recordingView.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            recordingView.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 17),

            activityIndicator.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])

        self.view = root
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        recordingView.image = UIImage.gifImageWithName("recording")
        session ! UICmd.BecomeCamera(sender: nil, ctrl: self)
        configureIdleMode()
        setupRecordingTimerOverlay()
        setupProgressOverlay()
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(false, animated: animated)

        navigationItem.title = nil
        navigationController?.navigationBar.prefersLargeTitles = false

        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.tintColor = .white

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
    
    // MARK: - Video Transfer Progress Methods
    private func setupProgressOverlay() {
        let progressOverlayView = CameraProgressOverlayView(viewModel: cameraViewModel)
        progressOverlayController = UIHostingController(rootView: progressOverlayView)
        
        if let overlayController = progressOverlayController {
            addChild(overlayController)
            view.addSubview(overlayController.view)
            overlayController.didMove(toParent: self)
            
            // Setup constraints to fill the entire view
            overlayController.view.translatesAutoresizingMaskIntoConstraints = false
            overlayController.view.backgroundColor = UIColor.clear
            NSLayoutConstraint.activate([
                overlayController.view.topAnchor.constraint(equalTo: view.topAnchor),
                overlayController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                overlayController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                overlayController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
        print("📱 DEBUG: CameraViewController - Setup progress overlay")
    }

    
    private func updateRecordingTimerDisplay() {
        recordingTimerController?.updateRecordingState(
            startTime: recordingStartTime,
            isRecording: isRecording
        )
    }
    
    private func showPermissionErrorView() {
        let errorView = CameraPermissionErrorView(
            onOpenSettings: { 
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
        ensureTorchOff()
        if self.isBeingDismissed || self.isMovingFromParent {
            if captureSession.isRunning {
                cameraConfigQueue.async { [weak self] in
                    self?.captureSession.stopRunning()
                }
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

    var currentCameraMode: RecordingMode = .Photo

    func configureIdleMode() {
        recordingView.isHidden = true
        navigationController?.isNavigationBarHidden = false
        activityIndicator.style = UIActivityIndicatorView.Style.large
        activityIndicator.color = UIColor.white
        updateCameraStatus()
    }

    func configureVideoModeRecording() {
        recordingView.isHidden = false
        navigationController?.isNavigationBarHidden = true
        currentCameraMode = .Video
        updateCameraStatus()
    }

    func updateCameraStatus() {
        cameraViewModel.updateStatus(
            mode: currentCameraMode,
            resolution: currentVideoResolution,
            frameRate: currentVideoFrameRate,
            photoFormat: currentPhotoFormat,
            hdrMode: currentHDRMode)
    }

    func playCountdownChime(remaining: Int) {
        if remaining == 2 {
            cameraSoundManager.playBeepSound(CPSoundManagerAudioTypeFast)
            countdownTorch.startStrobe(device: videoDeviceInput?.device)
        } else if remaining > 2 {
            cameraSoundManager.playBeepSound(CPSoundManagerAudioTypeSlow)
            countdownTorch.blinkOnce(device: videoDeviceInput?.device)
        }
    }

    func ensureTorchOff() {
        countdownTorch.stop(device: videoDeviceInput?.device)
    }

    // MARK: - Countdown Torch
    let countdownTorch = CameraCountdownTorch()

    public override var shouldAutorotate: Bool {
        // Disable autorotation of the interface when recording is in progress.
        return !isRecording
    }

    public override func willAnimateRotation(to toInterfaceOrientation: UIInterfaceOrientation, duration: TimeInterval) {
        orientation = getOrientation()
        self.rotateCameraToOrientation(orientation: toInterfaceOrientation)
    }

    func setupCamera() {
        self.cameraSettings.isHighResolutionPhotoEnabled = true
        self.videoDataOutput.setSampleBufferDelegate(self, queue: self.videoDataOutputQueue)
        self.videoDataOutput.videoSettings =
            [kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA)] as [String: Any]
        self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
        if self.captureSession.isRunning {
            self.cameraConfigQueue.async {
                self.captureSession.stopRunning()
            }
        }
        self.captureSession.beginConfiguration()
        self.captureSession.sessionPreset = .high

        guard let videoDevice = preferredBackCamera() ?? AVCaptureDevice.default(for: AVMediaType.video) else {
            return
        }
        print("🔍 SETUP CAMERA: using device=\(videoDevice.localizedName) type=\(videoDevice.deviceType.rawValue) isVirtual=\(!videoDevice.virtualDeviceSwitchOverVideoZoomFactors.isEmpty)")

        self.captureVideoPreviewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)

        self.captureVideoPreviewLayer!.videoGravity = AVLayerVideoGravity.resizeAspect
        DispatchQueue.main.async {
            self.captureVideoPreviewLayer!.frame = self.view.frame
            self.view.layer.insertSublayer(self.captureVideoPreviewLayer!, below: self.recordingView.layer)
        }

        do {
            self.videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            self.captureSession.addInput(self.videoDeviceInput)
            self.captureSession.addOutput(self.videoDataOutput)

            try self.setFrameRate(framerate: fps, videoDevice: videoDevice)
            
            // Gather complete camera capabilities for both front and back cameras
            self.gatherAllCameraCapabilities()
            
            // Initialize current state
            self.updateAvailableLensTypes(for: videoDevice.position)
            self.zoomStops = self.discoverZoomStops(for: videoDevice)

            // Start at the wide-angle zoom factor (matches native Camera app "1x")
            let wideZoom = self.wideAngleZoomFactor(for: videoDevice)
            if wideZoom > 1.0 {
                try videoDevice.lockForConfiguration()
                videoDevice.videoZoomFactor = wideZoom
                videoDevice.unlockForConfiguration()
            }
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
            self.cameraConfigQueue.async {
                self.captureSession.startRunning()
            }
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
            try setFrameRate(framerate: fps, videoDevice: newDevice!)
            
            // Update available lens types and zoom stops for new camera position
            self.updateAvailableLensTypes(for: newPosition!)
            self.zoomStops = self.discoverZoomStops(for: newDevice!)

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
            photoOutput.maxPhotoQualityPrioritization = .quality
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

    // MARK: - Virtual Device Preference

    /// Returns the best virtual camera device for the back position, falling back to wide-angle.
    /// Virtual devices automatically switch between physical cameras at appropriate zoom factors.
    func preferredBackCamera() -> AVCaptureDevice? {
        // Try triple camera first (iPhone 14 Pro+: ultra-wide + wide + telephoto)
        if let triple = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
            return triple
        }
        // Try dual wide camera (iPhone 11+: ultra-wide + wide)
        if let dualWide = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
            return dualWide
        }
        // Try dual camera (iPhone 7+: wide + telephoto)
        if let dual = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
            return dual
        }
        // Fallback to wide angle
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    /// Discovers hardware zoom stop factors from a virtual device's switchOverVideoZoomFactors.
    ///
    /// For builtInTripleCamera: base (1.0) = ultra-wide, switchovers e.g. [2.0, 6.0]
    /// - Hardware 1.0 = ultra-wide (displayed as "0.5x" by dividing by wideAngleZoomFactor)
    /// - Hardware 2.0 = wide-angle (displayed as "1x")
    /// - Hardware 6.0 = telephoto (displayed as "3x")
    func discoverZoomStops(for device: AVCaptureDevice) -> [CGFloat] {
        if device.position == .front {
            return [1.0]
        }

        let switchOverFactors = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        print("🔍 ZOOM STOPS: device=\(device.localizedName) switchOverFactors=\(switchOverFactors) minZoom=\(device.minAvailableVideoZoomFactor) maxZoom=\(device.maxAvailableVideoZoomFactor)")

        // Start with the base (1.0) which is the widest constituent camera
        var stops: [CGFloat] = [device.minAvailableVideoZoomFactor]

        // Add each switchover factor
        for f in switchOverFactors {
            if !stops.contains(f) {
                stops.append(f)
            }
        }

        // If no switchover factors, this is a single camera — just return [1.0]
        if switchOverFactors.isEmpty && stops == [1.0] {
            return [1.0]
        }

        let result = stops.sorted()
        print("🔍 ZOOM STOPS: final=\(result)")
        return result
    }

    /// Returns the hardware zoom factor that corresponds to the wide-angle camera.
    /// For virtual devices with ultra-wide base, this is the first switchover factor.
    /// For single cameras or dual (wide+telephoto), this is 1.0.
    func wideAngleZoomFactor(for device: AVCaptureDevice) -> CGFloat {
        let switchOverFactors = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        // If there are switchover factors and the base zoom < 1.5 (i.e., ultra-wide is base),
        // the first switchover is where the wide-angle starts
        if let first = switchOverFactors.first, device.minAvailableVideoZoomFactor < 1.5 {
            return first
        }
        return 1.0
    }

    func cameraForPosition(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .back {
            return preferredBackCamera()
        }
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
        
        // Gather quality capabilities — probe each resolution's actual FPS limits
        let supportedResolutions = VideoResolution.selectableCases.filter { r in
            captureSession.canSetSessionPreset(r.sessionPreset)
        }

        var resolutionFrameRates: [VideoResolution: [VideoFrameRate]] = [:]
        var allSupportedFrameRates: Set<VideoFrameRate> = []

        if let dev = videoDevices.first {
            for res in supportedResolutions {
                let maxFPS = maxFPSAcrossFormats(for: dev, resolution: res)
                let rates = VideoFrameRate.selectableCases.filter { $0.value <= Int(maxFPS) }
                resolutionFrameRates[res] = rates
                rates.forEach { allSupportedFrameRates.insert($0) }
            }
        }

        let supportedFrameRates = VideoFrameRate.selectableCases.filter { allSupportedFrameRates.contains($0) }

        let supportsHEIF = photoOutput.availablePhotoCodecTypes.contains(.hevc)
        let supportsHDR = true // All iOS 15+ devices support .quality prioritization (HDR)

        // Discover zoom stops from virtual device
        let preferredDevice: AVCaptureDevice?
        if position == .back {
            preferredDevice = preferredBackCamera()
        } else {
            preferredDevice = videoDevices.first
        }
        let discoveredZoomStops = preferredDevice.map { discoverZoomStops(for: $0) } ?? [1.0]
        let wideAngle = preferredDevice.map { wideAngleZoomFactor(for: $0) } ?? 1.0

        return RemoteCmd.CameraInfo(
            availableLenses: availableLenses,
            hasFlash: hasFlash,
            hasTorch: hasTorch,
            zoomCapabilities: zoomCapabilities,
            supportedResolutions: supportedResolutions,
            supportedFrameRates: supportedFrameRates,
            resolutionFrameRates: resolutionFrameRates,
            supportsHEIF: supportsHEIF,
            supportsHDR: supportsHDR,
            zoomStops: discoveredZoomStops,
            wideAngleZoomFactor: wideAngle
        )
    }
    
    func sendCameraCapabilities() {
        guard let currentDevice = self.videoDeviceInput?.device else { return }
        
        let capabilities = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: frontCameraInfo,
            backCamera: backCameraInfo,
            currentCamera: currentDevice.position,
            currentLens: currentLensType,
            currentZoom: currentZoomFactor,
            currentVideoResolution: currentVideoResolution,
            currentVideoFrameRate: currentVideoFrameRate,
            currentPhotoFormat: currentPhotoFormat,
            currentHDRMode: currentHDRMode,
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
            currentVideoResolution: currentVideoResolution,
            currentVideoFrameRate: currentVideoFrameRate,
            currentPhotoFormat: currentPhotoFormat,
            currentHDRMode: currentHDRMode,
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

            // Update currentLensType based on which lens the virtual device is using
            currentLensType = lensTypeForZoomFactor(clampedZoom, device: device)

            device.unlockForConfiguration()

            print("✅ DEBUG: Zoom set successfully to \(device.videoZoomFactor), lens: \(currentLensType.displayName)")

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

    /// Determines which lens is active based on the current zoom factor and switchover points.
    private func lensTypeForZoomFactor(_ zoom: CGFloat, device: AVCaptureDevice) -> CameraLensType {
        let switchOverFactors = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        guard !switchOverFactors.isEmpty else { return .wideAngle }

        if switchOverFactors.count >= 2 && zoom >= switchOverFactors[1] {
            return .telephoto
        } else if zoom >= switchOverFactors[0] {
            return .wideAngle
        } else {
            return .ultraWide
        }
    }

    /// Maps a CameraLensType to the appropriate hardware zoom factor on the current virtual device.
    ///
    /// For builtInTripleCamera with switchOverFactors [2, 6]:
    ///   .ultraWide → 1.0 (base = ultra-wide)
    ///   .wideAngle → 2.0 (first switchover)
    ///   .telephoto → 6.0 (second switchover)
    private func zoomFactorForLensType(_ lensType: CameraLensType, device: AVCaptureDevice) -> CGFloat {
        let switchOverFactors = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }

        switch lensType {
        case .ultraWide:
            // Ultra-wide is the base lens of the virtual device
            return device.minAvailableVideoZoomFactor
        case .wideAngle:
            // Wide-angle is at the first switchover factor
            return switchOverFactors.first ?? 1.0
        case .telephoto:
            // Telephoto is at the last switchover factor
            return switchOverFactors.last ?? switchOverFactors.first ?? 2.0
        case .dualCamera:
            return switchOverFactors.first ?? 2.0
        }
    }

    func switchLens(to lensType: CameraLensType) -> Try<(CameraLensType, [CameraLensType], CGFloat, RemoteCmd.ZoomRange)> {
        guard let device = self.videoDeviceInput?.device else {
            return Failure(error: NSError(domain: "No camera device available", code: 0, userInfo: nil))
        }

        // If using a virtual device, just set the zoom factor — the virtual device
        // automatically switches physical cameras at the right zoom levels.
        let isVirtualDevice = !device.virtualDeviceSwitchOverVideoZoomFactors.isEmpty
                              || device.minAvailableVideoZoomFactor < 0.9

        if isVirtualDevice {
            let targetZoom = zoomFactorForLensType(lensType, device: device)
            do {
                try device.lockForConfiguration()
                let clampedZoom = max(device.minAvailableVideoZoomFactor,
                                     min(targetZoom, device.maxAvailableVideoZoomFactor))
                device.videoZoomFactor = clampedZoom
                currentZoomFactor = clampedZoom
                currentLensType = lensType
                device.unlockForConfiguration()

                let zoomRange = RemoteCmd.ZoomRange(
                    minZoom: device.minAvailableVideoZoomFactor,
                    maxZoom: device.maxAvailableVideoZoomFactor
                )
                return Success((lensType, availableLensTypes, currentZoomFactor, zoomRange))
            } catch let error as NSError {
                return Failure(error: error)
            }
        }

        // Fallback: swap physical devices for non-virtual cameras (e.g., front camera)
        let position = device.position
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

            currentZoomFactor = 1.0

            configSessionOutput()
            try setFrameRate(framerate: fps, videoDevice: newDevice)

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

    func setFrameRate(framerate: Int, videoDevice: AVCaptureDevice) throws {
        let maxFPS = Int(maxSupportedFPS(for: videoDevice))
        let safeFPS = max(1, min(framerate, maxFPS))
        try videoDevice.lockForConfiguration()
        videoDevice.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: Int32(safeFPS))
        videoDevice.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(safeFPS))
        videoDevice.unlockForConfiguration()
        if safeFPS != framerate {
            RemoteShutter.fps = safeFPS
            currentVideoFrameRate = VideoFrameRate.selectableCases.last(where: { $0.value <= safeFPS }) ?? .fps30
            updateCameraStatus()
        }
    }

    /// Max FPS supported by the device's *current active format*.
    func maxSupportedFPS(for device: AVCaptureDevice) -> Double {
        device.activeFormat.videoSupportedFrameRateRanges.reduce(30.0) { max($0, $1.maxFrameRate) }
    }

    /// Max FPS across *all* device formats at a given resolution.
    func maxFPSAcrossFormats(for device: AVCaptureDevice, resolution: VideoResolution) -> Double {
        let targetDims = resolution.dimensions
        var result: Double = 30
        for format in device.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.width >= targetDims.width && dims.height >= targetDims.height else { continue }
            for range in format.videoSupportedFrameRateRanges {
                result = max(result, range.maxFrameRate)
            }
        }
        return result
    }

    /// Finds a device format supporting both the target resolution and FPS.
    func findFormat(for device: AVCaptureDevice, resolution: VideoResolution, fps: Double) -> AVCaptureDevice.Format? {
        let targetDims = resolution.dimensions
        for format in device.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.width >= targetDims.width && dims.height >= targetDims.height else { continue }
            if format.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= fps }) {
                return format
            }
        }
        return nil
    }

    func setVideoQuality(resolution: VideoResolution, frameRate: VideoFrameRate) -> (VideoResolution, VideoFrameRate)? {
        guard !isRecording else { return nil }
        guard let device = videoDeviceInput?.device else { return nil }

        captureSession.beginConfiguration()

        var appliedFrameRate = frameRate

        if let format = findFormat(for: device, resolution: resolution, fps: Double(frameRate.value)) {
            captureSession.sessionPreset = .inputPriority
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                device.unlockForConfiguration()
            } catch {
                captureSession.commitConfiguration()
                return nil
            }
        } else {
            guard captureSession.canSetSessionPreset(resolution.sessionPreset) else {
                captureSession.commitConfiguration()
                return nil
            }
            captureSession.sessionPreset = resolution.sessionPreset
            let maxFPS = Int(maxSupportedFPS(for: device))
            appliedFrameRate = VideoFrameRate.selectableCases
                .filter { $0.value <= maxFPS }
                .last ?? .fps30
        }

        do {
            try setFrameRate(framerate: appliedFrameRate.value, videoDevice: device)
        } catch {
            captureSession.commitConfiguration()
            return nil
        }
        captureSession.commitConfiguration()

        currentVideoResolution = resolution
        currentVideoFrameRate = appliedFrameRate
        RemoteShutter.fps = appliedFrameRate.value
        updateCameraStatus()

        return (resolution, appliedFrameRate)
    }

    // MARK: - Aspect Ratio Methods

    func setAspectRatio(_ ratio: AspectRatio) -> AspectRatio {
        currentAspectRatio = ratio
        updateCameraStatus()
        return ratio
    }

    /// Crops photo data to the selected aspect ratio using CGImage.
    func cropPhotoData(_ data: Data, to aspectRatio: AspectRatio) -> Data? {
        guard let image = UIImage(data: data),
              let cgImage = image.cgImage else { return nil }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        // Determine the target ratio for the image's actual orientation
        let isLandscape = imageWidth > imageHeight
        let targetRatio = isLandscape ? aspectRatio.widthToHeight : (1.0 / aspectRatio.widthToHeight)
        let currentRatio = imageWidth / imageHeight

        var cropRect: CGRect
        if abs(currentRatio - targetRatio) < 0.01 {
            return data // Already at the target aspect ratio
        } else if currentRatio > targetRatio {
            // Wider than target: crop sides
            let newWidth = imageHeight * targetRatio
            let xOffset = (imageWidth - newWidth) / 2
            cropRect = CGRect(x: xOffset, y: 0, width: newWidth, height: imageHeight)
        } else {
            // Taller than target: crop top/bottom
            let newHeight = imageWidth / targetRatio
            let yOffset = (imageHeight - newHeight) / 2
            cropRect = CGRect(x: 0, y: yOffset, width: imageWidth, height: newHeight)
        }

        guard let croppedCG = cgImage.cropping(to: cropRect) else { return nil }
        let croppedImage = UIImage(cgImage: croppedCG, scale: image.scale, orientation: image.imageOrientation)
        return croppedImage.jpegData(compressionQuality: 0.95)
    }

    func setPhotoQuality(format: PhotoFormat, hdrMode: HDRMode) -> (PhotoFormat, HDRMode)? {
        if format == .heif {
            guard photoOutput.availablePhotoCodecTypes.contains(.hevc) else { return nil }
        }

        currentPhotoFormat = format
        currentHDRMode = hdrMode
        updateCameraStatus()
        return (format, hdrMode)
    }

    func cloneCameraSettings(_ settings: AVCapturePhotoSettings) -> AVCapturePhotoSettings {
        let newSettings: AVCapturePhotoSettings
        if currentPhotoFormat == .heif && photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            newSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            newSettings = AVCapturePhotoSettings()
        }
        newSettings.flashMode = settings.flashMode
        newSettings.isHighResolutionPhotoEnabled = settings.isHighResolutionPhotoEnabled
        if currentHDRMode == .on {
            newSettings.photoQualityPrioritization = .quality
        } else {
            newSettings.photoQualityPrioritization = .balanced
        }
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
        // Apply aspect ratio cropping if needed
        if currentAspectRatio != .sixteenNine,
           let croppedData = cropPhotoData(photoData, to: currentAspectRatio) {
            session ! UICmd.OnPicture(sender: nil, pic: croppedData)
        } else {
            session ! UICmd.OnPicture(sender: nil, pic: photoData)
        }
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
        
                 // Send video to the monitor using resource transfer if requested
         if sendVideoToPeer {
             sendVideoAsResource(outputFileURL)
         } else {
             // Send empty response when not sending video
             session ! RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: nil)
         }
         
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
   }
   
       // MARK: - Video Resource Transfer
    private func sendVideoAsResource(_ videoURL: URL) {
        // Get connected peers through the session
        // Note: We can't access session.connectedPeers directly since session is ActorRef
        // Instead, we'll send a message to let the actor handle peer checking
        
        // Send message to RemoteCamSession actor to handle video resource transfer
        let sendVideoMsg = UICmd.SendVideoResource(
            videoURL: videoURL,
            peers: [], // Will be populated by the actor from its session
            shouldSendToPeer: true,
            sender: nil
        )
        
        session ! sendVideoMsg
        print("📤 DEBUG: Sent SendVideoResource message to actor system")
    }
    
    // MARK: - Video Transfer Progress
    // Video transfer progress is now handled directly in CameraVideoStates.swift
    // via the direct ctrl reference passed to camera states

   func setupAssetWriterVideoInput(_ formatDescription: CMVideoFormatDescription,
                                    assetWriter: AVAssetWriter) -> Bool {
        // Get recommended settings and override codec to HEVC (H.265) for smaller files
        var videoSettings = self.videoDataOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov)
        videoSettings?[AVVideoCodecKey] = AVVideoCodecType.hevc

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
