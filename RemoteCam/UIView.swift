//
//  UIView.swift
//  RemoteShutter
//
//  Created by Griffin Obeid on 12/18/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation


extension UIView {
    func roundCorners(_ corners: UIRectCorner, borderRadius: CGFloat, borderColor: UIColor, borderWidth: CGFloat) {
        let path = UIBezierPath(roundedRect: self.bounds, byRoundingCorners: corners, cornerRadii: CGSize(width: borderRadius, height: borderRadius))

        let mask = CAShapeLayer()
        mask.path = path.cgPath
        self.layer.mask = mask

        let borderPath = UIBezierPath(roundedRect: self.bounds, byRoundingCorners: corners, cornerRadii: CGSize(width: borderRadius, height:borderRadius))
        let borderLayer = CAShapeLayer()
        borderLayer.path = borderPath.cgPath
        borderLayer.lineWidth = borderWidth
        borderLayer.strokeColor = borderColor.cgColor
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.frame = self.bounds
        self.layer.addSublayer(borderLayer)
    }
    
    func styleEmbeddedView(backgroundColor: UIColor, borderColor: UIColor, textColor: UIColor) {
        self.roundCorners([.allCorners], borderRadius: 16.0, borderColor: borderColor, borderWidth: 8.0)
        self.backgroundColor = backgroundColor
    }
}
