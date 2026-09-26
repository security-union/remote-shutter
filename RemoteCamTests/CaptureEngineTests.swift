import XCTest
import AVFoundation
@testable import RemoteShutter

/// Exercises the pure, session-free surface of `CaptureEngine`. These paths
/// need no `AVCaptureDevice`, so they run on the simulator.
final class CaptureEngineTests: XCTestCase {

    // MARK: - resolveFrameRate
    // Supported rates form disjoint ranges; a value outside every range
    // raises an uncatchable ObjC exception in AVFoundation, so the resolver
    // must always land inside one.

    func testFrameRateBelowOnlyRangeSnapsUp() {
        // The Mac-camera crash: format supports exactly 60–60, app asked for 30.
        let resolved = CaptureEngine.resolveFrameRate(requested: 30, supportedRanges: [60...60])
        XCTAssertEqual(resolved?.fps, 60)
        XCTAssertEqual(resolved?.rangeIndex, 0)
    }

    func testFrameRateInsideRangeIsUnchanged() {
        XCTAssertEqual(CaptureEngine.resolveFrameRate(requested: 30, supportedRanges: [1...60])?.fps, 30)
        XCTAssertEqual(CaptureEngine.resolveFrameRate(requested: 24, supportedRanges: [24...30, 60...60])?.fps, 24)
    }

    func testFrameRateAboveAllRangesClampsToMax() {
        let resolved = CaptureEngine.resolveFrameRate(requested: 120, supportedRanges: [1...30, 1...60])
        XCTAssertEqual(resolved?.fps, 60)
        XCTAssertEqual(resolved?.rangeIndex, 1, "the chosen range must be the one containing the answer")
    }

    func testFrameRateBetweenDisjointRangesPicksNearest() {
        // 40 is 10 away from 30, 20 away from 60.
        let low = CaptureEngine.resolveFrameRate(requested: 40, supportedRanges: [24...30, 60...60])
        XCTAssertEqual(low?.fps, 30)
        XCTAssertEqual(low?.rangeIndex, 0)
        // 55 is 25 away from 30, 5 away from 60.
        let high = CaptureEngine.resolveFrameRate(requested: 55, supportedRanges: [24...30, 60...60])
        XCTAssertEqual(high?.fps, 60)
        XCTAssertEqual(high?.rangeIndex, 1)
    }

    func testFrameRateTiePrefersLowerRate() {
        // 45 is equidistant from 30 and 60 — don't exceed the request unnecessarily.
        XCTAssertEqual(CaptureEngine.resolveFrameRate(requested: 45, supportedRanges: [24...30, 60...60])?.fps, 30)
    }

    func testFrameRateWithNoReportedRangesResolvesNil() {
        // No ranges: the caller leaves the device's defaults untouched.
        XCTAssertNil(CaptureEngine.resolveFrameRate(requested: 30, supportedRanges: []))
    }

    func testFrameRateFractionalUVCRangeStillChoosesIt() {
        // Real UVC hardware advertises "60 fps" as 60.00024 — the resolver
        // must pick that range so the caller can use ITS CMTime durations.
        let resolved = CaptureEngine.resolveFrameRate(
            requested: 60, supportedRanges: [30.00003...30.00003, 60.00024...60.00024])
        XCTAssertEqual(resolved?.fps, 60)
        XCTAssertEqual(resolved?.rangeIndex, 1)
    }

    // MARK: - Configuration state

    func testDefaultConfigurationState() {
        let engine = CaptureEngine()
        XCTAssertEqual(engine.currentAspectRatioValue(), .sixteenNine)
        XCTAssertEqual(engine.currentVideoResolution, .hd1080p)
        XCTAssertEqual(engine.currentVideoFrameRate, .fps30)
        XCTAssertEqual(engine.currentPhotoFormat, .jpeg)
        XCTAssertEqual(engine.currentHDRMode, .off)
        XCTAssertFalse(engine.desiredTorchOn)
    }

    func testSetAspectRatioUpdatesStateAndNotifies() async {
        let engine = CaptureEngine()
        var notified = false
        engine.onStatusChanged = { notified = true }

        let result = await engine.setAspectRatio(.oneOne)

        XCTAssertEqual(result, .oneOne)
        XCTAssertEqual(engine.currentAspectRatioValue(), .oneOne)
        XCTAssertTrue(notified)
    }

