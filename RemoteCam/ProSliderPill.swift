//
//  ProSliderPill.swift
//  RemoteShutter
//
//  Manual exposure (shutter, ISO) and Cinematic aperture as viewfinder
//  sliders in the zoom pill's slot: the same `RulerPill` zoom uses, with the
//  ruler always up and AUTO / × buttons at its ends. This file adds only
//  what is pro-specific — which slider, its range and labels from the
//  camera's echoed state, and the command a value becomes.
//  See Docs/pro-controls.md.
//

import SwiftUI

/// Which pro slider sits on the viewfinder (at most one at a time).
enum ProSliderKind: Equatable, CaseIterable {
    case shutter
    case iso
    case aperture

    /// The tray tile that opens this slider.
    var tile: MonitorTrayItem {
        switch self {
        case .shutter: return .shutter
        case .iso: return .iso
        case .aperture: return .aperture
        }
    }

    var title: String {
        switch self {
        case .shutter: return NSLocalizedString("SHUTTER", comment: "pro slider")
        case .iso: return "ISO"
        case .aperture: return NSLocalizedString("APERTURE", comment: "pro slider")
        }
    }

    /// The wire intent for a slider value. Shutter and ISO each lock their
    /// own component and keep the other as the camera has it (`0` = keep),
    /// so dragging one never disturbs the other; aperture rides Cinematic on.
    func intent(for value: Double) -> ProControlIntent {
        switch self {
        case .shutter: return .exposure(.manual(durationSeconds: value, iso: 0))
        case .iso: return .exposure(.manual(durationSeconds: 0, iso: Float(value)))
        case .aperture: return .cinematic(.on(aperture: Float(value)))
        }
    }
}

/// A pro-control request, typed by the command it becomes.
enum ProControlIntent: Equatable {
    case exposure(ExposureIntent)
    case cinematic(CinematicIntent)
}

/// One slider's range and labels, from the camera's echoed state — the pro
/// analog of `ZoomScale`: it owns the units, `LogTrack` owns the ruler.
struct ProSliderScale: Equatable {
    let kind: ProSliderKind
    let track: LogTrack

    static func shutter(_ exposure: ExposureState) -> ProSliderScale {
        ProSliderScale(kind: .shutter,
                       track: LogTrack(min: exposure.minDurationSeconds, max: exposure.maxDurationSeconds,
                                       stops: ProStops.allShutterSeconds))
    }

    static func iso(_ exposure: ExposureState) -> ProSliderScale {
        ProSliderScale(kind: .iso,
                       track: LogTrack(min: Double(exposure.minISO), max: Double(exposure.maxISO),
                                       stops: ProStops.allISO.map { Double($0) }))
    }

    static func aperture(_ cinematic: CinematicState) -> ProSliderScale {
        ProSliderScale(kind: .aperture,
                       track: LogTrack(min: Double(cinematic.minSimulatedAperture),
                                       max: Double(cinematic.maxSimulatedAperture),
                                       stops: ProStops.allApertures.map { Double($0) }))
    }

    func label(_ value: Double) -> String {
        switch kind {
        case .shutter: return ProStops.shutterLabel(value)
        case .iso: return ProStops.isoLabel(Float(value))
        case .aperture: return ProStops.apertureLabel(Float(value))
        }
    }
}

// MARK: - Pill

struct ProSliderPill: View {
    let scale: ProSliderScale
    /// The camera's confirmed value.
    let currentValue: Double
    let onChange: (Double) -> Void
    /// Exposure sliders offer AUTO (hands exposure back to the camera and
    /// closes the pill); the aperture slider has no auto, so nil there.
    let onAuto: (() -> Void)?
    let onClose: () -> Void

    /// Narrower than zoom's track: the AUTO and × circles share the width.
    private static let trackWidth: CGFloat = 200

    var body: some View {
        RulerPill(track: scale.track,
                  currentValue: currentValue,
                  readout: { "\(scale.kind.title)  \(scale.label($0))" },
                  accessibilityLabel: scale.kind.title,
                  trackWidth: Self.trackWidth,
                  onChange: onChange,
                  leading: {
                      if let onAuto {
                          PillCircleButton(action: onAuto) {
                              Text(NSLocalizedString("AUTO", comment: "exposure back to auto"))
                                  .font(.system(size: 10, weight: .bold, design: .rounded))
                          }
                          .accessibilityLabel(NSLocalizedString("Auto exposure", comment: "a11y"))
                      }
                  },
                  trailing: {
                      PillCircleButton(action: onClose) {
                          Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                      }
                      .accessibilityLabel(NSLocalizedString("Close", comment: "a11y"))
                  })
    }
}

// MARK: - Send throttle

/// A slider's stream of values, rate-limited the way zoom is
/// (`ZoomSendThrottle`: leading edge for responsiveness, trailing edge so the
/// final position always lands). One per slider, owned by the screen's
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
