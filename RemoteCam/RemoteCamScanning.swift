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
            case is RemoteShutter.DisconnectPeer:
                ^{
                    let alert = UIAlertController(title: "Error", message: "Unable to connect")
                    alert.simpleOkAction()
                    alert.show(true)
                    lobby.splash.stopAnimating()
                }
                self.startScanning(lobby: lobby)
            case let w as ConnectToDevice:
                self.multipeerService.invitePeer(w.peer, timeout: 5)
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

            case let m as UICmd.BrowserFoundPeer:
                ^{
                    if !lobby.connectedPeers.contains(m.peer) {
                        lobby.connectedPeers.append(m.peer)
                    }
                    lobby.speedRunScanning = true
                    lobby.tableView.reloadData()
                }

            case let m as UICmd.BrowserLostPeer:
                ^{
                    lobby.connectedPeers.removeAll { $0 == m.peer }
                    lobby.tableView.reloadData()
                }

            case let m as UICmd.BrowserFailed:
                ^{
                    lobby.speedRunScanning = false
                    lobby.hasScanningError = true
                    lobby.isScanning = false
                    lobby.tableView.reloadData()

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
                _ = m // suppress unused warning

            default:
                self.receive(msg: msg)
            }
        }
    }
}
