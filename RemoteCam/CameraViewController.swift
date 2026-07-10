//
//  CameraViewController.swift
//  RemoteShutter
//
//  Created by Dario on 10/7/15.
//  Copyright © 2020 Security Union LLC. All rights reserved.
//

import UIKit
import AVFoundation
import StoreKit
import SwiftUI

/**
Default fps, it would be neat if we would adjust this based on network conditions.
*/

var fps = 30


/**
  Camera UI
*/
public class CameraViewController: UIViewController {

    private enum AssociatedKeys {
        nonisolated(unsafe) static var microphonePromptController: UInt8 = 0
    }

    /// Owns the capture session, still-photo capture and all camera configuration.
    /// This VC keeps the preview layer and the UI/lifecycle glue.
    let engine = CaptureEngine()

    /// Owns the asset writer, recording state machine and per-frame writing.
    lazy var pipeline = RecordingPipeline(engine: engine)

    /// The capture session's sample-buffer delegate: routes frames to the
    /// preview streamers and, while recording, to the pipeline. The providers
    /// read UI state owned here; the sink captures the actor ref, not the VC.
    lazy var streamingCoordinator = FrameStreamingCoordinator(
        engine: engine,
        pipeline: pipeline,
        orientationProvider: { [weak self] in self?.orientation ?? .portrait },
        isWatchRemoteMode: { [weak self] in self?.isWatchRemoteMode ?? false },
        frameSink: { [frameSender] frame in frameSender ! frame })

    var isRecording: Bool { pipeline.isRecording }

    var captureVideoPreviewLayer: AVCaptureVideoPreviewLayer?
    /// Orientation used for the preview layer and the frame streamer. The engine
    /// keeps its own copy for the output/photo connections (kept in sync here).
    var orientation: UIInterfaceOrientation = UIInterfaceOrientation.portrait
    let session: ActorRef = getRemoteCamSession()!
    let frameSender: ActorRef = getFrameSender()!

    /// When true, this camera is controlled by an Apple Watch via WCSession.
    /// Suppresses MultipeerConnectivity-related actor messages (BecomeCamera/UnbecomeCamera).
    var isWatchRemoteMode = false

    // MARK: - Recording Timer Properties
    private var recordingStartTime: Date?
    private var recordingTimerController: CameraRecordingTimerViewController?
    
    // MARK: - Video Transfer Progress Properties
    let cameraViewModel = CameraViewModel()
    private var progressOverlayController: UIHostingController<CameraProgressOverlayView>?

