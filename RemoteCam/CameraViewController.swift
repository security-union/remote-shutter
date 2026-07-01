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

    /// When true, this camera is controlled by an Apple Watch via WCSession.
    /// Suppresses MultipeerConnectivity-related actor messages (BecomeCamera/UnbecomeCamera).
    var isWatchRemoteMode = false

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
    let videoCropContext = CIContext(options: [.useSoftwareRenderer: false])
    /// Dedicated context for the tiny Apple Watch preview, kept off the recording
    /// crop context to avoid cross-queue contention.
    private let watchPreviewContext = CIContext(options: [.useSoftwareRenderer: false])
    /// Streams preview frames to the Apple Watch with ack back-pressure and lazy encoding.
    /// Runs on `videoDataOutputQueue`, where the capture callback hands it sample buffers.
    private lazy var watchPreviewStreamer = WatchPreviewStreamer(queue: videoDataOutputQueue)
    var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    var cachedVideoCropRect: CGRect? // Computed once at recording start, reused per frame
    
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
        if !isWatchRemoteMode {
            session ! UICmd.BecomeCamera(sender: nil, ctrl: self)
        }
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

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "questionmark.circle"),
            style: .plain,
            target: self,
            action: #selector(showHelpModal)
        )

        orientation = getOrientation()
    }

    @objc private func showHelpModal() {
        let helpView = RemoteShutterHelpView(onDismiss: { [weak self] in
            self?.dismiss(animated: true)
        })
        let hostingController = UIHostingController(rootView: helpView)
        hostingController.modalPresentationStyle = .pageSheet
        if let sheet = hostingController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        present(hostingController, animated: true)
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
            if !isWatchRemoteMode {
                session ! UICmd.UnbecomeCamera(sender: nil)
            }
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

    /// Turns the torch off for good (screen teardown). Clears the user's intent so the
    /// torch doesn't silently come back when the camera is next configured.
    func ensureTorchOff() {
        desiredTorchOn = false
        countdownTorch.stop(device: videoDeviceInput?.device)
        applyDesiredTorch()
    }

    /// Called at the end/cancel of a self-timer countdown: stops the strobe and returns
    /// the torch to whatever the user actually wanted, instead of forcing it off. Keeps
    /// the Watch in sync since the phone changed torch state on its own.
    func restoreTorchAfterCountdown() {
        countdownTorch.stop(device: videoDeviceInput?.device)
        applyDesiredTorch()
        syncTorchToWatch()
    }

    /// The single source of truth for whether the user wants the torch on. Set only by the
    /// user-facing torch controls (`toggleTorch` / `setTorchMode`); the countdown strobe
    /// drives the hardware directly and never touches this, so it survives a countdown.
    private(set) var desiredTorchOn = false

    /// Applies `desiredTorchOn` to the hardware. Reused to restore the torch after any
    /// event that resets it (rotation, session reconfiguration, timer countdown).
    func applyDesiredTorch() {
        guard let device = videoDeviceInput?.device, device.hasTorch else { return }
        let mode: AVCaptureDevice.TorchMode = desiredTorchOn ? .on : .off
        guard device.torchMode != mode else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = mode
            device.unlockForConfiguration()
        } catch {}
    }

    /// Pushes a fresh state snapshot to the Watch after the phone changes torch on its own
    /// (rotation, timer), so the Watch's torch indicator never goes stale. No-op outside
    /// Watch Remote mode.
    func syncTorchToWatch() {
        guard isWatchRemoteMode else { return }
        WatchSessionManager.shared.cameraController?.pushCurrentState()
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

    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        // iOS can drop the torch when the capture pipeline reconfigures during rotation.
        // `viewWillTransition` fires reliably on modern iOS (unlike the deprecated
        // `willAnimateRotation`), so restore the user's torch intent once the rotation
        // settles and re-sync the Watch, which would otherwise keep a stale torch state.
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.applyDesiredTorch()
            self?.syncTorchToWatch()
        }
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

        guard let videoDevice = preferredCamera(for: .back) ?? AVCaptureDevice.default(for: AVMediaType.video) else {
            return
        }
        debugLog("🔍 SETUP CAMERA: using device=\(videoDevice.localizedName) type=\(videoDevice.deviceType.rawValue) isVirtual=\(!videoDevice.virtualDeviceSwitchOverVideoZoomFactors.isEmpty)")

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
            self.applyDesiredTorch()   // commitConfiguration can reset the torch
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
                self.applyDesiredTorch()   // restore torch onto the new camera (no-op if it has none)

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
                desiredTorchOn = newTorchMode == .on
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
                desiredTorchOn = mode == .on
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

    /// Returns the best camera device for the given position, preferring virtual devices.
    /// Virtual devices automatically switch between physical cameras at appropriate zoom factors.
    func preferredCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if let triple = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: position) {
            return triple
        }
        if let dualWide = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: position) {
            return dualWide
        }
        if let dual = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: position) {
            return dual
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
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
        debugLog("🔍 ZOOM STOPS: device=\(device.localizedName) switchOverFactors=\(switchOverFactors) minZoom=\(device.minAvailableVideoZoomFactor) maxZoom=\(device.maxAvailableVideoZoomFactor)")

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
        debugLog("🔍 ZOOM STOPS: final=\(result)")
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
        return preferredCamera(for: position)
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
        debugLog("🔍 DEBUG: gatherAllCameraCapabilities called")
        
        // Gather front camera capabilities
        frontCameraInfo = gatherCameraInfo(for: .front)
        debugLog("🔍 DEBUG: Front camera info: \(frontCameraInfo != nil ? "available" : "nil")")
        
        // Gather back camera capabilities  
        backCameraInfo = gatherCameraInfo(for: .back)
        debugLog("🔍 DEBUG: Back camera info: \(backCameraInfo != nil ? "available" : "nil")")
        
        if let backInfo = backCameraInfo {
            debugLog("🔍 DEBUG: - Back camera available lenses: \(backInfo.availableLenses)")
            debugLog("🔍 DEBUG: - Back camera has flash: \(backInfo.hasFlash)")
        }
        
        if let frontInfo = frontCameraInfo {
            debugLog("🔍 DEBUG: - Front camera available lenses: \(frontInfo.availableLenses)")
            debugLog("🔍 DEBUG: - Front camera has flash: \(frontInfo.hasFlash)")
        }
    }
    
    func gatherCameraInfo(for position: AVCaptureDevice.Position) -> RemoteCmd.CameraInfo? {
        let positionName = position == .front ? "Front" : "Back"
        debugLog("🔍 DEBUG: gatherCameraInfo for \(positionName) camera")
        
        let deviceTypes = getAllDeviceTypes()
        let videoDevices = AVCaptureDevice.DiscoverySession.init(
                deviceTypes: deviceTypes,
                mediaType: .video, position: position).devices
        
        debugLog("🔍 DEBUG: - Found \(videoDevices.count) devices for \(positionName) position")
        for device in videoDevices {
            debugLog("🔍 DEBUG: - \(device.localizedName) (\(device.deviceType.rawValue))")
        }
        
        guard !videoDevices.isEmpty else { 
            debugLog("🔍 DEBUG: - No devices found for \(positionName) position")
            return nil 
        }
        
        // Find available lens types for this position
        let availableLenses = CameraLensType.allCases.filter { lensType in
            return videoDevices.contains { $0.deviceType == lensType.deviceType }
        }
        
        debugLog("🔍 DEBUG: - Final available lenses: \(availableLenses.map { $0.displayName })")
        
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

        // Discover zoom stops from the preferred (virtual) device
        let preferredDevice = preferredCamera(for: position)
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
        debugLog("🔍 DEBUG: gatherCurrentCameraCapabilities called")
        
        guard let currentDevice = self.videoDeviceInput?.device else { 
            debugLog("❌ DEBUG: No videoDeviceInput.device available")
            debugLog("❌ DEBUG: videoDeviceInput is \(self.videoDeviceInput != nil ? "not nil" : "nil")")
            return nil 
        }
        
        debugLog("🔍 DEBUG: Current device: \(currentDevice.localizedName)")
        debugLog("🔍 DEBUG: frontCameraInfo: \(frontCameraInfo != nil ? "available" : "nil")")
        debugLog("🔍 DEBUG: backCameraInfo: \(backCameraInfo != nil ? "available" : "nil")")
        
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

        debugLog("🔍 DEBUG: Created capabilities response successfully")
        return capabilities
    }
    
    // MARK: - Enhanced Zoom Control Methods
    func setZoom(zoomFactor: CGFloat) -> Try<(CGFloat, CameraLensType, RemoteCmd.ZoomRange)> {
        debugLog("🔍 DEBUG: setZoom called with factor: \(zoomFactor)")
        
        guard let device = self.videoDeviceInput?.device else {
            debugLog("❌ DEBUG: No camera device available")
            return Failure(error: NSError(domain: "No camera device available", code: 0, userInfo: nil))
        }
        
        debugLog("🔍 DEBUG: Current device: \(device.localizedName), position: \(device.position.rawValue)")
        debugLog("🔍 DEBUG: Zoom range: \(device.minAvailableVideoZoomFactor) - \(device.maxAvailableVideoZoomFactor)")
        debugLog("🔍 DEBUG: Current zoom: \(device.videoZoomFactor)")
        
        do {
            try device.lockForConfiguration()
            
            let clampedZoom = max(device.minAvailableVideoZoomFactor, 
                                 min(zoomFactor, device.maxAvailableVideoZoomFactor))
            
            debugLog("🔍 DEBUG: Setting zoom from \(device.videoZoomFactor) to \(clampedZoom)")
            device.videoZoomFactor = clampedZoom
            currentZoomFactor = clampedZoom

            // Update currentLensType based on which lens the virtual device is using
            currentLensType = lensTypeForZoomFactor(clampedZoom, device: device)

            device.unlockForConfiguration()

            debugLog("✅ DEBUG: Zoom set successfully to \(device.videoZoomFactor), lens: \(currentLensType.displayName)")

            let zoomRange = RemoteCmd.ZoomRange(
                minZoom: device.minAvailableVideoZoomFactor,
                maxZoom: device.maxAvailableVideoZoomFactor
            )

            return Success((clampedZoom, currentLensType, zoomRange))
        } catch let error as NSError {
            debugLog("❌ DEBUG: Error setting zoom: \(error.localizedDescription)")
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
    
    func getAvailableLensTypes() -> [CameraLensType] {
        return availableLensTypes
    }
    
    func getCurrentLensType() -> CameraLensType {
        return currentLensType
    }

    func getZoomStops() -> [CGFloat] {
        return zoomStops
    }

    func getWideAngleZoomFactor() -> CGFloat {
        guard let device = videoDeviceInput?.device else { return 1.0 }
        return wideAngleZoomFactor(for: device)
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

        // Restore zoom factor — changing activeFormat/sessionPreset resets it to 1.0
        let savedZoom = currentZoomFactor
        do {
            try device.lockForConfiguration()
            let clampedZoom = max(device.minAvailableVideoZoomFactor,
                                 min(savedZoom, device.maxAvailableVideoZoomFactor))
            device.videoZoomFactor = clampedZoom
            currentZoomFactor = clampedZoom
            device.unlockForConfiguration()
        } catch {
            debugLog("❌ DEBUG: Failed to restore zoom after quality change: \(error)")
        }

        applyDesiredTorch()   // changing activeFormat/preset also resets the torch

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

    /// Computes a centered crop rect for the given aspect ratio within source dimensions.
    /// Returns nil if the source already matches the target ratio.
    static func cropRect(sourceWidth: CGFloat, sourceHeight: CGFloat, aspectRatio: AspectRatio) -> CGRect? {
        let isLandscape = sourceWidth > sourceHeight
        let targetRatio = isLandscape ? aspectRatio.widthToHeight : (1.0 / aspectRatio.widthToHeight)
        let currentRatio = sourceWidth / sourceHeight

        if abs(currentRatio - targetRatio) < 0.01 {
            return nil // Already matches
        } else if currentRatio > targetRatio {
            let newWidth = sourceHeight * targetRatio
            return CGRect(x: (sourceWidth - newWidth) / 2, y: 0, width: newWidth, height: sourceHeight)
        } else {
            let newHeight = sourceWidth / targetRatio
            return CGRect(x: 0, y: (sourceHeight - newHeight) / 2, width: sourceWidth, height: newHeight)
        }
    }

    /// Crops photo data to the selected aspect ratio.
    func cropPhotoData(_ data: Data, to aspectRatio: AspectRatio) -> Data? {
        guard let image = UIImage(data: data),
              let cgImage = image.cgImage else {
            debugLog("cropPhotoData: failed to create UIImage/CGImage from data (\(data.count) bytes)")
            return nil
        }

        guard let rect = Self.cropRect(
            sourceWidth: CGFloat(cgImage.width),
            sourceHeight: CGFloat(cgImage.height),
            aspectRatio: aspectRatio
        ) else { return data }

        guard let croppedCG = cgImage.cropping(to: rect) else {
            debugLog("cropPhotoData: cgImage.cropping failed for rect \(rect)")
            return nil
        }
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

                // Restore the user's torch preference — iOS resets the torch on commitConfiguration.
                self.applyDesiredTorch()
                
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
                self?.assetWriter = nil
                self?.pixelBufferAdaptor = nil
                self?.cachedVideoCropRect = nil
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

        // Watch Remote mode has no MultipeerConnectivity peer — the iPhone is the camera
        // and the only consumer is the Apple Watch. The streamer applies ack back-pressure
        // and only invokes the encode when it's actually ready to send.
        if isWatchRemoteMode {
            watchPreviewStreamer.offer { [weak self] in self?.watchPreviewJPEG(from: sampleBuffer) }
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

    /// Builds a compact JPEG of the current frame for the Apple Watch live preview:
    /// long edge ~320 px (matching the Watch screen width) at quality 0.55, ~10-20 KB
    /// per frame. The sample buffer is already oriented by
    /// `videoConnection.videoOrientation`, so it renders upright.
    private func watchPreviewJPEG(from sampleBuffer: CMSampleBuffer) -> Data? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let longEdge = max(ciImage.extent.width, ciImage.extent.height)
        guard longEdge > 0 else { return nil }
        let scale = min(1.0, 320.0 / longEdge)
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = watchPreviewContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.55)
    }

    /// The Watch acked the in-flight preview frame — let the streamer send the next.
    func acknowledgeWatchPreview() {
        watchPreviewStreamer.acknowledge()
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
        var videoSettings = self.videoDataOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov)
        videoSettings?[AVVideoCodecKey] = AVVideoCodecType.hevc

        let dims = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let sourceWidth = CGFloat(dims.width)
        let sourceHeight = CGFloat(dims.height)

        // Compute and cache the crop rect once — reused for every frame
        let needsCrop = currentAspectRatio != .sixteenNine
        if needsCrop, let rawRect = Self.cropRect(sourceWidth: sourceWidth, sourceHeight: sourceHeight, aspectRatio: currentAspectRatio) {
            // Round to even for codec compatibility
            let evenRect = CGRect(
                x: floor(rawRect.origin.x / 2) * 2,
                y: floor(rawRect.origin.y / 2) * 2,
                width: floor(rawRect.width / 2) * 2,
                height: floor(rawRect.height / 2) * 2
            )
            cachedVideoCropRect = evenRect

            if var settings = videoSettings {
                settings[AVVideoWidthKey] = Int(evenRect.width)
                settings[AVVideoHeightKey] = Int(evenRect.height)
                videoSettings = settings
            }
        } else {
            cachedVideoCropRect = nil
        }

        if assetWriter.canApply(outputSettings: videoSettings, forMediaType: .video) {
            videoInput = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true

            if cachedVideoCropRect != nil {
                // Pool attributes match output dimensions — avoids per-frame CVPixelBufferCreate
                let poolAttrs: [String: Any] = [
                    kCVPixelBufferWidthKey as String: Int(cachedVideoCropRect!.width),
                    kCVPixelBufferHeightKey as String: Int(cachedVideoCropRect!.height),
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                ]
                pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: videoInput,
                    sourcePixelBufferAttributes: poolAttrs)
            } else {
                pixelBufferAdaptor = nil
            }

            if assetWriter.canAdd(videoInput) {
                assetWriter.add(videoInput)
            } else {
                return false
            }
        } else {
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

            if mediaType == .video, let adaptor = self.pixelBufferAdaptor,
               self.currentAspectRatio != .sixteenNine {
                // Crop video frame for non-16:9 aspect ratios
                if self.videoInput.isReadyForMoreMediaData,
                   let croppedBuffer = self.cropSampleBuffer(sampleBuffer) {
                    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    adaptor.append(croppedBuffer, withPresentationTime: pts)
                }
            } else if let input = (mediaType == .video) ? self.videoInput : self.audioInput {
                if input.isReadyForMoreMediaData {
                    input.append(sampleBuffer)
                }
            }
        }
    }

    /// Crops a video frame using the cached crop rect and the adaptor's pixel buffer pool.
    /// Called on every video frame during recording — must be fast.
    private func cropSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> CVPixelBuffer? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        // No crop needed — pass through the original buffer
        guard let cropRect = cachedVideoCropRect,
              let pool = pixelBufferAdaptor?.pixelBufferPool else {
            return pixelBuffer
        }

        // Get a buffer from the pool (reuses memory, no per-frame allocation)
        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
        guard status == kCVReturnSuccess, let output = outputBuffer else { return nil }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))
        videoCropContext.render(ciImage, to: output)
        return output
    }
}
