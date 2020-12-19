//
//  UIViewController.swift
//  RemoteShutter
//
//  Created by Griffin Obeid on 12/18/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation


extension UIViewController {
    func add(_ child: UIViewController) {
        addChild(child)
        view.addSubview(child.view)
        child.didMove(toParent: self)
    }

    func remove() {
        // Just to be safe, we check that this view controller
        // is actually added to a parent before removing it.
        guard parent != nil else {
            return
        }

        willMove(toParent: nil)
        view.removeFromSuperview()
        removeFromParent()
    }
}

