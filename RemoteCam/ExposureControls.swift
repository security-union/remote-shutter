//
//  ExposureControls.swift
//  RemoteShutter
//
//  The director's exposure controls: three rulers (shutter, ISO, EV) on the
//  same `RulerPill` zoom uses, a readout strip with the light meter and the
//  AUTO / MANUAL chip, and the value → `SetExposure` mapping. Ranges come
//  from the focused camera's `ExposureState`, never from constants.
//  See Docs/pro-controls.md.
//

import SwiftUI

// MARK: - Stops and labels

enum ExposureStops {

    /// Standard shutter stops from 1/8000 s up to 1 s.
    static let shutterSeconds: [Double] = [
        1.0 / 8000, 1.0 / 4000, 1.0 / 2000, 1.0 / 1000, 1.0 / 500, 1.0 / 250,
        1.0 / 125, 1.0 / 60, 1.0 / 30, 1.0 / 15, 1.0 / 8, 1.0 / 4, 1.0 / 3,
        1.0 / 2, 1.0
    ]

    /// ISO in ⅓-stops.
    static let iso: [Double] = [
        25, 32, 40, 50, 64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640,
        800, 1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000, 10_000
    ]

    /// EV bias detents, one per stop. The ruler spans ±2 like Apple's dial;
    /// the device's own range (typically ±8) still bounds what is sent.
    static let bias: [Double] = [-2, -1, 0, 1, 2]
    static let biasRulerSpan: Double = 2

    /// "1/125" below a quarter second, "0.5s" / "1s" at or above.
    static func shutterLabel(_ seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        if seconds < 0.25 {
            return "1/\(Int((1.0 / seconds).rounded()))"
        }
        let formatted = seconds == seconds.rounded()
            ? String(Int(seconds)) : String(format: "%.1f", seconds)
        return "\(formatted)s"
    }

    static func isoLabel(_ iso: Double) -> String {
        "ISO \(Int(iso.rounded()))"
    }

    /// "+0.3 EV", "0 EV", "−1.7 EV".
    static func biasLabel(_ bias: Double) -> String {
        let rounded = (bias * 10).rounded() / 10
        if rounded == 0 { return "0 EV" }
        let sign = rounded > 0 ? "+" : "−"
        let magnitude = abs(rounded)
        let number = magnitude == magnitude.rounded() ? String(Int(magnitude)) : String(format: "%.1f", magnitude)
        return "\(sign)\(number) EV"
    }
}

// MARK: - Rulers

/// Which exposure ruler: shutter and ISO in Manual, EV in Auto.
enum ExposureRulerKind: Equatable, CaseIterable {
    case shutter
    case iso
    case bias

    /// The ruler's range and detents for this camera. Degenerate (drawn as
    /// nothing) when the camera reports no range for it.
    func track(_ exposure: ExposureState) -> RulerTrack {
        switch self {
        case .shutter:
            return RulerTrack(min: exposure.minDurationSeconds, max: exposure.maxDurationSeconds,
                              stops: ExposureStops.shutterSeconds)
        case .iso:
            return RulerTrack(min: Double(exposure.minISO), max: Double(exposure.maxISO),
                              stops: ExposureStops.iso)
        case .bias:
            let span = min(ExposureStops.biasRulerSpan, Double(max(-exposure.minBias, exposure.maxBias)))
            return RulerTrack(mapping: .linear, min: -span, max: span, stops: ExposureStops.bias)
        }
    }

    /// The camera's current value on this ruler.
    func value(_ exposure: ExposureState) -> Double {
        switch self {
        case .shutter: return exposure.durationSeconds
        case .iso: return Double(exposure.iso)
        case .bias: return Double(exposure.bias)
        }
    }

    func label(_ value: Double) -> String {
        switch self {
        case .shutter: return ExposureStops.shutterLabel(value)
        case .iso: return ExposureStops.isoLabel(value)
        case .bias: return ExposureStops.biasLabel(value)
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .shutter: return NSLocalizedString("Shutter speed", comment: "a11y")
        case .iso: return "ISO"
        case .bias: return NSLocalizedString("Exposure compensation", comment: "a11y")
        }
    }

