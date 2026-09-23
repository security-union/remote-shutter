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

    /// The rulers a camera offers in its current mode: EV in Auto, shutter
    /// and ISO in Manual (only when the device accepts custom exposure).
    static func offered(by exposure: ExposureState) -> [ExposureRulerKind] {
        switch exposure.mode {
        case .auto: return [.bias]
        case .manual: return exposure.supportsManual ? [.shutter, .iso] : [.bias]
        }
    }
}

/// One exposure ruler, always up. Vertical on a side edge in landscape,
/// horizontal in the zoom pill's slot in portrait.
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
                  trackLength: axis == .vertical ? 200 : 240,
                  axis: axis,
                  onChange: onChange,
                  leading: { EmptyView() },
                  trailing: { EmptyView() })
    }
}

// MARK: - Readout strip

/// The top plate of a camera: shutter, ISO, EV and the light meter as
/// values, plus the AUTO / MANUAL chip. Tapping a readout is how portrait
/// picks which ruler takes the zoom pill's slot.
struct ExposureReadoutStrip: View {
    let exposure: ExposureState
    /// The ruler currently shown in the zoom pill's slot (portrait), if any.
    let selected: ExposureRulerKind?
    let onSelect: (ExposureRulerKind) -> Void
    let onSetMode: (ExposureMode) -> Void

    var body: some View {
        HStack(spacing: 8) {
            PillCircleButton(isActive: exposure.mode == .manual, action: {
                onSetMode(exposure.mode == .manual ? .auto : .manual)
            }) {
                Text(exposure.mode == .manual
                     ? NSLocalizedString("MANUAL", comment: "exposure mode chip")
                     : NSLocalizedString("AUTO", comment: "exposure mode chip"))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 3)
            }
            .opacity(exposure.supportsManual ? 1 : 0.35)
            .allowsHitTesting(exposure.supportsManual)
            .accessibilityLabel(NSLocalizedString("Manual exposure", comment: "a11y"))
            .accessibilityValue(exposure.mode == .manual ? "on" : "off")

            ForEach(ExposureRulerKind.offered(by: exposure), id: \.self) { kind in
                readout(kind)
            }

            meter
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            ZStack {
                Color.black.opacity(0.3).background(.ultraThinMaterial).clipShape(Capsule())
                Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1)
            })
    }

    private func readout(_ kind: ExposureRulerKind) -> some View {
        Text(kind.label(kind.value(exposure)))
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigitIfAvailable()
            .foregroundColor(selected == kind ? .black : .white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(selected == kind ? AppTheme.accent : Color.white.opacity(0.12)))
            .contentShape(Capsule())
            .onTapGesture { onSelect(kind) }
            .accessibilityLabel(kind.accessibilityLabel)
            .accessibilityAddTraits(.isButton)
    }

    /// The light meter: a needle over a ±2 stop scale, from the camera's
    /// `targetOffset`. Balancing two dials by eye needs this, not a number.
    private var meter: some View {
        let offset = max(-2, min(2, Double(exposure.targetOffset)))
        return ZStack {
            Rectangle().fill(Color.white.opacity(0.35)).frame(width: 44, height: 1)
            Rectangle().fill(Color.white.opacity(0.6)).frame(width: 1, height: 8)
            Circle()
                .fill(abs(offset) < 0.3 ? AppTheme.accent : Color.white)
                .frame(width: 6, height: 6)
                .offset(x: CGFloat(offset / 2) * 22)
        }
        .frame(width: 44, height: 14)
        .accessibilityLabel(NSLocalizedString("Light meter", comment: "a11y"))
        .accessibilityValue(ExposureStops.biasLabel(offset))
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
