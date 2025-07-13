//
//  DeviceScannerViewController.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 12/14/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import UIKit
import Theater
import MultipeerConnectivity
import Network
import dnssd

let goToRolePickerController = "goToRolePickerController"
let service: String = "RemoteCam"
let userDefaultsPeerId = "peerID"
let userDefaultsSpeedRunScanning = "speedrunscanning"
let remoteShutterUrl = "https://apps.apple.com/us/app/remote-shutter/id633274861"

func generateQRCode(_ string: String) -> UIImage? {
    let data = string.data(using: String.Encoding.utf8)

    if let filter = CIFilter(name: "CIQRCodeGenerator") {
        filter.setValue(data, forKey: "inputMessage")
        let transform = CGAffineTransform(scaleX: 3, y: 3)

        if let output = filter.outputImage?.transformed(by: transform) {
            return UIImage(ciImage: output)
        }
    }
    return nil
}

class DeviceScannerPlaceholder: UITableViewCell {
    @IBOutlet weak var shareButton: UIButton!
    @IBOutlet weak var goToSettings: UIButton!
    @IBOutlet weak var qrCode: UIImageView!
}

public class DeviceScannerViewController: UIViewController {
    
    @IBOutlet var tableView: UITableView!    

    lazy var qrCodeImage = {
        generateQRCode(remoteShutterUrl)
    }()

    var peerID: MCPeerID = MCPeerID(displayName: "null")
    
    var connectedPeers: [MCPeerID] = []
    
    // Add state tracking
    var isScanning: Bool = false
    var hasLocalNetworkAccess: Bool = true
    var hasScanningError: Bool = false
    
