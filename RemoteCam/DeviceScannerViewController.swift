//
//  DeviceScannerViewController.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 12/14/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import UIKit
import SwiftUI
import MultipeerConnectivity
import Network
import dnssd

let service: String = "RemoteCam"
let userDefaultsPeerId = "peerID"
let userDefaultsSpeedRunScanning = "speedrunscanning"
let remoteShutterUrl = "https://apps.apple.com/us/app/remote-shutter/id633274861"

func generateQRCode(_ string: String) -> UIImage? {
    let data = string.data(using: String.Encoding.utf8)

    if let filter = CIFilter(name: "CIQRCodeGenerator") {
        filter.setValue(data, forKey: "inputMessage")
        let transform = CGAffineTransform(scaleX: 10, y: 10)

        if let output = filter.outputImage?.transformed(by: transform) {
            let context = CIContext()
            if let cgImage = context.createCGImage(output, from: output.extent) {
                return UIImage(cgImage: cgImage)
            }
        }
    }
    return nil
}

public class DeviceScannerViewController: UIViewController {

    // MARK: - SwiftUI ViewModel

    let scannerViewModel = DeviceScannerViewModel()
    private var swiftUIHostingController: UIHostingController<DeviceScannerView>?

    // MARK: - Peer ID

    var peerID: MCPeerID = MCPeerID(displayName: "null")

    private lazy var _peerIDInitialized: Bool = {
        initializePeerID()
        return true
    }()

