//
//  RemoteViewController.swift
//  Actors
//
//  Created by Dario on 10/7/15.
//  Copyright © 2015 dario. All rights reserved.
//

import UIKit
import SwiftUI
import AVFoundation

let timerDefault = "timerDefault"

// Legacy setFlashMode and setTorchMode functions removed - using SwiftUI view model instead

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
                    ctrl?.value?.swiftUIConfigurePhotoMode()
                }

            case is UICmd.RenderVideoMode:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.swiftUIConfigureVideoMode()
                }

            case is UICmd.RenderVideoModeRecording:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.swiftUIConfigureVideoRecording()
                }
                
            case let cmd as UICmd.SyncRecordingStartTime:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.viewModel.recordingStartTime = cmd.startTime
                }

            case is UICmd.RenderShortsMode:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.swiftUIConfigureShortsMode()
                }

            case is UICmd.BecomeMonitorFailed:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.navigationController?.popViewController(animated: true)
                }

            case let cam as UICmd.ToggleCameraResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ctrl = ctrl?.value, let flashMode = cam.flashMode {
                        ctrl.updateFlashModeInViewModel(flashMode)
                    }
                }

            case let flash as RemoteCmd.ToggleFlashResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ctrl = ctrl?.value, let flashMode = flash.flashMode {
                        ctrl.updateFlashModeInViewModel(flashMode)
                    }
                }

            case let torch as RemoteCmd.ToggleTorchResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ctrl = ctrl?.value, let torchMode = torch.torchMode {
                        ctrl.updateTorchModeInViewModel(torchMode)
                    }
                }
                
            case let torchSet as RemoteCmd.SetTorchResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ctrl = ctrl?.value, let torchMode = torchSet.torchMode {
                        ctrl.updateTorchModeInViewModel(torchMode)
                    }
                }

            case let f as RemoteCmd.OnFrame:
                if let cgImage = UIImage(data: f.data) {
                    OperationQueue.main.addOperation {[weak ctrl] in
                        if let ctrl = ctrl?.value {
                            ctrl.updateCameraImageInViewModel(cgImage)
                        }
                    }
                }
                
            // MARK: - Camera Capabilities Response Handling
            case let capabilities as RemoteCmd.CameraCapabilitiesResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ctrl = ctrl?.value, let cameraInfo = capabilities.getCurrentCameraInfo() {
                        // Update lens controls in view model
                        ctrl.updateLensTypesInViewModel(
                            cameraInfo.availableLenses,
                            current: capabilities.currentLens
                        )

                        // Update zoom controls in view model
                        if let zoomRange = cameraInfo.getZoomCapabilities()[capabilities.currentLens] {
                            ctrl.updateZoomInViewModel(
                                capabilities.currentZoom,
                                maxFactor: zoomRange.maxZoom
                            )
                        }

                        // Update quality capabilities in view model
                        ctrl.viewModel.updateVideoCapabilities(
                            resolutions: cameraInfo.supportedResolutions,
                            frameRates: cameraInfo.supportedFrameRates,
                            resolutionFrameRates: cameraInfo.getResolutionFrameRates())
                        ctrl.viewModel.updatePhotoCapabilities(
                            supportsHEIF: cameraInfo.supportsHEIF,
                            supportsHDR: cameraInfo.supportsHDR)

                        // Sync current quality settings from camera
                        ctrl.viewModel.updateVideoQuality(
                            resolution: capabilities.currentVideoResolution,
                            frameRate: capabilities.currentVideoFrameRate)
                        ctrl.viewModel.updatePhotoQuality(
                            format: capabilities.currentPhotoFormat,
                            hdrMode: capabilities.currentHDRMode)

                        // Update zoom stops from camera capabilities
                        ctrl.viewModel.updateZoomStops(
                            cameraInfo.zoomStops,
                            wideAngleZoomFactor: cameraInfo.wideAngleZoomFactor
                        )
                    }
                }
                
            // MARK: - Zoom Response Handling
            case let zoom as UICmd.SetZoomResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ctrl = ctrl?.value, let zoomFactor = zoom.zoomFactor {
                        let maxZoom = zoom.zoomRange?.maxZoom ?? ctrl.maxZoomFactor
                        ctrl.updateZoomInViewModel(zoomFactor, maxFactor: maxZoom)
                        // Sync lens type so zoom and lens controls stay cohesive
                        if let lens = zoom.currentLens {
                            ctrl.viewModel.updateAvailableLenses(ctrl.viewModel.availableLensTypes, current: lens)
                        }
                    }
                }

            case let zoomRemote as RemoteCmd.SetZoomResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ctrl = ctrl?.value, let zoomFactor = zoomRemote.zoomFactor {
                        let maxZoom = zoomRemote.zoomRange?.maxZoom ?? ctrl.maxZoomFactor
                        ctrl.updateZoomInViewModel(zoomFactor, maxFactor: maxZoom)
                        // Sync lens type so zoom and lens controls stay cohesive
                        if let lens = zoomRemote.currentLens {
                            ctrl.viewModel.updateAvailableLenses(ctrl.viewModel.availableLensTypes, current: lens)
                        }
                    }
                }
                
            // MARK: - Lens Response Handling
            case let lens as UICmd.SwitchLensResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ctrl = ctrl?.value,
                       let lensType = lens.lensType,
                       let availableLenses = lens.availableLenses {
                        ctrl.updateLensTypesInViewModel(availableLenses, current: lensType)
                        if let currentZoom = lens.currentZoom,
                           let zoomRange = lens.zoomRange {
                            ctrl.updateZoomInViewModel(currentZoom, maxFactor: zoomRange.maxZoom)
                        }
                    }
                }

            case let lensRemote as RemoteCmd.SwitchLensResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ctrl = ctrl?.value,
                       let lensType = lensRemote.lensType,
                       let availableLenses = lensRemote.availableLenses {
                        ctrl.updateLensTypesInViewModel(availableLenses, current: lensType)
                        if let currentZoom = lensRemote.currentZoom,
                           let zoomRange = lensRemote.zoomRange {
                            ctrl.updateZoomInViewModel(currentZoom, maxFactor: zoomRange.maxZoom)
                        }
                    }
                }

            // MARK: - Video Quality Response Handling
            case let videoQuality as RemoteCmd.SetVideoQualityResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let resolution = videoQuality.resolution,
                       let frameRate = videoQuality.frameRate {
                        ctrl?.value?.viewModel.updateVideoQuality(resolution: resolution, frameRate: frameRate)
                    }
                }

            // MARK: - Photo Quality Response Handling
            case let photoQuality as RemoteCmd.SetPhotoQualityResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let format = photoQuality.format,
                       let hdrMode = photoQuality.hdrMode {
                        ctrl?.value?.viewModel.updatePhotoQuality(format: format, hdrMode: hdrMode)
                    }
                }
            
            // MARK: - Aspect Ratio Response Handling
            case let ratioResp as RemoteCmd.SetAspectRatioResp:
                OperationQueue.main.addOperation {[weak ctrl] in
                    if let ratio = ratioResp.aspectRatio {
                        ctrl?.value?.viewModel.updateAspectRatio(ratio)
                    }
                }

            // MARK: - Video Transfer Progress Handling
            case let started as UICmd.VideoResourceTransferStarted:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.viewModel.startVideoTransfer(totalBytes: started.totalBytes)
                    print("📺 DEBUG: MonitorActor - Video transfer started: \(started.totalBytes) bytes")
                }
                
            case let progress as UICmd.VideoResourceTransferProgress:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.viewModel.updateVideoTransferProgress(
                        completedBytes: progress.completedBytes,
                        totalBytes: progress.totalBytes
                    )
                    ctrl?.value?.viewModel.updateVideoTransferSpeed(progress.transferSpeed)
                    print("📺 DEBUG: MonitorActor - Video transfer progress: \(Int(progress.progress * 100))% - Speed: \(String(format: "%.1f", progress.transferSpeed / 1024 / 1024)) MB/s")
                }
                
            case is UICmd.VideoResourceTransferCompleted:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.viewModel.finishVideoTransfer()
                    print("📺 DEBUG: MonitorActor - Video transfer completed")
                }
                
            case let failed as UICmd.VideoResourceTransferFailed:
                OperationQueue.main.addOperation {[weak ctrl] in
                    ctrl?.value?.viewModel.finishVideoTransfer()
                    print("📺 DEBUG: MonitorActor - Video transfer failed: \(failed.error.localizedDescription)")
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

    private(set) var monitor: ActorRef!
    private var monitorInstanceId: ObjectIdentifier?

    let timer: RCTimer = RCTimer()

    let soundManager: CPSoundManager = CPSoundManager()
    
    // MARK: - SwiftUI Integration
    private(set) var viewModel = MonitorViewModel()
    var swiftUIHostingController: UIHostingController<MonitorView>?

    private let sliderColor1 = UIColor(red: 0.150, green: 0.670, blue: 0.80, alpha: 1)
    private let sliderColor2 = UIColor(red: 0.060, green: 0.100, blue: 0.160, alpha: 1)

    // Note: bannerView, bannerHeight, bottomBannerConstraint inherited from BaseViewController
    
    // Pinch Gesture for Zoom
    private var pinchGestureRecognizer: UIPinchGestureRecognizer!
    private var lastPinchScale: CGFloat = 1.0
    private var zoomLabelTimer: Timer?
    
    // MARK: - Zoom and Lens Properties
    var currentZoomFactor: CGFloat = 1.0
    public var maxZoomFactor: CGFloat = 10.0
    var availableLensTypes: [CameraLensType] = [.wideAngle]
    var currentLensType: CameraLensType = .wideAngle

    var buttonPrompt: String = ""

    // MARK: - Orientation Control
    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    override public var shouldAutorotate: Bool {
        return false
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

    override public func viewDidLoad() {
        super.viewDidLoad()
        debugLog("🔍 DEBUG: MonitorViewController viewDidLoad - \(ObjectIdentifier(self))")

        let m = createOrReplaceActor(
            clz: MonitorActor.self,
            name: "MonitorActor"
        )
        monitor = m.ref
        monitorInstanceId = m.instanceId

        monitor ! SetViewCtrl(ctrl: self)
        
        // Setup SwiftUI view instead of storyboard
        setupSwiftUIView()
        
        // Configure initial state
        swiftUIConfigurePhotoMode()
        
        // Request camera capabilities after MonitorActor is fully set up
        // This handles the race condition where capabilities arrive before viewDidLoad
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            debugLog("🔍 DEBUG: Requesting camera capabilities after MonitorActor setup")
            if let session = self?.session {
                session ! UICmd.RequestCameraCapabilities()
            }
            
        }
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
    }

    deinit {
        print("MonitorViewController deinit")
        self.timer.cancel()
        self.zoomLabelTimer?.invalidate()
        self.soundManager.stopPlayer()
        session ! UICmd.UnbecomeMonitor(sender: nil)
        stopActorIfCurrent(ref: monitor, instanceId: monitorInstanceId)
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

    // Legacy configurePhotoMode removed - using SwiftUI swiftUIConfigurePhotoMode instead

    // Legacy configureVideoMode removed - using SwiftUI swiftUIConfigureVideoMode instead

    // Legacy configureVideoModeRecording removed - using SwiftUI swiftUIConfigureVideoRecording instead

    // Legacy @IBAction methods removed - using SwiftUI callbacks instead
    
    // Legacy @objc and @IBAction methods removed - using SwiftUI callbacks instead


    /**
     Take picture contains the logic to kick off the Timer for the picture.
    */

    // Legacy @IBAction onTakePicture removed - using SwiftUI callbacks instead

    // Legacy configureTimerUI removed - using SwiftUI instead
    
    // Legacy setupProgrammaticZoomAndLensControls removed - using SwiftUI instead
    
    // Legacy UIKit setup methods removed - using SwiftUI instead
    
    // Legacy pinch gesture handler removed - zoom gestures will be handled in SwiftUI
    
    // All legacy UIKit methods removed - using SwiftUI view model integration instead
    
    // MARK: - Essential UIImagePickerController Delegate (keep for now)
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        if let image = info[.originalImage] {
            let activityViewController = UIActivityViewController(activityItems: [image], applicationActivities: [])
            picker.dismiss(animated: true) {
                #if targetEnvironment(macCatalyst)
                activityViewController.modalPresentationStyle = UIModalPresentationStyle.pageSheet
                #else
                activityViewController.modalPresentationStyle = UIModalPresentationStyle.popover
                // Note: Using view instead of removed galleryButton
                activityViewController.popoverPresentationController?.sourceView = self.view
                #endif
                self.present(activityViewController, animated: true)
            }
        }
    }
}
