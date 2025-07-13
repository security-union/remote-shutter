//
//  RemoteViewController.swift
//  Actors
//
//  Created by Dario on 10/7/15.
//  Copyright © 2015 dario. All rights reserved.
//

import UIKit
import Theater
import AVFoundation

let timerDefault = "timerDefault"

func setFlashMode(ctrl: Weak<MonitorViewController>, flashMode: AVCaptureDevice.FlashMode?) {
    if let f = flashMode {
        switch f {
        case .off:
            ctrl.value?.flashStatus.text = "Off"
        case .on:
            ctrl.value?.flashStatus.text = "On"
        case .auto:
            ctrl.value?.flashStatus.text = "Auto"
        default:
            ctrl.value?.flashStatus.text = "None"
        }
    } else {
        ctrl.value?.flashStatus.text = "None"
    }
}

// MARK: - Generic Camera Configuration Refresh
func refreshCameraConfiguration(ctrl: Weak<MonitorViewController>, capabilities: RemoteShutter_CameraCapabilities?, currentState: RemoteShutter_CameraState?) {
    guard let ctrl = ctrl.value else { return }
    
    // Determine which camera info to use based on current camera position
    let cameraPosition = currentState?.currentCamera ?? .back
    let cameraInfo: RemoteShutter_CameraInfo?
    
    switch cameraPosition {
    case .front:
        cameraInfo = capabilities?.frontCamera
    case .back:
        cameraInfo = capabilities?.backCamera
    }
    
    // Update flash and torch button visibility based on camera capabilities
    print("updating camera controls for \(cameraPosition)")
    if let cameraInfo = cameraInfo {
        print("has torch \(cameraInfo.hasTorch)")
        ctrl.flashButton.isHidden = !cameraInfo.hasFlash
        ctrl.programmaticTorchButton.isHidden = !cameraInfo.hasTorch
    } else {
        // If no camera info available, hide both buttons
        print( "No camera info available")
        ctrl.flashButton.isHidden = true
        ctrl.programmaticTorchButton.isHidden = true
    }
    
    // Update lens controls if we have available lenses
    if let cameraInfo = cameraInfo, cameraInfo.hasAvailableLenses {
        let availableLenses = Array(0..<cameraInfo.availableLensesCount).compactMap { index in
            cameraInfo.availableLenses(at: index)
        }
        
        // Convert FlatBuffers lens types to CameraLensType
        let lensTypes: [CameraLensType] = availableLenses.compactMap { lensType in
            switch lensType {
            case .ultrawide: return .ultraWide
            case .wideangle: return .wideAngle
            case .telephoto: return .telephoto
            case .dualcamera: return .dualCamera
            }
        }
        
        let currentLensType: CameraLensType
        if let currentLens = currentState?.currentLens {
            switch currentLens {
            case .ultrawide: currentLensType = .ultraWide
            case .wideangle: currentLensType = .wideAngle
            case .telephoto: currentLensType = .telephoto
            case .dualcamera: currentLensType = .dualCamera
            }
        } else {
            currentLensType = .wideAngle // Default
        }
        
        ctrl.updateLensControls(lensType: currentLensType, availableLenses: lensTypes)
    }
    
    // Update zoom controls if we have zoom capabilities
    if let cameraInfo = cameraInfo, cameraInfo.hasZoomCapabilities {
        let currentLens = currentState?.currentLens ?? .wideangle
        let currentZoom = currentState?.zoomFactor ?? 1.0
        
        // Find zoom capability for current lens
        for i in 0..<cameraInfo.zoomCapabilitiesCount {
            if let zoomCapability = cameraInfo.zoomCapabilities(at: i),
               zoomCapability.lensType == currentLens,
               let zoomRange = zoomCapability.zoomRange {
                ctrl.updateZoomControls(zoomFactor: CGFloat(currentZoom), maxZoom: CGFloat(zoomRange.maxZoom))
                break
            }
        }
    }
}

