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

    /// The grid toggle is offered only when there is more than one camera —
    /// with a single camera the focus view already is the whole screen.
    static func showsGridToggle(cameraCount: Int) -> Bool {
        cameraCount > 1
    }
}
