//
//  PeerCompatibility.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union. All rights reserved.
//

import Foundation

/// A semantic version, parsed from a version string.
///
/// Ordering is lexicographic over (major, minor, patch); prerelease and build
/// metadata are ignored, so `1.2.3-beta.1` compares equal to `1.2.3`.
struct SemanticVersion: Equatable, Comparable, CustomStringConvertible, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init(major: Int, minor: Int = 0, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses `MAJOR[.MINOR[.PATCH]]`, tolerating a `-prerelease` or `+build`
    /// suffix and extra dot components (both discarded). Returns nil unless
    /// every component it reads is a non-negative integer — a version it cannot
    /// fully trust is no version at all, so callers get one unambiguous
    /// "unparseable" signal instead of a silently wrong number.
    init?(parsing raw: String) {
        // Drop prerelease/build metadata: "9.1.0-beta.2+ci" -> "9.1.0".
        let core = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix { $0 != "-" && $0 != "+" }
        guard !core.isEmpty else { return nil }

        let fields = core.split(separator: ".", omittingEmptySubsequences: false)
        var numbers: [Int] = []
        for field in fields.prefix(3) {
            guard let value = Int(field), value >= 0 else { return nil }
            numbers.append(value)
        }
        guard let major = numbers.first else { return nil }

        self.major = major
        self.minor = numbers.count > 1 ? numbers[1] : 0
        self.patch = numbers.count > 2 ? numbers[2] : 0
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// Whether two devices can hold a session, decided from the app version each
/// one announces in its `PeerBecameCamera`/`PeerBecameMonitor` handshake.
///
/// The rule is semver on the **app** version: a differing major means the two
/// devices cannot talk; minor and patch differences are always fine. Individual
/// features that only newer builds understand stay gated separately (see
/// `VP9PreviewCompatibility`) — this policy answers "can we talk at all", not
/// "which features do we share".
///
/// Consequence to keep in mind when bumping the marketing version: because the
/// gate reads `CFBundleShortVersionString`, **raising the major refuses pairing
/// with every device on the previous major.** Ship a major bump only when that
/// is what you mean.
enum PeerAppCompatibility {

    enum Verdict: Equatable {
        /// Same major: talk normally.
        case compatible
        /// The peer is on an older major and must update.
        case peerNeedsUpdate
        /// This device is on an older major and must update.
        case selfNeedsUpdate
        /// The peer announced no version, or one that cannot be parsed — a
        /// build too old to be trusted with this session.
        case unknownPeerVersion
    }

    /// This device's app version, or nil if `CFBundleShortVersionString` is
    /// missing or malformed. Nil means "cannot judge": callers allow the
    /// session rather than blaming the peer for our own bad Info.plist.
    static var localVersion: SemanticVersion? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        else { return nil }
        return SemanticVersion(parsing: raw)
    }

    /// Pure policy: version in, verdict out.
    static func decide(local: SemanticVersion, remoteShortVersion: String?) -> Verdict {
        guard let raw = remoteShortVersion,
              let remote = SemanticVersion(parsing: raw) else {
            return .unknownPeerVersion
        }
        if remote.major == local.major { return .compatible }
        return remote.major < local.major ? .peerNeedsUpdate : .selfNeedsUpdate
    }
}
