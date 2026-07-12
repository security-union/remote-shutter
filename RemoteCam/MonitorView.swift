import SwiftUI
import UIKit
import Combine

// MARK: - Monitor View
struct MonitorView: View {
    @ObservedObject var viewModel: MonitorViewModel
    @State private var zoomAtGestureStart: CGFloat?


    // Callbacks to MonitorViewController for Actor integration
    let onTakePicture: () -> Void
    let onToggleCamera: () -> Void
    let onSelectCameraDevice: (String) -> Void
    let onSelectAudioDevice: (String) -> Void
    let onToggleFlash: () -> Void
    let onToggleTorch: () -> Void
    let onTimerChange: (Int) -> Void
    let onModeChange: (RecordingMode) -> Void
    let onGalleryTapped: () -> Void
    let onSettingsTapped: () -> Void
    let onZoomChange: (CGFloat) -> Void
    let onLensChange: (CameraLensType) -> Void
    let onVideoQualityChange: (VideoResolution, VideoFrameRate) -> Void
    let onPhotoQualityChange: (PhotoFormat, HDRMode) -> Void
    let onAspectRatioChange: (AspectRatio) -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // MARK: - Camera Preview
                    cameraPreviewSection
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // MARK: - Controls Section
                    controlsSection
                        .background(Color.black.opacity(0.8))
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .statusBarHidden()
    }
    
    // MARK: - Camera Preview Section
    private var cameraPreviewSection: some View {
        ZStack {
            // Camera preview background
            Color.black
            
            // Camera image with aspect ratio crop overlay. Its own view so
            // the ~20fps frame stream re-renders ONLY this subtree — not the
            // menu and the rest of the chrome.
            LiveFrameView(frames: viewModel.frames,
                          aspectRatio: viewModel.currentAspectRatio)
            
            // Which camera is driving the preview — iOS and Mac peers both
            // advertise their device list, so the name is always real.
            if let active = viewModel.remoteCameraDevices.first(where: { $0.isActive }) {
                VStack {
                    HStack {
                        Text(active.localizedName)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.45))
                            .cornerRadius(6)
                            .padding(.top, 20)
                            .padding(.leading, 12)
                        Spacer()
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            // Recording indicator with duration timer
            if viewModel.isShowingRecordingDuration {
                VStack {
                    HStack {
                        Spacer()
                        RecordingTimer(
                            startTime: viewModel.recordingStartTime,
                            isRecording: viewModel.isRecording
                        )
                        .padding(.top, 20)
                        .padding(.trailing, 20)
                    }
                    Spacer()
                }
            }
            
            // Zoom controls overlay - positioned at top for right-handed accessibility
            if viewModel.showZoomControls {
                VStack {
                    zoomControlsOverlay
                        .padding(.top, 50) // Below status bar
                    Spacer()
                }
            }
            
            // Video transfer progress overlay - positioned at center
            if viewModel.isVideoTransferring {
                VideoTransferProgressView(
                    progress: viewModel.videoTransferProgress,
                    transferSizeText: viewModel.videoTransferSizeText,
                    transferSpeedText: viewModel.videoTransferSpeedText,
                    isVisible: viewModel.isVideoTransferring
                )
            }
            
            // Flash status overlay
            if !viewModel.flashStatus.isEmpty && viewModel.uiState == .photoMode {
                VStack {
                    HStack {
                        Text(viewModel.flashStatus)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(8)
                            .padding(.leading, 20)
                            .padding(.top, 20)
                        Spacer()
                    }
                    Spacer()
                }
            }

        }
        .onTapGesture(count: 2) {
            // Double tap to toggle camera
            onToggleCamera()
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    // Capture zoom at gesture start (first onChanged)
                    if zoomAtGestureStart == nil {
                        zoomAtGestureStart = viewModel.currentZoomFactor
                    }
                    let start = zoomAtGestureStart!

                    // Logarithmic zoom: newZoom = start * value^sensitivity
                    // Operates in log2 space for uniform perceptual sensitivity
                    let minZoom = viewModel.zoomStops.first ?? 1.0
                    let maxZoom = viewModel.maxZoomFactor
                    let sensitivity: CGFloat = 0.6

                    let logStart = log2(start)
                    let logDelta = log2(value) * sensitivity
                    let logNew = logStart + logDelta
                    let clamped = max(log2(minZoom), min(log2(maxZoom), logNew))
                    let newZoom = pow(2, clamped)

                    onZoomChange(newZoom)
                    viewModel.showZoomControlsTemporarily()
                }
                .onEnded { _ in
                    zoomAtGestureStart = nil
                }
        )
    }
    
    // MARK: - Recording Indicator
    // Note: Replaced with RecordingTimer component that includes duration
    
    // MARK: - Zoom Controls Overlay
    private var zoomControlsOverlay: some View {
        VStack(spacing: 10) {
            // Current zoom level - display relative to wide-angle
            Text("\(String(format: "%.1f", viewModel.currentZoomFactor / viewModel.wideAngleZoomFactor))×")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .tracking(0.5)
            
            // Progress bar with refined styling
            HStack(spacing: 8) {
                // Start label
                Text(formatZoomStop(viewModel.zoomStops.first ?? 1.0))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))

                // Enhanced progress bar
                ZStack(alignment: .leading) {
                    let minZoom = viewModel.zoomStops.first ?? 1.0
                    let range = viewModel.maxZoomFactor - minZoom
                    let progress = range > 0 ? (viewModel.currentZoomFactor - minZoom) / range : 0

                    // Background track with subtle gradient
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.25)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 140, height: 8)

                    // Progress fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.accent, AppTheme.accentLight],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: CGFloat(140 * max(0, min(1, Double(progress)))),
                            height: 8
                        )
                        .shadow(color: AppTheme.accent.opacity(0.3), radius: 2, x: 0, y: 1)
                }

                // End label
                Text("\(String(format: "%.0f", viewModel.maxZoomFactor))×")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            // Premium glassmorphism card background
            ZStack {
                // Backdrop blur effect with proper clipping
                Color.black.opacity(0.3)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                
                // Subtle border highlight
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.4),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
        )
        .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 4)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Quality Controls
    private var qualityControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if viewModel.uiState == .videoMode {
                    videoQualityButtons
                } else if viewModel.uiState == .photoMode {
                    photoQualityButtons
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var videoQualityButtons: some View {
        // Resolution picker
        if viewModel.supportedResolutions.count > 1 {
            ForEach(viewModel.supportedResolutions, id: \.self) { resolution in
                Button(action: {
                    onVideoQualityChange(resolution, viewModel.currentVideoFrameRate)
                }) {
                    Text(resolution.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(viewModel.currentVideoResolution == resolution ? .black : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            viewModel.currentVideoResolution == resolution ?
                            AppTheme.accent : Color.gray.opacity(0.3)
                        )
                        .cornerRadius(6)
                }
                .disabled(!viewModel.isQualityControlEnabled)
            }

            Divider()
                .frame(height: 20)
                .background(Color.gray.opacity(0.5))
        }

        // FPS picker
        ForEach(availableFrameRates, id: \.self) { rate in
            Button(action: {
                onVideoQualityChange(viewModel.currentVideoResolution, rate)
            }) {
                Text("\(rate.displayName) fps")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(viewModel.currentVideoFrameRate == rate ? .black : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        viewModel.currentVideoFrameRate == rate ?
                        AppTheme.accent : Color.gray.opacity(0.3)
                    )
                    .cornerRadius(6)
            }
            .disabled(!viewModel.isQualityControlEnabled)
        }
    }

    private var availableFrameRates: [VideoFrameRate] {
        let rates = viewModel.resolutionFrameRates[viewModel.currentVideoResolution]
        return (rates?.isEmpty == false) ? rates! : viewModel.supportedFrameRates
    }

    @ViewBuilder
    private var photoQualityButtons: some View {
        // Format picker
        if viewModel.supportsHEIF {
            ForEach(PhotoFormat.selectableCases, id: \.self) { format in
                Button(action: {
                    onPhotoQualityChange(format, viewModel.currentHDRMode)
                }) {
                    Text(format.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(viewModel.currentPhotoFormat == format ? .black : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            viewModel.currentPhotoFormat == format ?
                            AppTheme.accent : Color.gray.opacity(0.3)
                        )
                        .cornerRadius(6)
                }
                .disabled(!viewModel.isQualityControlEnabled)
            }

            Divider()
                .frame(height: 20)
                .background(Color.gray.opacity(0.5))
        }

        // HDR toggle
        if viewModel.supportsHDR {
            Button(action: {
                let newHDR: HDRMode = viewModel.currentHDRMode == .on ? .off : .on
                onPhotoQualityChange(viewModel.currentPhotoFormat, newHDR)
            }) {
                Text("HDR")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(viewModel.currentHDRMode == .on ? .black : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        viewModel.currentHDRMode == .on ?
                        AppTheme.accent : Color.gray.opacity(0.3)
                    )
                    .cornerRadius(6)
            }
            .disabled(!viewModel.isQualityControlEnabled)
        }
    }

    // MARK: - Controls Section
    private var controlsSection: some View {
        VStack(spacing: viewModel.areControlsExpanded ? 20 : 12) {
            // Mode Selector + expand/collapse toggle
            HStack {
                modeSelector

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.areControlsExpanded.toggle()
                    }
                }) {
                    Image(systemName: viewModel.areControlsExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 24, height: 24)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                }
            }

            if viewModel.areControlsExpanded {
                // Quality Controls (video: resolution + fps, photo: format + HDR)
                if FeatureFlags.ENABLE_QUALITY_CONTROLS
                    && (viewModel.uiState == .videoMode || viewModel.uiState == .photoMode) {
                    qualityControls
                }

                // Timer Controls (only for Photo/Video modes)
                if viewModel.uiState != .shortsMode {
                    timerControls
                }

                // Lens Controls
                if viewModel.availableLensTypes.count > 1 {
                    lensControls
                }

                // Aspect Ratio Controls
                aspectRatioControls
            }

            // Main Action Buttons (always visible)
            mainActionButtons

            // Bottom Navigation (always visible)
            bottomNavigation
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    // MARK: - Mode Selector
    private var modeSelector: some View {
        HStack(spacing: 0) {
            modeButton(title: "Photo", mode: .Photo)
            modeButton(title: "Video", mode: .Video)
            
            // Shorts mode - feature flagged
            if FeatureFlags.ENABLE_SHORTS_MODE {
                modeButton(title: "Shorts", mode: .Shorts)
            }
        }
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
        .disabled(!viewModel.isSegmentedControlEnabled)
    }
    
    private func modeButton(title: String, mode: RecordingMode) -> some View {
        Button(action: {
            onModeChange(mode)
        }) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(viewModel.currentMode == mode ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    viewModel.currentMode == mode ?
                    AppTheme.accent : Color.clear
                )
                .cornerRadius(6)
        }
    }
    
    // MARK: - Timer Controls
    private var timerControls: some View {
        HStack(spacing: 16) {
            Text("Timer:")
                .font(.system(size: 16))
                .foregroundColor(.white)
            
            Slider(
                value: Binding(
                    get: { viewModel.timerSliderValue },
                    set: { newValue in
                        viewModel.timerSliderValue = newValue
                        onTimerChange(Int(newValue))
                    }
                ),
                in: 0...viewModel.maxTimerValue,
                step: 1
            )
            .accentColor(AppTheme.accent)
            .disabled(!viewModel.isTimerSliderEnabled)
            
            Text("\(Int(viewModel.timerSliderValue))s")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 30)
        }
    }
    
    /// Formats a hardware zoom factor as a user-facing label relative to the wide-angle camera.
    /// e.g., hardware 1.0 with wideAngleFactor 2.0 → "0.5x", hardware 2.0 → "1x", hardware 6.0 → "3x"
    private func formatZoomStop(_ hardwareZoom: CGFloat) -> String {
        let displayZoom = hardwareZoom / viewModel.wideAngleZoomFactor
        let rounded = round(displayZoom * 10) / 10
        if rounded == CGFloat(Int(rounded)) {
            return "\(Int(rounded))x"
        }
        return String(format: "%.1fx", rounded)
    }

    // MARK: - Lens Controls
    private var lensControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.availableLensTypes, id: \.self) { lensType in
                    Button(action: {
                        onLensChange(lensType)
                    }) {
                        Text(lensType.displayName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(viewModel.currentLensType == lensType ? .black : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                viewModel.currentLensType == lensType ?
                                AppTheme.accent : Color.gray.opacity(0.3)
                            )
                            .cornerRadius(6)
                    }
                    .disabled(!viewModel.isLensControlEnabled)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Aspect Ratio Controls
    private var aspectRatioControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(AspectRatio.selectableCases, id: \.self) { ratio in
                    Button(action: {
                        onAspectRatioChange(ratio)
                    }) {
                        Text(ratio.displayName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(viewModel.currentAspectRatio == ratio ? .black : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                viewModel.currentAspectRatio == ratio ?
                                AppTheme.accent : Color.gray.opacity(0.3)
                            )
                            .cornerRadius(6)
                    }
                    .disabled(!viewModel.isQualityControlEnabled)
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Main Action Buttons
    private var mainActionButtons: some View {
        HStack(spacing: 40) {
            // Gallery Button
            actionButton(
                systemImage: "photo.on.rectangle",
                action: onGalleryTapped,
                isEnabled: viewModel.isGalleryEnabled
            )
            
            // Main Action Button (Take Photo/Record Video)
            mainActionButton
            
            // Camera switch control, isolated behind Equatable: it must not
            // re-render (an open menu dismisses if rebuilt) unless the
            // devices, active ID, or enabled state actually changed.
            CameraSwitchControlView(
                control: viewModel.cameraSwitchControl,
                devices: viewModel.remoteCameraDevices,
                activeDeviceID: viewModel.activeRemoteDeviceID,
                isEnabled: viewModel.isToggleCameraEnabled,
                onToggleCamera: onToggleCamera,
                onSelectCameraDevice: onSelectCameraDevice
            )
            .equatable()
        }
    }
    
    private var mainActionButton: some View {
        Button(action: onTakePicture) {
            ZStack {
                // Outer border (always white)
                Circle()
                    .fill(Color.white)
                    .frame(width: 80, height: 80)
                
                // Main button styling based on mode and recording state
                if viewModel.isRecording {
                    // Recording: Red background with white stop square
                    Circle()
                        .fill(Color.red)
                        .frame(width: 70, height: 70)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white)
                        .frame(width: 22, height: 22)
                } else if viewModel.uiState == .videoMode || viewModel.uiState == .shortsMode {
                    // Video mode (not recording): Red circle ready to record
                    Circle()
                        .fill(Color.red)
                        .frame(width: 70, height: 70)
                } else {
                    // Photo mode: White with black inner border
                    Circle()
                        .stroke(Color.black, lineWidth: 3)
                        .frame(width: 65, height: 65)
                }
                
                // Show countdown number if timer is active
                if viewModel.timerValue > 0 {
                    Text("\(viewModel.timerValue)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(viewModel.uiState == .photoMode ? .black : .white)
                }
            }
        }
        .disabled(!viewModel.isSegmentedControlEnabled && !viewModel.isRecording)
    }
    
    private func actionButton(systemImage: String, action: @escaping () -> Void, isEnabled: Bool) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 24))
                .foregroundColor(isEnabled ? .white : .gray)
                .frame(width: 44, height: 44)
        }
        .disabled(!isEnabled)
    }
    
    // MARK: - Bottom Navigation
    private var bottomNavigation: some View {
        HStack {
            Spacer()

            // Flash/Torch Controls (context-dependent)
            if viewModel.uiState == .photoMode {
                // Show both flash and torch for photo mode
                HStack(spacing: 20) {
                    flashButton
                    torchButton
                }
            } else if viewModel.uiState == .videoMode || viewModel.uiState == .shortsMode {
                HStack(spacing: 20) {
                    torchButton
                    // Mic picker: video modes only (a mic is meaningless for
                    // photos) and only when the peer offers a real choice.
                    // Hidden while recording (uiState .videoRecording) — the
                    // camera peer rejects mid-recording selection anyway.
                    if viewModel.showsAudioDeviceMenu {
                        AudioDeviceMenuView(
                            devices: viewModel.remoteAudioDevices,
                            activeDeviceID: viewModel.activeRemoteAudioDeviceID,
                            isEnabled: viewModel.isToggleCameraEnabled,
                            onSelectAudioDevice: onSelectAudioDevice
                        )
                        .equatable()
                    }
                }
            }

            Spacer()

            // Settings Button
            Button(action: onSettingsTapped) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
            }
            .disabled(!viewModel.isSettingsEnabled)
        }
    }
    
    private var flashButton: some View {
        Button(action: onToggleFlash) {
            Image(systemName: viewModel.isFlashEnabled ? "bolt.fill" : "bolt.slash")
                .font(.system(size: 20))
                .foregroundColor(viewModel.isFlashEnabled ? .yellow : .white)
        }
        .disabled(!viewModel.isFlashButtonEnabled)
    }
    
    private var torchButton: some View {
        Button(action: onToggleTorch) {
            Image(systemName: viewModel.isTorchEnabled ? "flashlight.on.fill" : "flashlight.off.fill")
                .font(.system(size: 20))
                .foregroundColor(viewModel.isTorchEnabled ? .yellow : .white)
        }
        .disabled(!viewModel.isTorchButtonEnabled)
    }
}

