//
//  RulerPill.swift
//  RemoteShutter
//
//  The one ruler control on the monitor. Zoom, shutter, ISO and aperture are
//  all "a value on a log-spaced range with detents", so they share the math
//  (`LogTrack`) and the pill (`RulerPill`): the glass capsule, the ruler with
//  its ticks and thumb, relative drag, scroll wheel on the Mac, the pending
//  value that keeps the thumb under the finger until the camera echoes, and
//  the VoiceOver adjustable element. `ZoomPill` configures it with its lens
//  stops as the collapsed state; `ProSliderPill` with AUTO / × buttons and no
//  collapsed state.
//

import SwiftUI

// MARK: - Math

/// A positive range on a 0…1 log2 track with detents. Pure; pinned through
/// `ZoomScaleTests` (via `ZoomScale`) and `ProSliderScaleTests`.
struct LogTrack: Equatable {
    let minValue: Double
    let maxValue: Double
    /// Detents inside the range, ascending.
    let stops: [Double]

    init(min: Double, max: Double, stops: [Double]) {
        let low = (min.isFinite && min > 0) ? min : 0
        let high = (max.isFinite && max > low) ? max : low
        minValue = low
        maxValue = high
        self.stops = stops.filter { $0.isFinite && $0 >= low && $0 <= high }.sorted()
    }

    /// True when there is nothing to slide: no range yet, or a fixed value.
    /// Callers must check this before drawing a track.
    var isDegenerate: Bool { minValue <= 0 || maxValue <= minValue }

    private var logMin: Double { log2(minValue) }
    private var logSpan: Double { log2(maxValue) - logMin }

    func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return minValue }
        return Swift.max(minValue, Swift.min(maxValue, value))
    }

    /// Where `value` sits on the track. Log2 so equal travel is equal
    /// perceived change anywhere on the range (one stop is one distance).
    func position(for value: Double) -> Double {
        guard !isDegenerate else { return 0 }
        return (log2(clamped(value)) - logMin) / logSpan
    }

    func value(atPosition position: Double) -> Double {
        guard !isDegenerate, position.isFinite else { return minValue }
        let clampedPosition = Swift.max(0, Swift.min(1, position))
        // Exact at the ends: round-tripping through log2/pow2 leaves a max of
        // 5.0 as 4.999999999999999, so a drag to the end of the ruler would
        // stop a hair short and never compare equal to `maxValue`.
        if clampedPosition <= 0 { return minValue }
        if clampedPosition >= 1 { return maxValue }
        return clamped(pow(2, logMin + clampedPosition * logSpan))
    }

    /// Snaps to the nearest detent when within `tolerance` of it. Tolerance
    /// is a fraction of the track, so the pull feels identical everywhere.
    func snappedToStop(_ value: Double, tolerance: Double = 0.04) -> Double {
        guard !isDegenerate else { return minValue }
        let target = clamped(value)
        let targetPosition = position(for: target)
        let nearest = stops.min {
            abs(position(for: $0) - targetPosition) < abs(position(for: $1) - targetPosition)
        }
        guard let stop = nearest, abs(position(for: stop) - targetPosition) <= tolerance else { return target }
        return stop
    }
}

// MARK: - Pill

/// What a pill's collapsed content can read and do: the value the pill is
/// drawing (in-flight or confirmed) and a way to jump to one.
struct RulerPillProxy {
    let displayedValue: Double
    let commit: (Double) -> Void
}

struct RulerPill<Collapsed: View, Leading: View, Trailing: View>: View {
    let track: LogTrack
    /// The camera's confirmed value.
    let currentValue: Double
    /// The readout above the ruler, e.g. "2.4×" or "SHUTTER 1/125".
    let readout: (Double) -> String
    let accessibilityLabel: String
    /// Collapse to `collapsed` when idle (zoom's lens stops) or stay up.
    let collapsesWhenIdle: Bool
    /// The collapsed content's width, so the capsule can animate between
    /// its two widths; nil sizes to the content.
    let collapsedWidth: CGFloat?
    let trackWidth: CGFloat
    let onChange: (Double) -> Void
    let collapsed: (RulerPillProxy) -> Collapsed
    let leading: () -> Leading
    let trailing: () -> Trailing

    @State private var isExpanded: Bool
    @State private var collapseWork: DispatchWorkItem?
    /// What the user just asked for, shown immediately. `currentValue` only
    /// catches up when the camera's response returns — a throttled send plus
    /// a peer-to-peer round trip — so without this the thumb trails the cursor.
    @State private var pendingValue: Double?
    @State private var isAdjusting = false
    /// Track position when the current drag began; movement is a delta.
    @State private var dragStartPosition: Double?

