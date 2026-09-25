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
        XCTAssertEqual(bias.stops.count, 13, "⅓ stops across ±2")
        XCTAssertEqual(bias.majorStops, [-2, -1, 0, 1, 2])

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

    /// A magnetic track (zoom) only pulls a value that is near a detent.
    func testMagneticTrackSnapsToNearbyDetentOnly() {
        let track = RulerTrack(min: 1.0 / 8000, max: 1, stops: [1.0 / 125, 1.0 / 60])
        XCTAssertEqual(track.settled(1.0 / 124), 1.0 / 125)
        let midway = track.value(atPosition: (track.position(for: 1.0 / 125) + track.position(for: 1.0 / 60)) / 2)
        XCTAssertEqual(track.settled(midway), midway, "midway between stops stays free")
    }

    /// Exposure rulers click like a dial: every value lands on a ⅓ stop,
    /// wherever the finger stops.
    func testSteppedTrackAlwaysLandsOnADetent() {
        let shutter = ExposureRulerKind.shutter.track(exposure)
        let iso = ExposureRulerKind.iso.track(exposure)
        XCTAssertEqual(shutter.detents, .stepped)
        XCTAssertEqual(shutter.settled(1.0 / 110), pow(2, -20.0 / 3), accuracy: 1e-12)
        XCTAssertEqual(ExposureRulerKind.shutter.label(shutter.settled(1.0 / 110)), "1/100")
        XCTAssertEqual(ExposureRulerKind.shutter.label(shutter.settled(1.0 / 85)), "1/80")
        XCTAssertEqual(ExposureRulerKind.iso.label(iso.settled(460)), "ISO 500")
        XCTAssertEqual(ExposureRulerKind.bias.track(exposure).settled(0.2), 1.0 / 3)
    }

    /// The clicks come from the range the camera reports, not from a list:
    /// a camera that goes past 1/8000 s or ISO 10000 has clicks out there.
    func testDialDetentsComeFromTheCamerasRange() {
        let fast = RulerTrack.dial(min: 1.0 / 24000, max: 1, anchor: ExposureStops.shutterAnchor)
        let names = fast.stops.map(ExposureRulerKind.shutter.label)
        XCTAssertEqual(names.first, "1/24000", "the camera's own end reads as exactly what it is")
        XCTAssertTrue(names.contains("1/16000"))
        XCTAssertTrue(names.contains("1/12800"))
        XCTAssertEqual(names.last, "1s")

        let bright = RulerTrack.dial(min: 50, max: 12800, anchor: ExposureStops.isoAnchor)
        let isoNames = bright.stops.map(ExposureRulerKind.iso.label)
        XCTAssertEqual(isoNames.suffix(4), ["ISO 6400", "ISO 8000", "ISO 10000", "ISO 12800"])
        XCTAssertEqual(bright.majorStops.map(ExposureRulerKind.iso.label),
                       ["ISO 50", "ISO 100", "ISO 200", "ISO 400", "ISO 800", "ISO 1600", "ISO 3200",
                        "ISO 6400", "ISO 12800"], "full stops are the tall ticks")
    }

    /// A camera whose range ends off the grid still reaches its ends, and
    /// an end a hair from a detent does not add a second click.
    func testSteppedTrackKeepsTheCamerasEnds() {
        let odd = RulerTrack.dial(min: 34, max: 2176, anchor: ExposureStops.isoAnchor)
        XCTAssertEqual(odd.stops.first, 34, "a fifth of a stop below the first click: its own click")
        XCTAssertEqual(ExposureRulerKind.iso.label(odd.stops.first ?? 0), "ISO 34", "never named as ISO 32")
        XCTAssertEqual(ExposureRulerKind.iso.label(odd.stops.last ?? 0), "ISO 2000",
                       "an eighth of a stop past the last click: one click, not two")
        let nearDetent = RulerTrack.dial(min: 38, max: 3200, anchor: ExposureStops.isoAnchor)
        XCTAssertEqual(ExposureRulerKind.iso.label(nearDetent.stops.first ?? 0), "ISO 40")
        let exact = RulerTrack.dial(min: 25, max: 3200, anchor: ExposureStops.isoAnchor)
        XCTAssertEqual(exact.stops.filter { $0 < 30 }, [25], "an end on a detent is one click, not two")
    }

    /// VoiceOver moves one detent per swipe on a stepped track.
    func testSteppingMovesOneDetent() {
        let iso = ExposureRulerKind.iso.track(exposure)
        XCTAssertEqual(ExposureRulerKind.iso.label(iso.stepping(400, by: 1)), "ISO 500")
        XCTAssertEqual(ExposureRulerKind.iso.label(iso.stepping(400, by: -1)), "ISO 320")
        XCTAssertEqual(iso.stepping(3200, by: 1), 3200, "the end holds")
    }

    /// The thumb waits for a report at the asked-for spot, within a
    /// hundredth of the track, and ignores reports for older asks.
    func testMatchesIsAHundredthOfTheTrack() {
        let iso = ExposureRulerKind.iso.track(exposure)
        XCTAssertTrue(iso.matches(400, 400.4), "a device's float ISO is still the ask")
        XCTAssertFalse(iso.matches(400, 320), "a report one detent behind is an older ask")
    }

    /// Stepped rulers draw one tick per detent, the full stops tall; zoom
    /// keeps its even grid.
    func testTicksFollowTheDetents() {
        let bias = ExposureRulerKind.bias.track(exposure)
        let marks = RulerTicks.marks(for: bias, gridCount: 41)
        XCTAssertEqual(marks.count, 13)
        XCTAssertEqual(marks.filter(\.isMajor).count, 5)
        XCTAssertEqual(marks.first?.position, 0)
        XCTAssertEqual(marks.last?.position, 1)

        let zoom = ZoomScale(stops: [1, 2, 6], maxZoomFactor: 10, wideAngleZoomFactor: 2).track
        let zoomMarks = RulerTicks.marks(for: zoom, gridCount: 41)
        XCTAssertEqual(zoomMarks.count, 41)
        XCTAssertEqual(zoomMarks.filter(\.isMajor).count, 3, "one tall tick per lens")
        XCTAssertTrue(RulerTicks.marks(for: RulerTrack(min: 1, max: 1, stops: []), gridCount: 41).isEmpty)
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
        let track = RulerTrack.dial(min: 1.0 / 500, max: 1.0 / 30, anchor: ExposureStops.shutterAnchor)
        XCTAssertEqual(ExposureRulerKind.shutter.label(track.stops.first ?? 0), "1/500")
        XCTAssertEqual(ExposureRulerKind.shutter.label(track.stops.last ?? 0), "1/30")
    }

    func testLabelsSpeakPhotography() {
        XCTAssertEqual(ExposureStops.shutterLabel(1.0 / 125), "1/125")
        XCTAssertEqual(ExposureStops.shutterLabel(0.5), "0.5s")
        XCTAssertEqual(ExposureStops.shutterLabel(1.0 / 4), "1/4")
        XCTAssertEqual(ExposureStops.shutterLabel(0.3), "0.3s")
        XCTAssertEqual(ExposureStops.shutterLabel(1.0 / 13), "1/13")
        XCTAssertEqual(ExposureStops.shutterLabel(1.0 / 128), "1/125", "the click on 2⁻⁷ s carries its name")
        XCTAssertEqual(ExposureStops.shutterLabel(1.0 / 64), "1/60")
        XCTAssertEqual(ExposureStops.isoLabel(100 * pow(2, 1.0 / 3)), "ISO 125")
        XCTAssertEqual(ExposureStops.isoLabel(287), "ISO 287", "off the grid: the camera's own value")
        XCTAssertEqual(ExposureStops.biasLabel(-5.0 / 3), "−1.7 EV")
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

    // MARK: - Queued exposure

    /// What the director folds a queued exposure and a newer ask into.
    func testCoalescingKeepsTheNewestAndBothManualComponents() {
        let cases: [(queued: ExposureIntent, newer: ExposureIntent, expected: ExposureIntent)] = [
            (.manual(durationSeconds: 0.01, iso: 0), .manual(durationSeconds: 0, iso: 800),
             .manual(durationSeconds: 0.01, iso: 800)),
            (.manual(durationSeconds: 0.01, iso: 400), .manual(durationSeconds: 0.02, iso: 0),
             .manual(durationSeconds: 0.02, iso: 400)),
            (.manual(durationSeconds: 0.01, iso: 400), .auto(bias: 0), .auto(bias: 0)),
            (.auto(bias: 1), .auto(bias: -1), .auto(bias: -1)),
            (.auto(bias: 1), .manual(durationSeconds: 0, iso: 0), .manual(durationSeconds: 0, iso: 0))
        ]
        for (queued, newer, expected) in cases {
            XCTAssertEqual(queued.coalesced(with: newer), expected, "\(queued) then \(newer)")
        }
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
