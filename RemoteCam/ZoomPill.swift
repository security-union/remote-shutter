#if targetEnvironment(macCatalyst)
import SwiftUI

/// Camera-style detented zoom control for the Mac monitor screen.
///
/// `MagnificationGesture` only fires from a trackpad pinch, so a mouse-only Mac has no
/// way to zoom at all. This is that affordance: collapsed it shows the lens stops with
/// the active one highlighted; dragging expands it into a ruler that snaps to those
/// stops; releasing collapses it again.
///
/// Mac-only by design — iPhone and iPad keep pinch plus the auto-hiding zoom HUD.
/// All zoom math is delegated to `ZoomScale`, which the pinch gesture shares.
struct ZoomPill: View {
    let scale: ZoomScale
    /// Current zoom in hardware factors, as reported by the camera.
    let currentZoomFactor: CGFloat
    let onZoomChange: (CGFloat) -> Void

    @State private var isExpanded = false
    @State private var collapseWork: DispatchWorkItem?
    /// What the user just asked for, shown immediately. `currentZoomFactor` only catches
    /// up when the camera's SetZoomResp returns — a throttled send plus a peer-to-peer
    /// round trip — so without this the thumb visibly trails the cursor.
    @State private var pendingZoom: CGFloat?
    @State private var isDragging = false

    private static let trackWidth: CGFloat = 240
    private static let horizontalPadding: CGFloat = 14
    private static let height: CGFloat = 46
    private static let stopDiameter: CGFloat = 30
    private static let thumbWidth: CGFloat = 3
    private static let tickCount = 41
    /// How long the ruler lingers after the drag ends, so a repeated adjustment
    /// doesn't have to re-expand each time.
    private static let collapseDelay: TimeInterval = 1.2

