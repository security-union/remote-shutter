//
//  CaptureSyncMetadata.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 2026.
//  Copyright © 2026 Security Union. All rights reserved.
//

import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Alignment metadata attached to every clip and photo captured in a multicam
/// director session. Each camera saves full-res media locally; these fields
/// are what let any editor (CapCut, FCP, Resolve) line the angles up without
/// the files ever leaving the phones.
///
/// The `anchorMillis` timestamp is the scheduled fire time on the *director's*
/// clock, so it is identical across all N cameras' clips for one capture —
/// that shared value is the alignment key. `clockOffsetMillis`/
/// `roundTripMillis` record how good this camera's clock estimate was when it
/// fired (a quality hint, not part of alignment).
struct CaptureSyncMetadata: Codable, Equatable {
    /// One per multicam rig session (director generates it).
    let sessionID: String
    /// One per shutter press / record start, shared by every camera in the rig.
    let captureID: String
    /// Stable 1-based index of this camera in the rig, for humans and filenames.
    let cameraIndex: Int
    /// Scheduled fire time in ms on the director's clock — the alignment key.
    let anchorMillis: UInt64
    /// This camera's estimated clock offset vs the director when it fired (ms).
    let clockOffsetMillis: Int64
    /// RTT of the offset estimate (ms); smaller = tighter sync.
    let roundTripMillis: Int64

    /// QuickTime metadata keys, reverse-DNS in the `mdta` keyspace.
    enum QuickTimeKey {
        static let anchor = "com.remoteshutter.syncAnchorMs"
        static let capture = "com.remoteshutter.captureId"
        static let session = "com.remoteshutter.sessionId"
        static let offset = "com.remoteshutter.clockOffsetMs"
    }

    /// `RS_<sess>_<cap>_cam<k>` — groups one capture's files across cameras
    /// when they land in a shared folder or an editor's media bin. Uses the
    /// first UUID group so names stay readable.
    var filenamePrefix: String {
        "RS_\(Self.shortID(sessionID))_\(Self.shortID(captureID))_cam\(cameraIndex)"
    }

    /// Items for `AVAssetWriter.metadata` so the values travel inside the
    /// .mov itself and survive export/AirDrop.
    func quickTimeMetadataItems() -> [AVMetadataItem] {
        [
            Self.item(key: QuickTimeKey.anchor, value: NSNumber(value: anchorMillis)),
            Self.item(key: QuickTimeKey.capture, value: captureID as NSString),
            Self.item(key: QuickTimeKey.session, value: sessionID as NSString),
            Self.item(key: QuickTimeKey.offset, value: NSNumber(value: clockOffsetMillis)),
        ]
    }

    /// JSON blob for the photo path (EXIF UserComment) and the Documents
    /// sidecar. Sorted keys so output is deterministic and testable.
    func jsonString() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func fromJSONString(_ string: String) -> CaptureSyncMetadata? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CaptureSyncMetadata.self, from: data)
    }

    /// Re-encode `imageData` with this shot's sync fields embedded in EXIF, so
    /// the alignment travels inside the photo itself (survives export/AirDrop):
    /// the JSON in `UserComment`, and the anchor instant in
    /// `DateTimeOriginal`/`SubSecTimeOriginal`. Format (JPEG/HEIC) is preserved.
    /// Returns the original data unchanged if re-encoding isn't possible, so a
    /// stamping failure never costs the user the photo.
    func stamped(_ imageData: Data) -> Data {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let type = CGImageSourceGetType(source) else { return imageData }

        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any]) ?? [:]
        var exif = (properties[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]

        if let json = jsonString() {
            exif[kCGImagePropertyExifUserComment] = json
        }
        let anchorSeconds = Double(anchorMillis) / 1000.0
        let date = Date(timeIntervalSince1970: anchorSeconds)
        exif[kCGImagePropertyExifDateTimeOriginal] = Self.exifDateFormatter.string(from: date)
        exif[kCGImagePropertyExifSubsecTimeOriginal] = String(format: "%03d", anchorMillis % 1000)
        properties[kCGImagePropertyExifDictionary] = exif

        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            output, type, 1, nil) else { return imageData }
        CGImageDestinationAddImageFromSource(dest, source, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return imageData }
        return output as Data
    }

    /// A Photos `originalFilename` for this shot, e.g.
    /// `RS_<sess>_<cap>_cam2.heic`. Groups a capture's files across cameras.
    func photoFilename(isHEIC: Bool) -> String {
        "\(filenamePrefix).\(isHEIC ? "heic" : "jpg")"
    }

    /// EXIF wants `yyyy:MM:dd HH:mm:ss` in the local zone.
    private static let exifDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func shortID(_ uuidString: String) -> String {
        String(uuidString.prefix(8)).lowercased()
    }

    private static func item(key: String, value: NSCopying & NSObjectProtocol) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = AVMetadataItem.identifier(forKey: key, keySpace: .quickTimeMetadata)
        item.keySpace = .quickTimeMetadata
        item.key = key as NSString
        item.value = value
        return item
    }
}
