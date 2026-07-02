//
//  FrameSender.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 11/24/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import MultipeerConnectivity

class SetSession : Actor.Message {
    let peer: MCPeerID
    unowned var session: RemoteCamSession?
    init(peer: MCPeerID, session: RemoteCamSession) {
        self.peer = peer
        self.session = session
        super.init()
    }
}

/// Watchdog message the sender schedules to itself when it starts waiting for
/// the monitor's `RequestFrame` ack. The generation counter makes timeouts from
/// completed waits harmless (same pattern as `RemoteCamSession.scheduleTimeout`).
class AckTimeout: Actor.Message {
    let generation: Int
    init(generation: Int) {
        self.generation = generation
        super.init()
    }
}

let readyToSendFrame = "readyToSendFrame"
let waitingForAckName = "waitingForAck"

class FrameSender: Actor {

    /// How long to wait for the monitor's `RequestFrame` ack before concluding
    /// it was lost and re-opening the send gate. Without this, one lost ack
    /// wedges the stream forever: the monitor only acks frames it receives, and
    /// the camera only sends frames when acked.
    static let ackTimeout: TimeInterval = 1.0

    weak var ressionRef: ActorRef?

    private(set) var ackGeneration = 0

    public required init(context: ActorSystem, ref: ActorRef) {
        super.init(context: context, ref: ref)
    }

    override func receive(msg: Actor.Message) {
        switch msg {
        case is OnEnter:
            break
        case is AckTimeout:
            break
        case let s as SetSession:
            self.become(name: readyToSendFrame, state: readyToSend(s), discardOld: true)
        default:
            super.receive(msg: msg)
        }
    }

    func readyToSend(_ data: SetSession) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter:
                break
            case is AckTimeout:
                break // stale: the wait it guarded is already over

            case let s as SetSession:
                self.become(name: readyToSendFrame, state: readyToSend(s), discardOld: true)

            case let s as RemoteCmd.SendFrame:
                data.session?.sendCommandOrGoToScanning(peer: [data.peer], msg: s, mode: .unreliable)
                self.become(name: waitingForAckName, state: waitingForAck(data), discardOld: true)
                self.armAckWatchdog()
            default:
                self.receive(msg: msg)
            }
        }
    }

    func waitingForAck(_ session: SetSession) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter:
                break
            case is RemoteCmd.SendFrame:
                break // back-pressure: drop frames until the in-flight one is acked

            case let s as SetSession:
                self.become(name: readyToSendFrame, state: readyToSend(s), discardOld: true)

            case is RemoteCmd.RequestFrame:
                self.become(name: readyToSendFrame, state: readyToSend(session), discardOld: true)

            case let timeout as AckTimeout:
                guard timeout.generation == self.ackGeneration else { break }
                StreamLog.transport.info("ack watchdog fired after \(Self.ackTimeout, format: .fixed(precision: 1))s — re-arming sender")
                self.become(name: readyToSendFrame, state: readyToSend(session), discardOld: true)

            default:
                self.receive(msg: msg)
            }
        }
    }

    private func armAckWatchdog() {
        ackGeneration += 1
        let generation = ackGeneration
        let actorRef = this
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.ackTimeout) { [weak self] in
            guard self != nil else { return }
            actorRef ! AckTimeout(generation: generation)
        }
    }

    deinit {
        print("killing frame sender")
    }
}