    // Modern Swift UserDefaults property
    var speedRunScanning: Bool {
        get {
            UserDefaults.standard.bool(forKey: userDefaultsSpeedRunScanning)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: userDefaultsSpeedRunScanning)
            // Update UI when flag changes
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        }
    }
    
    lazy var splash = {
        CoolActivityIndicator(currentController: self)
    }()
    
    // Add network browser for checking local network access
    var networkBrowser: NWBrowser?
    
    lazy var scanner: MCNearbyServiceBrowser = {
        if let data = UserDefaults.standard.data(forKey: userDefaultsPeerId),
           let id = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? MCPeerID {
              self.peerID = id
        } else {
          let peerID = MCPeerID(displayName: UIDevice.current.name)
          let data = try? NSKeyedArchiver.archivedData(
                withRootObject: peerID, requiringSecureCoding: false)
          UserDefaults.standard.set(data, forKey: userDefaultsPeerId)
          self.peerID = peerID
        }
        let browser =  MCNearbyServiceBrowser(peer: self.peerID, serviceType: service)
        browser.delegate = self
        return browser
    }()
    
        
    let remoteCamSession: ActorRef! = RemoteCamSystem.shared.actorOf(clz: RemoteCamSession.self, name: "RemoteCam Session")

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.remoteCamSession ! SetViewCtrl(ctrl: self)
        self.setupStyle()
        tableView.delegate = self
        tableView.dataSource = self
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.isNavigationBarHidden = false
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.remoteCamSession ! Disconnect()
        
        // Reload table data in case user returned from system permission dialog
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
        
        // Check if user has successfully found peers before (speed run mode)
        if speedRunScanning {
            // Auto-start scanning for experienced users
            checkLocalNetworkAccessAndStartScanning()
        }
        // First-time users will see the button and educational flow
    }
    
    public override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let backItem = UIBarButtonItem()
        backItem.title = NSLocalizedString("Disconnect", comment: "")
        navigationItem.backBarButtonItem = backItem
    }
    
    func setupStyle() {
        navigationController?.navigationBar.prefersLargeTitles = true
        self.navigationItem.title = NSLocalizedString("Scan for devices", comment: "")
        self.navigationItem.prompt = NSLocalizedString("You need at least 2 devices running remote shutter", comment: "")
    }
    
    func startScanning() {
        splash.stopAnimating()
        connectedPeers.removeAll()
        isScanning = true
        hasScanningError = false  // Clear error state when starting new scan
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
        scanner.stopBrowsingForPeers()
        scanner.startBrowsingForPeers()
    }
    
    func stopScanning() {
        splash.stopAnimating()
        connectedPeers.removeAll()
        isScanning = false
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
        scanner.stopBrowsingForPeers()
    }
    
    @IBAction func startScanningDevices() {
        showScanningPermissionAlert()
    }
    
    func showScanningPermissionAlert() {
        let alert = UIAlertController(
            title: NSLocalizedString("Scan for Nearby Devices", comment: ""),
            message: NSLocalizedString("Remote Shutter needs to scan for other devices on your local network to establish a connection. This allows you to use one device as a camera and another as a remote control.", comment: ""),
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Not Now", comment: ""),
            style: .cancel,
            handler: { _ in
                // Reload table when "Not Now" is tapped
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
            }
        ))
        
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Start Scanning", comment: ""),
            style: .default,
            handler: { _ in
                self.checkLocalNetworkAccessAndStartScanning()
                // Reload table when "Start Scanning" is tapped
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
            }
        ))
        
        present(alert, animated: true) {
            // Reload table after scanning permission alert is presented
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        }
    }
    
    func checkLocalNetworkAccessAndStartScanning() {
        // Use Bonjour to check local network access
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
                        print("DNS error code: \(dnsCode)")
                        if dnsCode == Int(kDNSServiceErr_PolicyDenied) {
                            // No local network access - reset speed run mode and set error state
                            self?.speedRunScanning = false
                            self?.hasLocalNetworkAccess = false
                            self?.hasScanningError = true
                            self?.showLocalNetworkAccessDeniedAlert()
                            return
                        }
                    }
                    // Other waiting states - continue with scanning, clear error state
                    self?.hasLocalNetworkAccess = true
                    self?.hasScanningError = false
                    self?.startActualScanning()
                case .ready:
                    print("Network browser ready")
                    // Network access is available - clear error state
                    self?.hasLocalNetworkAccess = true
                    self?.hasScanningError = false
                    self?.startActualScanning()
                case .failed(let error):
                    print("Network browser failed: \(error)")
                    // Permission denied - likely local network access denied
                    self?.speedRunScanning = false
                    self?.hasLocalNetworkAccess = false
                    self?.hasScanningError = true
                    self?.showLocalNetworkAccessDeniedAlert()
                default:
                    print("Network browser state: \(state)")
                    break
                }
            }
        }
        
        networkBrowser?.start(queue: .main)
        
        // Stop the browser after a short check
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.networkBrowser?.cancel()
        }
    }
    
    func startActualScanning() {
        self.remoteCamSession ! UICmd.StartScanning(sender: nil)
        startScanning()
    }
    
    func showLocalNetworkAccessDeniedAlert() {
        let alert = UIAlertController(
            title: NSLocalizedString("Local Network Access Required", comment: ""),
            message: NSLocalizedString("Remote Shutter needs access to your local network to find other devices. Please grant access in Settings.", comment: ""),
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Cancel", comment: ""),
            style: .cancel,
            handler: { _ in
                // Reload table when "Cancel" is tapped
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
            }
        ))
        
        alert.addAction(UIAlertAction(
            title: NSLocalizedString("Open Settings", comment: ""),
            style: .default,
            handler: { _ in
                self.goToAppSettings()
            }
        ))
        
        present(alert, animated: true) {
            // Reload table after local network access alert is presented
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        }
    }
    
    @IBAction func goToRolePicker() {
        self.performSegue(withIdentifier: goToRolePickerController, sender: self)
    }
    
    @IBAction func goToAppSettings() {
        goToSettings()
    }
    
    @IBAction func shareAppLink() {
        let items = [String(format:NSLocalizedString("call_to_download", comment: ""), remoteShutterUrl)]
        let activityViewController = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activityViewController.excludedActivityTypes = [.airDrop]
        // This code is required to support iPad and iPhone
        if let popoverController = activityViewController.popoverPresentationController {
            popoverController.sourceRect = CGRect(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2, width: 0, height: 0)
            popoverController.sourceView = self.view
            popoverController.permittedArrowDirections = UIPopoverArrowDirection(rawValue: 0)
        }
        self.present(activityViewController, animated: true, completion: nil)
    }
    
    deinit {
        print("deinit DeviceScanners")
        networkBrowser?.cancel()
        remoteCamSession ! Actor.Harakiri(sender: nil)
    }
}

