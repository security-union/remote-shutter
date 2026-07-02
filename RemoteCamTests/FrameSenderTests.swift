//
//  FrameSenderTests.swift
//  RemoteShutterTests
//
//  Tests for the camera-side frame sender: credit-window back-pressure (up to
//  `maxInFlight` frames outstanding), one credit released per RequestFrame ack, and the
//  ack watchdog that keeps a lost ack from wedging the stream forever.
//

import XCTest
import MultipeerConnectivity

@testable import RemoteShutter

class FrameSenderTests: XCTestCase {

    private var system: TestActorSystem!
    private var sessionRef: ActorRef!
    private var session: TestableRemoteCamSession!
    private var senderRef: ActorRef!
    private var frameSender: FrameSender!
    private var peer: MCPeerID!
    private var fakeMP: FakeMultipeerService!

    override func setUp() {
        super.setUp()
        system = TestActorSystem(name: "frameSenderTests")
        sessionRef = system.actorOf(clz: TestableRemoteCamSession.self, name: "session")
        session = (system.actorForRef(ref: sessionRef) as! TestableRemoteCamSession)
        senderRef = system.actorOf(clz: FrameSender.self, name: "frameSender")
        frameSender = (system.actorForRef(ref: senderRef) as! FrameSender)

        peer = MCPeerID(displayName: "TestPeer")
        fakeMP = FakeMultipeerService()
        fakeMP.connectedPeers = [peer]
        fakeMP.sendResult = Success(Actor.Message())
        session.multipeerService = fakeMP

        senderRef ! SetSession(peer: peer, session: session)
        drainSenderMailbox()
    }

    override func tearDown() {
        drainMailboxPumpingRunLoop()
        system.stop()
        drainMailboxPumpingRunLoop()
        system = nil
        sessionRef = nil
        session = nil
        senderRef = nil
        frameSender = nil
        peer = nil
        fakeMP = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func drainSenderMailbox() {
        let expectation = expectation(description: "frame sender mailbox drained")
        frameSender.mailbox.addOperation { expectation.fulfill() }
        wait(for: [expectation], timeout: 5.0)
    }

    private func drainMailboxPumpingRunLoop() {
        let deadline = Date(timeIntervalSinceNow: 5.0)
        while frameSender.mailbox.operationCount > 0 && Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }

    private func makeFrame() -> RemoteCmd.SendFrame {
        RemoteCmd.SendFrame(
            data: Data([1, 2, 3]),
            sender: nil,
            fps: 30,
            camPosition: .back,
            camOrientation: .portrait
        )
    }

    private var sentFrameCount: Int {
        fakeMP.sentMessages.filter { $0.msg is RemoteCmd.SendFrame }.count
    }

    /// The production window size (from StreamingConfig) — the actor is created by the test
    /// ActorSystem via its required init, so we read the size it actually uses rather than
    /// hard-coding it.
    private var windowSize: Int { frameSender.window.maxInFlight }

    private func sendFrames(_ count: Int) {
        for _ in 0..<count { senderRef ! makeFrame() }
        drainSenderMailbox()
    }

    // MARK: - Send path

    func testSendFrameSendsUnreliablyAndConsumesOneCredit() {
        senderRef ! makeFrame()
        drainSenderMailbox()

        XCTAssertEqual(sentFrameCount, 1)
        let sent = fakeMP.sentMessages[0]
        XCTAssertEqual(sent.peers, [peer])
        XCTAssertEqual(sent.mode, .unreliable)
        XCTAssertEqual(frameSender.window.inFlight, 1)
    }

    func testWindowAllowsMultipleFramesInFlight() {
        sendFrames(windowSize)

        XCTAssertEqual(sentFrameCount, windowSize, "the whole window may be in flight without any ack")
        XCTAssertEqual(frameSender.window.inFlight, windowSize)
        XCTAssertFalse(frameSender.window.hasCredit)
    }

    func testFramesDroppedWhenWindowFull() {
        sendFrames(windowSize + 3)

        XCTAssertEqual(sentFrameCount, windowSize, "back-pressure must drop frames once the window is full")
        XCTAssertEqual(frameSender.window.inFlight, windowSize)
    }

    func testRequestFrameReleasesExactlyOneCredit() {
        sendFrames(windowSize)                       // window full
        senderRef ! RemoteCmd.RequestFrame(sender: nil)
        senderRef ! makeFrame()                      // one freed slot refills
        senderRef ! makeFrame()                      // window full again → dropped
        drainSenderMailbox()

        XCTAssertEqual(sentFrameCount, windowSize + 1, "one ack releases exactly one slot")
        XCTAssertEqual(frameSender.window.inFlight, windowSize)
    }

    // MARK: - Ack watchdog

    func testAckTimeoutResetsTheWholeWindow() {
        sendFrames(windowSize)
        XCTAssertEqual(frameSender.window.inFlight, windowSize)

        // Deliver the watchdog for the wait that is actually outstanding.
        senderRef ! AckTimeout(generation: frameSender.ackGeneration)
        drainSenderMailbox()
        XCTAssertEqual(frameSender.window.inFlight, 0, "a stall resets the whole window")

        // The window is open again: a fresh window's worth of frames flows without any ack.
        sendFrames(windowSize)
        XCTAssertEqual(sentFrameCount, windowSize * 2)
    }

    func testStaleAckTimeoutIgnored() {
        // Complete a send/ack cycle so a watchdog for an earlier generation is stale.
        senderRef ! makeFrame()
        senderRef ! RemoteCmd.RequestFrame(sender: nil)
        senderRef ! makeFrame()
        drainSenderMailbox()
        XCTAssertEqual(frameSender.window.inFlight, 1)

        senderRef ! AckTimeout(generation: 1)
        drainSenderMailbox()

        XCTAssertEqual(frameSender.window.inFlight, 1,
                       "a watchdog from an already-completed wait must not reset the window")
    }

    func testAckTimeoutIgnoredWhenWindowEmpty() {
        senderRef ! AckTimeout(generation: frameSender.ackGeneration)
        drainSenderMailbox()

        XCTAssertEqual(frameSender.window.inFlight, 0)

        senderRef ! makeFrame()
        drainSenderMailbox()
        XCTAssertEqual(sentFrameCount, 1)
    }

    /// End-to-end: the scheduled watchdog itself (not an injected message) resets the
    /// window after `FrameSender.ackTimeout` when acks are lost.
    func testScheduledWatchdogRecoversFromLostAcks() {
        sendFrames(windowSize)
        XCTAssertEqual(sentFrameCount, windowSize)

        // No acks arrive. After the timeout the sender must accept frames again.
        let deadline = Date(timeIntervalSinceNow: FrameSender.ackTimeout + 1.0)
        while sentFrameCount < windowSize + 1 && Date() < deadline {
            senderRef ! makeFrame()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        XCTAssertEqual(sentFrameCount, windowSize + 1,
                       "watchdog should have reset the window within \(FrameSender.ackTimeout)s")
    }

    // MARK: - SetSession resets

    func testSetSessionResetsTheWindow() {
        sendFrames(windowSize)
        XCTAssertEqual(frameSender.window.inFlight, windowSize)

        senderRef ! SetSession(peer: peer, session: session)
        drainSenderMailbox()
        XCTAssertEqual(frameSender.window.inFlight, 0)
    }
}
