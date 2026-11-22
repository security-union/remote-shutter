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
    /// 3–4 form a 2×2, 5–9 a 3×3 (8 cameras leave the last cell empty).
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

    /// Gap between grid cells, and the wall's inset from the screen edge.
    static let gridSpacing: CGFloat = 4
    static let gridPadding: CGFloat = 8

    /// One grid cell's size for `cameraCount` cameras in a `viewport`: the
    /// columns split the width, the rows split the height, so the whole wall
    /// always fits the window. The grid view sizes its cells from this.
    static func gridCellSize(cameraCount: Int, in viewport: CGSize) -> CGSize {
        let columns = CGFloat(gridColumnCount(cameraCount: cameraCount))
        let rows = CGFloat(gridRowCount(cameraCount: cameraCount))
        let width = (viewport.width - gridPadding * 2 - gridSpacing * (columns - 1)) / columns
        let height = (viewport.height - gridPadding * 2 - gridSpacing * (rows - 1)) / rows
        return CGSize(width: max(1, width), height: max(1, height))
    }

    /// The grid toggle is offered only when there is more than one camera —
    /// with a single camera the focus view already is the whole screen.
    static func showsGridToggle(cameraCount: Int) -> Bool {
        cameraCount > 1
    }
}

// MARK: - Rig tray

/// Which tiles the rig settings tray shows per capture mode: photo settings
/// never show in video mode and vice versa. Rig quality stays one tile (the intersection cycle carries both
/// resolution and frame rate), so video mode has no separate frame-rate tile.
/// Whether the rig tray is presented as a real sheet. A system sheet brings
/// the grab handle, the rubber-banding and the drag-to-dismiss for free, but
/// only where both halves hold: `presentationDetents` exists (iOS 16), and a
/// sheet is the right shape for the platform. On Mac Catalyst it is not — a
/// sheet there is a modal card bolted to the window, where the overlay is
/// dismissed by clicking the viewfinder, which is what a pointer expects.
enum RigTrayPresentation {
    static var style: TrayPresentation {
        #if targetEnvironment(macCatalyst)
        return .overlay
        #else
        if #available(iOS 16.0, *) { return .sheet }
        return .overlay
        #endif
    }
}

enum RigTray {

    /// `standbyAvailable` omits (not dims) the standby tile, as the 1:1 tray
    /// does — a rig with no standby-capable camera has nothing to offer.
    /// Format/HDR stay listed when blocked: the intersection model greys them
    /// and names the blocking camera in the footnote instead. Aspect, like the
    /// 1:1 tray's, shows in both modes — every camera can crop.
    static func items(mode: MonitorMode, standbyAvailable: Bool,
                      exposureAvailable: Bool = false) -> [MonitorTrayItem] {
        var items: [MonitorTrayItem] = [.timer, .aspect]

        switch mode {
        case .video:
            items.append(.resolution)
        case .photo, .portrait:
            items.append(contentsOf: [.format, .hdr])
        }

        if exposureAvailable { items.append(.exposure) }
        if standbyAvailable { items.append(.cameraStandby) }
        items.append(.settings)
        items.append(.help)
        return items
    }
}
