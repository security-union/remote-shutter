import SwiftUI
import UIKit
import Combine

// MARK: - Monitor View

/// The remote control's viewfinder.
///
/// The preview is the screen: everything else floats over it on translucent
/// surfaces, and the set-once controls (timer, aspect, quality) live behind the
/// tray button rather than occupying permanent rows. The action cluster docks to
/// whichever edge the screen's *shape* makes cheap — see `MonitorChromeLayout`.
struct MonitorView: View {
    @ObservedObject var viewModel: MonitorViewModel
    @State private var zoomAtGestureStart: CGFloat?
    /// Peer-link state; the reconnect overlay is a function of it.
    @ObservedObject var peerLink: PeerLinkStatus = .shared

    // Callbacks to MonitorViewController for session integration
    let onTakePicture: () -> Void
    let onToggleCamera: () -> Void
    let onSelectCameraDevice: (String) -> Void
    let onToggleFlash: () -> Void
    let onToggleTorch: () -> Void
    let onTimerChange: (Int) -> Void
    let onModeChange: (RecordingMode) -> Void
    let onGalleryTapped: () -> Void
    let onSettingsTapped: () -> Void
    let onHelpTapped: () -> Void
    let onBackTapped: () -> Void
    let onZoomChange: (CGFloat) -> Void
    let onVideoQualityChange: (VideoResolution, VideoFrameRate) -> Void
    let onPhotoQualityChange: (PhotoFormat, HDRMode) -> Void
    let onAspectRatioChange: (AspectRatio) -> Void
    /// Tap-to-focus: the tap point normalized (0..1) in the displayed image,
    /// origin top-left. Not called for taps that land in the letterbox bars.
    let onFocusTap: (CGPoint) -> Void
    /// Toggles the connected camera's local-preview mode (on ⇄ standby).
    let onToggleCameraStandby: () -> Void

    /// The live focus reticle (view-space position + identity to re-trigger the
    /// animation on each tap). Local UI only — no round-trip to the camera.
    @State private var focusReticle: FocusReticle?
    /// The preview area's measured size, for tap → normalized-image mapping.
    @State private var previewSize: CGSize = .zero
    @State private var isTrayOpen = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                previewLayer

                chrome(dock: MonitorChromeLayout.dock(
                    viewSize: geometry.size,
                    interfaceOrientation: viewModel.interfaceOrientation,
                    input: Self.chromeInput))

                if isTrayOpen {
                    trayLayer
                }

                if viewModel.isVideoTransferring {
                    VideoTransferProgressView(
                        progress: viewModel.videoTransferProgress,
                        transferSizeText: viewModel.videoTransferSizeText,
                        transferSpeedText: viewModel.videoTransferSpeedText,
                        isVisible: viewModel.isVideoTransferring
                    )
                }

