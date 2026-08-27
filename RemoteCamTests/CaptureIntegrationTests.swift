//
//  CaptureIntegrationTests.swift
//  RemoteShutterTests
//
//  Drives the REAL camera stack — CameraRig, watchdog included — against the
//  machine's physical cameras. The product invariant under test is not
//  "every device delivers frames" (a Mac always has junk virtual cameras and
//  suspended built-ins that enumerate but never deliver); it is:
//
//      frames are flowing within a bounded time after every action,
//      no matter which device was picked — via fallback if necessary.
//
//  Skips itself where no camera exists (iOS simulator, CI). Run for real:
//    xcodebuild test -workspace RemoteShutter.xcworkspace -scheme RemoteCam \
//      -destination 'platform=macOS,variant=Mac Catalyst' \
//      -only-testing:RemoteShutterTests/CaptureIntegrationTests
//

import XCTest
import AVFoundation

@testable import RemoteShutter

final class CaptureIntegrationTests: XCTestCase {

    /// Worst case: junk initial device (5s watchdog) + fallback attach
    /// (Continuity Camera needs ~3s wireless attach).
    private static let framesDeadline: TimeInterval = 15

    private var rig: CameraRig!
    #if targetEnvironment(macCatalyst)
    private var savedPreferredCamera: AVCaptureDevice?
    #endif

