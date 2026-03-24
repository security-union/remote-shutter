//
//  CameraRegistry.swift
//  RemoteShutter
//
//  Tracks connected camera peers for multi-camera support.
//  Owned by RemoteCamSession — only accessed from the actor's serial mailbox.
//

import Foundation
import MultipeerConnectivity

enum CameraStatus {
    case connected
    case ready
    case capturing
    case disconnected
}

struct CameraState {
    let peerId: MCPeerID
    let displayName: String
    var status: CameraStatus
}

class CameraRegistry {

    static let maxCameras = 7

    // MARK: - Connected cameras

    private(set) var cameras: [MCPeerID: CameraState] = [:]
    var selectedCamera: MCPeerID?

    var allPeers: [MCPeerID] { Array(cameras.keys) }
    var count: Int { cameras.count }
    var isEmpty: Bool { cameras.isEmpty }
    var isFull: Bool { cameras.count >= Self.maxCameras }

    // MARK: - Discovered but not-yet-connected cameras

    private(set) var availableCameras: [MCPeerID] = []

    func addAvailable(peer: MCPeerID) {
        guard !availableCameras.contains(peer), !contains(peer: peer) else { return }
        availableCameras.append(peer)
    }

    func removeAvailable(peer: MCPeerID) {
        availableCameras.removeAll { $0 == peer }
    }

    // MARK: - Connected cameras

    @discardableResult
    func add(peer: MCPeerID) -> Bool {
        guard cameras[peer] == nil, !isFull else { return false }
        cameras[peer] = CameraState(
            peerId: peer,
            displayName: peer.displayName,
            status: .connected
        )
        removeAvailable(peer: peer)
        if selectedCamera == nil {
            selectedCamera = peer
        }
        return true
    }

    func remove(peer: MCPeerID?) {
        guard let peer = peer else { return }
        cameras.removeValue(forKey: peer)
        if selectedCamera == peer {
            selectedCamera = cameras.keys.first
        }
    }

    func updateStatus(peer: MCPeerID, status: CameraStatus) {
        cameras[peer]?.status = status
    }

    func contains(peer: MCPeerID) -> Bool {
        cameras[peer] != nil
    }

    func reset() {
        cameras.removeAll()
        availableCameras.removeAll()
        selectedCamera = nil
    }
}
