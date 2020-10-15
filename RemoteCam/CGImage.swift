//
//  CGImage.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 10/7/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation

extension CGImage {

    func rotated(by angle: CGFloat) -> CGImage? {
        let angleInRadians = angle * .pi / 180

        let imgRect = CGRect(x: 0, y: 0, width: width, height: height)
        let transform = CGAffineTransform.identity.rotated(by: angleInRadians)
        let rotatedRect = imgRect.applying(transform)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let bmContext = CGContext(
                data: nil,
                width: Int(rotatedRect.size.width),
                height: Int(rotatedRect.size.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
                else {
            return nil
        }

        bmContext.setAllowsAntialiasing(true)
        bmContext.setShouldAntialias(true)
        bmContext.interpolationQuality = .high
        bmContext.translateBy(x: rotatedRect.size.width * 0.5, y: rotatedRect.size.height * 0.5)
        bmContext.rotate(by: angleInRadians)
        let drawRect = CGRect(
                origin: CGPoint(x: -imgRect.size.width * 0.5, y: -imgRect.size.height * 0.5),
                size: imgRect.size)
        bmContext.draw(self, in: drawRect)

        guard let rotatedImage = bmContext.makeImage() else {
            return nil
        }

        return rotatedImage
    }
}
