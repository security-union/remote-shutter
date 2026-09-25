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
import CoreImage
#if canImport(Cinematic)
import Cinematic
#endif

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

    /// Cinematic on the real rig (Docs/cinematic.md): the effect turns on
    /// through the rig, the aperture lands, frames keep flowing, the state
    /// reply carries the truth, a focus tap doesn't hit the pinned focus
    /// mode, the front camera hops to TrueDepth, photo mode suspends it, the
    /// editable output attaches the movie output and holds 16:9, and turning
    /// it off restores the quality. Skips where the camera has no Cinematic
    /// formats (Macs, older iPhones). Prints 🎬 lines for the hardware record.
    func testCinematicOnTheRealRig() async throws {
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { throw XCTSkip("Cinematic needs iOS 26") }
        try await startRealRig()
        guard await waitForFrames(since: 0) != nil else {
            throw XCTSkip("camera delivers no frames here — \(await diagnostics())")
        }
        rig.currentCameraMode = .Video
        guard let before = await rig.gatherCurrentCameraCapabilities(), let offered = before.cinematic else {
            throw XCTSkip("this camera offers no Cinematic block")
        }
        print("🎬 rig: offered f/\(offered.minAperture)…\(offered.maxAperture) default f/\(offered.defaultAperture) "
              + "qualities=\(offered.qualities) quality=\(before.currentVideoResolution)/\(before.currentVideoFrameRate)")
        XCTAssertFalse(offered.enabled)

        // Subjects: capture what the engine publishes (the rig normally
        // forwards it to the director).
        let reports = Locked<[CinematicSubjectsReport]>([])
        let forward = rig.engine.onCinematicSubjects
        rig.engine.onCinematicSubjects = { report in
            reports.mutate { $0.append(report) }
            forward?(report)
        }

        let t0 = Date()
        try await rig.setCinematic(CinematicIntent(enabled: true, aperture: offered.minAperture))
        let on = await rig.gatherCurrentCameraCapabilities()?.cinematic
        print("🎬 rig: enabled=\(on?.enabled ?? false) aperture=f/\(on?.aperture ?? 0) in \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        XCTAssertEqual(on?.enabled, true)
        XCTAssertEqual(Double(on?.aperture ?? 0), Double(offered.minAperture), accuracy: 0.05)
        let flowing = await waitForFrames(since: lastFrameAt)
        XCTAssertNotNil(flowing, "frames must keep flowing with Cinematic on")
        let exposure = await rig.gatherCurrentCameraCapabilities()?.exposure
        XCTAssertNotEqual(exposure?.supportsManual, true, "Manual is off the table while Cinematic runs")

        // Focus with the focus mode pinned: must not raise.
        try await rig.focusAtPoint(x: 0.5, y: 0.4)
        try await rig.setCinematicFocus(.trackPoint(x: 0.5, y: 0.4, strength: .weak))
        try await rig.setCinematicFocus(.fixedPoint(x: 0.5, y: 0.5))
        try await rig.setCinematicFocus(.trackPoint(x: 0.5, y: 0.4, strength: .strong))
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let seen = reports.value
        print("🎬 rig: \(seen.count) subject reports; last=\(seen.last.map { "\($0.subjects.map { "\($0.kind)#\($0.id) \($0.rect) focus=\(String(describing: $0.focus))" }) light=\(!$0.notEnoughLight)" } ?? "none")")
        if let subject = seen.last?.subjects.first {
            try await rig.setCinematicFocus(.subject(id: subject.id, strength: .strong))
        }
        // What the director is sent, with the boxes it would draw (pull
        // Documents/CinematicProbe/rig_*.jpg off the phone to look).
        let output = rig.engine.videoDataOutput
        let original = output.sampleBufferDelegate
        let tap = StreamedFrameTap(forwardingTo: original)
        output.setSampleBufferDelegate(tap, queue: rig.engine.dataOutputQueue)
        defer { output.setSampleBufferDelegate(original, queue: rig.engine.dataOutputQueue) }
        if let frame = await tap.nextFrame() {
            StreamedFrameTap.save(frame, subjects: reports.value.last?.subjects ?? [], name: "rig_back")
        }
        assertSubjectMappingMatchesAVFoundation("back")

        // The aperture follows a second request.
        try await rig.setCinematic(CinematicIntent(enabled: true, aperture: 8))
        let narrower = await rig.gatherCurrentCameraCapabilities()?.cinematic?.aperture ?? 0
        XCTAssertEqual(Double(narrower), 8, accuracy: 0.05)

        // Editable: the movie output attaches, and the aspect holds 16:9.
        try await rig.setCinematic(CinematicIntent(enabled: true, aperture: 0, output: .editable))
        XCTAssertNotNil(rig.engine.cinematicMovieOutputForRecording())
        let aspect = await rig.setAspectRatio(.fourThree)
        XCTAssertEqual(aspect, .sixteenNine, "the editable file is 16:9 only")
        try await rig.setCinematic(CinematicIntent(enabled: true, aperture: 0, output: .baked))
        XCTAssertNil(rig.engine.cinematicMovieOutputForRecording())

        // Photo mode suspends the effect; video brings it back.
        rig.currentCameraMode = .Photo
        let inPhoto = await rig.gatherCurrentCameraCapabilities()?.cinematic?.enabled
        XCTAssertEqual(inPhoto, false)
        rig.currentCameraMode = .Video
        let backInVideo = await rig.gatherCurrentCameraCapabilities()?.cinematic?.enabled
        XCTAssertEqual(backInVideo, true)

        // The flip: the front camera hops to its Cinematic sibling, and the
        // chosen (logical) camera stays what the flip picked.
        #if !targetEnvironment(macCatalyst)
        let back = await rig.currentCameraDevice()
        _ = try await rig.toggleCamera()
        let chosen = await rig.currentCameraDevice()
        let running = rig.engine.currentDevice()
        let front = await rig.gatherCurrentCameraCapabilities()
        let mirrored = rig.engine.videoConnection?.isVideoMirrored
        print("🎬 rig: flip chose \(chosen?.localizedName ?? "nil") running \(running?.localizedName ?? "nil") "
              + "[\(running?.deviceType.rawValue ?? "-")] cinematic=\(front?.cinematic?.enabled ?? false) "
              + "dataOutputMirrored=\(String(describing: mirrored))")
        XCTAssertNotEqual(chosen?.uniqueID, back?.uniqueID)
        if front?.cinematic != nil {
            XCTAssertEqual(front?.cinematic?.enabled, true)
            let frontFlowing = await waitForFrames(since: lastFrameAt)
            XCTAssertNotNil(frontFlowing, "front frames must flow with Cinematic on")
            try await rig.focusAtPoint(x: 0.5, y: 0.5)
            try await Task.sleep(nanoseconds: 2_000_000_000)
            if let frame = await tap.nextFrame() {
                StreamedFrameTap.save(frame, subjects: reports.value.last?.subjects ?? [], name: "rig_front")
            }
            assertSubjectMappingMatchesAVFoundation("front")
        }
        _ = try await rig.toggleCamera()
        let flippedBack = await rig.currentCameraDevice()
        XCTAssertEqual(flippedBack?.uniqueID, back?.uniqueID)
        #endif

        // Off: the quality setting's format and frame rate come back.
        try await rig.setCinematic(CinematicIntent(enabled: false))
        let off = await rig.gatherCurrentCameraCapabilities()
        XCTAssertEqual(off?.cinematic?.enabled, false)
        XCTAssertEqual(off?.currentVideoResolution, before.currentVideoResolution)
        XCTAssertEqual(off?.currentVideoFrameRate, before.currentVideoFrameRate)
        let offFlowing = await waitForFrames(since: lastFrameAt)
        XCTAssertNotNil(offFlowing, "frames must flow after Cinematic goes off")
        let manualAfter = await rig.gatherCurrentCameraCapabilities()?.exposure?.supportsManual
        XCTAssertEqual(manualAfter, before.exposure?.supportsManual)
    }

    /// The subject boxes (and focus taps) map device space to the streamed
    /// image with `FocusPointMapping` and the connection's orientation +
    /// mirroring. AVFoundation's own conversion is the ground truth: they
    /// must agree for every camera, whatever the scene.
    private func assertSubjectMappingMatchesAVFoundation(_ label: String,
                                                         file: StaticString = #filePath, line: UInt = #line) {
        let output = rig.engine.videoDataOutput
        guard let connection = output.connection(with: .video) else {
            return XCTFail("no video connection", file: file, line: line)
        }
        let full = output.outputRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
        let samples = [CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4), CGRect(x: 0.6, y: 0.05, width: 0.2, height: 0.1)]
        for device in samples {
            let converted = output.outputRectConverted(fromMetadataOutputRect: device)
            let truth = CGRect(x: (converted.minX - full.minX) / full.width, y: (converted.minY - full.minY) / full.height,
                               width: converted.width / full.width, height: converted.height / full.height)
            let ours = FocusPointMapping.displayRect(deviceNormalized: device,
                                                     videoOrientation: connection.videoOrientation,
                                                     mirrored: connection.isVideoMirrored)
            print("🎬 mapping \(label): device=\(device) avfoundation=\(truth) ours=\(ours) "
                  + "orientation=\(connection.videoOrientation.rawValue) mirrored=\(connection.isVideoMirrored)")
            XCTAssertEqual(ours.minX, truth.minX, accuracy: 0.01, "\(label) x", file: file, line: line)
            XCTAssertEqual(ours.minY, truth.minY, accuracy: 0.01, "\(label) y", file: file, line: line)
            XCTAssertEqual(ours.width, truth.width, accuracy: 0.01, "\(label) width", file: file, line: line)
            XCTAssertEqual(ours.height, truth.height, accuracy: 0.01, "\(label) height", file: file, line: line)
        }
    }

    /// Refusals come back as errors, never as silent no-ops.
    func testCinematicRefusesPhotoModeOnTheRealRig() async throws {
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { throw XCTSkip("Cinematic needs iOS 26") }
        try await startRealRig()
        guard await waitForFrames(since: 0) != nil else {
            throw XCTSkip("camera delivers no frames here — \(await diagnostics())")
        }
        guard await rig.gatherCurrentCameraCapabilities()?.cinematic != nil else {
            throw XCTSkip("this camera offers no Cinematic block")
        }
        rig.currentCameraMode = .Photo
        do {
            try await rig.setCinematic(CinematicIntent(enabled: true))
            XCTFail("Cinematic must be refused in photo mode")
        } catch {
            print("🎬 rig: photo mode refusal: \((error as NSError).domain)")
        }
        rig.currentCameraMode = .Video
        _ = await rig.setAspectRatio(.oneOne)
        do {
            try await rig.setCinematic(CinematicIntent(enabled: true, output: .editable))
            XCTFail("editable Cinematic must be refused at 1:1")
        } catch {
            print("🎬 rig: aspect refusal: \((error as NSError).domain)")
        }
        _ = await rig.setAspectRatio(.sixteenNine)
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

    /// Both Cinematic outputs, recorded through the real pipeline as a
    /// multicam take would be (sync metadata set): Baked writes one video
    /// track with the first-frame offset inside the .mov; Editable writes the
    /// movie output's disparity + metadata tracks, Cinematic reads it as
    /// renderable, and the offset lands in the sidecar. Copies each clip to
    /// Documents/CinematicTakes for inspection (the clips also go to Photos).
    func testCinematicTakesRecordBothOutputsOnTheRealRig() async throws {
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { throw XCTSkip("Cinematic needs iOS 26") }
        try await startRealRig()
        try await Self.skipUnlessMicAuthorized()
        guard await waitForFrames(since: 0) != nil else {
            throw XCTSkip("camera delivers no frames here — \(await diagnostics())")
        }
        rig.currentCameraMode = .Video
        guard await rig.gatherCurrentCameraCapabilities()?.cinematic != nil else {
            throw XCTSkip("this camera offers no Cinematic block")
        }
        let keep = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CinematicTakes", isDirectory: true)
        try? FileManager.default.createDirectory(at: keep, withIntermediateDirectories: true)

        for output in [CinematicOutput.baked, .editable] {
            try await rig.setCinematic(CinematicIntent(enabled: true, output: output))
            let now = SyncClock.nowMillis()
            let metadata = CaptureSyncMetadata(
                sessionID: UUID().uuidString, captureID: UUID().uuidString, cameraIndex: 1,
                anchorMillis: now, clockOffsetMillis: 0, roundTripMillis: 0,
                cameraClockAnchorMillis: now)
            rig.setVideoSyncMetadata(metadata)

            let responded = expectation(description: "StopRecordingVideoResp \(output)")
            responded.assertForOverFulfill = false
            let copy = keep.appendingPathComponent("\(output).mov")
            try? FileManager.default.removeItem(at: copy)
            rig.pipeline.sendMessage = { msg in
                guard msg is RemoteCmd.StopRecordingVideoResp else { return }
                // Before Photos takes the file.
                try? FileManager.default.copyItem(at: movieUrl(), to: copy)
                responded.fulfill()
            }
            let pressed = Date()
            rig.startRecordingVideo()
            let deadline = Date().addingTimeInterval(10)
            while !rig.isRecording && Date() < deadline {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            let startDiagnostics = await diagnostics()
            XCTAssertTrue(rig.isRecording, "\(output): recording never started. \(startDiagnostics)")
            print("🎬 take \(output): rolling after \(Int(Date().timeIntervalSince(pressed) * 1000)) ms")
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            rig.stopRecordingVideo(false)
            await fulfillment(of: [responded], timeout: 15)

            let asset = AVURLAsset(url: copy)
            let tracks = (try? await asset.load(.tracks)) ?? []
            let subtypes = await withTaskGroup(of: String.self) { group in
                for track in tracks {
                    group.addTask {
                        let formats = (try? await track.load(.formatDescriptions)) ?? []
                        return formats.map { Self.fourCC(CMFormatDescriptionGetMediaSubType($0)) }.joined()
                    }
                }
                return await group.reduce(into: [String]()) { $0.append($1) }
            }
            print("🎬 take \(output): tracks=\(subtypes.sorted())")
            let items = (try? await asset.load(.metadata)) ?? []
            let offsetItem = items.first { $0.identifier?.rawValue.hasSuffix(CaptureSyncMetadata.QuickTimeKey.firstFrameOffset) == true }
            let fileOffset = try? await offsetItem?.load(.value)

            switch output {
            case .baked:
                XCTAssertFalse(subtypes.contains("dish"), "baked has no disparity track")
                XCTAssertNotNil(fileOffset, "baked stamps the first-frame offset into the .mov")
                print("🎬 take baked: firstFrameOffsetMs=\(String(describing: fileOffset))")
            case .editable:
                XCTAssertTrue(subtypes.contains("dish"), "editable carries the disparity track")
                let sidecar = RecordingPipeline.syncSidecarDirectory
                    .appendingPathComponent("\(metadata.filenamePrefix).json")
                let stamped = (try? String(contentsOf: sidecar, encoding: .utf8))
                    .flatMap(CaptureSyncMetadata.fromJSONString)
                XCTAssertNotNil(stamped?.firstFrameOffsetMillis, "editable writes the offset to the sidecar")
                print("🎬 take editable: firstFrameOffsetMs=\(String(describing: stamped?.firstFrameOffsetMillis))")
                #if canImport(Cinematic)
                if #available(iOS 27.0, macCatalyst 27.0, *) {
                    let capability = await CNAssetInfo.cinematicCapability(for: asset)
                    print("🎬 take editable: CNCinematicCapability=\(capability.rawValue)")
                    XCTAssertEqual(capability, .renderable)
                }
                #endif
            }
        }
        rig.setVideoSyncMetadata(nil)
        try await rig.setCinematic(CinematicIntent(enabled: false))
    }

    private static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        return String(bytes: bytes, encoding: .ascii) ?? "\(code)"
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
}

