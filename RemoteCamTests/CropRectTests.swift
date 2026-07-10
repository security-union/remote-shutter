import XCTest
@testable import RemoteShutter

final class CropRectTests: XCTestCase {

    typealias CR = CaptureEngine

    // MARK: - Helpers

    /// Asserts the crop rect produces the correct aspect ratio.
    private func assertRatioMatches(
        sourceWidth: CGFloat, sourceHeight: CGFloat,
        aspectRatio: AspectRatio, file: StaticString = #file, line: UInt = #line
    ) {
        guard let rect = CR.cropRect(sourceWidth: sourceWidth, sourceHeight: sourceHeight, aspectRatio: aspectRatio) else {
            XCTFail("Expected a crop rect, got nil", file: file, line: line)
            return
        }
        let isLandscape = sourceWidth > sourceHeight
        let expectedRatio = isLandscape ? aspectRatio.widthToHeight : (1.0 / aspectRatio.widthToHeight)
        let actualRatio = rect.width / rect.height
        XCTAssertEqual(actualRatio, expectedRatio, accuracy: 0.01,
                       "Crop rect \(rect) ratio \(actualRatio) != expected \(expectedRatio)",
                       file: file, line: line)
    }

    /// Asserts the crop rect is within source bounds.
    private func assertWithinBounds(
        sourceWidth: CGFloat, sourceHeight: CGFloat,
        aspectRatio: AspectRatio, file: StaticString = #file, line: UInt = #line
    ) {
        guard let rect = CR.cropRect(sourceWidth: sourceWidth, sourceHeight: sourceHeight, aspectRatio: aspectRatio) else {
            return // nil is valid (already matches)
        }
        XCTAssertGreaterThanOrEqual(rect.origin.x, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(rect.origin.y, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(rect.origin.x + rect.width, sourceWidth + 0.01, file: file, line: line)
        XCTAssertLessThanOrEqual(rect.origin.y + rect.height, sourceHeight + 0.01, file: file, line: line)
    }

    /// Asserts the crop rect is centered within the source.
    private func assertCentered(
        sourceWidth: CGFloat, sourceHeight: CGFloat,
        aspectRatio: AspectRatio, file: StaticString = #file, line: UInt = #line
    ) {
        guard let rect = CR.cropRect(sourceWidth: sourceWidth, sourceHeight: sourceHeight, aspectRatio: aspectRatio) else {
            return
        }
        let leftMargin = rect.origin.x
        let rightMargin = sourceWidth - (rect.origin.x + rect.width)
        let topMargin = rect.origin.y
        let bottomMargin = sourceHeight - (rect.origin.y + rect.height)
        XCTAssertEqual(leftMargin, rightMargin, accuracy: 0.01,
                       "Not horizontally centered: left=\(leftMargin) right=\(rightMargin)", file: file, line: line)
        XCTAssertEqual(topMargin, bottomMargin, accuracy: 0.01,
                       "Not vertically centered: top=\(topMargin) bottom=\(bottomMargin)", file: file, line: line)
    }

    // MARK: - Output ratio is correct

    func testOutputRatio_landscape1080p_allRatios() {
        assertRatioMatches(sourceWidth: 1920, sourceHeight: 1080, aspectRatio: .fourThree)
        assertRatioMatches(sourceWidth: 1920, sourceHeight: 1080, aspectRatio: .oneOne)
    }

    func testOutputRatio_portrait1080p_allRatios() {
        assertRatioMatches(sourceWidth: 1080, sourceHeight: 1920, aspectRatio: .fourThree)
        assertRatioMatches(sourceWidth: 1080, sourceHeight: 1920, aspectRatio: .oneOne)
    }

    func testOutputRatio_landscape4K_allRatios() {
        assertRatioMatches(sourceWidth: 3840, sourceHeight: 2160, aspectRatio: .fourThree)
        assertRatioMatches(sourceWidth: 3840, sourceHeight: 2160, aspectRatio: .oneOne)
    }

    // MARK: - Crop stays within source bounds

    func testWithinBounds_allCombinations() {
        let sources: [(CGFloat, CGFloat)] = [
            (1920, 1080), (1080, 1920), (3840, 2160), (2160, 3840),
            (640, 480), (100, 100), (1, 1)
        ]
        for (w, h) in sources {
            for ratio in AspectRatio.selectableCases {
                assertWithinBounds(sourceWidth: w, sourceHeight: h, aspectRatio: ratio)
            }
        }
    }

    // MARK: - Crop is always centered

    func testCentered_allCombinations() {
        let sources: [(CGFloat, CGFloat)] = [
            (1920, 1080), (1080, 1920), (3840, 2160), (2160, 3840)
        ]
        for (w, h) in sources {
            for ratio in AspectRatio.selectableCases {
                assertCentered(sourceWidth: w, sourceHeight: h, aspectRatio: ratio)
            }
        }
    }

    // MARK: - Returns nil when source already matches target

    func testNil_16x9_to16x9() {
        XCTAssertNil(CR.cropRect(sourceWidth: 1920, sourceHeight: 1080, aspectRatio: .sixteenNine))
    }

    func testNil_portrait16x9_to16x9() {
        XCTAssertNil(CR.cropRect(sourceWidth: 1080, sourceHeight: 1920, aspectRatio: .sixteenNine))
    }

    func testNil_4x3_to4x3() {
        XCTAssertNil(CR.cropRect(sourceWidth: 1440, sourceHeight: 1080, aspectRatio: .fourThree))
    }

    func testNil_square_to1x1() {
        XCTAssertNil(CR.cropRect(sourceWidth: 1080, sourceHeight: 1080, aspectRatio: .oneOne))
    }

    // MARK: - Crop only reduces dimensions, never enlarges

    func testCropNeverEnlarges() {
        let sources: [(CGFloat, CGFloat)] = [
            (1920, 1080), (1080, 1920), (3840, 2160), (640, 480)
        ]
        for (w, h) in sources {
            for ratio in AspectRatio.selectableCases {
                guard let rect = CR.cropRect(sourceWidth: w, sourceHeight: h, aspectRatio: ratio) else { continue }
                XCTAssertLessThanOrEqual(rect.width, w)
                XCTAssertLessThanOrEqual(rect.height, h)
            }
        }
    }

    // MARK: - Specific dimension checks

    func testLandscape1080p_to4x3_exactDimensions() {
        let rect = CR.cropRect(sourceWidth: 1920, sourceHeight: 1080, aspectRatio: .fourThree)!
        // 1080 * (4/3) = 1440 wide, full 1080 tall
        XCTAssertEqual(rect.size, CGSize(width: 1440, height: 1080))
    }

    func testLandscape1080p_to1x1_exactDimensions() {
        let rect = CR.cropRect(sourceWidth: 1920, sourceHeight: 1080, aspectRatio: .oneOne)!
        XCTAssertEqual(rect.size, CGSize(width: 1080, height: 1080))
    }

    func testPortrait1080p_to4x3_exactDimensions() {
        let rect = CR.cropRect(sourceWidth: 1080, sourceHeight: 1920, aspectRatio: .fourThree)!
        // Portrait 4:3 → ratio 3/4 = 0.75, height = 1080 / 0.75 = 1440
        XCTAssertEqual(rect.size, CGSize(width: 1080, height: 1440))
    }

    func test4K_to1x1_exactDimensions() {
        let rect = CR.cropRect(sourceWidth: 3840, sourceHeight: 2160, aspectRatio: .oneOne)!
        XCTAssertEqual(rect.size, CGSize(width: 2160, height: 2160))
    }

    // MARK: - Unknown aspect ratio behaves like 4:3

    func testUnknown_behavesLike4x3() {
        let unknownRect = CR.cropRect(sourceWidth: 1920, sourceHeight: 1080, aspectRatio: .unknown)
        let fourThreeRect = CR.cropRect(sourceWidth: 1920, sourceHeight: 1080, aspectRatio: .fourThree)
        XCTAssertEqual(unknownRect, fourThreeRect)
    }
}