                PeerLinkOverlay(status: peerLink)
            }
        }
        // Every control here draws its own shape; Catalyst's default style
        // paints a bordered box behind them. .borderless removes that box.
        // NOT .plain -- that also drops the style's hit region, which left the
        // material-filled controls clickable only where their glyph draws.
        .buttonStyle(.borderless)
        .onPreferenceChange(PreviewSizePreferenceKey.self) { previewSize = $0 }
        .statusBarHidden()
    }

    /// iPhone/iPad draw the preview full-bleed under the notch and the home
    /// indicator. The Mac's toolbar (Back button, window title) is opaque
    /// chrome — the preview must never draw under it.
    private static var previewBleedEdges: Edge.Set {
        #if targetEnvironment(macCatalyst)
        []
        #else
        .all
        #endif
    }

    /// The viewfinder hides the nav bar on every platform, and the Mac window
    /// has no toolbar Back of its own, so the floating chevron is the only way
    /// out everywhere.
    private static let showsFloatingBackButton = true

    /// A Mac window neither rotates nor is held, so the side rail buys nothing
    /// there and the bottom bar is the convention.
    private static var chromeInput: MonitorChromeInput {
        #if targetEnvironment(macCatalyst)
        .pointer
        #else
        .touch
        #endif
    }

    // MARK: - Preview layer

    /// The image and everything that shares its coordinate space. Measured as
    /// one unit so a tap maps to the same rect the frame is drawn in.
    private var previewLayer: some View {
        ZStack {
            Color.black

            // Its own view so the ~20fps frame stream re-renders ONLY this
            // subtree — not the chrome.
            LiveFrameView(frames: viewModel.frames,
                          aspectRatio: viewModel.currentAspectRatio)
                // A stalled stream is a stale picture. Desaturating it says so
                // continuously, where a badge alone can be missed.
                .saturation(viewModel.isPreviewStale ? 0.25 : 1)
                .opacity(viewModel.isPreviewStale ? 0.65 : 1)
                .animation(.easeInOut(duration: 0.25), value: viewModel.isPreviewStale)

            // Preview gestures sit BELOW the interactive chrome, so a tap on a
            // control is never stolen as a focus tap. Double tap toggles the
            // camera; a single tap focuses (simultaneous so the reticle is
            // instant — an exclusive gesture would stall it for the double-tap
            // window); pinch zooms. The translation guard keeps drags and
            // pinches from focusing.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    onToggleCamera()
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            if abs(value.translation.width) < 10, abs(value.translation.height) < 10 {
                                handleFocusTap(at: value.location)
                            }
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            if zoomAtGestureStart == nil {
                                zoomAtGestureStart = viewModel.currentZoomFactor
                            }
                            let start = zoomAtGestureStart!
                            onZoomChange(viewModel.zoomScale.pinched(from: start, magnification: value))
                        }
                        .onEnded { _ in
                            zoomAtGestureStart = nil
                        }
                )

            focusReticleOverlay

            countdownOverlay
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: PreviewSizePreferenceKey.self, value: geo.size)
            }
        )
        .ignoresSafeArea(edges: Self.previewBleedEdges)
    }

    /// The focus reticle, drawn in the preview's coordinate space. Non-interactive
    /// so it never eats a subsequent tap.
    @ViewBuilder
    private var focusReticleOverlay: some View {
        if let reticle = focusReticle {
            FocusReticleView()
                .id(reticle.id)
                .position(reticle.point)
                .allowsHitTesting(false)
        }
    }

    /// The self-timer, centered and large. The capture happens across the room:
    /// a subject walking into frame has to read this at a glance, which a digit
    /// tucked inside the shutter never allowed.
    @ViewBuilder
    private var countdownOverlay: some View {
        if viewModel.timerValue > 0 {
            Text("\(viewModel.timerValue)")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.accent)
                // The number must read against whatever the camera is pointed
                // at, including a bright wall. Two shadows — one tight for edge
                // definition, one wide for separation — keep it legible without
                // a backing plate smudging the frame the user is composing.
                .shadow(color: .black.opacity(0.85), radius: 3)
                .shadow(color: .black.opacity(0.55), radius: 16)
                .id(viewModel.timerValue)
                .transition(.scale(scale: 1.15).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    /// Maps a preview tap into a normalized image point and, if it landed on the
    /// image (not the letterbox), shows the reticle and forwards it to the camera.
    private func handleFocusTap(at location: CGPoint) {
        guard let image = viewModel.frames.cameraImage,
              let normalized = FocusPointMapping.normalizedImagePoint(
                tap: location, viewSize: previewSize, imageSize: image.size)
        else { return }
        showFocusReticle(at: location)
        onFocusTap(normalized)
    }

    private func showFocusReticle(at point: CGPoint) {
        let reticle = FocusReticle(point: point)
        focusReticle = reticle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if focusReticle?.id == reticle.id { focusReticle = nil }
        }
    }

    // MARK: - Chrome

    /// Everything that floats over the preview, arranged for the docked edge.
    private func chrome(dock: MonitorChromeDock) -> some View {
        VStack(spacing: 0) {
            topBar

            Spacer(minLength: 0)

            switch dock {
            case .bottom:
                bottomCluster
            case .leading:
                sideCluster(onLeading: true)
            case .trailing:
                sideCluster(onLeading: false)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    /// Back (leading) · recording timecode (centered) · state capsule (trailing).
    private var topBar: some View {
        ZStack {
            if viewModel.isShowingRecordingDuration {
                RecordingTimer(
                    startTime: viewModel.recordingStartTime,
                    isRecording: viewModel.isRecording
                )
            }

            HStack(spacing: 0) {
                if Self.showsFloatingBackButton {
                    GlassCircleButton(systemImage: "chevron.backward",
                                      size: 36,
                                      glyphSize: 16,
                                      isEnabled: viewModel.isBackEnabled,
                                      action: onBackTapped)
                }
                LinkChip(state: MonitorLinkState.resolve(link: peerLink.link,
                                                         isPreviewStale: viewModel.isPreviewStale))
                    .equatable()
                    .padding(.leading, 8)
                // Belongs with the other status, not floating over the middle
                // of the picture the user is framing.
                activeCameraCaption
                    .padding(.leading, 8)
                Spacer(minLength: 0)
                ControlCapsule(showsFlash: viewModel.uiState == .photoMode,
                               isFlashEnabled: viewModel.isFlashEnabled,
                               isFlashButtonEnabled: viewModel.isFlashButtonEnabled,
                               isTorchEnabled: viewModel.isTorchEnabled,
                               isTorchButtonEnabled: viewModel.isTorchButtonEnabled,
                               isTrayOpen: isTrayOpen,
                               onToggleFlash: onToggleFlash,
                               onToggleTorch: onToggleTorch,
                               onToggleTray: toggleTray)
                    .equatable()
            }
        }
    }

    /// Portrait and other tall shapes: everything stacks across the bottom.
    ///
    /// Full width on purpose. A stack sizes to its widest child, and children
    /// wider than that draw outside its bounds but stop receiving clicks there
    /// — which left a centred live band and killed the outer buttons.
    private var bottomCluster: some View {
        VStack(spacing: 14) {
            ZoomPill(scale: viewModel.zoomScale,
                     currentZoomFactor: viewModel.currentZoomFactor,
                     onZoomChange: onZoomChange)
            actionCluster(axis: .horizontal)
            modeSelector
        }
        .frame(maxWidth: .infinity)
    }

    /// Wide shapes: the action cluster rides the rail on the home-indicator side
    /// so it doesn't move when the device turns; zoom and mode stay low.
    private func sideCluster(onLeading: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 16) {
            if !onLeading { Spacer(minLength: 0) }
            if onLeading { actionCluster(axis: .vertical) }

            // Sits inboard of the rail, not adrift in the middle: one control
            // zone on the docked edge instead of three scattered groups.
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                ZoomPill(scale: viewModel.zoomScale,
                         currentZoomFactor: viewModel.currentZoomFactor,
                         onZoomChange: onZoomChange)
                modeSelector
            }

            if !onLeading { actionCluster(axis: .vertical) }
            if onLeading { Spacer(minLength: 0) }
        }
    }

    /// Gallery · shutter · camera switch, laid out along `axis`.
    private func actionCluster(axis: Axis) -> some View {
        let gallery = GlassCircleButton(systemImage: "photo.on.rectangle.angled",
                                        size: 44,
                                        glyphSize: 20,
                                        isEnabled: viewModel.isGalleryEnabled,
                                        action: onGalleryTapped)
        let shutter = ShutterButton(uiState: viewModel.uiState,
                                    isRecording: viewModel.isRecording,
                                    activity: viewModel.activity,
                                    isEnabled: viewModel.isSegmentedControlEnabled || viewModel.isRecording,
                                    action: onTakePicture)
            .equatable()
        let switcher = CameraSwitchControlView(
            control: viewModel.cameraSwitchControl,
            devices: viewModel.remoteCameraDevices,
            activeDeviceID: viewModel.activeRemoteDeviceID,
            isEnabled: viewModel.isToggleCameraEnabled,
            isSwitching: viewModel.activity == .switchingCamera,
            onToggleCamera: onToggleCamera,
            onSelectCameraDevice: onSelectCameraDevice)
            .equatable()

        return Group {
            if axis == .horizontal {
                HStack(spacing: 40) {
                    gallery
                    shutter
                    switcher
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 24) {
                    gallery
                    shutter
                    switcher
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    /// Which camera is driving the preview. Only meaningful when the peer has
    /// more than one — a single-camera peer has nothing to disambiguate.
    @ViewBuilder
    private var activeCameraCaption: some View {
        if viewModel.remoteCameraDevices.count > 1,
           let active = viewModel.remoteCameraDevices.first(where: { $0.uniqueID == viewModel.activeRemoteDeviceID }) {
            Text(active.localizedName)
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(.ultraThinMaterial))
                .allowsHitTesting(false)
        }
    }

    // MARK: - Mode selector

    private var modeSelector: some View {
        HStack(spacing: 4) {
            modeButton(title: NSLocalizedString("PHOTO", comment: "capture mode"), mode: .Photo)
            modeButton(title: NSLocalizedString("VIDEO", comment: "capture mode"), mode: .Video)

            if FeatureFlags.ENABLE_SHORTS_MODE {
                modeButton(title: NSLocalizedString("SHORTS", comment: "capture mode"), mode: .Shorts)
            }
        }
        .padding(4)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08)))
        .disabled(!viewModel.isSegmentedControlEnabled)
    }

    private func modeButton(title: String, mode: RecordingMode) -> some View {
        let isActive = viewModel.currentMode == mode
        return Button(action: { onModeChange(mode) }) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(isActive ? AppTheme.accent : .white.opacity(0.75))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isActive ? Color.white.opacity(0.16) : Color.clear)
                )
                .contentShape(Capsule())
        }
    }

    // MARK: - Tray

    private func toggleTray() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            isTrayOpen.toggle()
        }
    }

    private var trayLayer: some View {
        ZStack(alignment: .bottom) {
            // Near-invisible full-screen scrim: dismisses on tap without
            // dimming the preview the user is still framing with. Must stay
            // above 0.01 — UIKit does not hit-test at or below that.
            Color.black.opacity(0.02)
                .ignoresSafeArea()
                .onTapGesture { toggleTray() }

            MonitorTrayPanel(
                items: MonitorTray.items(for: viewModel.uiState,
                                         supportsHEIF: viewModel.supportsHEIF,
                                         supportsHDR: viewModel.supportsHDR,
                                         supportsCameraStandby: viewModel.supportsCameraStandby,
                                         resolutionCount: viewModel.supportedResolutions.count,
                                         frameRateCount: availableFrameRates.count),
                timerValue: Int(viewModel.timerSliderValue),
                aspectRatio: viewModel.currentAspectRatio,
                resolution: viewModel.currentVideoResolution,
                frameRate: viewModel.currentVideoFrameRate,
                photoFormat: viewModel.currentPhotoFormat,
                hdrMode: viewModel.currentHDRMode,
                cameraPreviewMode: viewModel.cameraPreviewMode,
                isQualityEnabled: viewModel.isQualityControlEnabled,
                isTimerEnabled: viewModel.isTimerSliderEnabled,
                isSettingsEnabled: viewModel.isSettingsEnabled,
                onTap: handleTrayTap)
                .transition(.move(edge: .bottom))
        }
    }

    private var availableFrameRates: [VideoFrameRate] {
        let rates = viewModel.resolutionFrameRates[viewModel.currentVideoResolution]
        return (rates?.isEmpty == false) ? rates! : viewModel.supportedFrameRates
    }

    /// Value tiles cycle in place and leave the tray open — you watch the glyph
    /// change. Tiles that push a screen close it first.
    private func handleTrayTap(_ item: MonitorTrayItem) {
        switch item {
        case .timer:
            let next = MonitorTimer.next(after: Int(viewModel.timerSliderValue))
            viewModel.timerSliderValue = Double(next)
            onTimerChange(next)

        case .aspect:
            onAspectRatioChange(Self.cycled(viewModel.currentAspectRatio, in: AspectRatio.selectableCases))

        case .resolution:
            onVideoQualityChange(Self.cycled(viewModel.currentVideoResolution, in: viewModel.supportedResolutions),
                                 viewModel.currentVideoFrameRate)

        case .frameRate:
            onVideoQualityChange(viewModel.currentVideoResolution,
                                 Self.cycled(viewModel.currentVideoFrameRate, in: availableFrameRates))

        case .format:
            onPhotoQualityChange(Self.cycled(viewModel.currentPhotoFormat, in: PhotoFormat.selectableCases),
                                 viewModel.currentHDRMode)

        case .hdr:
            onPhotoQualityChange(viewModel.currentPhotoFormat,
                                 viewModel.currentHDRMode == .on ? .off : .on)

        case .cameraStandby:
            // Stays open: the tile's glyph is the reflection of what the camera
            // is doing, so you want to watch it settle rather than lose it.
            onToggleCameraStandby()

        case .settings:
            toggleTray()
            onSettingsTapped()

        case .help:
            toggleTray()
            onHelpTapped()
        }
    }

    /// The next option after `current`, wrapping. Falls back to the first
    /// option when the current value isn't among them (a capability list can
    /// change under us when the peer swaps cameras).
    static func cycled<T: Equatable>(_ current: T, in options: [T]) -> T {
        guard let index = options.firstIndex(of: current) else { return options.first ?? current }
        return options[(index + 1) % options.count]
    }
}

