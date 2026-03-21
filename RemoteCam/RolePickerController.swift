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

public class RemoteCamSystem: ActorSystem {
    static let shared = ActorSystem(name: "RemoteCam")
}

let connectedPrompt = NSLocalizedString("Pick a role: Camera or Remote", comment: "")

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
            title: NSLocalizedString("Info", comment: ""),
            style: .plain,
            target: self,
            action: #selector(showSettingsAction)
        )
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
            onSettings: { [weak self] in
                self?.showSettingsAction()
            }
        )

        let hostingController = UIHostingController(rootView: rolePickerView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        swiftUIHostingController = hostingController
    }

    // MARK: - Navigation

    @objc private func showSettingsAction() {
        let ctrl = UIHostingController(rootView: SettingsView())
        ctrl.modalPresentationStyle = .pageSheet
        self.present(ctrl, animated: true)
    }

    func becomeMonitor() {
        let scanner = DeviceScannerViewController(role: .monitor)
        navigationController?.pushViewController(scanner, animated: true)
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
            onNotNow: { [weak self] in
                self?.dismiss(animated: true)
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
