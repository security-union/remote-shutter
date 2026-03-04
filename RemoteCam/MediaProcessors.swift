//
//  MediaProcessors.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 10/12/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import AVFoundation
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
