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
import PhotosUI

let timerDefault = "timerDefault"

// Legacy setFlashMode and setTorchMode functions removed - using SwiftUI view model instead

/**
UI for the monitor.
*/

public class MonitorViewController: UIViewController {

    let session: SessionCoordinator

    /// The session→UI bridge; every session-side update lands here.
    let presenter = MonitorPresenter()

    init(session: SessionCoordinator) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Decodes incoming preview frames (JPEG/HEIC) off the actor mailbox and
    /// raises StreamStalled when the stream goes quiet.
    let frameStreamReceiver = FrameStreamReceiver()

    let timer = CountdownTimer()

    let soundManager = SoundManager()
    
    // MARK: - SwiftUI Integration
    private(set) var viewModel = MonitorViewModel()
    var swiftUIHostingController: UIHostingController<MonitorView>?

    private let sliderColor1 = UIColor(red: 0.150, green: 0.670, blue: 0.80, alpha: 1)
    private let sliderColor2 = UIColor(red: 0.060, green: 0.100, blue: 0.160, alpha: 1)

    private var zoomLabelTimer: Timer?
    
    // MARK: - Zoom and Lens Properties
    var currentZoomFactor: CGFloat = 1.0
    public var maxZoomFactor: CGFloat = 10.0

    /// Zoom sends are throttled to 20Hz with a trailing-edge flush. A continuous drag on
    /// the Mac zoom pill emits a value per frame, which would flood the Multipeer channel;
    /// a plain rate limit would silently drop the final position the user released on.
    /// Internal rather than private: `handleZoomChange` lives in a different file's
    /// extension, and `private` is file-scoped.
    var zoomThrottle = ZoomSendThrottle()
    var trailingZoomTimer: Timer?
    var availableLensTypes: [CameraLensType] = [.wideAngle]
    var currentLensType: CameraLensType = .wideAngle

    var buttonPrompt: String = ""

    // MARK: - Orientation Control