func setTorchMode(ctrl: Weak<MonitorViewController>, torchMode: AVCaptureDevice.TorchMode?) {
    if let t = torchMode {
        switch t {
        case .off:
            if let torchOffImage = UIImage(named: "torch_off")?.preparingThumbnail(of: CGSize(width: 35, height: 35))?.withRenderingMode(.alwaysTemplate)  {
                ctrl.value?.programmaticTorchButton?.setImage(torchOffImage, for: .normal)
                ctrl.value?.programmaticTorchButton?.tintColor = UIColor(red: 78/255, green: 168/255, blue: 201/255, alpha: 1);
                ctrl.value?.programmaticTorchButton?.backgroundColor = UIColor.black.withAlphaComponent(0.6)
            }
        case .on:
            if let torchOnImage = UIImage(named: "torch_on")?.preparingThumbnail(of: CGSize(width: 35, height: 35))?.withRenderingMode(.alwaysTemplate) {
                ctrl.value?.programmaticTorchButton?.setImage(torchOnImage, for: .normal)
                ctrl.value?.programmaticTorchButton?.tintColor = UIColor.white
                ctrl.value?.programmaticTorchButton?.backgroundColor = UIColor(red: 78/255, green: 168/255, blue: 201/255, alpha: 0.6);
            }
        case .auto:
            if let torchOffImage = UIImage(named: "torch_off")?.preparingThumbnail(of: CGSize(width: 35, height: 35))?.withRenderingMode(.alwaysTemplate)  {
                ctrl.value?.programmaticTorchButton?.setImage(torchOffImage, for: .normal)
                ctrl.value?.programmaticTorchButton?.tintColor = UIColor.orange
                ctrl.value?.programmaticTorchButton?.backgroundColor = UIColor.black.withAlphaComponent(0.6)
            }
        @unknown default:
            if let torchOffImage = UIImage(named: "torch_off")?.preparingThumbnail(of: CGSize(width: 35, height: 35))?.withRenderingMode(.alwaysTemplate) {
                ctrl.value?.programmaticTorchButton?.setImage(torchOffImage, for: .normal)
                ctrl.value?.programmaticTorchButton?.tintColor = UIColor.red
                ctrl.value?.programmaticTorchButton?.backgroundColor = UIColor.black.withAlphaComponent(0.6)
            }
        }
    } else {
        if let torchOffImage = UIImage(named: "torch_off")?.preparingThumbnail(of: CGSize(width: 35, height: 35))?.withRenderingMode(.alwaysTemplate)  {
            ctrl.value?.programmaticTorchButton?.setImage(torchOffImage, for: .normal)
            ctrl.value?.programmaticTorchButton?.tintColor = UIColor.white
        }
    }
}

/**
Monitor actor has a reference to the session actor and to the monitorViewController, it acts as the connection between the model and the controller from an MVC perspective.
*/

public class MonitorActor: ViewCtrlActor<MonitorViewController> {

    public required init(context: ActorSystem, ref: ActorRef) {
        super.init(context: context, ref: ref)
        mailbox = OperationQueue()
        let session: ActorRef? = RemoteCamSystem.shared.selectActor(actorPath: "RemoteCam/user/RemoteCam Session")
        session! ! UICmd.BecomeMonitor(ref, mode: .Photo)
    }

    override public func receiveWithCtrl(ctrl: Weak<MonitorViewController>) -> Receive {

        return { [unowned self](msg: Message) in
            switch msg {
                
            case is UICmd.RenderPhotoMode:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.configurePhotoMode()
                }

            case is UICmd.RenderVideoMode:
                print("🔍 DEBUG: MonitorActor received UICmd.RenderVideoMode")
                OperationQueue.main.addOperation {[weak ctrl] in
                    print("🔍 DEBUG: Executing configureVideoMode on main thread")
                    ctrl?.value?.configureVideoMode()
                }

            case is UICmd.RenderVideoModeRecording:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.configureVideoModeRecording()
                }

            case is UICmd.BecomeMonitorFailed:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.navigationController?.popViewController(animated: true)
                }

