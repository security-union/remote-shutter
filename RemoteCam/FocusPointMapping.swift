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
//  is the inverse of that rotation, plus an un-mirror when the streamed buffer
//  is mirrored (the caller reads that from the connection; an iPhone 14's
//  front-camera data output measured NOT mirrored).
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
    ///     relative to the sensor (the connection's `isVideoMirrored`).
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

    /// The inverse of `devicePoint`: a point in device space (where
    /// `focusPointOfInterest` and `AVMetadataObject.bounds` live) back into the
    /// upright display image the director shows.
    static func displayPoint(deviceNormalized point: CGPoint,
                             videoOrientation: AVCaptureVideoOrientation,
                             mirrored: Bool) -> CGPoint {
        let dx = clamp01(point.x)
        let dy = clamp01(point.y)
        var display: CGPoint
        switch videoOrientation {
        case .landscapeRight:
            display = CGPoint(x: dx, y: dy)
        case .landscapeLeft:
            display = CGPoint(x: 1 - dx, y: 1 - dy)
        case .portrait:
            display = CGPoint(x: 1 - dy, y: dx)
        case .portraitUpsideDown:
            display = CGPoint(x: dy, y: 1 - dx)
        @unknown default:
            display = CGPoint(x: dx, y: dy)
        }
        if mirrored { display.x = 1 - display.x }
        return display
    }

    /// A device-space rect (a detected subject's bounds) in the upright
    /// display image: both corners mapped, then re-normalized, since a
    /// rotation swaps which corner is the origin.
    static func displayRect(deviceNormalized rect: CGRect,
                            videoOrientation: AVCaptureVideoOrientation,
                            mirrored: Bool) -> CGRect {
        let a = displayPoint(deviceNormalized: CGPoint(x: rect.minX, y: rect.minY),
                             videoOrientation: videoOrientation, mirrored: mirrored)
        let b = displayPoint(deviceNormalized: CGPoint(x: rect.maxX, y: rect.maxY),
                             videoOrientation: videoOrientation, mirrored: mirrored)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
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
