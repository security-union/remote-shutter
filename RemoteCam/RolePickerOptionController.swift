//
//  RolePickerOptionController.swift
//  RemoteShutter
//
//  Created by Griffin Obeid on 12/18/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation


public class RolePickerOptionController: UIViewController {
    @IBOutlet public var titleLabel: UILabel!
    @IBOutlet public var descriptionLabel: UILabel!
    @IBOutlet public var tipLabel: UILabel!
    @IBOutlet public var image: UIImageView!
    @IBOutlet public var colorfulButton: UIButton!
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        self.setupStyle()
    }
    
    func setupStyle() {
        titleLabel.font = UIFont.boldSystemFont(ofSize: 24)
        descriptionLabel.font = UIFont.boldSystemFont(ofSize: 12)
        tipLabel.font = UIFont.systemFont(ofSize: 12)
        colorfulButton.styleButton(backgroundColor: UIColor.systemBlue, borderColor: UIColor.clear, textColor: UIColor.white)
    }
}
