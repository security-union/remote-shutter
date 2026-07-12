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

    // MARK: - Camera device list

    /// A Mac camera peer advertises N devices but has no front/back
    /// CameraInfo — the device list must reach the view model anyway.
    func testCapabilitiesWithoutPositionInfoStillDeliverDeviceList() {
        let devices = [
            RemoteCmd.CameraDeviceEntry(
                uniqueID: "facetime-0", localizedName: "FaceTime HD Camera",
                positionRaw: AVCaptureDevice.Position.unspecified.rawValue,
                isActive: true, info: nil),
            RemoteCmd.CameraDeviceEntry(
                uniqueID: "usb-0", localizedName: "USB Camera",
                positionRaw: AVCaptureDevice.Position.unspecified.rawValue,
                isActive: false, info: nil)
        ]
        let capabilities = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, currentLens: .wideAngle, currentZoom: 1.0,
            cameraDevices: devices, activeDeviceID: "facetime-0", error: nil)

        presenter.updateCapabilities(capabilities)
        drain()

        XCTAssertEqual(display.viewModel.remoteCameraDevices, devices)
        XCTAssertEqual(display.viewModel.activeRemoteDeviceID, "facetime-0")
        // No front/back info: the lens/zoom sync is skipped, not crashed.
        XCTAssertTrue(display.lensUpdates.isEmpty)
    }

    func testLegacyCapabilitiesClearDeviceList() {
        display.viewModel.remoteCameraDevices = [
            RemoteCmd.CameraDeviceEntry(
                uniqueID: "stale", localizedName: "Stale",
                positionRaw: 0, isActive: true, info: nil)
        ]
        let capabilities = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil,
            currentCamera: .back, currentLens: .wideAngle, currentZoom: 1.0,
            error: nil)

        presenter.updateCapabilities(capabilities)
        drain()

        XCTAssertTrue(display.viewModel.remoteCameraDevices.isEmpty,
                      "a legacy peer's capabilities must clear a stale device list")
        XCTAssertNil(display.viewModel.activeRemoteDeviceID)
    }

    // MARK: - Camera switch control policy

    private func entry(_ id: String, suspended: Bool = false) -> RemoteCmd.CameraDeviceEntry {
        RemoteCmd.CameraDeviceEntry(
            uniqueID: id, localizedName: id, positionRaw: 0,
            isActive: false, isSuspended: suspended, info: nil)
    }

    func testSwitchControlMatchesCameraTopology() {
        // Legacy peer (no list): count unknown — keep the classic flip.
        XCTAssertEqual(MonitorViewModel.switchControl(for: []), .flipButton)
        // One camera: nothing to switch to.
        XCTAssertEqual(MonitorViewModel.switchControl(for: [entry("a")]), .hidden)
        // Two usable cameras: the classic flip button.
        XCTAssertEqual(MonitorViewModel.switchControl(for: [entry("a"), entry("b")]), .flipButton)
        // Two cameras but one suspended: the menu explains the grayed device.
        XCTAssertEqual(
            MonitorViewModel.switchControl(for: [entry("a"), entry("b", suspended: true)]),
            .deviceMenu)
        // Three or more: the menu.
        XCTAssertEqual(
            MonitorViewModel.switchControl(for: [entry("a"), entry("b"), entry("c")]),
            .deviceMenu)
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

// MARK: - Error alert dedup

/// The presenter is the single gate for error alerts: an error identical to
/// the one already on screen is dropped instead of stacked (a peer disconnect
/// fails many queued sends in a burst; the user should hear about it once).
@MainActor
final class AlertDedupTests: XCTestCase {

    func testIdenticalErrorDoesNotStackWhileVisible() {
        XCTAssertTrue(UIAlertPresenter.presentErrorDeduped(title: "Connection error (dedup test)"))
        // Let the presentation commit.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))

        XCTAssertFalse(UIAlertPresenter.presentErrorDeduped(title: "Connection error (dedup test)"),
                       "an identical error must be dropped while one is on screen")
        XCTAssertTrue(UIAlertPresenter.presentErrorDeduped(title: "A different error (dedup test)"),
                      "a different error is still surfaced")
    }
}
