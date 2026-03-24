//
//  MultipeerService.swift
//  RemoteShutter
//
//  Created by Phase 3 refactor.
//

import Foundation
import MultipeerConnectivity
import Combine

protocol MultipeerServiceDelegate: AnyObject {
    func didReceiveMessage(_ message: Actor.Message, from peer: MCPeerID)
    func didReceiveFrameRequest(_ request: RemoteCmd.RequestFrame)
    func didReceiveFrame(_ frame: RemoteCmd.SendFrame, from peer: MCPeerID)
    func peerDidConnect(_ peer: MCPeerID)
    func peerDidDisconnect(_ peer: MCPeerID)
    func didDetectIncompatibility()
    func didStartReceivingResource(name: String, progress: Progress)
    func didFinishReceivingResource(name: String, at localURL: URL?, error: Error?)
    func browserDidFindPeer(_ peer: MCPeerID)
    func browserDidLosePeer(_ peer: MCPeerID)
    func browserDidFail(_ error: Error)
}

protocol MultipeerServiceProtocol: AnyObject {
    var delegate: MultipeerServiceDelegate? { get set }
    var session: MCSession! { get }
    var connectedPeers: [MCPeerID] { get }
    var progressCancellables: Set<AnyCancellable> { get set }

    func startAdvertisingAndBrowsing()
    func startAdvertisingOnly(discoveryInfo: [String: String]?)
    func startBrowsingOnly()
    func stopAdvertisingAndBrowsing()
    func disconnect()
    func stopSession()
    func invitePeer(_ peer: MCPeerID, timeout: TimeInterval)
    func send(_ msg: Actor.Message, to peers: [MCPeerID],
              mode: MCSessionSendDataMode) -> Try<Actor.Message>
    func sendResource(at url: URL, withName name: String,
                      toPeer peer: MCPeerID,
                      completion: @escaping (Error?) -> Void) -> Progress?
}

class MultipeerService: NSObject, MCSessionDelegate,
    MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate,
    MultipeerServiceProtocol {

    weak var delegate: MultipeerServiceDelegate?
    private(set) var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    var progressCancellables = Set<AnyCancellable>()

    var connectedPeers: [MCPeerID] { session?.connectedPeers ?? [] }

    init(peerID: MCPeerID) {
        super.init()
        session = MCSession(peer: peerID)
        session.delegate = self
        advertiser = MCNearbyServiceAdvertiser(
            peer: peerID, discoveryInfo: nil, serviceType: service)
        advertiser.delegate = self
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: service)
        browser.delegate = self
    }

    func startAdvertisingAndBrowsing() {
        advertiser.startAdvertisingPeer()
        browser.stopBrowsingForPeers()
        browser.startBrowsingForPeers()
    }

    func startAdvertisingOnly(discoveryInfo: [String: String]? = nil) {
        if let info = discoveryInfo {
            advertiser.stopAdvertisingPeer()
            advertiser = MCNearbyServiceAdvertiser(
                peer: session.myPeerID, discoveryInfo: info, serviceType: service)
            advertiser.delegate = self
        }
        advertiser.startAdvertisingPeer()
    }

    func startBrowsingOnly() {
        browser.stopBrowsingForPeers()
        browser.startBrowsingForPeers()
    }

    func stopAdvertisingAndBrowsing() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
    }

    func disconnect() {
        session.disconnect()
    }

    func stopSession() {
        stopAdvertisingAndBrowsing()
        session?.disconnect()
        session?.delegate = nil
    }

    func invitePeer(_ peer: MCPeerID, timeout: TimeInterval = 10) {
        browser.invitePeer(peer, to: session, withContext: nil, timeout: timeout)
    }

    func send(_ msg: Actor.Message, to peers: [MCPeerID],
              mode: MCSessionSendDataMode) -> Try<Actor.Message> {
        do {
            guard let serializedMessage = serializeToFlatBuffer(msg) else {
                let error = NSError(domain: "MultipeerService", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "Unknown message type: \(type(of: msg))"])
                return Failure(error: error)
            }
            try session.send(serializedMessage, toPeers: peers, with: mode)
            return Success(msg)
        } catch let error as NSError {
            print("sendMessage error \(error)")
            return Failure(error: error)
        }
    }

    func sendResource(at url: URL, withName name: String,
                      toPeer peer: MCPeerID,
                      completion: @escaping (Error?) -> Void) -> Progress? {
        return session.sendResource(at: url, withName: name,
                                    toPeer: peer, withCompletionHandler: completion)
    }

    // MARK: - MCNearbyServiceAdvertiserDelegate

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didNotStartAdvertisingPeer error: Error) {
        print("Advertiser failed to start: \(error.localizedDescription)")
    }

    // MARK: - MCNearbyServiceBrowserDelegate

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        delegate?.browserDidFindPeer(peerID)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        delegate?.browserDidLosePeer(peerID)
    }

    func browser(_ browser: MCNearbyServiceBrowser,
                 didNotStartBrowsingForPeers error: Error) {
        delegate?.browserDidFail(error)
    }

    // MARK: - MCSessionDelegate

    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            print("Connected: \(peerID.displayName)")
            delegate?.peerDidConnect(peerID)
        case .connecting:
            print("Connecting: \(peerID.displayName)")
        case .notConnected:
            print("Not Connected: \(peerID.displayName)")
            delegate?.peerDidDisconnect(peerID)
        @unknown default:
            print("unknown default")
            fatalError()
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let inboundMessage = RemoteCmd.fromFlatBuffer(data) else {
            delegate?.didDetectIncompatibility()
            return
        }

        switch inboundMessage {
        case let requestFrame as RemoteCmd.RequestFrame:
            delegate?.didReceiveFrameRequest(requestFrame)
        case let frame as RemoteCmd.SendFrame:
            delegate?.didReceiveFrame(frame, from: peerID)
        default:
            delegate?.didReceiveMessage(inboundMessage, from: peerID)
        }
    }

    public func session(_ session: MCSession, didReceive stream: InputStream,
                        withName streamName: String, fromPeer peerID: MCPeerID) {
    }

    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                        fromPeer peerID: MCPeerID, with progress: Progress) {
        delegate?.didStartReceivingResource(name: resourceName, progress: progress)
    }

    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                        fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        delegate?.didFinishReceivingResource(name: resourceName, at: localURL, error: error)
    }

    @nonobjc public func session(session: MCSession, didReceiveCertificate certificate: [AnyObject]?,
                                  fromPeer peerID: MCPeerID,
                                  certificateHandler: @escaping (Bool) -> Void) {
        certificateHandler(true)
    }
}
