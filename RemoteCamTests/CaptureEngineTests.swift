import XCTest
import AVFoundation
@testable import RemoteShutter

/// Exercises the pure, session-free surface of `CaptureEngine`. These paths
/// need no `AVCaptureDevice`, so they run on the simulator.
final class CaptureEngineTests: XCTestCase {

    // MARK: - previewOutputDimensions

    func testPreviewSizeFor4KIsExact16By9AndEven() {
        let dims = CaptureEngine.previewOutputDimensions(sourceWidth: 3840, sourceHeight: 2160,
                                                         portrait: false, maxLongEdge: 1200)
        XCTAssertEqual(dims?.width, 1184)
        XCTAssertEqual(dims?.height, 666)
    }

    func testPreviewSizeSwapsForPortrait() {
        let dims = CaptureEngine.previewOutputDimensions(sourceWidth: 1920, sourceHeight: 1080,
                                                         portrait: true, maxLongEdge: 1200)
        XCTAssertEqual(dims?.width, 666)
        XCTAssertEqual(dims?.height, 1184)
    }

    func testPreviewSizeForFullSensorPhotoFormat() {
        let dims = CaptureEngine.previewOutputDimensions(sourceWidth: 4032, sourceHeight: 3024,
                                                         portrait: false, maxLongEdge: 1200)
        XCTAssertEqual(dims?.width, 1200)
        XCTAssertEqual(dims?.height, 900)
    }

    func testNoPreviewSizeWhenTheSourceIsAlreadyPreviewSized() {
        XCTAssertNil(CaptureEngine.previewOutputDimensions(sourceWidth: 640, sourceHeight: 480,
                                                           portrait: false, maxLongEdge: 1200))
        XCTAssertNil(CaptureEngine.previewOutputDimensions(sourceWidth: 0, sourceHeight: 1080,
                                                           portrait: false, maxLongEdge: 1200))
    }

    func testPreviewSizeKeepsTheSourceAspectExactlyForEveryCommonFormat() {
        let formats = [(3840, 2160), (1920, 1080), (1280, 720), (4032, 3024), (2048, 1536), (1440, 1080), (3024, 3024)]
        for (w, h) in formats {
            guard let dims = CaptureEngine.previewOutputDimensions(sourceWidth: w, sourceHeight: h,
                                                                   portrait: false, maxLongEdge: 1200) else {
                continue // already preview-sized: no second output
            }
            XCTAssertEqual(dims.width * h, dims.height * w, "\(w)x\(h) → \(dims) is not the same ratio")
            XCTAssertEqual(dims.width % 2, 0); XCTAssertEqual(dims.height % 2, 0)
            XCTAssertLessThanOrEqual(max(dims.width, dims.height), 1200)
            XCTAssertLessThan(dims.width * dims.height, w * h)
        }
    }

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