    /// The wire intent for a ruler value. Shutter and ISO each set their own
    /// component and keep the other as the camera has it (`0` = keep), so
    /// dragging one never disturbs the other.
    func intent(for value: Double) -> ExposureIntent {
        switch self {
        case .shutter: return .manual(durationSeconds: value, iso: 0)
        case .iso: return .manual(durationSeconds: 0, iso: Float(value))
        case .bias: return .auto(bias: Float(value))
        }
    }

    /// EV is the one ruler with a "correct" value to go back to, so it is
    /// the one that carries a reset.
    var hasReset: Bool { self == .bias }

    /// The rulers a camera offers in its current mode: EV in Auto, shutter
    /// and ISO in Manual (only when the device accepts custom exposure).
    static func offered(by exposure: ExposureState) -> [ExposureRulerKind] {
        switch exposure.mode {
        case .auto: return [.bias]
        case .manual: return exposure.supportsManual ? [.shutter, .iso] : [.bias]
        }
    }
}

/// The column's geometry. Every ruler — zoom, shutter, ISO, EV — gets the
/// SAME track, so a thumb travels the same distance on each and the tick
/// fields line up; and every pill reserves the same slot at the end of that
/// track, filled by the reset on EV and empty elsewhere, so the capsules are
/// one width. Nothing gives up track length to carry a button.
enum ExposureRulerMetrics {
    static let horizontalTrack: CGFloat = 260
    static let verticalTrack: CGFloat = 240

    static func track(axis: Axis) -> CGFloat {
        axis == .vertical ? verticalTrack : horizontalTrack
    }

    /// The reserved slot at the end of every pill: one button wide.
    static var endSlot: CGFloat { PillCircleButton<Text>.diameter }
}

/// One exposure ruler, always up. Vertical on a side edge in landscape,
/// horizontal above the zoom pill in portrait. Every ruler a camera offers
/// is on screen at once — nothing is behind a toggle.
struct ExposureRulerPill: View {
    let kind: ExposureRulerKind
    let exposure: ExposureState
    let axis: Axis
    let onChange: (Double) -> Void

    var body: some View {
        RulerPill(track: kind.track(exposure),
                  currentValue: kind.value(exposure),
                  readout: { kind.label($0) },
                  accessibilityLabel: kind.accessibilityLabel,
                  trackLength: ExposureRulerMetrics.track(axis: axis),
                  axis: axis,
                  onChange: onChange,
                  leading: { _ in EmptyView() },
                  trailing: { proxy in
                      RulerEndSlot {
                          // Back to neutral. It commits through the pill, so
                          // the thumb returns on the tap rather than waiting
                          // for the camera to answer.
                          if kind.hasReset {
                              PillCircleButton(action: { proxy.commit(0) }) {
                                  Image(systemName: "arrow.uturn.backward")
                                      .font(.system(size: 16, weight: .semibold))
                              }
                              .accessibilityLabel(NSLocalizedString("Reset exposure compensation",
                                                                    comment: "a11y"))
                          }
                      }
                  })
    }
}

/// The slot every pill keeps at the end of its track. A ruler with nothing
/// to put there holds the space anyway, so one pill carrying a reset is not
/// wider than its neighbours.
struct RulerEndSlot<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Spacer(minLength: 0)
            content()
        }
        .frame(width: ExposureRulerMetrics.endSlot, height: ExposureRulerMetrics.endSlot)
    }
}

// MARK: - Readout strip

/// The AUTO / MANUAL switch and the light meter. Each ruler carries its own
/// value above its track, so this says only what no ruler can: which mode
/// the camera is in, and how far the frame is from the metered target.
struct ExposureReadoutStrip: View {
    let exposure: ExposureState
    let onSetMode: (ExposureMode) -> Void

