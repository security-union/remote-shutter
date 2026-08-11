//
//  MulticamViewModel.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import Combine
import Foundation
import MPCCompat
import SwiftUI

/// One camera's UI state in the director screen. Its `frames` model is
/// isolated exactly like the 1:1 monitor's `FrameDisplayModel`: only this
/// lane's tile observes it, so a 20fps stream from camera B never re-renders
/// camera A's tile or the surrounding chrome.
final class CameraLane: ObservableObject, Identifiable {
    let peerID: MCPeerID
    var id: MCPeerID { peerID }
    let displayName: String

    /// Live preview frames for this lane only (not `@Published` on the parent
    /// view model — see `FrameDisplayModel`).
    let frames = FrameDisplayModel()

    @Published var status: CameraLink.Status
    @Published var isFocused: Bool
    /// How this camera answered the last synced capture — a brief tile badge.
    @Published var captureOutcome: CaptureOutcome?
    /// This camera is rolling in a synced recording — REC badge.
    @Published var isRecording: Bool
    /// This camera can't match the running rig quality — badge + re-match.
    @Published var needsQualityRematch: Bool
    /// Post-take footage collection progress — transfer badge / done / failed.
    @Published var collection: CameraLink.LaneCollectionState

    /// This lane's own decoder + stall watchdog. The view controller wires its
    /// `onImage` to set `frames.cameraImage`, and its stall/keyframe callbacks
    /// back to the controller for this peer.
    let receiver = FrameStreamReceiver()

    init(info: MulticamLaneInfo) {
        self.peerID = info.peerID
        self.displayName = info.displayName
        self.status = info.status
        self.isFocused = info.isFocused
        self.captureOutcome = info.captureOutcome
        self.isRecording = info.isRecording
        self.needsQualityRematch = info.needsQualityRematch
        self.collection = info.collection
    }
}

/// Top-level state for the multicam director screen. Holds the ordered lanes
/// and which one is focused; per-lane frame churn lives in each `CameraLane`.
final class MulticamViewModel: ObservableObject {
    @Published private(set) var lanes: [CameraLane] = []
    @Published var interfaceOrientation: UIInterfaceOrientation = .portrait
    /// A synced photo is in flight — drives the shutter's activity ring.
    @Published var isCapturing: Bool = false
    /// The rig is recording — the shutter becomes a stop button.
    @Published var isRecording: Bool = false
    /// Photo vs video shutter mode.
    @Published var mode: MonitorMode = .photo
    /// Focus (viewfinder + strip) vs grid (monitor wall) layout.
    @Published var displayMode: MulticamDisplayMode = .focus
    /// Cameras discovered but not yet in the rig — the add-camera sheet's list.
    @Published var availablePeers: [MCPeerID] = []
    /// Whether the add-camera sheet is showing.
    @Published var showingAddCamera: Bool = false
    /// Rig-wide settings (timer + quality intersection) for the tray.
    @Published var rigSettings = RigSettingsSnapshot(activeVideoLabel: "Auto")
    /// Whether the rig settings tray is showing.
    @Published var showingRigTray: Bool = false

    var focusedLane: CameraLane? { lanes.first { $0.isFocused } }
    var otherLanes: [CameraLane] { lanes.filter { !$0.isFocused } }

    /// Reconcile against a controller snapshot: add new lanes, drop gone ones,
    /// preserve existing `CameraLane` instances (and their receivers/frames)
    /// so streams are never interrupted by a status change elsewhere.
    ///
    /// Returns the lanes that were newly created, so the view controller can
    /// wire their receivers.
    @discardableResult
    func apply(_ infos: [MulticamLaneInfo]) -> [CameraLane] {
        var existing = Dictionary(uniqueKeysWithValues: lanes.map { ($0.peerID, $0) })
        var created: [CameraLane] = []

        let next: [CameraLane] = infos.map { info in
            if let lane = existing.removeValue(forKey: info.peerID) {
                if lane.status != info.status { lane.status = info.status }
                if lane.isFocused != info.isFocused { lane.isFocused = info.isFocused }
                if lane.captureOutcome != info.captureOutcome { lane.captureOutcome = info.captureOutcome }
                if lane.isRecording != info.isRecording { lane.isRecording = info.isRecording }
                if lane.needsQualityRematch != info.needsQualityRematch { lane.needsQualityRematch = info.needsQualityRematch }
                if lane.collection != info.collection { lane.collection = info.collection }
                return lane
            }
            let lane = CameraLane(info: info)
            created.append(lane)
            return lane
        }

        // Tear down receivers for lanes that went away.
        for gone in existing.values { gone.receiver.invalidate() }

        lanes = next
        return created
    }

    func lane(for peer: MCPeerID) -> CameraLane? {
        lanes.first { $0.peerID == peer }
    }
}
