import SwiftUI

/// Camera-style detented zoom and lens control for the monitor screen.
///
/// Collapsed it shows the lens stops with the active one highlighted; tapping a stop
/// jumps to that lens, dragging expands it into a ruler that snaps to those stops, and
/// releasing collapses it again. This is the single lens/zoom affordance on every
/// platform: on a mouse-only Mac it's the only way to zoom at all (`MagnificationGesture`
/// fires only from a trackpad pinch), and on iPhone and iPad it sits alongside pinch.
/// The ruler, drag, scroll wheel and pending-value handling are `RulerPill`'s (shared
/// with the pro sliders); all zoom math is `ZoomScale`'s, which the pinch gesture shares.
struct ZoomPill: View {
    let scale: ZoomScale
    /// Current zoom in hardware factors, as reported by the camera.
    let currentZoomFactor: CGFloat
    let onZoomChange: (CGFloat) -> Void

    /// Gap between adjacent lens circles when collapsed. The stops sit in a tight
    /// cluster rather than spread along the track: a lens button is a *choice*,
    /// not a position, and spacing them by their zoom factor left ragged gaps
    /// that grow with the camera's range.
    private static let stopSpacing: CGFloat = 10
    /// Breathing room between the number and the circle's edge.
    private static let stopTextInset: CGFloat = 5

    var body: some View {
        RulerPill(track: scale.track,
                  currentValue: Double(currentZoomFactor),
                  readout: { scale.label(forHardware: CGFloat($0)) },
                  accessibilityLabel: "Zoom",
                  collapsedWidth: collapsedWidth,
                  onChange: { onZoomChange(CGFloat($0)) },
                  collapsed: { proxy in stopRow(proxy) })
    }

    // MARK: - Collapsed: the lens stops

    private func stopRow(_ proxy: RulerPillProxy) -> some View {
        let active = activeStop(displayed: CGFloat(proxy.displayedValue))
        return HStack(spacing: Self.stopSpacing) {
            ForEach(scale.stops, id: \.self) { stop in
                PillCircleButton(isActive: stop == active,
                                 action: { proxy.commit(Double(scale.clamped(stop))) }) {
                    Text(labelText(for: stop, active: active, displayed: CGFloat(proxy.displayedValue)))
                        .font(.system(size: stop == active ? 11.5 : 11, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        // The active circle reads out the live factor, so it can be as wide
                        // as "2.4×" where a stop's own name is just "1×". Scale the wide one
                        // down to fit rather than letting it spill past the circle, and keep
                        // an inset so glyphs never touch the edge.
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, Self.stopTextInset)
                }
            }
        }
    }

    /// The cluster's intrinsic width, which the pill collapses to.
    private var collapsedWidth: CGFloat {
        let count = CGFloat(scale.stops.count)
        guard count > 0 else { return PillCircleButton<Text>.diameter }
        return count * PillCircleButton<Text>.diameter + (count - 1) * Self.stopSpacing
    }

    /// The stop the pill highlights: whichever is nearest on the track.
    private func activeStop(displayed: CGFloat) -> CGFloat? {
        let position = scale.position(forHardware: displayed)
        return scale.stops.min {
            abs(scale.position(forHardware: $0) - position)
                < abs(scale.position(forHardware: $1) - position)
        }
    }

    /// The active stop reads out the live factor ("2.4×") when zoom sits between stops,
    /// and its own name ("2×") when parked on it — same as the Camera app.
    private func labelText(for stop: CGFloat, active: CGFloat?, displayed: CGFloat) -> String {
        guard stop == active else { return scale.label(forHardware: stop) }
        return scale.label(forHardware: displayed)
    }
}