    static var height: CGFloat { 46 }
    private static var horizontalPadding: CGFloat { 14 }
    private static var thumbWidth: CGFloat { 3 }
    /// Track fraction per point of scroll: a ~10pt wheel notch moves ~3%.
    private static var scrollSensitivity: Double { 0.003 }
    private static var tickCount: Int { 41 }
    /// How long the ruler lingers after a drag, so a repeated adjustment
    /// doesn't have to re-expand each time.
    private static var collapseDelay: TimeInterval { 1.2 }

    init(track: LogTrack,
         currentValue: Double,
         readout: @escaping (Double) -> String,
         accessibilityLabel: String,
         collapsesWhenIdle: Bool,
         collapsedWidth: CGFloat? = nil,
         trackWidth: CGFloat = 240,
         onChange: @escaping (Double) -> Void,
         @ViewBuilder collapsed: @escaping (RulerPillProxy) -> Collapsed,
         @ViewBuilder leading: @escaping () -> Leading,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.track = track
        self.currentValue = currentValue
        self.readout = readout
        self.accessibilityLabel = accessibilityLabel
        self.collapsesWhenIdle = collapsesWhenIdle
        self.collapsedWidth = collapsedWidth
        self.trackWidth = trackWidth
        self.onChange = onChange
        self.collapsed = collapsed
        self.leading = leading
        self.trailing = trailing
        _isExpanded = State(initialValue: !collapsesWhenIdle)
    }

    var body: some View {
        HStack(spacing: 10) {
            leading()

            ZStack {
                if isExpanded {
                    ruler
                } else {
                    collapsed(RulerPillProxy(displayedValue: displayedValue, commit: commit))
                }
            }
            // Collapsed, the pill is only as wide as its content; it grows to
            // the full track while the ruler is up.
            .frame(width: isExpanded ? trackWidth : collapsedWidth, height: Self.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(readout(displayedValue))
            .accessibilityAdjustableAction { direction in
                let step = 0.05
                let position = track.position(for: displayedValue)
                switch direction {
                case .increment: commit(track.value(atPosition: position + step))
                case .decrement: commit(track.value(atPosition: position - step))
                @unknown default: break
                }
            }

            trailing()
        }
        .padding(.horizontal, Self.horizontalPadding)
        .background(glassBackground)
        // Scrolling over the pill adjusts — reaching for the wheel is the
        // reflex on a Mac. Behind the content so it never intercepts the drag.
        .background(
            ScrollWheelCatcher(onScroll: handleScroll,
                               onEnded: {
                                   isAdjusting = false
                                   scheduleCollapse()
                               })
        )
        // The whole pill is draggable, not just the track, so there is no
        // thin target to hunt for with a mouse.
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .animation(.easeOut(duration: 0.18), value: isExpanded)
        .opacity(track.isDegenerate ? 0 : 1)
        .allowsHitTesting(!track.isDegenerate)
        // Hand control back to the camera once it confirms, but never
        // mid-drag: a response for an earlier value would yank the thumb
        // backwards under the cursor.
        .onChange(of: currentValue) { _ in
            if !isAdjusting { pendingValue = nil }
        }
    }

    /// The value the pill draws: the user's in-flight value if there is one,
    /// otherwise whatever the camera last confirmed.
    private var displayedValue: Double { pendingValue ?? currentValue }

    // MARK: Ruler

    private var ruler: some View {
        VStack(spacing: 4) {
            Text(readout(displayedValue))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigitIfAvailable()

            ZStack(alignment: .leading) {
                ticks
                RoundedRectangle(cornerRadius: Self.thumbWidth / 2)
                    .fill(AppTheme.accent)
                    .frame(width: Self.thumbWidth, height: 20)
                    .shadow(color: AppTheme.accent.opacity(0.5), radius: 3)
                    .offset(x: CGFloat(track.position(for: displayedValue)) * (trackWidth - Self.thumbWidth))
            }
            .frame(width: trackWidth, height: 20, alignment: .leading)
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
        .frame(width: trackWidth)
    }

    /// True when a detent falls within half a tick of this tick, so detents
    /// read as taller marks rather than being drawn between ticks.
    private func tickMarksAStop(_ index: Int) -> Bool {
        let spacing = 1.0 / Double(Self.tickCount - 1)
        let position = Double(index) * spacing
        return track.stops.contains { abs(track.position(for: $0) - position) < spacing / 2 }
    }

    // MARK: Interaction

    /// The value moves *relative* to where it was when the drag began, not
    /// to the absolute position under the finger: the pill may be narrower
    /// than the track while collapsed, and picking up from the current value
    /// is what the Camera app's ruler does — a small correction stays small.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                cancelCollapse()
                isAdjusting = true
                let start: Double
                if let existing = dragStartPosition {
                    start = existing
                } else {
                    start = track.position(for: displayedValue)
                    dragStartPosition = start
                    isExpanded = true
                }
                let moved = start + Double(value.translation.width) / Double(trackWidth)
                commit(track.snappedToStop(track.value(atPosition: moved)))
            }
            .onEnded { _ in
                dragStartPosition = nil
                isAdjusting = false
                scheduleCollapse()
            }
    }

