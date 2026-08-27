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

    // MARK: - Cinematic never hides the zoom pill

    /// Apple narrows zoom under Cinematic (videoMin/MaxZoomFactorForCinematicVideo)
    /// but never removes it — and neither may the derivation. For every
    /// plausible narrowed range the engine can emit (its guard ensures
    /// max > min within the device range), the derived scale must stay
    /// non-degenerate, because a degenerate scale is exactly what hides the
    /// pill. This pins the field report "zoom disappears when Cinematic is on".
    func testCinematicNarrowedRangesNeverDegenerateTheZoomScale() {
        // (stops, wide, cineMin, cineMax) — hardware factors.
        let cases: [(stops: [CGFloat], wide: CGFloat, min: CGFloat, max: CGFloat, label: String)] = [
            ([1, 2], 2, 2, 6, "iPhone 14 DualWide: Cinematic pinned to the wide lens"),
            ([1, 2], 2, 1, 3, "DualWide: narrowed from both ends"),
            ([1, 2, 6], 2, 2, 9, "Triple: ultra-wide and tele stops dropped"),
            ([1, 2], 2, 3, 6, "floor above every lens stop: the floor is the one detent"),
            ([1], 1, 1, 2, "single-lens: tiny cinematic headroom"),
        ]
        for c in cases {
            let state = ControlState(seq: 1, zoomFactor: c.min,
                                     minZoom: c.min, maxZoom: c.max,
                                     zoomStops: c.stops, wideAngleZoomFactor: c.wide)
            let scale = state.zoomScale
            XCTAssertFalse(scale.isDegenerate, "\(c.label): a degenerate scale hides the pill")
            XCTAssertGreaterThanOrEqual(scale.minZoom, c.min, c.label)
            XCTAssertFalse(scale.stops.isEmpty, "\(c.label): the ruler needs at least one detent")
            XCTAssertTrue(scale.stops.allSatisfy { $0 >= scale.minZoom && $0 <= scale.maxZoom },
                          "\(c.label): every offered detent must be reachable")
        }
    }

    /// Disabling Cinematic restores the device range: the same derivation
    /// widens back — no stored value to un-stick.
    func testDisablingCinematicRestoresTheFullScale() {
        let narrowed = ControlState(seq: 1, minZoom: 2, maxZoom: 6,
                                    zoomStops: [1, 2], wideAngleZoomFactor: 2)
        let restored = ControlState(seq: 2, minZoom: 1, maxZoom: 10,
                                    zoomStops: [1, 2], wideAngleZoomFactor: 2)
        XCTAssertEqual(narrowed.zoomScale.stops, [2], "ultra-wide is out of reach under Cinematic")
        XCTAssertEqual(ControlState.absorb(narrowed, restored).zoomScale.stops, [1, 2],
                       "the next snapshot brings the ultra-wide stop back")
    }
}
