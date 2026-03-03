//
//  MultipeerService.swift
//  RemoteShutter
//
//  Created by Phase 3 refactor.
//

import Foundation
import MultipeerConnectivity
import Combine
import FlatBuffers

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
    var session: MCSession? { get }
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

    // MARK: - Heartbeat Configuration

    /// Interval between heartbeat sends (seconds).
    static let heartbeatInterval: TimeInterval = 1.0

    /// Maximum time to wait for a heartbeat before declaring peer disconnected (seconds).
    static let heartbeatDeadline: TimeInterval = 3.0

    // MARK: - Properties

    weak var delegate: MultipeerServiceDelegate?
    var session: MCSession?
    private var mcAdvertiserAssistant: MCAdvertiserAssistant?
    var progressCancellables = Set<AnyCancellable>()

    // MARK: - Heartbeat State (all access must be on heartbeatQueue)

    /// Serial queue for all heartbeat/watchdog state. Keeps this off the main thread.
    private let heartbeatQueue = DispatchQueue(label: "com.remoteshutter.heartbeat")

    /// Timer that sends heartbeats to all connected peers at 1Hz.
    private var heartbeatSendTimer: DispatchSourceTimer?

    /// Per-peer watchdog timers. If a peer's timer fires, we declare it disconnected.
    private var peerWatchdogs: [MCPeerID: DispatchSourceTimer] = [:]

    /// Pre-built heartbeat FlatBuffer data (never changes, allocated once).
    private static let heartbeatData: Data = {
        var fbb = FlatBufferBuilder()
        let msg = RemoteShutter_P2PMessage.createP2PMessage(&fbb, type: .heartbeat)
        fbb.finish(offset: msg, fileId: "RCAM")
        return fbb.data
    }()

    var connectedPeers: [MCPeerID] { session?.connectedPeers ?? [] }

    // MARK: - Session Lifecycle

    func startSession(peerID: MCPeerID) {
        session = MCSession(peer: peerID)
        session?.delegate = self
        mcAdvertiserAssistant = MCAdvertiserAssistant(
            serviceType: service, discoveryInfo: nil, session: session!)
        mcAdvertiserAssistant?.start()
    }

    func stopSession() {
        // Clean up all heartbeat/watchdog timers synchronously
        // so no stale callbacks fire after this returns.
        heartbeatQueue.sync {
            self.stopHeartbeatSendTimer()
            self.cancelAllWatchdogs()
        }
        mcAdvertiserAssistant?.stop()
        session?.disconnect()
        session?.delegate = nil
    }

    // MARK: - Send

    func send(_ msg: Actor.Message, to peers: [MCPeerID],
              mode: MCSessionSendDataMode) -> Try<Actor.Message> {
        do {
            guard let serializedMessage = serializeToFlatBuffer(msg) else {
                let error = NSError(domain: "MultipeerService", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "Unknown message type: \(type(of: msg))"])
                return Failure(error: error)
            }
            try session?.send(serializedMessage, toPeers: peers, with: mode)
            return Success(msg)
        } catch let error as NSError {
            print("sendMessage error \(error)")
            return Failure(error: error)
        }
    }

    func sendResource(at url: URL, withName name: String,
                      toPeer peer: MCPeerID,
                      completion: @escaping (Error?) -> Void) -> Progress? {
        return session?.sendResource(at: url, withName: name,
                                    toPeer: peer, withCompletionHandler: completion)
    }

    // MARK: - Heartbeat Sending (must be called on heartbeatQueue)

    private func startHeartbeatSendTimer() {
        stopHeartbeatSendTimer()

        let timer = DispatchSource.makeTimerSource(queue: heartbeatQueue)
        timer.schedule(deadline: .now() + Self.heartbeatInterval,
                       repeating: Self.heartbeatInterval)
        timer.setEventHandler { [weak self] in
            self?.sendHeartbeatToAllPeers()
        }
        timer.resume()
        heartbeatSendTimer = timer
    }

    private func stopHeartbeatSendTimer() {
        heartbeatSendTimer?.cancel()
        heartbeatSendTimer = nil
    }

    private func sendHeartbeatToAllPeers() {
        guard let session = session else { return }
        let peers = session.connectedPeers
        guard !peers.isEmpty else { return }

        do {
            try session.send(Self.heartbeatData, toPeers: peers, with: .unreliable)
        } catch {
            // Heartbeat send failures are expected when peers disconnect;
            // the watchdog will handle cleanup.
        }
    }

    // MARK: - Peer Watchdog (must be called on heartbeatQueue)

    private func resetWatchdog(for peerID: MCPeerID) {
        print("reset watchdog for \(peerID.displayName)")
        peerWatchdogs[peerID]?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: heartbeatQueue)
        timer.schedule(deadline: .now() + Self.heartbeatDeadline)
        timer.setEventHandler { [weak self] in
            print("firing watchdog for \(peerID.displayName)")
            guard let self = self else { return }
            print("Watchdog fired for \(peerID.displayName) — no heartbeat in \(Self.heartbeatDeadline)s")
            self.peerWatchdogs.removeValue(forKey: peerID)
            self.delegate?.peerDidDisconnect(peerID)
            if self.peerWatchdogs.isEmpty {
                self.stopHeartbeatSendTimer()
            }
        }
        timer.resume()
        peerWatchdogs[peerID] = timer
    }

    private func cancelWatchdog(for peerID: MCPeerID) {
        peerWatchdogs[peerID]?.cancel()
        peerWatchdogs.removeValue(forKey: peerID)
    }

    private func cancelAllWatchdogs() {
        peerWatchdogs.values.forEach { $0.cancel() }
        peerWatchdogs.removeAll()
    }

    // MARK: - MCSessionDelegate

    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            print("Connected: \(peerID)")
            heartbeatQueue.async { [weak self] in
                guard let self = self else { return }
                self.resetWatchdog(for: peerID)
                if self.heartbeatSendTimer == nil {
                    self.startHeartbeatSendTimer()
                }
            }
            delegate?.peerDidConnect(peerID)

        case .connecting:
            print("Connecting: \(peerID)")

        case .notConnected:
            // Intentionally ignored. The heartbeat watchdog is the sole
            // disconnect mechanism. This callback is unreliable.
            print("Not Connected (ignored): \(peerID)")

        @unknown default:
            print("unknown default")
            fatalError()
        }
    }

    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let msg = RemoteCmd.parseMessage(data) else {
            delegate?.didDetectIncompatibility()
            return
        }

        switch msg.type {
        case .heartbeat:
            heartbeatQueue.async { [weak self] in
                self?.resetWatchdog(for: peerID)
            }

        case .cameracommand, .camerastateresponse, .framedata:
            guard let inboundMessage = RemoteCmd.decode(from: msg) else {
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
    
    deinit {
        print("killing Multipeer Service")
    }
}
