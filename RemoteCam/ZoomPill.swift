import SwiftUI

/// Camera-style detented zoom and lens control for the monitor screen.
///
/// Collapsed it shows the lens stops with the active one highlighted; tapping a stop
/// jumps to that lens, dragging expands it into a ruler that snaps to those stops, and
/// releasing collapses it again. This is the single lens/zoom affordance on every
/// platform: on a mouse-only Mac it's the only way to zoom at all (`MagnificationGesture`
/// fires only from a trackpad pinch), and on iPhone and iPad it sits alongside pinch.
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
    @State private var isAdjusting = false
    /// Track position (0…1) when the current drag began, so movement is applied
    /// as a delta. Nil when no drag is in flight.
    @State private var dragStartPosition: Double?

    private static let trackWidth: CGFloat = 240
    private static let horizontalPadding: CGFloat = 14
    private static let height: CGFloat = 46
    private static let stopDiameter: CGFloat = 32
    /// Gap between adjacent lens circles when collapsed. The stops sit in a tight
    /// cluster rather than spread along the track: a lens button is a *choice*,
    /// not a position, and spacing them by their zoom factor left ragged gaps
    /// that grow with the camera's range.
    private static let stopSpacing: CGFloat = 10
    /// Breathing room between the number and the circle's edge.
    private static let stopTextInset: CGFloat = 5
    private static let thumbWidth: CGFloat = 3
    /// Track fraction travelled per point of scroll. A wheel notch is ~10pt, so a notch
    /// moves ~3% of the range — fine enough to land on a value, coarse enough to cross
    /// the whole range without spinning forever.
    private static let scrollSensitivity: Double = 0.003
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
        // Collapsed, the pill is only as wide as its lens circles; it grows to the
        // full track only while the ruler is up. A fixed track-width capsule sat
        // there at 268pt permanently, which is a lot of viewfinder to spend on
        // three buttons.
        .frame(width: isExpanded ? Self.trackWidth : collapsedWidth, height: Self.height)
        .padding(.horizontal, Self.horizontalPadding)
        .background(glassBackground)
        // Scrolling over the pill zooms — reaching for the wheel is the reflex on a Mac.
        // Behind the content so it never intercepts the drag.
        .background(
            ScrollWheelCatcher(onScroll: handleScroll,
                               onEnded: {
                                   isAdjusting = false
                                   scheduleCollapse()
                               })
        )
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
            if !isAdjusting { pendingZoom = nil }
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
        HStack(spacing: Self.stopSpacing) {
            ForEach(scale.stops, id: \.self) { stop in
                stopButton(stop)
            }
        }
    }

    /// The cluster's intrinsic width, which the pill collapses to. Held as a
    /// number rather than left to `fit` so the capsule can animate between the
    /// two widths.
    private var collapsedWidth: CGFloat {
        let count = CGFloat(scale.stops.count)
        guard count > 0 else { return Self.stopDiameter }
        return count * Self.stopDiameter + (count - 1) * Self.stopSpacing
    }

    private func stopButton(_ stop: CGFloat) -> some View {
        let isActive = stop == activeStop
        return Text(labelText(for: stop))
            .font(.system(size: isActive ? 11.5 : 11, weight: .semibold, design: .rounded))
            .foregroundColor(isActive ? .black : .white.opacity(0.85))
            .lineLimit(1)
            // The active circle reads out the live factor, so it can be as wide as "2.4×"
            // where a stop's own name is just "1×". Scale the wide one down to fit rather
            // than letting it spill past the circle, and keep an inset so glyphs never
            // touch the edge. (Sizing the text before the frame is what bounds it.)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, Self.stopTextInset)
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

    /// Zoom moves *relative* to where it was when the drag began, rather than
    /// jumping to the absolute position under the finger. Two reasons: the pill
    /// is narrower than the track while collapsed, so an absolute mapping would
    /// read the first event in the wrong coordinate space and snap somewhere
    /// unintended; and picking up from the current value is what the Camera
    /// app's ruler does, so a small correction stays a small correction.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                cancelCollapse()
                isAdjusting = true
                let start: Double
                if let existing = dragStartPosition {
                    start = existing
                } else {
                    start = scale.position(forHardware: displayedZoom)
                    dragStartPosition = start
                    isExpanded = true
                }
                let moved = start + Double(value.translation.width) / Double(Self.trackWidth)
                commit(scale.snappedToStop(scale.hardwareFactor(atPosition: moved)))
            }
            .onEnded { _ in
                dragStartPosition = nil
                isAdjusting = false
                scheduleCollapse()
            }
    }

    /// Mouse wheel / trackpad scroll: nudge along the track from wherever zoom is now.
    /// Scrolling up (negative delta) zooms in, matching the direction the content appears
    /// to move in Maps and Photos.
    private func handleScroll(_ delta: CGFloat) {
        guard !scale.isDegenerate else { return }
        cancelCollapse()
        // Same as a drag: hold off the camera's confirmations until the user stops, or a
        // response for an earlier value resets pendingZoom and the next scroll steps from
        // a stale position.
        isAdjusting = true
        if !isExpanded { isExpanded = true }
        let position = scale.position(forHardware: displayedZoom)
        let moved = position - Double(delta) * Self.scrollSensitivity
        commit(scale.snappedToStop(scale.hardwareFactor(atPosition: moved)))
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

/// Delivers mouse-wheel and trackpad scrolls to SwiftUI, which has no gesture for them.
///
/// A `UIPanGestureRecognizer` with `allowedScrollTypesMask` is UIKit's way to receive
/// indirect scrolls. `allowedTouchTypes = []` makes it a scroll-only recognizer, so it
/// cannot compete with the pill's `DragGesture` for click-drags.
private struct ScrollWheelCatcher: UIViewRepresentable {
    /// Vertical scroll delta in points, positive when scrolling down.
    let onScroll: (CGFloat) -> Void
    let onEnded: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleScroll(_:)))
        pan.allowedScrollTypesMask = .all
        pan.allowedTouchTypes = []  // scroll events only — leave touches to SwiftUI
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onScroll = onScroll
        context.coordinator.onEnded = onEnded
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScroll: onScroll, onEnded: onEnded) }

    final class Coordinator: NSObject {
        var onScroll: (CGFloat) -> Void
        var onEnded: () -> Void
        /// `translation` is cumulative for the gesture; the pill wants per-event deltas.
        private var lastTranslation: CGFloat = 0

        init(onScroll: @escaping (CGFloat) -> Void, onEnded: @escaping () -> Void) {
            self.onScroll = onScroll
            self.onEnded = onEnded
        }

        @objc func handleScroll(_ pan: UIPanGestureRecognizer) {
            switch pan.state {
            case .began:
                lastTranslation = 0
            case .changed:
                let translation = pan.translation(in: pan.view).y
                onScroll(translation - lastTranslation)
                lastTranslation = translation
            case .ended, .cancelled, .failed:
                lastTranslation = 0
                onEnded()
            default:
                break
            }
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