// MARK: - Link chip

/// The state of the picture, top-leading.
///
/// Quiet by design: a healthy link is one small dot, because a remote that
/// shouts about being connected is noise. It earns words only when the picture
/// on screen has stopped being trustworthy.
struct LinkChip: View, Equatable {
    let state: MonitorLinkState

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.state == rhs.state }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)

            if let label {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, label == nil ? 7 : 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(.ultraThinMaterial))
        .allowsHitTesting(false)
    }

    private var dotColor: Color {
        switch state {
        case .live: return AppTheme.success
        case .stalled, .reconnecting: return AppTheme.accent
        }
    }

    private var label: String? {
        switch state {
        case .live: return nil
        case .stalled: return NSLocalizedString("NO SIGNAL", comment: "preview stream stalled")
        case .reconnecting: return NSLocalizedString("RECONNECTING", comment: "peer link dropped")
        }
    }
}

// MARK: - Glass circle button

/// A translucent round button — the monitor's standard auxiliary control.
struct GlassCircleButton: View {
    let systemImage: String
    let size: CGFloat
    let glyphSize: CGFloat
    var isActive: Bool = false
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(.ultraThinMaterial))
        }
        .disabled(!isEnabled)
    }

    private var tint: Color {
        if !isEnabled { return .white.opacity(0.35) }
        return isActive ? AppTheme.accent : .white
    }
}

