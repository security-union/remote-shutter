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
    /// The camera's advertised name, for filenames. Nil when unknown.
    var cameraName: String? = nil

    /// QuickTime metadata keys, reverse-DNS in the `mdta` keyspace.
    enum QuickTimeKey {
        static let anchor = "com.remoteshutter.syncAnchorMs"
        static let capture = "com.remoteshutter.captureId"
        static let session = "com.remoteshutter.sessionId"
        static let offset = "com.remoteshutter.clockOffsetMs"
    }

    /// `cam<k>_<name>_RS_<sess>_<cap>`: the camera first, so sorting a folder
    /// by name groups every file from one angle (one editor track); the
    /// shared session and capture IDs then line the angles up. Uses the
    /// first UUID group so names stay readable.
    var filenamePrefix: String {
        let ids = "RS_\(Self.shortID(sessionID))_\(Self.shortID(captureID))"
        let name = cameraName.map(Self.filenameComponent) ?? ""
        return name.isEmpty ? "cam\(cameraIndex)_\(ids)" : "cam\(cameraIndex)_\(name)_\(ids)"
    }

    /// A device name made safe for a filename on any desktop: letters and
    /// digits kept, every other run of characters becomes one hyphen.
    static func filenameComponent(_ name: String) -> String {
        var result = ""
        var pendingHyphen = false
        for scalar in name.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingHyphen && !result.isEmpty { result.append("-") }
                pendingHyphen = false
                result.unicodeScalars.append(scalar)
            } else {
                pendingHyphen = true
            }
        }
        return String(result.prefix(DeviceNamePreference.maxLength))
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
    /// the alignment travels inside the photo itself (survives export/AirDrop).
    /// The alignment key (`anchorMillis`) rides in `UserComment` as opaque JSON;
    /// `DateTimeOriginal`/`SubSecTimeOriginal` are the camera's **wall clock at
    /// capture** (`capturedAt`) — EXIF's meaning is "when the photo was taken",
    /// and `anchorMillis` is monotonic uptime, not a wall-clock date. Format
    /// (JPEG/HEIC) is preserved. Returns the original data unchanged if
    /// re-encoding isn't possible, so a stamping failure never costs the photo.
    func stamped(_ imageData: Data, capturedAt: Date = Date()) -> Data {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let type = CGImageSourceGetType(source) else { return imageData }

        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any]) ?? [:]
        var exif = (properties[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]

        if let json = jsonString() {
            exif[kCGImagePropertyExifUserComment] = json
        }
        exif[kCGImagePropertyExifDateTimeOriginal] = Self.exifDateFormatter.string(from: capturedAt)
        let subsec = Int((capturedAt.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)) * 1000)
        exif[kCGImagePropertyExifSubsecTimeOriginal] = String(format: "%03d", subsec)
        properties[kCGImagePropertyExifDictionary] = exif

        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            output, type, 1, nil) else { return imageData }
        CGImageDestinationAddImageFromSource(dest, source, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return imageData }
        return output as Data
    }

    /// A Photos `originalFilename` for this shot, e.g.
    /// `cam2_Drums_RS_<sess>_<cap>.heic`.
    func photoFilename(isHEIC: Bool) -> String {
        "\(filenamePrefix).\(isHEIC ? "heic" : "jpg")"
    }

    /// A Photos `originalFilename` for this clip, e.g. `cam2_Drums_RS_<sess>_<cap>.mov`.
    func videoFilename() -> String { "\(filenamePrefix).mov" }

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
