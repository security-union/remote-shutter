//
//  OtherStates.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 10/10/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import Theater
import MultipeerConnectivity

extension RemoteCamSession {

    func scanning(lobby: DeviceScannerViewController) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter,
                 is UICmd.BecomeCamera,
                 is UICmd.BecomeMonitor,
                 is UICmd.StartScanning:
                self.startScanning(lobby: lobby)
            case let w as ConnectToDevice:
                lobby.scanner.invitePeer(w.peer, to: session, withContext: nil, timeout: 5)
            case let w as OnConnectToDevice:
                self.become(
                    name: self.states.connected,
                    state: self.connected(lobby: lobby, peer: w.peer)
                )
                ^{
                    lobby.goToRolePicker()
                }

            default:
                self.receive(msg: msg)
            }
        }
    }
}
