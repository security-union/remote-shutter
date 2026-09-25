//
//  CinematicPolicyTests.swift
//  RemoteShutterTests
//
//  Table tests for the Cinematic decisions. The device inventory in these
//  tables is what an iPhone 14 measured (CinematicProbeTests, 2026-09-25):
//  back Dual Wide and front TrueDepth have Cinematic formats, the plain
//  cameras don't.
//

import XCTest
@testable import RemoteShutter

final class CinematicPolicyTests: XCTestCase {

    private typealias Device = CinematicPolicy.DeviceCandidate
    private typealias Format = CinematicPolicy.FormatCandidate

    private let backDualWide = Device(id: "dualWide", kind: .dualWide, side: .back, hasCinematicFormats: true)
    private let backWide = Device(id: "backWide", kind: .wide, side: .back, hasCinematicFormats: false)
    private let backUltraWide = Device(id: "ultra", kind: .other, side: .back, hasCinematicFormats: false)
    private let frontWide = Device(id: "frontWide", kind: .wide, side: .front, hasCinematicFormats: false)
    private let trueDepth = Device(id: "trueDepth", kind: .trueDepth, side: .front, hasCinematicFormats: true)

    // MARK: - Device choice

    func testChosenCameraWithCinematicFormatsRunsItself() {
        XCTAssertEqual(CinematicPolicy.device(for: backDualWide, among: [backWide, backDualWide]), backDualWide)
    }

    func testFrontWideHopsToTrueDepth() {
        XCTAssertEqual(CinematicPolicy.device(for: frontWide, among: [frontWide, trueDepth, backDualWide]), trueDepth)
    }

    func testHopStaysOnTheSameSide() {
        XCTAssertNil(CinematicPolicy.device(for: frontWide, among: [frontWide, backDualWide]))
    }

    func testPreferenceOrderPicksDualWideOverOthers() {
        let triple = Device(id: "triple", kind: .triple, side: .back, hasCinematicFormats: true)
        let chosen = CinematicPolicy.device(for: backWide, among: [triple, backDualWide, backUltraWide])
        XCTAssertEqual(chosen, backDualWide)
    }

    func testNoCinematicAnywhereIsNil() {
        XCTAssertNil(CinematicPolicy.device(for: backWide, among: [backWide, backUltraWide]))
    }

    // MARK: - Format choice

    private let formats = [
        Format(width: 1920, height: 1080, isEightBit: false, minFPS: 24, maxFPS: 30),  // x420
        Format(width: 1920, height: 1080, isEightBit: true, minFPS: 24, maxFPS: 30),   // 420v
        Format(width: 3840, height: 2160, isEightBit: true, minFPS: 24, maxFPS: 30),
        Format(width: 3840, height: 2160, isEightBit: false, minFPS: 24, maxFPS: 30),
    ]

    func testFormatMatchesTheQualityResolutionAndPrefersEightBit() {
        XCTAssertEqual(CinematicPolicy.formatIndex(formats, resolution: .hd1080p), 1)
        XCTAssertEqual(CinematicPolicy.formatIndex(formats, resolution: .uhd4k), 2)
    }

    func testFormatFallsBackTo1080p() {
        let only1080 = Array(formats.prefix(2))
        XCTAssertEqual(CinematicPolicy.formatIndex(only1080, resolution: .uhd4k), 1)
    }

    func testFormatFallsBackToAnythingAndNilWhenEmpty() {
        let odd = [Format(width: 1280, height: 720, isEightBit: false, minFPS: 30, maxFPS: 30)]
        XCTAssertEqual(CinematicPolicy.formatIndex(odd, resolution: .hd1080p), 0)
        XCTAssertNil(CinematicPolicy.formatIndex([], resolution: .hd1080p))
    }

    // MARK: - Qualities

    func testQualitiesMapResolutionsAndTheCinematicFrameRates() {
        let qualities = CinematicPolicy.qualities(formats)
        XCTAssertEqual(qualities[.hd1080p], [.fps24, .fps30])
        XCTAssertEqual(qualities[.uhd4k], [.fps24, .fps30])
    }

    func testQualitiesSkipUnknownSizes() {
        let qualities = CinematicPolicy.qualities([Format(width: 1280, height: 720, isEightBit: true, minFPS: 24, maxFPS: 30)])
        XCTAssertTrue(qualities.isEmpty)
    }

    func testQualityFittingKeepsAnAllowedSetting() {
        let fitted = CinematicPolicy.quality(fitting: .uhd4k, .fps24, in: CinematicPolicy.qualities(formats))
        XCTAssertEqual(fitted?.0, .uhd4k)
        XCTAssertEqual(fitted?.1, .fps24)
    }

    func testQualityFittingDropsSixtyToThirty() {
        let fitted = CinematicPolicy.quality(fitting: .hd1080p, .fps60, in: CinematicPolicy.qualities(formats))
        XCTAssertEqual(fitted?.0, .hd1080p)
        XCTAssertEqual(fitted?.1, .fps30)
    }

