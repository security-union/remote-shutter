//
//  RulerPill.swift
//  RemoteShutter
//
//  The one ruler control on the director. Zoom, shutter, ISO and EV are all
//  "a value on a range with detents", so they share the math (`RulerTrack`)
//  and the pill (`RulerPill`): the glass capsule, the ruler with its ticks
//  and thumb, relative drag, scroll wheel on the Mac, the pending value that
//  keeps the thumb under the finger until the camera reports, and the
//  VoiceOver adjustable element. `ZoomPill` configures it with its lens
//  stops as the collapsed state; the exposure rulers keep it up, horizontal
//  or vertical (Docs/pro-controls.md).
//

import SwiftUI

// MARK: - Math

/// A range on a 0…1 track with detents. Log2 for zoom, shutter and ISO (one
/// stop is one distance anywhere), linear for EV. Pure; pinned through
/// `ZoomScaleTests` (via `ZoomScale`) and `ExposureScaleTests`.
struct RulerTrack: Equatable {
    enum Mapping: Equatable { case log2, linear }

    /// How a dragged value settles. Zoom is continuous and only *pulled*
    /// onto a lens stop near one. Shutter, ISO and EV click from detent to
    /// detent like a camera's dial, and nothing between them is reachable.
    enum Detents: Equatable { case magnetic, stepped }

    let mapping: Mapping
    let detents: Detents
    let minValue: Double
    let maxValue: Double
    /// Detents inside the range, ascending. A stepped track also carries
    /// its two ends, so the camera's whole range stays reachable.
    let stops: [Double]
    /// The detents drawn as tall ticks (full stops on a ⅓-stop dial); the
    /// rest are drawn short. Every detent on a magnetic track is major.
    let majorStops: [Double]

    init(mapping: Mapping = .log2, detents: Detents = .magnetic,
         min: Double, max: Double, stops: [Double], majorStops: [Double]? = nil) {
        self.mapping = mapping
        self.detents = detents
        let floor: Double = mapping == .log2 ? 0 : -.infinity
        let low = (min.isFinite && min > floor) ? min : floor
        let high = (max.isFinite && max > low) ? max : low
        minValue = low
        maxValue = high
        let inRange = { (value: Double) in value.isFinite && value >= low && value <= high }
        var detentValues = stops.filter(inRange).sorted()
        if detents == .stepped, low.isFinite, high > low {
            // An end that is not a detent becomes one, unless a detent sits
            // within a sixth of a stop of it — two clicks for one value.
            let toTrack: (Double) -> Double = mapping == .log2 ? { Foundation.log2($0) } : { $0 }
            for end in [low, high] where !detentValues.contains(where: { abs(toTrack($0) - toTrack(end)) < 1.0 / 6 }) {
                detentValues.append(end)
            }
            detentValues.sort()
        }
        self.stops = detentValues
        self.majorStops = majorStops.map { $0.filter(inRange).sorted() } ?? detentValues
    }

    /// A camera dial over `min…max`: a detent every `1 / stepsPerStop` of a
    /// stop, laid on the grid through `anchor`, the full stops major. Every
    /// detent is computed from the range the camera reports, so a device
    /// that reaches 1/24000 s or ISO 12800 gets clicks all the way there.
    static func dial(mapping: Mapping = .log2, min: Double, max: Double,
                     anchor: Double, stepsPerStop: Int = 3) -> RulerTrack {
        let steps = Double(stepsPerStop)
        let onGrid: (Double) -> Double = mapping == .log2
            ? { Foundation.log2($0 / anchor) * steps } : { ($0 - anchor) * steps }
        let atStep: (Int) -> Double = mapping == .log2
            ? { anchor * pow(2, Double($0) / steps) } : { anchor + Double($0) / steps }
        var detents: [Double] = []
        var major: [Double] = []
        if min.isFinite, max.isFinite, max > min, mapping == .linear || min > 0 {
            let first = Int((onGrid(min) - 1e-9).rounded(.up))
            let last = Int((onGrid(max) + 1e-9).rounded(.down))
            if first <= last, last - first < 1000 {
                for step in first...last {
                    detents.append(atStep(step))
                    if step % stepsPerStop == 0 { major.append(atStep(step)) }
                }
            }
        }
        return RulerTrack(mapping: mapping, detents: .stepped, min: min, max: max,
                          stops: detents, majorStops: major)
    }

