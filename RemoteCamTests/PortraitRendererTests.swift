//
//  PortraitRendererTests.swift
//  RemoteShutterTests
//
//  Copyright © 2026 Security Union. All rights reserved.
//

import XCTest
@testable import RemoteShutter

final class PortraitRendererTests: XCTestCase {
    /// The camera reports this range to the director, so it must be a real
    /// f-number range with the default inside it.
    func testApertureRangeHoldsTheDefault() {
        let range = PortraitRenderer.apertureRange
        XCTAssertGreaterThan(range.lowerBound, 0)
        XCTAssertTrue(range.contains(PortraitRenderer.defaultAperture))
    }

    func testClampedApertureStaysInRange() {
        let range = PortraitRenderer.apertureRange
        XCTAssertEqual(PortraitRenderer.clampedAperture(0.1), range.lowerBound)
        XCTAssertEqual(PortraitRenderer.clampedAperture(100), range.upperBound)
        XCTAssertEqual(PortraitRenderer.clampedAperture(4.5), 4.5)
        XCTAssertEqual(PortraitRenderer.clampedAperture(.nan), PortraitRenderer.defaultAperture)
    }
}