    /// The monitor follows the hand that holds it.
    ///
    /// The camera device rotates freely, so a tripod-mounted camera is usually
    /// landscape — and a portrait-locked monitor letterboxed that 16:9 frame
    /// into a 393pt-wide column, leaving the picture at 26% of the screen.
    /// Turning the remote to match puts it at ~82%. Nothing about capture is
    /// coupled to this: frames arrive already rotated by the camera.
    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .allButUpsideDown
    }

    override public var shouldAutorotate: Bool {
        return true
    }

    /// The nav bar's appearance before this screen made it transparent.
    private var savedBarAppearance: (standard: UINavigationBarAppearance,
                                     scrollEdge: UINavigationBarAppearance?,
                                     tint: UIColor?)?

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // iOS: the bar stays *present* but fully transparent, so the preview
        // still runs edge to edge behind it. Hiding it instead costs the
        // interactive swipe-back gesture, which UIKit disables along with the
        // bar; keeping it means Back and the swipe are both the system's own.
        //
        // Catalyst does not render this bar, and a Mac has no swipe to protect,
        // so there it stays hidden and MonitorView draws its own chevron.
        #if targetEnvironment(macCatalyst)
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
        #else
        self.navigationController?.setNavigationBarHidden(false, animated: animated)
        makeNavigationBarTransparent()
        installNavigationBarControls()
        #endif
        navigationItem.title = nil
        syncInterfaceOrientation()
    }

    /// Retained, but deliberately NOT added as a child view controller.
    /// `UIBarButtonItem(customView:)` puts the *view* inside the navigation
    /// bar, whose owning controller is the UINavigationController — parenting
    /// the hosting controller here as well makes UIKit see a child whose view
    /// lives under a different controller, and it raises
    /// UIViewControllerHierarchyInconsistency. The strong reference is what
    /// keeps the SwiftUI view alive and updating.
    private var navControlsHost: UIHostingController<MonitorNavControls>?

    /// Puts the flash · torch · tray capsule in the bar rather than in the
    /// chrome, so the strip the bar already occupies isn't spent twice.
    private func installNavigationBarControls() {
        guard navControlsHost == nil else { return }
        let controls = MonitorNavControls(
            viewModel: viewModel,
            onToggleFlash: { [weak self] in self?.handleToggleFlash() },
            onToggleTorch: { [weak self] in self?.handleToggleTorch() },
            onToggleTray: { [weak self] in
                guard let self else { return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    self.viewModel.isTrayOpen.toggle()
                }
            })
        let host = UIHostingController(rootView: controls)
        // Both: a hosting controller's view is opaque by default, which would
        // put a solid rectangle behind the capsule in the bar.
        host.view.backgroundColor = .clear
        host.view.isOpaque = false
        // Let Auto Layout ask SwiftUI for the size: the capsule is narrower in
        // video mode, where the flash glyph drops out.
        host.view.translatesAutoresizingMaskIntoConstraints = false
        navControlsHost = host
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: host.view)
    }

    private func makeNavigationBarTransparent() {
        guard let bar = navigationController?.navigationBar else { return }
        if savedBarAppearance == nil {
            savedBarAppearance = (bar.standardAppearance, bar.scrollEdgeAppearance, bar.tintColor)
        }
        let transparent = UINavigationBarAppearance()
        transparent.configureWithTransparentBackground()
        transparent.backgroundColor = .clear
        transparent.backgroundEffect = nil
        transparent.shadowColor = .clear
        bar.standardAppearance = transparent
        bar.scrollEdgeAppearance = transparent
        bar.compactAppearance = transparent
        // The one used in landscape on iPhone. Left unset it falls back to the
        // default opaque background, so the bar goes solid when you rotate.
        if #available(iOS 15.0, *) {
            bar.compactScrollEdgeAppearance = transparent
        }
        bar.isTranslucent = true
        bar.setBackgroundImage(UIImage(), for: .default)
        bar.shadowImage = UIImage()

        // Chevron only: the destination is a viewfinder, and "Disconnect" as a
        // back title read as a button rather than as where you came from.
        navigationItem.backButtonDisplayMode = .minimal
        // The viewfinder is dark in every state, so the back chevron and its
        // title are always white rather than following the tint.
        bar.tintColor = .white
    }

    override public func viewWillTransition(to size: CGSize,
                                            with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.syncInterfaceOrientation()
        })
    }

    /// Both landscapes are the same shape, so the view can't infer which rail
    /// keeps the shutter on the device's home-indicator edge.
    private func syncInterfaceOrientation() {
        let orientation = view.window?.windowScene?.interfaceOrientation
            ?? UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.interfaceOrientation }
                .first
            ?? .portrait
        if viewModel.interfaceOrientation != orientation {
            viewModel.interfaceOrientation = orientation
        }
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Hand the bar back to whatever screen comes next exactly as we found it.
        if let bar = navigationController?.navigationBar, let saved = savedBarAppearance {
            bar.standardAppearance = saved.standard
            bar.scrollEdgeAppearance = saved.scrollEdge
            bar.compactAppearance = nil
            if #available(iOS 15.0, *) {
                bar.compactScrollEdgeAppearance = nil
            }
            // Undo the legacy overrides too, or the next screen inherits a
            // transparent bar.
            bar.setBackgroundImage(nil, for: .default)
            bar.shadowImage = nil
            bar.isTranslucent = true
            bar.tintColor = saved.tint
            savedBarAppearance = nil
        }
        self.navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        debugLog("🔍 DEBUG: MonitorViewController viewDidLoad - \(ObjectIdentifier(self))")

        presenter.setDisplay(self)
        session ! UICmd.BecomeMonitor(presenter: presenter, mode: .Photo)

        frameStreamReceiver.onImage = { [weak self] image in
            OperationQueue.main.addOperation {
                // A frame arrived: whatever the watchdog thought, the stream is
                // live again.
                self?.viewModel.isPreviewStale = false
                self?.updateCameraImageInViewModel(image)
            }
        }
        frameStreamReceiver.onStall = { [weak self] in
            // Say so on screen. Re-requesting a frame silently left the user
            // looking at a frozen picture with no way to tell it was frozen.
            OperationQueue.main.addOperation {
                self?.viewModel.isPreviewStale = true
            }
            if let session = self?.session {
                session ! UICmd.StreamStalled()
            }
        }
        frameStreamReceiver.onKeyframeNeeded = { [weak self] in
            if let session = self?.session {
                session ! UICmd.RequestVideoKeyframe()
            }
        }
        frameStreamReceiver.start()
        
        // Setup SwiftUI view instead of storyboard
        setupSwiftUIView()
        
        // Configure initial state
        swiftUIConfigurePhotoMode()
        
        // Request camera capabilities after the monitor is fully set up
        // This handles the race condition where capabilities arrive before viewDidLoad
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            debugLog("🔍 DEBUG: Requesting camera capabilities after monitor setup")
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
        self.frameStreamReceiver.invalidate()
        self.timer.cancel()
        self.zoomLabelTimer?.invalidate()
        self.soundManager.stopPlayer()
        session ! UICmd.UnbecomeMonitor(sender: nil)
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
    
}

// MARK: - Gallery picker (PHPicker: modern, no photo-library permission prompt)

extension MonitorViewController: PHPickerViewControllerDelegate {
    public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else {
            picker.dismiss(animated: true)
            return
        }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            DispatchQueue.main.async {
                picker.dismiss(animated: true) {
                    guard let self, let image = object as? UIImage else { return }
                    let activityViewController = UIActivityViewController(
                        activityItems: [image], applicationActivities: [])
                    #if targetEnvironment(macCatalyst)
                    activityViewController.modalPresentationStyle = .pageSheet
                    #else
                    activityViewController.modalPresentationStyle = .popover
                    activityViewController.popoverPresentationController?.sourceView = self.view
                    #endif
                    self.present(activityViewController, animated: true)
                }
            }
        }
    }
}

// MARK: - MonitorDisplay

extension MonitorViewController: MonitorDisplay {
    /// The peer refused the monitor role — leave the monitor screen.
    func exitMonitor() {
        navigationController?.popViewController(animated: true)
    }
}
