//
//  FrameSender.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 11/24/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import Theater
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

let readyToSendFrame = "readyToSendFrame"
let waitingForAckName = "waitingForAck"

class FrameSender: Actor {
    
    weak var ressionRef: ActorRef?
    
    public required init(context: ActorSystem, ref: ActorRef) {
        super.init(context: context, ref: ref)
    }
    
    override func receive(msg: Actor.Message) {
        switch msg {
        case is OnEnter:
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
            case let s as SetSession:
                self.become(name: readyToSendFrame, state: readyToSend(s), discardOld: true)
                
            case let s as RemoteCmd.SendFrame:
                // Send FlatBuffers frame data instead of legacy SendFrame
                data.session?.sendFlatBuffersFrameData(
                    peer: [data.peer],
                    frameData: s.data,
                    fps: s.fps,
                    cameraPosition: s.camPosition,
                    orientation: s.camOrientation
                )
                self.become(name: waitingForAckName, state: waitingForAck(data), discardOld: true)
                
            case let fbCommand as FlatBuffersCameraCommand:
                // Handle FlatBuffers frame request
                if fbCommand.command.action == .requestframe {
                    // Transition to ready state to send frame data
                    self.become(name: readyToSendFrame, state: readyToSend(data), discardOld: true)
                }
                
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
                break
            case let s as SetSession:
                self.become(name: readyToSendFrame, state: readyToSend(s), discardOld: true)

            case let fbCommand as FlatBuffersCameraCommand:
                // Handle FlatBuffers frame request
                if fbCommand.command.action == .requestframe {
                    self.become(name: readyToSendFrame, state: readyToSend(session), discardOld: true)
                }

            default:
                self.receive(msg: msg)
            }
        }
    }
    
    deinit {
        print("killing frame sender")
    }
}
