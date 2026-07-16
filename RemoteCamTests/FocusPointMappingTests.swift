//
//  FocusPointMappingTests.swift
//  RemoteShutterTests
//
//  Pure geometry tests for tap-to-focus. These pin the intended math; the
//  orientation/mirroring conventions are additionally validated against real
//  hardware in CaptureIntegrationTests.
//

import XCTest
import CoreGraphics
import AVFoundation
@testable import RemoteShutter

final class FocusPointMappingTests: XCTestCase {

    private let acc: CGFloat = 0.0001

    // MARK: - normalizedImagePoint (tap -> normalized image, letterbox aware)

    func testCenterTapMapsToImageCenter() {
        let p = FocusPointMapping.normalizedImagePoint(
            tap: CGPoint(x: 50, y: 50),
            viewSize: CGSize(width: 100, height: 100),
            imageSize: CGSize(width: 100, height: 100))
        XCTAssertNotNil(p)
        XCTAssertEqual(p!.x, 0.5, accuracy: acc)
        XCTAssertEqual(p!.y, 0.5, accuracy: acc)
    }

    func testLetterboxedImageCenterTapIgnoresBars() {
        // 2:1 image in a square view -> fitted 100x50, bars of 25 top and bottom.
        let view = CGSize(width: 100, height: 100)
        let image = CGSize(width: 200, height: 100)
        let center = FocusPointMapping.normalizedImagePoint(
            tap: CGPoint(x: 50, y: 50), viewSize: view, imageSize: image)
        XCTAssertEqual(center?.x ?? -1, 0.5, accuracy: acc)
        XCTAssertEqual(center?.y ?? -1, 0.5, accuracy: acc)

        // Tap inside the image at its top edge.
        let topEdge = FocusPointMapping.normalizedImagePoint(
            tap: CGPoint(x: 50, y: 25), viewSize: view, imageSize: image)
        XCTAssertEqual(topEdge?.y ?? -1, 0.0, accuracy: acc)
    }

    func testTapInLetterboxBarReturnsNil() {
        let view = CGSize(width: 100, height: 100)
        let image = CGSize(width: 200, height: 100)   // horizontal bars at y<25 and y>75
        XCTAssertNil(FocusPointMapping.normalizedImagePoint(
            tap: CGPoint(x: 50, y: 10), viewSize: view, imageSize: image))
        XCTAssertNil(FocusPointMapping.normalizedImagePoint(
            tap: CGPoint(x: 50, y: 90), viewSize: view, imageSize: image))
    }

    func testTapInPillarboxBarReturnsNil() {
        // 1:2 image in a square view -> fitted 50x100, vertical bars at x<25 and x>75.
        let view = CGSize(width: 100, height: 100)
        let image = CGSize(width: 100, height: 200)
        XCTAssertNil(FocusPointMapping.normalizedImagePoint(
            tap: CGPoint(x: 10, y: 50), viewSize: view, imageSize: image))
        XCTAssertNil(FocusPointMapping.normalizedImagePoint(
            tap: CGPoint(x: 90, y: 50), viewSize: view, imageSize: image))
    }

    func testZeroSizesReturnNil() {
        XCTAssertNil(FocusPointMapping.normalizedImagePoint(
            tap: CGPoint(x: 1, y: 1), viewSize: .zero, imageSize: CGSize(width: 10, height: 10)))
        XCTAssertNil(FocusPointMapping.normalizedImagePoint(
            tap: CGPoint(x: 1, y: 1), viewSize: CGSize(width: 10, height: 10), imageSize: .zero))
    }

    // MARK: - devicePoint (display-normalized -> focusPointOfInterest space)

    func testLandscapeRightIsIdentity() {
        let p = FocusPointMapping.devicePoint(
            displayNormalized: CGPoint(x: 0.2, y: 0.3),
            videoOrientation: .landscapeRight, mirrored: false)
        XCTAssertEqual(p.x, 0.2, accuracy: acc)
        XCTAssertEqual(p.y, 0.3, accuracy: acc)
    }

    func testFrontMirrorFlipsX() {
        let p = FocusPointMapping.devicePoint(
            displayNormalized: CGPoint(x: 0.2, y: 0.3),
            videoOrientation: .landscapeRight, mirrored: true)
        XCTAssertEqual(p.x, 0.8, accuracy: acc)
        XCTAssertEqual(p.y, 0.3, accuracy: acc)
    }

    func testPortraitRotation() {
        let p = FocusPointMapping.devicePoint(
            displayNormalized: CGPoint(x: 0.2, y: 0.3),
            videoOrientation: .portrait, mirrored: false)
        // (px, py) -> (py, 1 - px)
        XCTAssertEqual(p.x, 0.3, accuracy: acc)
        XCTAssertEqual(p.y, 0.8, accuracy: acc)
    }

    func testPortraitUpsideDownRotation() {
        let p = FocusPointMapping.devicePoint(
            displayNormalized: CGPoint(x: 0.2, y: 0.3),
            videoOrientation: .portraitUpsideDown, mirrored: false)
        // (px, py) -> (1 - py, px)
        XCTAssertEqual(p.x, 0.7, accuracy: acc)
        XCTAssertEqual(p.y, 0.2, accuracy: acc)
    }

    func testLandscapeLeftRotation() {
        let p = FocusPointMapping.devicePoint(
            displayNormalized: CGPoint(x: 0.2, y: 0.3),
            videoOrientation: .landscapeLeft, mirrored: false)
        // (px, py) -> (1 - px, 1 - py)
        XCTAssertEqual(p.x, 0.8, accuracy: acc)
        XCTAssertEqual(p.y, 0.7, accuracy: acc)
    }

    func testOutOfRangeInputIsClamped() {
        let p = FocusPointMapping.devicePoint(
            displayNormalized: CGPoint(x: 1.5, y: -0.5),
            videoOrientation: .landscapeRight, mirrored: false)
        XCTAssertEqual(p.x, 1.0, accuracy: acc)
        XCTAssertEqual(p.y, 0.0, accuracy: acc)
    }
}
