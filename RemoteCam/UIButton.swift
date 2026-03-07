//
//  UIButton.swift
//  RemoteShutter
//
//  Created by Griffin Obeid on 12/10/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation

extension UIButton {
    func styleButton(backgroundColor: UIColor, borderColor: UIColor, textColor: UIColor) {
        self.roundCorners([.allCorners], borderRadius: 16.0, borderColor: borderColor, borderWidth: 8.0)
        self.backgroundColor = backgroundColor
        var config = self.configuration ?? UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 0.0, leading: 5.0, bottom: 0.0, trailing: 5.0)
        self.configuration = config
        self.titleLabel?.tintColor = textColor
        self.titleLabel?.font = UIFont.systemFont(ofSize: 18.0, weight: .bold)
    }
}