    /// True when there is nothing to slide: no range yet, or a fixed value.
    /// Callers must check this before drawing a track.
    var isDegenerate: Bool {
        !minValue.isFinite || maxValue <= minValue || (mapping == .log2 && minValue <= 0)
    }

    private func toTrack(_ value: Double) -> Double { mapping == .log2 ? log2(value) : value }
    private func fromTrack(_ onTrack: Double) -> Double { mapping == .log2 ? pow(2, onTrack) : onTrack }
    private var trackMin: Double { toTrack(minValue) }
    private var trackSpan: Double { toTrack(maxValue) - trackMin }

    func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return minValue }
        return Swift.max(minValue, Swift.min(maxValue, value))
    }

    /// Where `value` sits on the track.
    func position(for value: Double) -> Double {
        guard !isDegenerate else { return 0 }
        return (toTrack(clamped(value)) - trackMin) / trackSpan
    }

    func value(atPosition position: Double) -> Double {
        guard !isDegenerate, position.isFinite else { return minValue }
        let clampedPosition = Swift.max(0, Swift.min(1, position))
        // Exact at the ends: round-tripping through log2/pow2 leaves a max of
        // 5.0 as 4.999999999999999, so a drag to the end of the ruler would
        // stop a hair short and never compare equal to `maxValue`.
        if clampedPosition <= 0 { return minValue }
        if clampedPosition >= 1 { return maxValue }
        return clamped(fromTrack(trackMin + clampedPosition * trackSpan))
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

    /// Where a dragged value comes to rest: the nearest detent on a stepped
    /// track, the magnetic pull near one otherwise.
    func settled(_ value: Double) -> Double {
        guard detents == .stepped else { return snappedToStop(value) }
        return snappedToStop(value, tolerance: .infinity)
    }

    /// `count` detents on from `value` (negative = down), for VoiceOver's
    /// swipe up / down. A magnetic track moves a twentieth of its length.
    func stepping(_ current: Double, by count: Int) -> Double {
        guard detents == .stepped, !stops.isEmpty else {
            return value(atPosition: position(for: current) + 0.05 * Double(count))
        }
        let here = settled(current)
        let index = stops.firstIndex(of: here) ?? 0
        return stops[Swift.max(0, Swift.min(stops.count - 1, index + count))]
    }

    /// True when two values sit on the same spot of the track, to within a
    /// hundredth of it. The pill keeps drawing what the user asked for until
    /// the camera reports a value that matches it this way, so the thumb
    /// never flicks back to a reply that answers an older ask.
    func matches(_ value: Double, _ other: Double) -> Bool {
        abs(position(for: value) - position(for: other)) <= 0.01
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
    let track: RulerTrack
    /// The camera's confirmed value.
    let currentValue: Double
    /// The readout above the ruler, e.g. "2.4×" or "1/125".
    let readout: (Double) -> String
    let accessibilityLabel: String
    /// Collapse to `collapsed` when idle (zoom's lens stops) or stay up.
    let collapsesWhenIdle: Bool
    /// The collapsed content's width, so the capsule can animate between
    /// its two widths; nil sizes to the content.
    let collapsedWidth: CGFloat?
    let trackLength: CGFloat
    /// Horizontal under a thumb along the bottom, vertical on a side edge:
    /// same ruler, drawn along the other axis, dragged along it too.
    let axis: Axis
    let onChange: (Double) -> Void
    let collapsed: (RulerPillProxy) -> Collapsed
    let leading: (RulerPillProxy) -> Leading
    let trailing: (RulerPillProxy) -> Trailing

    @State private var isExpanded: Bool
    @State private var collapseWork: DispatchWorkItem?
    /// What the user just asked for, shown immediately. `currentValue` only
    /// catches up when the camera's state reply returns — a throttled send
    /// plus a peer-to-peer round trip — so without this the thumb trails.
    @State private var pendingValue: Double?
    @State private var isAdjusting = false
    /// Track position when the current drag began; movement is a delta.
    @State private var dragStartPosition: Double?
    /// Where the scroll wheel has carried the track so far this gesture,
    /// before settling. A stepped track needs it: one small notch moves less
    /// than a detent, and re-reading the settled value each notch would
    /// snap it straight back.
    @State private var scrollPosition: Double?
    /// Gives the thumb back to the camera if its report never matches the
    /// ask (a value it clamped), so a stale thumb cannot stick forever.
    @State private var releaseWork: DispatchWorkItem?
    @State private var detentFeedback = UISelectionFeedbackGenerator()

    /// Tall enough for a 44pt control plus its readout — the iOS minimum
    /// touch target, which a 32pt circle in a 46pt capsule was not.
    static var height: CGFloat { 64 }
    private static var horizontalPadding: CGFloat { 16 }
    private static var thumbWidth: CGFloat { 4 }
    /// Track fraction per point of scroll: a ~10pt wheel notch moves ~3%.
    private static var scrollSensitivity: Double { 0.003 }
    private static var tickCount: Int { 41 }
    /// How long the ruler lingers after a drag, so a repeated adjustment
    /// doesn't have to re-expand each time.
    private static var collapseDelay: TimeInterval { 1.2 }
    /// How long the thumb holds the asked-for value waiting for a matching
    /// report before the camera's own value takes over.
    private static var releaseDelay: TimeInterval { 1.0 }

    init(track: RulerTrack,
         currentValue: Double,
         readout: @escaping (Double) -> String,
         accessibilityLabel: String,
         collapsesWhenIdle: Bool,
         collapsedWidth: CGFloat? = nil,
         trackLength: CGFloat = 280,
         axis: Axis = .horizontal,
         onChange: @escaping (Double) -> Void,
         @ViewBuilder collapsed: @escaping (RulerPillProxy) -> Collapsed,
         @ViewBuilder leading: @escaping (RulerPillProxy) -> Leading,
         @ViewBuilder trailing: @escaping (RulerPillProxy) -> Trailing) {
        self.track = track
        self.currentValue = currentValue
        self.readout = readout
        self.accessibilityLabel = accessibilityLabel
        self.collapsesWhenIdle = collapsesWhenIdle
        self.collapsedWidth = collapsedWidth
        self.trackLength = trackLength
        self.axis = axis
        self.onChange = onChange
        self.collapsed = collapsed
        self.leading = leading
        self.trailing = trailing
        _isExpanded = State(initialValue: !collapsesWhenIdle)
    }

    var body: some View {
        stack {
            leading(proxy)

            ZStack {
                if isExpanded {
                    ruler
                } else {
                    collapsed(proxy)
                }
            }
            // Collapsed, the pill is only as wide as its content; it grows to
            // the full track while the ruler is up.
            .frame(width: axis == .horizontal ? (isExpanded ? trackLength : collapsedWidth) : Self.height,
                   height: axis == .horizontal ? Self.height : trackLength)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(readout(displayedValue))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: commitAndRelease(track.stepping(displayedValue, by: 1))
                case .decrement: commitAndRelease(track.stepping(displayedValue, by: -1))
                @unknown default: break
                }
            }

            trailing(proxy)
        }
        .padding(axis == .horizontal ? .horizontal : .vertical, Self.horizontalPadding)
        .pillGlass()
        // Scrolling over the pill adjusts — reaching for the wheel is the
        // reflex on a Mac. Behind the content so it never intercepts the drag.
        .background(
            ScrollWheelCatcher(onScroll: handleScroll,
                               onEnded: {
                                   isAdjusting = false
                                   scrollPosition = nil
                                   scheduleRelease()
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
        // Hand the thumb back to the camera once it reports what was asked
        // for. Any other report answers an older ask (they arrive in order,
        // one round trip behind), so drawing it would flick the thumb back.
        .onChange(of: currentValue) { reported in
            if !isAdjusting, let pending = pendingValue, track.matches(pending, reported) {
                pendingValue = nil
            }
        }
    }

    @ViewBuilder
    private func stack<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if axis == .horizontal {
            HStack(spacing: 10) { content() }
        } else {
            VStack(spacing: 10) { content() }
        }
    }

    /// The value the pill draws: the user's in-flight value if there is one,
    /// otherwise whatever the camera last confirmed.
    private var displayedValue: Double { pendingValue ?? currentValue }

    /// What the pill hands its slots: what it is drawing, and a way to jump
    /// to a value (a lens stop, a reset) as though it had been dragged there.
    private var proxy: RulerPillProxy {
        RulerPillProxy(displayedValue: displayedValue, commit: commitAndRelease)
    }

    // MARK: Ruler

    private var ruler: some View {
        let position = CGFloat(track.position(for: displayedValue))
        let travel = trackLength - Self.thumbWidth
        let readoutText = Text(readout(displayedValue))
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .monospacedDigitIfAvailable()
        let thumb = RoundedRectangle(cornerRadius: Self.thumbWidth / 2)
            .fill(AppTheme.accent)
            .shadow(color: AppTheme.accent.opacity(0.5), radius: 3)
        // A stepped thumb glides into each detent, so a click reads as a
        // click; a continuous one (zoom) tracks the finger with no lag.
        let thumbMotion: Animation? = track.detents == .stepped || !isAdjusting
            ? .interactiveSpring(response: 0.18, dampingFraction: 0.86) : nil
        return Group {
            if axis == .horizontal {
                VStack(spacing: 4) {
                    readoutText
                    ZStack(alignment: .leading) {
                        ticks
                        thumb.frame(width: Self.thumbWidth, height: Self.tickFieldDepth)
                            .offset(x: position * travel)
                            .animation(thumbMotion, value: position)
                    }
                    .frame(width: trackLength, height: Self.tickFieldDepth, alignment: .leading)
                }
            } else {
                // Up is more, as on a camera's dial: the thumb sits at the top
                // for the max value.
                VStack(spacing: 4) {
                    readoutText
                    ZStack(alignment: .top) {
                        ticks
                        thumb.frame(width: Self.tickFieldDepth, height: Self.thumbWidth)
                            .offset(y: (1 - position) * travel)
                            .animation(thumbMotion, value: position)
                    }
                    .frame(width: Self.tickFieldDepth, height: trackLength, alignment: .top)
                }
            }
        }
    }

    private static var tickFieldDepth: CGFloat { 28 }

    /// The tick field in one draw. Ticks sit where the thumb's centre would
    /// for their value, so the thumb parked on a detent covers its tick.
    private var ticks: some View {
        let marks = RulerTicks.marks(for: track, gridCount: Self.tickCount)
        let horizontal = axis == .horizontal
        return Canvas { context, size in
            let length = horizontal ? size.width : size.height
            let depth = horizontal ? size.height : size.width
            let inset = Self.thumbWidth / 2
            for mark in marks {
                let along = inset + CGFloat(mark.position) * (length - 2 * inset)
                let tickLength: CGFloat = mark.isMajor ? 22 : 11
                let tickWidth: CGFloat = mark.isMajor ? 2 : 1
                let across = (depth - tickLength) / 2
                // Up is more on a vertical track.
                let rect = horizontal
                    ? CGRect(x: along - tickWidth / 2, y: across, width: tickWidth, height: tickLength)
                    : CGRect(x: across, y: length - along - tickWidth / 2, width: tickLength, height: tickWidth)
                context.fill(Path(rect), with: .color(.white.opacity(mark.isMajor ? 0.9 : 0.35)))
            }
        }
        .frame(width: horizontal ? trackLength : Self.tickFieldDepth,
               height: horizontal ? Self.tickFieldDepth : trackLength)
        .allowsHitTesting(false)
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
                    cancelRelease()
                    detentFeedback.prepare()
                }
                let travel = axis == .horizontal ? value.translation.width : -value.translation.height
                let moved = start + Double(travel) / Double(trackLength)
                commit(track.settled(track.value(atPosition: moved)))
            }
            .onEnded { _ in
                dragStartPosition = nil
                isAdjusting = false
                scheduleRelease()
                scheduleCollapse()
            }
    }

    /// Mouse wheel / trackpad: nudge along the track from the current value.
    /// Scrolling up (negative delta) increases, matching Maps and Photos.
    private func handleScroll(_ delta: CGFloat) {
        guard !track.isDegenerate else { return }
        cancelCollapse()
        cancelRelease()
        isAdjusting = true
        if !isExpanded { isExpanded = true }
        let position = scrollPosition ?? track.position(for: displayedValue)
        let moved = max(0, min(1, position - Double(delta) * Self.scrollSensitivity))
        scrollPosition = moved
        commit(track.settled(track.value(atPosition: moved)))
    }

    /// Shows `value` at once and asks the camera for it, only when it is a
    /// change: a drag that stays inside one detent sends nothing.
    private func commit(_ value: Double) {
        guard !track.isDegenerate, value != displayedValue else { return }
        if track.detents == .stepped { detentFeedback.selectionChanged() }
        pendingValue = value
        onChange(value)
    }

    /// A commit that is not part of a drag (a lens stop, a reset, VoiceOver):
    /// the release deadline starts at once.
    private func commitAndRelease(_ value: Double) {
        commit(value)
        scheduleRelease()
    }

    private func scheduleRelease() {
        cancelRelease()
        guard pendingValue != nil else { return }
        let work = DispatchWorkItem { if !isAdjusting { pendingValue = nil } }
        releaseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.releaseDelay, execute: work)
    }

    private func cancelRelease() {
        releaseWork?.cancel()
        releaseWork = nil
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

}