    private func initializePeerID() {
        let currentDeviceName = UIDevice.current.name

        if let data = UserDefaults.standard.data(forKey: userDefaultsPeerId),
           let cachedPeerID = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data) {
            if cachedPeerID.displayName == currentDeviceName {
                self.peerID = cachedPeerID
            } else {
                let newPeerID = MCPeerID(displayName: currentDeviceName)
                let newData = try? NSKeyedArchiver.archivedData(
                      withRootObject: newPeerID, requiringSecureCoding: false)
                UserDefaults.standard.set(newData, forKey: userDefaultsPeerId)
                self.peerID = newPeerID
            }
        } else {
            let peerID = MCPeerID(displayName: currentDeviceName)
            let data = try? NSKeyedArchiver.archivedData(
                  withRootObject: peerID, requiringSecureCoding: false)
            UserDefaults.standard.set(data, forKey: userDefaultsPeerId)
            self.peerID = peerID
        }
    }

    // MARK: - Actors

    private(set) var frameSender: ActorRef!
    private var frameSenderInstanceId: ObjectIdentifier?
    private(set) var remoteCamSession: ActorRef!
    private var remoteCamSessionInstanceId: ObjectIdentifier?

    // MARK: - Network Browser

    var networkBrowser: NWBrowser?

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        _ = _peerIDInitialized
        let fs = createOrReplaceActor(
            clz: FrameSender.self,
            name: "FrameSender"
        )
        frameSender = fs.ref
        frameSenderInstanceId = fs.instanceId
        let rcs = createOrReplaceActor(
            clz: RemoteCamSession.self,
            name: "RemoteCam Session"
        )
        remoteCamSession = rcs.ref
        remoteCamSessionInstanceId = rcs.instanceId
        self.remoteCamSession ! SetViewCtrl(ctrl: self)
        setupSwiftUIView()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = false
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.title = NSLocalizedString("Scan for devices", comment: "")

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "questionmark.circle"),
            style: .plain,
            target: self,
            action: #selector(showHelpModal)
        )
        navigationItem.rightBarButtonItem?.tintColor = UIColor(AppTheme.accent)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        remoteCamSession ! Disconnect()

        if scannerViewModel.speedRunScanning {
            checkLocalNetworkAccessAndStartScanning()
        }
    }

    // MARK: - SwiftUI Setup

    private func setupSwiftUIView() {

        let scannerView = DeviceScannerView(
            viewModel: scannerViewModel,
            onStartScanning: { [weak self] in
                self?.startScanningDevices()
            },
            onStopScanning: { [weak self] in
                self?.stopScanningDevices()
            },
            onSelectPeer: { [weak self] peer in
                guard let self = self else { return }
                self.remoteCamSession ! ConnectToDevice(peer: peer, sender: nil)
                self.scannerViewModel.connectingToPeer()
            },
            onShareApp: { [weak self] in
                self?.shareAppLink()
            },
            onOpenSettings: { [weak self] in
                self?.goToAppSettings()
            },
            onHelp: { [weak self] in
                self?.showHelpModal()
            }
        )

        let hostingController = UIHostingController(rootView: scannerView)
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

    // MARK: - Scanning

    func startScanningDevices() {
        showScanningPermissionAlert()
    }

    func showScanningPermissionAlert() {
        let permissionView = LocalNetworkPermissionView(
            permissionType: .initial,
            onAllow: { [weak self] in
                self?.dismiss(animated: true) {
                    self?.checkLocalNetworkAccessAndStartScanning()
                }
            },
            onNotNow: { [weak self] in
                self?.dismiss(animated: true)
            },
            onOpenSettings: { [weak self] in
                self?.dismiss(animated: true) {
                    self?.goToAppSettings()
                }
            }
        )

        let hostingController = UIHostingController(rootView: permissionView)
        hostingController.modalPresentationStyle = .fullScreen
        present(hostingController, animated: true)
    }

    func checkLocalNetworkAccessAndStartScanning() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browserDescriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(
            type: "_remotecam._tcp",
            domain: "local."
        )

        networkBrowser = NWBrowser(for: browserDescriptor, using: parameters)

        networkBrowser?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .waiting(let error):
                    print("Network browser waiting with error: \(error)")
                    if case .dns(let dnsError) = error {
                        let dnsCode = Int(dnsError)
                        if dnsCode == Int(kDNSServiceErr_PolicyDenied) {
                            self?.scannerViewModel.networkAccessDenied()
                            self?.showLocalNetworkAccessDeniedAlert()
                            return
                        }
                    }
                    self?.scannerViewModel.networkAccessGranted()
                    self?.startActualScanning()
                case .ready:
                    self?.scannerViewModel.networkAccessGranted()
                    self?.startActualScanning()
                case .failed:
                    self?.scannerViewModel.networkAccessDenied()
                    self?.showLocalNetworkAccessDeniedAlert()
                default:
                    break
                }
            }
        }

        networkBrowser?.start(queue: .main)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.networkBrowser?.cancel()
        }
    }

    func startActualScanning() {
        remoteCamSession ! UICmd.StartScanning(sender: nil)
    }

    func startScanning() {
        scannerViewModel.startedScanning()
    }

    func stopScanning() {
        scannerViewModel.stoppedScanning()
    }

    @objc func stopScanningDevices() {
        scannerViewModel.stoppedScanning()
        scannerViewModel.clearPeers()
        remoteCamSession ! Disconnect()
    }

    func showLocalNetworkAccessDeniedAlert() {
        let permissionView = LocalNetworkPermissionView(
            permissionType: .denied,
            onAllow: { [weak self] in
                self?.dismiss(animated: true) {
                    self?.goToAppSettings()
                }
            },
            onNotNow: { [weak self] in
                self?.dismiss(animated: true)
            },
            onOpenSettings: { [weak self] in
                self?.dismiss(animated: true) {
                    self?.goToAppSettings()
                }
            }
        )

        let hostingController = UIHostingController(rootView: permissionView)
        hostingController.modalPresentationStyle = .fullScreen
        present(hostingController, animated: true)
    }

    // MARK: - Navigation

    func goToRolePicker() {
        scannerViewModel.connectedToPeer()
        let backItem = UIBarButtonItem()
        backItem.title = NSLocalizedString("Disconnect", comment: "")
        navigationItem.backBarButtonItem = backItem
        let rolePicker = RolePickerController()
        navigationController?.pushViewController(rolePicker, animated: true)
    }

    func goToAppSettings() {
        goToSettings()
    }

    func shareAppLink() {
        let items = [String(format: NSLocalizedString("call_to_download", comment: ""), remoteShutterUrl)]
        let activityViewController = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activityViewController.excludedActivityTypes = [.airDrop]
        if let popoverController = activityViewController.popoverPresentationController {
            popoverController.sourceRect = CGRect(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2, width: 0, height: 0)
            popoverController.sourceView = self.view
            popoverController.permittedArrowDirections = UIPopoverArrowDirection(rawValue: 0)
        }
        present(activityViewController, animated: true, completion: nil)
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

    deinit {
        print("deinit DeviceScanners")
        networkBrowser?.cancel()
        stopActorIfCurrent(ref: frameSender, instanceId: frameSenderInstanceId)
        stopActorIfCurrent(ref: remoteCamSession, instanceId: remoteCamSessionInstanceId)
    }
}
