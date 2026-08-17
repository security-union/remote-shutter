//
//  MulticamView.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import MPCCompat
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
    /// "Add camera" tapped — the host decides paywall vs. the sheet.
    let onAddCamera: () -> Void
    /// Invite a discovered camera into the rig.
    let onInviteCamera: (MCPeerID) -> Void
    /// Rig self-timer changed (seconds; 0 = off).
    let onSetTimer: (Int) -> Void
    /// Rig video quality picked (fans out to every lane).
    let onSelectVideoQuality: (VideoResolution, VideoFrameRate) -> Void
    /// "Automatic" — recompute best-in-intersection and apply.
    let onAutomaticVideoQuality: () -> Void
    /// Rig photo format / HDR picked.
    let onSetPhotoFormat: (PhotoFormat) -> Void
    let onSetHDR: (Bool) -> Void
    /// Retry a lane's failed footage collection.
    let onRetryCollection: (CameraLane) -> Void
    /// Flip the focused camera front/back (per-camera framing).
    let onToggleFocusedCamera: () -> Void
    /// Torch / flash on the focused camera (per-camera framing).
    let onToggleTorch: () -> Void
    let onToggleFlash: () -> Void
    /// Disconnect one camera from the rig (long-press → EndSession to it).
    let onDisconnectCamera: (CameraLane) -> Void
    /// Zoom the focused camera (per-camera framing; throttled by the host).
    let onZoomChange: (CGFloat) -> Void
    /// Tap-to-focus on the focused camera (normalized upright coords; the host
    /// gates on the IAP, the controller on the peer's advertised support).
    let onFocusTap: (CGPoint) -> Void
    /// Leave the director screen, back to the scanner (links stay up; the
    /// scanner re-arms and re-selects the still-connected cameras).
    let onBack: () -> Void

    var body: some View {
        GeometryReader { geo in
            let dock = MonitorChromeLayout.dock(
                viewSize: geo.size,
                interfaceOrientation: viewModel.interfaceOrientation,
                input: chromeInput)

            ZStack {
                Color.black.ignoresSafeArea()

                if viewModel.displayMode == .grid {
                    gridWall
                } else {
                    focusedViewfinder
                }

                // Same chrome skeleton as the 1:1 monitor: a top bar, then the
                // docked action cluster on the home-indicator edge. The camera
                // strip is multicam's one added element, tucked above the
                // action cluster in focus mode only.
                chrome(dock: dock)
                countdownOverlay
                if viewModel.showingRigTray { rigTrayLayer }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: viewModel.showingRigTray)
            .sheet(isPresented: $viewModel.showingAddCamera) {
                AddCameraSheet(peers: viewModel.availablePeers, onInvite: onInviteCamera)
            }
        }
    }

    /// The rig tray in the classic monitor's glass presentation: a near-invisible
    /// dismiss scrim (so the preview stays framed) under the floating panel.
    private var rigTrayLayer: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.02)
                .ignoresSafeArea()
                .onTapGesture { viewModel.showingRigTray = false }
            RigTrayPanel(settings: viewModel.rigSettings,
                         onSetTimer: onSetTimer,
                         onSelectVideoQuality: onSelectVideoQuality,
                         onAutomaticVideoQuality: onAutomaticVideoQuality,
                         onSetPhotoFormat: onSetPhotoFormat,
                         onSetHDR: onSetHDR)
                .transition(.move(edge: .bottom))
        }
    }

    // MARK: - Chrome (mirrors MonitorView's chrome, slot for slot)

    /// Everything floating over the preview, arranged for the docked edge —
    /// the same skeleton the 1:1 monitor uses (`topBar`, spacer, docked
    /// cluster) with the same padding, so the two screens read identically.
    private func chrome(dock: MonitorChromeDock) -> some View {
        VStack(spacing: 0) {
            topBar

            Spacer(minLength: 0)

            switch dock {
            case .bottom: bottomCluster
            case .leading: sideCluster(onLeading: true)
            case .trailing: sideCluster(onLeading: false)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    /// Back (leading) · focused link + camera chip · Spacer · flash/torch/tray,
    /// with the recording timecode centered over it all — the same slots as
    /// the monitor's `topBar`; the rig tray takes the settings glyph's place.
    private var topBar: some View {
        ZStack {
            if viewModel.isRecording {
                RecordingTimer(startTime: viewModel.recordingStartTime,
                               isRecording: viewModel.isRecording)
            }
            topBarControls
        }
    }

    private var topBarControls: some View {
        HStack(spacing: 0) {
            GlassCircleButton(systemImage: "chevron.backward",
                              size: 44, glyphSize: 22,
                              isEnabled: !viewModel.isRecording,
                              action: onBack)
            LinkChip(state: viewModel.focusedLinkState)
                .equatable()
                .padding(.leading, 8)
            focusedCameraChip
                .padding(.leading, 8)
            Spacer(minLength: 0)
            ControlCapsule(showsFlash: viewModel.mode == .photo,
                           isFlashEnabled: viewModel.focusedFlashOn,
                           isFlashButtonEnabled: viewModel.focusedFlashEnabled,
                           isTorchEnabled: viewModel.focusedTorchOn,
                           isTorchButtonEnabled: viewModel.focusedTorchEnabled,
                           isTrayOpen: viewModel.showingRigTray,
                           onToggleFlash: onToggleFlash,
                           onToggleTorch: onToggleTorch,
                           onToggleTray: { viewModel.showingRigTray = true })
                .equatable()
        }
    }

    /// The focused camera's name, and — via long-press — "Disconnect Camera",
    /// the same purposeful goodbye offered on each strip thumbnail.
    @ViewBuilder
    private var focusedCameraChip: some View {
        if let focused = viewModel.focusedLane {
            Text(focused.displayName)
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(.ultraThinMaterial))
                .contextMenu { disconnectButton(for: focused) }
        }
    }

    /// Portrait and other tall shapes: strip, then the action cluster and mode
    /// selector stack across the bottom — the monitor's `bottomCluster`, with
    /// the strip added above it.
    private var bottomCluster: some View {
        VStack(spacing: 14) {
            if viewModel.displayMode == .focus { cameraStrip(axis: .horizontal) }
            focusedZoomPill
            actionCluster(axis: .horizontal)
            modeSelector
        }
        .frame(maxWidth: .infinity)
    }

    /// Wide shapes: the action cluster rides the docked rail; the strip and
    /// mode selector sit inboard — the monitor's `sideCluster` shape.
    private func sideCluster(onLeading: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 16) {
            if !onLeading { Spacer(minLength: 0) }
            if onLeading { actionCluster(axis: .vertical) }

            VStack(spacing: 10) {
                Spacer(minLength: 0)
                if viewModel.displayMode == .focus { cameraStrip(axis: .vertical) }
                focusedZoomPill
                modeSelector
            }

            if !onLeading { actionCluster(axis: .vertical) }
            if onLeading { Spacer(minLength: 0) }
        }
    }

    /// Grid toggle · shutter · flip — the monitor's gallery · shutter · switch
    /// cluster, slot for slot. The gallery slot carries the grid toggle (the
    /// only added glyph); the switch slot carries the focused-camera flip.
    private func actionCluster(axis: Axis) -> some View {
        let leading = gridToggleButton
        let shutter = ShutterButton(
            uiState: viewModel.mode == .video ? .videoMode : .photoMode,
            isRecording: viewModel.isRecording,
            activity: viewModel.isCapturing ? .capturing : nil,
            isEnabled: !viewModel.isCapturing && viewModel.focusedLane != nil,
            action: onShutter)
            .equatable()
        let flip = CameraSwitchControlView(
            control: .flipButton,
            devices: [],
            activeDeviceID: nil,
            isEnabled: viewModel.focusedCameraCanFlip,
            isSwitching: false,
            onToggleCamera: onToggleFocusedCamera,
            onSelectCameraDevice: { _ in })
            .equatable()

        return Group {
            if axis == .horizontal {
                HStack(spacing: 40) { leading; shutter; flip }.frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 24) { leading; shutter; flip }.frame(maxHeight: .infinity)
            }
        }
    }

    /// The focused camera's zoom pill — the monitor's `ZoomPill`, same
    /// component and slot. Per-camera framing, so it shows in focus mode only,
    /// and hides when the focused camera has no usable zoom range (a
    /// fixed-focal-length camera, or before its first response), exactly as the
    /// 1:1 monitor does.
    @ViewBuilder
    private var focusedZoomPill: some View {
        if viewModel.displayMode == .focus && viewModel.showsFocusedZoomPill {
            ZoomPill(scale: viewModel.focusedZoomScale,
                     currentZoomFactor: viewModel.focusedZoomFactor,
                     onZoomChange: onZoomChange)
        }
    }

    /// The grid toggle occupies the monitor's gallery slot. Shown only with
    /// more than one camera; otherwise an empty 44pt frame keeps the shutter
    /// centered, exactly as the monitor's hidden-control spacer does.
    @ViewBuilder
    private var gridToggleButton: some View {
        if MultiCamChrome.showsGridToggle(cameraCount: viewModel.lanes.count) {
            GlassCircleButton(
                systemImage: viewModel.displayMode == .grid
                    ? "rectangle.inset.filled" : "square.grid.2x2.fill",
                size: 44, glyphSize: 20,
                isActive: viewModel.displayMode == .grid,
                isEnabled: true,
                action: { viewModel.displayMode = viewModel.displayMode == .grid ? .focus : .grid })
        } else {
            Color.clear.frame(width: 44, height: 44)
        }
    }

    /// PHOTO / VIDEO segmented capsule — the shared `CaptureModeSelector`.
    /// Tapping the inactive segment flips the rig mode; fades out while recording.
    private var modeSelector: some View {
        CaptureModeSelector(
            segments: [
                CaptureModeSelector.Segment(
                    id: 0, title: NSLocalizedString("PHOTO", comment: "capture mode"),
                    isActive: viewModel.mode != .video,
                    action: { if viewModel.mode == .video { onToggleMode() } }),
                CaptureModeSelector.Segment(
                    id: 1, title: NSLocalizedString("VIDEO", comment: "capture mode"),
                    isActive: viewModel.mode == .video,
                    action: { if viewModel.mode != .video { onToggleMode() } }),
            ],
            isEnabled: !viewModel.isRecording)
            .opacity(viewModel.isRecording ? 0 : 1)
    }

    /// "Disconnect Camera" — a purposeful goodbye to one camera. Long-press on
    /// the focused chip or any strip thumbnail.
    private func disconnectButton(for lane: CameraLane) -> some View {
        Button(role: .destructive, action: { onDisconnectCamera(lane) }) {
            Label(NSLocalizedString("Disconnect Camera", comment: "remove one camera from the rig"),
                  systemImage: "xmark.circle")
        }
    }

    /// The rig self-timer countdown, big and centered so subjects see it.
    @ViewBuilder
    private var countdownOverlay: some View {
        if let n = viewModel.rigSettings.countdown, n > 0 {
            Text("\(n)")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .shadow(radius: 8)
        }
    }

    /// An equal grid of every camera — the monitor wall. Tap a tile to focus it
    /// (and return to focus mode).
    private var gridWall: some View {
        let count = viewModel.lanes.count
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 4),
            count: MultiCamChrome.gridColumnCount(cameraCount: count))
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(viewModel.lanes) { lane in
                CameraTileView(lane: lane, isThumbnail: true, onRetry: { onRetryCollection(lane) })
                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
                    .onTapGesture {
                        onFocusLane(lane)
                        viewModel.displayMode = .focus
                    }
            }
        }
        .padding(8)
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
            // One ZStack, one `ignoresSafeArea`: the frame, the gestures, and
            // the reticle share a single coordinate space (the same contract as
            // the 1:1 monitor's preview layer). Gestures address the focused
            // camera; in grid mode a tile tap focuses the lane instead.
            ZStack {
                LiveFrameView(frames: focused.frames, aspectRatio: .sixteenNine)
                ViewfinderGestureLayer(
                    cameraImage: { focused.frames.cameraImage },
                    zoomScale: { focused.zoomScale },
                    currentZoomFactor: { focused.zoomFactor },
                    focusEnabled: focused.supportsFocusPoint,
                    onFocusTap: onFocusTap,
                    onDoubleTap: onToggleFocusedCamera,
                    onZoomChange: onZoomChange)
            }
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

    /// The camera strip — multicam's one added element. Thumbnails of the other
    /// cameras plus the Add tile, laid out along `axis` so it tucks into the
    /// action area on either dock. Tap a thumbnail to focus it; long-press for
    /// "Disconnect Camera".
    @ViewBuilder
    private func cameraStrip(axis: Axis) -> some View {
        let others = viewModel.otherLanes
        let tile = CGSize(width: axis == .horizontal ? 72 : 96,
                          height: axis == .horizontal ? 96 : 72)
        Group {
            if axis == .horizontal {
                HStack(spacing: 8) { stripTiles(others, size: tile) }
            } else {
                VStack(spacing: 8) { stripTiles(others, size: tile) }
            }
        }
    }

    @ViewBuilder
    private func stripTiles(_ others: [CameraLane], size: CGSize) -> some View {
        ForEach(others) { lane in
            CameraTileView(lane: lane, isThumbnail: true, onRetry: { onRetryCollection(lane) })
                .frame(width: size.width, height: size.height)
                .onTapGesture { onFocusLane(lane) }
                .contextMenu { disconnectButton(for: lane) }
        }
        addCameraTile.frame(width: size.width, height: size.height)
    }

    /// The "add camera" affordance at the end of the strip. The host decides
    /// whether tapping opens the sheet or the paywall (at the tier cap).
    private var addCameraTile: some View {
        Button(action: onAddCamera) {
            VStack(spacing: 6) {
                Image(systemName: "plus.circle.fill").font(.title)
                Text(NSLocalizedString("Add camera", comment: "add a camera to the multicam rig"))
                    .font(.caption2)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

/// The single status a tile shows, coalesced from the lane's capture and
/// collection state so a synced photo (both captured AND collected) reads as
/// one green check, never two overlapping glyphs.
enum TileStatus: Equatable {
    case none
    case reconnecting
    case recording
    case transferring(Double)
    case success        // captured and/or collected — one confirmation
    case captureFailed  // the shot nacked; not retryable from the tile
    case transferFailed // footage collection failed; tap to retry
    case needsRematch   // can't match the running rig quality

    /// Success confirmations are transient — they fade off the tile.
    var isTransient: Bool { self == .success }

    /// Priority ladder (highest first): failed > reconnecting > transferring >
    /// REC > success > rematch > nothing. `includeSuccess: false` yields the
    /// resting status the tile falls back to once a success confirmation fades.
    static func resolve(status: CameraLink.Status,
                        captureOutcome: CaptureOutcome?,
                        isRecording: Bool,
                        collection: CameraLink.LaneCollectionState,
                        needsQualityRematch: Bool,
                        includeSuccess: Bool = true) -> TileStatus {
        if collection == .failed { return .transferFailed }
        if captureOutcome == .failed { return .captureFailed }
        if status == .reconnecting { return .reconnecting }
        if case .transferring(let progress) = collection { return .transferring(progress) }
        if isRecording { return .recording }
        if includeSuccess, collection == .collected || captureOutcome == .captured { return .success }
        if needsQualityRematch { return .needsRematch }
        return .none
    }
}

/// One corner badge, one glyph, on a glass circle with a surface ring so it
/// reads cleanly over any frame — the fix for the overlapping-checks blob.
struct TileStatusBadge: View {
    let status: TileStatus
    let onRetry: (() -> Void)?
    /// Smaller on strip/grid thumbnails, full size on a focused tile.
    var diameter: CGFloat = 28

    var body: some View {
        switch status {
        case .none, .reconnecting:
            EmptyView()
        case .transferFailed:
            Button { onRetry?() } label: { chip("arrow.clockwise.icloud", tint: .white) }
        case .captureFailed:
            chip("exclamationmark.triangle.fill", tint: .yellow)
        case .needsRematch:
            chip("exclamationmark.triangle.fill", tint: .yellow)
        case .recording:
            chip("record.circle.fill", tint: .red)
        case .transferring(let progress):
            chip(nil, tint: .white, progress: progress)
        case .success:
            chip("checkmark.circle.fill", tint: .green)
        }
    }

    /// A glass circle with a 2px surface ring; either an SF Symbol or a
    /// determinate progress ring.
    private func chip(_ symbol: String?, tint: Color, progress: Double? = nil) -> some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 2)
            if let progress {
                Circle().trim(from: 0, to: max(0.02, progress))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(4)
            } else if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: diameter * 0.54, weight: .semibold))
                    .foregroundColor(tint)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// One camera's tile: its isolated live frame, a name chip, a focus ring, and
/// a reconnecting scrim. `Equatable` on the value inputs so a frame delivered
/// to another lane can't invalidate this tile's chrome — only its own
/// `LiveFrameView` (observing its own `FrameDisplayModel`) re-renders.
struct CameraTileView: View {
    @ObservedObject var lane: CameraLane
    var isThumbnail: Bool = false
    /// Retry a failed footage collection for this lane (nil = not offered).
    var onRetry: (() -> Void)? = nil

    /// The one status this tile shows, before the transient-success fade.
    private var baseStatus: TileStatus {
        TileStatus.resolve(status: lane.status,
                           captureOutcome: lane.captureOutcome,
                           isRecording: lane.isRecording,
                           collection: lane.collection,
                           needsQualityRematch: lane.needsQualityRematch)
    }

    /// The status actually rendered: once a success confirmation has faded, the
    /// tile falls back to its resting status (a rematch warning, or nothing).
    private var shownStatus: TileStatus {
        guard baseStatus == .success, successFaded else { return baseStatus }
        return TileStatus.resolve(status: lane.status,
                                  captureOutcome: lane.captureOutcome,
                                  isRecording: lane.isRecording,
                                  collection: lane.collection,
                                  needsQualityRematch: lane.needsQualityRematch,
                                  includeSuccess: false)
    }

    @State private var successFaded = false

    var body: some View {
        ZStack {
            LiveFrameView(frames: lane.frames, aspectRatio: .sixteenNine)
                .clipShape(RoundedRectangle(cornerRadius: isThumbnail ? 10 : 0))
                .saturation(lane.status == .linked ? 1 : 0)

            // Reconnecting is the one full-tile treatment; every other status is
            // the single corner badge, so nothing ever stacks on nothing.
            if shownStatus == .reconnecting {
                RoundedRectangle(cornerRadius: isThumbnail ? 10 : 0)
                    .fill(Color.black.opacity(0.45))
                    .overlay(
                        Text(NSLocalizedString("RECONNECTING", comment: "peer link dropped"))
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.white))
            } else {
                VStack {
                    HStack {
                        Spacer()
                        TileStatusBadge(status: shownStatus, onRetry: onRetry,
                                        diameter: isThumbnail ? 22 : 28)
                            .transition(.opacity)
                    }
                    Spacer()
                }
                .padding(6)
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
        // Auto-fade a success confirmation after ~2s; the task restarts (and
        // resets the fade) whenever the underlying status changes.
        .task(id: baseStatus) {
            successFaded = false
            guard baseStatus.isTransient else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.easeInOut(duration: 0.3)) { successFaded = true }
        }
    }
}

/// Lists the cameras the director's browser has discovered but not yet added,
/// so the user can invite them into the rig mid-session. Shown only below the
/// tier cap (the host routes to the paywall at the cap).
struct AddCameraSheet: View {
    let peers: [MCPeerID]
    let onInvite: (MCPeerID) -> Void

    var body: some View {
        NavigationView {
            Group {
                if peers.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(NSLocalizedString("Searching for cameras…",
                                               comment: "add-camera sheet, no peers yet"))
                            .foregroundColor(.secondary)
                    }
                } else {
                    List(peers, id: \.self) { peer in
                        Button { onInvite(peer) } label: {
                            HStack {
                                Image(systemName: "iphone.radiowaves.left.and.right")
                                    .foregroundColor(AppTheme.accent)
                                Text(peer.displayName)
                                Spacer()
                                Text(NSLocalizedString("Add", comment: "invite this camera"))
                                    .foregroundColor(AppTheme.accent)
                            }
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Add camera",
                                               comment: "add a camera to the multicam rig"))
        }
    }
}

/// The rig settings tray: one self-timer + rig-wide quality (the intersection
/// model). Manual quality selection is first-class; "Automatic" is the reset at
/// the top. Reachable from both focus and grid modes.
/// The rig settings tray, in the 1:1 monitor's glass presentation: a floating
/// panel of tiles that cycle their value in place over the live preview
/// (reusing `MonitorTrayTile`), rather than a pushed table. Timer and quality
/// carry rig semantics — quality cycles the capability intersection, and a
/// footnote names any camera that blocks an option.
struct RigTrayPanel: View {
    let settings: RigSettingsSnapshot
    let onSetTimer: (Int) -> Void
    let onSelectVideoQuality: (VideoResolution, VideoFrameRate) -> Void
    let onAutomaticVideoQuality: () -> Void
    let onSetPhotoFormat: (PhotoFormat) -> Void
    let onSetHDR: (Bool) -> Void

    private let timerStops = [0, 3, 5, 10, 20]

    var body: some View {
        TrayPanelShell(footnote: settings.blockerFootnote) {
            MonitorTrayTile(item: .timer, value: settings.timerSeconds > 0 ? "\(settings.timerSeconds)" : nil,
                            isActive: settings.timerSeconds > 0, isEnabled: true,
                            action: cycleTimer)
            MonitorTrayTile(item: .resolution, value: settings.videoTileValue,
                            isActive: settings.activeVideo != nil,
                            isEnabled: !settings.videoOptions.filter(\.enabled).isEmpty,
                            action: cycleQuality)
            MonitorTrayTile(item: .format, value: (settings.activePhotoFormat ?? .jpeg).displayName,
                            isActive: settings.activePhotoFormat == .heif,
                            isEnabled: settings.heifAvailable,
                            action: { onSetPhotoFormat(settings.activePhotoFormat == .heif ? .jpeg : .heif) })
            MonitorTrayTile(item: .hdr, value: nil,
                            isActive: settings.activeHDR == .on,
                            isEnabled: settings.hdrAvailable,
                            action: { onSetHDR(settings.activeHDR != .on) })
        }
    }

    private func cycleTimer() {
        let idx = timerStops.firstIndex(of: settings.timerSeconds) ?? 0
        onSetTimer(timerStops[(idx + 1) % timerStops.count])
    }

    private func cycleQuality() {
        if let next = settings.nextVideoSelection {
            onSelectVideoQuality(next.resolution, next.frameRate)
        } else {
            onAutomaticVideoQuality()
        }
    }
}
