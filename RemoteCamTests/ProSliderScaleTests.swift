import XCTest
@testable import RemoteShutter

/// The pro sliders: their ranges and labels (`ProSliderScale`), the shared
/// ruler math they ride on (`LogTrack`, which `ZoomScale` also wraps), and
/// the value → command mapping (`ProSliderKind.intent`).
final class ProSliderScaleTests: XCTestCase {

    private let exposure = ExposureState(
        mode: .manual, durationSeconds: 1.0 / 125, iso: 400,
        minDurationSeconds: 1.0 / 8000, maxDurationSeconds: 1, minISO: 32, maxISO: 3200)

    func testRangeAndDetentsComeFromTheCamera() {
        let shutter = ProSliderScale.shutter(exposure).track
        XCTAssertEqual(shutter.minValue, 1.0 / 8000)
        XCTAssertEqual(shutter.maxValue, 1)
        XCTAssertEqual(shutter.stops.first, 1.0 / 8000)
        XCTAssertEqual(shutter.stops.last, 1)
        XCTAssertFalse(shutter.isDegenerate)

        let iso = ProSliderScale.iso(exposure).track
        XCTAssertEqual(iso.stops.first, 32)
        XCTAssertEqual(iso.stops.last, 3200)
    }

    /// Log track: one stop is the same travel anywhere, ends are exact.
    func testTrackIsLogarithmicWithExactEnds() {
        let iso = LogTrack(min: 32, max: 3200, stops: [])
        XCTAssertEqual(iso.position(for: 32), 0)
        XCTAssertEqual(iso.position(for: 3200), 1)
        // 32 → 320 is the same log distance as 320 → 3200.
        XCTAssertEqual(iso.position(for: 320), 0.5, accuracy: 1e-9)
        XCTAssertEqual(iso.value(atPosition: 0), 32)
        XCTAssertEqual(iso.value(atPosition: 1), 3200)
        XCTAssertEqual(iso.value(atPosition: 2), 3200, "past the end clamps")
        XCTAssertEqual(iso.value(atPosition: 0.5), 320, accuracy: 1e-6)
    }

    func testSnapsToNearbyDetentOnly() {
        let shutter = ProSliderScale.shutter(exposure).track
        XCTAssertEqual(shutter.snappedToStop(1.0 / 124), 1.0 / 125)
        let midway = shutter.value(atPosition: (shutter.position(for: 1.0 / 125) + shutter.position(for: 1.0 / 60)) / 2)
        XCTAssertEqual(shutter.snappedToStop(midway), midway, "midway between stops stays free")
    }

    /// No range (before the first echo) or a fixed value draws nothing —
    /// the rule `ZoomScale.isDegenerate` already applies to zoom.
    func testDegenerateRanges() {
        let fixed = CinematicState(enabled: true, simulatedAperture: 0, minSimulatedAperture: 0,
                                   maxSimulatedAperture: 0, defaultSimulatedAperture: 0,
                                   apertureLocked: false, notEnoughLight: false)
        XCTAssertTrue(ProSliderScale.aperture(fixed).track.isDegenerate)
        XCTAssertEqual(ProSliderScale.aperture(fixed).track.position(for: 2.8), 0)
        XCTAssertTrue(LogTrack(min: 100, max: 100, stops: []).isDegenerate)
        XCTAssertTrue(LogTrack(min: .nan, max: 100, stops: []).isDegenerate)
        XCTAssertTrue(LogTrack(min: 0, max: 100, stops: []).isDegenerate, "log of zero is not a position")
    }

    /// Detents outside the camera's range are not offered.
    func testStopsOutsideTheRangeAreDropped() {
        let track = LogTrack(min: 1.0 / 500, max: 1.0 / 30, stops: ProStops.allShutterSeconds)
        XCTAssertEqual(track.stops.first, 1.0 / 500)
        XCTAssertEqual(track.stops.last, 1.0 / 30)
    }

    func testLabelsSpeakPhotography() {
        XCTAssertEqual(ProSliderScale.shutter(exposure).label(1.0 / 125), "1/125")
        XCTAssertEqual(ProSliderScale.iso(exposure).label(400), "400", "the pill's title already says ISO")
        let phone = CinematicState(enabled: true, simulatedAperture: 2.8, minSimulatedAperture: 1.4,
                                   maxSimulatedAperture: 16, defaultSimulatedAperture: 2,
                                   apertureLocked: false, notEnoughLight: false)
        XCTAssertEqual(ProSliderScale.aperture(phone).label(2.8), "f/2.8")
    }

    /// Dragging one dial locks only that component (0 = keep the other as
    /// the camera has it); the aperture slider rides Cinematic on.
    func testSliderValuesBecomeSingleComponentIntents() {
        XCTAssertEqual(ProSliderKind.shutter.intent(for: 0.5), .exposure(.manual(durationSeconds: 0.5, iso: 0)))
        XCTAssertEqual(ProSliderKind.iso.intent(for: 800), .exposure(.manual(durationSeconds: 0, iso: 800)))
        XCTAssertEqual(ProSliderKind.aperture.intent(for: 4), .cinematic(.on(aperture: 4)))
    }

    func testEveryKindHasATile() {
        XCTAssertEqual(ProSliderKind.allCases.map(\.tile), [.shutter, .iso, .aperture])
    }
}
