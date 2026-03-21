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
                self.startScanning(lobby: lobby)
            case is RemoteShutter.DisconnectPeer:
                ^{
                    let alert = UIAlertController(title: "Error", message: "Unable to connect")
                    alert.simpleOkAction()
                    alert.show(true)
                }
                self.startScanning(lobby: lobby)
            case let w as ConnectToDevice:
                self.multipeerService.invitePeer(w.peer, timeout: 5)
                ^{
                    lobby.scannerViewModel.connectingToPeer()
                }
            case let w as OnConnectToDevice:
                ^{
                    lobby.scannerViewModel.connectedToPeer()
                }
                self.become(
                    name: .connected,
                    state: self.connected(lobbyWrapper: lobbyWrapper, peer: w.peer)
                )
                ^{
                    lobby.goToRole()
                }

            case let m as UICmd.BrowserFoundPeer:
                ^{
                    lobby.scannerViewModel.addPeer(m.peer)
                }

            case let m as UICmd.BrowserLostPeer:
                ^{
                    lobby.scannerViewModel.removePeer(m.peer)
                }

            case _ as UICmd.BrowserFailed:
                ^{
                    lobby.scannerViewModel.scanningFailed()

                    let alert = UIAlertController(
                        title: NSLocalizedString("Scanning Error", comment: ""),
                        message: NSLocalizedString("Unable to scan for nearby devices. Please check your network settings and try again.", comment: ""),
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(
                        title: NSLocalizedString("OK", comment: ""),
                        style: .default,
                        handler: nil
                    ))
                    lobby.present(alert, animated: true)
                }

            default:
                self.receive(msg: msg)
            }
        }
    }
}
