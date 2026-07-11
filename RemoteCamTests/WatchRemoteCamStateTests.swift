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
import UIKit
import AVFoundation
import MultipeerConnectivity

@testable import RemoteShutter

class WatchRemoteCamStateTests: XCTestCase {

    private var coordinator: SessionCoordinator!
    private var ctrl: FakeCameraControlling!
    private var pusher: RecordingWatchPusher!
    private var alerts: FakeAlertPresenter!
    private var savedPhotos: [Data] = []

    override func setUp() async throws {
        try await super.setUp()
        coordinator = SessionCoordinator()

        // Watch Remote mode never has a multipeer session — keep it nil so these
        // tests also guard the nil-service crash path in the coordinator's sends.
        ctrl = FakeCameraControlling()
        pusher = RecordingWatchPusher()
        alerts = FakeAlertPresenter()
        savedPhotos = []
        await coordinator.setWatchStatePusher(pusher)
        await coordinator.setAlertPresenter(alerts)
        await coordinator.setPhotoLibrarySaver { [weak self] data in self?.savedPhotos.append(data) }
    }

    override func tearDown() async throws {
        coordinator.stop()
        coordinator = nil
        ctrl = nil
        pusher = nil
        alerts = nil
        try await super.tearDown()
    }

    private func deliver(_ msg: Message) async {
        coordinator.tell(msg)
        await coordinator.waitForIdle()
        await MainActor.run { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02)) }
    }

    private func stateName() async -> RemoteCamState {
        await coordinator.currentStateName()
    }

    private func enterWatchCamera() async {
        await deliver(UICmd.BecomeWatchCamera(ctrl: ctrl))
    }

    private func enterTakingPic() async {
        await enterWatchCamera()
        await deliver(RemoteCmd.TakePic(sender: nil, sendMediaToPeer: false))
    }

    private func enterStartingVideo() async {
        await enterWatchCamera()
        await deliver(RemoteCmd.StartRecordingVideo(sender: nil))
    }

    private func enterRecording() async {
        await enterStartingVideo()
        ctrl.isRecording = true
        await deliver(RemoteCmd.StartRecordingVideoAck(sender: nil, recordingStartTime: Date()))
    }

    // MARK: - Entry

    func testBecomeWatchCameraEntersStateAndPushesState() async {
        await enterWatchCamera()
        let name = await stateName()
        XCTAssertEqual(name, .watchRemoteCamera)
        XCTAssertFalse(pusher.pushedSnapshots.isEmpty, "entry should push initial state")
    }

    // MARK: - Photo capture

    func testTakePicTransitionsToTakingPic() async {
        await enterTakingPic()
        let name = await stateName()
        XCTAssertEqual(name, .watchRemoteCameraTakingPic)
        XCTAssertEqual(ctrl.takePictureCalls, [false], "watch capture must never send media to a peer")
    }

    func testOnPictureSuccessSavesPhotoAndPushesPhotoTaken() async {
        await enterTakingPic()
        let photoBytes = Data([0xCA, 0xFE])
        await deliver(UICmd.OnPicture(sender: nil, pic: photoBytes))

        let name = await stateName()
        XCTAssertEqual(name, .watchRemoteCamera)
        XCTAssertEqual(pusher.lastEvent, .phototaken)
        XCTAssertEqual(savedPhotos, [photoBytes],
                       "the captured photo must be written to the photo library")
    }

    func testOnPictureErrorDoesNotSaveAndPushesPhotoError() async {
        await enterTakingPic()
        await deliver(UICmd.OnPicture(sender: nil, error: NSError(domain: "capture", code: 1)))

        let name = await stateName()
        XCTAssertEqual(name, .watchRemoteCamera)
        XCTAssertEqual(pusher.lastEvent, .photoerror)
        XCTAssertTrue(savedPhotos.isEmpty)
    }

    func testTakingPicTimeoutUnbecomesWithPhotoError() async {
        await enterTakingPic()
        let generation = await coordinator.currentTimeoutGeneration()

        await deliver(UICmd.StateTimeout(stateName: .watchRemoteCameraTakingPic, generation: generation))

        let name = await stateName()
        XCTAssertEqual(name, .watchRemoteCamera)
        XCTAssertEqual(pusher.lastEvent, .photoerror)
    }

    func testTakingPicStaleTimeoutIsIgnored() async {
        await enterTakingPic()
        let generation = await coordinator.currentTimeoutGeneration()

        await deliver(UICmd.StateTimeout(stateName: .watchRemoteCameraTakingPic, generation: generation - 1))

        let name = await stateName()
        XCTAssertEqual(name, .watchRemoteCameraTakingPic,
                       "a stale generation must not abort an in-flight capture")
    }

    func testDuplicateTakePicWhileInFlightIsIgnored() async {
        await enterTakingPic()
        await deliver(RemoteCmd.TakePic(sender: nil, sendMediaToPeer: false))

        let name = await stateName()
        XCTAssertEqual(name, .watchRemoteCameraTakingPic)
        XCTAssertEqual(ctrl.takePictureCalls.count, 1, "double-tap must not trigger a second capture")
    }

    func testZoomDuringCaptureStillApplies() async {
        await enterTakingPic()
        await deliver(RemoteCmd.SetZoom(zoomFactor: 3.0))

        XCTAssertEqual(ctrl.zoomCalls, [3.0])
        let name = await stateName()
        XCTAssertEqual(name, .watchRemoteCameraTakingPic)
    }

    func testStartRecordingDuringCapturePushesBusy() async {
        await enterTakingPic()
        await deliver(RemoteCmd.StartRecordingVideo(sender: nil))

        XCTAssertEqual(pusher.lastEvent, .busy)
        XCTAssertEqual(ctrl.startRecordingCalls, 0)
    }

    func testLateOnPictureInIdleStateSavesAndPushesTruthfulEvent() async {
        await enterWatchCamera()
        let photoBytes = Data([0xBE, 0xEF])
        await deliver(UICmd.OnPicture(sender: nil, pic: photoBytes))

        let name = await stateName()
        XCTAssertEqual(name, .watchRemoteCamera)
        XCTAssertEqual(pusher.lastEvent, .phototaken)
        XCTAssertEqual(savedPhotos, [photoBytes], "a late capture must still be saved")
    }

    // MARK: - Video recording

    func testStartRecordingEntersStartingVideo() async {
        await enterStartingVideo()
        let name = await stateName()
        XCTAssertEqual(name, .watchRemoteCameraStartingVideo)
        XCTAssertEqual(ctrl.startRecordingCalls, 1)
    }

    func testStartAckTransitionsToRecording() async {
        await enterRecording()
        let name = await stateName()
        XCTAssertEqual(name, .watchRemoteCameraRecordingVideo)
        XCTAssertEqual(pusher.lastEvent, .recordingstarted)
    }

    func testStartAckWithErrorReturnsToCameraWithRecordingFailed() async {
        await enterStartingVideo()
        await deliver(RemoteCmd.StartRecordingVideoAck(sender: nil, recordingStartTime: nil,
                                                       error: NSError(domain: "av", code: 1)))

        let name = await stateName()
        XCTAssertEqual(name, .watchRemoteCamera)
        XCTAssertEqual(pusher.lastEvent, .recordingfailed)
    }

    func testMicrophoneDeniedDuringStartReturnsToCamera() async {
        await enterStartingVideo()
        await deliver(UICmd.MicrophoneAccessDenied(error: NSError(domain: "mic", code: 1)))

        let name = await stateName()
        XCTAssertEqual(name, .watchRemoteCamera)
        XCTAssertEqual(pusher.lastEvent, .microphonedenied)
    }

    func testStartingVideoTimeoutCleansUpAndReturnsToCamera() async {
        await enterStartingVideo()
        let generation = await coordinator.currentTimeoutGeneration()

        await deliver(UICmd.StateTimeout(stateName: .watchRemoteCameraStartingVideo, generation: generation))

        let name = await stateName()
        XCTAssertEqual(name, .watchRemoteCamera)
        XCTAssertEqual(pusher.lastEvent, .recordingfailed)
        XCTAssertEqual(ctrl.stopRecordingCalls, [false], "timeout must attempt recorder cleanup")
    }

    func testStopDuringStartingVideoAbortsCleanly() async {
        await enterStartingVideo()
        await deliver(RemoteCmd.StopRecordingVideo(sender: nil))

        let name = await stateName()
        XCTAssertEqual(name, .watchRemoteCamera)
        XCTAssertEqual(ctrl.stopRecordingCalls, [false])
    }

    func testStopRecordingCompletesOnResp() async {
        await enterRecording()
        await deliver(RemoteCmd.StopRecordingVideo(sender: nil))
        XCTAssertEqual(ctrl.stopRecordingCalls, [false])

        ctrl.isRecording = false
        await deliver(RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: nil))

        let name = await stateName()
        XCTAssertEqual(name, .watchRemoteCamera)
        XCTAssertEqual(pusher.lastEvent, .recordingstopped)
    }

    func testStopRecordingTimeoutUnwedgesState() async {
        await enterRecording()
        await deliver(RemoteCmd.StopRecordingVideo(sender: nil))
        let generation = await coordinator.currentTimeoutGeneration()

        await deliver(UICmd.StateTimeout(stateName: .watchRemoteCameraRecordingVideo, generation: generation))

        let name = await stateName()
        XCTAssertEqual(name, .watchRemoteCamera)
        XCTAssertEqual(pusher.lastEvent, .recordingfailed)
    }

    func testRecordingHasNoBlanketTimeout() async {
        await enterRecording()
        // A timeout that wasn't armed by a stop request must not kill the recording.
        let generation = await coordinator.currentTimeoutGeneration()
        await deliver(UICmd.StateTimeout(stateName: .watchRemoteCameraRecordingVideo,
                                         generation: generation + 100))

        let name = await stateName()
        XCTAssertEqual(name, .watchRemoteCameraRecordingVideo)
    }

    func testTakePicDuringRecordingPushesBusyRecording() async {
        await enterRecording()
        await deliver(RemoteCmd.TakePic(sender: nil, sendMediaToPeer: false))

        XCTAssertEqual(pusher.lastEvent, .busyrecording)
        XCTAssertTrue(ctrl.takePictureCalls.isEmpty)
        let name = await stateName()
        XCTAssertEqual(name, .watchRemoteCameraRecordingVideo)
    }

    func testZoomAndTorchKeepWorkingDuringRecording() async {
        await enterRecording()
        await deliver(RemoteCmd.SetZoom(zoomFactor: 2.0))
        await deliver(RemoteCmd.ToggleTorch())

        XCTAssertEqual(ctrl.zoomCalls, [2.0])
        XCTAssertEqual(ctrl.torchToggles, 1)
        let name = await stateName()
        XCTAssertEqual(name, .watchRemoteCameraRecordingVideo)
    }

    // MARK: - Exit from sub-states

    func testUnbecomeWatchCameraFromTakingPicPopsToRoot() async {
        await enterTakingPic()
        await deliver(UICmd.UnbecomeWatchCamera())

        // (Was `nil` for Theater's emptied stack — the enum floor maps to .idle.)
        let name = await stateName()
        XCTAssertEqual(name, .idle)
        XCTAssertEqual(pusher.disconnectedPushes, 1)
    }

    func testUnbecomeWatchCameraDuringRecordingStopsRecorder() async {
        await enterRecording()
        await deliver(UICmd.UnbecomeWatchCamera())

        let name = await stateName()
        XCTAssertEqual(name, .idle)
        XCTAssertEqual(ctrl.stopRecordingCalls, [false])
        XCTAssertEqual(pusher.disconnectedPushes, 1)
    }

    // MARK: - Photo/Video mode switching

    func testSetModeSwitchesToVideoAndPushesState() async {
        await enterWatchCamera()
        await deliver(UICmd.SetWatchCameraMode(mode: .Video))

        XCTAssertEqual(ctrl.currentCameraMode, .Video)
        XCTAssertEqual(pusher.pushedSnapshots.last?.currentMode, .video)
        var name = await stateName()
        XCTAssertEqual(name, .watchRemoteCamera)

        await deliver(UICmd.SetWatchCameraMode(mode: .Photo))

        XCTAssertEqual(ctrl.currentCameraMode, .Photo)
        XCTAssertEqual(pusher.pushedSnapshots.last?.currentMode, .photo)
        name = await stateName()
        XCTAssertEqual(name, .watchRemoteCamera)
    }

    func testSetModeDuringCaptureIsRejectedAsBusy() async {
        await enterTakingPic()
        await deliver(UICmd.SetWatchCameraMode(mode: .Video))

        XCTAssertEqual(ctrl.currentCameraMode, .Photo, "mode must not change mid-capture")
        XCTAssertEqual(pusher.lastEvent, .busy)
        let name = await stateName()
        XCTAssertEqual(name, .watchRemoteCameraTakingPic)
    }

    func testSetModeDuringRecordingIsRejectedAsBusy() async {
        await enterRecording()
        ctrl.currentCameraMode = .Video
        await deliver(UICmd.SetWatchCameraMode(mode: .Photo))

        XCTAssertEqual(ctrl.currentCameraMode, .Video, "mode must not change while recording")
        XCTAssertEqual(pusher.lastEvent, .busyrecording)
        let name = await stateName()
        XCTAssertEqual(name, .watchRemoteCameraRecordingVideo)
    }

    // MARK: - Timer countdown plumbing

    func testTimerCountdownIsCarriedAsSnapshotState() async {
        await enterWatchCamera()
        await deliver(RemoteCmd.TimerCountdown(value: 3))
        await deliver(RemoteCmd.TimerCountdown(value: 2))
        await deliver(RemoteCmd.TimerCountdown(value: 0))

        XCTAssertEqual(ctrl.countdownTicks, [3, 2, 0])
        // Ticks travel as snapshot state, never as events.
        XCTAssertTrue(pusher.allEvents.isEmpty)
        let countdowns = pusher.pushedSnapshots.map(\.countdownRemainingSecs)
        XCTAssertTrue(countdowns.contains(3))
        XCTAssertTrue(countdowns.contains(2))
        let name = await stateName()
        XCTAssertEqual(name, .watchRemoteCamera)

        // The fire tick must push a countdown-free snapshot: without it the
        // Watch (and the latest-wins context mirror) keeps showing the last tick.
        let last = pusher.pushedSnapshots.last
        XCTAssertEqual(last?.countdownRemainingSecs, 0)
        XCTAssertNil(last?.activeCountdownSeconds)
    }

    func testTimerCancelDrivesPhoneUIAndPushesCountdownFreeSnapshot() async {
        await enterWatchCamera()
        await deliver(RemoteCmd.TimerCountdown(value: 2))
        await deliver(RemoteCmd.TimerCountdown(value: -1))

        XCTAssertEqual(ctrl.countdownTicks, [2, -1],
                       "cancel must tear down the on-phone countdown overlay")
        let last = pusher.pushedSnapshots.last
        XCTAssertNotNil(last, "cancel must push state so the context mirror can't hold a dead countdown")
        XCTAssertEqual(last?.countdownRemainingSecs, 0)
        XCTAssertNil(last?.activeCountdownSeconds)
        let name = await stateName()
        XCTAssertEqual(name, .watchRemoteCamera)
    }

    /// Any push that interleaves with a live countdown (zoom, toggles, capability
    /// refresh) must carry the countdown — it's snapshot state, so no push can
    /// accidentally "clear" it on the Watch.
    func testPushesDuringCountdownCarryTheCountdown() async {
        await enterWatchCamera()
        await deliver(RemoteCmd.TimerCountdown(value: 5))
        await deliver(RemoteCmd.SetZoom(zoomFactor: 2.0))
        await deliver(RemoteCmd.RequestCameraCapabilities())

        let afterTick = pusher.pushedSnapshots.suffix(2)
        XCTAssertEqual(afterTick.count, 2)
        XCTAssertTrue(afterTick.allSatisfy { $0.countdownRemainingSecs == 5 },
                      "interleaved pushes must not drop a live countdown")
        XCTAssertTrue(afterTick.allSatisfy { $0.activeCountdownSeconds == 5 })
    }

    // MARK: - Snapshot truthfulness

    func testSnapshotReportsFlashFromController() async {
        ctrl.flashMode = .auto
        let snapshot = await SessionCoordinator.watchStateSnapshot(ctrl: ctrl)
        XCTAssertTrue(snapshot.isFlashEnabled, "auto flash must surface as enabled on the Watch")

        ctrl.flashMode = .off
        let offSnapshot = await SessionCoordinator.watchStateSnapshot(ctrl: ctrl)
        XCTAssertFalse(offSnapshot.isFlashEnabled)
    }

    func testSnapshotReportsTorchAndRecordingState() async {
        ctrl.torchActive = true
        ctrl.isRecording = true
        ctrl.currentCameraMode = .Video
        let snapshot = await SessionCoordinator.watchStateSnapshot(ctrl: ctrl, event: .recordingstarted)
        XCTAssertTrue(snapshot.isTorchEnabled)
        XCTAssertTrue(snapshot.isRecording)
        XCTAssertEqual(snapshot.currentMode, .video)
        XCTAssertEqual(snapshot.event, .recordingstarted)
    }

    // MARK: - Readiness (backgrounded / locked phone)

    func testSnapshotReadyWhenForegrounded() async {
        let snapshot = await SessionCoordinator.watchStateSnapshot(ctrl: ctrl, event: .phototaken, isBackgrounded: false)
        XCTAssertEqual(snapshot.readiness, .ready)
        XCTAssertEqual(snapshot.event, .phototaken, "transient event passes through while foregrounded")
    }

    func testSnapshotNotReadyWhenBackgrounded() async {
        let snapshot = await SessionCoordinator.watchStateSnapshot(ctrl: ctrl, event: .phototaken,
                                                                   isBackgrounded: true, countdownRemaining: 3)
        XCTAssertEqual(snapshot.readiness, .phonebackgrounded,
                       "a backgrounded/locked phone can't capture")
        XCTAssertEqual(snapshot.event, .unknown,
                       "the not-ready verdict suppresses any in-flight transient event")
        XCTAssertEqual(snapshot.countdownRemainingSecs, 0,
                       "the countdown timer is suspended with the app — don't report it live")
    }

    /// The regression this whole change targets: whichever push path runs while the
    /// phone is backgrounded, the snapshot must report not-ready — so a stale "ready"
    /// push can never race ahead and hide the Watch's "app closed" screen.
    func testBackgroundedPhoneAlwaysPushesNotReady() async {
        await coordinator.setIsPhoneBackgrounded { true }
        await enterWatchCamera()

        // A capabilities request is exactly the push that used to win the race with isReady=true.
        await deliver(RemoteCmd.RequestCameraCapabilities())

        let pushes = pusher.pushedSnapshots
        XCTAssertFalse(pushes.isEmpty)
        XCTAssertTrue(pushes.allSatisfy { !$0.isReady },
                      "no push may claim ready while the phone is backgrounded")
        XCTAssertEqual(pushes.last?.readiness, .phonebackgrounded)
    }
}

