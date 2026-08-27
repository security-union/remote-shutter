import XCTest
@testable import RemoteShutter

final class ExposurePolicyTests: XCTestCase {

    /// A typical iPhone wide camera at 30 fps.
    private let phone = ExposureFacts(
        supportsCustom: true,
        minDurationSeconds: 1.0 / 10_000,
        maxDurationSeconds: 1.0,
        minISO: 32,
        maxISO: 3200,
        maxFrameDurationSeconds: 1.0 / 30,
        currentDurationSeconds: 1.0 / 120,
        currentISO: 64)

    func testAutoIntentIsAlwaysAuto() {
        XCTAssertEqual(ExposurePolicy.resolve(.auto, facts: phone, isRecording: false), .auto)
        XCTAssertEqual(ExposurePolicy.resolve(.auto, facts: phone, isRecording: true), .auto)
        var noCustom = phone
        noCustom.supportsCustom = false
        XCTAssertEqual(ExposurePolicy.resolve(.auto, facts: noCustom, isRecording: false), .auto)
    }

    func testUnsupportedDeviceFallsBack() {
        var virtual = phone
        virtual.supportsCustom = false
        XCTAssertEqual(
            ExposurePolicy.resolve(.manual(durationSeconds: 0.01, iso: 100), facts: virtual, isRecording: false),
            .unsupported)
    }

    func testInRangeValuesPassThrough() {
        let plan = ExposurePolicy.resolve(.manual(durationSeconds: 1.0 / 250, iso: 400), facts: phone, isRecording: false)
        XCTAssertEqual(plan, .manual(durationSeconds: 1.0 / 250, iso: 400))
    }

    func testValuesClampIntoFormatRange() {
        let tooLong = ExposurePolicy.resolve(.manual(durationSeconds: 30, iso: 1_000_000), facts: phone, isRecording: false)
        XCTAssertEqual(tooLong, .manual(durationSeconds: 1.0, iso: 3200))

        let tooShort = ExposurePolicy.resolve(.manual(durationSeconds: 1e-9, iso: 1), facts: phone, isRecording: false)
        XCTAssertEqual(tooShort, .manual(durationSeconds: 1.0 / 10_000, iso: 32))
    }

    func testZeroKeepsCurrentValue() {
        let isoOnly = ExposurePolicy.resolve(.manual(durationSeconds: 0, iso: 800), facts: phone, isRecording: false)
        XCTAssertEqual(isoOnly, .manual(durationSeconds: 1.0 / 120, iso: 800))

        let shutterOnly = ExposurePolicy.resolve(.manual(durationSeconds: 0.5, iso: 0), facts: phone, isRecording: false)
        XCTAssertEqual(shutterOnly, .manual(durationSeconds: 0.5, iso: 64))
    }

    /// A long shutter while recording would lengthen the frame duration and
    /// change the clip's frame rate mid-take; the policy caps it at 1/fps.
    func testRecordingCapsShutterAtFrameDuration() {
        let recording = ExposurePolicy.resolve(.manual(durationSeconds: 0.5, iso: 100), facts: phone, isRecording: true)
        XCTAssertEqual(recording, .manual(durationSeconds: 1.0 / 30, iso: 100))

        let photo = ExposurePolicy.resolve(.manual(durationSeconds: 0.5, iso: 100), facts: phone, isRecording: false)
        XCTAssertEqual(photo, .manual(durationSeconds: 0.5, iso: 100))
    }

    /// A frame duration below the sensor's minimum shutter must not invert the
    /// range: the floor wins.
    func testRecordingCapNeverDropsBelowMinimumShutter() {
        var odd = phone
        odd.maxFrameDurationSeconds = 1.0 / 100_000
        let plan = ExposurePolicy.resolve(.manual(durationSeconds: 1.0 / 60, iso: 100), facts: odd, isRecording: true)
        XCTAssertEqual(plan, .manual(durationSeconds: 1.0 / 10_000, iso: 100))
    }

    func testUnknownFrameDurationDoesNotCap() {
        var noFPS = phone
        noFPS.maxFrameDurationSeconds = 0
        let plan = ExposurePolicy.resolve(.manual(durationSeconds: 0.5, iso: 100), facts: noFPS, isRecording: true)
        XCTAssertEqual(plan, .manual(durationSeconds: 0.5, iso: 100))
    }
}