// MARK: - Ticks

/// Where a ruler's ticks go, as positions on its 0…1 track. A stepped track
/// draws one tick per detent, tall on its major stops; a magnetic one draws
/// an even grid with the ticks nearest a detent drawn tall. Pure, so the
/// layout is testable without rendering.
enum RulerTicks {
    struct Mark: Equatable {
        let position: Double
        let isMajor: Bool
    }

    static func marks(for track: RulerTrack, gridCount: Int) -> [Mark] {
        guard !track.isDegenerate else { return [] }
        if track.detents == .stepped {
            return track.stops.map { stop in
                Mark(position: track.position(for: stop),
                     isMajor: track.majorStops.contains { track.matches($0, stop) })
            }
        }
        let spacing = 1.0 / Double(max(1, gridCount - 1))
        return (0..<gridCount).map { index in
            let position = Double(index) * spacing
            return Mark(position: position,
                        isMajor: track.stops.contains { abs(track.position(for: $0) - position) < spacing / 2 })
        }
    }
}

// MARK: - Glass

extension View {
    /// The director's control capsule. From iOS 26 it is the system's Liquid
    /// Glass, interactive so it answers a touch the way system controls do,
    /// with the system's own edge and adaptive tint. Before that, the nearest
    /// thing: a dark-tinted material with a hairline edge.
    @ViewBuilder func pillGlass() -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            glassEffect(.regular.interactive(), in: Capsule())
        } else {
            background(
                ZStack {
                    Color.black.opacity(0.3)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1)
                })
        }
    }
}