// MARK: - AppActivityMonitor (lifecycle → readiness flag wiring)

final class AppActivityMonitorTests: XCTestCase {

    /// Drives the monitor with a private NotificationCenter so posts don't touch the
    /// real app lifecycle. Observers register with `queue: nil`, so posting on the test
    /// thread runs them synchronously — assertions can follow each post directly.
    func testTracksLifecycleTransitionsAndNotifies() {
        let center = NotificationCenter()
        let monitor = AppActivityMonitor()
        var changeCount = 0
        monitor.onChange = { changeCount += 1 }
        monitor.startObserving(notificationCenter: center)

        XCTAssertFalse(monitor.isBackgrounded, "starts foregrounded")

        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertTrue(monitor.isBackgrounded, "backgrounding sets the flag")

        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        XCTAssertFalse(monitor.isBackgrounded, "foregrounding clears the flag")

        XCTAssertEqual(changeCount, 2, "each transition notifies the re-push trigger")
    }

    /// onChange must fire *after* the flag is updated, so the re-push it triggers
    /// always reads the new value (this ordering is what killed the original race).
    func testOnChangeSeesUpdatedFlag() {
        let center = NotificationCenter()
        let monitor = AppActivityMonitor()
        var observedDuringCallback: Bool?
        monitor.onChange = { observedDuringCallback = monitor.isBackgrounded }
        monitor.startObserving(notificationCenter: center)

        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertEqual(observedDuringCallback, true,
                       "onChange runs after the flag flips, never before")
    }

    func testStartObservingIsIdempotent() {
        let center = NotificationCenter()
        let monitor = AppActivityMonitor()
        var changeCount = 0
        monitor.onChange = { changeCount += 1 }
        monitor.startObserving(notificationCenter: center)
        monitor.startObserving(notificationCenter: center)   // second call must not double-register

        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertEqual(changeCount, 1, "a single transition fires onChange exactly once")
    }
}