    override func setUp() async throws {
        try await super.setUp()
        try Self.skipIfHeadless()
        #if targetEnvironment(macCatalyst)
        if #available(macCatalyst 17.0, *) {
            // selectCameraDevice writes the SYSTEM-WIDE preference (Apple's
            // manual mode) — save it so tests don't repoint FaceTime et al.
            savedPreferredCamera = AVCaptureDevice.userPreferredCamera
        }
        #endif
    }

    override func tearDown() async throws {
        rig?.stopSession()
        rig = nil
        #if targetEnvironment(macCatalyst)
        if #available(macCatalyst 17.0, *) {
            AVCaptureDevice.userPreferredCamera = savedPreferredCamera
        }
        #endif
        try await super.tearDown()
    }

    /// Skips the whole suite before ANY AVFoundation call on machines that
    /// cannot answer a TCC prompt. `requestAccess(for: .video)` on a fresh
    /// headless runner posts a prompt no one can click — the await never
    /// resumes and the CI job hangs forever (run 29173204289). The skip must
    /// therefore happen up front, not after probing the camera.
    /// GitHub Actions sets `CI=true`; ios-ci.yml forwards it to the test
    /// process as `TEST_RUNNER_CI` (xcodebuild strips the prefix). Local
    /// interactive runs keep the real TCC prompt.
    private static func skipIfHeadless() throws {
        if ProcessInfo.processInfo.environment["CI"] != nil {
            throw XCTSkip("headless CI — no camera, and a TCC prompt could never be answered")
        }
        #if targetEnvironment(simulator)
        throw XCTSkip("iOS simulator has no cameras")
        #endif
    }

    /// Timestamp source the rig's own watchdog uses.
    private var lastFrameAt: TimeInterval {
        rig.streamingCoordinator.lastVideoFrameAt.value
    }

    /// Waits until a frame newer than `since` arrives. Suspends (never
    /// spins): the rig's completion and fallback paths hop through the main
    /// queue, which cannot drain while a main-actor test is busy-waiting.
    private func waitForFrames(since: TimeInterval,
                               timeout: TimeInterval = CaptureIntegrationTests.framesDeadline) async -> TimeInterval? {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if lastFrameAt > since { return Date().timeIntervalSince(start) }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return nil
    }

    /// Builds the real rig and starts the camera as the camera screen does,
    /// or skips (simulator/CI have no cameras; TCC denied means this
    /// environment can't run it).
    @MainActor
    private func startRealRig() async throws {
        var status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            status = await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
        }
        guard status == .authorized else {
            throw XCTSkip("no camera permission in this environment")
        }

        rig = CameraRig(session: SessionCoordinator(), frameSender: FrameSender())
        rig.startCameraOnce()

        // Wait for the engine to finish configuration (isBusy clears via a
        // main-queue hop — suspend, don't spin, or it can never land).
        let deadline = Date().addingTimeInterval(10)
        while rig.cameraViewModel.isBusy && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard rig.cameraViewModel.previewSession != nil else {
            throw XCTSkip("no camera on this machine (simulator/CI)")
        }
        let initial = await rig.currentCameraDevice()
        var preferred = "n/a"
        #if targetEnvironment(macCatalyst)
        if #available(macCatalyst 17.0, *) {
            preferred = AVCaptureDevice.systemPreferredCamera?.localizedName ?? "nil"
        }
        #endif
        print("📸 startup: initial=\(initial?.localizedName ?? "none") systemPreferred=\(preferred)")
    }

    /// Session-state dump for failures — the difference between "device never
    /// delivered" and "session isn't even running" is the whole diagnosis.
    private func diagnostics() async -> String {
        let session = rig.engine.captureSession
        let device = await rig.currentCameraDevice()
        return "isRunning=\(session.isRunning) interrupted=\(session.isInterrupted) "
            + "inputs=\(session.inputs.count) outputs=\(session.outputs.count) "
            + "active=\(device?.localizedName ?? "none") suspended=\(device?.isSuspended ?? false) "
            + "lastFrameAt=\(lastFrameAt)"
    }

    func testCameraStartsAndFramesFlowWithinDeadline() async throws {
        try await startRealRig()

        guard let latency = await waitForFrames(since: 0) else {
            return XCTFail("no frames within \(Self.framesDeadline)s — \(await diagnostics())")
        }
        let device = await rig.currentCameraDevice()
        print("📸 startup: frames from \(device?.localizedName ?? "?") in \(Int(latency * 1000))ms")
    }

    /// Selecting ANY healthy-looking device must end with frames flowing —
    /// from that device, or from the watchdog's fallback if it turned out to
    /// be a zero-frame source (suspended, sandboxed-out virtual camera).
    func testEverySelectionEndsWithFramesFlowing() async throws {
        try await startRealRig()
        guard await waitForFrames(since: 0) != nil else {
            return XCTFail("startup never delivered frames — \(await diagnostics())")
        }

        let candidates = await rig.availableCameraDevices().filter { !$0.isSuspended }
        print("📸 candidates: \(candidates.map(\.localizedName))")

        for device in candidates {
            let mark = Date().timeIntervalSinceReferenceDate
            _ = try? await rig.selectCameraDevice(uniqueID: device.uniqueID)

            guard let latency = await waitForFrames(since: mark) else {
                let active = await rig.currentCameraDevice()
                return XCTFail("selected \(device.localizedName): no frames within \(Self.framesDeadline)s (active: \(active?.localizedName ?? "none"))")
            }
            let active = await rig.currentCameraDevice()
            let outcome = active?.uniqueID == device.uniqueID
                ? "delivers" : "fell back to \(active?.localizedName ?? "?")"
            print("📸 \(device.localizedName): \(outcome), frames in \(Int(latency * 1000))ms")
        }
    }

    // MARK: - Recording

    /// Counts audio sample buffers straight off the capture stack.
    private final class AudioProbe: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
        let samples = Locked(0)
        func captureOutput(_ output: AVCaptureOutput,
                           didOutput sampleBuffer: CMSampleBuffer,
                           from connection: AVCaptureConnection) {
            samples.mutate { $0 += 1 }
        }
    }

    /// A missing mic TCC grant produces "no audio samples" for a reason that has
    /// nothing to do with the recording bug. Skip loudly rather than fail, so a
    /// permission problem can never be mistaken for the capture problem.
    private static func skipUnlessMicAuthorized() async throws {
        var status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            status = await AVCaptureDevice.requestAccess(for: .audio) ? .authorized : .denied
        }
        guard status == .authorized else {
            throw XCTSkip("""
                no microphone permission for the test host (status \(status.rawValue)) — grant it \
                under System Settings > Privacy & Security > Microphone. Until then this run says \
                nothing about recording.
                """)
        }
    }

    /// `configureAudioForRecording` is the value `RecordingPipeline` trusts to decide
    /// whether a recording can proceed. If it reports success without actually
    /// attaching audio, the pipeline arms a recording that can never start: no audio
    /// sample ⇒ `readyToRecordAudio` never flips ⇒ `isRecording` never flips ⇒ stop
    /// silently no-ops and both devices hang. So its verdict must match reality.
    func testAudioConfigurationVerdictMatchesReality() async throws {
        try await startRealRig()
        try await Self.skipUnlessMicAuthorized()
        guard await waitForFrames(since: 0) != nil else {
            return XCTFail("startup never delivered frames — \(await diagnostics())")
        }

        print("🎙 default audio device: \(AVCaptureDevice.default(for: .audio)?.localizedName ?? "NONE")")

        let verdict = rig.engine.configureAudioForRecording(delegate: AudioProbe())

        let session = rig.engine.captureSession
        let input = session.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .first { $0.device.hasMediaType(.audio) }
        let output = session.outputs.first { $0 is AVCaptureAudioDataOutput }

        print("""
            🎙 verdict=\(verdict) \
            input=\(input?.device.localizedName ?? "NOT ATTACHED") \
            output=\(output == nil ? "NOT ATTACHED" : "attached") \
            connection=\(rig.engine.audioConnection == nil ? "nil" : "live")
            """)

        XCTAssertEqual(verdict, input != nil && output != nil, """
            configureAudioForRecording returned \(verdict) but audio input attached=\(input != nil), \
            output attached=\(output != nil). A false success is what strands the recording.
            """)
    }

    /// Attaching audio isn't enough: the pipeline only becomes ready on a real audio
    /// sample buffer (RecordingPipeline `readyToRecordAudio`). If the device attaches
    /// but never delivers, the symptom is identical to a failed attach.
    func testAudioSamplesActuallyArrive() async throws {
        try await startRealRig()
        try await Self.skipUnlessMicAuthorized()
        guard await waitForFrames(since: 0) != nil else {
            return XCTFail("startup never delivered frames — \(await diagnostics())")
        }

        let probe = AudioProbe()
        guard rig.engine.configureAudioForRecording(delegate: probe) else {
            throw XCTSkip("audio could not be configured at all — testAudioConfigurationVerdictMatchesReality has the detail")
        }

        let deadline = Date().addingTimeInterval(5)
        while probe.samples.value == 0 && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        print("🎙 audio sample buffers in 5s: \(probe.samples.value)")
        XCTAssertGreaterThan(probe.samples.value, 0, """
            no audio sample buffers within 5s. readyToRecordAudio can therefore never flip, so \
            recording never starts and stopRecording silently does nothing — the hang.
            """)
    }

    private func scratchWriter() throws -> AVAssetWriter {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("probe-\(UUID().uuidString).mov")
        return try AVAssetWriter(outputURL: url, fileType: .mov)
    }

    /// Pinpoints WHICH asset-writer input can't be configured on this machine.
    /// `setupAssetWriterVideoInput` and `setupAssetWriterAudioInput` both return false
    /// silently when `canApply`/`canAdd` rejects their settings, and a false from
    /// either leaves its ready flag off forever — which is precisely what strands the
    /// recording and hangs both devices.
    func testAssetWriterInputsConfigureOnThisHardware() async throws {
        try await startRealRig()
        try await Self.skipUnlessMicAuthorized()
        guard await waitForFrames(since: 0) != nil else {
            return XCTFail("startup never delivered frames — \(await diagnostics())")
        }
        // The real AVFoundation device, not the app's descriptor — we need its format.
        guard let device = rig.engine.captureSession.inputs
            .compactMap({ $0 as? AVCaptureDeviceInput })
            .first(where: { $0.device.hasMediaType(.video) })?.device else {
            return XCTFail("no video device input on the session — \(await diagnostics())")
        }
        print("🎬 video device: \(device.localizedName)")

        // What the capture stack recommends, and whether forcing HEVC onto it survives.
        let recommended = rig.engine.videoDataOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov)
        print("🎬 recommended video settings: \(recommended.map { String(describing: $0) } ?? "NIL")")

        var withHEVC = recommended
        withHEVC?[AVVideoCodecKey] = AVVideoCodecType.hevc
        var withH264 = recommended
        withH264?[AVVideoCodecKey] = AVVideoCodecType.h264

        let probe = try scratchWriter()
        print("""
            🎬 canApply: recommended=\(probe.canApply(outputSettings: recommended, forMediaType: .video)) \
            +hevc=\(probe.canApply(outputSettings: withHEVC, forMediaType: .video)) \
            +h264=\(probe.canApply(outputSettings: withH264, forMediaType: .video))
            """)

        // Is HEVC itself unsupported here, or only HEVC *merged into* the recommended
        // settings (whose compression properties are keyed to the recommended codec)?
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let bareHEVC: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(dims.width),
            AVVideoHeightKey: Int(dims.height)
        ]
        let recommendedForHEVC = rig.engine.videoDataOutput
            .recommendedVideoSettings(forVideoCodecType: .hevc, assetWriterOutputFileType: .mov)
        print("""
            🎬 canApply: bare-hevc=\(probe.canApply(outputSettings: bareHEVC, forMediaType: .video)) \
            hevc-recommended=\(recommendedForHEVC.map { probe.canApply(outputSettings: $0, forMediaType: .video) }.map(String.init) ?? "NIL-SETTINGS")
            """)
        print("🎬 recommendedVideoSettings(forVideoCodecType: .hevc) = \(recommendedForHEVC.map { String(describing: $0) } ?? "NIL")")

        // The real code path, with this machine's real format description.
        let videoOK = rig.pipeline.setupAssetWriterVideoInput(device.activeFormat.formatDescription,
                                                              assetWriter: try scratchWriter())
        print("🎬 setupAssetWriterVideoInput → \(videoOK)")

        var audioOK: Bool?
        if let audioFormat = AVCaptureDevice.default(for: .audio)?.activeFormat.formatDescription {
            audioOK = rig.pipeline.setupAssetWriterAudioInput(audioFormat, assetWriter: try scratchWriter())
            print("🎙 setupAssetWriterAudioInput → \(audioOK!)")
        }

        XCTAssertTrue(videoOK, """
            the VIDEO asset-writer input could not be configured on this hardware, so \
            readyToRecordVideo can never flip and recording can never start.
            """)
        XCTAssertNotEqual(audioOK, false, """
            the AUDIO asset-writer input could not be configured on this hardware, so \
            readyToRecordAudio can never flip and recording can never start.
            """)
    }

    /// The product invariant, end to end on real hardware: a recording starts, and
    /// stopping it resolves the protocol with a StopRecordingVideoResp — the message
    /// the monitor blocks on in `.monitorWaitingForVideo`.
    func testRecordingStartsAndStopEmitsAResponse() async throws {
        try await startRealRig()
        try await Self.skipUnlessMicAuthorized()
        guard await waitForFrames(since: 0) != nil else {
            return XCTFail("startup never delivered frames — \(await diagnostics())")
        }

        // Intercept the pipeline's outbound messages: this is exactly what the
        // session coordinator (and so the monitor) waits for.
        let responded = expectation(description: "StopRecordingVideoResp")
        responded.assertForOverFulfill = false
        var startAcked = false
        rig.pipeline.sendMessage = { msg in
            if msg is RemoteCmd.StartRecordingVideoAck { startAcked = true }
            if msg is RemoteCmd.StopRecordingVideoResp { responded.fulfill() }
        }

        rig.startRecordingVideo()

        let deadline = Date().addingTimeInterval(10)
        while !rig.isRecording && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        let diag = await diagnostics()
        XCTAssertTrue(rig.isRecording, """
            recording never started within 10s (startAcked=\(startAcked)). \(diag)
            """)

        try? await Task.sleep(nanoseconds: 1_000_000_000)  // ~1s of footage

        // false = don't ship the movie to a peer; the pipeline then answers directly
        // instead of going through a resource transfer that needs a live peer.
        rig.stopRecordingVideo(false)

        await fulfillment(of: [responded], timeout: 15)
    }

    func testToggleKeepsFramesFlowing() async throws {
        try await startRealRig()
        guard await waitForFrames(since: 0) != nil else {
            return XCTFail("startup never delivered frames — \(await diagnostics())")
        }

        let healthy = await rig.availableCameraDevices().filter { !$0.isSuspended }
        guard healthy.count > 1 else {
            throw XCTSkip("only one healthy camera — nothing to toggle between")
        }

        let before = await rig.currentCameraDevice()
        let mark = Date().timeIntervalSinceReferenceDate
        _ = try? await rig.toggleCamera()

        guard let latency = await waitForFrames(since: mark) else {
            return XCTFail("no frames within \(Self.framesDeadline)s after toggle")
        }
        let after = await rig.currentCameraDevice()
        XCTAssertFalse(after?.isSuspended ?? true, "toggle must never land on a suspended device")
        print("📸 toggle \(before?.localizedName ?? "?") → \(after?.localizedName ?? "?"): frames in \(Int(latency * 1000))ms")
    }

    // MARK: - Manual exposure (Docs/pro-controls.md hardware probe)

    /// Probe question 1: which physical devices accept custom exposure — the
    /// header says virtual multi-lens devices refuse it, and the lens-swap
    /// design hinges on whether that holds on current iOS. Prints one line per
    /// device; never fails (the answer is data, not a pass/fail).
    func testProbeCustomExposureSupportPerDevice() async throws {
        try await startRealRig()
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera,
            .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera
        ]
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: .unspecified).devices
        for device in devices {
            let format = device.activeFormat
            print("🌗 PROBE \(device.localizedName) [\(device.deviceType.rawValue)] custom=\(device.isExposureModeSupported(.custom)) "
                  + "shutter=\(CMTimeGetSeconds(format.minExposureDuration))–\(CMTimeGetSeconds(format.maxExposureDuration))s "
                  + "ISO=\(format.minISO)–\(format.maxISO)")
        }
    }

    /// With Manual on, the session may be running a physical lens of the
    /// chosen virtual camera. The flip and the advertised active device must
    /// still speak in terms of the chosen camera: a flip goes to the other
    /// position (this pinned a field bug — "Unable to find camera position"),
    /// and Auto afterwards stays on the camera the flip landed on.
    func testFlipKeepsWorkingWhileManualExposureHasHopped() async throws {
        try await startRealRig()
        guard await waitForFrames(since: 0) != nil else {
            return XCTFail("startup never delivered frames — \(await diagnostics())")
        }
        let devices = await rig.availableCameraDevices()
        guard devices.count >= 2 else { throw XCTSkip("needs two selectable cameras to flip between") }
        let before = await rig.currentCameraDevice()
        let state = try await rig.setExposure(ExposureIntent.manual(durationSeconds: 1.0 / 250, iso: 0))
        guard state.mode == .manual else { throw XCTSkip("no device here accepts custom exposure") }

        _ = try await rig.toggleCamera()
        let after = await rig.currentCameraDevice()
        XCTAssertNotEqual(after?.uniqueID, before?.uniqueID, "the flip must land on the other camera")
        XCTAssertTrue(devices.contains { $0.uniqueID == after?.uniqueID },
                      "the reported camera is one the user can choose, never a hopped physical lens")

        _ = try await rig.setExposure(ExposureIntent.auto)
        let restored = await rig.currentCameraDevice()
        XCTAssertEqual(restored?.uniqueID, after?.uniqueID, "Auto stays on the camera the flip chose")
    }

    /// Manual exposure applied to the active device reads back within
    /// tolerance, and Auto restores continuous AE and the frame rate.
    func testManualExposureAppliesAndAutoRestores() async throws {
        try await startRealRig()
        guard await waitForFrames(since: 0) != nil else {
            return XCTFail("startup never delivered frames — \(await diagnostics())")
        }
        guard let device = rig.engine.videoDeviceInput?.device, device.isExposureModeSupported(.custom) else {
            throw XCTSkip("active device does not support custom exposure")
        }
        let fpsBefore = device.activeVideoMaxFrameDuration

        let wanted = 1.0 / 250
        let state = try await rig.setExposure(ExposureIntent.manual(durationSeconds: wanted, iso: device.activeFormat.minISO * 2))
        XCTAssertEqual(state.mode, .manual)
        XCTAssertEqual(state.durationSeconds, wanted, accuracy: wanted * 0.1)
        XCTAssertEqual(device.exposureMode, .custom)

        // A long shutter may legitimately stretch the frame duration in photo
        // mode; Auto must bring the frame rate back to what quality chose.
        _ = try await rig.setExposure(ExposureIntent.manual(durationSeconds: 0.5, iso: 0))
        let restored = try await rig.setExposure(ExposureIntent.auto)
        XCTAssertEqual(restored.mode, .auto)
        XCTAssertEqual(device.exposureMode, .continuousAutoExposure)
        XCTAssertEqual(CMTimeGetSeconds(device.activeVideoMaxFrameDuration),
                       CMTimeGetSeconds(fpsBefore), accuracy: 0.001)
    }
}
