import XCTest
import SwiftUI
@testable import RemoteShutter

/// Renders `CameraScreenView` in a real window (hosted test bundle) across its
/// chrome states and attaches PNGs to the test result, so the camera screen —
/// which in the app only exists with a connected peer — can be verified
/// visually without one. Each test also asserts the render is non-blank so a
/// broken layout fails in CI, not just in the attachment gallery.
@MainActor
final class CameraScreenSnapshotTests: SnapshotTestCase {

    private func renderCameraScreen(named name: String, configure: (CameraViewModel) -> Void) -> UIImage {
        let model = CameraViewModel()
        configure(model)
        return renderScreen(named: name, CameraScreenView(viewModel: model))
    }

    func testIdlePhotoModeChrome() {
        let image = renderCameraScreen(named: "camera-idle-photo") { model in
            model.updateStatus(mode: .Photo, resolution: .hd1080p, frameRate: .fps30,
                               photoFormat: .jpeg, hdrMode: .on)
        }
        assertHasChrome(image)
    }

    func testRecordingChromeShowsBadgeAndTimer() {
        let image = renderCameraScreen(named: "camera-recording") { model in
            model.updateStatus(mode: .Video, resolution: .hd1080p, frameRate: .fps30,
                               photoFormat: .jpeg, hdrMode: .off)
            model.isRecordingIndicatorVisible = true
            model.recordingStartTime = Date().addingTimeInterval(-65)
            model.isRecordingTimerActive = true
        }
        assertHasChrome(image)
    }

    func testRecordingAwaitingRemoteShowsChipAndStop() {
        let image = renderCameraScreen(named: "camera-recording-awaiting-remote") { model in
            model.updateStatus(mode: .Video, resolution: .hd1080p, frameRate: .fps30,
                               photoFormat: .jpeg, hdrMode: .off)
            model.isRecordingIndicatorVisible = true
            model.recordingStartTime = Date().addingTimeInterval(-65)
            model.isRecordingTimerActive = true
            model.isAwaitingRemoteReconnect = true
        }
        assertHasChrome(image)
    }

    func testIdleAwaitingRemoteShowsChipOnly() {
        let image = renderCameraScreen(named: "camera-idle-awaiting-remote") { model in
            model.updateStatus(mode: .Video, resolution: .hd1080p, frameRate: .fps30,
                               photoFormat: .jpeg, hdrMode: .off)
            model.isAwaitingRemoteReconnect = true
        }
        assertHasChrome(image)
    }

    func testCountdownChrome() {
        let image = renderCameraScreen(named: "camera-countdown") { model in
            model.showCountdown(3)
        }
        assertHasChrome(image)
    }

    func testVideoTransferChrome() {
        let image = renderCameraScreen(named: "camera-video-transfer") { model in
            model.startVideoTransfer(totalBytes: 45_800_000)
            model.updateVideoTransferProgress(completedBytes: 15_200_000, totalBytes: 45_800_000)
            model.updateVideoTransferSpeed(2_100_000)
        }
        assertHasChrome(image)
    }
}
