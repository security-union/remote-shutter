//
//  ControlStateTests.swift
//  RemoteShutterTests
//
//  The pure core of the v11 control plane: the `absorb` fold, and the
//  derivations remotes render (`zoomScale`, capability = presence). No wire,
//  no engine — this is the maths every consumer trusts.
//

import XCTest
@testable import RemoteShutter

final class ControlStateTests: XCTestCase {

    private func snapshot(seq: UInt64,
                          minZoom: CGFloat = 1.0,
                          maxZoom: CGFloat = 10.0,
                          stops: [CGFloat] = [1.0, 2.0, 6.0],
                          wide: CGFloat = 2.0,
                          exposure: ExposureState? = nil,
                          cinematic: CinematicState? = nil) -> ControlState {
        ControlState(seq: seq,
                     zoomFactor: 1.0,
                     minZoom: minZoom, maxZoom: maxZoom,
                     zoomStops: stops, wideAngleZoomFactor: wide,
                     exposure: exposure, cinematic: cinematic)
    }

    // MARK: - absorb: the one write

    func testAbsorbTakesTheFirstSnapshotWhenNothingStored() {
        let incoming = snapshot(seq: 5)
        XCTAssertEqual(ControlState.absorb(nil, incoming), incoming)
    }

    func testAbsorbKeepsTheNewerSnapshot() {
        let old = snapshot(seq: 5, maxZoom: 10)
        let new = snapshot(seq: 6, maxZoom: 3)
        XCTAssertEqual(ControlState.absorb(old, new), new)
    }

    func testAbsorbDropsAStaleSnapshot() {
        let current = snapshot(seq: 9, maxZoom: 3)
        let stale = snapshot(seq: 4, maxZoom: 10)
        XCTAssertEqual(ControlState.absorb(current, stale), current,
                       "a delayed/reordered older snapshot must never overwrite fresher truth")
    }

    func testAbsorbPrefersIncomingOnEqualSeq() {
        // Equal seq means "same generation, re-sent" — take the incoming copy,
        // never a wedge that could ignore a re-push.
        let current = snapshot(seq: 7, maxZoom: 10)
        let resent = snapshot(seq: 7, maxZoom: 3)
        XCTAssertEqual(ControlState.absorb(current, resent), resent)
    }

    // MARK: - zoomScale derivation (Cinematic narrows; display cap)

    func testZoomScaleFloorNarrowsStopsUnderCinematic() {
        // Cinematic restricts zoom to [3, 6]; stops below the floor drop out,
        // so the pill can never offer a factor the camera would reject.
        let scale = snapshot(seq: 1, minZoom: 3, maxZoom: 6, stops: [1.0, 2.0, 6.0], wide: 2.0).zoomScale
        XCTAssertEqual(scale.minZoom, 3)
        XCTAssertFalse(scale.stops.contains(1.0), "the 1× stop is below the Cinematic floor")
        XCTAssertFalse(scale.stops.contains(2.0), "the 2× stop is below the Cinematic floor")
        XCTAssertTrue(scale.stops.contains(6.0))
    }

    func testZoomScaleWideRangeKeepsEveryStop() {
        let scale = snapshot(seq: 1, minZoom: 1, maxZoom: 10, stops: [1.0, 2.0, 6.0], wide: 2.0).zoomScale
        XCTAssertEqual(scale.minZoom, 1)
        XCTAssertEqual(Set(scale.stops), Set([1.0, 2.0, 6.0]))
    }

    func testZoomScaleCapsRunawayMaxAtFiveTimesWide() {
        // Display zoom tops out at 5× the wide-angle reference (hardware 2.0),
        // so a huge digital-zoom ceiling never leaks into the pill.
        let scale = snapshot(seq: 1, minZoom: 1, maxZoom: 100, stops: [1.0, 2.0], wide: 2.0).zoomScale
        XCTAssertEqual(scale.maxZoom, ZoomScale.displayCapped(100, wideAngle: 2.0))
        XCTAssertEqual(scale.maxZoom, 10)
    }

    // MARK: - capability = presence

    func testCapabilityIsPresence() {
        let none = snapshot(seq: 1)
        XCTAssertFalse(none.supportsManualExposure)
        XCTAssertFalse(none.supportsCinematicVideo)

        let exposure = ExposureState(mode: .auto, durationSeconds: 1.0 / 120, iso: 64,
                                     minDurationSeconds: 1.0 / 8000, maxDurationSeconds: 1,
                                     minISO: 32, maxISO: 3200)
        let cinematic = CinematicState(enabled: false, simulatedAperture: 2.0,
                                       minSimulatedAperture: 1.4, maxSimulatedAperture: 16,
                                       defaultSimulatedAperture: 2.0, apertureLocked: false,
                                       notEnoughLight: false)
        let full = snapshot(seq: 2, exposure: exposure, cinematic: cinematic)
        XCTAssertTrue(full.supportsManualExposure)
        XCTAssertTrue(full.supportsCinematicVideo)
    }

    // MARK: - refusal messaging

    func testRefusalMessageAppendsDetailWhenPresent() {
        XCTAssertEqual(ControlRefusalReason.photoMode.message(detail: nil),
                       "Switch to video mode for Cinematic")
        let withDetail = ControlRefusalReason.sessionRefused.message(detail: "Back Camera; 1920x1080")
        XCTAssertTrue(withDetail.contains("Back Camera; 1920x1080"))
        XCTAssertTrue(withDetail.hasPrefix("The camera refused that setting"))
        XCTAssertEqual(ControlRefusalReason.sessionRefused.message(detail: ""),
                       "The camera refused that setting", "an empty detail adds no parens")
    }
}
