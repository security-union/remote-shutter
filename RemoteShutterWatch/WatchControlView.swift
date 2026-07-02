//
//  WatchControlView.swift
//  RemoteShutterWatch
//
//  Main Watch remote control UI. Crown is always locked to zoom.
//  No ScrollView — fixed layout so Digital Crown never gets stolen.
//
//  Collapsed by default: just the live preview, the shutter, and a settings
//  button. Tapping settings reveals the full control stack in place (zoom, lens,
//  flash/torch, camera flip, photo/video mode, timer) over the same screen.
//

import SwiftUI

struct WatchControlView: View {
    @EnvironmentObject var viewModel: WatchCameraViewModel
    @EnvironmentObject var session: WatchSessionDelegate

    /// Whether the secondary controls are revealed over the preview.
    @State private var showControls = false

    /// Drives focus onto the crown-rotation view. Without an explicitly focused
    /// view, watchOS logs "Crown Sequencer was set up without a view property"
    /// and the crown indicator can't track state.
    @FocusState private var isCrownFocused: Bool

    var body: some View {
        ZStack {
            previewBackground
            VStack(spacing: 6) {
                statusRow
                Spacer(minLength: 0)
                if showControls {
                    expandedControls
                } else {
                    collapsedControls
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 4)
            .navigationBarTitleDisplayMode(.inline)
            // Crown ALWAYS controls zoom — no ScrollView to steal it
            .focusable()
            .focused($isCrownFocused)
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
            .onAppear { isCrownFocused = true }
            // Event confirmation overlay
            .overlay {
                if viewModel.showEventConfirmation, let event = viewModel.lastEvent {
                    eventConfirmationView(event: event)
                }
            }
            // Self-timer countdown overlay (steady count + cancel)
            .overlay {
                if let remaining = viewModel.countdownRemaining {
                    countdownOverlay(remaining: remaining)
                }
            }
        }
    }

    // MARK: - Status + Zoom Label

    private var statusRow: some View {
        HStack {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .accessibilityLabel("Connected")
            // Zoom readout only matters when the zoom controls are on screen.
            if showControls {
                Text(viewModel.displayZoom)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .accessibilityLabel("Zoom \(viewModel.displayZoom)")
            }
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
    }

    // MARK: - Collapsed (shutter + settings only)

    private var collapsedControls: some View {
        HStack(spacing: 24) {
            shutterButton

            Button(action: { showControls = true }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show controls")
        }
    }

    // MARK: - Expanded (full control stack)

    private var expandedControls: some View {
        VStack(spacing: 6) {
            zoomSlider

            if viewModel.availableLensTypes.count > 1 {
                lensRow
            }

            // Flash (photo only) · torch · shutter · camera flip
            HStack(spacing: 12) {
                if viewModel.isPhotoMode {
                    flashButton
                }
                torchButton
                shutterButton
                cameraFlipButton
            }

            // Photo/video mode · timer/settings
            HStack(spacing: 12) {
                modeToggle

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

            // Full-width hide affordance — large tap target back to the preview.
            Button(action: { showControls = false }) {
                Image(systemName: "chevron.down")
                    .font(.body)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide controls")
        }
    }

    // MARK: - Zoom Slider (synced with crown)

    private var zoomRange: ClosedRange<Double> {
        let upper = max(viewModel.minZoomFactor + 0.1, viewModel.clampedMaxZoom)
        return viewModel.minZoomFactor...upper
    }

    private var zoomSlider: some View {
        Slider(
            value: Binding(
                get: { viewModel.crownZoomValue },
                set: { newValue in
                    viewModel.zoomChanged(newValue) { session.setZoom($0) }
                }
            ),
            in: zoomRange
        )
        .tint(.green)
        .accessibilityLabel("Zoom")
        .accessibilityValue(viewModel.displayZoom)
    }

    // MARK: - Lens Buttons

    private var lensRow: some View {
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

    // MARK: - Shutter

    private var shutterButton: some View {
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
    }

    // MARK: - Flash/Torch + Camera Flip Buttons

    /// Capture flash — only meaningful for photo capture, so shown in photo mode.
    private var flashButton: some View {
        Button(action: { session.toggleFlash() }) {
            Image(systemName: viewModel.isFlashEnabled ? "bolt.fill" : "bolt.slash.fill")
                .font(.title3)
                .foregroundColor(viewModel.isFlashEnabled ? .yellow : .white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.isFlashEnabled ? "Flash on" : "Flash off")
    }

    /// Continuous torch — a device-level light, available in both photo and video.
    private var torchButton: some View {
        Button(action: { session.toggleTorch() }) {
            Image(systemName: viewModel.isTorchEnabled ? "flashlight.on.fill" : "flashlight.off.fill")
                .font(.title3)
                .foregroundColor(viewModel.isTorchEnabled ? .yellow : .white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.isTorchEnabled ? "Torch on" : "Torch off")
    }

    private var cameraFlipButton: some View {
        Button(action: { session.toggleCamera() }) {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.title3)
                .foregroundColor(.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch front and back camera")
    }

    // MARK: - Live Preview Background

    /// Live camera preview behind the controls, dimmed so the white controls stay
    /// legible. `.scaledToFit()` keeps the full landscape frame visible (letterboxed).
    /// `nil` falls back to the default background before the first frame.
    @ViewBuilder
    private var previewBackground: some View {
        if let image = viewModel.previewImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(Color.black.opacity(0.35))
                .ignoresSafeArea()
        }
    }

    // MARK: - Photo/Video Mode Toggle

    private var modeToggle: some View {
        HStack(spacing: 0) {
            modeSegment(icon: "camera.fill", label: "Photo mode",
                        active: viewModel.isPhotoMode, mode: .photo)
            modeSegment(icon: "video.fill", label: "Video mode",
                        active: viewModel.isVideoMode, mode: .video)
        }
        .background(Color.gray.opacity(0.25))
        .clipShape(Capsule())
        .opacity(viewModel.isRecording ? 0.4 : 1.0)
        .disabled(viewModel.isRecording)
    }

    private func modeSegment(icon: String, label: LocalizedStringKey, active: Bool,
                             mode: RemoteShutter_RecordingModeEnum) -> some View {
        Button(action: {
            viewModel.selectMode(mode) { session.setMode($0) }
        }) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(active ? .black : .white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(active ? Color.white : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: - Shutter Accessibility

    private var shutterAccessibilityLabel: LocalizedStringKey {
        if viewModel.isVideoMode {
            return viewModel.isRecording ? "Stop recording" : "Start recording"
        } else {
            return "Take photo"
        }
    }

    // MARK: - Self-Timer Countdown

    @ViewBuilder
    private func countdownOverlay(remaining: Int) -> some View {
        VStack(spacing: 10) {
            Text("\(remaining)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)

            Button(action: {
                viewModel.cancelTimer { session.cancelTimer() }
            }) {
                Text("Cancel")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.85))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel timer")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.6).ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Self timer, \(remaining) seconds remaining")
    }

    // MARK: - Event Confirmation

    @ViewBuilder
    private func eventConfirmationView(event: RemoteShutter_WatchEventType) -> some View {
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

    private func iconForEvent(_ event: RemoteShutter_WatchEventType) -> String {
        switch event {
        case .phototaken: return "checkmark.circle.fill"
        case .recordingstarted: return "record.circle"
        case .recordingstopped: return "stop.circle.fill"
        case .photoerror, .recordingfailed, .sendfailed: return "xmark.circle.fill"
        case .microphonedenied: return "mic.slash.fill"
        case .busy, .busyrecording: return "hourglass"
        case .unknown: return "info.circle"
        }
    }

    private func colorForEvent(_ event: RemoteShutter_WatchEventType) -> Color {
        switch event {
        case .photoerror, .microphonedenied, .recordingfailed, .sendfailed: return .red
        case .recordingstarted: return .red
        case .busy, .busyrecording: return .orange
        case .phototaken, .recordingstopped, .unknown: return .green
        }
    }

    private func textForEvent(_ event: RemoteShutter_WatchEventType) -> LocalizedStringKey {
        switch event {
        case .phototaken: return "Photo Saved"
        case .recordingstarted: return "Recording"
        case .recordingstopped: return "Video Saved"
        case .photoerror: return "Photo Failed"
        case .recordingfailed: return "Recording Failed"
        case .sendfailed: return "Not Delivered"
        case .microphonedenied: return "Mic Denied"
        case .busy: return "Busy"
        case .busyrecording: return "Recording…"
        case .unknown: return ""
        }
    }
}
