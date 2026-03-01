//
//  RemoteCamSessionTests.swift
//  RemoteShutterTests
//
//  Created by Tests on 3/1/26.
//

import XCTest
@testable import Theater
import MultipeerConnectivity

@testable import RemoteShutter

// MARK: - Testable Subclass

class TestableRemoteCamSession: RemoteCamSession {

    var sentMessages: [(peers: [MCPeerID], msg: Actor.Message)] = []

    override public func sendMessage(
        peer: [MCPeerID],
        msg: Actor.Message,
        mode: MCSessionSendDataMode = .reliable
    ) -> Try<Actor.Message> {
        sentMessages.append((peers: peer, msg: msg))
        return Success(msg)
    }

    override public func sendCommandOrGoToScanning(
        peer: [MCPeerID],
        msg: Actor.Message,
        mode: MCSessionSendDataMode = .reliable
    ) {
        sentMessages.append((peers: peer, msg: msg))
    }

    override func startScanning(lobby: DeviceScannerViewController) {
        // no-op — avoids MCAdvertiserAssistant, MCSession, and UI code
    }
}

// MARK: - Test ViewController

/// Subclass that prevents crashes from nil IBOutlets and storyboard-dependent code.
/// The real `DeviceScannerViewController` has IBOutlets (tableView, etc.) that are
/// nil when created programmatically. This subclass makes the VC safe for tests.
class TestDeviceScannerViewController: DeviceScannerViewController {
    override public func viewDidLoad() {
        // Skip super — avoids accessing nil IBOutlets and actor system registration
    }

    override func stopScanning() {
        // no-op — avoids accessing splash/tableView
    }

    override func startScanning() {
        // no-op
    }
}

// MARK: - Test Helpers

/// Waits for all prior operations on the actor's serial mailbox to drain.
/// Since Theater delivers messages (including OnEnter) via `mailbox.addOperation`,
/// queuing a fulfillment operation after the message-under-test guarantees it has
/// been fully processed before assertions run.
func waitForMailbox(_ session: TestableRemoteCamSession, test: XCTestCase) {
    let expectation = test.expectation(description: "mailbox drained")
    session.mailbox.addOperation { expectation.fulfill() }
    test.wait(for: [expectation], timeout: 2.0)
}

// MARK: - Tests

class RemoteCamSessionTests: XCTestCase {

    private var system: TestActorSystem!
    private var ref: ActorRef!
    private var session: TestableRemoteCamSession!
    private var peer: MCPeerID!
    // Keep strong reference so Weak wrapper doesn't become nil during tests.
    private var lobby: DeviceScannerViewController!
    private var lobbyWrapper: Weak<DeviceScannerViewController>!

    override func setUp() {
        super.setUp()

        system = TestActorSystem(name: "test")
        ref = system.actorOf(clz: TestableRemoteCamSession.self, name: "session")
        session = system.actorForRef(ref: ref!) as! TestableRemoteCamSession
        peer = MCPeerID(displayName: "TestPeer")

        // Create a lobby wrapper whose VC stays alive for the duration of the test.
        // Uses TestDeviceScannerViewController to avoid nil IBOutlet crashes.
        lobby = TestDeviceScannerViewController()
        lobbyWrapper = Weak(lobby)

        // Wait for preStart's `become(waitingForCtrl)` + OnEnter to finish.
        waitForMailbox(session, test: self)
    }