// MARK: - Preview
struct MonitorView_Previews: PreviewProvider {
    static var previews: some View {
        MonitorView(
            viewModel: MonitorViewModel(),
            onTakePicture: {},
            onToggleCamera: {},
            onSelectCameraDevice: { _ in },
            onSelectAudioDevice: { _ in },
            onToggleFlash: {},
            onToggleTorch: {},
            onTimerChange: { _ in },
            onModeChange: { _ in },
            onGalleryTapped: {},
            onSettingsTapped: {},
            onZoomChange: { _ in },
            onLensChange: { _ in },
            onVideoQualityChange: { _, _ in },
            onPhotoQualityChange: { _, _ in },
            onAspectRatioChange: { _ in }
        )
        .preferredColorScheme(.dark)
    }
}

// MARK: - Live Frame View

/// Renders the streamed preview frames. Deliberately its own view observing
/// only `FrameDisplayModel`: frames publish ~20×/sec, and observing them
/// from `MonitorView` re-rendered every control on each frame.
struct LiveFrameView: View {
    @ObservedObject var frames: FrameDisplayModel
    let aspectRatio: AspectRatio

    var body: some View {
        if let image = frames.cameraImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipped()
                .overlay(
                    AspectRatioCropOverlay(
                        selectedRatio: aspectRatio,
                        imageSize: image.size
                    )
                )
        } else {
            // Placeholder until the first frame arrives.
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    Image(systemName: "camera")
                        .font(.system(size: 50))
                        .foregroundColor(.white.opacity(0.5))
                )
        }
    }
}

