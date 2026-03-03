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
    func didReceiveMessage(_ message: Actor.Message)
    func didReceiveFrameRequest(_ request: RemoteCmd.RequestFrame)
    func didReceiveFrame(_ frame: RemoteCmd.SendFrame, from peer: MCPeerID)
    func peerDidConnect(_ peer: MCPeerID)
    func peerDidDisconnect(_ peer: MCPeerID)
    func didDetectIncompatibility()
    func didStartReceivingResource(name: String, progress: Progress)
    func didFinishReceivingResource(name: String, at localURL: URL?, error: Error?)
}

protocol MultipeerServiceProtocol: AnyObject {
    var delegate: MultipeerServiceDelegate? { get set }
    var session: MCSession! { get }
    var connectedPeers: [MCPeerID] { get }
    var progressCancellables: Set<AnyCancellable> { get set }

    func startSession(peerID: MCPeerID)
    func stopSession()
    func send(_ msg: Actor.Message, to peers: [MCPeerID],
              mode: MCSessionSendDataMode) -> Try<Actor.Message>
    func sendResource(at url: URL, withName name: String,
                      toPeer peer: MCPeerID,
                      completion: @escaping (Error?) -> Void) -> Progress?
}

class MultipeerService: NSObject, MCSessionDelegate, MultipeerServiceProtocol {

    weak var delegate: MultipeerServiceDelegate?
    var session: MCSession!
    private var mcAdvertiserAssistant: MCAdvertiserAssistant!
    var progressCancellables = Set<AnyCancellable>()

    var connectedPeers: [MCPeerID] { session?.connectedPeers ?? [] }

    func startSession(peerID: MCPeerID) {
        session = MCSession(peer: peerID)
        session.delegate = self
        mcAdvertiserAssistant = MCAdvertiserAssistant(
            serviceType: service, discoveryInfo: nil, session: session)
        mcAdvertiserAssistant.start()
    }

    func stopSession() {
        mcAdvertiserAssistant?.stop()
        session?.disconnect()
        session?.delegate = nil
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
            delegate?.didReceiveMessage(inboundMessage)
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
