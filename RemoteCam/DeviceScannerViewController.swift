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

let goToRolePickerController = "goToRolePickerController"
let service: String = "RemoteCam"
let userDefaultsPeerId = "peerID"
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
    
    lazy var splash = {
        CoolActivityIndicator(currentController: self)
    }()
    
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
    
    var remoteCamSession: ActorRef! = RemoteCamSystem.shared.actorOf(clz: RemoteCamSession.self, name: "RemoteCam Session")
    
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
        self.remoteCamSession ! UICmd.StartScanning(sender: nil)
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
        tableView.reloadData()
        scanner.stopBrowsingForPeers()
        scanner.startBrowsingForPeers()
    }
    
    func stopScanning() {
        splash.stopAnimating()
        connectedPeers.removeAll()
        tableView.reloadData()
        scanner.stopBrowsingForPeers()
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
            cell.shareButton.styleButton(
                backgroundColor: UIColor.systemGray,
                borderColor: UIColor.clear,
                textColor: UIColor.white
            )
            cell.shareButton.setNeedsDisplay()
            cell.goToSettings.styleButton(
                backgroundColor: UIColor.systemGreen,
                borderColor: UIColor.clear,
                textColor: UIColor.white
            )
            cell.goToSettings.setNeedsDisplay()
            if #available(iOS 14.0, *) {
                cell.goToSettings.isHidden = false
            } else {
                cell.goToSettings.isHidden = true
            }
            return cell
        }
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
        return "SEARCHING FOR NEARBY DEVICES..."
    }
}

extension DeviceScannerViewController: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        connectedPeers.append(peerID)
        tableView.reloadData()
    }
    
    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        connectedPeers = connectedPeers.filter { (peer) -> Bool in peer != peerID }
        tableView.reloadData()
    }
}

