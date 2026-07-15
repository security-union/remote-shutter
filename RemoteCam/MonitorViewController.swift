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
        presentHelpSheet()
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        debugLog("🔍 DEBUG: MonitorViewController viewDidLoad - \(ObjectIdentifier(self))")

        presenter.setDisplay(self)
        session ! UICmd.BecomeMonitor(presenter: presenter, mode: .Photo)

        frameStreamReceiver.onImage = { [weak self] image in
            OperationQueue.main.addOperation {
                self?.updateCameraImageInViewModel(image)
            }
        }
        frameStreamReceiver.onStall = { [weak self] in
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
