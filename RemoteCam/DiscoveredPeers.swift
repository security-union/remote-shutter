//
//  DiscoveredPeers.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import MPCCompat

/// The list of peers a browser has discovered, with the name-resolution rule
/// both scanners need in one place: the main `DeviceScannerViewModel` and the
/// multicam director's add-camera flow (`MulticamController.available`).
///
/// Peer identity under Stormo is key-hash-only, so a re-found peer compares
/// equal but may carry an enriched display name — the transport re-delivers a
/// peer once TXT enrichment replaces the hash-prefix placeholder
/// (e.g. "QmQqML3n…" → "iPad"). `upsert` updates in place so the resolved name
/// reaches the UI; dropping the re-delivery freezes the placeholder, which was
/// the add-camera sheet's raw-id bug.
struct DiscoveredPeers: Equatable {
    private(set) var peers: [MCPeerID] = []

    /// The resolution rule itself, over any peer list — so a caller that keeps
    /// its own `@Published [MCPeerID]` (the scanner view model) shares the exact
    /// same in-place upgrade as this value type (the director's list).
    static func upsert(_ peers: inout [MCPeerID], _ peer: MCPeerID) {
        if let index = peers.firstIndex(of: peer) {
            peers[index] = peer
        } else {
            peers.append(peer)
        }
    }

    /// Add a newly discovered peer, or replace an already-present one in place
    /// with its re-delivered (name-upgraded) identity.
    mutating func upsert(_ peer: MCPeerID) {
        Self.upsert(&peers, peer)
    }

    /// Drop a peer; returns whether it was present.
    @discardableResult
    mutating func remove(_ peer: MCPeerID) -> Bool {
        guard let index = peers.firstIndex(of: peer) else { return false }
        peers.remove(at: index)
        return true
    }

    mutating func removeAll() { peers.removeAll() }

    func contains(_ peer: MCPeerID) -> Bool { peers.contains(peer) }
}
