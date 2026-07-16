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
import UIKit

@testable import RemoteShutter

class FrameSenderTests: XCTestCase {

    private var frameSender: FrameSender!
    private var peer: MCPeerID!
    private var fakeMP: FakeMultipeerService!

    override func setUp() {
        super.setUp()
        frameSender = FrameSender()

        peer = MCPeerID(displayName: "TestPeer")
        fakeMP = FakeMultipeerService()
        fakeMP.connectedPeers = [peer]
        fakeMP.sendResult = Success(Message())

        frameSender.setSession(peer: peer, transport: fakeMP)
        frameSender.drain()
    }

    override func tearDown() {
        frameSender.drain()
        frameSender = nil
        peer = nil
        fakeMP = nil
        super.tearDown()
    }

    // MARK: - Helpers

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

    /// The production window size (from StreamingConfig) — read from the
    /// sender rather than hard-coded.
    private var windowSize: Int { frameSender.windowSnapshot().maxInFlight }

    private func sendFrames(_ count: Int) {
        for _ in 0..<count { frameSender.send(makeFrame()) }
        frameSender.drain()
    }

    // MARK: - Send path

    func testSendFrameSendsUnreliablyAndConsumesOneCredit() {
        frameSender.send(makeFrame())
        frameSender.drain()

        XCTAssertEqual(sentFrameCount, 1)
        let sent = fakeMP.sentMessages[0]
        XCTAssertEqual(sent.peers, [peer])
        // Frames are ALWAYS .unreliable (hard rule): a live viewfinder drops
        // stale frames, it never queues them.
        XCTAssertEqual(sent.mode, .unreliable)
        XCTAssertEqual(frameSender.windowSnapshot().inFlight, 1)
    }

    /// The datagram-channel warm-up must be harmless on the receiving side:
    /// a stray RequestFrame before any frame is in flight is a no-op ack.
    func testStrayAckOnEmptyWindowIsHarmless() {
        frameSender.receiveAck(RemoteCmd.RequestFrame(sender: nil))
        frameSender.drain()
        XCTAssertEqual(frameSender.windowSnapshot().inFlight, 0)
    }

    /// Peer connect fires exactly one unreliable no-op ping so MC starts
    /// negotiating its lossy datagram channel (~10s) during role selection
    /// instead of during the first seconds of live preview.
    func testPeerConnectSendsOneUnreliableWarmUpPing() async {
        let harness = await makeCoordinatorHarness()
        harness.coordinator.peerDidConnect(harness.peer)
        await harness.coordinator.waitForIdle()

        let pings = harness.fakeMP.sentMessages.filter { $0.msg is RemoteCmd.RequestFrame }
        XCTAssertEqual(pings.count, 1, "connect must warm the unreliable channel exactly once")
        XCTAssertEqual(pings.first?.mode, .unreliable)
    }

    func testWindowAllowsMultipleFramesInFlight() {
        sendFrames(windowSize)

        XCTAssertEqual(sentFrameCount, windowSize, "the whole window may be in flight without any ack")
        XCTAssertEqual(frameSender.windowSnapshot().inFlight, windowSize)
        XCTAssertFalse(frameSender.windowSnapshot().hasCredit)
    }

    func testFramesDroppedWhenWindowFull() {
        sendFrames(windowSize + 3)

        XCTAssertEqual(sentFrameCount, windowSize, "back-pressure must drop frames once the window is full")
        XCTAssertEqual(frameSender.windowSnapshot().inFlight, windowSize)
    }

    func testRequestFrameReleasesExactlyOneCredit() {
        sendFrames(windowSize)                                    // window full
        frameSender.receiveAck(RemoteCmd.RequestFrame(sender: nil))
        frameSender.send(makeFrame())                             // one freed slot refills
        frameSender.send(makeFrame())                             // window full again → dropped
        frameSender.drain()

        XCTAssertEqual(sentFrameCount, windowSize + 1, "one ack releases exactly one slot")
        XCTAssertEqual(frameSender.windowSnapshot().inFlight, windowSize)
    }

    // MARK: - Ack watchdog