// MARK: - Control capsule

/// The state-carrying toggles, top-trailing: flash (photo only), torch, and the
/// tray button. `Equatable` over value inputs so the ~20fps frame stream — and
/// any unrelated view-model change — cannot rebuild it.
struct ControlCapsule: View, Equatable {
    let showsFlash: Bool
    let isFlashEnabled: Bool
    let isFlashButtonEnabled: Bool
    let isTorchEnabled: Bool
    let isTorchButtonEnabled: Bool
    let isTrayOpen: Bool
    let onToggleFlash: () -> Void
    let onToggleTorch: () -> Void
    let onToggleTray: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.showsFlash == rhs.showsFlash
            && lhs.isFlashEnabled == rhs.isFlashEnabled
            && lhs.isFlashButtonEnabled == rhs.isFlashButtonEnabled
            && lhs.isTorchEnabled == rhs.isTorchEnabled
            && lhs.isTorchButtonEnabled == rhs.isTorchButtonEnabled
            && lhs.isTrayOpen == rhs.isTrayOpen
    }

    var body: some View {
        HStack(spacing: 6) {
            if showsFlash {
                glyph(isFlashEnabled ? "bolt.fill" : "bolt.slash.fill",
                      isActive: isFlashEnabled,
                      isEnabled: isFlashButtonEnabled,
                      action: onToggleFlash)
            }
            glyph(isTorchEnabled ? "flashlight.on.fill" : "flashlight.off.fill",
                  isActive: isTorchEnabled,
                  isEnabled: isTorchButtonEnabled,
                  action: onToggleTorch)
            glyph("circle.grid.3x3.fill",
                  isActive: isTrayOpen,
                  isEnabled: true,
                  action: onToggleTray)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Capsule().fill(.ultraThinMaterial))
    }

    private func glyph(_ name: String, isActive: Bool, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(isEnabled ? (isActive ? AppTheme.accent : .white) : .white.opacity(0.35))
                .frame(width: 38, height: 34)
                .contentShape(Rectangle())
        }
        .disabled(!isEnabled)
    }
}

