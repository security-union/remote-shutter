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

    func scanning(lobby: RolePickerController) -> Receive {
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is OnEnter,
                 is UICmd.BecomeCamera,
                 is UICmd.BecomeMonitor,
                 is UICmd.ToggleConnect,
                 is UICmd.StartScanning:
                self.startScanning(lobby: lobby)
                ^{
                    lobby.navigationItem.rightBarButtonItem?.title = lobby.states.connect
                    lobby.self.navigationItem.prompt = lobby.disconnectedPrompt
                    lobby.remote.alpha = 0.3
                    lobby.camera.alpha = 0.3
                    lobby.remote.isEnabled = false
                    lobby.camera.isEnabled = false
                    lobby.instructionLabel.text = lobby.disconnectedInstructionsLabel
                }
            case let w as OnConnectToDevice:
                self.become(
                    name: self.states.connected,
                    state: self.connected(lobby: lobby, peer: w.peer)
                )
                ^{
                    if let c = self.browser {
                        c.dismiss(animated: true, completion: { [unowned self] in
                            self.browser = nil
                        })
                    }
                }

            default:
                self.receive(msg: msg)
            }
        }
    }
}
