//
//  ClockOffsetEstimatorTests.swift
//  RemoteShutterTests
//
//  Created by Dario Lencina on 2026.
//  Copyright © 2026 Security Union. All rights reserved.
//

import XCTest
@testable import RemoteShutter

final class ClockOffsetEstimatorTests: XCTestCase {

    func testSymmetricExchangeRecoversExactOffset() {
        // Camera runs 500ms ahead. Ping takes 10ms each way: sent at t0=1000,
        // received at director-time 1010 = camera clock 1510, pong back at
        // t3=1020. Symmetric latency → the rtt/2 midpoint is exact.
        var estimator = ClockOffsetEstimator()
        let sample = estimator.recordExchange(
            t0Millis: 1000, cameraClockMillis: 1510, t3Millis: 1020)
        XCTAssertEqual(sample?.offsetMillis, 500)
        XCTAssertEqual(sample?.roundTripMillis, 20)
    }

    func testAsymmetricLatencyErrorIsBoundedByHalfRoundTrip() {
        // Worst case: all 20ms on the outbound leg. Receive happens at
        // director-time 1020 (camera 1520) but the midpoint guess is 1010 —
        // estimate 510, true offset 500. |error| = rtt/2.
        var estimator = ClockOffsetEstimator()
        let sample = estimator.recordExchange(
            t0Millis: 1000, cameraClockMillis: 1520, t3Millis: 1020)
        XCTAssertEqual(sample?.offsetMillis, 510)
    }

    func testNegativeOffsetWhenCameraRunsBehind() {
        var estimator = ClockOffsetEstimator()
        let sample = estimator.recordExchange(
            t0Millis: 10_000, cameraClockMillis: 8_010, t3Millis: 10_020)
        XCTAssertEqual(sample?.offsetMillis, -2_000)
    }

    func testBestPrefersMinimumRoundTrip() {
        var estimator = ClockOffsetEstimator()
        // A slow, queued exchange with a skewed midpoint...
        estimator.recordExchange(t0Millis: 1000, cameraClockMillis: 1900, t3Millis: 1400)
        // ...must not outvote a clean 8ms exchange.
        estimator.recordExchange(t0Millis: 2000, cameraClockMillis: 2504, t3Millis: 2008)
        XCTAssertEqual(estimator.best?.roundTripMillis, 8)
        XCTAssertEqual(estimator.best?.offsetMillis, 500)
    }

    func testWindowSlidesAndDropsOldest() {
        var estimator = ClockOffsetEstimator()
        // Fill the window with a fast-but-old sample first.
        estimator.recordExchange(t0Millis: 0, cameraClockMillis: 501, t3Millis: 2)
        for i in 0..<ClockOffsetEstimator.windowSize {
            let t0 = UInt64(1000 + i * 100)
            estimator.recordExchange(
                t0Millis: t0, cameraClockMillis: t0 + 510, t3Millis: t0 + 20)
        }
        XCTAssertEqual(estimator.samples.count, ClockOffsetEstimator.windowSize)
        // The 2ms sample fell out of the window; best is now a 20ms exchange.
        XCTAssertEqual(estimator.best?.roundTripMillis, 20)
    }

    func testRejectsPongBeforePing() {
        var estimator = ClockOffsetEstimator()
        XCTAssertNil(estimator.recordExchange(
            t0Millis: 5000, cameraClockMillis: 5000, t3Millis: 4000))
        XCTAssertTrue(estimator.samples.isEmpty)
    }

    func testResetEmptiesTheWindow() {
        var estimator = ClockOffsetEstimator()
        estimator.recordExchange(t0Millis: 1000, cameraClockMillis: 1500, t3Millis: 1010)
        estimator.reset()
        XCTAssertNil(estimator.best)
        XCTAssertTrue(estimator.samples.isEmpty)
    }
}
