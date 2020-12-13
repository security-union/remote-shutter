//
//  ConnectViewController.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 11/30/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import UIKit

let goToRolePickerViewControllerSegue = "goToRolePickerViewControllerSegue"
let remoteShutterUrl = "https://apps.apple.com/us/app/remote-shutter/id633274861"

class ConnectViewController: UIViewController {
    @IBOutlet weak var shareButton: UIButton!
    @IBOutlet weak var scanForDevices: UIButton!
    @IBOutlet weak var qrCode: UIImageView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupStyle()
        qrCode.image = generateQRCode(remoteShutterUrl)
    }
    
    func setupStyle() {
        scanForDevices.styleButton(
            backgroundColor: UIColor.systemGreen,
            borderColor: UIColor.clear,
            textColor: UIColor.white
        )
        shareButton.styleButton(
            backgroundColor: UIColor.systemGray,
            borderColor: UIColor.clear,
            textColor: UIColor.white
        )
    }
    
    @IBAction func goToRolePickerViewController() {
        self.performSegue(withIdentifier: goToRolePickerViewControllerSegue, sender: self)
    }
        
    @IBAction func showHelp() {
        let alert = UIAlertController(title: NSLocalizedString("help", comment: ""), message: "")
        alert.simpleOkAction()
        alert.show(true)
    }
    
    @IBAction func shareAppLink() {
        let items = [String(format:NSLocalizedString("call_to_download", comment: ""), remoteShutterUrl)]
        let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
        present(ac, animated: true)
    }

}

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

