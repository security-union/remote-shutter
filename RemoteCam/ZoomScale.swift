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

    /// Display zoom tops out at 5× the wide-angle reference, so a pill never
    /// offers unreachable range. The one place this constant lives.
    static let maxDisplayZoom: CGFloat = 5.0

    /// Clamp a camera-reported max zoom to the display ceiling.
    static func displayCapped(_ maxFactor: CGFloat, wideAngle: CGFloat) -> CGFloat {
        min(maxFactor, maxDisplayZoom * wideAngle)
    }

    /// `minZoomFactor` is a hard floor below which the camera cannot go right
    /// now (Cinematic narrows zoom from both ends); stops beneath it are not
    /// offered. Nil/invalid = the first stop is the floor, as ever.
    init(stops: [CGFloat], maxZoomFactor: CGFloat, wideAngleZoomFactor: CGFloat,
         minZoomFactor: CGFloat? = nil) {
        let usable = stops.filter { $0.isFinite && $0 > 0 }.sorted()
        let safeStops = usable.isEmpty ? [1.0] : usable
        let floor = minZoomFactor.flatMap { ($0.isFinite && $0 > 0) ? $0 : nil }
        let low = max(safeStops[0], floor ?? 0)
        // `maxZoomFactor` arrives as a default before the first snapshot and can
        // legitimately land at or below the low stop on a fixed-focal-length camera.
        let ceiling = (maxZoomFactor.isFinite && maxZoomFactor > low) ? maxZoomFactor : low

        self.minZoom = low
        self.maxZoom = ceiling
        self.wideAngleZoomFactor =
            (wideAngleZoomFactor.isFinite && wideAngleZoomFactor > 0) ? wideAngleZoomFactor : 1.0
        // A stop outside [low, ceiling] can't be reached, so it must not be
        // offered as a detent; if the floor swallowed every stop, the floor
        // itself is the one detent.
        let reachable = safeStops.filter { $0 >= low && $0 <= ceiling }
        self.stops = reachable.isEmpty ? [low] : reachable
    }

    /// True when the range has collapsed and there is nothing to zoom: before the first
    /// `SetZoomResp` lands, or on a camera with a single fixed focal length. Callers must
    /// check this before drawing a track — a SwiftUI `Slider` traps on an empty range.
    var isDegenerate: Bool { maxZoom <= minZoom }

    /// The ruler math in hardware factors — what the pill draws and drags.
    var track: LogTrack {
        LogTrack(min: Double(minZoom), max: Double(maxZoom), stops: stops.map { Double($0) })
    }

    func clamped(_ hardware: CGFloat) -> CGFloat {
        CGFloat(track.clamped(Double(hardware)))
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
        track.position(for: Double(hardware))
    }

    func hardwareFactor(atPosition position: Double) -> CGFloat {
        CGFloat(track.value(atPosition: position))
    }

    // MARK: - Detents

    /// Snaps to the nearest stop when within `tolerance` of it. Tolerance is a fraction of
    /// the whole track, not a zoom delta, so the pull feels identical at 1× and at 5×.
    func snappedToStop(_ hardware: CGFloat, tolerance: Double = 0.04) -> CGFloat {
        CGFloat(track.snappedToStop(Double(hardware), tolerance: tolerance))
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
