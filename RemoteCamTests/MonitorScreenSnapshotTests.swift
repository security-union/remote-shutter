import XCTest
import SwiftUI
@testable import RemoteShutter

/// Renders `MonitorView` — the remote-control screen — in a real window
/// across its chrome states, with a synthetic camera frame standing in for
/// the streamed preview. PNGs are attached to the test result; each render
/// is asserted non-blank so a broken layout fails in CI.
@MainActor
final class MonitorScreenSnapshotTests: SnapshotTestCase {

    /// MonitorView's action closures all route to the hosting VC; snapshots
    /// only need them to exist.
    private func makeMonitorView(_ viewModel: MonitorViewModel) -> MonitorView {
        MonitorView(
            viewModel: viewModel,
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
            onToggleCameraStandby: {})
    }

    /// A connected monitor with a live frame and the full lens/zoom surface.
    private func makeConnectedModel() -> MonitorViewModel {
        let model = MonitorViewModel()
        model.frames.cameraImage = syntheticCameraFrame()
        model.availableLensTypes = [.ultraWide, .wideAngle, .telephoto]
        model.currentLensType = .wideAngle
        model.zoomStops = [1.0, 2.0, 5.0]
        model.currentZoomFactor = 1.0
        return model
    }

    func testPhotoModeWithLiveFrame() {
        let model = makeConnectedModel()
        model.currentMode = .Photo
        model.uiState = .photoMode

        let image = renderScreen(named: "monitor-photo-mode", makeMonitorView(model))
        assertHasChrome(image)
    }

    func testVideoRecordingShowsTimer() {
        let model = makeConnectedModel()
        model.currentMode = .Video
        model.uiState = .videoRecording
        model.isRecording = true
        model.recordingStartTime = Date().addingTimeInterval(-42)
        model.isShowingRecordingDuration = true

        let image = renderScreen(named: "monitor-video-recording", makeMonitorView(model))
        assertHasChrome(image)
    }

    func testWaitingForFirstFrame() {
        // Fresh connection: no frame from the camera yet.
        let model = MonitorViewModel()
        model.currentMode = .Photo
        model.uiState = .photoMode

        let image = renderScreen(named: "monitor-waiting-for-frame", makeMonitorView(model))
        assertHasChrome(image)
    }

    func testTwoCamerasShowFlipButtonAndActiveName() {
        // iPhone-shaped peer: two usable cameras — the classic flip button,
        // plus the active-camera name overlay on the preview.
        let model = makeConnectedModel()
        model.currentMode = .Photo
        model.uiState = .photoMode
        model.remoteCameraDevices = [
            RemoteCmd.CameraDeviceEntry(
                uniqueID: "back-0", localizedName: "Back Dual Wide Camera",
                positionRaw: 0, isActive: true, info: nil),
            RemoteCmd.CameraDeviceEntry(
                uniqueID: "front-0", localizedName: "Front Camera",
                positionRaw: 1, isActive: false, info: nil)
        ]
        model.activeRemoteDeviceID = "back-0"

        let image = renderScreen(named: "monitor-two-camera-flip", makeMonitorView(model))
        assertHasChrome(image)
    }

    func testManyCamerasShowDeviceMenu() {
        // Mac-shaped peer: several cameras, one suspended (grayed in the menu).
        let model = makeConnectedModel()
        model.currentMode = .Photo
        model.uiState = .photoMode
        model.remoteCameraDevices = [
            RemoteCmd.CameraDeviceEntry(
                uniqueID: "facetime-0", localizedName: "FaceTime HD Camera",
                positionRaw: 0, isActive: true, info: nil),
            RemoteCmd.CameraDeviceEntry(
                uniqueID: "usb-0", localizedName: "USB Camera",
                positionRaw: 0, isActive: false, info: nil),
            RemoteCmd.CameraDeviceEntry(
                uniqueID: "builtin-0", localizedName: "MacBook Pro Camera",
                positionRaw: 0, isActive: false, isSuspended: true, info: nil)
        ]
        model.activeRemoteDeviceID = "facetime-0"

        let image = renderScreen(named: "monitor-device-menu", makeMonitorView(model))
        assertHasChrome(image)
    }