    func testQualityFittingFallsBackTo1080p() {
        let fitted = CinematicPolicy.quality(fitting: .uhd4k, .fps30, in: [.hd1080p: [.fps24, .fps30]])
        XCTAssertEqual(fitted?.0, .hd1080p)
        XCTAssertEqual(fitted?.1, .fps30)
        XCTAssertNil(CinematicPolicy.quality(fitting: .hd1080p, .fps30, in: [:]))
    }

    func testDirectorQualityGateFollowsTheState() {
        var state = CinematicState(enabled: true, output: .baked, aperture: 2.8, minAperture: 2, maxAperture: 16,
                                   defaultAperture: 2.8, qualities: [.hd1080p: [.fps24, .fps30]])
        XCTAssertTrue(CinematicPolicy.allows(resolution: .hd1080p, frameRate: .fps30, in: state))
        XCTAssertFalse(CinematicPolicy.allows(resolution: .hd1080p, frameRate: .fps60, in: state))
        XCTAssertFalse(CinematicPolicy.allows(resolution: .uhd4k, frameRate: .fps30, in: state))
        state.enabled = false
        XCTAssertTrue(CinematicPolicy.allows(resolution: .uhd4k, frameRate: .fps60, in: state))
    }

    // MARK: - Refusals

    private func refusal(_ intent: CinematicIntent, video: Bool = true, recording: Bool = false,
                         aspect: AspectRatio = .sixteenNine, supported: Bool = true) -> CinematicPolicy.Refusal? {
        CinematicPolicy.refusal(for: intent, isVideoMode: video, isRecording: recording,
                                aspect: aspect, supported: supported, deviceName: "Front Camera")
    }

    func testRefusalTable() {
        let on = CinematicIntent(enabled: true)
        let off = CinematicIntent(enabled: false)
        let editable = CinematicIntent(enabled: true, output: .editable)
        XCTAssertNil(refusal(on))
        XCTAssertEqual(refusal(on, recording: true), .recording)
        XCTAssertEqual(refusal(off, recording: true), .recording)
        XCTAssertNil(refusal(off, video: false, supported: false), "turning off is always allowed outside a take")
        XCTAssertEqual(refusal(on, video: false), .photoMode)
        XCTAssertEqual(refusal(on, supported: false), .unsupported(device: "Front Camera"))
        XCTAssertEqual(refusal(editable, aspect: .fourThree), .editableNeedsSixteenNine)
        XCTAssertNil(refusal(on, aspect: .fourThree), "baked Cinematic takes any aspect")
        XCTAssertNil(refusal(editable))
    }

    func testRefusalMessagesNameTheCause() {
        XCTAssertTrue(CinematicPolicy.Refusal.unsupported(device: "Front Camera").message.contains("Front Camera"))
        XCTAssertFalse(CinematicPolicy.Refusal.photoMode.message.isEmpty)
    }

    func testAspectRule() {
        XCTAssertTrue(CinematicPolicy.allows(aspect: .oneOne, output: .baked))
        XCTAssertTrue(CinematicPolicy.allows(aspect: .sixteenNine, output: .editable))
        XCTAssertFalse(CinematicPolicy.allows(aspect: .oneOne, output: .editable))
    }

    // MARK: - Effect, exposure, aperture

    func testEffectNeedsIntentVideoModeAndSupport() {
        XCTAssertTrue(CinematicPolicy.isEffective(CinematicIntent(enabled: true), isVideoMode: true, supported: true))
        XCTAssertFalse(CinematicPolicy.isEffective(CinematicIntent(enabled: true), isVideoMode: false, supported: true))
        XCTAssertFalse(CinematicPolicy.isEffective(CinematicIntent(enabled: true), isVideoMode: true, supported: false))
        XCTAssertFalse(CinematicPolicy.isEffective(CinematicIntent(enabled: false), isVideoMode: true, supported: true))
    }

    func testCinematicEndsManualAndKeepsBias() {
        XCTAssertEqual(CinematicPolicy.exposureIntent(.manual(durationSeconds: 0.01, iso: 400), cinematicOn: true),
                       .auto(bias: 0))
        XCTAssertEqual(CinematicPolicy.exposureIntent(.auto(bias: 0.7), cinematicOn: true), .auto(bias: 0.7))
        XCTAssertEqual(CinematicPolicy.exposureIntent(.manual(durationSeconds: 0.01, iso: 400), cinematicOn: false),
                       .manual(durationSeconds: 0.01, iso: 400))
    }

    func testApertureClampsKeepsAndDefaults() {
        XCTAssertEqual(CinematicPolicy.aperture(requested: 1.4, current: 2.8, defaultValue: 2.8, min: 2, max: 16), 2)
        XCTAssertEqual(CinematicPolicy.aperture(requested: 22, current: 2.8, defaultValue: 2.8, min: 2, max: 16), 16)
        XCTAssertEqual(CinematicPolicy.aperture(requested: 0, current: 5.6, defaultValue: 2.8, min: 2, max: 16), 5.6)
        XCTAssertEqual(CinematicPolicy.aperture(requested: 0, current: 0, defaultValue: 4.5, min: 2, max: 16), 4.5)
    }
}
