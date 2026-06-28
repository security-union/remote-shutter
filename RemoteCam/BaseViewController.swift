//
//  DeviceViewController.swift
//  Actors
//
//  Created by Dario Lencina on 11/1/15.
//  Copyright © 2015 dario. All rights reserved.
//

import UIKit

public func showError(_ error: String) {
    ^{
        let alert = UIAlertController(
            title: NSLocalizedString("Error", comment: ""),
            message: error
        )
        alert.simpleOkAction()
        alert.show(true)
    }
}

/// Base view controller formerly used for ad integration.
/// Kept as a superclass so existing subclasses (MonitorViewController) compile unchanged.
public class iAdViewController: UIViewController {

    override public func viewDidLoad() {
        super.viewDidLoad()
    }
}