extension DeviceScannerViewController: UITableViewDataSource, UITableViewDelegate {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        connectedPeers.count > 0 ? connectedPeers.count : 1
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if (connectedPeers.count > 0) {
            let cell = UITableViewCell()
            cell.textLabel?.text = connectedPeers[indexPath.row].displayName
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "instructions") as! DeviceScannerPlaceholder
            cell.qrCode.image = qrCodeImage
            
            // If no local network access, hide scanning buttons and only show settings
            if !hasLocalNetworkAccess {
                cell.shareButton.isHidden = true
                cell.goToSettings.isHidden = false
            } else {
                // Configure start scanning button when network access is available
                cell.shareButton.isHidden = false
                if !isScanning {
                    cell.shareButton.setTitle(NSLocalizedString("Start Scanning Devices", comment: ""), for: .normal)
                    cell.shareButton.removeTarget(nil, action: nil, for: .allEvents)
                    cell.shareButton.addTarget(self, action: #selector(startScanningDevices), for: .touchUpInside)
                    cell.shareButton.styleButton(
                        backgroundColor: UIColor.systemGreen,
                        borderColor: UIColor.clear,
                        textColor: UIColor.white
                    )
                } else {
                    cell.shareButton.setTitle(NSLocalizedString("Stop Scanning", comment: ""), for: .normal)
                    cell.shareButton.removeTarget(nil, action: nil, for: .allEvents)
                    cell.shareButton.addTarget(self, action: #selector(stopScanningDevices), for: .touchUpInside)
                    cell.shareButton.styleButton(
                        backgroundColor: UIColor.systemRed,
                        borderColor: UIColor.clear,
                        textColor: UIColor.white
                    )
                }
                cell.shareButton.setNeedsDisplay()
                
                // Configure settings button - only show when there's a scanning error
                if #available(iOS 14.0, *) {
                    cell.goToSettings.isHidden = !hasScanningError
                } else {
                    cell.goToSettings.isHidden = true
                }
            }
            
            // Always configure settings button styling when visible
            cell.goToSettings.styleButton(
                backgroundColor: UIColor.systemGray,
                borderColor: UIColor.clear,
                textColor: UIColor.white
            )
            cell.goToSettings.setNeedsDisplay()
            return cell
        }
    }
    
    @objc func stopScanningDevices() {
        stopScanning()
        self.remoteCamSession ! Disconnect()
    }
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if (connectedPeers.count == 0) {
            return
        }
        let peer = connectedPeers[indexPath.row]
        remoteCamSession ! ConnectToDevice(peer: peer, sender: nil)
    }
    
    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if !isScanning {
            if hasScanningError {
                return NSLocalizedString("SCANNING ERROR - CHECK NETWORK SETTINGS", comment: "")
            } else {
                return NSLocalizedString("TAP THE GREEN BUTTON TO GET STARTED", comment: "")
            }
        } else {
            return NSLocalizedString("SEARCHING FOR NEARBY DEVICES...", comment: "")
        }
    }
}

extension DeviceScannerViewController: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        connectedPeers.append(peerID)
        
        // Enable speed run scanning for future visits - user has successfully found a peer
        speedRunScanning = true
        
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
    
    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        connectedPeers = connectedPeers.filter { (peer) -> Bool in peer != peerID }
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
    
    public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("Browser failed to start browsing: \(error.localizedDescription)")
        
        // Reset speed run mode and set error state when scanning fails
        speedRunScanning = false
        hasScanningError = true
        
        DispatchQueue.main.async {
            self.stopScanning()
            
            // Show error alert to user
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
            
            self.present(alert, animated: true) {
                // Reload table after scanning error alert is presented
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
            }
        }
    }
}

