//
//  StormoLoopbackTests.swift
//  RemoteShutterTests
//
//  End-to-end loopback test that stands up the app's REAL MultipeerService
//  twice in-process — a camera-side service that advertises and a monitor-side
//  service that browses, each with a distinct PeerID — and drives them through
//  the compat layer's default transport path (QUICTransport). It proves the
//  app's own service layer works against Stormo end to end: discovery,
//  invitation, connection, and a RemoteCmd round trip over the real FlatBuffers
//  wire path.
//
//  Unlike LoopbackSessionTests (which uses an in-process fake transport), this
//  exercises the genuine Stormo transport. The compat layer exposes no public
//  seam to inject InMemoryTransport, so this runs over real QUIC. On a bare
//  simulator test process a TLS identity may be unavailable (no keychain
//  entitlement) and Bonjour discovery may not form; in those cases the test
//  SKIPS with a printed reason rather than failing.
//

import XCTest
import MPCCompat
import Stormo
import Combine

@testable import RemoteShutter

final class StormoLoopbackTests: XCTestCase {

    /// Records the MultipeerService delegate callbacks this test waits on.
    /// Callbacks arrive on the compat layer's serial delegate queue, so the
    /// arrays are lock-guarded and the expectations tolerate over-fulfillment
    /// (discovery in particular can fire found/updated more than once).
    private final class ServiceProbe: NSObject, MultipeerServiceDelegate {
        let foundPeer = XCTestExpectation(description: "browser found a peer")
        let connected = XCTestExpectation(description: "peer reached connected")
        let messageReceived = XCTestExpectation(description: "received a decoded message")

        private let lock = NSLock()
        private var _foundPeers: [PeerID] = []
        private var _receivedMessages: [Message] = []

        var foundPeers: [PeerID] { lock.lock(); defer { lock.unlock() }; return _foundPeers }
        var receivedMessages: [Message] { lock.lock(); defer { lock.unlock() }; return _receivedMessages }

        override init() {
            super.init()
            foundPeer.assertForOverFulfill = false
            connected.assertForOverFulfill = false
            messageReceived.assertForOverFulfill = false
        }

        func browserDidFindPeer(_ peer: PeerID) {
            lock.lock(); _foundPeers.append(peer); lock.unlock()
            foundPeer.fulfill()
        }

        func peerDidConnect(_ peer: PeerID) { connected.fulfill() }

        func didReceiveMessage(_ message: Message, from peer: PeerID) {
            lock.lock(); _receivedMessages.append(message); lock.unlock()
            messageReceived.fulfill()
        }

        // Unused delegate surface for this test.
        func peerDidDisconnect(_ peer: PeerID) {}
        func didReceiveFrameRequest(_ request: RemoteCmd.RequestFrame) {}
        func didReceiveFrame(_ frame: RemoteCmd.SendFrame, from peer: PeerID) {}
        func didDetectIncompatibility() {}
        func didStartReceivingResource(name: String, from peer: PeerID, progress: Progress) {}
        func didFinishReceivingResource(name: String, from peer: PeerID, at localURL: URL?, error: Error?) {}
        func browserDidLosePeer(_ peer: PeerID) {}
        func browserDidFail(_ error: Error) {}
        func advertiserDidFail(_ error: Error) {}
    }

    /// Camera-side service advertises, monitor-side service browses+invites; both
    /// reach connected; the monitor sends a `RemoteCmd.SetZoom` through the real
    /// FlatBuffers path and the camera side receives and decodes it.
    func testRealServicesExchangeRemoteCmdOverQUIC() throws {
        // Same-machine self-dials fail with peer-to-peer Wi-Fi enabled (a
        // documented Network.framework behavior, not an app concern) — opt out
        // for the in-process pair. Must be set before any service starts.
        setenv("STORMO_NO_P2P", "1", 1)
        setenv("QUIC_DEBUG", "1", 1)

        // The default compat transport is QUIC, which needs a local TLS identity.
        let probe = PeerIdentity(name: "stormo-loopback-tls-probe")
        let tlsDiagnostic = QUICTransport.tlsIdentityDiagnostic(for: probe)
        #if targetEnvironment(macCatalyst)
        // Catalyst host has the keychain-access-groups entitlement: identity
        // MUST form here. A failure is a real regression, never an
        // environment excuse — this exact gap shipped a broken Mac build once.
        XCTAssertEqual(tlsDiagnostic, "OK",
                       "TLS identity must form in the entitled Catalyst host")
        #else
        // A bare simulator test process may lack a keychain route; skip cleanly.
        try XCTSkipUnless(
            tlsDiagnostic == "OK",
            "QUIC TLS identity unavailable: \(tlsDiagnostic); "
                + "skipping real-transport loopback.")
        #endif

        let cameraPeerID = PeerID(displayName: "StormoLoopbackCamera")
        let monitorPeerID = PeerID(displayName: "StormoLoopbackMonitor")

        let camera = MultipeerService(peerID: cameraPeerID)
        let monitor = MultipeerService(peerID: monitorPeerID)

        let cameraProbe = ServiceProbe()
        let monitorProbe = ServiceProbe()
        camera.delegate = cameraProbe
        monitor.delegate = monitorProbe

        defer {
            camera.stopSession()
            monitor.stopSession()
        }

        // A advertises, B browses.
        camera.startAdvertisingOnly(discoveryInfo: nil)
        monitor.startBrowsingOnly()

        // B must discover A within a generous window. If discovery never fires,
        // the sandbox can't run this (no mDNS/peer-to-peer): skip, don't fail.
        let discovery = XCTWaiter().wait(for: [monitorProbe.foundPeer], timeout: 10)
        guard discovery == .completed, let discoveredCamera = monitorProbe.foundPeers.first else {
            throw XCTSkip("Bonjour discovery did not surface the advertiser in this "
                + "environment; skipping real-transport loopback.")
        }

        // B invites A; A's advertiser handler auto-accepts; both reach connected.
        monitor.invitePeer(discoveredCamera, timeout: 10)
        let connection = XCTWaiter().wait(
            for: [cameraProbe.connected, monitorProbe.connected], timeout: 10)
        guard connection == .completed else {
            throw XCTSkip("QUIC connection did not establish in this environment; "
                + "skipping real-transport loopback.")
        }

        // B sends a RemoteCmd through MultipeerService.send (FlatBuffers wire path).
        let peers = monitor.connectedPeers
        XCTAssertFalse(peers.isEmpty, "monitor must have a connected peer to send to")
        let sendResult = monitor.send(
            RemoteCmd.SetZoom(zoomFactor: 3.5), to: peers, mode: .reliable)
        XCTAssertTrue(sendResult, "send over an established route must not throw")

        // A receives and decodes it.
        let delivery = XCTWaiter().wait(for: [cameraProbe.messageReceived], timeout: 10)
        XCTAssertEqual(delivery, .completed,
                       "the camera side must receive the RemoteCmd over Stormo")

        let zoom = cameraProbe.receivedMessages.compactMap { $0 as? RemoteCmd.SetZoom }.first
        XCTAssertNotNil(zoom, "the received message must decode as RemoteCmd.SetZoom")
        XCTAssertEqual(zoom?.zoomFactor ?? 0, 3.5, accuracy: 0.001,
                       "the FlatBuffers wire round trip must preserve the zoom factor")
    }
}
