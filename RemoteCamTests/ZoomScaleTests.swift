import XCTest
@testable import RemoteShutter

final class ZoomScaleTests: XCTestCase {

    /// Single-lens iPhone / Mac webcam: wide angle is hardware 1.0.
    private let singleLens = ZoomScale(stops: [1.0], maxZoomFactor: 5.0, wideAngleZoomFactor: 1.0)

    /// Triple-camera iPhone: ultra-wide is the base, so the wide angle the user calls
    /// "1×" is hardware 2.0, and 5× display is hardware 10.0.
    private let tripleCamera = ZoomScale(stops: [1.0, 2.0, 6.0], maxZoomFactor: 10.0, wideAngleZoomFactor: 2.0)

    // MARK: - Clamping

    func testClampsToRange() {
        XCTAssertEqual(singleLens.clamped(0.1), 1.0)
        XCTAssertEqual(singleLens.clamped(99.0), 5.0)
        XCTAssertEqual(singleLens.clamped(2.5), 2.5)
    }

    func testClampRejectsNonFiniteInput() {
        XCTAssertEqual(singleLens.clamped(.nan), 1.0)
        XCTAssertEqual(singleLens.clamped(.infinity), 1.0)
    }

    // MARK: - Display units

    func testDisplayFactorIsRelativeToWideAngle() {
        // The whole point of the conversion: hardware 2.0 is what the user calls "1×".
        XCTAssertEqual(tripleCamera.displayFactor(forHardware: 2.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(tripleCamera.displayFactor(forHardware: 1.0), 0.5, accuracy: 0.0001)
        XCTAssertEqual(tripleCamera.displayFactor(forHardware: 10.0), 5.0, accuracy: 0.0001)
    }

    func testDisplayStopsMatchTheLensesTheUserSees() {
        XCTAssertEqual(tripleCamera.displayStops, [0.5, 1.0, 3.0])
    }

    func testLabelDropsTrailingZeroAndKeepsOneDecimal() {
        XCTAssertEqual(tripleCamera.label(forHardware: 2.0), "1×")
        XCTAssertEqual(tripleCamera.label(forHardware: 1.0), "0.5×")
        XCTAssertEqual(tripleCamera.label(forHardware: 4.8), "2.4×")
        XCTAssertEqual(tripleCamera.label(forHardware: 2.0, glyph: "x"), "1x")
    }

    // MARK: - Ruler geometry

    func testPositionSpansTheFullTrack() {
        XCTAssertEqual(singleLens.position(forHardware: 1.0), 0.0, accuracy: 0.0001)
        XCTAssertEqual(singleLens.position(forHardware: 5.0), 1.0, accuracy: 0.0001)
    }

    func testPositionIsLogarithmic() {
        // The geometric midpoint of 1…5 is sqrt(5) ≈ 2.236, not the arithmetic mean of 3.
        XCTAssertEqual(singleLens.position(forHardware: CGFloat(5.0).squareRoot()), 0.5, accuracy: 0.0001)
    }

    func testPositionRoundTrips() {
        for hardware in stride(from: 1.0, through: 10.0, by: 0.25) {
            let position = tripleCamera.position(forHardware: CGFloat(hardware))
            XCTAssertEqual(tripleCamera.hardwareFactor(atPosition: position),
                           CGFloat(hardware),
                           accuracy: 0.0001,
                           "round trip failed at \(hardware)")
        }
    }

    func testPositionClampsOutOfRangeInput() {
        XCTAssertEqual(singleLens.position(forHardware: 99.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(singleLens.position(forHardware: 0.01), 0.0, accuracy: 0.0001)
        XCTAssertEqual(singleLens.hardwareFactor(atPosition: 2.0), 5.0)
        XCTAssertEqual(singleLens.hardwareFactor(atPosition: -1.0), 1.0)
    }

    // MARK: - Detents

    func testSnapsToNearbyStop() {
        // Just off the hardware-6.0 stop — close enough to pull in.
        XCTAssertEqual(tripleCamera.snappedToStop(6.05), 6.0)
    }

    func testDoesNotSnapWhenFarFromAnyStop() {
        // Midway between the 2.0 and 6.0 stops: the user meant this value.
        XCTAssertEqual(tripleCamera.snappedToStop(3.5), 3.5, accuracy: 0.0001)
    }

    func testSnapToleranceIsUniformAcrossTheRange() {
        // Same fractional distance from a stop at each end must snap the same way,
        // even though the absolute zoom deltas differ by 6x.
        let lowSide = tripleCamera.hardwareFactor(
            atPosition: tripleCamera.position(forHardware: 1.0) + 0.02)
        let highSide = tripleCamera.hardwareFactor(
            atPosition: tripleCamera.position(forHardware: 6.0) + 0.02)
        XCTAssertEqual(tripleCamera.snappedToStop(lowSide), 1.0)
        XCTAssertEqual(tripleCamera.snappedToStop(highSide), 6.0)
    }

    // MARK: - Degenerate ranges

    func testDegenerateRangeIsFlaggedAndNeverDividesByZero() {
        // maxZoomFactor below the low stop: what the view model holds before the first
        // SetZoomResp arrives. Must not produce NaN or trap.
        let collapsed = ZoomScale(stops: [1.0], maxZoomFactor: 1.0, wideAngleZoomFactor: 1.0)
        XCTAssertTrue(collapsed.isDegenerate)
        XCTAssertEqual(collapsed.position(forHardware: 1.0), 0.0)
        XCTAssertEqual(collapsed.hardwareFactor(atPosition: 0.5), 1.0)
        XCTAssertEqual(collapsed.snappedToStop(1.0), 1.0)
        XCTAssertFalse(collapsed.position(forHardware: 1.0).isNaN)
    }

    func testMaxBelowMinCollapsesRatherThanInverting() {
        let inverted = ZoomScale(stops: [2.0], maxZoomFactor: 1.0, wideAngleZoomFactor: 1.0)
        XCTAssertEqual(inverted.minZoom, 2.0)
        XCTAssertEqual(inverted.maxZoom, 2.0)
        XCTAssertTrue(inverted.isDegenerate)
    }

    func testEmptyStopsFallBackToUnityRatherThanCrashing() {
        let empty = ZoomScale(stops: [], maxZoomFactor: 5.0, wideAngleZoomFactor: 1.0)
        XCTAssertEqual(empty.stops, [1.0])
        XCTAssertEqual(empty.minZoom, 1.0)
    }

    func testUnreachableStopsAreNotOfferedAsDetents() {
        // A 6.0 stop is meaningless when the camera caps at 3.0.
        let capped = ZoomScale(stops: [1.0, 2.0, 6.0], maxZoomFactor: 3.0, wideAngleZoomFactor: 1.0)
        XCTAssertEqual(capped.stops, [1.0, 2.0])
    }

    func testStopsAreSortedAndSanitised() {
        let messy = ZoomScale(stops: [6.0, 1.0, -2.0, .nan, 2.0],
                              maxZoomFactor: 10.0,
                              wideAngleZoomFactor: 1.0)
        XCTAssertEqual(messy.stops, [1.0, 2.0, 6.0])
    }

    // MARK: - Pinch parity

    /// The exact math that lived inline in MonitorView's MagnificationGesture before it
    /// moved into ZoomScale. Pins the refactor: iPhone pinch must not change feel.
    private func legacyPinch(start: CGFloat,
                             magnification: CGFloat,
                             minZoom: CGFloat,
                             maxZoom: CGFloat) -> CGFloat {
        let sensitivity: CGFloat = 0.6
        let logStart = log2(start)
        let logDelta = log2(magnification) * sensitivity
        let logNew = logStart + logDelta
        let clamped = max(log2(minZoom), min(log2(maxZoom), logNew))
        return pow(2, clamped)
    }

    func testPinchMatchesTheLegacyInlineMath() {
        for start in [1.0, 1.5, 2.0, 4.0, 9.5] as [CGFloat] {
            for magnification in [0.25, 0.5, 0.9, 1.0, 1.1, 2.0, 4.0] as [CGFloat] {
                XCTAssertEqual(
                    tripleCamera.pinched(from: start, magnification: magnification),
                    legacyPinch(start: start, magnification: magnification, minZoom: 1.0, maxZoom: 10.0),
                    accuracy: 0.0001,
                    "pinch drifted at start=\(start) magnification=\(magnification)")
            }
        }
    }

    func testPinchIsIdentityAtUnitMagnification() {
        XCTAssertEqual(tripleCamera.pinched(from: 4.0, magnification: 1.0), 4.0, accuracy: 0.0001)
    }

    func testPinchClampsAtBothEnds() {
        XCTAssertEqual(tripleCamera.pinched(from: 9.5, magnification: 8.0), 10.0)
        XCTAssertEqual(tripleCamera.pinched(from: 1.1, magnification: 0.01), 1.0)
    }

    func testPinchRejectsNonFiniteMagnification() {
        // MagnificationGesture can emit 0 on the first event of a fast pinch.
        XCTAssertEqual(tripleCamera.pinched(from: 3.0, magnification: 0.0), 3.0)
        XCTAssertEqual(tripleCamera.pinched(from: 3.0, magnification: .nan), 3.0)
    }
}
