//
//  CaptureSyncMetadata.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 2026.
//  Copyright © 2026 Security Union. All rights reserved.
//

import AVFoundation
import Foundation

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
