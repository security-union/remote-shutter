import CoreGraphics
import Foundation

/// Single source of truth for monitor-side zoom math.
///
/// The camera reports zoom as a *hardware* factor (`AVCaptureDevice.videoZoomFactor`),
/// but the user reads a *display* factor: "1×" means the wide-angle lens, which on a
/// triple-camera iPhone is hardware 2.0. Conversion, clamping, ruler geometry, detents
/// and label formatting all live here so the pinch gesture and the Mac zoom pill cannot
/// drift apart, and so no call site has to remember which unit it is holding.
///
/// Pure value type — no UIKit, no AVFoundation, no actor. Pinned by `ZoomScaleTests`.
struct ZoomScale: Equatable {
    /// Lens switch-over points in hardware factors, ascending. Never empty.
    let stops: [CGFloat]
    /// The hardware factor the user reads as "1×".
    let wideAngleZoomFactor: CGFloat
    let minZoom: CGFloat
    let maxZoom: CGFloat

    init(stops: [CGFloat], maxZoomFactor: CGFloat, wideAngleZoomFactor: CGFloat) {
        let usable = stops.filter { $0.isFinite && $0 > 0 }.sorted()
        let safeStops = usable.isEmpty ? [1.0] : usable
        let low = safeStops[0]
        // `maxZoomFactor` arrives as a default (10.0) before the first SetZoomResp and can
        // legitimately land at or below the low stop on a fixed-focal-length camera.
        let ceiling = (maxZoomFactor.isFinite && maxZoomFactor > low) ? maxZoomFactor : low

        self.minZoom = low
        self.maxZoom = ceiling
        self.wideAngleZoomFactor =
            (wideAngleZoomFactor.isFinite && wideAngleZoomFactor > 0) ? wideAngleZoomFactor : 1.0
        // A stop past the ceiling can't be reached, so it must not be offered as a detent.
        // `low` always survives, so this can never empty the array.
        self.stops = safeStops.filter { $0 <= ceiling }
    }

    /// True when the range has collapsed and there is nothing to zoom: before the first
    /// `SetZoomResp` lands, or on a camera with a single fixed focal length. Callers must
    /// check this before drawing a track — a SwiftUI `Slider` traps on an empty range.
    var isDegenerate: Bool { maxZoom <= minZoom }

    private var logMin: Double { Double(log2(minZoom)) }
    private var logSpan: Double { Double(log2(maxZoom)) - logMin }

    func clamped(_ hardware: CGFloat) -> CGFloat {
        guard hardware.isFinite else { return minZoom }
        return max(minZoom, min(maxZoom, hardware))
    }

    // MARK: - Display units

    func displayFactor(forHardware hardware: CGFloat) -> CGFloat {
        hardware / wideAngleZoomFactor
    }

    var displayStops: [CGFloat] { stops.map { displayFactor(forHardware: $0) } }

    /// Formats a hardware factor as a user-facing label, e.g. hardware 1.0 against a
    /// wide-angle factor of 2.0 → "0.5×", hardware 2.0 → "1×", hardware 6.0 → "3×".
    func label(forHardware hardware: CGFloat, glyph: String = "×") -> String {
        let rounded = (displayFactor(forHardware: hardware) * 10).rounded() / 10
        if rounded == CGFloat(Int(rounded)) {
            return "\(Int(rounded))\(glyph)"
        }
        return String(format: "%.1f", rounded) + glyph
    }

    // MARK: - Ruler geometry

    /// Where `hardware` sits on a 0…1 track. Log2 so equal travel is equal perceived
    /// change at 1× and at 5×, matching the pinch curve.
    func position(forHardware hardware: CGFloat) -> Double {
        guard !isDegenerate else { return 0 }
        return (Double(log2(clamped(hardware))) - logMin) / logSpan
    }

    func hardwareFactor(atPosition position: Double) -> CGFloat {
        guard !isDegenerate, position.isFinite else { return minZoom }
        let clampedPosition = max(0, min(1, position))
        // Exact at the ends. Round-tripping through log2/pow2 leaves a max of 5.0 as
        // 4.999999999999999, so a drag to the end of the ruler would stop a hair short
        // of the ceiling and never compare equal to `maxZoom`.
        if clampedPosition <= 0 { return minZoom }
        if clampedPosition >= 1 { return maxZoom }
        return clamped(CGFloat(pow(2, logMin + clampedPosition * logSpan)))
    }

    // MARK: - Detents

    /// Snaps to the nearest stop when within `tolerance` of it. Tolerance is a fraction of
    /// the whole track, not a zoom delta, so the pull feels identical at 1× and at 5×.
    func snappedToStop(_ hardware: CGFloat, tolerance: Double = 0.04) -> CGFloat {
        guard !isDegenerate else { return minZoom }
        let target = clamped(hardware)
        let targetPosition = position(forHardware: target)
        let nearest = stops.min {
            abs(position(forHardware: $0) - targetPosition)
                < abs(position(forHardware: $1) - targetPosition)
        }
        guard let stop = nearest,
              abs(position(forHardware: stop) - targetPosition) <= tolerance else { return target }
        return stop
    }

    // MARK: - Pinch

    /// `newZoom = start * magnification^sensitivity`, evaluated in log2 space so a given
    /// finger movement changes zoom by the same perceptual amount across the range.
    func pinched(from start: CGFloat, magnification: CGFloat, sensitivity: CGFloat = 0.6) -> CGFloat {
        guard start > 0, start.isFinite, magnification > 0, magnification.isFinite else {
            return clamped(start)
        }
        return clamped(pow(2, log2(start) + log2(magnification) * sensitivity))
    }
}
