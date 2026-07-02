//
//  FrameSenderTests.swift
//  RemoteShutterTests
//
//  State-machine tests for the camera-side frame sender: one-frame-in-flight
//  back-pressure, and the ack watchdog that keeps a lost RequestFrame ack from
//  wedging the stream forever.
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

    // MARK: - Send path

    func testSendFrameSendsUnreliablyAndWaitsForAck() {
        senderRef ! makeFrame()
        drainSenderMailbox()

        XCTAssertEqual(sentFrameCount, 1)
        let sent = fakeMP.sentMessages[0]
        XCTAssertEqual(sent.peers, [peer])
        XCTAssertEqual(sent.mode, .unreliable)
        XCTAssertEqual(frameSender.currentState()?.0, waitingForAckName)
    }

    func testFramesDroppedWhileWaitingForAck() {
        senderRef ! makeFrame()
        senderRef ! makeFrame()
        senderRef ! makeFrame()
        drainSenderMailbox()

        XCTAssertEqual(sentFrameCount, 1, "back-pressure must drop frames until the in-flight one is acked")
        XCTAssertEqual(frameSender.currentState()?.0, waitingForAckName)
    }

    func testRequestFrameAckReopensGate() {
        senderRef ! makeFrame()
        senderRef ! RemoteCmd.RequestFrame(sender: nil)
        senderRef ! makeFrame()
        drainSenderMailbox()

        XCTAssertEqual(sentFrameCount, 2)
        XCTAssertEqual(frameSender.currentState()?.0, waitingForAckName)
    }

    // MARK: - Ack watchdog

    func testAckTimeoutReopensGate() {
        senderRef ! makeFrame()
        drainSenderMailbox()
        XCTAssertEqual(frameSender.currentState()?.0, waitingForAckName)

        // Deliver the watchdog for the wait that is actually in flight.
        senderRef ! AckTimeout(generation: frameSender.ackGeneration)
        drainSenderMailbox()
        XCTAssertEqual(frameSender.currentState()?.0, readyToSendFrame)

        // The gate is open again: the next frame flows without any ack.
        senderRef ! makeFrame()
        drainSenderMailbox()
        XCTAssertEqual(sentFrameCount, 2)
    }

    func testStaleAckTimeoutIgnoredWhileWaiting() {
        // Complete one send/ack cycle so a watchdog for generation 1 is stale.
        senderRef ! makeFrame()
        senderRef ! RemoteCmd.RequestFrame(sender: nil)
        senderRef ! makeFrame()
        drainSenderMailbox()
        XCTAssertEqual(frameSender.ackGeneration, 2)

        senderRef ! AckTimeout(generation: 1)
        drainSenderMailbox()

        XCTAssertEqual(frameSender.currentState()?.0, waitingForAckName,
                       "a watchdog from an already-completed wait must not re-open the gate")
    }

    func testAckTimeoutIgnoredWhenReady() {
        senderRef ! AckTimeout(generation: frameSender.ackGeneration)
        drainSenderMailbox()

        XCTAssertEqual(frameSender.currentState()?.0, readyToSendFrame)

        senderRef ! makeFrame()
        drainSenderMailbox()
        XCTAssertEqual(sentFrameCount, 1)
    }

    /// End-to-end: the scheduled watchdog itself (not an injected message)
    /// re-opens the gate after `FrameSender.ackTimeout` when the ack is lost.
    func testScheduledWatchdogRecoversFromLostAck() {
        senderRef ! makeFrame()
        drainSenderMailbox()
        XCTAssertEqual(sentFrameCount, 1)

        // No ack arrives. After the timeout the sender must accept frames again.
        let deadline = Date(timeIntervalSinceNow: FrameSender.ackTimeout + 1.0)
        while sentFrameCount < 2 && Date() < deadline {
            senderRef ! makeFrame()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        XCTAssertEqual(sentFrameCount, 2, "watchdog should have re-armed the sender within \(FrameSender.ackTimeout)s")
    }

    // MARK: - SetSession resets

    func testSetSessionWhileWaitingReturnsToReady() {
        senderRef ! makeFrame()
        drainSenderMailbox()
        XCTAssertEqual(frameSender.currentState()?.0, waitingForAckName)

        senderRef ! SetSession(peer: peer, session: session)
        drainSenderMailbox()
        XCTAssertEqual(frameSender.currentState()?.0, readyToSendFrame)
    }
}