    func testSetPhotoQualityJPEGUpdatesStateAndNotifies() async {
        let engine = CaptureEngine()
        var notified = false
        engine.onStatusChanged = { notified = true }

        // The JPEG path does not consult the photo output's codecs, so it is
        // reachable without a running capture session.
        let result = await engine.setPhotoQuality(format: .jpeg, hdrMode: .on)

        XCTAssertEqual(result?.0, .jpeg)
        XCTAssertEqual(result?.1, .on)
        XCTAssertEqual(engine.currentPhotoFormat, .jpeg)
        XCTAssertEqual(engine.currentHDRMode, .on)
        XCTAssertTrue(notified)
    }

    func testClearTorchIntentKeepsIntentOff() {
        let engine = CaptureEngine()
        engine.clearTorchIntent()
        XCTAssertFalse(engine.desiredTorchOn)
    }
}

// TEMPORARY device probe — not for commit.
@available(iOS 16.0, *)
final class StillResolutionProbe: XCTestCase, AVCapturePhotoCaptureDelegate {
    private var done: XCTestExpectation?
    private var result = ""

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let d = photo.resolvedSettings.photoDimensions
        var px = "?"
        if let data = photo.fileDataRepresentation(), let img = UIImage(data: data)?.cgImage {
            px = "\(img.width)x\(img.height) \(data.count / 1024)KB"
        }
        result = "resolved=\(d.width)x\(d.height) file=\(px) err=\(String(describing: error))"
        done?.fulfill()
    }

    private func shoot(_ output: AVCapturePhotoOutput, _ settings: AVCapturePhotoSettings) -> String {
        done = expectation(description: "photo")
        output.capturePhoto(with: settings, delegate: self)
        wait(for: [done!], timeout: 15)
        return result
    }

    private func dims(_ f: AVCaptureDevice.Format) -> String {
        let v = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
        let sub = CMFormatDescriptionGetMediaSubType(f.formatDescription)
        let fourcc = String(bytes: [UInt8(sub >> 24 & 255), UInt8(sub >> 16 & 255), UInt8(sub >> 8 & 255), UInt8(sub & 255)], encoding: .ascii) ?? "?"
        let fps = f.videoSupportedFrameRateRanges.map { $0.maxFrameRate }.max() ?? 0
        let stills = f.supportedMaxPhotoDimensions.map { "\($0.width)x\($0.height)" }.joined(separator: ",")
        return "video=\(v.width)x\(v.height) \(fourcc) fps<=\(Int(fps)) stills=[\(stills)]"
    }

    func testProbeStillResolution() throws {
        print("PROBE auth=\(AVCaptureDevice.authorizationStatus(for: .video).rawValue)")
        let device = CaptureEngine().preferredCamera(for: .back) ?? AVCaptureDevice.default(for: .video)!
        print("PROBE device=\(device.localizedName) type=\(device.deviceType.rawValue)")
        for preset in [AVCaptureSession.Preset.high, .hd1920x1080, .hd4K3840x2160, .photo] {
            let session = AVCaptureSession()
            session.beginConfiguration()
            session.sessionPreset = preset
            session.addInput(try AVCaptureDeviceInput(device: device))
            session.addOutput(AVCaptureVideoDataOutput())
            let output = AVCapturePhotoOutput()
            output.isHighResolutionCaptureEnabled = true
            output.maxPhotoQualityPrioritization = .quality
            session.addOutput(output)
            session.commitConfiguration()
            session.startRunning()
            Thread.sleep(forTimeInterval: 1.5)
            print("PROBE [\(preset.rawValue)] active: \(dims(device.activeFormat))")

            // What the App Store build does today.
            let today = AVCapturePhotoSettings()
            today.isHighResolutionPhotoEnabled = true
            today.photoQualityPrioritization = .balanced
            print("PROBE [\(preset.rawValue)] today:   \(shoot(output, today))")

            // Ask for the biggest still this format allows.
            if let big = device.activeFormat.supportedMaxPhotoDimensions.max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
                output.maxPhotoDimensions = big
                let s = AVCapturePhotoSettings()
                s.maxPhotoDimensions = big
                s.photoQualityPrioritization = .balanced
                print("PROBE [\(preset.rawValue)] maxDims: \(shoot(output, s))")
            }
            session.stopRunning()
        }
        let active = CMVideoFormatDescriptionGetDimensions(device.formats[0].formatDescription)
        _ = active
        print("PROBE --- all formats ---")
        for (i, f) in device.formats.enumerated() { print("PROBE fmt\(i) \(dims(f))") }
    }
}
