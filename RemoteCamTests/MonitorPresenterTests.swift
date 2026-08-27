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

    var photoModeConfigured = 0
    var videoModeConfigured = 0
    var videoRecordingConfigured = 0
    var shortsModeConfigured = 0
    var exits = 0
    var flashModes: [AVCaptureDevice.FlashMode] = []
    var torchModes: [AVCaptureDevice.TorchMode] = []
    /// Every control snapshot the presenter applied, in order.
    var controlStates: [ControlState] = []

    // Mirrors the real MonitorViewController conformance (counter + the
    // view-model configure), so end-to-end tests can assert the screen state
    // a render actually produces — pinned against the real thing by
    // ControllerWiringTests.testMonitorDisplayConformanceDrivesViewModelState.
    func swiftUIConfigurePhotoMode() { photoModeConfigured += 1; viewModel.configurePhotoMode() }
    func swiftUIConfigureVideoMode() { videoModeConfigured += 1; viewModel.configureVideoMode() }
    func swiftUIConfigureVideoRecording() { videoRecordingConfigured += 1; viewModel.configureVideoRecording() }
    func swiftUIConfigureShortsMode() { shortsModeConfigured += 1; viewModel.configureShortsMode() }
    func exitMonitor() { exits += 1 }
    func updateFlashModeInViewModel(_ flashMode: AVCaptureDevice.FlashMode) {
        flashModes.append(flashMode)
    }
    func updateTorchModeInViewModel(_ torchMode: AVCaptureDevice.TorchMode) {
        torchModes.append(torchMode)
    }
    // Mirrors the real MonitorViewController: the snapshot lands in the view
    // model (so `exposure`, `zoomScale`, … read back), and is recorded for
    // order/count assertions.
    func applyControlState(_ state: ControlState) {
        controlStates.append(state)
        viewModel.applyControlState(state)
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

    // MARK: - Exposure echo

    func testApplyControlStateLandsExposureInViewModelOnMain() {
        let state = ExposureState(mode: .manual, durationSeconds: 1.0 / 125, iso: 200,
                                  minDurationSeconds: 1.0 / 8000, maxDurationSeconds: 0.5, minISO: 50, maxISO: 1600)
        presenter.applyControlState(ControlState(seq: 1, exposure: state))
        drain()
        XCTAssertTrue(display.viewModel.supportsManualExposure)
        XCTAssertEqual(display.viewModel.exposure, state)

        // A swap to a device that can't do it: the snapshot omits exposure and
        // the control disappears — capability is presence.
        presenter.applyControlState(ControlState(seq: 2))
        drain()
        XCTAssertFalse(display.viewModel.supportsManualExposure)
        XCTAssertNil(display.viewModel.exposure)
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

    // MARK: - Control snapshot: zoom + lens are one value now

    func testApplyControlStateDrivesZoomAndLens() {
        presenter.applyControlState(ControlState(
            seq: 1,
            currentLens: .telephoto,
            availableLenses: [.wideAngle, .telephoto],
            zoomFactor: 3.0, minZoom: 1.0, maxZoom: 12.0,
            zoomStops: [1.0, 3.0], wideAngleZoomFactor: 1.0))
        drain()

        XCTAssertEqual(display.controlStates.count, 1)
        XCTAssertEqual(display.viewModel.currentZoomFactor, 3.0, accuracy: 0.001)
        XCTAssertEqual(display.viewModel.currentLensType, .telephoto)
        XCTAssertEqual(display.viewModel.availableLensTypes, [.wideAngle, .telephoto])
        // The pill's ceiling is the snapshot's effective max (display-capped).
        XCTAssertEqual(display.viewModel.zoomScale.maxZoom, 5.0, accuracy: 0.001)
    }

    /// The fold drops a stale snapshot: an out-of-order older seq never
    /// overwrites fresher zoom/lens truth.
    func testApplyControlStateDropsStaleSnapshot() {
        presenter.applyControlState(ControlState(seq: 9, zoomFactor: 4.0, minZoom: 1.0, maxZoom: 10.0,
                                                 zoomStops: [1.0], wideAngleZoomFactor: 1.0))
        presenter.applyControlState(ControlState(seq: 4, zoomFactor: 1.0, minZoom: 1.0, maxZoom: 10.0,
                                                 zoomStops: [1.0], wideAngleZoomFactor: 1.0))
        drain()
        XCTAssertEqual(display.viewModel.currentZoomFactor, 4.0, accuracy: 0.001,
                       "the older snapshot must not clobber the newer zoom")
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
            frontCamera: nil, backCamera: nil, currentCamera: .back,
            cameraDevices: devices,
            control: ControlState(seq: 1, activeDeviceID: "facetime-0"), error: nil)

        presenter.updateCapabilities(capabilities)
        drain()

        XCTAssertEqual(display.viewModel.remoteCameraDevices, devices)
        XCTAssertEqual(display.viewModel.activeRemoteDeviceID, "facetime-0")
    }

    func testLegacyCapabilitiesClearDeviceList() {
        display.viewModel.remoteCameraDevices = [
            RemoteCmd.CameraDeviceEntry(
                uniqueID: "stale", localizedName: "Stale",
                positionRaw: 0, isActive: true, info: nil)
        ]
        let capabilities = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: nil, backCamera: nil, currentCamera: .back,
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
