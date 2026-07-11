//
//  MonitorPresenterTests.swift
//  RemoteShutterTests
//
//  MonitorPresenter is decoupled from MonitorViewController via the
//  MonitorDisplay protocol — these tests drive the presenter against a fake
//  display.
//

import XCTest
import AVFoundation

@testable import RemoteShutter

// MARK: - Fake display

class FakeMonitorDisplay: MonitorDisplay {
    let viewModel = MonitorViewModel()
    let frameStreamReceiver = FrameStreamReceiver()
    var maxZoomFactor: CGFloat = 10.0

    var photoModeConfigured = 0
    var videoModeConfigured = 0
    var videoRecordingConfigured = 0
    var shortsModeConfigured = 0
    var exits = 0
    var flashModes: [AVCaptureDevice.FlashMode] = []
    var torchModes: [AVCaptureDevice.TorchMode] = []
    var zoomUpdates: [(factor: CGFloat, maxFactor: CGFloat)] = []
    var lensUpdates: [(lenses: [CameraLensType], current: CameraLensType)] = []

    func swiftUIConfigurePhotoMode() { photoModeConfigured += 1 }
    func swiftUIConfigureVideoMode() { videoModeConfigured += 1 }
    func swiftUIConfigureVideoRecording() { videoRecordingConfigured += 1 }
    func swiftUIConfigureShortsMode() { shortsModeConfigured += 1 }
    func exitMonitor() { exits += 1 }
    func updateFlashModeInViewModel(_ flashMode: AVCaptureDevice.FlashMode) {
        flashModes.append(flashMode)
    }
    func updateTorchModeInViewModel(_ torchMode: AVCaptureDevice.TorchMode) {
        torchModes.append(torchMode)
    }
    func updateZoomInViewModel(_ factor: CGFloat, maxFactor: CGFloat) {
        zoomUpdates.append((factor, maxFactor))
    }
    func updateLensTypesInViewModel(_ lenses: [CameraLensType], current: CameraLensType) {
        lensUpdates.append((lenses, current))
    }
}

// MARK: - Tests

class MonitorPresenterTests: XCTestCase {

    private var presenter: MonitorPresenter!
    private var display: FakeMonitorDisplay!

    override func setUp() {
        super.setUp()
        presenter = MonitorPresenter()
        display = FakeMonitorDisplay()
        presenter.setDisplay(display)
    }

    override func tearDown() {
        presenter = nil
        display = nil
        super.tearDown()
    }

    /// Pumps the main queue where the presenter dispatches its display updates.
    private func drain() {
        let expectation = expectation(description: "main queue drained")
        OperationQueue.main.addOperation { expectation.fulfill() }
        wait(for: [expectation], timeout: 5.0)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }

    // MARK: - Render calls

    func testRenderMessagesConfigureDisplayModes() {
        presenter.renderPhotoMode()
        presenter.renderVideoMode()
        presenter.renderVideoModeRecording()
        drain()

        XCTAssertEqual(display.photoModeConfigured, 1)
        XCTAssertEqual(display.videoModeConfigured, 1)
        XCTAssertEqual(display.videoRecordingConfigured, 1)
    }

    // MARK: - BecomeMonitorFailed

    func testBecomeMonitorFailedExitsMonitor() {
        presenter.becomeMonitorFailed()
        drain()

        XCTAssertEqual(display.exits, 1)
    }

    // MARK: - Flash / torch responses

    func testToggleFlashRespUpdatesFlashMode() {
        presenter.updateFlashMode(.on)
        drain()

        XCTAssertEqual(display.flashModes, [.on])
    }

    func testToggleFlashRespWithoutModeDoesNothing() {
        presenter.updateFlashMode(nil)
        drain()

        XCTAssertTrue(display.flashModes.isEmpty)
    }

    // MARK: - Zoom responses

    func testSetZoomRespUpdatesZoom() {
        presenter.updateZoom(3.0,
                             zoomRange: RemoteCmd.ZoomRange(minZoom: 1.0, maxZoom: 12.0),
                             currentLens: nil)
        drain()

        XCTAssertEqual(display.zoomUpdates.count, 1)
        XCTAssertEqual(display.zoomUpdates[0].factor, 3.0, accuracy: 0.001)
        XCTAssertEqual(display.zoomUpdates[0].maxFactor, 12.0, accuracy: 0.001)
    }

    func testSetZoomRespWithoutRangeFallsBackToDisplayMax() {
        presenter.updateZoom(2.0, zoomRange: nil, currentLens: nil)
        drain()

        XCTAssertEqual(display.zoomUpdates.count, 1)
        XCTAssertEqual(display.zoomUpdates[0].maxFactor, display.maxZoomFactor, accuracy: 0.001)
    }

    // MARK: - Lens responses

    func testSwitchLensRespUpdatesLensesAndZoom() {
        presenter.updateLens(.telephoto,
                             availableLenses: [.wideAngle, .telephoto],
                             currentZoom: 2.0,
                             zoomRange: RemoteCmd.ZoomRange(minZoom: 1.0, maxZoom: 8.0))
        drain()

        XCTAssertEqual(display.lensUpdates.count, 1)
        XCTAssertEqual(display.lensUpdates[0].current, .telephoto)
        XCTAssertEqual(display.lensUpdates[0].lenses, [.wideAngle, .telephoto])
        XCTAssertEqual(display.zoomUpdates.count, 1)
        XCTAssertEqual(display.zoomUpdates[0].maxFactor, 8.0, accuracy: 0.001)
    }

    // MARK: - Video transfer progress

    func testVideoTransferMessagesDriveViewModel() {
        presenter.videoTransferStarted(totalBytes: 1000)
        drain()
        XCTAssertTrue(display.viewModel.isVideoTransferring)

        presenter.videoTransferFinished()
        drain()
        XCTAssertFalse(display.viewModel.isVideoTransferring)
    }
}
