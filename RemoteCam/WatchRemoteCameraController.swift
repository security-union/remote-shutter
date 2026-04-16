//
//  WatchRemoteCameraController.swift
//  RemoteShutter
//
//  View controller for Watch Remote mode.
//  Creates actors, embeds CameraViewController, and bridges Watch commands.
//

import UIKit
import SwiftUI

public class WatchRemoteCameraController: UIViewController {

    // MARK: - Actor References

    private var frameSender: ActorRef!
    private var frameSenderInstanceId: ObjectIdentifier?
    private var remoteCamSession: ActorRef!
    private var remoteCamSessionInstanceId: ObjectIdentifier?

    // MARK: - Camera

    private var cameraVC: CameraViewController!

    // MARK: - Watch Status Overlay

    private var statusLabel: UILabel!

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        setupActors()
        setupCameraViewController()
        setupWatchStatusOverlay()
        bindToWatchManager()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Enter watchRemoteCamera state on the actor
        remoteCamSession ! UICmd.BecomeWatchCamera(ctrl: cameraVC)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed || isMovingFromParent {
            unbindFromWatchManager()
            remoteCamSession ! UICmd.UnbecomeWatchCamera()
        }
    }

    deinit {
        unbindFromWatchManager()
        stopActorIfCurrent(ref: remoteCamSession, instanceId: remoteCamSessionInstanceId)
        stopActorIfCurrent(ref: frameSender, instanceId: frameSenderInstanceId)
    }

    // MARK: - Actor Setup

    private func setupActors() {
        let fs = createOrReplaceActor(clz: FrameSender.self, name: "FrameSender")
        frameSender = fs.ref
        frameSenderInstanceId = fs.instanceId

        let rcs = createOrReplaceActor(clz: RemoteCamSession.self, name: "RemoteCam Session")
        remoteCamSession = rcs.ref
        remoteCamSessionInstanceId = rcs.instanceId
    }

    // MARK: - Camera Setup

    private func setupCameraViewController() {
        cameraVC = CameraViewController()
        cameraVC.isWatchRemoteMode = true

        addChild(cameraVC)
        view.addSubview(cameraVC.view)
        cameraVC.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cameraVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            cameraVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cameraVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cameraVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        cameraVC.didMove(toParent: self)
    }

    // MARK: - Watch Status Overlay

    private func setupWatchStatusOverlay() {
        statusLabel = UILabel()
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.layer.cornerRadius = 14
        statusLabel.clipsToBounds = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.heightAnchor.constraint(equalToConstant: 28),
        ])

        updateWatchStatusLabel()
    }

    private func updateWatchStatusLabel() {
        let isReachable = WatchSessionManager.shared.isWatchReachable
        if isReachable {
            statusLabel.text = "  \u{2328}\u{FE0F}  " + NSLocalizedString("Watch Connected", comment: "") + "  "
            statusLabel.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.4)
        } else {
            statusLabel.text = "  \u{231A}  " + NSLocalizedString("Open Watch App", comment: "") + "  "
            statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        }
        statusLabel.sizeToFit()
        // Re-apply height and corner radius after sizeToFit
        statusLabel.frame.size.height = 28
        statusLabel.frame.size.width += 16 // padding
    }

    // MARK: - Watch Manager Binding

    private func bindToWatchManager() {
        WatchSessionManager.shared.cameraController = self
    }

    private func unbindFromWatchManager() {
        if WatchSessionManager.shared.cameraController === self {
            WatchSessionManager.shared.cameraController = nil
            WatchSessionManager.shared.pushDisconnectedState()
        }
    }

    // MARK: - Navigation Bar

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationItem.title = NSLocalizedString("Watch Remote", comment: "")
        navigationController?.navigationBar.prefersLargeTitles = false

        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.tintColor = .white
    }

    // MARK: - Handle Watch Commands (FlatBuffer-decoded)

    func handleWatchCommand(action: RemoteShutter_WatchCommandAction,
                            zoomFactor: Double,
                            lensType: RemoteShutter_CameraLensType) {
        let session = remoteCamSession!

        switch action {
        case .setzoom:
            session ! RemoteCmd.SetZoom(zoomFactor: CGFloat(zoomFactor))

        case .takepicture:
            session ! RemoteCmd.TakePic(sender: nil, sendMediaToPeer: false)

        case .startrecording:
            session ! RemoteCmd.StartRecordingVideo(sender: nil)

        case .stoprecording:
            session ! RemoteCmd.StopRecordingVideo(sender: nil)

        case .switchlens:
            if let camLens = CameraLensType(rawValue: Int(lensType.rawValue)) {
                session ! RemoteCmd.SwitchLens(lensType: camLens)
            }

        case .toggleflash:
            session ! RemoteCmd.ToggleFlash()

        case .toggletorch:
            session ! RemoteCmd.ToggleTorch()

        case .togglecamera:
            session ! RemoteCmd.ToggleCamera()

        case .requeststate:
            session ! RemoteCmd.RequestCameraCapabilities()

        case .unknown:
            debugLog("WatchRemoteCameraController: Unknown watch command")
        }
    }

    // MARK: - Watch Reachability Changed

    func watchReachabilityChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.updateWatchStatusLabel()
        }
    }

    // MARK: - Push Current Camera State to Watch

    func pushCurrentState() {
        guard let ctrl = cameraVC else { return }
        let session = remoteCamSession!
        session ! RemoteCmd.RequestCameraCapabilities()
    }
}
