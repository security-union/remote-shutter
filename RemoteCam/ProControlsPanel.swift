//
//  ProControlsPanel.swift
//  RemoteShutter
//
//  The pro-controls bottom panel on the monitor: manual exposure (shutter +
//  ISO) and Cinematic video (iOS 26 simulated aperture). Every value shown is
//  the CAMERA's echoed truth (`MonitorViewModel.exposure` / `.cinematic`) —
//  the panel never displays a value the camera did not confirm. Controls are
//  rendered only when the connected camera advertised the capability.
//  See Docs/pro-controls.md.
//

import SwiftUI

struct ProControlsPanel: View {
    @ObservedObject var viewModel: MonitorViewModel
    let onExposureChange: (ExposureIntent) -> Void
    let onCinematicChange: (CinematicIntent) -> Void

    private var isVideoMode: Bool {
        viewModel.uiState == .videoMode || viewModel.uiState == .videoRecording
    }

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 5)

            if viewModel.supportsManualExposure, let exposure = viewModel.exposure {
                exposureSection(exposure)
            }

            if isVideoMode, viewModel.supportsCinematicVideo, let cinematic = viewModel.cinematic {
                if viewModel.supportsManualExposure {
                    Divider().overlay(Color.white.opacity(0.15))
                }
                cinematicSection(cinematic)
            }
        }
        .padding(.top, 10)
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Exposure

    @ViewBuilder
    private func exposureSection(_ exposure: ExposureState) -> some View {
        HStack {
            sectionTitle(NSLocalizedString("EXPOSURE", comment: "pro panel section"))
            Spacer()
            Picker("", selection: Binding(
                get: { exposure.mode == .manual },
                set: { manual in
                    // Manual with zeros = "lock what auto is doing right now",
                    // so the dials pick up from a correctly exposed frame.
                    onExposureChange(manual ? .manual(durationSeconds: 0, iso: 0) : .auto)
                })) {
                Text(NSLocalizedString("Auto", comment: "exposure mode")).tag(false)
                Text(NSLocalizedString("Manual", comment: "exposure mode")).tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
        }

        if exposure.mode == .manual {
            ProDial(
                caption: NSLocalizedString("SHUTTER", comment: "pro dial"),
                stops: ProDialStops.shutterStops(min: exposure.minDurationSeconds,
                                                 max: exposure.maxDurationSeconds),
                value: exposure.durationSeconds,
                label: { ProDialStops.shutterLabel($0) },
                accessibilityValue: { seconds in
                    String(format: NSLocalizedString("%@ second", comment: "shutter a11y"),
                           ProDialStops.shutterLabel(seconds))
                },
                onSelect: { onExposureChange(.manual(durationSeconds: $0, iso: 0)) })

            ProDial(
                caption: "ISO",
                stops: ProDialStops.isoStops(min: exposure.minISO, max: exposure.maxISO)
                    .map { Double($0) },
                value: Double(exposure.iso),
                label: { String(Int($0.rounded())) },
                accessibilityValue: { "ISO \(Int($0.rounded()))" },
                onSelect: { onExposureChange(.manual(durationSeconds: 0, iso: Float($0))) })
        } else {
            // What auto is choosing right now — what Manual would take over.
            Text("\(ProDialStops.shutterLabel(exposure.durationSeconds)) · \(ProDialStops.isoLabel(exposure.iso))")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    // MARK: - Cinematic

    @ViewBuilder
    private func cinematicSection(_ cinematic: CinematicState) -> some View {
        HStack {
            sectionTitle(NSLocalizedString("CINEMATIC", comment: "pro panel section"))
            Spacer()
            Toggle("", isOn: Binding(
                get: { cinematic.enabled },
                set: { isOn in onCinematicChange(isOn ? .on(aperture: nil) : .off) }))
                .labelsHidden()
                .tint(AppTheme.accent)
                // Apple rejects enabling/disabling mid-take.
                .disabled(cinematic.apertureLocked)
                .accessibilityLabel(NSLocalizedString("Cinematic video", comment: "a11y"))
        }

        if cinematic.enabled, cinematic.minSimulatedAperture > 0 {
            ProDial(
                caption: NSLocalizedString("APERTURE", comment: "pro dial"),
                stops: ProDialStops.apertureStops(min: cinematic.minSimulatedAperture,
                                                  max: cinematic.maxSimulatedAperture)
                    .map { Double($0) },
                value: Double(cinematic.simulatedAperture),
                label: { ProDialStops.apertureLabel(Float($0)) },
                accessibilityValue: { ProDialStops.apertureLabel(Float($0)) },
                onSelect: { onCinematicChange(.on(aperture: Float($0))) })
                .disabled(cinematic.apertureLocked)
                .opacity(cinematic.apertureLocked ? 0.4 : 1)

            if cinematic.apertureLocked {
                footnote(NSLocalizedString("Aperture is set before recording",
                                           comment: "cinematic hint"))
            }
        }

        if cinematic.enabled && cinematic.notEnoughLight {
            footnote(NSLocalizedString("Scene too dark for Cinematic",
                                       comment: "cinematic hint"))
        }
    }

    // MARK: - Bits

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .tracking(1)
            .foregroundColor(.white.opacity(0.6))
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.white.opacity(0.7))
    }
}

// MARK: - Dial

/// A detented value dial: chevrons step one stop, dragging scrubs stops with a
/// haptic tick per detent. Shows the camera's echoed value; a step calls
/// `onSelect` with the neighboring stop and waits for the echo to move the
/// label (the remote never claims a state the camera did not confirm).
struct ProDial: View {
    let caption: String
    let stops: [Double]
    let value: Double
    let label: (Double) -> String
    let accessibilityValue: (Double) -> String
    let onSelect: (Double) -> Void

    /// Points of horizontal drag per detent.
    private static let dragStride: CGFloat = 24

    @State private var dragBaseIndex: Int?
    @State private var lastDraggedIndex: Int?

    private var currentIndex: Int { ProDialStops.nearestIndex(of: value, in: stops) ?? 0 }

    var body: some View {
        HStack(spacing: 14) {
            Text(caption)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 64, alignment: .leading)

            stepButton(systemName: "chevron.left", step: -1)

            Text(stops.isEmpty ? "—" : label(stops[currentIndex]))
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(dragGesture)

            stepButton(systemName: "chevron.right", step: +1)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .accessibilityValue(stops.isEmpty ? "" : accessibilityValue(stops[currentIndex]))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: select(currentIndex + 1)
            case .decrement: select(currentIndex - 1)
            @unknown default: break
            }
        }
    }

    private func stepButton(systemName: String, step: Int) -> some View {
        Button { select(currentIndex + step) } label: {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { gesture in
                let base = dragBaseIndex ?? currentIndex
                dragBaseIndex = base
                let offset = Int((gesture.translation.width / Self.dragStride).rounded())
                let target = max(0, min(stops.count - 1, base + offset))
                if target != (lastDraggedIndex ?? base) {
                    lastDraggedIndex = target
                    tick()
                    onSelect(stops[target])
                }
            }
            .onEnded { _ in
                dragBaseIndex = nil
                lastDraggedIndex = nil
            }
    }

    private func select(_ index: Int) {
        guard !stops.isEmpty else { return }
        let clamped = max(0, min(stops.count - 1, index))
        guard clamped != currentIndex else { return }
        tick()
        onSelect(stops[clamped])
    }

    private func tick() {
        #if !targetEnvironment(macCatalyst)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}
