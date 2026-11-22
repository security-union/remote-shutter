//
//  DeviceNamePreferenceTests.swift
//  RemoteShutterTests
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import XCTest
@testable import RemoteShutter

final class DeviceNamePreferenceTests: XCTestCase {

    private var saved: String?

    override func setUp() {
        super.setUp()
        saved = UserDefaults.standard.string(forKey: DeviceNamePreference.key)
        UserDefaults.standard.removeObject(forKey: DeviceNamePreference.key)
    }

    override func tearDown() {
        if let saved {
            UserDefaults.standard.set(saved, forKey: DeviceNamePreference.key)
        } else {
            UserDefaults.standard.removeObject(forKey: DeviceNamePreference.key)
        }
        super.tearDown()
    }

    func testUnsetMeansTheSystemName() {
        XCTAssertEqual(DeviceNamePreference.custom, "")
        XCTAssertEqual(DeviceNamePreference.effectiveName(custom: "", systemName: "iPhone"), "iPhone")
    }

    func testACustomNameWins() {
        XCTAssertEqual(DeviceNamePreference.effectiveName(custom: "Drums", systemName: "iPhone"), "Drums")
    }

    func testSpacesOnlyFallsBackToTheSystemName() {
        XCTAssertEqual(DeviceNamePreference.effectiveName(custom: "   ", systemName: "iPad"), "iPad")
    }

    func testNamesAreTrimmedAndCapped() {
        XCTAssertEqual(DeviceNamePreference.sanitized("  Stage Left \n"), "Stage Left")
        let long = String(repeating: "a", count: 40)
        XCTAssertEqual(DeviceNamePreference.sanitized(long).count, DeviceNamePreference.maxLength)
    }

    func testStoringIsSanitizedAndClearingRemovesIt() {
        DeviceNamePreference.custom = "  Drums  "
        XCTAssertEqual(DeviceNamePreference.custom, "Drums")
        DeviceNamePreference.custom = "  "
        XCTAssertNil(UserDefaults.standard.object(forKey: DeviceNamePreference.key))
    }
}