            case let fbResponse as FlatBuffersCameraStateResponse:
                // Handle FlatBuffers camera state response - update UI based on current state
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ctrl = ctrl {
                        // Extract torch mode from FlatBuffers response current state
                        let torchMode: AVCaptureDevice.TorchMode?
                        
                        if let state = fbResponse.response.currentState {
                            switch state.torchMode {
                            case .off: torchMode = .off
                            case .on: torchMode = .on
                            case .auto: torchMode = .auto
                            }
                        } else {
                            torchMode = nil
                        }
                        setTorchMode(ctrl: ctrl, torchMode: torchMode)
                        
                        // Extract flash mode from FlatBuffers response current state
                        let flashMode: AVCaptureDevice.FlashMode?
                        if let state = fbResponse.response.currentState {
                            switch state.flashMode {
                            case .off: flashMode = .off
                            case .on: flashMode = .on
                            case .auto: flashMode = .auto
                            }
                        } else {
                            flashMode = nil
                        }
                        setFlashMode(ctrl: ctrl, flashMode: flashMode)
                        
                        // Refresh camera configuration based on capabilities and current state
                        refreshCameraConfiguration(ctrl: ctrl, capabilities: fbResponse.response.capabilities, currentState: fbResponse.response.currentState)
                    }
                }

            case let fbFrameData as FlatBuffersFrameData:
                let imageData = Data(fbFrameData.frameData.imageData)
                if let cgImage = UIImage(data: imageData) {
                    OperationQueue.main.addOperation {[weak ctrl] in
                        if let ctrl = ctrl {
                            ctrl.value?.imageView.image = cgImage
                        } else {
                            print("🖼️ DEBUG: ctrl is nil, cannot update imageView")
                        }
                    }
                } else {
                    print("🖼️ DEBUG: Failed to create UIImage from frame data")
                }
                
            // MARK: - Camera Capabilities Response Handling
            case let capabilities as RemoteCmd.CameraCapabilitiesResp:
                break
                
                
            // MARK: - Lens Response Handling
            case let lens as UICmd.SwitchLensResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ctrl = ctrl, 
                       let lensType = lens.lensType,
                       let availableLenses = lens.availableLenses {
                        ctrl.value?.updateLensControls(lensType: lensType, availableLenses: availableLenses)
                        
                        // Update zoom controls if we have the new zoom info
                        if let currentZoom = lens.currentZoom,
                           let zoomRange = lens.zoomRange {
                            ctrl.value?.updateZoomControls(zoomFactor: currentZoom, maxZoom: zoomRange.maxZoom)
                        }
                    }
                }
                
            case let lensRemote as RemoteCmd.SwitchLensResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ctrl = ctrl,
                       let lensType = lensRemote.lensType,
                       let availableLenses = lensRemote.availableLenses {
                        ctrl.value?.updateLensControls(lensType: lensType, availableLenses: availableLenses)
                        
                        // Update zoom controls if we have the new zoom info
                        if let currentZoom = lensRemote.currentZoom,
                           let zoomRange = lensRemote.zoomRange {
                            ctrl.value?.updateZoomControls(zoomFactor: currentZoom, maxZoom: zoomRange.maxZoom)
                        }
                    }
                }
                
            default:
                self.receive(msg: msg)
            }
        }
    }
}

/**
UI for the monitor.
*/

public class MonitorViewController: iAdViewController, UIImagePickerControllerDelegate & UINavigationControllerDelegate {

    let session = getRemoteCamSession()!

    let monitor = RemoteCamSystem.shared.actorOf(clz: MonitorActor.self, name: "MonitorActor")!

    let timer: RCTimer = RCTimer()

    let soundManager: CPSoundManager = CPSoundManager()

    private let sliderColor1 = UIColor(red: 0.150, green: 0.670, blue: 0.80, alpha: 1)
    private let sliderColor2 = UIColor(red: 0.060, green: 0.100, blue: 0.160, alpha: 1)

    @IBOutlet weak var flashStatus: UILabel!

    @IBOutlet weak var imageView: UIImageView!

    @IBOutlet weak var takePicture: UIButton!

    @IBOutlet weak var sliderContainer: UIView!

    @IBOutlet weak var timerSlider: UISlider!

    @IBOutlet weak var timerLabel: UILabel!

    @IBOutlet weak var galleryButton: UIButton!

    @IBOutlet weak var backButton: UIButton!

    @IBOutlet weak var flashButton: UIButton!

    @IBOutlet weak var settingsButton: UIButton!

    @IBOutlet weak var toggleCamera: UIButton!
    
    @IBOutlet weak var controlsView: UIView!

    @IBOutlet weak var segmentedControl: UISegmentedControl!

    @IBOutlet weak var recordingView: UIImageView!
    
    // MARK: - Zoom and Lens Controls
    @IBOutlet weak var lensSegmentedControl: UISegmentedControl?
    
    // Programmatic UI Controls
    private var programmaticZoomSlider: UISlider!
    private var programmaticZoomLabel: UILabel!
    private var programmaticLensSegmentedControl: UISegmentedControl!
    private var zoomControlsContainer: UIView!
    private var lensControlsContainer: UIView!
    private var programmaticToggleCameraButton: UIButton!
    var programmaticTorchButton: UIButton!
    
    // Pinch Gesture for Zoom
    private var pinchGestureRecognizer: UIPinchGestureRecognizer!
    private var lastPinchScale: CGFloat = 1.0
    private var zoomLabelTimer: Timer?
    
    // MARK: - Zoom and Lens Properties
    private var currentZoomFactor: CGFloat = 1.0
    public var maxZoomFactor: CGFloat = 10.0
    private var availableLensTypes: [CameraLensType] = [.wideAngle]
    private var currentLensType: CameraLensType = .wideAngle

