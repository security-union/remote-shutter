import XCTest
import AVFoundation
@testable import RemoteShutter

/// Exercises the pure, session-free surface of `CaptureEngine`. These paths
/// need no `AVCaptureDevice`, so they run on the simulator.
final class CaptureEngineTests: XCTestCase {

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
