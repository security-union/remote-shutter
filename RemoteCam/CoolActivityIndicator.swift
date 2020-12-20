//
//  CoolActivityIndicator.swift
//   Armore
//
//  Created by Security Union on 18/12/19.
//  Copyright © 2019 Security Union. All rights reserved.
//

import Foundation
import UIKit

public class CoolActivityIndicator {

    weak var currentController: UIViewController?
    let actInd = UIActivityIndicatorView()
    var backgroundColorGray = UIView()

    init(currentController: UIViewController) {
        self.currentController = currentController
    }

    public func startAnimating() {
        guard let controller = currentController else {
            return
        }
        actInd.frame = CGRect(x: 0.0, y: 0.0, width: 40.0, height: 40.0)
        actInd.center = controller.view.center
        actInd.hidesWhenStopped = true
        actInd.style =
                UIActivityIndicatorView.Style.whiteLarge
        if var rect = controller.view.window?.bounds {
            rect.size.height = 1000
            backgroundColorGray = UIView(frame: rect)
            backgroundColorGray.backgroundColor = .gray
            backgroundColorGray.alpha = 0.3
            controller.view.addSubview(backgroundColorGray)

            // set that the user can do nothing while loading
            controller.view.isUserInteractionEnabled = false
            controller.view.addSubview(actInd)
            actInd.startAnimating()
        }
    }

    public func stopAnimating() {
        guard let controller = currentController else {
            return
        }
        controller.view.isUserInteractionEnabled = true
        backgroundColorGray.removeFromSuperview()
        actInd.stopAnimating()
    }

}
