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
            onAspectRatioChange: { _ in })
    }

    /// A connected monitor with a live frame and the full lens/zoom surface.
    private func makeConnectedModel() -> MonitorViewModel {
        let model = MonitorViewModel()
        model.cameraImage = syntheticCameraFrame()
        model.availableLensTypes = [.ultraWide, .wideAngle, .telephoto]
        model.currentLensType = .wideAngle
        model.zoomStops = [1.0, 2.0, 5.0]
        model.showZoomControls = true
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
}