// MARK: - Camera Switch Control

/// The flip button / device menu, sized to the peer's cameras (one: hidden;
/// two usable: flip; more: menu). Equatable so SwiftUI provably skips it on
/// unrelated monitor updates — rebuilding a Menu dismisses it while open.
/// Callbacks are deliberately excluded from equality (they are stable
/// controller closures).
struct CameraSwitchControlView: View, Equatable {
    let control: MonitorViewModel.CameraSwitchControl
    let devices: [RemoteCmd.CameraDeviceEntry]
    let activeDeviceID: String?
    let isEnabled: Bool
    let onToggleCamera: () -> Void
    let onSelectCameraDevice: (String) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.control == rhs.control
            && lhs.devices == rhs.devices
            && lhs.activeDeviceID == rhs.activeDeviceID
            && lhs.isEnabled == rhs.isEnabled
    }

    var body: some View {
        switch control {
        case .hidden:
            Color.clear.frame(width: 44, height: 44)   // keep the shutter centered
        case .flipButton:
            Button(action: onToggleCamera) {
                switchIcon
            }
            .disabled(!isEnabled)
        case .deviceMenu:
            Menu {
                ForEach(devices, id: \.uniqueID) { device in
                    CameraDeviceMenuItem(
                        name: device.localizedName,
                        isActive: device.uniqueID == activeDeviceID,
                        isSuspended: device.isSuspended,
                        select: { onSelectCameraDevice(device.uniqueID) })
                }
            } label: {
                switchIcon
            }
            .disabled(!isEnabled)
        }
    }

    private var switchIcon: some View {
        Image(systemName: "arrow.triangle.2.circlepath.camera")
            .font(.system(size: 24))
            .foregroundColor(isEnabled ? .white : .gray)
            .frame(width: 44, height: 44)
    }
}

