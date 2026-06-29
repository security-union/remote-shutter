//
//  WatchPreviewStreamerTests.swift
//  RemoteShutterTests
//
//  Back-pressure tests for the Apple Watch preview stream: at most one frame in flight,
//  the next sent only after the Watch acks the previous, and — critically — a frame
//  offered while one is in flight is never even encoded. A fake transport stands in for
//  WCSession so the protocol is exercised without any device or connectivity.
//

import XCTest

@testable import RemoteShutter

final class WatchPreviewStreamerTests: XCTestCase {

    private var queue: DispatchQueue!
    private var streamer: WatchPreviewStreamer!

    private var sent: [Data] = []
    private var encodeCount = 0

    override func setUp() {
        super.setUp()
        queue = DispatchQueue(label: "watch-preview-streamer-test")
        sent = []
        encodeCount = 0
        streamer = makeStreamer()
    }

    override func tearDown() {
        streamer = nil
        queue = nil
        super.tearDown()
    }

    private func makeStreamer(ackTimeout: TimeInterval = 1.0) -> WatchPreviewStreamer {
        WatchPreviewStreamer(queue: queue, ackTimeout: ackTimeout, send: { [weak self] jpeg in
            self?.sent.append(jpeg)
        })
    }

    /// Offers a one-byte frame on the streamer's queue (its calling contract), counting
    /// how often the encode actually runs.
    @discardableResult
    private func offer(_ tag: UInt8) -> Bool {
        var result = false
        queue.sync {
            result = streamer.offer { [weak self] in
                self?.encodeCount += 1
                return Data([tag])
            }
        }
        return result
    }

    /// Acks the in-flight frame, then flushes the queue so the re-arm lands.
    private func ack() {
        streamer.acknowledge()
        queue.sync {}
    }

    func testFirstFrameIsEncodedAndSent() {
        XCTAssertTrue(offer(1))
        XCTAssertEqual(sent, [Data([1])])
        XCTAssertEqual(encodeCount, 1)
    }

    func testFrameWhileInFlightIsNotEvenEncoded() {
        offer(1)
        XCTAssertFalse(offer(2))
        XCTAssertEqual(sent, [Data([1])], "a frame must not be sent before the previous is acked")
        XCTAssertEqual(encodeCount, 1, "a dropped frame must not be encoded — the point of lazy encoding")
    }

    func testAckReleasesTheNextFrame() {
        offer(1)
        offer(2)            // dropped, never encoded
        ack()
        XCTAssertTrue(offer(3))
        XCTAssertEqual(sent, [Data([1]), Data([3])])
        XCTAssertEqual(encodeCount, 2)
    }

    func testEachFrameNeedsItsOwnAck() {
        for tag: UInt8 in 1...3 {
            XCTAssertTrue(offer(tag))
            ack()
        }
        XCTAssertEqual(sent, [Data([1]), Data([2]), Data([3])], "one ack should release exactly one frame")
    }

    func testFailedEncodeLeavesTheStreamReady() {
        queue.sync {
            XCTAssertFalse(streamer.offer { nil })   // encode returns nil → nothing sent
        }
        XCTAssertEqual(sent, [])
        XCTAssertTrue(offer(1), "a frame that failed to encode must not consume the in-flight slot")
        XCTAssertEqual(sent, [Data([1])])
    }

    func testWatchdogReleasesTheStreamWhenAnAckIsLost() {
        streamer = makeStreamer(ackTimeout: 0.05)
        XCTAssertTrue(offer(1))
        XCTAssertFalse(offer(2), "still gated immediately after sending")

        // No ack ever arrives — the watchdog must re-arm the stream.
        let released = expectation(description: "watchdog re-armed the stream")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            if self.offer(3) { released.fulfill() }
        }
        wait(for: [released], timeout: 2.0)
        XCTAssertEqual(sent, [Data([1]), Data([3])])
    }
}