    func testAckTimeoutResetsTheWholeWindow() {
        sendFrames(windowSize)
        XCTAssertEqual(frameSender.windowSnapshot().inFlight, windowSize)

        // Deliver the watchdog for the wait that is actually outstanding.
        frameSender.fireAckWatchdog(generation: frameSender.currentAckGeneration())
        XCTAssertEqual(frameSender.windowSnapshot().inFlight, 0, "a stall resets the whole window")

        // The window is open again: a fresh window's worth of frames flows without any ack.
        sendFrames(windowSize)
        XCTAssertEqual(sentFrameCount, windowSize * 2)
    }

    func testStaleAckTimeoutIgnored() {
        // Complete a send/ack cycle so a watchdog for an earlier generation is stale.
        frameSender.send(makeFrame())
        frameSender.receiveAck(RemoteCmd.RequestFrame(sender: nil))
        frameSender.send(makeFrame())
        frameSender.drain()
        XCTAssertEqual(frameSender.windowSnapshot().inFlight, 1)

        frameSender.fireAckWatchdog(generation: 1)

        XCTAssertEqual(frameSender.windowSnapshot().inFlight, 1,
                       "a watchdog from an already-completed wait must not reset the window")
    }

    func testAckTimeoutIgnoredWhenWindowEmpty() {
        frameSender.fireAckWatchdog(generation: frameSender.currentAckGeneration())

        XCTAssertEqual(frameSender.windowSnapshot().inFlight, 0)

        frameSender.send(makeFrame())
        frameSender.drain()
        XCTAssertEqual(sentFrameCount, 1)
    }

    /// End-to-end: the scheduled watchdog itself (not an injected firing) resets the
    /// window after `FrameSender.ackTimeout` when acks are lost.
    func testScheduledWatchdogRecoversFromLostAcks() {
        sendFrames(windowSize)
        XCTAssertEqual(sentFrameCount, windowSize)

        // No acks arrive. After the timeout the sender must accept frames again.
        let deadline = Date(timeIntervalSinceNow: FrameSender.ackTimeout + 1.0)
        while sentFrameCount < windowSize + 1 && Date() < deadline {
            frameSender.send(makeFrame())
            frameSender.drain()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        XCTAssertEqual(sentFrameCount, windowSize + 1,
                       "watchdog should have reset the window within \(FrameSender.ackTimeout)s")
    }

    // MARK: - SetSession resets

    func testSetSessionResetsTheWindow() {
        sendFrames(windowSize)
        XCTAssertEqual(frameSender.windowSnapshot().inFlight, windowSize)

        frameSender.setSession(peer: peer, transport: fakeMP)
        frameSender.drain()
        XCTAssertEqual(frameSender.windowSnapshot().inFlight, 0)
    }

    // MARK: - Keyframe triggers

    /// Binding a peer is the moment the stream starts flowing — and it is re-entered
    /// after a photo or a video transfer. The monitor's decoder cannot safely predict
    /// from whatever it held before, so the first frame back must stand alone.
    func testSetSessionArmsAKeyframe() {
        let sender = FrameSender()
        XCTAssertFalse(sender.takeKeyframeRequest(), "nothing armed before binding")

        sender.setSession(peer: peer, transport: fakeMP)
        sender.drain()

        XCTAssertTrue(sender.takeKeyframeRequest(), "binding a peer must arm a keyframe")
        XCTAssertFalse(sender.takeKeyframeRequest(), "consumed exactly once")
    }

    /// Coming back from the background, this encoder carries on from its own state
    /// while the monitor's decoder still holds pre-freeze references. The deltas
    /// decode without error, so nothing else would ever prompt a keyframe.
    func testForegroundingArmsAKeyframe() {
        let center = NotificationCenter()
        let sender = FrameSender(notificationCenter: center)
        XCTAssertFalse(sender.takeKeyframeRequest(), "nothing armed at rest")

        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        XCTAssertTrue(sender.takeKeyframeRequest(), "foregrounding must arm a keyframe")
        XCTAssertFalse(sender.takeKeyframeRequest(), "consumed exactly once")
    }
}
