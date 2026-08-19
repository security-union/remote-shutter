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
import Stormo
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

        // The Stormo-backed MCPeerID is Codable, not NSCoding like the real
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

    /// Injectable so the foreground re-arm can be driven in tests.
    var notificationCenter: NotificationCenter = .default
    private var foregroundTask: Task<Void, Never>?
    private var backgroundTask: Task<Void, Never>?

    // MARK: - Network Browser

    var networkBrowser: NWBrowser?

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        _ = _peerIDInitialized
        remoteCamSession.setFrameSender(frameSender)
        self.remoteCamSession ! SetScannerLobby(lobby: self)
        scannerViewModel.role = role
        // Multicam director collecting: only the monitor role, only behind the
        // flag. Off, the coordinator's scanning path is byte-identical.
        if FeatureFlags.ENABLE_MULTICAM && role == .monitor {
            remoteCamSession ! UICmd.SetMulticamCollecting(on: true)
        }
        // The reconnect overlay's only action, routed like every other UI
        // command; the overlay itself is pure state (PeerLinkStatus).
        PeerLinkStatus.shared.onCancel = { [weak self] in
            self?.remoteCamSession ! UICmd.CancelReconnect()
        }
        observeForeground()
        setupSwiftUIView()
    }

    /// Suspension kills the peer session within seconds and the transport's
    /// notice lands on a frozen app, so returning to the foreground is the one
    /// moment we know we are running: the session re-checks itself here. A
    /// plain observer because `AppActivityMonitor.onChange` is a single closure
    /// already owned by `WatchSessionManager`.
    private func observeForeground() {
        let notifications = notificationCenter.notifications(
            named: UIApplication.didBecomeActiveNotification)
        foregroundTask = Task { [weak self] in
            for await _ in notifications {
                guard let self else { return }
                self.remoteCamSession ! UICmd.AppForegrounded()
            }
        }
        observeBackground()
    }

    /// Locking or backgrounding suspends the process in seconds — a rolling
    /// recording would be frozen mid-write and its footage's fate left to
    /// chance. The coordinator finalizes and saves instead ("a locked camera
    /// cannot capture, so recording through a lock would be a lie"); the
    /// background task buys the writer the seconds it needs to finish.
    private func observeBackground() {
        let notifications = notificationCenter.notifications(
            named: UIApplication.didEnterBackgroundNotification)
        backgroundTask = Task { [weak self] in
            for await _ in notifications {
                guard let self else { return }
                var token: UIBackgroundTaskIdentifier = .invalid
                token = UIApplication.shared.beginBackgroundTask {
                    UIApplication.shared.endBackgroundTask(token)
                }
                self.remoteCamSession ! UICmd.AppBackgrounded()
                // The finalize + Photos save settle well inside this window.
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                    if token != .invalid { UIApplication.shared.endBackgroundTask(token) }
                }
            }
        }
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
        remoteCamSession ! UICmd.ScannerDidAppear()

        // Re-arm multicam collecting on every appearance: this controller
        // stays in the nav stack, so viewDidLoad does not re-run on return.
        // Sent AFTER ScannerDidAppear so the coordinator has settled into
        // scanning; the re-arm reports the live set and the scanner resyncs
        // (see rearmMulticamScanner).
        if FeatureFlags.ENABLE_MULTICAM && role == .monitor {
            remoteCamSession ! UICmd.SetMulticamCollecting(on: true)
        }

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
                if FeatureFlags.ENABLE_MULTICAM && self.role == .monitor {
                    self.handleMulticamRowTap(peer)
                } else {
                    self.remoteCamSession ! ConnectToDevice(peer: peer, sender: nil)
                    self.scannerViewModel.connectingToPeer()
                }
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
            },
            onConnectSelected: (FeatureFlags.ENABLE_MULTICAM && role == .monitor)
                ? { [weak self] in self?.handleConnectSelected() }
                : nil
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

    /// Probes for Local Network permission, then starts scanning. The verdict
    /// comes from `LocalNetworkProbe`: only the OS's own denial code blocks;
    /// anything else — including a probe that fails or times out because there
    /// is no Wi-Fi network — proceeds, since scanning is the real test.
    func checkLocalNetworkAccessAndStartScanning() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browserDescriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(
            type: "_\(service)._tcp",
            domain: "local."
        )

        let browser = NWBrowser(for: browserDescriptor, using: parameters)
        networkBrowser = browser

        // The probe answers once; later state changes (waiting → ready, or the
        // cancel below) must not re-present the alert or restart scanning.
        var resolved = false
        let resolve: (LocalNetworkProbe.Verdict) -> Void = { [weak self] verdict in
            guard !resolved, verdict != .keepWaiting else { return }
            resolved = true
            switch verdict {
            case .denied:
                self?.scannerViewModel.networkAccessDenied()
                self?.showLocalNetworkAccessDeniedAlert()
            case .proceed, .keepWaiting:
                self?.scannerViewModel.networkAccessGranted()
                self?.startActualScanning()
            }
        }

        browser.stateUpdateHandler = { state in
            DispatchQueue.main.async {
                resolve(LocalNetworkProbe.verdict(for: state))
            }
        }

        browser.start(queue: .main)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.networkBrowser?.cancel()
            // No evidence of denial within the window is not denial.
            if !resolved { resolve(.proceed) }
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
        remoteCamSession ! UICmd.StopScanning()
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

    /// Multicam "Start (N)": one camera runs the classic 1:1 monitor
    /// (unchanged); two or more hands the live transport to a
    /// `MulticamController` and pushes the director screen.
    /// A tap on a discovered-camera row while SELECTING. Pure — it toggles the
    /// checkmark and fires zero network. An over-cap unselected row is locked
    /// and routes to the paywall instead.
    private func handleMulticamRowTap(_ peer: MCPeerID) {
        let vm = scannerViewModel
        if vm.multicamRowLocked(peer, maxCameras: StoreManager.shared.maxCameras()) {
            presentMulticamPaywall()
            return
        }
        vm.toggleMulticamSelection(peer)
    }

    /// The bottom CTA. With a selection, connect it; with none, select all up
    /// to the cap and connect. A selection made entirely of still-live links
    /// invites nobody and settles immediately.
    private func handleConnectSelected() {
        let vm = scannerViewModel
        let peers = vm.multicamSelectedPeers.isEmpty
            ? vm.selectAllAndBeginConnecting(maxCameras: StoreManager.shared.maxCameras())
            : vm.beginMulticamConnecting()
        for peer in peers {
            remoteCamSession ! ConnectToDevice(peer: peer, sender: nil)
        }
        finishMulticamConnectIfSettled()
    }

    /// Every selected camera has connected or failed. Hand off to the right
    /// screen, or fall back to the scanner if none connected.
    private func finishMulticamConnectIfSettled() {
        let vm = scannerViewModel
        guard vm.multicamConnectSettled else { return }
        let connected = vm.multicamConnectedPeers
        switch MulticamHandoff.decide(
            connected: connectedPeersInSelectionOrder(connected)) {
        case .none:
            vm.resetMulticamCycle()
            presentScanningError()
        case .classicMonitor:
            Task { @MainActor in
                if await remoteCamSession.promoteSingleCollectedToConnected() { goToRole() }
            }
        case .director:
            Task { @MainActor in
                guard let handoff = await remoteCamSession.detachTransportForMulticam() else { return }
                let controller = MulticamController()
                await controller.install(transport: handoff.transport,
                                         initialPeers: handoff.peers)
                let directorVC = MulticamViewController(controller: controller)
                navigationController?.pushViewController(directorVC, animated: true)
            }
        }
    }

    /// The connected cameras in discovered-list order (stable handoff order).
    private func connectedPeersInSelectionOrder(_ connected: Set<MCPeerID>) -> [MCPeerID] {
        scannerViewModel.connectedPeers.filter { connected.contains($0) }
    }

    /// The shared Settings/paywall sheet — the same one the monitor gates use.
    private func presentMulticamPaywall() {
        let ctrl = UIHostingController(rootView: SettingsView())
        ctrl.modalPresentationStyle = .pageSheet
        present(ctrl, animated: true)
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
        logDebug("deinit DeviceScanners")
        foregroundTask?.cancel()
        backgroundTask?.cancel()
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

    /// Multicam collecting: reconcile the per-row selection + the "Start (N)"
    /// count from the coordinator's effective set.
    func didCollectMulticamCameras(_ peers: [MCPeerID]) {
        scannerViewModel.reconcileMulticamConnected(peers)
        finishMulticamConnectIfSettled()
    }

    func didFailMulticamCamera(_ peer: MCPeerID) {
        scannerViewModel.markMulticamFailed(peer)
        finishMulticamConnectIfSettled()
    }

    /// Collecting was (re)armed: sync the view model's live-link truth to the
    /// coordinator's current set, then clear stale cycle state. A camera whose
    /// link survived (director re-entry) stays selected+checked; a single-cam
    /// visit that dropped its link comes back empty and ready to re-select.
    func rearmMulticamScanner(liveLinks: [MCPeerID]) {
        scannerViewModel.reconcileMulticamConnected(liveLinks)
        scannerViewModel.resetMulticamCycle()
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