/// Groups neighbouring glass capsules so the system renders them as one
/// layer of glass (glass cannot sample glass) and morphs them as they come
/// and go. Spacing 0 keeps each capsule its own shape: they share the glass,
/// they do not melt into each other. Plain content before iOS 26.
struct PillGlassGroup<Content: View>: View {
    var spacing: CGFloat = 0
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

extension RulerPill where Leading == EmptyView, Trailing == EmptyView {
    /// A pill that collapses to its own content when idle (zoom).
    init(track: RulerTrack,
         currentValue: Double,
         readout: @escaping (Double) -> String,
         accessibilityLabel: String,
         collapsedWidth: CGFloat?,
         trackLength: CGFloat = 280,
         onChange: @escaping (Double) -> Void,
         @ViewBuilder collapsed: @escaping (RulerPillProxy) -> Collapsed) {
        self.init(track: track, currentValue: currentValue, readout: readout,
                  accessibilityLabel: accessibilityLabel, collapsesWhenIdle: true,
                  collapsedWidth: collapsedWidth, trackLength: trackLength, onChange: onChange,
                  collapsed: collapsed, leading: { _ in EmptyView() }, trailing: { _ in EmptyView() })
    }
}

extension RulerPill where Collapsed == EmptyView {
    /// A pill whose ruler is always up, with content at either end.
    init(track: RulerTrack,
         currentValue: Double,
         readout: @escaping (Double) -> String,
         accessibilityLabel: String,
         trackLength: CGFloat,
         axis: Axis,
         onChange: @escaping (Double) -> Void,
         @ViewBuilder leading: @escaping (RulerPillProxy) -> Leading,
         @ViewBuilder trailing: @escaping (RulerPillProxy) -> Trailing) {
        self.init(track: track, currentValue: currentValue, readout: readout,
                  accessibilityLabel: accessibilityLabel, collapsesWhenIdle: false,
                  trackLength: trackLength, axis: axis, onChange: onChange,
                  collapsed: { _ in EmptyView() }, leading: leading, trailing: trailing)
    }
}

/// A round button inside a pill: zoom's lens stops, the exposure strip's
/// AUTO / MANUAL. A tap gesture rather than a `Button` so it never competes
/// with the pill's drag for the touch.
struct PillCircleButton<Label: View>: View {
    var isActive = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    /// The iOS minimum touch target. Every circular control in a pill — a
    /// lens stop, a reset — is this big, so none needs aiming for.
    static var diameter: CGFloat { 44 }

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