    var body: some View {
        ZStack {
            if isExpanded {
                ruler
            } else {
                stopRow
            }
        }
        .frame(width: Self.trackWidth, height: Self.height)
        .padding(.horizontal, Self.horizontalPadding)
        .background(glassBackground)
        // The whole pill is draggable, not just the track, so there is no thin
        // target to hunt for with a mouse.
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .animation(.easeOut(duration: 0.18), value: isExpanded)
        .opacity(scale.isDegenerate ? 0 : 1)
        .allowsHitTesting(!scale.isDegenerate)
        // Hand control back to the camera once it confirms, but never mid-drag: a
        // response for an earlier value would yank the thumb backwards under the cursor.
        .onChange(of: currentZoomFactor) { _ in
            if !isDragging { pendingZoom = nil }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zoom")
        .accessibilityValue(scale.label(forHardware: displayedZoom))
        .accessibilityAdjustableAction { direction in
            let step = 0.05
            let position = scale.position(forHardware: displayedZoom)
            switch direction {
            case .increment: commit(scale.hardwareFactor(atPosition: position + step))
            case .decrement: commit(scale.hardwareFactor(atPosition: position - step))
            @unknown default: break
            }
        }
    }

    // MARK: - Collapsed: the lens stops

    private var stopRow: some View {
        ZStack(alignment: .leading) {
            ForEach(scale.stops, id: \.self) { stop in
                stopButton(stop)
                    .offset(x: offset(forHardware: stop, itemWidth: Self.stopDiameter))
            }
        }
        .frame(width: Self.trackWidth, alignment: .leading)
    }

    private func stopButton(_ stop: CGFloat) -> some View {
        let isActive = stop == activeStop
        return Text(labelText(for: stop))
            .font(.system(size: isActive ? 13 : 12, weight: .semibold, design: .rounded))
            .foregroundColor(isActive ? .black : .white.opacity(0.85))
            .lineLimit(1)
            .fixedSize()
            .frame(width: Self.stopDiameter, height: Self.stopDiameter)
            .background(
                Circle().fill(isActive ? AppTheme.accent : Color.white.opacity(0.12))
            )
            .contentShape(Circle())
            .onTapGesture { commit(scale.clamped(stop)) }
    }

    /// The zoom the pill draws: the user's in-flight value if there is one, otherwise
    /// whatever the camera last confirmed.
    private var displayedZoom: CGFloat { pendingZoom ?? currentZoomFactor }

    /// The stop the pill highlights: whichever is nearest on the track.
    private var activeStop: CGFloat? {
        let position = scale.position(forHardware: displayedZoom)
        return scale.stops.min {
            abs(scale.position(forHardware: $0) - position)
                < abs(scale.position(forHardware: $1) - position)
        }
    }

    /// The active stop reads out the live factor ("2.4×") when zoom sits between stops,
    /// and its own name ("2×") when parked on it — same as the Camera app.
    private func labelText(for stop: CGFloat) -> String {
        guard stop == activeStop else { return scale.label(forHardware: stop) }
        return scale.label(forHardware: displayedZoom)
    }

    // MARK: - Expanded: the ruler

    private var ruler: some View {
        VStack(spacing: 4) {
            Text(scale.label(forHardware: displayedZoom))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigitIfAvailable()

            ZStack(alignment: .leading) {
                ticks
                RoundedRectangle(cornerRadius: Self.thumbWidth / 2)
                    .fill(AppTheme.accent)
                    .frame(width: Self.thumbWidth, height: 20)
                    .shadow(color: AppTheme.accent.opacity(0.5), radius: 3)
                    .offset(x: offset(forHardware: displayedZoom, itemWidth: Self.thumbWidth))
            }
            .frame(width: Self.trackWidth, height: 20, alignment: .leading)
        }
    }

    private var ticks: some View {
        HStack(spacing: 0) {
            ForEach(0..<Self.tickCount, id: \.self) { index in
                let isStop = tickMarksAStop(index)
                Rectangle()
                    .fill(Color.white.opacity(isStop ? 0.9 : 0.3))
                    .frame(width: isStop ? 2 : 1, height: isStop ? 16 : 8)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(width: Self.trackWidth)
    }

    /// True when a lens stop falls within half a tick of this tick, so detents read as
    /// taller marks rather than being drawn at a position no tick occupies.
    private func tickMarksAStop(_ index: Int) -> Bool {
        let spacing = 1.0 / Double(Self.tickCount - 1)
        let position = Double(index) * spacing
        return scale.stops.contains {
            abs(scale.position(forHardware: $0) - position) < spacing / 2
        }
    }

    // MARK: - Geometry

    private func offset(forHardware hardware: CGFloat, itemWidth: CGFloat) -> CGFloat {
        CGFloat(scale.position(forHardware: hardware)) * (Self.trackWidth - itemWidth)
    }

    // MARK: - Interaction

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                cancelCollapse()
                isDragging = true
                if !isExpanded { isExpanded = true }
                let x = value.location.x - Self.horizontalPadding
                let raw = scale.hardwareFactor(atPosition: Double(x / Self.trackWidth))
                commit(scale.snappedToStop(raw))
            }
            .onEnded { _ in
                isDragging = false
                scheduleCollapse()
            }
    }

    private func commit(_ hardware: CGFloat) {
        guard !scale.isDegenerate else { return }
        pendingZoom = hardware
        onZoomChange(hardware)
    }

    private func scheduleCollapse() {
        cancelCollapse()
        let work = DispatchWorkItem { isExpanded = false }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.collapseDelay, execute: work)
    }

    private func cancelCollapse() {
        collapseWork?.cancel()
        collapseWork = nil
    }

    // MARK: - Chrome

    private var glassBackground: some View {
        ZStack {
            Color.black.opacity(0.3)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1)
        }
    }
}

private extension View {
    /// The ruler's readout changes every frame during a drag; monospaced digits stop it
    /// jittering. `.monospacedDigit()` is iOS 16+, and the deployment target is 15.
    @ViewBuilder func monospacedDigitIfAvailable() -> some View {
        if #available(iOS 16.0, *) {
            self.monospacedDigit()
        } else {
            self
        }
    }
}
#endif
