//
//  ErrorViewController.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 9/24/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import UIKit

class ErrorViewController: UIViewController {

    @IBAction func btnOpenSettings(_ sender: Any) {
        if let bundleId = Bundle.main.bundleIdentifier,
           let url = URL(string: "\(UIApplication.openSettingsURLString)&path=LOCATION/\(bundleId)") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
}