// MARK: - Shutter

/// The capture button, including what the camera is currently doing about it.
///
/// The in-flight ring replaces the modal spinner that used to cover the preview
/// on every command: the feedback belongs on the control you pressed, not over
/// the picture you are framing.
struct ShutterButton: View, Equatable {
    let uiState: MonitorUIState
    let isRecording: Bool
    let activity: MonitorActivity?
    let isEnabled: Bool
    let action: () -> Void

    private static let diameter: CGFloat = 74

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.uiState == rhs.uiState
            && lhs.isRecording == rhs.isRecording
            && lhs.activity == rhs.activity
            && lhs.isEnabled == rhs.isEnabled
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: Self.diameter, height: Self.diameter)

                if isRecording {
                    Circle()
                        .fill(AppTheme.record)
                        .frame(width: 64, height: 64)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white)
                        .frame(width: 22, height: 22)
                } else if uiState == .videoMode || uiState == .shortsMode {
                    Circle()
                        .fill(AppTheme.record)
                        .frame(width: 64, height: 64)
                } else {
                    Circle()
                        .stroke(Color.black.opacity(0.85), lineWidth: 3)
                        .frame(width: 60, height: 60)
                }

                if isCaptureInFlight {
                    ShutterActivityRing()
                }
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .contentShape(Circle())
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
    }

    /// Only capture states dim the shutter — a flash or lens change in flight
    /// shows on its own control, not here.
    private var isCaptureInFlight: Bool {
        activity == .capturing || activity == .receivingCapture
    }
}

