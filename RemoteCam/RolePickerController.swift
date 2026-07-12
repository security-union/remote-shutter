//
//  LobbyViewController.swift
//  RemoteShutter
//
//  Created by Dario on 10/7/15.
//  Copyright © 2020 Security Union LLC. All rights reserved.
//

import UIKit
import SwiftUI


/**
     Role picker allows the user to select whether the current device want's to be the camera or the monitor.

    It is important to mention that the session is the actor that coordinates this modes internally.

    One neat feature is that if two devices are connected and both are in the RolePickerController, when device1 selects a role, say Camera, RemoteCamSession will inform device2 about the choice, so that it becomes the Monitor.
*/

public class RolePickerController: UIViewController {

    private var swiftUIHostingController: UIHostingController<RolePickerView>?

    override public func viewDidLoad() {
        super.viewDidLoad()
        setupSwiftUIView()
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = false
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.title = NSLocalizedString("Pick a role", comment: "")

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "questionmark.circle"),
            style: .plain,
            target: self,
            action: #selector(showHelpModal)
        )
        navigationItem.rightBarButtonItem?.tintColor = UIColor(AppTheme.accent)
    }

    // MARK: - SwiftUI Setup

    private func setupSwiftUIView() {
        let rolePickerView = RolePickerView(
            onCamera: { [weak self] in
                self?.becomeCamera()
            },
            onRemote: { [weak self] in
                self?.becomeMonitor()
            },
            onWatchRemote: { [weak self] in
                self?.becomeWatchRemote()
            }
        )

        swiftUIHostingController = embedSwiftUIView(rolePickerView)
    }

    // MARK: - Navigation

    @objc private func showHelpModal() {
        presentHelpSheet()
    }

    func becomeMonitor() {
        let scanner = DeviceScannerViewController(role: .monitor)
        navigationController?.pushViewController(scanner, animated: true)
    }

    func becomeWatchRemote() {
        #if targetEnvironment(macCatalyst)
        // No WatchConnectivity on the Mac; the role-picker row is already
        // hidden (watchPaired stays false), this guards the seam itself.
        return
        #else
        checkCameraPermissionsForWatchRemote()
        #endif
    }

    private func checkCameraPermissionsForWatchRemote() {
        let permissionManager = PermissionManager.shared
        permissionManager.updatePermissionStatuses()

        if permissionManager.areCameraAndPhotosGranted {
            let watchRemote = WatchRemoteCameraController()
            navigationController?.pushViewController(watchRemote, animated: true)
        } else if permissionManager.areCameraAndPhotosDenied {
            showCameraPermissionsModal(permissionType: .denied)
        } else {
            showWatchRemotePermissionsModal()
        }
    }

    private func showWatchRemotePermissionsModal() {
        let permissionView = CameraPermissionsView(
            permissionType: .initial,
            onAllow: { [weak self] in
                self?.dismiss(animated: true) {
                    PermissionManager.shared.requestCameraAndPhotosPermissions { [weak self] granted in
                        DispatchQueue.main.async {
                            if granted {
                                let watchRemote = WatchRemoteCameraController()
                                self?.navigationController?.pushViewController(watchRemote, animated: true)
                            } else {
                                self?.showCameraPermissionsModal(permissionType: .denied)
                            }
                        }
                    }
                }
            },
            onOpenSettings: { [weak self] in
                self?.dismiss(animated: true) {
                    PermissionManager.shared.openAppSettings()
                }
            }
        )

        let hostingController = UIHostingController(rootView: permissionView)
        hostingController.modalPresentationStyle = .fullScreen
        present(hostingController, animated: true)
    }

    func becomeCamera() {
        checkCameraPermissionsAndProceed()
    }

    private func checkCameraPermissionsAndProceed() {
        let permissionManager = PermissionManager.shared
        permissionManager.updatePermissionStatuses()

        if permissionManager.areCameraAndPhotosGranted {
            let scanner = DeviceScannerViewController(role: .camera)
            navigationController?.pushViewController(scanner, animated: true)
        } else if permissionManager.areCameraAndPhotosDenied {
            showCameraPermissionsModal(permissionType: .denied)
        } else {
            showCameraPermissionsModal(permissionType: .initial)
        }
    }

    private func showCameraPermissionsModal(permissionType: CameraPermissionsView.PermissionType) {
        let permissionView = CameraPermissionsView(
            permissionType: permissionType,
            onAllow: { [weak self] in
                self?.dismiss(animated: true) {
                    self?.requestPermissionsAndProceed()
                }
            },
            onOpenSettings: { [weak self] in
                self?.dismiss(animated: true) {
                    PermissionManager.shared.openAppSettings()
                }
            }
        )

        let hostingController = UIHostingController(rootView: permissionView)
        hostingController.modalPresentationStyle = .fullScreen
        present(hostingController, animated: true)
    }

    private func requestPermissionsAndProceed() {
        PermissionManager.shared.requestCameraAndPhotosPermissions { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    let scanner = DeviceScannerViewController(role: .camera)
                    self?.navigationController?.pushViewController(scanner, animated: true)
                } else {
                    self?.showCameraPermissionsModal(permissionType: .denied)
                }
            }
        }
    }

}
