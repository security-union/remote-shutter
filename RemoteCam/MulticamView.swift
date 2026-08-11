//
//  MulticamView.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import SwiftUI

/// The director screen in focus mode: the selected camera fills the viewfinder
/// (reusing the 1:1 monitor's `LiveFrameView` so it looks and behaves the same)
/// with a floating strip of the other cameras' live thumbnails. Grid mode is a
/// later PR; this is the default surface.
struct MulticamView: View {
    @ObservedObject var viewModel: MulticamViewModel

    /// Tap a thumbnail to make that camera the focused one.
    let onFocusLane: (CameraLane) -> Void
    /// The synced shutter — photo, or record start/stop depending on mode.
    let onShutter: () -> Void
    /// Toggle the shutter between photo and video mode.
    let onToggleMode: () -> Void

    var body: some View {
        GeometryReader { geo in
            let dock = MonitorChromeLayout.dock(
                viewSize: geo.size,
                interfaceOrientation: viewModel.interfaceOrientation,
                input: chromeInput)

            ZStack {
                Color.black.ignoresSafeArea()

                focusedViewfinder

                stripOverlay(dock: dock)

                shutterOverlay(dock: dock)
            }
        }
    }

    /// The all-camera shutter + a photo/video mode toggle, docked on the same
    /// edge the 1:1 monitor uses. Reuses the monitor's `ShutterButton` (and its
    /// activity ring) so the two screens feel of a piece.
    @ViewBuilder
    private func shutterOverlay(dock: MonitorChromeDock) -> some View {
        let shutter = ShutterButton(
            uiState: viewModel.mode == .video ? .videoMode : .photoMode,
            isRecording: viewModel.isRecording,
            activity: viewModel.isCapturing ? .capturing : nil,
            isEnabled: !viewModel.isCapturing && viewModel.focusedLane != nil,
            action: onShutter)

        // The mode toggle is hidden while recording (you can't switch mid-clip).
        let modeToggle = Button(action: onToggleMode) {
            Image(systemName: viewModel.mode == .video ? "video.fill" : "camera.fill")
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.4))
                .clipShape(Circle())
        }
        .opacity(viewModel.isRecording ? 0 : 1)
        .disabled(viewModel.isRecording)

        switch dock {
        case .bottom:
            VStack {
                Spacer()
                ZStack {
                    shutter
                    HStack { Spacer(); modeToggle.padding(.trailing, 40) }
                }
                .padding(.bottom, 24)
            }
        case .leading:
            HStack {
                VStack { Spacer(); modeToggle; shutter; Spacer() }.padding(.leading, 24)
                Spacer()
            }
        case .trailing:
            HStack {
                Spacer()
                VStack { Spacer(); modeToggle; shutter; Spacer() }.padding(.trailing, 24)
            }
        }
    }

    private var chromeInput: MonitorChromeInput {
        #if targetEnvironment(macCatalyst)
        return .pointer
        #else
        return .touch
        #endif
    }

    @ViewBuilder
    private var focusedViewfinder: some View {
        if let focused = viewModel.focusedLane {
            LiveFrameView(frames: focused.frames, aspectRatio: .sixteenNine)
                .ignoresSafeArea()
        } else {
            // No camera focused yet (all reconnecting, or none linked).
            Rectangle()
                .fill(Color.gray.opacity(0.25))
                .overlay(
                    Image(systemName: "video.slash")
                        .font(.system(size: 44))
                        .foregroundColor(.white.opacity(0.5)))
                .ignoresSafeArea()
        }
    }

    /// The thumbnail rail, docked opposite the (future) action cluster on the
    /// same axis the 1:1 chrome uses, so the two screens feel of a piece.
    @ViewBuilder
    private func stripOverlay(dock: MonitorChromeDock) -> some View {
        let others = viewModel.otherLanes
        if !others.isEmpty {
            switch dock {
            case .bottom:
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        ForEach(others) { lane in
                            CameraTileView(lane: lane, isThumbnail: true)
                                .frame(width: 96, height: 128)
                                .onTapGesture { onFocusLane(lane) }
                        }
                    }
                    .padding(.bottom, 96)
                }
            case .leading, .trailing:
                HStack {
                    if dock == .trailing { Spacer() }
                    VStack(spacing: 8) {
                        ForEach(others) { lane in
                            CameraTileView(lane: lane, isThumbnail: true)
                                .frame(width: 128, height: 96)
                                .onTapGesture { onFocusLane(lane) }
                        }
                    }
                    .padding(dock == .leading ? .leading : .trailing, 12)
                    if dock == .leading { Spacer() }
                }
            }
        }
    }
}

/// One camera's tile: its isolated live frame, a name chip, a focus ring, and
/// a reconnecting scrim. `Equatable` on the value inputs so a frame delivered
/// to another lane can't invalidate this tile's chrome — only its own
/// `LiveFrameView` (observing its own `FrameDisplayModel`) re-renders.
struct CameraTileView: View {
    @ObservedObject var lane: CameraLane
    var isThumbnail: Bool = false

    var body: some View {
        ZStack {
            LiveFrameView(frames: lane.frames, aspectRatio: .sixteenNine)
                .clipShape(RoundedRectangle(cornerRadius: isThumbnail ? 10 : 0))
                .saturation(lane.status == .linked ? 1 : 0)

            if lane.status == .reconnecting {
                RoundedRectangle(cornerRadius: isThumbnail ? 10 : 0)
                    .fill(Color.black.opacity(0.45))
                    .overlay(
                        Text(NSLocalizedString("RECONNECTING", comment: "peer link dropped"))
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.white))
            }

            if lane.isRecording {
                VStack {
                    HStack {
                        Image(systemName: "record.circle.fill")
                            .font(.body)
                            .foregroundColor(.red)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(6)
            } else if let outcome = lane.captureOutcome {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: outcome == .captured
                              ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.body)
                            .foregroundColor(outcome == .captured ? .green : .yellow)
                            .padding(6)
                    }
                    Spacer()
                }
            }

            VStack {
                Spacer()
                Text(lane.displayName)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())
                    .padding(4)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: isThumbnail ? 10 : 0)
                .stroke(lane.isFocused ? AppTheme.accent : .clear, lineWidth: 3))
    }
}
