//
//  MediaProcessors.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 10/12/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import Theater
import AVFoundation
import AssetsLibrary
import Photos

func movieUrl() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory().appending(tempFile))
}

func cleanupFileAt(_ url: URL) {
    if FileManager.default.fileExists(atPath: url.path) {
        do {
            try FileManager.default.removeItem(atPath: url.path)
        } catch {
            print("Could not remove file at url: \(url.path)")
        }
    }
}

func imageFromSampleBuffer(sampleBuffer: CMSampleBuffer) -> UIImage? {
    if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
        CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
        let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            return nil
        }

        let quartzImage = context.makeImage()
        CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))

        if let quartzImage = quartzImage {
            let image = UIImage(cgImage: quartzImage)
            return image
        }
    }
    return nil
}
