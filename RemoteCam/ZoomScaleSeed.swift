//
//  ZoomScaleSeed.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import CoreGraphics

/// The single home for the zoom-range math both camera-control paths share:
/// the 1:1 monitor (`MonitorViewModel`/`MonitorPresenter`) and the multicam
/// director (`MulticamController`). Pure — no view, no isolation — so both
/// derive identical values from the same capabilities.
enum ZoomScaleSeed {

    /// Display zoom tops out at 5× the wide-angle reference, so a pill never
    /// offers unreachable range. The one place this constant lives.
    static let maxDisplayZoom: CGFloat = 5.0

    /// Clamp a camera-reported max zoom to the display ceiling.
    static func clampMaxZoom(_ maxFactor: CGFloat, wideAngle: CGFloat) -> CGFloat {
        min(maxFactor, maxDisplayZoom * wideAngle)
    }

    /// The zoom values seeded from a capabilities exchange.
    struct Seed {
        let zoomFactor: CGFloat
        let zoomStops: [CGFloat]
        let wideAngleZoomFactor: CGFloat
        /// The clamped ceiling, or nil when the current lens advertised no
        /// range — callers leave their existing ceiling untouched then.
        let maxZoomFactor: CGFloat?
    }

    /// Read zoom state from a capabilities response the way both paths do:
    /// stops and wide-angle reference from the current camera, the ceiling from
    /// the current lens's zoom range (clamped). Nil when there is no current
    /// camera to read.
    static func seed(from caps: RemoteCmd.CameraCapabilitiesResp) -> Seed? {
        guard let info = caps.getCurrentCameraInfo() else { return nil }
        let wide = info.wideAngleZoomFactor
        let maxZoom = info.getZoomCapabilities()[caps.currentLens]
            .map { clampMaxZoom($0.maxZoom, wideAngle: wide) }
        return Seed(zoomFactor: caps.currentZoom,
                    zoomStops: info.zoomStops,
                    wideAngleZoomFactor: wide,
                    maxZoomFactor: maxZoom)
    }
}
