//
//  OtherStates.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 10/10/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import MultipeerConnectivity

extension RemoteCamSession {

    func scanning(_ lobbyWrapper: Weak<DeviceScannerViewController>) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            guard let lobby = lobbyWrapper.value else {
                return
            }
            switch msg {

            case is OnEnter,
                 is UICmd.BecomeCamera,
                 is UICmd.BecomeMonitor,
                 is UICmd.StartScanning:
                ^{
                    lobby.splash.stopAnimating()
                }
                self.startScanning(lobby: lobby)
            case is Disconnect:
                self.startScanning(lobby: lobby)

            case is RemoteShutter.DisconnectPeer:
                ^{
                    let alert = UIAlertController(title: "Error", message: "Unable to connect")
                    alert.simpleOkAction()
                    alert.show(true)
                    lobby.splash.stopAnimating()
                }
                self.startScanning(lobby: lobby)
            case let w as ConnectToDevice:
                guard let session = session else { return }
                lobby.scanner.invitePeer(w.peer, to: session, withContext: nil, timeout: 5)
                ^{
                    lobby.splash.startAnimating()
                }
            case let w as OnConnectToDevice:
                ^{
                    lobby.splash.stopAnimating()
                }
                self.become(
                    name: self.states.connected,
                    state: self.connected(lobbyWrapper: lobbyWrapper, peer: w.peer)
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
