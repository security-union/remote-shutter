//
//  GalleryViewController.swift
//  Actors
//
//  Created by Dario Lencina on 11/3/15.
//  Copyright © 2015 dario. All rights reserved.
//

import UIKit
import BFGallery

public class GalleryViewController : BFGalleryViewController {
    
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.title = "Photos"
        self.view.backgroundColor = UIColor.black
        self.tableView.backgroundColor = UIColor.black
        self.tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) //hack
        self.navigationController?.setNavigationBarHidden(false, animated: true)
    }
    
    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if self.isBeingDismissed || self.isMovingFromParent {
            self.navigationController?.setNavigationBarHidden(true, animated: true)
        }
    }
    
}
