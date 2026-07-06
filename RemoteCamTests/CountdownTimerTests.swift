//
//  CountdownTimerTests.swift
//  RemoteShutterTests
//
//  Copyright © 2026 Security Union. All rights reserved.
//

import XCTest
@testable import RemoteShutter

class CountdownTimerTests: XCTestCase {

    func testZeroDurationCompletesSynchronously() {
        let timer = CountdownTimer()
        var completed = false
        timer.start(duration: 0, onTick: { _ in
            XCTFail("tick should not fire for zero duration")
        }, onCompletion: { _ in
            completed = true
        })
        XCTAssertTrue(completed)
    }

    func testCountdownTicksThenCompletes() {
        let timer = CountdownTimer()
        var ticks: [Int] = []
        let completion = expectation(description: "completion")
        timer.start(duration: 3, onTick: { timer in
            ticks.append(timer.timeRemaining)
        }, onCompletion: { timer in
            XCTAssertEqual(timer.timeRemaining, 0)
            completion.fulfill()
        })
        wait(for: [completion], timeout: 5)
        XCTAssertEqual(ticks, [2, 1])
    }

    func testCancelStopsCountdown() {
        let timer = CountdownTimer()
        timer.start(duration: 2, onTick: { _ in
            XCTFail("tick should not fire after cancel")
        }, onCompletion: { _ in
            XCTFail("completion should not fire after cancel")
        })
        timer.cancel()

        // Wait past the first tick to confirm nothing fires.
        let quiet = expectation(description: "no callbacks")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            quiet.fulfill()
        }
        wait(for: [quiet], timeout: 3)
    }
}
