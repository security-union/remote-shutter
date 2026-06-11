//
//  WatchControlView.swift
//  RemoteShutterWatch
//
//  Main Watch remote control UI. Crown is always locked to zoom.
//  No ScrollView — fixed layout so Digital Crown never gets stolen.
//

import SwiftUI

struct WatchControlView: View {
    @EnvironmentObject var viewModel: WatchCameraViewModel
    @EnvironmentObject var session: WatchSessionDelegate

    var body: some View {
        VStack(spacing: 6) {
            // MARK: - Status + Zoom Label
            HStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Connected")
                Text(viewModel.displayZoom)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .accessibilityLabel("Zoom \(viewModel.displayZoom)")
                Spacer()
                if viewModel.isRecording {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("REC")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .accessibilityLabel("Recording in progress")
                }
            }
            .padding(.horizontal, 4)

            // MARK: - Zoom Slider (synced with crown)
            Slider(
                value: Binding(
                    get: { viewModel.crownZoomValue },
                    set: { newValue in
                        viewModel.zoomChanged(newValue) { session.setZoom($0) }
                    }
                ),
                in: viewModel.minZoomFactor...max(viewModel.minZoomFactor + 0.1, viewModel.clampedMaxZoom)
            )
            .tint(.green)
            .accessibilityLabel("Zoom")
            .accessibilityValue(viewModel.displayZoom)

            // MARK: - Lens Buttons
            if viewModel.availableLensTypes.count > 1 {
                HStack(spacing: 6) {
                    ForEach(viewModel.availableLensTypes, id: \.rawValue) { lens in
                        Button(action: {
                            session.switchLens(lens)
                        }) {
                            Text(lens.displayName)
                                .font(.caption2)
                                .fontWeight(lens == viewModel.currentLensType ? .bold : .regular)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    lens == viewModel.currentLensType
                                        ? Color.green.opacity(0.3)
                                        : Color.gray.opacity(0.3)
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(lens.displayName) lens")
                        .accessibilityAddTraits(lens == viewModel.currentLensType ? .isSelected : [])
                    }
                }
            }

            // MARK: - Shutter + Controls Row
            HStack(spacing: 12) {
                // Flash (photo mode) / Torch (video mode)
                Button(action: {
                    if viewModel.isPhotoMode {
                        session.toggleFlash()
                    } else {
                        session.toggleTorch()
                    }
                }) {
                    Image(systemName: flashTorchIcon)
                        .font(.title3)
                        .foregroundColor(flashTorchColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(flashTorchAccessibilityLabel)

                // Shutter button
                Button(action: {
                    if viewModel.isVideoMode {
                        if viewModel.isRecording {
                            session.stopRecording()
                        } else {
                            session.startRecording(timerSeconds: viewModel.timerSeconds)
                        }
                    } else {
                        session.takePicture(timerSeconds: viewModel.timerSeconds)
                    }
                }) {
                    ZStack {
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 3)
                            .frame(width: 50, height: 50)

                        if viewModel.isVideoMode {
                            if viewModel.isRecording {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.red)
                                    .frame(width: 18, height: 18)
                            } else {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 38, height: 38)
                            }
                        } else {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 38, height: 38)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(shutterAccessibilityLabel)

                // Camera flip (front/back)
                Button(action: { session.toggleCamera() }) {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Switch front and back camera")
            }

            // Timer indicator (tappable → settings)
            NavigationLink(destination: WatchSettingsView()) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.timerSeconds > 0 ? "timer" : "gearshape")
                        .font(.caption2)
                    if viewModel.timerSeconds > 0 {
                        Text("\(viewModel.timerSeconds)s")
                            .font(.caption2)
                    }
                }
                .foregroundColor(viewModel.timerSeconds > 0 ? .orange : .gray)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.timerSeconds > 0
                ? "Timer \(viewModel.timerSeconds) seconds, open settings"
                : "Settings")
        }
        .padding(.horizontal, 4)
        .navigationBarTitleDisplayMode(.inline)
        // Crown ALWAYS controls zoom — no ScrollView to steal it
        .focusable()
        .digitalCrownRotation(
            $viewModel.crownRawValue,
            from: 0.0,
            through: 50.0,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: viewModel.crownRawValue) {
            let zoom = viewModel.zoomFromCrown(viewModel.crownRawValue)
            viewModel.zoomChanged(zoom) { session.setZoom($0) }
        }
        // Event confirmation overlay
        .overlay {
            if viewModel.showEventConfirmation, let event = viewModel.lastEvent {
                eventConfirmationView(event: event)
            }
        }
    }

    // MARK: - Flash/Torch Helpers

    private var flashTorchIcon: String {
        if viewModel.isPhotoMode {
            return viewModel.isFlashEnabled ? "bolt.fill" : "bolt.slash.fill"
        } else {
            return viewModel.isTorchEnabled ? "flashlight.on.fill" : "flashlight.off.fill"
        }
    }

    private var flashTorchColor: Color {
        if viewModel.isPhotoMode {
            return viewModel.isFlashEnabled ? .yellow : .white
        } else {
            return viewModel.isTorchEnabled ? .yellow : .white
        }
    }

    private var flashTorchAccessibilityLabel: String {
        if viewModel.isPhotoMode {
            return viewModel.isFlashEnabled ? "Flash on" : "Flash off"
        } else {
            return viewModel.isTorchEnabled ? "Torch on" : "Torch off"
        }
    }

    // MARK: - Shutter Accessibility

    private var shutterAccessibilityLabel: String {
        if viewModel.isVideoMode {
            return viewModel.isRecording ? "Stop recording" : "Start recording"
        } else {
            return "Take photo"
        }
    }

    // MARK: - Event Confirmation

    @ViewBuilder
    private func eventConfirmationView(event: String) -> some View {
        VStack {
            Image(systemName: iconForEvent(event))
                .font(.title)
                .foregroundColor(colorForEvent(event))
            Text(textForEvent(event))
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(textForEvent(event))
    }

    private func iconForEvent(_ event: String) -> String {
        if event.hasPrefix("countdown:") { return "timer" }
        switch event {
        case "photoTaken": return "checkmark.circle.fill"
        case "recordingStarted": return "record.circle"
        case "recordingStopped": return "stop.circle.fill"
        case "photoError", "recordingFailed", "sendFailed": return "xmark.circle.fill"
        case "microphoneDenied": return "mic.slash.fill"
        case "busy", "busyRecording": return "hourglass"
        default: return "info.circle"
        }
    }

    private func colorForEvent(_ event: String) -> Color {
        if event.hasPrefix("countdown:") { return .orange }
        switch event {
        case "photoError", "microphoneDenied", "recordingFailed", "sendFailed": return .red
        case "recordingStarted": return .red
        case "busy", "busyRecording": return .orange
        default: return .green
        }
    }

    private func textForEvent(_ event: String) -> String {
        if let seconds = event.split(separator: ":").last, event.hasPrefix("countdown:") {
            return "\(seconds)s"
        }
        switch event {
        case "photoTaken": return "Photo Saved"
        case "recordingStarted": return "Recording"
        case "recordingStopped": return "Video Saved"
        case "photoError": return "Photo Failed"
        case "recordingFailed": return "Recording Failed"
        case "sendFailed": return "Not Delivered"
        case "microphoneDenied": return "Mic Denied"
        case "busy": return "Busy"
        case "busyRecording": return "Recording…"
        default: return event
        }
    }
}
