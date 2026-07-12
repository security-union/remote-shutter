//
//  CameraHostController.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import UIKit
import SwiftUI

/**
 The camera screen's disposable UIKit shell: hosts `CameraScreenView` and does
 only view-controller things — navigation chrome, permissions UI, modal
 presentation, rotation forwarding, and announcing the camera role to the actor
 system at lifecycle edges. Everything with a brain lives on the `CameraRig`.
 */
final class CameraHostController: UIHostingController<CameraScreenView> {

    let rig: CameraRig
    private var microphonePromptController: UIViewController?

    init(rig: CameraRig) {
        self.rig = rig
        super.init(rootView: CameraScreenView(
            viewModel: rig.cameraViewModel,
            onSelectCameraDevice: { [weak rig] uniqueID in
                rig?.selectCameraDeviceLocally(uniqueID: uniqueID)
            },
            onSelectAudioDevice: { [weak rig] uniqueID in
                rig?.selectAudioDeviceLocally(uniqueID: uniqueID)
            }))
    }

    @available(*, unavailable)
    required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        wireRigSeams()
        if !rig.isWatchRemoteMode {
            rig.session ! UICmd.BecomeCamera(sender: nil, ctrl: rig)
        }
        rig.configureIdleMode()
    }

    private func wireRigSeams() {
        rig.setNavigationBarHidden = { [weak self] hidden in
            self?.navigationController?.isNavigationBarHidden = hidden
        }
        rig.onExit = { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        }
        rig.onMicrophoneDenied = { [weak self] in
            self?.showMicrophonePermissionPrompt()
        }
        rig.onPhotosAccessDenied = { [weak self] in
            self?.showPhotosAccessDeniedModal(for: .video)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)

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

        rig.orientation = getOrientation()
    }

    @objc private func showHelpModal() {
        presentHelpSheet()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        checkPermissionsAndSetupCamera()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        rig.ensureTorchOff()
        if isBeingDismissed || isMovingFromParent {
            rig.stopSession()
            if !rig.isWatchRemoteMode {
                rig.session ! UICmd.UnbecomeCamera(sender: nil)
            }
        }
    }

    override var shouldAutorotate: Bool {
        // Disable autorotation of the interface when recording is in progress.
        return !rig.isRecording
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        #if targetEnvironment(macCatalyst)
        // Window resizes reach here on the Mac, but there is no device
        // rotation — the capture orientation stays fixed (getOrientation()).
        return
        #else
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            // Mid-transition the window scene already reports the TARGET
            // orientation (getOrientation()'s foreground-scene lookup would still
            // return the old one if read before the animation block).
            let newOrientation = self.view.window?.windowScene?.interfaceOrientation ?? getOrientation()
            self.rig.orientation = newOrientation
            self.rig.rotateCameraToOrientation(orientation: newOrientation)
        }, completion: { [weak self] _ in
            // iOS can drop the torch when the capture pipeline reconfigures during
            // rotation, so restore the user's torch intent once the rotation
            // settles and re-sync the Watch, which would otherwise keep a stale
            // torch state.
            self?.rig.restoreTorchAfterRotation()
        })
        #endif
    }

    // MARK: - Permissions UI

    private func checkPermissionsAndSetupCamera() {
        let permissionManager = PermissionManager.shared
        permissionManager.updatePermissionStatuses()

        if permissionManager.areCameraAndPhotosGranted {
            rig.startCameraOnce()
        } else {
            showPermissionErrorView()
        }
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
        microphonePromptController = hostingController
    }

    private func dismissMicrophonePrompt() {
        microphonePromptController?.dismiss(animated: true)
        microphonePromptController = nil
    }
}
