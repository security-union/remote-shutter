import SwiftUI
import XCTest
@testable import RemoteShutter

/// The exposure rulers: their ranges and labels from the camera's state, the
/// shared ruler math they ride on (`RulerTrack`, which `ZoomScale` also
/// wraps), the value → command mapping, and the send throttle.
final class ExposureScaleTests: XCTestCase {

    private let exposure = ExposureState(
        mode: .manual, bias: 0.3, minBias: -8, maxBias: 8, targetOffset: -0.5, supportsManual: true,
        durationSeconds: 1.0 / 125, iso: 400,
        minDurationSeconds: 1.0 / 8000, maxDurationSeconds: 1, minISO: 32, maxISO: 3200,
        maxFrameDurationSeconds: 1.0 / 30)

    func testRangeAndDetentsComeFromTheCamera() {
        let shutter = ExposureRulerKind.shutter.track(exposure)
        XCTAssertEqual(shutter.minValue, 1.0 / 8000)
        XCTAssertEqual(shutter.maxValue, 1)
        XCTAssertEqual(shutter.stops.first, 1.0 / 8000)
        XCTAssertEqual(shutter.stops.last, 1)
        XCTAssertFalse(shutter.isDegenerate)

        let iso = ExposureRulerKind.iso.track(exposure)
        XCTAssertEqual(iso.stops.first, 32)
        XCTAssertEqual(iso.stops.last, 3200)
    }

    /// The EV ruler spans ±2 like Apple's dial even when the device reports
    /// ±8, and shrinks to the device's range when that is narrower.
    func testBiasRulerIsLinearAndCappedAtTwoStops() {
        let bias = ExposureRulerKind.bias.track(exposure)
        XCTAssertEqual(bias.mapping, .linear)
        XCTAssertEqual(bias.minValue, -2)
        XCTAssertEqual(bias.maxValue, 2)
        XCTAssertEqual(bias.position(for: 0), 0.5)
        XCTAssertEqual(bias.value(atPosition: 0.75), 1)
        XCTAssertEqual(bias.stops, [-2, -1, 0, 1, 2])

        var narrow = exposure
        narrow.minBias = -1
        narrow.maxBias = 1
        XCTAssertEqual(ExposureRulerKind.bias.track(narrow).maxValue, 1)
    }

    /// Log track: one stop is the same travel anywhere, ends are exact.
    func testLogTrackIsLogarithmicWithExactEnds() {
        let iso = RulerTrack(min: 32, max: 3200, stops: [])
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
        let shutter = ExposureRulerKind.shutter.track(exposure)
        XCTAssertEqual(shutter.snappedToStop(1.0 / 124), 1.0 / 125)
        let midway = shutter.value(atPosition: (shutter.position(for: 1.0 / 125) + shutter.position(for: 1.0 / 60)) / 2)
        XCTAssertEqual(shutter.snappedToStop(midway), midway, "midway between stops stays free")
    }

    /// No range (a camera that reports none) or a fixed value draws nothing —
    /// the rule `ZoomScale.isDegenerate` already applies to zoom.
    func testDegenerateRanges() {
        XCTAssertTrue(RulerTrack(min: 100, max: 100, stops: []).isDegenerate)
        XCTAssertTrue(RulerTrack(min: .nan, max: 100, stops: []).isDegenerate)
        XCTAssertTrue(RulerTrack(min: 0, max: 100, stops: []).isDegenerate, "log of zero is not a position")
        XCTAssertTrue(RulerTrack(mapping: .linear, min: 0, max: 0, stops: []).isDegenerate)
        XCTAssertFalse(RulerTrack(mapping: .linear, min: -2, max: 2, stops: []).isDegenerate,
                       "a linear track may cross zero")
        var noManual = exposure
        noManual.minDurationSeconds = 0
        noManual.maxDurationSeconds = 0
        XCTAssertTrue(ExposureRulerKind.shutter.track(noManual).isDegenerate)
    }

    /// Detents outside the camera's range are not offered.
    func testStopsOutsideTheRangeAreDropped() {
        let track = RulerTrack(min: 1.0 / 500, max: 1.0 / 30, stops: ExposureStops.shutterSeconds)
        XCTAssertEqual(track.stops.first, 1.0 / 500)
        XCTAssertEqual(track.stops.last, 1.0 / 30)
    }

