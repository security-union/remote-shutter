//
//  WatchRemoteCamStateTests.swift
//  RemoteShutterTests
//
//  State machine tests for the Watch Remote camera states. Uses a fake
//  camera controller and a fake state pusher so transitions, timeouts and
//  busy/duplicate handling can be exercised without AVFoundation or
//  WatchConnectivity.
//

import XCTest
import AVFoundation
import MultipeerConnectivity

@testable import RemoteShutter

// MARK: - Fakes

final class FakeWatchCameraController: WatchCameraControlling {
    var currentCameraMode: RecordingMode = .Photo
    var isRecording = false
    var isTorchActive = false
    var currentFlashMode: AVCaptureDevice.FlashMode = .off

    var takePictureCalls: [Bool] = []
    var startRecordingCalls = 0
    var stopRecordingCalls: [Bool] = []
    var gatherCapabilitiesCalls = 0
    var zoomCalls: [CGFloat] = []
    var lensSwitches: [CameraLensType] = []
    var torchToggles = 0

    func updateCameraStatus() {}
    func takePicture(_ sendMediaToRemote: Bool) { takePictureCalls.append(sendMediaToRemote) }
    func startRecordingVideo() { startRecordingCalls += 1 }
    func stopRecordingVideo(_ shouldSendVideo: Bool) { stopRecordingCalls.append(shouldSendVideo) }
    func setZoom(zoomFactor: CGFloat) -> Try<(CGFloat, CameraLensType, RemoteCmd.ZoomRange)> {
        zoomCalls.append(zoomFactor)
        return Success((zoomFactor, .wideAngle, RemoteCmd.ZoomRange(minZoom: 1, maxZoom: 10)))
    }
    func switchLens(to lensType: CameraLensType) -> Try<(CameraLensType, [CameraLensType], CGFloat, RemoteCmd.ZoomRange)> {
        lensSwitches.append(lensType)
        return Success((lensType, [.wideAngle], 1.0, RemoteCmd.ZoomRange(minZoom: 1, maxZoom: 10)))
    }
    func toggleFlash() -> Try<AVCaptureDevice.FlashMode> {
        currentFlashMode = currentFlashMode == .off ? .on : .off
        return Success(currentFlashMode)
    }
    func toggleTorch() -> Try<AVCaptureDevice.TorchMode> {
        torchToggles += 1
        isTorchActive.toggle()
        return Success(isTorchActive ? .on : .off)
    }
    func toggleCamera() -> Try<(AVCaptureDevice.FlashMode?, AVCaptureDevice.Position)> {
        return Success((currentFlashMode, .back))
    }
    func gatherAllCameraCapabilities() { gatherCapabilitiesCalls += 1 }

    func getCurrentZoomFactor() -> CGFloat { zoomCalls.last ?? 1.0 }
    func getMinZoomFactor() -> CGFloat { 1.0 }
    func getMaxZoomFactor() -> CGFloat { 10.0 }
    func getCurrentLensType() -> CameraLensType { .wideAngle }
    func getAvailableLensTypes() -> [CameraLensType] { [.wideAngle] }
    func getZoomStops() -> [CGFloat] { [1.0, 2.0] }
    func getWideAngleZoomFactor() -> CGFloat { 1.0 }

    var countdownTicks: [Int] = []
    func updateTimerCountdown(value: Int) { countdownTicks.append(value) }
}

final class FakeWatchStatePusher: WatchStatePushing {
    var pushedSnapshots: [WatchCameraStateSnapshot] = []
    var notReadyReasons: [String] = []
    var disconnectedPushes = 0

    var lastEvent: String? { pushedSnapshots.last(where: { $0.lastEvent != nil })?.lastEvent }
    var allEvents: [String] { pushedSnapshots.compactMap { $0.lastEvent } }

    func pushCameraState(_ snapshot: WatchCameraStateSnapshot) { pushedSnapshots.append(snapshot) }
    func pushNotReady(reason: String) { notReadyReasons.append(reason) }
    func pushDisconnectedState() { disconnectedPushes += 1 }
}

// MARK: - Tests

class WatchRemoteCamStateTests: XCTestCase {

    private var system: TestActorSystem!
    private var ref: ActorRef!
    private var session: TestableRemoteCamSession!
    private var ctrl: FakeWatchCameraController!
    private var pusher: FakeWatchStatePusher!
    private var savedPhotos: [Data] = []

