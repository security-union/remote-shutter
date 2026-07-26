//
//  MultipeerService.swift
//  RemoteShutter
//
//  Created by Phase 3 refactor.
//

import Foundation
import MPCCompat
import PeerMesh
import Combine

protocol MultipeerServiceDelegate: AnyObject {
    func didReceiveMessage(_ message: Message)
    func didReceiveFrameRequest(_ request: RemoteCmd.RequestFrame)
    func didReceiveFrame(_ frame: RemoteCmd.SendFrame, from peer: PeerID)
    func peerDidConnect(_ peer: PeerID)
    func peerDidDisconnect(_ peer: PeerID)
    func didDetectIncompatibility()
    func didStartReceivingResource(name: String, progress: Progress)
    func didFinishReceivingResource(name: String, at localURL: URL?, error: Error?)
    func browserDidFindPeer(_ peer: PeerID)
    func browserDidLosePeer(_ peer: PeerID)
    func browserDidFail(_ error: Error)
    func advertiserDidFail(_ error: Error)
}

protocol MultipeerServiceProtocol: AnyObject {
    var delegate: MultipeerServiceDelegate? { get set }
    var session: MultipeerSession! { get }
    var connectedPeers: [PeerID] { get }
    var progressCancellables: Set<AnyCancellable> { get set }

    func startAdvertisingAndBrowsing()
    func startAdvertisingOnly(discoveryInfo: [String: String]?)
    func startBrowsingOnly()
    func stopAdvertisingAndBrowsing()
    func disconnect()
    func stopSession()
    func invitePeer(_ peer: PeerID, timeout: TimeInterval)
    func send(_ msg: Message, to peers: [PeerID],
              mode: MultipeerSession.SendDataMode) -> Try<Message>
    func sendResource(at url: URL, withName name: String,
                      toPeer peer: PeerID,
                      completion: @escaping (Error?) -> Void) -> Progress?
}

class MultipeerService: NSObject, MultipeerSessionDelegate,
    NearbyServiceAdvertiserDelegate, NearbyServiceBrowserDelegate,
    MultipeerServiceProtocol {

    weak var delegate: MultipeerServiceDelegate?
    private let peerID: PeerID
    private var advertiser: NearbyServiceAdvertiser!
    private var browser: NearbyServiceBrowser!
    var progressCancellables = Set<AnyCancellable>()

    // `session` is swapped on rebuild from both the coordinator's context
    // (monitor inviting) and MC's delegate queue (camera accepting), while
    // senders read it from their own queues — hence the Locked box.
    private let sessionBox: Locked<MultipeerSession>
    var session: MultipeerSession! { sessionBox.value }

    var connectedPeers: [PeerID] { session?.connectedPeers ?? [] }

    init(peerID: PeerID) {
        self.peerID = peerID
        sessionBox = Locked(Self.makeSession(peerID: peerID))
        super.init()
        sessionBox.value.delegate = self
        advertiser = NearbyServiceAdvertiser(
            peer: peerID, discoveryInfo: nil, serviceType: service)
        advertiser.delegate = self
        browser = NearbyServiceBrowser(peer: peerID, serviceType: service)
        browser.delegate = self
    }

    private static func makeSession(peerID: PeerID) -> MultipeerSession {
        MultipeerSession(peer: peerID, securityIdentity: nil,
                  encryptionPreference: .required)
    }

    /// Apple never documents a torn-down MultipeerSession as reusable, and reused
    /// sessions are the classic cause of invites that wedge in `.connecting`.
    /// Every connection attempt therefore starts from a virgin session: the
    /// monitor rebuilds before inviting, the camera before accepting. The
    /// idle check and the swap must be one critical section, or two threads
    /// could both see "idle" and rebuild twice.
    private func rebuildSessionIfIdle() {
        sessionBox.mutate { session in
            guard session.connectedPeers.isEmpty else { return }
            session.delegate = nil
            session.disconnect()
            let fresh = Self.makeSession(peerID: peerID)
            fresh.delegate = self
            session = fresh
        }
    }

    func startAdvertisingAndBrowsing() {
        advertiser.startAdvertisingPeer()
        browser.stopBrowsingForPeers()
        browser.startBrowsingForPeers()
    }

    func startAdvertisingOnly(discoveryInfo: [String: String]? = nil) {
        if let info = discoveryInfo {
            advertiser.stopAdvertisingPeer()
            advertiser = NearbyServiceAdvertiser(
                peer: peerID, discoveryInfo: info, serviceType: service)
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

    func invitePeer(_ peer: PeerID, timeout: TimeInterval = 10) {
        rebuildSessionIfIdle()
        browser.invitePeer(peer, to: session, withContext: nil, timeout: timeout)
    }

    func send(_ msg: Message, to peers: [PeerID],
              mode: MultipeerSession.SendDataMode) -> Try<Message> {
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
                      toPeer peer: PeerID,
                      completion: @escaping (Error?) -> Void) -> Progress? {
        return session.sendResource(at: url, withName: name,
                                    toPeer: peer, withCompletionHandler: completion)
    }

    // MARK: - NearbyServiceAdvertiserDelegate

    func advertiser(_ advertiser: NearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: PeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MultipeerSession?) -> Void) {
        rebuildSessionIfIdle()
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: NearbyServiceAdvertiser,
                    didNotStartAdvertisingPeer error: Error) {
        print("Advertiser failed to start: \(error.localizedDescription)")
        delegate?.advertiserDidFail(error)
    }

    // MARK: - NearbyServiceBrowserDelegate

    func browser(_ browser: NearbyServiceBrowser, foundPeer peerID: PeerID,
                 withDiscoveryInfo info: [String: String]?) {
        delegate?.browserDidFindPeer(peerID)
    }

    func browser(_ browser: NearbyServiceBrowser, lostPeer peerID: PeerID) {
        delegate?.browserDidLosePeer(peerID)
    }

    func browser(_ browser: NearbyServiceBrowser,
                 didNotStartBrowsingForPeers error: Error) {
        delegate?.browserDidFail(error)
    }

    // MARK: - MultipeerSessionDelegate

    public func session(_ session: MultipeerSession, peer peerID: PeerID, didChange state: MultipeerSession.PeerState) {
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
            print("Unhandled session state \(state.rawValue) for \(peerID.displayName)")
        }
    }

    public func session(_ session: MultipeerSession, didReceive data: Data, fromPeer peerID: PeerID) {
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
            delegate?.didReceiveMessage(inboundMessage)
        }
    }

    public func session(_ session: MultipeerSession, didReceive stream: InputStream,
                        withName streamName: String, fromPeer peerID: PeerID) {
    }

    public func session(_ session: MultipeerSession, didStartReceivingResourceWithName resourceName: String,
                        fromPeer peerID: PeerID, with progress: Progress) {
        delegate?.didStartReceivingResource(name: resourceName, progress: progress)
    }

    public func session(_ session: MultipeerSession, didFinishReceivingResourceWithName resourceName: String,
                        fromPeer peerID: PeerID, at localURL: URL?, withError error: Error?) {
        delegate?.didFinishReceivingResource(name: resourceName, at: localURL, error: error)
    }
}