    func testLabelsSpeakPhotography() {
        XCTAssertEqual(ExposureStops.shutterLabel(1.0 / 125), "1/125")
        XCTAssertEqual(ExposureStops.shutterLabel(0.5), "0.5s")
        XCTAssertEqual(ExposureStops.shutterLabel(1), "1s")
        XCTAssertEqual(ExposureStops.shutterLabel(0), "—")
        XCTAssertEqual(ExposureStops.isoLabel(399.6), "ISO 400")
        XCTAssertEqual(ExposureStops.biasLabel(0), "0 EV")
        XCTAssertEqual(ExposureStops.biasLabel(0.33), "+0.3 EV")
        XCTAssertEqual(ExposureStops.biasLabel(-1), "−1 EV")
        XCTAssertEqual(ExposureRulerKind.iso.label(400), "ISO 400")
    }

    /// Dragging one ruler never disturbs the other: each sends only its own
    /// component, 0 = keep the camera's current value.
    func testRulerValuesBecomeSingleComponentIntents() {
        XCTAssertEqual(ExposureRulerKind.shutter.intent(for: 1.0 / 60), .manual(durationSeconds: 1.0 / 60, iso: 0))
        XCTAssertEqual(ExposureRulerKind.iso.intent(for: 800), .manual(durationSeconds: 0, iso: 800))
        XCTAssertEqual(ExposureRulerKind.bias.intent(for: -1.5), .auto(bias: -1.5))
    }

    /// Auto shows the EV ruler; Manual the shutter and ISO pair; a bias-only
    /// camera never shows the pair.
    func testOfferedRulersFollowTheModeAndTheDevice() {
        XCTAssertEqual(ExposureRulerKind.offered(by: exposure), [.shutter, .iso])
        var auto = exposure
        auto.mode = .auto
        XCTAssertEqual(ExposureRulerKind.offered(by: auto), [.bias])
        var biasOnly = exposure
        biasOnly.supportsManual = false
        XCTAssertEqual(ExposureRulerKind.offered(by: biasOnly), [.bias])
    }

    /// The zoom pill's math is the same track, so extracting it changed
    /// nothing the zoom tests pin.
    func testZoomScaleRidesTheSameTrack() {
        let scale = ZoomScale(stops: [1, 2, 6], maxZoomFactor: 10, wideAngleZoomFactor: 2)
        XCTAssertEqual(scale.track.mapping, .log2)
        XCTAssertEqual(scale.position(forHardware: 1), 0)
        XCTAssertEqual(scale.hardwareFactor(atPosition: 1), 10)
        XCTAssertEqual(scale.snappedToStop(2.02), 2)
    }

    /// Every ruler gets the same track and the same reserved end slot, so
    /// the capsules are one width and a thumb travels the same distance on
    /// each. A reset never costs its ruler any track.
    func testEveryRulerSharesOneTrackAndOneEndSlot() {
        for axis in [Axis.horizontal, .vertical] {
            let lengths = ExposureRulerKind.allCases.map { _ in ExposureRulerMetrics.track(axis: axis) }
            XCTAssertEqual(Set(lengths).count, 1, "one track length per axis")
        }
        XCTAssertGreaterThan(ExposureRulerMetrics.track(axis: .horizontal), 0)
        XCTAssertEqual(ExposureRulerMetrics.endSlot, PillCircleButton<Text>.diameter,
                       "the slot is exactly one button wide, filled or not")
        XCTAssertEqual(ExposureRulerKind.allCases.filter(\.hasReset), [.bias],
                       "EV is the only ruler with a value worth going back to")
    }

    // MARK: - Send throttle

    func testFirstValueSendsImmediately() {
        var sent: [Double] = []
        let sender = ThrottledValueSender(interval: 60) { sent.append($0) }
        sender.submit(0.5)
        XCTAssertEqual(sent, [0.5])
    }

    func testTrailingEdgeDeliversTheLastValueOnly() {
        var sent: [Double] = []
        let sender = ThrottledValueSender(interval: 0.05) { sent.append($0) }
        sender.submit(1)
        sender.submit(2)
        sender.submit(3)
        XCTAssertEqual(sent, [1], "the burst is held")
        let landed = expectation(description: "trailing")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { landed.fulfill() }
        wait(for: [landed], timeout: 1)
        XCTAssertEqual(sent, [1, 3], "then only the final position lands")
    }
}