    override func setUp() {
        super.setUp()
        system = TestActorSystem(name: "watch-test")
        ref = system.actorOf(clz: TestableRemoteCamSession.self, name: "watch-session")
        session = (system.actorForRef(ref: ref!) as! TestableRemoteCamSession)

        // Watch Remote mode never has a multipeer session — keep it nil so these
        // tests also guard the nil-service crash fixed in RemoteCamSession.sendMessage.
        session.multipeerService = nil

        ctrl = FakeWatchCameraController()
        pusher = FakeWatchStatePusher()
        session.watchStatePusher = pusher
        savedPhotos = []
        session.photoLibrarySaver = { [weak self] data in self?.savedPhotos.append(data) }

        waitForMailbox(session, test: self)
    }

    override func tearDown() {
        drainMailbox()
        system.stop()
        drainMailbox()
        system = nil
        ref = nil
        session = nil
        ctrl = nil
        pusher = nil
        super.tearDown()
    }

    private func drainMailbox() {
        let deadline = Date(timeIntervalSinceNow: 5.0)
        while session.mailbox.operationCount > 0 && Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }

    private func enterWatchCamera() {
        ref ! UICmd.BecomeWatchCamera(ctrl: ctrl)
        // Twice: become() enqueues OnEnter while the first message is being
        // processed, i.e. behind the first drain marker.
        waitForMailbox(session, test: self)
        waitForMailbox(session, test: self)
    }

    private func enterTakingPic() {
        enterWatchCamera()
        ref ! RemoteCmd.TakePic(sender: nil, sendMediaToPeer: false)
        waitForMailbox(session, test: self)
    }

    private func enterStartingVideo() {
        enterWatchCamera()
        ref ! RemoteCmd.StartRecordingVideo(sender: nil)
        waitForMailbox(session, test: self)
    }

    private func enterRecording() {
        enterStartingVideo()
        ctrl.isRecording = true
        ref ! RemoteCmd.StartRecordingVideoAck(sender: nil, recordingStartTime: Date())
        waitForMailbox(session, test: self)
    }

    // MARK: - Entry

    func testBecomeWatchCameraEntersStateAndPushesState() {
        enterWatchCamera()
        XCTAssertEqual(session.currentStateName(), .watchRemoteCamera)
        XCTAssertFalse(pusher.pushedSnapshots.isEmpty, "OnEnter should push initial state")
    }

    // MARK: - Photo capture

    func testTakePicTransitionsToTakingPic() {
        enterTakingPic()
        XCTAssertEqual(session.currentStateName(), .watchRemoteCameraTakingPic)
        XCTAssertEqual(ctrl.takePictureCalls, [false], "watch capture must never send media to a peer")
    }