    func testVideoTransferProgress() {
        let model = makeConnectedModel()
        model.currentMode = .Video
        model.uiState = .videoMode
        model.isVideoTransferring = true
        model.videoTransferProgress = 0.33
        model.videoTransferBytesCompleted = 15_200_000
        model.videoTransferBytesTotal = 45_800_000
        model.videoTransferSpeed = 2_100_000

        let image = renderScreen(named: "monitor-video-transfer", makeMonitorView(model))
        assertHasChrome(image)
    }

    // MARK: - Landscape

    /// The shape the redesign exists to serve: the remote turned sideways to
    /// match a tripod-mounted landscape camera. The action cluster moves to the
    /// trailing rail so the bottom stays free for the picture.
    func testLandscapePutsActionClusterOnTrailingRail() {
        setWindowSize(CGSize(width: 852, height: 393))
        let model = makeConnectedModel()
        model.currentMode = .Photo
        model.uiState = .photoMode

        let image = renderScreen(named: "monitor-landscape-photo", makeMonitorView(model))
        assertHasChrome(image)
    }

    func testLandscapeVideoRecording() {
        setWindowSize(CGSize(width: 852, height: 393))
        let model = makeConnectedModel()
        model.currentMode = .Video
        model.uiState = .videoRecording
        model.isRecording = true
        model.recordingStartTime = Date().addingTimeInterval(-42)
        model.isShowingRecordingDuration = true

        let image = renderScreen(named: "monitor-landscape-recording", makeMonitorView(model))
        assertHasChrome(image)
    }

    // MARK: - Capture feedback

    /// A capture in flight shows on the shutter, not as a modal over the
    /// preview — the whole point of deriving activity from session state.
    func testCaptureInFlightShowsOnShutterNotOverPreview() {
        let model = makeConnectedModel()
        model.currentMode = .Photo
        model.uiState = .photoMode
        model.activity = .capturing

        let image = renderScreen(named: "monitor-capture-in-flight", makeMonitorView(model))
        assertHasChrome(image)
    }

    /// The self-timer is centered and large enough to read from across the
    /// room, where the subject actually is.
    func testCountdownIsCenteredOverPreview() {
        let model = makeConnectedModel()
        model.currentMode = .Photo
        model.uiState = .photoMode
        model.timerValue = 5

        let image = renderScreen(named: "monitor-countdown", makeMonitorView(model))
        assertHasChrome(image)
    }

    // MARK: - Tray

    /// The tray is where the self-timer and the quality controls went when they
    /// left the permanent row, so it needs its own render: `MonitorView` owns
    /// `isTrayOpen` as private state and no test can reach it, which would
    /// otherwise leave every tile uncovered by snapshots.
    private func makeTrayPanel(items: [MonitorTrayItem], timerValue: Int) -> MonitorTrayPanel {
        MonitorTrayPanel(
            items: items,
            timerValue: timerValue,
            aspectRatio: .sixteenNine,
            resolution: .hd1080p,
            frameRate: .fps30,
            photoFormat: .heif,
            hdrMode: .on,
            isQualityEnabled: true,
            isTimerEnabled: true,
            isSettingsEnabled: true,
            onTap: { _ in })
    }

    /// Docked to the bottom over the dimmed viewfinder, the way it appears in
    /// the screen rather than floating in isolation.
    private func trayAsPresented(_ panel: MonitorTrayPanel) -> some View {
        ZStack(alignment: .bottom) {
            Color.black
            panel
        }
        .ignoresSafeArea()
    }

    func testPhotoTrayShowsTimerWithItsValue() {
        let items = MonitorTray.items(for: .photoMode,
                                      supportsHEIF: true,
                                      supportsHDR: true,
                                      resolutionCount: 0,
                                      frameRateCount: 0)
        XCTAssertEqual(items.first, .timer, "Timer should lead the photo tray")

        let image = renderScreen(named: "monitor-tray-photo",
                                 trayAsPresented(makeTrayPanel(items: items, timerValue: 10)))
        assertRendered(image)
    }

    func testVideoTrayShowsTimerAlongsideQuality() {
        let items = MonitorTray.items(for: .videoMode,
                                      supportsHEIF: false,
                                      supportsHDR: false,
                                      resolutionCount: 2,
                                      frameRateCount: 3)
        XCTAssertEqual(items.first, .timer, "Timer should lead the video tray")

        let image = renderScreen(named: "monitor-tray-video",
                                 trayAsPresented(makeTrayPanel(items: items, timerValue: 3)))
        assertRendered(image)
    }
}