/// Test-only tap on the engine's video data output: forwards every frame to
/// the rig's delegate (so streaming is undisturbed) and hands one frame to a
/// waiting test. Used to look at what the director is sent.
private final class StreamedFrameTap: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private weak var forward: AVCaptureVideoDataOutputSampleBufferDelegate?
    private let request = Locked<((CIImage) -> Void)?>(nil)

    init(forwardingTo forward: AVCaptureVideoDataOutputSampleBufferDelegate?) {
        self.forward = forward
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if let pending = request.value, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) {
            request.value = nil
            pending(CIImage(cvPixelBuffer: pixels))
        }
        forward?.captureOutput?(output, didOutput: sampleBuffer, from: connection)
    }

    func nextFrame() async -> CIImage? {
        await withCheckedContinuation { continuation in
            let done = Locked(false)
            request.value = { image in
                done.mutate { finished in
                    guard !finished else { return }
                    finished = true
                    continuation.resume(returning: image)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [request] in
                done.mutate { finished in
                    guard !finished else { return }
                    finished = true
                    request.value = nil
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Draws the subject boxes (upright display space, origin top-left) on
    /// the frame and writes Documents/CinematicProbe/<name>.jpg.
    static func save(_ image: CIImage, subjects: [CinematicSubject], name: String) {
        let context = CIContext()
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return }
        let width = cgImage.width, height = cgImage.height
        guard let canvas = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        canvas.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        canvas.setLineWidth(6)
        for subject in subjects {
            canvas.setStrokeColor(subject.focus != nil ? CGColor(red: 1, green: 0.8, blue: 0, alpha: 1)
                                                       : CGColor(red: 0, green: 1, blue: 0, alpha: 1))
            let rect = CGRect(x: subject.rect.minX * CGFloat(width),
                              y: (1 - subject.rect.maxY) * CGFloat(height),   // CG origin is bottom-left
                              width: subject.rect.width * CGFloat(width),
                              height: subject.rect.height * CGFloat(height))
            canvas.stroke(rect)
        }
        guard let boxed = canvas.makeImage() else { return }
        let url = CinematicProbe.directory.appendingPathComponent("\(name).jpg")
        try? context.writeJPEGRepresentation(of: CIImage(cgImage: boxed), to: url,
                                             colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }
}
