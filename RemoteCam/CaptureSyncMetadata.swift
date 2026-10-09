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
    /// The anchor on THIS camera's `SyncClock` (the director added its
    /// offset estimate: `ScheduledStartRecording.fireAtCameraClockMillis`).
    /// The bridge that turns a local frame time into an offset from the
    /// shared anchor. Nil when the scheduler didn't supply it — then no
    /// offset is computed, never guessed.
    var cameraClockAnchorMillis: UInt64?
    /// When this clip's first frame was captured, relative to the anchor, in
    /// ms (positive = the clip starts after the anchor). Recording fires the
    /// moment the command lands, so each camera's clip starts a little
    /// differently; an editor trims each angle by this much and every clip
    /// starts at the shared instant. Nil until the first frame is known.
    var firstFrameOffsetMillis: Int64?

    /// QuickTime metadata keys, reverse-DNS in the `mdta` keyspace.
    enum QuickTimeKey {
        static let anchor = "com.remoteshutter.syncAnchorMs"
        static let capture = "com.remoteshutter.captureId"
        static let session = "com.remoteshutter.sessionId"
        static let offset = "com.remoteshutter.clockOffsetMs"
        static let firstFrameOffset = "com.remoteshutter.firstFrameOffsetMs"
    }

    /// The first frame's offset from the anchor. `firstFrameUptimeNanos` is
    /// the frame's capture time converted to the `SyncClock` domain
    /// (`CaptureClockConversion.uptimeNanos`); rounded to the nearest ms.
    static func firstFrameOffsetMillis(firstFrameUptimeNanos: UInt64,
                                       cameraClockAnchorMillis: UInt64) -> Int64 {
        let frameMillis = (firstFrameUptimeNanos + 500_000) / 1_000_000
        return Int64(bitPattern: frameMillis &- cameraClockAnchorMillis)
    }

    /// A copy with the first frame's offset computed from its capture time,
    /// or unchanged when either side of the subtraction is unknown.
    func withFirstFrame(uptimeNanos: UInt64?) -> CaptureSyncMetadata {
        guard let uptimeNanos, let cameraClockAnchorMillis else { return self }
        var copy = self
        copy.firstFrameOffsetMillis = Self.firstFrameOffsetMillis(
            firstFrameUptimeNanos: uptimeNanos, cameraClockAnchorMillis: cameraClockAnchorMillis)
        return copy
    }

    /// `RS_<sess>_<cap>_cam<k>` — groups one capture's files across cameras
    /// when they land in a shared folder or an editor's media bin. Uses the
    /// first UUID group so names stay readable.
    var filenamePrefix: String {
        "RS_\(Self.shortID(sessionID))_\(Self.shortID(captureID))_cam\(cameraIndex)"
    }

    /// Items for `AVAssetWriter.metadata` (or a movie file output's) so the
    /// values travel inside the .mov itself and survive export/AirDrop. The
    /// first-frame offset rides only once it is known: the asset writer sets
    /// its metadata at the first frame, so its clips carry it; a movie file
    /// output takes metadata before recording starts, so an Editable
    /// Cinematic clip cannot — its offset goes to the JSON sidecar instead.
    func quickTimeMetadataItems() -> [AVMetadataItem] {
        var items = [
            Self.item(key: QuickTimeKey.anchor, value: NSNumber(value: anchorMillis)),
            Self.item(key: QuickTimeKey.capture, value: captureID as NSString),
            Self.item(key: QuickTimeKey.session, value: sessionID as NSString),
            Self.item(key: QuickTimeKey.offset, value: NSNumber(value: clockOffsetMillis)),
        ]
        if let firstFrameOffsetMillis {
            items.append(Self.item(key: QuickTimeKey.firstFrameOffset,
                                   value: NSNumber(value: firstFrameOffsetMillis)))
        }
        return items
    }

    /// Writes `<RS_ prefix>.json` into `directory` — the alignment record for
    /// a clip whose file cannot hold it (see `quickTimeMetadataItems`).
    @discardableResult
    func writeSidecar(in directory: URL) throws -> URL {
        guard let json = jsonString() else {
            throw NSError(domain: "CaptureSyncMetadata", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "sync metadata did not encode"])
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(filenamePrefix).json")
        try Data(json.utf8).write(to: url, options: .atomic)
        return url
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
    /// `RS_<sess>_<cap>_cam2.heic`. Groups a capture's files across cameras.
    func photoFilename(isHEIC: Bool) -> String {
        "\(filenamePrefix).\(isHEIC ? "heic" : "jpg")"
    }

    /// A Photos `originalFilename` for this clip, e.g. `RS_<sess>_<cap>_cam2.mov`.
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

/// Frame times → the `SyncClock` domain. A capture timestamp (a sample's PTS,
/// a movie output's `startPTS`) lives on the session's synchronization clock;
/// `SyncClock` is `DispatchTime` uptime. Both are the host's mach clock
/// underneath, so the conversion is: onto the host time clock, into mach
/// units, into nanoseconds with the same timebase `DispatchTime` uses.
enum CaptureClockConversion {

    /// `time` on `clock` (nil = already host time) as uptime nanoseconds,
    /// or nil when the time is invalid or cannot be converted.
    static func uptimeNanos(of time: CMTime, on clock: CMClock?) -> UInt64? {
        guard time.isValid, time.isNumeric else { return nil }
        let hostClock = CMClockGetHostTimeClock()
        let hostTime = clock.map { CMSyncConvertTime(time, from: $0, to: hostClock) } ?? time
        guard hostTime.isValid, hostTime.isNumeric, hostTime.seconds >= 0 else { return nil }
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS else { return nil }
        return nanos(machUnits: CMClockConvertHostTimeToSystemUnits(hostTime),
                     numer: timebase.numer, denom: timebase.denom)
    }

    /// Mach units → nanoseconds without overflowing on a long uptime.
    static func nanos(machUnits: UInt64, numer: UInt32, denom: UInt32) -> UInt64 {
        guard denom > 0 else { return machUnits }
        let numer = UInt64(numer), denom = UInt64(denom)
        return (machUnits / denom) * numer + (machUnits % denom) * numer / denom
    }
}