// MARK: - Audio Device Menu

/// The mic picker: a menu of the peer's audio inputs. Equatable for the same
/// reason as `CameraSwitchControlView` — rebuilding a Menu dismisses it while
/// open, and monitor updates are frequent. Callbacks are excluded from
/// equality (stable controller closures).
struct AudioDeviceMenuView: View, Equatable {
    let devices: [RemoteCmd.AudioDeviceEntry]
    let activeDeviceID: String?
    let isEnabled: Bool
    let onSelectAudioDevice: (String) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.devices == rhs.devices
            && lhs.activeDeviceID == rhs.activeDeviceID
            && lhs.isEnabled == rhs.isEnabled
    }

    var body: some View {
        Menu {
            ForEach(devices, id: \.uniqueID) { device in
                CameraDeviceMenuItem(
                    name: device.localizedName,
                    isActive: device.uniqueID == activeDeviceID,
                    isSuspended: false,
                    select: { onSelectAudioDevice(device.uniqueID) })
            }
        } label: {
            Image(systemName: "mic")
                .font(.system(size: 20))
                .foregroundColor(isEnabled ? .white : .gray)
                .frame(width: 44, height: 44)
        }
        .disabled(!isEnabled)
    }
}

// MARK: - Camera Device Menu Item

/// One camera in a device-picker menu: checkmark on the active device;
/// suspended devices (connected but delivering no frames — e.g. a clamshell
/// MacBook's built-in camera) are grayed out and not selectable.
/// Shared by the monitor's remote picker and the camera screen's local picker.
struct CameraDeviceMenuItem: View {
    let name: String
    let isActive: Bool
    let isSuspended: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            if isActive {
                Label(name, systemImage: "checkmark")
            } else if isSuspended {
                Label(String(format: NSLocalizedString("%@ (unavailable)", comment: "suspended camera"), name),
                      systemImage: "moon.zzz")
            } else {
                Text(name)
            }
        }
        .disabled(isSuspended)
    }
}