    var buttonPrompt: String = ""

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        print("🔍 DEBUG: MonitorViewController viewWillAppear - \(ObjectIdentifier(self))")
        self.navigationController?.isNavigationBarHidden = true
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        print("🔍 DEBUG: MonitorViewController viewDidLoad - \(ObjectIdentifier(self))")
        monitor ! SetViewCtrl(ctrl: self)
        self.configureTimerUI()
        self.setupProgrammaticZoomAndLensControls()
        self.setupProgrammaticTorchButton()
        self.configureZoomUI()
        self.configureLensUI()
        self.segmentedControl.addTarget(self,
                                        action: #selector(self.onSegmentedControlChanged(event:)),
                                        for: .valueChanged)
        self.takePicture.imageView?.contentMode = .scaleAspectFit
        self.flashButton.imageView?.contentMode = .scaleAspectFit
        self.imageView.contentMode = .scaleAspectFit
        recordingView.image = UIImage.gifImageWithName("recording")
        configurePhotoMode()
        
        // Request camera capabilities after MonitorActor is fully set up
        // This handles the race condition where capabilities arrive before viewDidLoad
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            print("🔍 DEBUG: Requesting camera capabilities after MonitorActor setup")
            if let session = self?.session {
                session ! UICmd.RequestCameraCapabilities()
            }
            
        }
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
    }

    deinit {
        print("🔍 DEBUG: MonitorViewController deinit - \(ObjectIdentifier(self))")
        print("stop monitor")
        self.timer.cancel()
        self.zoomLabelTimer?.invalidate()
        self.soundManager.stopPlayer()
        session ! UICmd.UnbecomeMonitor(sender: nil)
        
        // Delay actor destruction to allow pending messages to arrive
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [monitor] in
            monitor ! Actor.Harakiri(sender: nil)
        }
    }

    let buttonPromptPhotoMode = NSLocalizedString("Taking picture", comment: "")
    let buttonPromptVideoMode = NSLocalizedString("Starting video", comment: "")
    let buttonPromptRecordingMode = NSLocalizedString("Stopping video", comment: "")
    var timerSliderValue: Int {
        set {
            UserDefaults.standard.set(newValue, forKey: timerDefault)
            UserDefaults.standard.synchronize()
        }
        
        get {
            UserDefaults.standard.integer(forKey: timerDefault)
        }
    }

    func configurePhotoMode() {
        takePicture.setImage(UIImage.init(named: "camera.png"), for: .normal)
        galleryButton.isEnabled = true
        backButton.isEnabled = true
        flashButton.isEnabled = true
        flashButton.isHidden = false
        flashStatus.isHidden = false
        timerSlider.isEnabled = true
        settingsButton.isEnabled = true
        segmentedControl.isEnabled = true
        recordingView.isHidden = true
        toggleCamera.isEnabled = true
        toggleCamera.isHidden = false
        programmaticToggleCameraButton?.isEnabled = true
        programmaticToggleCameraButton?.isHidden = false
        lensSegmentedControl?.isEnabled = true
        // Enable programmatic controls
        programmaticZoomSlider.isEnabled = true
        programmaticLensSegmentedControl.isEnabled = true
        zoomControlsContainer.isHidden = true // Keep hidden - using pinch gesture
        lensControlsContainer.isHidden = false
        pinchGestureRecognizer.isEnabled = true
        buttonPrompt = buttonPromptPhotoMode
    }

    func configureVideoMode() {
        print("🔍 DEBUG: MonitorViewController configureVideoMode() called")
        takePicture.setImage(UIImage.init(named: "record-button.png"), for: .normal)
        galleryButton.isEnabled = true
        backButton.isEnabled = true
        flashButton.isEnabled = false
        flashButton.isHidden = true
        flashStatus.isHidden = true
        timerSlider.isEnabled = true
        settingsButton.isEnabled = true
        segmentedControl.isEnabled = true
        recordingView.isHidden = true
        toggleCamera.isEnabled = true
        toggleCamera.isHidden = false
        programmaticToggleCameraButton?.isEnabled = true
        programmaticToggleCameraButton?.isHidden = false
        lensSegmentedControl?.isEnabled = true
        // Enable programmatic controls
        programmaticZoomSlider.isEnabled = true
        programmaticLensSegmentedControl.isEnabled = true
        zoomControlsContainer.isHidden = true // Keep hidden - using pinch gesture
        lensControlsContainer.isHidden = false
        pinchGestureRecognizer.isEnabled = true
        buttonPrompt = buttonPromptVideoMode
        print("🔍 DEBUG: MonitorViewController configureVideoMode() completed")
    }

    func configureVideoModeRecording() {
        takePicture.setImage(UIImage.init(named: "stop-button.png"), for: .normal)
        galleryButton.isEnabled = false
        backButton.isEnabled = false
        flashButton.isEnabled = false
        flashButton.isHidden = true
        flashStatus.isHidden = true
        timerSlider.isEnabled = false
        settingsButton.isEnabled = false
        segmentedControl.isEnabled = false
        recordingView.isHidden = false
        toggleCamera.isEnabled = false
        toggleCamera.isHidden = true
        programmaticToggleCameraButton?.isEnabled = false
        programmaticToggleCameraButton?.isHidden = true
        lensSegmentedControl?.isEnabled = false
        // Disable programmatic controls
        programmaticZoomSlider.isEnabled = false
        programmaticLensSegmentedControl.isEnabled = false
        zoomControlsContainer.isHidden = true
        lensControlsContainer.isHidden = true
        pinchGestureRecognizer.isEnabled = false
        buttonPrompt = buttonPromptRecordingMode
    }

    @IBAction func onToggleCamera(sender: UIButton) {
        session ! UICmd.FlatBuffersCameraToggle()
    }

    @IBAction func onSliderChange(sender: UISlider) {
        timerSliderValue = Int(round(sender.value))
        self.timerLabel.text = "\(timerSliderValue)"
    }

    @IBAction func toggleFlash(sender: UIButton) {
        session ! UICmd.FlatBuffersFlashToggle()
    }
    
    @IBAction func toggleTorch(sender: UIButton) {
        if InAppPurchasesManager.shared().hasTorchFeature() {
            // Send FlatBuffers torch toggle command via existing UI command
            session ! UICmd.FlatBuffersTorchToggle()
        } else {
            showSettings(sender: settingsButton)
        }
    }
    
    @objc private func onZoomSliderChange(_ sender: UISlider) {
        currentZoomFactor = CGFloat(sender.value)
        updateZoomLabel()
        session ! UICmd.FlatBuffersSetZoom(zoomFactor: currentZoomFactor)
    }
    
    // MARK: - Lens Control Actions
    @IBAction func onLensSegmentedControlChanged(sender: UISegmentedControl) {
        let orderedAvailableLenses = getOrderedAvailableLenses()
        
        guard sender.selectedSegmentIndex < orderedAvailableLenses.count else { return }
        let selectedLensType = orderedAvailableLenses[sender.selectedSegmentIndex]
        currentLensType = selectedLensType
        session ! UICmd.SwitchLens(lensType: selectedLensType)
    }
    
    @objc func onProgrammaticLensSegmentedControlChanged(sender: UISegmentedControl) {
        let orderedAvailableLenses = getOrderedAvailableLenses()
        
        guard sender.selectedSegmentIndex < orderedAvailableLenses.count else { return }
        let selectedLensType = orderedAvailableLenses[sender.selectedSegmentIndex]
        currentLensType = selectedLensType
        session ! UICmd.SwitchLens(lensType: selectedLensType)
    }

    @IBAction func showSettings(sender: UIButton) {
        let ctrl = CMConfigurationsViewController()
        self.navigationController?.pushViewController(ctrl, animated: true)
    }

    @IBAction func showGallery(sender: UIButton) {
        let pickerController = UIImagePickerController()
        pickerController.delegate = self
        pickerController.allowsEditing = true
        pickerController.videoMaximumDuration = 60 * 60
        pickerController.mediaTypes = ["public.image", "public.movie"]
        pickerController.sourceType = .savedPhotosAlbum
        #if targetEnvironment(macCatalyst)
        pickerController.modalPresentationStyle = UIModalPresentationStyle.pageSheet
        #else
        pickerController.modalPresentationStyle = UIModalPresentationStyle.popover
        pickerController.popoverPresentationController?.sourceView = sender
        #endif
        self.present(pickerController, animated: true)
    }

    @IBAction func goBack(sender: UIButton) {
        self.navigationController?.popViewController(animated: true)
    }

    /**
     Take picture contains the logic to kick off the Timer for the picture.
    */

    @IBAction func onTakePicture(sender: UIBarButtonItem) {
        let sendMediaToRemote = CMConfigurationsViewController.sendMediaToRemote();
        if buttonPrompt == buttonPromptRecordingMode {
            self.session ! UICmd.TakePicture(sender: nil, sendMediaToRemote: sendMediaToRemote)
            return
        }

        func timerAlertTitle(seconds: Int) -> String {
            "\(buttonPrompt) in \(seconds) seconds"
        }

        let alert = UIAlertController(title: timerAlertTitle(seconds: timerSliderValue),
                message: nil,
                preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self](_) in
            alert.dismiss(animated: true, completion: nil)
            self?.timer.cancel()
        })

        self.soundManager.playBeepSound(CPSoundManagerAudioTypeSlow)

        self.present(alert, animated: true) { [weak self] in
            self?.timer.start(withDuration: Int(round(self?.timerSlider.value ?? 0)), withTickHandler: { [weak self](t) in
                alert.title = timerAlertTitle(seconds: t!.timeRemaining())
                switch t!.timeRemaining() {
                case let l where l > 3:
                    self?.soundManager.playBeepSound(CPSoundManagerAudioTypeSlow)
                case 3:
                    self?.soundManager.playBeepSound(CPSoundManagerAudioTypeFast)
                default:
                    break
                }
            },
            andCompletionHandler: { [weak self] (_) in
                alert.dismiss(animated: true, completion: nil)
                self?.session.tell(msg:UICmd.TakePicture(sender: nil, sendMediaToRemote: sendMediaToRemote))
            })
        }
    }

    private func configureTimerUI() {
        self.timerSlider.value = Float(timerSliderValue)
        self.timerLabel.text = "\(timerSliderValue)"
        self.sliderContainer.layer.cornerRadius = 30.0
        self.sliderContainer.clipsToBounds = true
        self.timerSlider.layer.anchorPoint = CGPoint.init(x: 1.0, y: 1.0)
        self.timerSlider.transform = CGAffineTransform(rotationAngle: CGFloat(-Double.pi / 2))
        self.timerSlider.minimumTrackTintColor = sliderColor1
        self.timerSlider.maximumTrackTintColor = sliderColor2
        self.timerSlider.thumbTintColor = sliderColor1
    }
    
    // MARK: - Programmatic UI Setup
    private func setupProgrammaticZoomAndLensControls() {
        // Setup zoom controls container
        zoomControlsContainer = UIView()
        zoomControlsContainer.backgroundColor = UIColor.clear
        zoomControlsContainer.translatesAutoresizingMaskIntoConstraints = false
        zoomControlsContainer.isHidden = true // Hide slider since we're using pinch gesture
        view.addSubview(zoomControlsContainer)
        
        // Setup zoom label - now positioned on main view since we're using pinch gesture
        programmaticZoomLabel = UILabel()
        programmaticZoomLabel.text = "1.0x"
        programmaticZoomLabel.textColor = .white
        programmaticZoomLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        programmaticZoomLabel.textAlignment = .center
        programmaticZoomLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        programmaticZoomLabel.layer.cornerRadius = 6
        programmaticZoomLabel.clipsToBounds = true
        programmaticZoomLabel.alpha = 0.3 // Start semi-transparent
        programmaticZoomLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(programmaticZoomLabel)
        
        // Setup zoom slider
        programmaticZoomSlider = UISlider()
        programmaticZoomSlider.minimumValue = 1.0
        programmaticZoomSlider.maximumValue = 10.0
        programmaticZoomSlider.value = 1.0
        programmaticZoomSlider.minimumTrackTintColor = sliderColor1
        programmaticZoomSlider.maximumTrackTintColor = sliderColor2
        programmaticZoomSlider.thumbTintColor = sliderColor1
        programmaticZoomSlider.addTarget(self, action: #selector(onZoomSliderChange), for: .valueChanged)
        programmaticZoomSlider.translatesAutoresizingMaskIntoConstraints = false
        zoomControlsContainer.addSubview(programmaticZoomSlider)
        
        // Setup lens controls container
        lensControlsContainer = UIView()
        lensControlsContainer.backgroundColor = UIColor.black.withAlphaComponent(0.0)
        lensControlsContainer.translatesAutoresizingMaskIntoConstraints = false
        controlsView.addSubview(lensControlsContainer)
        
        // Setup lens segmented control
        programmaticLensSegmentedControl = UISegmentedControl()
        programmaticLensSegmentedControl.backgroundColor = UIColor.clear
        programmaticLensSegmentedControl.selectedSegmentTintColor = sliderColor1
        programmaticLensSegmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        programmaticLensSegmentedControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        programmaticLensSegmentedControl.addTarget(self, action: #selector(onProgrammaticLensSegmentedControlChanged), for: .valueChanged)
        programmaticLensSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        lensControlsContainer.addSubview(programmaticLensSegmentedControl)
        
        // Setup constraints
        setupZoomAndLensConstraints()
        
        // Setup pinch gesture for zoom
        setupPinchGestureForZoom()
    }
    
    private func setupProgrammaticTorchButton() {
        // Create torch button
        programmaticTorchButton = UIButton(type: .custom)
        
        // Set initial image with template rendering mode
        if let torchOffImage = UIImage(named: "torch_off")?.preparingThumbnail(of: CGSize(width: 35, height: 35))?.withRenderingMode(.alwaysTemplate) {
            programmaticTorchButton.setImage(torchOffImage, for: .normal)
        }
        
        if #available(iOS 15.0, *) {
            var config = programmaticTorchButton.configuration ?? UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)

            programmaticTorchButton.configuration = config
            programmaticTorchButton.imageView?.contentMode = .scaleAspectFit
        } else {
            programmaticTorchButton.imageEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        }
        
        programmaticTorchButton.tintColor = UIColor(red: 78/255, green: 168/255, blue: 201/255, alpha: 1);
        programmaticTorchButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        programmaticTorchButton.layer.cornerRadius = 30
        programmaticTorchButton.clipsToBounds = true
        programmaticTorchButton.translatesAutoresizingMaskIntoConstraints = false
        programmaticTorchButton.addTarget(self, action: #selector(onProgrammaticTorchButtonTapped), for: .touchUpInside)
        view.addSubview(programmaticTorchButton)
        NSLayoutConstraint.activate([
            programmaticTorchButton.bottomAnchor.constraint(equalTo: settingsButton.topAnchor, constant: -20),
            programmaticTorchButton.centerXAnchor.constraint(equalTo: settingsButton.centerXAnchor),
            programmaticTorchButton.widthAnchor.constraint(equalToConstant: 60),
            programmaticTorchButton.heightAnchor.constraint(equalToConstant: 60)
        ])
    }
    
    
    @objc private func onProgrammaticTorchButtonTapped() {
        if InAppPurchasesManager.shared().hasTorchFeature() {
            session ! UICmd.FlatBuffersTorchToggle()
        } else {
            showSettings(sender: settingsButton)
        }
    }
    
    private func setupPinchGestureForZoom() {
        // Create pinch gesture recognizer
        pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(onPinchGesture(_:)))
        
        // Add to the image view (camera feed area)
        imageView.isUserInteractionEnabled = true
        imageView.addGestureRecognizer(pinchGestureRecognizer)
    }
    
    @objc private func onPinchGesture(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .changed {
            let scale = gesture.scale
            let scaleChange = scale / lastPinchScale
            lastPinchScale = scale
            
            let newZoom = currentZoomFactor * scaleChange
            let clampedZoom = max(1.0, min(newZoom, maxZoomFactor))
            
            if clampedZoom != currentZoomFactor {
                currentZoomFactor = clampedZoom
                programmaticZoomSlider.value = Float(currentZoomFactor)
                updateZoomLabel()
                session ! UICmd.FlatBuffersSetZoom(zoomFactor: currentZoomFactor)
            }
        } else if gesture.state == .ended || gesture.state == .cancelled {
            lastPinchScale = 1.0
            hideZoomLabelAfterDelay()
        }
    }
    
    private func showZoomLabel() {
        zoomLabelTimer?.invalidate()
        OperationQueue.main.addOperation { [weak self] in
            UIView.animate(withDuration: 0.2) {
                self?.programmaticZoomLabel.alpha = 1.0
            }
        }
    }
    
    private func hideZoomLabelAfterDelay() {
        zoomLabelTimer?.invalidate()
        zoomLabelTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            OperationQueue.main.addOperation {
                UIView.animate(withDuration: 0.3) {
                    self?.programmaticZoomLabel.alpha = 0.3
                }
            }
        }
    }
    
    private func setupZoomAndLensConstraints() {
        NSLayoutConstraint.activate([
            // Zoom controls container - positioned on the right side
            zoomControlsContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            zoomControlsContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 80),
            zoomControlsContainer.widthAnchor.constraint(equalToConstant: 120),
            zoomControlsContainer.heightAnchor.constraint(equalToConstant: 80),
            
            // Zoom label - positioned below the settings button
            programmaticZoomLabel.topAnchor.constraint(equalTo: settingsButton.bottomAnchor, constant: 20),
            programmaticZoomLabel.centerXAnchor.constraint(equalTo: settingsButton.centerXAnchor),
            programmaticZoomLabel.widthAnchor.constraint(equalToConstant: 60),
            programmaticZoomLabel.heightAnchor.constraint(equalToConstant: 30),
            
            // Zoom slider
            programmaticZoomSlider.topAnchor.constraint(equalTo: programmaticZoomLabel.bottomAnchor, constant: 8),
            programmaticZoomSlider.leadingAnchor.constraint(equalTo: zoomControlsContainer.leadingAnchor, constant: 8),
            programmaticZoomSlider.trailingAnchor.constraint(equalTo: zoomControlsContainer.trailingAnchor, constant: -8),
            programmaticZoomSlider.bottomAnchor.constraint(equalTo: zoomControlsContainer.bottomAnchor, constant: -8),
            
            // Lens controls container - positioned at the bottom of the controls view
            lensControlsContainer.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor, constant: 8),
            lensControlsContainer.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor, constant: -8),
            lensControlsContainer.topAnchor.constraint(equalTo: controlsView.topAnchor, constant: 8),
            lensControlsContainer.heightAnchor.constraint(equalToConstant: 40),
            
            // Lens segmented control - narrow and centered
            programmaticLensSegmentedControl.centerXAnchor.constraint(equalTo: lensControlsContainer.centerXAnchor),
            programmaticLensSegmentedControl.widthAnchor.constraint(equalToConstant: 180),
            programmaticLensSegmentedControl.topAnchor.constraint(equalTo: lensControlsContainer.topAnchor, constant: 8),
            programmaticLensSegmentedControl.bottomAnchor.constraint(equalTo: lensControlsContainer.bottomAnchor, constant: -8)
        ])
    }
    
    // MARK: - Zoom UI Configuration
    private func configureZoomUI() {
        // Configure programmatic controls
        programmaticZoomSlider.minimumValue = 1.0
        programmaticZoomSlider.maximumValue = Float(maxZoomFactor)
        programmaticZoomSlider.value = Float(currentZoomFactor)
        updateZoomLabel()
    }
    
    // MARK: - Lens UI Configuration
    private func configureLensUI() {
        updateLensSegmentedControl()
    }
    
    private func updateZoomLabel() {
        let zoomText = String(format: "%.1fx", currentZoomFactor)
        programmaticZoomLabel.text = zoomText
    }
    
    // MARK: - Lens Display Order Helper
    private func getOrderedAvailableLenses() -> [CameraLensType] {
        // Custom display order: 0.5, 1, 2x (ultraWide, wideAngle, telephoto)
        let displayOrder: [CameraLensType] = [.ultraWide, .wideAngle, .telephoto, .dualCamera]
        return displayOrder.filter { availableLensTypes.contains($0) }
    }
    
    private func updateLensSegmentedControl() {
        // Update both storyboard and programmatic controls
        updateSegmentedControl(programmaticLensSegmentedControl)
        if let lensControl = self.lensSegmentedControl {
            updateSegmentedControl(lensControl)
        }
    }
    
    private func updateSegmentedControl(_ control: UISegmentedControl) {
        control.removeAllSegments()
        
        let orderedAvailableLenses = getOrderedAvailableLenses()
        
        for (index, lensType) in orderedAvailableLenses.enumerated() {
            control.insertSegment(withTitle: lensType.displayName, at: index, animated: false)
        }
        
        if let currentIndex = orderedAvailableLenses.firstIndex(of: currentLensType) {
            control.selectedSegmentIndex = currentIndex
        }
    }
    
    // MARK: - Update Methods for Remote Responses
    func updateZoomControls(zoomFactor: CGFloat, maxZoom: CGFloat) {
        currentZoomFactor = zoomFactor
        maxZoomFactor = maxZoom
        
        OperationQueue.main.addOperation { [weak self] in
            self?.programmaticZoomSlider.maximumValue = Float(maxZoom)
            self?.programmaticZoomSlider.value = Float(zoomFactor)
            self?.updateZoomLabel()
        }
    }
    
    func updateLensControls(lensType: CameraLensType, availableLenses: [CameraLensType]) {
        currentLensType = lensType
        availableLensTypes = availableLenses
        
        OperationQueue.main.addOperation { [weak self] in
            self?.updateLensSegmentedControl()
        }
    }

    @objc func onSegmentedControlChanged(event: UIEvent) {
        if InAppPurchasesManager.shared().hasVideoRecordingFeature() {
            var mode = RecordingMode.Photo
            switch segmentedControl.selectedSegmentIndex {
            case 0:
                mode = RecordingMode.Photo
            default:
                mode = RecordingMode.Video
            }
            session ! UICmd.BecomeMonitor(nil, mode: mode)
        } else {
            showSettings(sender: settingsButton)
            segmentedControl.selectedSegmentIndex = 0
        }
    }

    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        if let image = info[.originalImage] {
            let activityViewController = UIActivityViewController(activityItems: [image], applicationActivities: [])
            picker.dismiss(animated: true) {
                #if targetEnvironment(macCatalyst)
                activityViewController.modalPresentationStyle = UIModalPresentationStyle.pageSheet
                #else
                activityViewController.modalPresentationStyle = UIModalPresentationStyle.popover
                activityViewController.popoverPresentationController?.sourceView = self.galleryButton
                #endif
                self.present(activityViewController, animated: true)
            }
        }
    }
}
