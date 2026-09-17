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

/// Moves a finished movie file into the Photos library. Takes ownership of
/// `url`: Photos consumes the file on success, and every other outcome
/// deletes it, so a temp file the transport handed us never leaks. The file
/// is never read into memory — a long 4K take is gigabytes.
enum VideoLibraryImport {
    enum Outcome {
        case saved
        case accessDenied
        case failed(Error?)
    }

    static func move(_ url: URL, originalFilename: String? = nil,
                     completion: @escaping (Outcome) -> Void) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                cleanupFileAt(url)
                completion(.accessDenied)
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = true
                if let originalFilename { options.originalFilename = originalFilename }
                PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: options)
            }, completionHandler: { success, error in
                // `shouldMoveFile` consumes the file only on success; on
                // failure it stays behind, so the importer removes it.
                if !success { cleanupFileAt(url) }
                completion(success ? .saved : .failed(error))
            })
        }
    }
}

func cleanupFileAt(_ url: URL) {
    if FileManager.default.fileExists(atPath: url.path) {
        do {
            try FileManager.default.removeItem(atPath: url.path)
        } catch {
            logWarning("Could not remove file at url: \(url.path)")
        }
    }
}
