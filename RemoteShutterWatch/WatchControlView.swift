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
                Text(viewModel.displayZoom)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Spacer()
                if viewModel.isRecording {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("REC")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 4)

            // MARK: - Zoom Slider (synced with crown)
            Slider(
                value: Binding(
                    get: { viewModel.crownZoomValue },
                    set: { newValue in
                        viewModel.crownZoomValue = newValue
                        if viewModel.shouldSendZoom() {
                            session.setZoom(newValue)
                        }
                    }
                ),
                in: viewModel.minZoomFactor...max(viewModel.minZoomFactor + 0.1, viewModel.clampedMaxZoom)
            )
            .tint(.green)

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
                    }
                }
            }

            // MARK: - Shutter + Controls Row
            HStack(spacing: 12) {
                // Torch
                Button(action: { session.toggleTorch() }) {
                    Image(systemName: viewModel.isTorchEnabled
                          ? "flashlight.on.fill"
                          : "flashlight.off.fill")
                        .font(.title3)
                        .foregroundColor(viewModel.isTorchEnabled ? .yellow : .white)
                }
                .buttonStyle(.plain)

                // Shutter button
                Button(action: {
                    if viewModel.isVideoMode {
                        if viewModel.isRecording {
                            session.stopRecording()
                        } else {
                            session.startRecording()
                        }
                    } else {
                        session.takePicture()
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

                // Camera toggle
                Button(action: { session.toggleCamera() }) {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        // Crown ALWAYS controls zoom — no ScrollView to steal it
        // Wide raw range (0-100) so each crown tick produces a tiny zoom change
        .focusable()
        .digitalCrownRotation(
            $viewModel.crownRawValue,
            from: 0.0,
            through: 50.0,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: viewModel.crownRawValue) { newValue in
            let zoom = viewModel.zoomFromCrown(newValue)
            viewModel.crownZoomValue = zoom
            if viewModel.shouldSendZoom() {
                session.setZoom(zoom)
            }
        }
        // Event confirmation overlay
        .overlay {
            if viewModel.showEventConfirmation, let event = viewModel.lastEvent {
                eventConfirmationView(event: event)
            }
        }
    }

    // MARK: - Event Confirmation

    @ViewBuilder
    private func eventConfirmationView(event: String) -> some View {
        VStack {
            Image(systemName: iconForEvent(event))
                .font(.title)
                .foregroundColor(.green)
            Text(textForEvent(event))
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .transition(.opacity)
    }

    private func iconForEvent(_ event: String) -> String {
        switch event {
        case "photoTaken": return "checkmark.circle.fill"
        case "recordingStarted": return "record.circle"
        case "recordingStopped": return "stop.circle.fill"
        default: return "info.circle"
        }
    }

    private func textForEvent(_ event: String) -> String {
        switch event {
        case "photoTaken": return "Photo Saved"
        case "recordingStarted": return "Recording"
        case "recordingStopped": return "Video Saved"
        case "photoError": return "Photo Failed"
        case "microphoneDenied": return "Mic Denied"
        default: return event
        }
    }
}
