//
//  FocusPointMapping.swift
//  RemoteShutter
//
//  Pure geometry for tap-to-focus. The monitor taps a point on the live
//  preview and sends it normalized (0..1) in the *upright display image*
//  space (origin top-left, x → right, y → down). The camera must convert that
//  into `AVCaptureDevice.focusPointOfInterest` space before applying it.
//
//  `focusPointOfInterest` is defined relative to the sensor's native readout,
//  which corresponds to `AVCaptureVideoOrientation.landscapeRight` (AVFoundation's
//  default connection orientation) being the identity. The preview frame was
//  rotated from that reference into the connection's current `videoOrientation`
//  before it left the camera, so mapping a display point back to device space
//  is the inverse of that rotation, plus an un-mirror for the front camera
//  (whose preview is shown horizontally mirrored).
//
//  This is deliberately isolated and pure so it can be unit-tested and,
//  crucially, validated/tuned against real hardware in CaptureIntegrationTests
//  (Catalyst) — the sensor/orientation conventions are the kind of thing a
//  code-read gets subtly wrong.
//

import CoreGraphics
import AVFoundation

enum FocusPointMapping {

    /// Converts a normalized preview-tap point into `focusPointOfInterest`
    /// device space.
    ///
    /// - Parameters:
    ///   - point: normalized (0..1) point in the upright display image, origin
    ///     top-left. Values outside [0,1] are clamped.
    ///   - videoOrientation: the orientation the preview buffer was rotated into
    ///     (i.e. the capture connection's `videoOrientation`). On landscape-native
    ///     Mac cameras this is `.landscapeRight` (identity).
    ///   - mirrored: true when the displayed image is horizontally mirrored
    ///     relative to the sensor (the front camera).
    /// - Returns: a point in `focusPointOfInterest` space, clamped to [0,1].
    static func devicePoint(displayNormalized point: CGPoint,
                            videoOrientation: AVCaptureVideoOrientation,
                            mirrored: Bool) -> CGPoint {
        // Work in clamped, mirror-corrected display coordinates first.
        var px = clamp01(point.x)
        let py = clamp01(point.y)
        if mirrored { px = 1 - px }

        // Invert the display rotation back to the landscapeRight-identity
        // reference used by focusPointOfInterest.
        let device: CGPoint
        switch videoOrientation {
        case .landscapeRight:
            device = CGPoint(x: px, y: py)
        case .landscapeLeft:
            device = CGPoint(x: 1 - px, y: 1 - py)
        case .portrait:
            device = CGPoint(x: py, y: 1 - px)
        case .portraitUpsideDown:
            device = CGPoint(x: 1 - py, y: px)
        @unknown default:
            device = CGPoint(x: px, y: py)
        }
        return CGPoint(x: clamp01(device.x), y: clamp01(device.y))
    }

    private static func clamp01(_ v: CGFloat) -> CGFloat {
        min(1, max(0, v))
    }

    /// Maps a tap point in an aspect-fit (`.fit`, letterboxed) preview into a
    /// normalized image point (0..1, origin top-left). Returns nil when the tap
    /// lands in the letterbox/pillarbox bars, i.e. off the image — those taps
    /// must not focus.
    ///
    /// - Parameters:
    ///   - tap: tap location in the preview view's coordinate space.
    ///   - viewSize: the preview view's size.
    ///   - imageSize: the displayed image's pixel size.
    static func normalizedImagePoint(tap: CGPoint,
                                     viewSize: CGSize,
                                     imageSize: CGSize) -> CGPoint? {
        guard viewSize.width > 0, viewSize.height > 0,
              imageSize.width > 0, imageSize.height > 0 else { return nil }
        let imageRatio = imageSize.width / imageSize.height
        let viewRatio = viewSize.width / viewSize.height
        let fitted: CGSize = imageRatio > viewRatio
            ? CGSize(width: viewSize.width, height: viewSize.width / imageRatio)
            : CGSize(width: viewSize.height * imageRatio, height: viewSize.height)
        let xOffset = (viewSize.width - fitted.width) / 2
        let yOffset = (viewSize.height - fitted.height) / 2
        let nx = (tap.x - xOffset) / fitted.width
        let ny = (tap.y - yOffset) / fitted.height
        guard (0...1).contains(nx), (0...1).contains(ny) else { return nil }
        return CGPoint(x: nx, y: ny)
    }
}
