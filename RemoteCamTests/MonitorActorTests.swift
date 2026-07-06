//
//  MonitorActorTests.swift
//  RemoteShutterTests
//
//  MonitorActor is decoupled from MonitorViewController via the
//  MonitorDisplay protocol — these tests drive the actor against a fake
//  display, something that was impossible when the actor was generic
//  over the concrete UIKit controller.
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

class MonitorActorTests: XCTestCase {

    private var system: TestActorSystem!
    private var actorRef: ActorRef!
    private var actor: MonitorActor!
    private var display: FakeMonitorDisplay!

    // MonitorActor's init sends BecomeMonitor to the shared session actor.
    private var sharedSessionRef: ActorRef!
    private var sharedSessionInstanceId: ObjectIdentifier!

    override func setUp() {
        super.setUp()

        sharedSessionRef = RemoteCamSystem.shared.actorOf(
            clz: TestableRemoteCamSession.self, name: "RemoteCam Session", replace: true)!
        sharedSessionInstanceId = RemoteCamSystem.shared.instanceId(forRef: sharedSessionRef)

        system = TestActorSystem(name: "monitor-actor-tests")
        actorRef = system.actorOf(clz: MonitorActor.self, name: "MonitorActor")
        actor = (system.actorForRef(ref: actorRef) as! MonitorActor)
        display = FakeMonitorDisplay()

        actorRef ! SetMonitorDisplay(display: display)
        drain()
    }

    override func tearDown() {
        drain()
        system.stop()
        drain()
        stopActorIfCurrent(ref: sharedSessionRef, instanceId: sharedSessionInstanceId)
        system = nil
        actorRef = nil
        actor = nil
        display = nil
        sharedSessionRef = nil
        sharedSessionInstanceId = nil
        super.tearDown()
    }

    /// Waits for the actor's mailbox, then pumps the main queue where the
    /// actor dispatches its display updates.
    private func drain() {
        let expectation = expectation(description: "mailbox drained")
        actor.mailbox.addOperation { expectation.fulfill() }
        wait(for: [expectation], timeout: 5.0)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }

    // MARK: - Render messages

    func testRenderMessagesConfigureDisplayModes() {
        actorRef ! UICmd.RenderPhotoMode(sender: nil)
        actorRef ! UICmd.RenderVideoMode(sender: nil)
        actorRef ! UICmd.RenderVideoModeRecording(sender: nil)
        drain()

        XCTAssertEqual(display.photoModeConfigured, 1)
        XCTAssertEqual(display.videoModeConfigured, 1)
        XCTAssertEqual(display.videoRecordingConfigured, 1)
    }

    // MARK: - BecomeMonitorFailed

    func testBecomeMonitorFailedExitsMonitor() {
        actorRef ! UICmd.BecomeMonitorFailed(sender: nil)
        drain()

        XCTAssertEqual(display.exits, 1)
    }

    // MARK: - Flash / torch responses

    func testToggleFlashRespUpdatesFlashMode() {
        actorRef ! RemoteCmd.ToggleFlashResp(flashMode: .on, error: nil)
        drain()

        XCTAssertEqual(display.flashModes, [.on])
    }

    func testToggleFlashRespWithoutModeDoesNothing() {
        actorRef ! RemoteCmd.ToggleFlashResp(flashMode: nil, error: nil)
        drain()

        XCTAssertTrue(display.flashModes.isEmpty)
    }

    // MARK: - Zoom responses

    func testSetZoomRespUpdatesZoom() {
        actorRef ! RemoteCmd.SetZoomResp(
            zoomFactor: 3.0,
            currentLens: nil,
            zoomRange: RemoteCmd.ZoomRange(minZoom: 1.0, maxZoom: 12.0),
            error: nil)
        drain()

        XCTAssertEqual(display.zoomUpdates.count, 1)
        XCTAssertEqual(display.zoomUpdates[0].factor, 3.0, accuracy: 0.001)
        XCTAssertEqual(display.zoomUpdates[0].maxFactor, 12.0, accuracy: 0.001)
    }

    func testSetZoomRespWithoutRangeFallsBackToDisplayMax() {
        actorRef ! RemoteCmd.SetZoomResp(
            zoomFactor: 2.0, currentLens: nil, zoomRange: nil, error: nil)
        drain()

        XCTAssertEqual(display.zoomUpdates.count, 1)
        XCTAssertEqual(display.zoomUpdates[0].maxFactor, display.maxZoomFactor, accuracy: 0.001)
    }

    // MARK: - Lens responses

    func testSwitchLensRespUpdatesLensesAndZoom() {
        actorRef ! RemoteCmd.SwitchLensResp(
            lensType: .telephoto,
            availableLenses: [.wideAngle, .telephoto],
            currentZoom: 2.0,
            zoomRange: RemoteCmd.ZoomRange(minZoom: 1.0, maxZoom: 8.0),
            error: nil)
        drain()

        XCTAssertEqual(display.lensUpdates.count, 1)
        XCTAssertEqual(display.lensUpdates[0].current, .telephoto)
        XCTAssertEqual(display.lensUpdates[0].lenses, [.wideAngle, .telephoto])
        XCTAssertEqual(display.zoomUpdates.count, 1)
        XCTAssertEqual(display.zoomUpdates[0].maxFactor, 8.0, accuracy: 0.001)
    }

    // MARK: - Video transfer progress

    func testVideoTransferMessagesDriveViewModel() {
        actorRef ! UICmd.VideoResourceTransferStarted(
            totalBytes: 1000, resourceName: "video_test.mov", sender: nil)
        drain()
        XCTAssertTrue(display.viewModel.isVideoTransferring)

        actorRef ! UICmd.VideoResourceTransferCompleted(
            resourceName: "video_test.mov", success: true, sender: nil)
        drain()
        XCTAssertFalse(display.viewModel.isVideoTransferring)
    }
}
