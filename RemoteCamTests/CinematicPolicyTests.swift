import XCTest
@testable import RemoteShutter

final class CinematicPolicyTests: XCTestCase {

    /// An iPhone that supports Cinematic video with an adjustable aperture.
    private let phone = CinematicFacts(
        supported: true, enabled: false,
        minAperture: 1.4, maxAperture: 16, defaultAperture: 2.0, currentAperture: 2.0)

    private func resolve(_ intent: CinematicIntent, facts: CinematicFacts,
                         recording: Bool = false, video: Bool = true) -> CinematicPlan {
        CinematicPolicy.resolve(intent, facts: facts, isRecording: recording, isVideoMode: video)
    }

    func testEnableOnSupportedVideoCamera() {
        XCTAssertEqual(resolve(.on(aperture: 2.8), facts: phone), .enable(aperture: 2.8))
        XCTAssertEqual(resolve(.on(aperture: nil), facts: phone), .enable(aperture: nil))
    }

    func testApertureClampsIntoRange() {
        XCTAssertEqual(resolve(.on(aperture: 0.95), facts: phone), .enable(aperture: 1.4))
        XCTAssertEqual(resolve(.on(aperture: 22), facts: phone), .enable(aperture: 16))
    }

    func testFixedApertureDeviceIgnoresRequestedValue() {
        var fixed = phone
        fixed.minAperture = 0
        fixed.maxAperture = 0
        XCTAssertEqual(resolve(.on(aperture: 2.8), facts: fixed), .enable(aperture: nil))
    }

    func testPhotoModeRejects() {
        XCTAssertEqual(resolve(.on(aperture: 2.8), facts: phone, video: false), .rejected(.photoMode))
    }

    func testUnsupportedRejectsInEveryMode() {
        var mac = phone
        mac.supported = false
        XCTAssertEqual(resolve(.on(aperture: 2.8), facts: mac), .rejected(.unsupported))
        XCTAssertEqual(resolve(.on(aperture: 2.8), facts: mac, video: false), .rejected(.unsupported))
    }

    /// Apple throws on aperture/enable changes mid-take: the policy rejects
    /// them so the engine never makes the call.
    func testRecordingLocksEverything() {
        var enabledPhone = phone
        enabledPhone.enabled = true
        XCTAssertEqual(resolve(.on(aperture: 4.0), facts: enabledPhone, recording: true), .rejected(.recording))
        XCTAssertEqual(resolve(.off, facts: enabledPhone, recording: true), .rejected(.recording))
        XCTAssertEqual(resolve(.on(aperture: 4.0), facts: phone, recording: true), .rejected(.recording))
    }

    func testApertureOnlyWhenAlreadyEnabled() {
        var enabledPhone = phone
        enabledPhone.enabled = true
        XCTAssertEqual(resolve(.on(aperture: 4.0), facts: enabledPhone), .apertureOnly(4.0))
        // Same aperture, same state: nothing to do.
        XCTAssertEqual(resolve(.on(aperture: 2.0), facts: enabledPhone), .noop)
        XCTAssertEqual(resolve(.on(aperture: nil), facts: enabledPhone), .noop)
    }

    func testDisable() {
        var enabledPhone = phone
        enabledPhone.enabled = true
        XCTAssertEqual(resolve(.off, facts: enabledPhone), .disable)
        XCTAssertEqual(resolve(.off, facts: phone), .noop)
    }

    // MARK: - Dial stops

    func testShutterStopsFilterToRange() {
        let stops = ProDialStops.shutterStops(min: 1.0 / 10_000, max: 1.0 / 3)
        XCTAssertEqual(stops.first, 1.0 / 8000)
        XCTAssertEqual(stops.last, 1.0 / 3)
        XCTAssertFalse(stops.contains(0.5))
    }

    func testISOStopsFilterToRange() {
        let stops = ProDialStops.isoStops(min: 32, max: 3200)
        XCTAssertEqual(stops.first, 32)
        XCTAssertEqual(stops.last, 3200)
    }

    func testApertureStopsEmptyForFixedAperture() {
        XCTAssertTrue(ProDialStops.apertureStops(min: 0, max: 0).isEmpty)
        XCTAssertEqual(ProDialStops.apertureStops(min: 1.4, max: 16).first, 1.4)
    }

    func testNearestIndexSnapsToClosestDetent() {
        let stops: [Double] = [1.0 / 250, 1.0 / 125, 1.0 / 60]
        XCTAssertEqual(ProDialStops.nearestIndex(of: 1.0 / 120, in: stops), 1)
        XCTAssertNil(ProDialStops.nearestIndex(of: 1.0, in: [Double]()))
    }

    func testLabels() {
        XCTAssertEqual(ProDialStops.shutterLabel(1.0 / 125), "1/125")
        XCTAssertEqual(ProDialStops.shutterLabel(0.5), "0.5s")
        XCTAssertEqual(ProDialStops.shutterLabel(1.0), "1s")
        XCTAssertEqual(ProDialStops.isoLabel(400), "ISO 400")
        XCTAssertEqual(ProDialStops.apertureLabel(2.8), "f/2.8")
        XCTAssertEqual(ProDialStops.apertureLabel(16), "f/16")
    }
}
