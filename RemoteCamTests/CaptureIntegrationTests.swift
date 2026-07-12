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
            let device = await rig.currentCameraDevice()
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
