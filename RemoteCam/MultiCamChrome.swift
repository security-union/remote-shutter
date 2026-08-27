//
//  MultiCamChrome.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import CoreGraphics
import Foundation

/// How the director screen lays out the cameras.
enum MulticamDisplayMode: Equatable {
    /// One focused viewfinder + a thumbnail strip of the others (the default).
    case focus
    /// An equal grid of every camera — the "monitor wall" for checking angles.
    case grid
}

/// Pure layout policy for the multicam director screen, kept out of the views
/// so it is unit-testable without a host (mirrors `MonitorChrome`).
enum MultiCamChrome {

    /// Columns for the grid: a near-square arrangement — 2 cameras sit 2-up,
    /// 3–4 form a 2×2, and it keeps growing by √n for any future larger rig.
    /// One camera has no grid (the focus view fills the screen).
    static func gridColumnCount(cameraCount: Int) -> Int {
        guard cameraCount > 1 else { return 1 }
        return max(1, Int(ceil(Double(cameraCount).squareRoot())))
    }

    /// Rows for the grid at `gridColumnCount` columns — with the columns this
    /// bounds the wall to the viewport: every cell's height is viewport/rows,
    /// so the grid never outgrows the window.
    static func gridRowCount(cameraCount: Int) -> Int {
        guard cameraCount > 1 else { return 1 }
        let columns = gridColumnCount(cameraCount: cameraCount)
        return Int(ceil(Double(cameraCount) / Double(columns)))
    }

    /// The grid toggle is offered only when there is more than one camera —
    /// with a single camera the focus view already is the whole screen.
    static func showsGridToggle(cameraCount: Int) -> Bool {
        cameraCount > 1
    }
}

// MARK: - Rig tray

/// Which tiles the rig settings tray shows — the multicam mirror of
/// `MonitorTray.items`, so the director offers the same settings per capture
/// mode as the 1:1 monitor: photo settings never show in video mode and vice
/// versa. Rig quality stays one tile (the intersection cycle carries both
/// resolution and frame rate), so video mode has no separate frame-rate tile.
enum RigTray {

    /// `standbyAvailable` omits (not dims) the standby tile, as the 1:1 tray
    /// does — a rig with no standby-capable camera has nothing to offer.
    /// Format/HDR stay listed when blocked: the intersection model greys them
    /// and names the blocking camera in the footnote instead. Aspect, like the
    /// 1:1 tray's, shows in both modes — every camera can crop.
    static func items(mode: MonitorMode, standbyAvailable: Bool,
                      proTiles: [MonitorTrayItem] = []) -> [MonitorTrayItem] {
        var items: [MonitorTrayItem] = [.timer, .aspect]

        switch mode {
        case .video:
            items.append(.resolution)
        case .photo:
            items.append(contentsOf: [.format, .hdr])
        }

        // Pro controls drive the FOCUSED camera (like torch and zoom), so the
        // tiles follow that camera's advertised capabilities — same slot as
        // the 1:1 tray, ahead of standby.
        items.append(contentsOf: proTiles)
        if standbyAvailable { items.append(.cameraStandby) }
        items.append(.settings)
        items.append(.help)
        return items
    }
}

extension MonitorMode {
    /// The camera-side vocabulary for `RemoteCmd.SyncMonitorSettings`.
    var recordingMode: RecordingMode {
        switch self {
        case .photo: return .Photo
        case .video: return .Video
        }
    }
}
