//
//  FrameSender.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 11/24/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import MultipeerConnectivity

class SetSession: Actor.Message {
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

let streamingStateName = "streaming"

class FrameSender: Actor {

    /// How long to wait for a `RequestFrame` ack before concluding it was lost and
    /// resetting the window. Without this, lost acks wedge the stream forever: the
    /// monitor only acks frames it receives, and the camera only sends when it has credit.
    static let ackTimeout: TimeInterval = StreamingConfig.default.peerAckTimeout

    weak var ressionRef: ActorRef?

    /// Credit-based back-pressure, shared with `WatchPreviewStreamer` via `FrameCreditWindow`:
    /// up to `maxInFlight` frames outstanding at once, each released by the monitor's
    /// `RemoteCmd.RequestFrame` ack. Confined to the actor mailbox.
    private(set) var window = FrameCreditWindow(maxInFlight: StreamingConfig.default.peerMaxInFlight)

    /// Invalidates watchdog timeouts from completed/superseded waits (same pattern as
    /// `RemoteCamSession.scheduleTimeout`).
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
        case let newSession as SetSession:
            self.become(name: streamingStateName, state: streaming(newSession), discardOld: true)
        default:
            super.receive(msg: msg)
        }
    }

    /// The one steady state. Sends while the credit window allows, drops otherwise, and
    /// releases credit on each ack — no more `readyToSend`/`waitingForAck` swap, because a
    /// window >1 has no single "waiting" moment.
    func streaming(_ data: SetSession) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter:
                break

            case let newSession as SetSession:
                self.window.reset()
                self.become(name: streamingStateName, state: streaming(newSession), discardOld: true)

            case let frame as RemoteCmd.SendFrame:
                guard self.window.hasCredit else { break } // back-pressure: drop until a credit frees
                data.session?.sendCommandOrGoToScanning(peer: [data.peer], msg: frame, mode: .unreliable)
                self.window.acquire()
                self.armAckWatchdog()

            case is RemoteCmd.RequestFrame:
                self.window.release()
                // Keep guarding any frames still outstanding; stand the watchdog down (by
                // bumping the generation) once the window is empty.
                if self.window.isEmpty {
                    self.ackGeneration += 1
                } else {
                    self.armAckWatchdog()
                }

            case let timeout as AckTimeout:
                guard timeout.generation == self.ackGeneration else { break } // stale wait
                StreamLog.transport.info(
                    "ack watchdog fired after \(Self.ackTimeout, format: .fixed(precision: 1))s — resetting window")
                self.window.reset()

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
