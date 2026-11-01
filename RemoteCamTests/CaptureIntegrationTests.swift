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
import ImageIO

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

    /// The exposure hardware probe (Docs/pro-controls.md): what this camera
    /// advertises, and that Manual / Auto-with-bias actually land on the
    /// device and are reported back. Prints the block so a run on a real
    /// iPhone answers the range and lens-hop questions a code read cannot.
    func testExposureProbeAppliesAndReportsTruth() async throws {
        let t0 = Date()
        try await startRealRig()
        print("🌗 probe: rig up in \(Int(Date().timeIntervalSince(t0)))s")
        guard await waitForFrames(since: 0) != nil else {
            throw XCTSkip("camera delivers no frames here — \(await diagnostics())")
        }
        print("🌗 probe: frames in \(Int(Date().timeIntervalSince(t0)))s")
        // Every Apple support query, raw, so a run on new hardware is a
        // complete record even when the block below is absent.
        if let av = rig.engine.currentDevice() {
            print("🌗 probe: raw \(av.localizedName) custom=\(av.isExposureModeSupported(.custom)) "
                  + "continuous=\(av.isExposureModeSupported(.continuousAutoExposure)) "
                  + "autoExpose=\(av.isExposureModeSupported(.autoExpose)) locked=\(av.isExposureModeSupported(.locked)) "
                  + "current=\(av.exposureMode.rawValue) poi=\(av.isExposurePointOfInterestSupported) "
                  + "bias=\(av.minExposureTargetBias)…\(av.maxExposureTargetBias) type=\(av.deviceType.rawValue)")
        }
        guard let before = await rig.gatherCurrentCameraCapabilities()?.exposure else {
            throw XCTSkip("this camera offers neither EV bias nor manual exposure")
        }
        let device = await rig.currentCameraDevice()
        print("🌗 probe: \(device?.localizedName ?? "?") \(before)")

        if before.maxBias > before.minBias {
            let t1 = Date()
            try await rig.setExposure(.auto(bias: 1))
            print("🌗 probe: setExposure(bias 1) returned in \(Int(Date().timeIntervalSince(t1) * 1000))ms")
            // The bias lands asynchronously (AVFoundation's completion handler
            // reports when); poll a little before judging it.
            var biased = await rig.gatherCurrentCameraCapabilities()?.exposure
            for _ in 0..<40 where (biased?.bias ?? 0) < 0.99 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                biased = await rig.gatherCurrentCameraCapabilities()?.exposure
            }
            print("🌗 probe: bias reads \(biased?.bias ?? -99) after \(Int(Date().timeIntervalSince(t1) * 1000))ms")
            XCTAssertEqual(biased?.mode, .auto)
            XCTAssertEqual(biased?.bias ?? 0, 1, accuracy: 0.01, "the bias must land on the device")
        }

        guard before.supportsManual else {
            try await rig.setExposure(.auto(bias: 0))
            throw XCTSkip("no manual exposure on \(device?.localizedName ?? "this camera") — bias verified")
        }
        let logicalBefore = device?.uniqueID
        try await rig.setExposure(.manual(durationSeconds: 1.0 / 250, iso: min(400, before.maxISO)))
        let manualFrames = await waitForFrames(since: lastFrameAt)
        XCTAssertNotNil(manualFrames, "frames must keep flowing in manual")
        let manual = await rig.gatherCurrentCameraCapabilities()
        XCTAssertEqual(manual?.exposure?.mode, .manual)
        XCTAssertEqual(manual?.exposure?.durationSeconds ?? 0, 1.0 / 250, accuracy: 1.0 / 2000)
        XCTAssertEqual(manual?.exposure?.iso ?? 0, min(400, before.maxISO), accuracy: 1)
        XCTAssertEqual(manual?.activeDeviceID, logicalBefore, "a lens hop never leaks into the logical device")
        print("🌗 probe: manual landed — \(manual?.exposure.map { "\($0)" } ?? "nil") active=\(manual?.activeDeviceID ?? "?")")

        // A focus tap must not throw the manual setting away.
        try await rig.focusAtPoint(x: 0.5, y: 0.5)
        let afterFocus = await rig.gatherCurrentCameraCapabilities()?.exposure?.mode
        XCTAssertEqual(afterFocus, .manual)

        try await rig.setExposure(.auto(bias: 0))
        let autoFrames = await waitForFrames(since: lastFrameAt)
        XCTAssertNotNil(autoFrames, "frames must keep flowing after auto")
        let auto = await rig.gatherCurrentCameraCapabilities()
        XCTAssertEqual(auto?.exposure?.mode, .auto)
        XCTAssertEqual(auto?.activeDeviceID, logicalBefore, "auto returns to the chosen device")
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

    // MARK: - Photo quality (full-sensor stills)

    /// Captures one still through the engine and hands back its bytes.
    /// Rewires `onPicture` away from the session — fine, the rig is torn
    /// down after every test.
    private func captureStill(timeout: TimeInterval = 30) async throws -> Data {
        let photoDelivered = expectation(description: "photo delivered")
        let delivered = Locked<(Data?, Error?)>((nil, nil))
        rig.engine.onPicture = { data, error in
            delivered.value = (data, error)
            photoDelivered.fulfill()
        }
        rig.engine.takePicture(false)
        await fulfillment(of: [photoDelivered], timeout: timeout)
        let (data, error) = delivered.value
        if let data { return data }
        throw error ?? NSError(domain: "no photo delivered", code: 0, userInfo: nil)
    }

    private func stillDimensions(_ data: Data) throws -> (width: Int, height: Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int),
                try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int))
    }

    /// THE invariant this branch exists for: in photo mode a still is the
    /// active format's full photo resolution — never a frame lifted from a
    /// video format. Native-ratio shot must match the format's photo ceiling
    /// exactly; any other ratio must be a crop of that full capture
    /// (`cropRect` is the oracle — it is what the engine applies).
    func testPhotoModeStillIsTheFormatsFullPhotoResolution() async throws {
        try await startRealRig()
        guard await waitForFrames(since: 0) != nil else {
            throw XCTSkip("camera delivers no frames here — \(await diagnostics())")
        }
        guard #available(macCatalyst 16.0, iOS 16.0, *) else {
            throw XCTSkip("maxPhotoDimensions needs OS 16")
        }
        let device = try XCTUnwrap(rig.engine.currentDevice())
        let ceiling = try XCTUnwrap(device.activeFormat.supportedMaxPhotoDimensions
            .max { Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height) })
        let ceilingW = Int(ceiling.width), ceilingH = Int(ceiling.height)
        print("📸 fullres: \(device.localizedName) photo ceiling \(ceilingW)x\(ceilingH) "
              + "format \(device.activeFormat.formatDescription)")

        // Shoot at the sensor's own ratio first: no crop may apply.
        let native = Double(ceilingW) / Double(ceilingH)
        let nativeAspect: AspectRatio? = abs(native - 4.0 / 3.0) < 0.05 ? .fourThree
            : abs(native - 16.0 / 9.0) < 0.05 ? .sixteenNine : nil
        if let nativeAspect {
            _ = await rig.engine.setAspectRatio(nativeAspect)
            let dims = try stillDimensions(try await captureStill())
            print("📸 fullres: native \(nativeAspect.displayName) still \(dims.width)x\(dims.height)")
            XCTAssertEqual(Set([dims.width, dims.height]), Set([ceilingW, ceilingH]),
                           "a native-ratio still must be the format's full photo resolution")
        }

        // Any other ratio is a crop OF THE FULL CAPTURE: cropRect on the
        // ceiling predicts the exact output dimensions.
        let croppedAspect: AspectRatio = nativeAspect == .fourThree ? .sixteenNine : .fourThree
        _ = await rig.engine.setAspectRatio(croppedAspect)
        let dims = try stillDimensions(try await captureStill())
        print("📸 fullres: cropped \(croppedAspect.displayName) still \(dims.width)x\(dims.height)")
        let expected = CaptureEngine.cropRect(
            sourceWidth: CGFloat(ceilingW), sourceHeight: CGFloat(ceilingH),
            aspectRatio: croppedAspect)?.size
            ?? CGSize(width: ceilingW, height: ceilingH)
        let sorted = [dims.width, dims.height].sorted()
        let expectedSorted = [Int(expected.width), Int(expected.height)].sorted()
        XCTAssertEqual(sorted[1], expectedSorted[1], accuracy: 2,
                       "the crop must come from the full-resolution capture")
        XCTAssertEqual(sorted[0], expectedSorted[0], accuracy: 2,
                       "the crop must come from the full-resolution capture")
    }

    /// The engine's session configuration follows the rig's mode — and both
    /// directions keep frames flowing (the preview encoder survives the
    /// 4:3 ↔ 16:9 dimension cut).
    func testCaptureModeFollowsTheRigAndFramesKeepFlowing() async throws {
        try await startRealRig()
        guard await waitForFrames(since: 0) != nil else {
            throw XCTSkip("camera delivers no frames here — \(await diagnostics())")
        }

        var mark = Date().timeIntervalSinceReferenceDate
        rig.currentCameraMode = .Video
        guard let toVideo = await waitForFrames(since: mark) else {
            return XCTFail("no frames after →video — \(await diagnostics())")
        }
        mark = Date().timeIntervalSinceReferenceDate
        rig.currentCameraMode = .Photo
        guard let toPhoto = await waitForFrames(since: mark) else {
            return XCTFail("no frames after →photo — \(await diagnostics())")
        }
        print("📸 mode flip: →video frames in \(Int(toVideo * 1000))ms, →photo in \(Int(toPhoto * 1000))ms")

        let data = try await captureStill()
        XCTAssertFalse(data.isEmpty, "a still must capture after round-tripping the modes")
    }

    /// A fresh session starts on the best format the hardware encodes.
    func testDefaultPhotoFormatMatchesTheHardware() async throws {
        try await startRealRig()
        let (_, _, format, _) = rig.engine.statusSnapshot()
        let hevcAvailable = rig.engine.photoOutput.availablePhotoCodecTypes.contains(.hevc)
        XCTAssertEqual(format, CaptureEngine.defaultPhotoFormat(hevcAvailable: hevcAvailable))
        print("📸 default format: \(format) (hevc \(hevcAvailable))")
    }

    /// Diagnostic for the current Mac and any attached Continuity Camera.
    /// Run on the Mac with the iPhone connected and unlocked; this prints the
    /// discovered device identities plus the HEVC photo codec exposed by a
    /// photo output configured against each device.
    func testProbePhotoCodecsForConnectedCameras() async throws {
        let auth = AVCaptureDevice.authorizationStatus(for: .video)
        if auth == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { throw XCTSkip("camera permission denied") }
        } else if auth != .authorized {
            throw XCTSkip("camera permission is not authorized")
        }

        var types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera,
            .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera
        ]
        if #available(iOS 17.0, macCatalyst 17.0, *) { types.append(.external) }
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: .unspecified
        ).devices
        XCTAssertFalse(devices.isEmpty, "No video capture devices discovered")

        for device in devices {
            let session = AVCaptureSession()
            let output = AVCapturePhotoOutput()
            do {
                session.beginConfiguration()
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input), session.canAddOutput(output) else {
                    session.commitConfiguration()
                    print("HEIF PROBE device=\(device.localizedName) type=\(device.deviceType.rawValue) cannot configure")
                    continue
                }
                session.addInput(input)
                session.addOutput(output)
                session.commitConfiguration()
                print("HEIF PROBE device=\(device.localizedName) type=\(device.deviceType.rawValue) position=\(device.position.rawValue) codecs=\(output.availablePhotoCodecTypes.map(\.rawValue)) hevc=\(output.availablePhotoCodecTypes.contains(.hevc))")
            } catch {
                if session.isRunning { session.stopRunning() }
                print("HEIF PROBE device=\(device.localizedName) type=\(device.deviceType.rawValue) error=\(error)")
            }
        }
    }

    /// The production ordering, reproduced. The coordinator asks for
    /// capabilities on `BecomeCamera` (camera screen `viewDidLoad`), which
    /// happens BEFORE the rig configures the capture session (`viewDidAppear`
    /// -> `startCameraOnce`). AVCapturePhotoOutput.h is explicit: "If you've
    /// not yet added your receiver to an AVCaptureSession with a video
    /// source, no codec types are available." So the early probe reads an
    /// empty codec list, and `cameraInfoCacheValid` makes that answer final.
    ///
    /// The invariant: what we REPORT about HEIF must equal what the live
    /// photo output says.
    @MainActor
    func testHEIFReportMatchesLiveOutputAcrossSetup() async throws {
        var status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            status = await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
        }
        guard status == .authorized else {
            throw XCTSkip("no camera permission in this environment")
        }

        rig = CameraRig(session: SessionCoordinator(), frameSender: FrameSender())

        // 1. The BecomeCamera probe, before any session configuration.
        await rig.gatherAllCameraCapabilities()
        let earlyCodecs = rig.engine.photoOutput.availablePhotoCodecTypes
        let earlyResp = await rig.gatherCurrentCameraCapabilities()
        print("HEIF ORDERING early: codecs=\(earlyCodecs.map(\.rawValue)) "
              + "resp=\(earlyResp == nil ? "nil" : "present") "
              + "front=\(String(describing: earlyResp?.frontCamera?.supportsHEIF)) "
              + "back=\(String(describing: earlyResp?.backCamera?.supportsHEIF))")

        // 2. The camera screen appears and configures the session.
        rig.startCameraOnce()
        let deadline = Date().addingTimeInterval(10)
        while rig.cameraViewModel.isBusy && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard rig.cameraViewModel.previewSession != nil else {
            throw XCTSkip("no camera on this machine (simulator/CI)")
        }

        // 3. What the remote is now told, against the live truth.
        await rig.gatherAllCameraCapabilities()
        let liveHEVC = rig.engine.photoOutput.availablePhotoCodecTypes.contains(.hevc)
        guard let resp = await rig.gatherCurrentCameraCapabilities() else {
            return XCTFail("no capabilities after setup")
        }
        let reported = resp.getCurrentCameraInfo()?.supportsHEIF
        print("HEIF ORDERING after setup: liveHEVC=\(liveHEVC) "
              + "reported=\(String(describing: reported)) "
              + "currentPhotoFormat=\(resp.currentPhotoFormat) "
              + "front=\(String(describing: resp.frontCamera?.supportsHEIF)) "
              + "back=\(String(describing: resp.backCamera?.supportsHEIF))")

        XCTAssertEqual(reported, liveHEVC,
                       "remote is told HEIF=\(String(describing: reported)) "
                       + "while the photo output says \(liveHEVC)")
    }

    /// The camera announces that it can answer, instead of being polled.
    /// `AVCapturePhotoOutput.h` documents `availablePhotoCodecTypes` as
    /// key-value observable; this is the signal that replaces the capabilities
    /// retry ladder, so if it ever stops firing the ladder's removal is unsafe.
    @MainActor
    func testPhotoCodecsObservationFiresWhenSessionComesUp() async throws {
        var status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            status = await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
        }
        guard status == .authorized else {
            throw XCTSkip("no camera permission in this environment")
        }

        rig = CameraRig(session: SessionCoordinator(), frameSender: FrameSender())
        let fired = expectation(description: "photo capabilities became answerable")
        fired.assertForOverFulfill = false
        rig.engine.onPhotoCapabilitiesChanged = { fired.fulfill() }

        rig.startCameraOnce()
        await fulfillment(of: [fired], timeout: 10)

        let codecs = rig.engine.photoOutput.availablePhotoCodecTypes
        print("HEIF KVO: fired with codecs=\(codecs.map(\.rawValue))")
        XCTAssertTrue(codecs.contains(.hevc),
                      "observation fired but the output still reports no HEVC")
    }

    /// HEIF in, HEIF out: the aspect crop must not silently convert to JPEG.
    func testHEICSurvivesAspectCrop() async throws {
        try await startRealRig()
        guard await waitForFrames(since: 0) != nil else {
            throw XCTSkip("camera delivers no frames here — \(await diagnostics())")
        }
        guard await rig.engine.setPhotoQuality(format: .heif, hdrMode: .off) != nil else {
            throw XCTSkip("no HEIF on this camera")
        }
        // Force a crop: shoot an aspect that can't match the sensor.
        _ = await rig.engine.setAspectRatio(.oneOne)
        let data = try await captureStill()
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let type = try XCTUnwrap(CGImageSourceGetType(source) as String?)
        print("📸 heic: cropped still type \(type), \(data.count) bytes")
        XCTAssertTrue(type.contains("heic") || type.contains("heif"),
                      "the crop must keep the HEIF container, got \(type)")
    }
}