    // MARK: - Sound Manager for Countdown Chimes
    let cameraSoundManager = SoundManager()

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
        wireEngineCallbacks()
        if !isWatchRemoteMode {
            session ! UICmd.BecomeCamera(sender: nil, ctrl: self)
        }
        configureIdleMode()
        setupRecordingTimerOverlay()
        setupProgressOverlay()
    }

    /// Bridges the non-UI engine back to the actor system and the status overlay.
    private func wireEngineCallbacks() {
        // Captures the session ref (not self) so an in-flight capture still
        // reaches the actor if the VC deallocates before the delegate fires.
        engine.onPicture = { [session] pic, error in
            if let error {
                session ! UICmd.OnPicture(sender: nil, error: error)
            } else if let pic {
                session ! UICmd.OnPicture(sender: nil, pic: pic)
            }
        }
        engine.onStatusChanged = { [weak self] in
            self?.updateCameraStatus()
        }
        // Captures the session ref (not self) so recording acks/responses still
        // reach the actor if the VC deallocates mid-recording.
        pipeline.sendMessage = { [session] msg in
            session ! msg
        }
        pipeline.onRecordingStarted = { [weak self] startTime in
            self?.recordingStartTime = startTime
            self?.updateRecordingTimerDisplay()
        }
        pipeline.onRecordingStopped = { [weak self] in
            self?.recordingStartTime = nil
            self?.updateRecordingTimerDisplay()
        }
        pipeline.onModeChanged = { [weak self] idle in
            if idle {
                self?.configureIdleMode()
            } else {
                self?.configureVideoModeRecording()
            }
        }
        pipeline.onError = { message in
            showError(message)
        }
        pipeline.onPhotosAccessDenied = { [weak self] in
            self?.showPhotosAccessDeniedModal(for: .video)
        }
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
            if engine.captureSession.isRunning {
                engine.cameraConfigQueue.async { [weak self] in
                    self?.engine.captureSession.stopRunning()
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
            resolution: engine.currentVideoResolution,
            frameRate: engine.currentVideoFrameRate,
            photoFormat: engine.currentPhotoFormat,
            hdrMode: engine.currentHDRMode)
    }

    func playCountdownChime(remaining: Int) {
        if remaining == 2 {
            cameraSoundManager.playBeepSound(.fast)
            countdownTorch.startStrobe(device: engine.videoDeviceInput?.device)
        } else if remaining > 2 {
            cameraSoundManager.playBeepSound(.slow)
            countdownTorch.blinkOnce(device: engine.videoDeviceInput?.device)
        }
    }

    /// Turns the torch off for good (screen teardown). Clears the user's intent so the
    /// torch doesn't silently come back when the camera is next configured.
    func ensureTorchOff() {
        engine.clearTorchIntent()
        countdownTorch.stop(device: engine.videoDeviceInput?.device)
        engine.applyDesiredTorch()
    }

    /// Called at the end/cancel of a self-timer countdown: stops the strobe and returns
    /// the torch to whatever the user actually wanted, instead of forcing it off. Keeps
    /// the Watch in sync since the phone changed torch state on its own.
    func restoreTorchAfterCountdown() {
        countdownTorch.stop(device: engine.videoDeviceInput?.device)
        engine.applyDesiredTorch()
        syncTorchToWatch()
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

    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            // Mid-transition the window scene already reports the TARGET
            // orientation (getOrientation()'s foreground-scene lookup would still
            // return the old one if read before the animation block).
            let newOrientation = self.view.window?.windowScene?.interfaceOrientation ?? getOrientation()
            self.orientation = newOrientation
            self.rotateCameraToOrientation(orientation: newOrientation)
        }, completion: { [weak self] _ in
            // iOS can drop the torch when the capture pipeline reconfigures during
            // rotation, so restore the user's torch intent once the rotation
            // settles and re-sync the Watch, which would otherwise keep a stale
            // torch state.
            self?.engine.applyDesiredTorch()
            self?.syncTorchToWatch()
        })
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The preview is a bare CALayer — it does not track the view through
        // rotation or layout changes, so keep it glued to the current bounds.
        captureVideoPreviewLayer?.frame = view.bounds
    }

    func setupCamera() {
        // The engine configures and starts the session; the preview layer and its
        // orientation stay here because the engine must not touch views/layers.
        guard engine.setupCamera(sampleBufferDelegate: streamingCoordinator) else { return }

        self.captureVideoPreviewLayer = AVCaptureVideoPreviewLayer(session: engine.captureSession)
        self.captureVideoPreviewLayer!.videoGravity = AVLayerVideoGravity.resizeAspect
        DispatchQueue.main.async {
            self.captureVideoPreviewLayer!.frame = self.view.frame
            self.view.layer.insertSublayer(self.captureVideoPreviewLayer!, below: self.recordingView.layer)
        }
        DispatchQueue.main.async {
            self.rotateCameraToOrientation(orientation: self.orientation)
        }
    }

    /// Rotates the preview-layer connection and delegates the output/photo
    /// connections to the engine (which caches the orientation for still capture).
    func rotateCameraToOrientation(orientation: UIInterfaceOrientation) {
        let o = OrientationUtils.transform(o: orientation)
        if let preview = self.captureVideoPreviewLayer {
            preview.connection?.videoOrientation = o
            let hadPhotoConnection = engine.rotateOutputs(orientation: orientation)
            if hadPhotoConnection {
                DispatchQueue.main.async {
                    preview.frame = self.view.bounds
                }
            }
        }
    }

    // MARK: - CaptureEngine forwarding
    //
    // The session's camera states drive the camera through `CameraControlling`;
    // these thin wrappers route those calls to the engine, which owns the capture
    // session and all still-photo / configuration concerns.

    func toggleCamera() -> Try<(AVCaptureDevice.FlashMode?, AVCaptureDevice.Position)> {
        engine.orientation = orientation
        let result = engine.toggleCamera()
        // Rotate the preview layer to match the newly rotated output connections.
        rotateCameraToOrientation(orientation: orientation)
        return result
    }

    func toggleFlash() -> Try<AVCaptureDevice.FlashMode> {
        engine.toggleFlash()
    }

    func toggleTorch() -> Try<AVCaptureDevice.TorchMode> {
        engine.toggleTorch()
    }

    func setTorchMode(mode: AVCaptureDevice.TorchMode) -> Try<AVCaptureDevice.TorchMode> {
        engine.setTorchMode(mode: mode)
    }

    func setZoom(zoomFactor: CGFloat) -> Try<(CGFloat, CameraLensType, RemoteCmd.ZoomRange)> {
        engine.setZoom(zoomFactor: zoomFactor)
    }

    func switchLens(to lensType: CameraLensType) -> Try<(CameraLensType, [CameraLensType], CGFloat, RemoteCmd.ZoomRange)> {
        engine.switchLens(to: lensType)
    }

    func setVideoQuality(resolution: VideoResolution, frameRate: VideoFrameRate) -> (VideoResolution, VideoFrameRate)? {
        engine.setVideoQuality(resolution: resolution, frameRate: frameRate, isRecording: isRecording)
    }

    func setPhotoQuality(format: PhotoFormat, hdrMode: HDRMode) -> (PhotoFormat, HDRMode)? {
        engine.setPhotoQuality(format: format, hdrMode: hdrMode)
    }

    func setAspectRatio(_ ratio: AspectRatio) -> AspectRatio {
        engine.setAspectRatio(ratio)
    }

    func gatherAllCameraCapabilities() {
        engine.gatherAllCameraCapabilities()
    }

    func gatherCurrentCameraCapabilities() -> RemoteCmd.CameraCapabilitiesResp? {
        engine.gatherCurrentCameraCapabilities()
    }

    func takePicture(_ sendMediaToRemote: Bool) {
        engine.takePicture(sendMediaToRemote)
    }

    func getCurrentZoomFactor() -> CGFloat { engine.getCurrentZoomFactor() }
    func getMaxZoomFactor() -> CGFloat { engine.getMaxZoomFactor() }
    func getMinZoomFactor() -> CGFloat { engine.getMinZoomFactor() }
    func getAvailableLensTypes() -> [CameraLensType] { engine.getAvailableLensTypes() }
    func getCurrentLensType() -> CameraLensType { engine.getCurrentLensType() }
    func getZoomStops() -> [CGFloat] { engine.getZoomStops() }
    func getWideAngleZoomFactor() -> CGFloat { engine.getWideAngleZoomFactor() }
}

extension CameraViewController {

    func startRecordingVideo() {
        // Check microphone permission before starting video recording
        PermissionManager.shared.requestMicrophonePermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if granted {
                    self.pipeline.startRecording(audioSampleBufferDelegate: self.streamingCoordinator)
                } else {
                    // Microphone denied - show prompt and send error to remote
                    self.handleMicrophoneDenied()
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
    
    func stopRecordingVideo(_ shouldSendVideo: Bool) {
        pipeline.stopRecording(shouldSendVideo)
    }
}

extension CameraViewController {
    /// The Watch acked the in-flight preview frame — let the streamer send the next.
    func acknowledgeWatchPreview() {
        streamingCoordinator.acknowledgeWatchPreview()
    }
}