    /// Mouse wheel / trackpad: nudge along the track from the current value.
    /// Scrolling up (negative delta) increases, matching Maps and Photos.
    private func handleScroll(_ delta: CGFloat) {
        guard !track.isDegenerate else { return }
        cancelCollapse()
        isAdjusting = true
        if !isExpanded { isExpanded = true }
        let position = track.position(for: displayedValue)
        let moved = position - Double(delta) * Self.scrollSensitivity
        commit(track.snappedToStop(track.value(atPosition: moved)))
    }

    private func commit(_ value: Double) {
        guard !track.isDegenerate else { return }
        pendingValue = value
        onChange(value)
    }

    private func scheduleCollapse() {
        guard collapsesWhenIdle else { return }
        cancelCollapse()
        let work = DispatchWorkItem { isExpanded = false }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.collapseDelay, execute: work)
    }

    private func cancelCollapse() {
        collapseWork?.cancel()
        collapseWork = nil
    }

    // MARK: Chrome

    private var glassBackground: some View {
        ZStack {
            Color.black.opacity(0.3)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1)
        }
    }
}

extension RulerPill where Leading == EmptyView, Trailing == EmptyView {
    /// A pill that collapses to its own content when idle (zoom).
    init(track: LogTrack,
         currentValue: Double,
         readout: @escaping (Double) -> String,
         accessibilityLabel: String,
         collapsedWidth: CGFloat?,
         onChange: @escaping (Double) -> Void,
         @ViewBuilder collapsed: @escaping (RulerPillProxy) -> Collapsed) {
        self.init(track: track, currentValue: currentValue, readout: readout,
                  accessibilityLabel: accessibilityLabel, collapsesWhenIdle: true,
                  collapsedWidth: collapsedWidth, onChange: onChange,
                  collapsed: collapsed, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

extension RulerPill where Collapsed == EmptyView {
    /// A pill whose ruler is always up, with buttons at either end.
    init(track: LogTrack,
         currentValue: Double,
         readout: @escaping (Double) -> String,
         accessibilityLabel: String,
         trackWidth: CGFloat,
         onChange: @escaping (Double) -> Void,
         @ViewBuilder leading: @escaping () -> Leading,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(track: track, currentValue: currentValue, readout: readout,
                  accessibilityLabel: accessibilityLabel, collapsesWhenIdle: false,
                  trackWidth: trackWidth, onChange: onChange,
                  collapsed: { _ in EmptyView() }, leading: leading, trailing: trailing)
    }
}

/// A round button inside a pill: zoom's lens stops, the pro pill's AUTO / ×.
/// A tap gesture rather than a `Button` so it never competes with the pill's
/// drag for the touch.
struct PillCircleButton<Label: View>: View {
    var isActive = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    static var diameter: CGFloat { 32 }

    var body: some View {
        label()
            .foregroundColor(isActive ? .black : .white.opacity(0.85))
            .frame(width: Self.diameter, height: Self.diameter)
            .background(Circle().fill(isActive ? AppTheme.accent : Color.white.opacity(0.12)))
            .contentShape(Circle())
            .onTapGesture(perform: action)
    }
}

/// Delivers mouse-wheel and trackpad scrolls to SwiftUI, which has no
/// gesture for them. A `UIPanGestureRecognizer` with `allowedScrollTypesMask`
/// is UIKit's way to receive indirect scrolls; `allowedTouchTypes = []` makes
/// it scroll-only so it cannot compete with the pill's `DragGesture`.
struct ScrollWheelCatcher: UIViewRepresentable {
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
        /// `translation` is cumulative for the gesture; the pill wants deltas.
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

extension View {
    /// The ruler's readout changes every frame during a drag; monospaced
    /// digits stop it jittering. `.monospacedDigit()` is iOS 16+, and the
    /// deployment target is 15.
    @ViewBuilder func monospacedDigitIfAvailable() -> some View {
        if #available(iOS 16.0, *) {
            self.monospacedDigit()
        } else {
            self
        }
    }
}