/// A rotating arc drawn around the shutter while a capture is in flight.
struct ShutterActivityRing: View {
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.28)
            .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .frame(width: 86, height: 86)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    spinning = true
                }
            }
    }
}

// MARK: - Tray panel

/// The capture tray: the controls that earn a tap rather than a permanent row.
struct MonitorTrayPanel: View {
    let items: [MonitorTrayItem]
    let timerValue: Int
    let aspectRatio: AspectRatio
    let resolution: VideoResolution
    let frameRate: VideoFrameRate
    let photoFormat: PhotoFormat
    let hdrMode: HDRMode
    /// The camera's reported local-preview mode. The standby tile is a
    /// reflection of the peer's actual state, not of a local intent, so it
    /// only lights up once the camera has confirmed.
    var cameraPreviewMode: CameraPreviewMode = .on
    let isQualityEnabled: Bool
    let isTimerEnabled: Bool
    let isSettingsEnabled: Bool
    let onTap: (MonitorTrayItem) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 5)

            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(items, id: \.self) { item in
                    MonitorTrayTile(item: item,
                                    value: value(for: item),
                                    isActive: isActive(item),
                                    isEnabled: isEnabled(item),
                                    action: { onTap(item) })
                }
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

    /// The glyph's payload — each tile shows its own current value, which is
    /// what lets it live behind a tap.
    private func value(for item: MonitorTrayItem) -> String? {
        switch item {
        case .timer: return timerValue > 0 ? "\(timerValue)" : nil
        case .aspect: return aspectRatio.displayName
        case .resolution: return resolution.displayName
        case .frameRate: return frameRate.displayName
        case .format: return photoFormat.displayName
        // Glyph-only tiles: their state is carried by the symbol, not a label.
        case .hdr, .cameraStandby, .settings, .help: return nil
        }
    }

    private func isActive(_ item: MonitorTrayItem) -> Bool {
        switch item {
        case .timer: return timerValue > 0
        case .hdr: return hdrMode == .on
        case .cameraStandby: return cameraPreviewMode == .standby
        default: return false
        }
    }

    private func isEnabled(_ item: MonitorTrayItem) -> Bool {
        switch item {
        case .timer: return isTimerEnabled
        case .aspect, .resolution, .frameRate, .format, .hdr: return isQualityEnabled
        // Not a capture setting — it stays usable mid-recording, when quality
        // controls are locked.
        case .cameraStandby: return true
        case .settings: return isSettingsEnabled
        case .help: return true
        }
    }
}

