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

public class RolePickerActor: ViewCtrlActor<RolePickerController> {

    override public func receiveWithCtrl(ctrl: Weak<RolePickerController>) -> Receive {
        return {[unowned self] (msg: Message) in
            switch msg {

            case is RemoteCmd.PeerBecameMonitor:
                ^{
                    ctrl.value?.becomeCamera()
                }
            case is RemoteCmd.PeerBecameCamera:
                ^{
                    ctrl.value?.becomeMonitor()
                }
            default:
                self.receive(msg: msg)
            }
        }
    }
}

public class RolePickerController: UIViewController {

    public struct States {
        let connect = "Connect"
        let disconnect = "Disconnect"
    }

    public let states = States()
    private var swiftUIHostingController: UIHostingController<RolePickerView>?

    private(set) var rolePicker: ActorRef!
    private var rolePickerInstanceId: ObjectIdentifier?

    override public func viewDidLoad() {
        super.viewDidLoad()
        let rp = createOrReplaceActor(
            clz: RolePickerActor.self,
            name: "RolePickerActor"
        )
        rolePicker = rp.ref
        rolePickerInstanceId = rp.instanceId
        setupSwiftUIView()
        rolePicker ! SetViewCtrl(ctrl: self)
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
        let monitor = MonitorViewController()
        navigationController?.pushViewController(monitor, animated: true)
    }

    func becomeCamera() {
        checkCameraPermissionsAndProceed()
    }

    private func checkCameraPermissionsAndProceed() {
        let permissionManager = PermissionManager.shared
        permissionManager.updatePermissionStatuses()

        if permissionManager.areCameraAndPhotosGranted {
            let camera = CameraViewController()
            navigationController?.pushViewController(camera, animated: true)
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
                    let camera = CameraViewController()
                    self?.navigationController?.pushViewController(camera, animated: true)
                } else {
                    self?.showCameraPermissionsModal(permissionType: .denied)
                }
            }
        }
    }

    deinit {
        print("killing RolePickerController")
        stopActorIfCurrent(ref: rolePicker, instanceId: rolePickerInstanceId)
    }

}
