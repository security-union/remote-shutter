//
//  RemoteShutterUITests.swift
//  RemoteShutterUITests
//
//  Created by Griffin Obeid on 9/12/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import XCTest

class RemoteShutterUITests: XCTestCase {
    
    var app: XCUIApplication!

    override func setUpWithError() throws {
        app = XCUIApplication()
        app.launch()

        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    func testAppLaunchesToPhonePicker() throws {
        let phonePickerLabel = app.staticTexts["CHOOSE 1 INVITEE"]
        XCTAssertTrue(phonePickerLabel.exists)
        app.buttons["Cancel"].tap()
        sleep(1)
        XCTAssertFalse(phonePickerLabel.exists)
    }
    
    func testConnectButton() throws {
        app.buttons["Cancel"].tap()
        app.buttons["Connect"].tap()
        let phonePickerLabel = app.staticTexts["CHOOSE 1 INVITEE"]
        sleep(1)
        XCTAssertTrue(phonePickerLabel.exists)
    }
    
    func testTapRemoteWithoutConnection() throws {
        app.buttons["Cancel"].tap()
        app.buttons["remote"].tap()
        let phonePickerLabel = app.staticTexts["CHOOSE 1 INVITEE"]
        sleep(1)
        XCTAssertTrue(phonePickerLabel.exists)
    }
    
    func testTapCameraWithoutConnection() throws {
        app.buttons["Cancel"].tap()
        app.buttons["camera"].tap()
        let phonePickerLabel = app.staticTexts["CHOOSE 1 INVITEE"]
        sleep(1)
        XCTAssertTrue(phonePickerLabel.exists)
    }
}