    override func tearDown() {
        system.stop()
        system = nil
        ref = nil
        session = nil
        peer = nil
        lobby = nil
        lobbyWrapper = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Pushes a no-op scanning state onto the state stack.
    /// The real `scanning` state accesses storyboard IBOutlets (splash, tableView)
    /// which crash when the VC is created programmatically. This placeholder
    /// gives `popAndStartScanning()` a target to pop back to.
    private func pushScanningState() {
        let noOpScanning: Receive = { [weak self] _ in
            // Minimal handler — just accept OnEnter without touching UI
            _ = self
        }
        session.become(name: session.states.scanning, state: noOpScanning)
        waitForMailbox(session, test: self) // let OnEnter process
    }

    /// Pushes the connected state on top of scanning.
    private func pushConnectedState() {
        session.become(name: session.states.connected,
                       state: session.connected(lobbyWrapper: lobbyWrapper, peer: peer))
        waitForMailbox(session, test: self) // let OnEnter process
    }

    // MARK: - Initial State

    func testInitialStateIsWaitingForCtrl() {
        // ViewCtrlActor.preStart() pushes "waitingForCtrl"
        XCTAssertEqual(session.currentState()?.0, session.waitingForCtrlState)
    }

    // MARK: - Connected State: Disconnect

    func testConnectedStateDisconnect() {
        // Build state stack: waitingForCtrl → scanning → connected
        pushScanningState()
        pushConnectedState()

        // Act
        ref ! Disconnect(sender: nil)
        waitForMailbox(session, test: self)

        // Assert — should have popped back to scanning
        XCTAssertEqual(session.currentState()?.0, session.states.scanning)
        XCTAssertTrue(session.sentMessages.isEmpty,
                      "Disconnect should not send any remote messages")
    }

    // MARK: - Connected State: BecomeMonitor (Photo)

    func testConnectedStateBecomeMonitorPhoto() {
        pushScanningState()
        pushConnectedState()

        // BecomeMonitor requires a sender ActorRef (used as the monitor actor ref).
        // We reuse `ref` as a stand-in since we only care about state transitions.
        ref ! UICmd.BecomeMonitor(ref, mode: .Photo)
        waitForMailbox(session, test: self)

        // Assert — state should be "monitor" (monitorPhotoMode)
        XCTAssertEqual(session.currentState()?.0, session.states.monitor)

        // Should have sent PeerBecameMonitor to the peer.
        // The monitorPhotoMode OnEnter may also send a message (e.g. RequestCameraCapabilities),
        // so we check that PeerBecameMonitor is the first message sent.
        XCTAssertGreaterThanOrEqual(session.sentMessages.count, 1)
        XCTAssertTrue(session.sentMessages[0].msg is RemoteCmd.PeerBecameMonitor)
        XCTAssertEqual(session.sentMessages[0].peers, [peer])
    }

    // MARK: - Connected State: BecomeMonitor (Video)

    func testConnectedStateBecomeMonitorVideo() {
        pushScanningState()
        pushConnectedState()

        ref ! UICmd.BecomeMonitor(ref, mode: .Video)
        waitForMailbox(session, test: self)

        // Assert — state should be "monitor" (monitorVideoMode)
        XCTAssertEqual(session.currentState()?.0, session.states.monitor)

        // Should have sent PeerBecameMonitor to the peer.
        XCTAssertGreaterThanOrEqual(session.sentMessages.count, 1)
        XCTAssertTrue(session.sentMessages[0].msg is RemoteCmd.PeerBecameMonitor)
        XCTAssertEqual(session.sentMessages[0].peers, [peer])
    }

    // MARK: - Connected State: Nil Lobby Pops to Scanning

    func testConnectedStateNilLobbyPopsToScanning() {
        pushScanningState()

        // Create a lobby wrapper and immediately nil the value to simulate a deallocated VC.
        let weakLobby = Weak(lobby!)
        session.become(name: session.states.connected,
                       state: session.connected(lobbyWrapper: weakLobby, peer: peer))
        waitForMailbox(session, test: self)

        // Nil out the weak reference to simulate the lobby VC being deallocated
        weakLobby.value = nil

        // Send any message — the guard-let will fail and trigger popAndStartScanning
        ref ! Disconnect(sender: nil)
        waitForMailbox(session, test: self)

        // Should have popped back to scanning
        XCTAssertEqual(session.currentState()?.0, session.states.scanning)
    }
}
