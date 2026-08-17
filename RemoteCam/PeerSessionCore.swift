//
//  PeerSessionCore.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import Foundation
import MPCCompat

/// The mechanics both peer-session actors share — `SessionCoordinator` (camera
/// + 1:1 monitor) and `MulticamController` (director). Only the genuinely
/// identical, behavior-preserving pieces live here; the two actors are largely
/// different *roles* (a camera answers clock pings and streams frames; a
/// director measures pongs and routes by peer), so most of their delegate
/// surface is role-specialization, not duplication, and stays local (see
/// docs/multicam.md).

extension RemoteCmd.OnFrame {
    /// Build the inbox frame message from a transport `SendFrame` and its
    /// source peer. Both actors' `didReceiveFrame` construct it identically.
    convenience init(forwarding frame: RemoteCmd.SendFrame, from peer: MCPeerID) {
        self.init(data: frame.data,
                  sender: nil,
                  peerId: peer,
                  fps: frame.fps,
                  camPosition: frame.camPosition,
                  camOrientation: frame.camOrientation,
                  codec: frame.codec,
                  sequenceNumber: frame.sequenceNumber)
    }
}

extension PeerAppCompatibility {
    /// Whether this build can drive a peer on `remoteShortVersion`. A missing
    /// local version never blames the peer for this device's own malformed
    /// Info.plist. The 1:1 monitor keeps `decide(...)` directly because its UI
    /// reaction needs the full `Verdict`; the director only needs the verdict
    /// here, so it reads through this.
    static func isCompatible(remoteShortVersion: String?) -> Bool {
        guard let local = localVersion else { return true }
        return decide(local: local, remoteShortVersion: remoteShortVersion) == .compatible
    }
}

/// The reconnect *scheduling* mechanic both actors share: after a delay, fire a
/// tick off-actor (each actor's tick then re-browses / re-invites through its
/// own inbox). The find/invite/overlay/state policy is genuinely different
/// between the two — single-peer with a `.reconnecting` state and overlay vs.
/// per-lane status — and stays local.
enum PeerReconnect {
    /// A cancellable one-shot: sleep `delay`, then `fire` unless cancelled.
    /// Returned so a caller that keeps a single retry task can cancel it (the
    /// per-lane caller discards it — its tick self-guards on lane status).
    @discardableResult
    static func scheduleTick(after delay: TimeInterval,
                             _ fire: @escaping @Sendable () -> Void) -> Task<Void, Never> {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            fire()
        }
    }
}