// MARK: - Aspect Ratio Crop Overlay

/// Draws semi-transparent black bars over areas that will be cropped for the selected aspect ratio.
struct AspectRatioCropOverlay: View {
    let selectedRatio: AspectRatio
    let imageSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            let viewSize = geometry.size
            let imageRatio = imageSize.width / imageSize.height
            let targetRatio: CGFloat = {
                // For portrait images, invert the ratio
                if imageSize.height > imageSize.width {
                    return 1.0 / selectedRatio.widthToHeight
                }
                return selectedRatio.widthToHeight
            }()

            // No overlay needed if the image already matches the target
            if abs(imageRatio - targetRatio) > 0.01 {
                let fittedSize = fittedImageSize(viewSize: viewSize, imageRatio: imageRatio)
                let cropSize = croppedSize(fittedSize: fittedSize, targetRatio: targetRatio)
                let xOffset = (viewSize.width - fittedSize.width) / 2
                let yOffset = (viewSize.height - fittedSize.height) / 2

                // Determine bar positions
                if fittedSize.width / fittedSize.height > targetRatio {
                    // Crop sides
                    let barWidth = (fittedSize.width - cropSize.width) / 2
                    HStack(spacing: 0) {
                        Color.black.opacity(0.5)
                            .frame(width: barWidth)
                        Color.clear
                            .frame(width: cropSize.width)
                        Color.black.opacity(0.5)
                            .frame(width: barWidth)
                    }
                    .frame(width: fittedSize.width, height: fittedSize.height)
                    .offset(x: xOffset, y: yOffset)
                } else {
                    // Crop top/bottom
                    let barHeight = (fittedSize.height - cropSize.height) / 2
                    VStack(spacing: 0) {
                        Color.black.opacity(0.5)
                            .frame(height: barHeight)
                        Color.clear
                            .frame(height: cropSize.height)
                        Color.black.opacity(0.5)
                            .frame(height: barHeight)
                    }
                    .frame(width: fittedSize.width, height: fittedSize.height)
                    .offset(x: xOffset, y: yOffset)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func fittedImageSize(viewSize: CGSize, imageRatio: CGFloat) -> CGSize {
        let viewRatio = viewSize.width / viewSize.height
        if imageRatio > viewRatio {
            let w = viewSize.width
            return CGSize(width: w, height: w / imageRatio)
        } else {
            let h = viewSize.height
            return CGSize(width: h * imageRatio, height: h)
        }
    }

    private func croppedSize(fittedSize: CGSize, targetRatio: CGFloat) -> CGSize {
        let currentRatio = fittedSize.width / fittedSize.height
        if currentRatio > targetRatio {
            return CGSize(width: fittedSize.height * targetRatio, height: fittedSize.height)
        } else {
            return CGSize(width: fittedSize.width, height: fittedSize.width / targetRatio)
        }
    }
}