/// One tray tile: a circular glyph carrying its current value, over a caption.
struct MonitorTrayTile: View {
    let item: MonitorTrayItem
    let value: String?
    let isActive: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 56, height: 56)

                    if let value {
                        Text(value)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 22, weight: .semibold))
                    }
                }
                .foregroundColor(tint)

                Text(caption)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(isEnabled ? .white.opacity(0.6) : .white.opacity(0.3))
            }
            .contentShape(Rectangle())
        }
        .disabled(!isEnabled)
    }

    private var tint: Color {
        if !isEnabled { return .white.opacity(0.3) }
        return isActive ? AppTheme.accent : .white
    }

    private var symbol: String {
        switch item {
        case .timer: return "timer"
        case .aspect: return "aspectratio"
        case .resolution: return "rectangle.on.rectangle"
        case .frameRate: return "speedometer"
        case .format: return "doc"
        case .hdr: return "camera.filters"
        case .cameraStandby: return isActive ? "moon.zzz.fill" : "moon.zzz"
        case .settings: return "gearshape.fill"
        case .help: return "questionmark"
        }
    }

    private var caption: String {
        switch item {
        case .timer: return NSLocalizedString("TIMER", comment: "tray tile")
        case .aspect: return NSLocalizedString("ASPECT", comment: "tray tile")
        case .resolution: return NSLocalizedString("QUALITY", comment: "tray tile")
        case .frameRate: return NSLocalizedString("FPS", comment: "tray tile")
        case .format: return NSLocalizedString("FORMAT", comment: "tray tile")
        case .hdr: return NSLocalizedString("HDR", comment: "tray tile")
        case .cameraStandby: return NSLocalizedString("STANDBY", comment: "tray tile")
        case .settings: return NSLocalizedString("SETTINGS", comment: "tray tile")
        case .help: return NSLocalizedString("HELP", comment: "tray tile")
        }
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

// MARK: - Tap to Focus

/// One tap-to-focus reticle: its view-space position plus an identity so a new
/// tap re-instantiates `FocusReticleView` and replays its animation.
struct FocusReticle: Equatable {
    let id = UUID()
    let point: CGPoint
}

/// Measures the preview area's size so a tap can be mapped to a normalized image
/// point. A preference key avoids mutating `@State` during layout.
private struct PreviewSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// The animated focus square: a yellow reticle that pulses in and fades. Purely
/// local tap feedback — the focus command travels separately.
struct FocusReticleView: View {
    @State private var scale: CGFloat = 1.25
    @State private var opacity: Double = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(Color.yellow, lineWidth: 1.5)
            .frame(width: 78, height: 78)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.12)) {
                    scale = 1.0
                    opacity = 1
                }
                withAnimation(.easeIn(duration: 0.2).delay(0.35)) {
                    opacity = 0
                }
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
    /// A switch is in flight; the glyph says so instead of a modal.
    var isSwitching: Bool = false
    let onToggleCamera: () -> Void
    let onSelectCameraDevice: (String) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.control == rhs.control
            && lhs.devices == rhs.devices
            && lhs.activeDeviceID == rhs.activeDeviceID
            && lhs.isEnabled == rhs.isEnabled
            && lhs.isSwitching == rhs.isSwitching
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
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 44, height: 44)
            Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(isEnabled ? .white : .white.opacity(0.35))
                .rotationEffect(.degrees(isSwitching ? 180 : 0))
                .animation(.easeInOut(duration: 0.35), value: isSwitching)
        }
        .frame(width: 44, height: 44)
        .contentShape(Circle())
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

// MARK: - Preview

struct MonitorView_Previews: PreviewProvider {
    static var previews: some View {
        MonitorView(
            viewModel: MonitorViewModel(),
            onTakePicture: {},
            onToggleCamera: {},
            onSelectCameraDevice: { _ in },
            onToggleFlash: {},
            onToggleTorch: {},
            onTimerChange: { _ in },
            onModeChange: { _ in },
            onGalleryTapped: {},
            onSettingsTapped: {},
            onHelpTapped: {},
            onBackTapped: {},
            onZoomChange: { _ in },
            onVideoQualityChange: { _, _ in },
            onPhotoQualityChange: { _, _ in },
            onAspectRatioChange: { _ in },
            onFocusTap: { _ in },
            onToggleCameraStandby: {}
        )
        .preferredColorScheme(.dark)
    }
}
