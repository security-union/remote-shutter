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

    /// The whole lane snapshot, published as one value — the fields below are
    /// pure reads, so a status change and a badge change coalesce into a single
    /// SwiftUI invalidation (frames are separate, in `FrameDisplayModel`).
    @Published private(set) var info: MulticamLaneInfo

    var status: CameraLink.Status { info.status }
    var isFocused: Bool { info.isFocused }
    var captureOutcome: CaptureOutcome? { info.captureOutcome }
    var isRecording: Bool { info.isRecording }
    var needsQualityRematch: Bool { info.needsQualityRematch }
    var collection: CameraLink.LaneCollectionState { info.collection }
    var canFlipCamera: Bool { info.canFlipCamera }

    /// This lane's own decoder + stall watchdog. The view controller wires its
    /// `onImage` to set `frames.cameraImage`, and its stall/keyframe callbacks
    /// back to the controller for this peer.
    let receiver = FrameStreamReceiver()

    init(info: MulticamLaneInfo) {
        self.peerID = info.peerID
        self.displayName = info.displayName
        self.info = info
    }

    /// Mechanical reconcile: one Equatable compare, one assignment.
    func update(_ info: MulticamLaneInfo) {
        if self.info != info { self.info = info }
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
    @Published var rigSettings = RigSettingsSnapshot()
    /// Whether the rig settings tray is showing.
    @Published var showingRigTray: Bool = false

    var focusedLane: CameraLane? { lanes.first { $0.isFocused } }
    var otherLanes: [CameraLane] { lanes.filter { !$0.isFocused } }

    /// The focused-camera flip button is live only when that camera is linked
    /// and advertises both a front and a back camera.
    var focusedCameraCanFlip: Bool {
        guard let focused = focusedLane else { return false }
        return focused.status == .linked && focused.canFlipCamera
    }

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
                lane.update(info) // one Equatable compare + assignment
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