    var body: some View {
        HStack(spacing: 14) {
            modeSwitch
            meter
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            ZStack {
                Color.black.opacity(0.3).background(.ultraThinMaterial).clipShape(Capsule())
                Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1)
            })
    }

    /// One tap between Auto and Manual, at the iOS minimum target size.
    /// Dimmed on a camera that cannot do manual exposure at all.
    private var modeSwitch: some View {
        let isManual = exposure.mode == .manual
        return Text(isManual
                    ? NSLocalizedString("MANUAL", comment: "exposure mode switch")
                    : NSLocalizedString("AUTO", comment: "exposure mode switch"))
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundColor(isManual ? .black : .white)
            .padding(.horizontal, 18)
            .frame(height: PillCircleButton<Text>.diameter)
            .background(Capsule().fill(isManual ? AppTheme.accent : Color.white.opacity(0.14)))
            .contentShape(Capsule())
            .onTapGesture { onSetMode(isManual ? .auto : .manual) }
            .opacity(exposure.supportsManual ? 1 : 0.35)
            .allowsHitTesting(exposure.supportsManual)
            .accessibilityLabel(NSLocalizedString("Manual exposure", comment: "a11y"))
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isManual ? "on" : "off")
    }

    /// The light meter: a needle over a ±2 stop scale, from the camera's
    /// `targetOffset`, captioned so it reads as an instrument rather than
    /// decoration. Balancing two dials by eye needs this, not a number: the
    /// dot goes gold within a third of a stop of the metered target.
    private var meter: some View {
        let offset = max(-Self.meterStops, min(Self.meterStops, Double(exposure.targetOffset)))
        return VStack(spacing: 3) {
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: Self.meterWidth, height: 1)
                // One tick per stop, the target taller — the scale is what
                // makes the dot's distance from centre mean something.
                ForEach(Array(stride(from: -Self.meterStops, through: Self.meterStops, by: 1)), id: \.self) { stop in
                    Rectangle()
                        .fill(Color.white.opacity(stop == 0 ? 0.7 : 0.35))
                        .frame(width: 1, height: stop == 0 ? 12 : 6)
                        .offset(x: Self.meterOffset(stop))
                }
                Circle()
                    .fill(abs(offset) < 0.3 ? AppTheme.accent : Color.white)
                    .frame(width: 9, height: 9)
                    .offset(x: Self.meterOffset(offset))
            }
            .frame(width: Self.meterWidth, height: 14)

            Text(NSLocalizedString("METER", comment: "light meter legend"))
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: Self.meterWidth)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NSLocalizedString("Light meter", comment: "a11y"))
        .accessibilityValue(ExposureStops.biasLabel(offset))
    }

    /// Half the scale, in stops either side of the metered target.
    private static let meterStops: Double = 2
    private static let meterWidth: CGFloat = 64
    /// Where a value in stops sits on the scale, for the ticks and the dot
    /// alike, so a tick and the needle at the same value coincide exactly.
    private static func meterOffset(_ stops: Double) -> CGFloat {
        CGFloat(stops / meterStops) * (meterWidth / 2)
    }
}

// MARK: - Send throttle

/// A ruler's stream of values, rate-limited the way zoom is
/// (`ZoomSendThrottle`: leading edge for responsiveness, trailing edge so the
/// final position always lands). One per ruler, owned by the screen's
/// controller; the send closure turns the value into the wire command.
final class ThrottledValueSender {
    private var throttle: ZoomSendThrottle
    private var trailing: Timer?
    private let send: (Double) -> Void

    init(interval: TimeInterval = 0.1, send: @escaping (Double) -> Void) {
        throttle = ZoomSendThrottle(interval: interval)
        self.send = send
    }

    func submit(_ value: Double) {
        switch throttle.update(value: value, now: Date()) {
        case .sendNow:
            send(value)
        case .scheduleTrailing:
            trailing?.invalidate()
            trailing = Timer.scheduledTimer(withTimeInterval: throttle.interval, repeats: false) { [weak self] _ in
                guard let self, let pending = self.throttle.fireTrailing(now: Date()) else { return }
                self.send(pending)
            }
        }
    }

    deinit { trailing?.invalidate() }
}
