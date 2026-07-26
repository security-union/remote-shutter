//
//  DeviceScannerViewController.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 12/14/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import UIKit
import SwiftUI
import MPCCompat
import PeerMesh
import Network
import dnssd

// Bonjour service types must be 1–15 chars of lowercase ASCII letters,
// digits and hyphens (MCNearbyServiceAdvertiser docs). DNS-SD compares
// labels case-insensitively, so this stays discoverable by older builds
// that used "RemoteCam". Must match NSBonjourServices in Info.plist.
let service: String = "remotecam"
let userDefaultsPeerId = "peerID"
let userDefaultsSpeedRunScanning = "speedrunscanning"
let userDefaultsLocalNetworkPrimerShown = "localNetworkPrimerShown"
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

    // MARK: - Role

    let role: DeviceRole

    init(role: DeviceRole) {
        self.role = role
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

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

        // The PeerMesh-backed MCPeerID is Codable, not NSCoding like the real
        // MCPeerID was; the cache moved from NSKeyedArchiver to JSON. Stale
        // MPC-era archives fail to decode and are simply regenerated.
        if let data = UserDefaults.standard.data(forKey: userDefaultsPeerId),
           let cachedPeerID = try? JSONDecoder().decode(MCPeerID.self, from: data),
           cachedPeerID.displayName == currentDeviceName {
            self.peerID = cachedPeerID
        } else {
            let peerID = MCPeerID(displayName: currentDeviceName)
            let data = try? JSONEncoder().encode(peerID)
            UserDefaults.standard.set(data, forKey: userDefaultsPeerId)
            self.peerID = peerID
        }
    }

    // MARK: - Session

    /// The session state machine; this screen owns its lifetime.
    let remoteCamSession = SessionCoordinator()
    private(set) lazy var frameSender = FrameSender(coordinator: remoteCamSession)

    // MARK: - Network Browser

    var networkBrowser: NWBrowser?

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        _ = _peerIDInitialized
        remoteCamSession.setFrameSender(frameSender)
        self.remoteCamSession ! SetScannerLobby(lobby: self)
        scannerViewModel.role = role
        setupSwiftUIView()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = false
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.title = role == .camera
            ? NSLocalizedString("Waiting for remote", comment: "")
            : NSLocalizedString("Scan for cameras", comment: "")

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
            onCancelConnect: { [weak self] in
                self?.remoteCamSession ! UICmd.CancelConnect(sender: nil)
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

        swiftUIHostingController = embedSwiftUIView(scannerView)
    }

    // MARK: - Scanning

    func startScanningDevices() {
        // App Review 5.1.1(iv): the explainer may precede the system prompt only —
        // once it has been shown (and the prompt reached), go straight to scanning.
        if UserDefaults.standard.bool(forKey: userDefaultsLocalNetworkPrimerShown) {
            checkLocalNetworkAccessAndStartScanning()
        } else {
            showScanningPermissionAlert()
        }
    }

    func showScanningPermissionAlert() {
        let permissionView = LocalNetworkPermissionView(
            permissionType: .initial,
            onAllow: { [weak self] in
                UserDefaults.standard.set(true, forKey: userDefaultsLocalNetworkPrimerShown)
                self?.dismiss(animated: true) {
                    self?.checkLocalNetworkAccessAndStartScanning()
                }
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
            type: "_\(service)._tcp",
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

    func goToRole() {
        scannerViewModel.connectedToPeer()
        let backItem = UIBarButtonItem()
        backItem.title = NSLocalizedString("Disconnect", comment: "")
        navigationItem.backBarButtonItem = backItem

        switch role {
        case .camera:
            let rig = CameraRig(session: remoteCamSession, frameSender: frameSender)
            let camera = CameraHostController(rig: rig)
            navigationController?.pushViewController(camera, animated: true)
        case .monitor:
            let monitor = MonitorViewController(session: remoteCamSession)
            navigationController?.pushViewController(monitor, animated: true)
        }
    }

    func goToAppSettings() {
        #if targetEnvironment(macCatalyst)
        // Local-network permission lives in System Settings on the Mac.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        #else
        if let bundleId = Bundle.main.bundleIdentifier,
           let url = URL(string: "\(UIApplication.openSettingsURLString)&path=LOCATION/\(bundleId)") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        #endif
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
        presentHelpSheet()
    }

    deinit {
        print("deinit DeviceScanners")
        networkBrowser?.cancel()
        remoteCamSession.stop()
    }
}

// MARK: - ScannerLobby

extension DeviceScannerViewController: ScannerLobby {
    /// Pop navigation back to this screen when scanning restarts.
    func returnToLobby() {
        navigationController?.popToViewController(self, animated: true)
    }

    func presentScanningError() {
        let alert = UIAlertController(
            title: NSLocalizedString("Scanning Error", comment: ""),
            message: NSLocalizedString("Unable to scan for nearby devices. Please check your network settings and try again.", comment: ""),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("OK", comment: ""),
            style: .default,
            handler: nil
        ))
        present(alert, animated: true)
    }
}