    func testOnPictureSuccessSavesPhotoAndPushesPhotoTaken() {
        enterTakingPic()
        let photoBytes = Data([0xCA, 0xFE])
        ref ! UICmd.OnPicture(sender: nil, pic: photoBytes)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .watchRemoteCamera)
        XCTAssertEqual(pusher.lastEvent, "photoTaken")
        XCTAssertEqual(savedPhotos, [photoBytes],
                       "the captured photo must be written to the photo library")
    }

    func testOnPictureErrorDoesNotSaveAndPushesPhotoError() {
        enterTakingPic()
        ref ! UICmd.OnPicture(sender: nil, error: NSError(domain: "capture", code: 1))
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .watchRemoteCamera)
        XCTAssertEqual(pusher.lastEvent, "photoError")
        XCTAssertTrue(savedPhotos.isEmpty)
    }

    func testTakingPicTimeoutUnbecomesWithPhotoError() {
        enterTakingPic()
        let gen = session._timeoutGeneration

        ref ! UICmd.StateTimeout(stateName: .watchRemoteCameraTakingPic, generation: gen)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .watchRemoteCamera)
        XCTAssertEqual(pusher.lastEvent, "photoError")
    }

    func testTakingPicStaleTimeoutIsIgnored() {
        enterTakingPic()
        let gen = session._timeoutGeneration

        ref ! UICmd.StateTimeout(stateName: .watchRemoteCameraTakingPic, generation: gen - 1)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .watchRemoteCameraTakingPic,
                       "a stale generation must not abort an in-flight capture")
    }

    func testDuplicateTakePicWhileInFlightIsIgnored() {
        enterTakingPic()
        ref ! RemoteCmd.TakePic(sender: nil, sendMediaToPeer: false)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .watchRemoteCameraTakingPic)
        XCTAssertEqual(ctrl.takePictureCalls.count, 1, "double-tap must not trigger a second capture")
    }

    func testZoomDuringCaptureStillApplies() {
        enterTakingPic()
        ref ! RemoteCmd.SetZoom(zoomFactor: 3.0)
        waitForMailbox(session, test: self)

        XCTAssertEqual(ctrl.zoomCalls, [3.0])
        XCTAssertEqual(session.currentStateName(), .watchRemoteCameraTakingPic)
    }

    func testStartRecordingDuringCapturePushesBusy() {
        enterTakingPic()
        ref ! RemoteCmd.StartRecordingVideo(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(pusher.lastEvent, "busy")
        XCTAssertEqual(ctrl.startRecordingCalls, 0)
    }

    func testLateOnPictureInIdleStateSavesAndPushesTruthfulEvent() {
        enterWatchCamera()
        let photoBytes = Data([0xBE, 0xEF])
        ref ! UICmd.OnPicture(sender: nil, pic: photoBytes)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .watchRemoteCamera)
        XCTAssertEqual(pusher.lastEvent, "photoTaken")
        XCTAssertEqual(savedPhotos, [photoBytes], "a late capture must still be saved")
    }

    // MARK: - Video recording

    func testStartRecordingEntersStartingVideo() {
        enterStartingVideo()
        XCTAssertEqual(session.currentStateName(), .watchRemoteCameraStartingVideo)
        XCTAssertEqual(ctrl.startRecordingCalls, 1)
    }

    func testStartAckTransitionsToRecording() {
        enterRecording()
        XCTAssertEqual(session.currentStateName(), .watchRemoteCameraRecordingVideo)
        XCTAssertEqual(pusher.lastEvent, "recordingStarted")
    }

    func testStartAckWithErrorReturnsToCameraWithRecordingFailed() {
        enterStartingVideo()
        ref ! RemoteCmd.StartRecordingVideoAck(sender: nil, recordingStartTime: nil,
                                               error: NSError(domain: "av", code: 1))
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .watchRemoteCamera)
        XCTAssertEqual(pusher.lastEvent, "recordingFailed")
    }

    func testMicrophoneDeniedDuringStartReturnsToCamera() {
        enterStartingVideo()
        ref ! UICmd.MicrophoneAccessDenied(error: NSError(domain: "mic", code: 1))
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .watchRemoteCamera)
        XCTAssertEqual(pusher.lastEvent, "microphoneDenied")
    }

    func testStartingVideoTimeoutCleansUpAndReturnsToCamera() {
        enterStartingVideo()
        let gen = session._timeoutGeneration

        ref ! UICmd.StateTimeout(stateName: .watchRemoteCameraStartingVideo, generation: gen)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .watchRemoteCamera)
        XCTAssertEqual(pusher.lastEvent, "recordingFailed")
        XCTAssertEqual(ctrl.stopRecordingCalls, [false], "timeout must attempt recorder cleanup")
    }

    func testStopDuringStartingVideoAbortsCleanly() {
        enterStartingVideo()
        ref ! RemoteCmd.StopRecordingVideo(sender: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .watchRemoteCamera)
        XCTAssertEqual(ctrl.stopRecordingCalls, [false])
    }

    func testStopRecordingCompletesOnResp() {
        enterRecording()
        ref ! RemoteCmd.StopRecordingVideo(sender: nil)
        waitForMailbox(session, test: self)
        XCTAssertEqual(ctrl.stopRecordingCalls, [false])

        ctrl.isRecording = false
        ref ! RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: nil)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .watchRemoteCamera)
        XCTAssertEqual(pusher.lastEvent, "recordingStopped")
    }

    func testStopRecordingTimeoutUnwedgesState() {
        enterRecording()
        ref ! RemoteCmd.StopRecordingVideo(sender: nil)
        waitForMailbox(session, test: self)
        let gen = session._timeoutGeneration

        ref ! UICmd.StateTimeout(stateName: .watchRemoteCameraRecordingVideo, generation: gen)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .watchRemoteCamera)
        XCTAssertEqual(pusher.lastEvent, "recordingFailed")
    }

    func testRecordingHasNoBlanketTimeout() {
        enterRecording()
        // A timeout that wasn't armed by a stop request must not kill the recording.
        ref ! UICmd.StateTimeout(stateName: .watchRemoteCameraRecordingVideo,
                                 generation: session._timeoutGeneration + 100)
        waitForMailbox(session, test: self)

        XCTAssertEqual(session.currentStateName(), .watchRemoteCameraRecordingVideo)
    }

    func testTakePicDuringRecordingPushesBusyRecording() {
        enterRecording()
        ref ! RemoteCmd.TakePic(sender: nil, sendMediaToPeer: false)
        waitForMailbox(session, test: self)

        XCTAssertEqual(pusher.lastEvent, "busyRecording")
        XCTAssertTrue(ctrl.takePictureCalls.isEmpty)
        XCTAssertEqual(session.currentStateName(), .watchRemoteCameraRecordingVideo)
    }

    func testZoomAndTorchKeepWorkingDuringRecording() {
        enterRecording()
        ref ! RemoteCmd.SetZoom(zoomFactor: 2.0)
        ref ! RemoteCmd.ToggleTorch()
        waitForMailbox(session, test: self)

        XCTAssertEqual(ctrl.zoomCalls, [2.0])
        XCTAssertEqual(ctrl.torchToggles, 1)
        XCTAssertEqual(session.currentStateName(), .watchRemoteCameraRecordingVideo)
    }

    // MARK: - Exit from sub-states

    func testUnbecomeWatchCameraFromTakingPicPopsToRoot() {
        enterTakingPic()
        ref ! UICmd.UnbecomeWatchCamera()
        waitForMailbox(session, test: self)

        XCTAssertNil(session.currentStateName())
        XCTAssertEqual(pusher.disconnectedPushes, 1)
    }

    func testUnbecomeWatchCameraDuringRecordingStopsRecorder() {
        enterRecording()
        ref ! UICmd.UnbecomeWatchCamera()
        waitForMailbox(session, test: self)

        XCTAssertNil(session.currentStateName())
        XCTAssertEqual(ctrl.stopRecordingCalls, [false])
        XCTAssertEqual(pusher.disconnectedPushes, 1)
    }

    // MARK: - Photo/Video mode switching

    func testSetModeSwitchesToVideoAndPushesState() {
        enterWatchCamera()
        ref ! UICmd.SetWatchCameraMode(mode: .Video)
        waitForMailbox(session, test: self)

        XCTAssertEqual(ctrl.currentCameraMode, .Video)
        XCTAssertEqual(pusher.pushedSnapshots.last?.currentMode, .video)
        XCTAssertEqual(session.currentStateName(), .watchRemoteCamera)

        ref ! UICmd.SetWatchCameraMode(mode: .Photo)
        waitForMailbox(session, test: self)

        XCTAssertEqual(ctrl.currentCameraMode, .Photo)
        XCTAssertEqual(pusher.pushedSnapshots.last?.currentMode, .photo)
    }

    func testSetModeDuringCaptureIsRejectedAsBusy() {
        enterTakingPic()
        ref ! UICmd.SetWatchCameraMode(mode: .Video)
        waitForMailbox(session, test: self)

        XCTAssertEqual(ctrl.currentCameraMode, .Photo, "mode must not change mid-capture")
        XCTAssertEqual(pusher.lastEvent, "busy")
        XCTAssertEqual(session.currentStateName(), .watchRemoteCameraTakingPic)
    }

    func testSetModeDuringRecordingIsRejectedAsBusy() {
        enterRecording()
        ref ! UICmd.SetWatchCameraMode(mode: .Photo)
        waitForMailbox(session, test: self)

        XCTAssertEqual(ctrl.currentCameraMode, .Video, "mode must not change while recording")
        XCTAssertEqual(pusher.lastEvent, "busyRecording")
        XCTAssertEqual(session.currentStateName(), .watchRemoteCameraRecordingVideo)
    }

    // MARK: - Timer countdown plumbing

    func testTimerCountdownDrivesPhoneUIAndWatchEvents() {
        enterWatchCamera()
        ref ! RemoteCmd.TimerCountdown(value: 3)
        ref ! RemoteCmd.TimerCountdown(value: 2)
        ref ! RemoteCmd.TimerCountdown(value: 0)
        waitForMailbox(session, test: self)

        XCTAssertEqual(ctrl.countdownTicks, [3, 2, 0])
        XCTAssertTrue(pusher.allEvents.contains("countdown:3"))
        XCTAssertTrue(pusher.allEvents.contains("countdown:2"))
        XCTAssertFalse(pusher.allEvents.contains("countdown:0"),
                       "the fire tick is not an event — the capture event follows")
        XCTAssertEqual(session.currentStateName(), .watchRemoteCamera)
    }

    // MARK: - Snapshot truthfulness

    func testSnapshotReportsFlashFromController() {
        ctrl.currentFlashMode = .auto
        let snapshot = RemoteCamSession.watchStateSnapshot(ctrl: ctrl)
        XCTAssertTrue(snapshot.isFlashEnabled, "auto flash must surface as enabled on the Watch")

        ctrl.currentFlashMode = .off
        XCTAssertFalse(RemoteCamSession.watchStateSnapshot(ctrl: ctrl).isFlashEnabled)
    }

    func testSnapshotReportsTorchAndRecordingState() {
        ctrl.isTorchActive = true
        ctrl.isRecording = true
        ctrl.currentCameraMode = .Video
        let snapshot = RemoteCamSession.watchStateSnapshot(ctrl: ctrl, event: "x")
        XCTAssertTrue(snapshot.isTorchEnabled)
        XCTAssertTrue(snapshot.isRecording)
        XCTAssertEqual(snapshot.currentMode, .video)
        XCTAssertEqual(snapshot.lastEvent, "x")
    }
}
