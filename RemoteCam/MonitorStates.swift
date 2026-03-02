//
//  SessionMonitorStates.swift
//  Actors
//
//  Created by Dario Lencina on 11/1/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation
import MultipeerConnectivity
import Photos

extension RemoteCamSession {

    func requestFrame(_ peer : [MCPeerID]) {
        self.sendCommandOrGoToScanning(peer: peer, msg: RemoteCmd.RequestFrame(sender: self.this))
    }

    func monitorTogglingFlash(monitor: ActorRef,
                              peer: MCPeerID,
                              lobby: Weak<DeviceScannerViewController>) -> Receive {
        var alertHandle: AlertHandle?
        ^{ [weak self] in
            alertHandle = self?.alertPresenter.showAlert(title: "Requesting flash toggle")
        }
        return { [unowned self] (msg: Actor.Message) in
            switch msg {

            case is UICmd.ToggleFlash:
                if let f = self.sendMessage(peer: [peer], msg: RemoteCmd.ToggleFlash()) as? Failure {
                    self.this ! RemoteCmd.ToggleFlashResp(flashMode: nil, error: f.error)
                }

            case let t as RemoteCmd.ToggleFlashResp:
                if let _ = t.flashMode {
                    monitor ! t
                    ^{ [weak self] in
                        if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                    }
                    self.unbecome()
                } else if let error = t.error {
                    ^{ [weak self] in
                        if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                        self?.alertPresenter.showError(title: error._domain)
                    }
                    self.unbecome()
                } else {
                    ^{ [weak self] in
                        if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                    }
                    self.unbecome()
                }

            case let c as DisconnectPeer:
                if c.peer.displayName == peer.displayName && self.connectedPeers.count == 0 {
                    ^{ [weak self] in
                        if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                    }
                    self.popAndStartScanning()
                }

            case is Disconnect:
                ^{ [weak self] in
                    if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                }
                self.popAndStartScanning()

            case is UICmd.UnbecomeMonitor:
                ^{ [weak self] in
                    if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                }
                self.popToState(name: self.states.connected)

            default:
                print("ignoring message")
            }
        }
    }

    // MARK: - Lens Switching State
    func monitorSwitchingLens(monitor: ActorRef,
                             peer: MCPeerID,
                             lobby: Weak<DeviceScannerViewController>) -> Receive {
        var alertHandle: AlertHandle?
        ^{ [weak self] in
            alertHandle = self?.alertPresenter.showAlert(title: "Switching lens")
        }
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case let lensCmd as UICmd.SwitchLens:
                if let f = self.sendMessage(
                    peer: [peer], msg: RemoteCmd.SwitchLens(lensType: lensCmd.lensType)) as? Failure {
                    self.this ! RemoteCmd.SwitchLensResp(lensType: nil, availableLenses: nil, currentZoom: nil, zoomRange: nil, error: f.error)
                }

            case let lensResp as RemoteCmd.SwitchLensResp:
                print("✅ DEBUG: Monitor received SwitchLensResp - lensType: \(lensResp.lensType?.displayName ?? "nil"), error: \(lensResp.error?.localizedDescription ?? "nil")")

                if let lensType = lensResp.lensType {
                    print("✅ DEBUG: Lens switch response success - lens: \(lensType.displayName)")
                    monitor ! lensResp
                    ^{ [weak self] in
                        if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                    }
                    print("🔍 DEBUG: Monitor lens switching state unbecoming")
                    self.unbecome()
                } else if let error = lensResp.error {
                    print("❌ DEBUG: Lens switch response error: \(error.localizedDescription)")
                    ^{ [weak self] in
                        if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                        self?.alertPresenter.showError(title: error._domain)
                    }
                    self.unbecome()
                } else {
                    print("❌ DEBUG: Received SwitchLensResp with no lensType and no error - this should not happen!")
                    ^{ [weak self] in
                        if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                    }
                    print("🔍 DEBUG: Force unbecoming from stuck lens switching state")
                    self.unbecome()
                }

            case let c as DisconnectPeer:
                ^{ [weak self] in
                    if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                }
                if c.peer.displayName == peer.displayName && self.connectedPeers.count == 0 {
                    self.popAndStartScanning()
                }

            case is UICmd.UnbecomeMonitor:
                ^{ [weak self] in
                    if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                }
                self.popToState(name: self.states.connected)

            default:
                print("ignoring lens message")
            }
        }
    }

    func monitorTogglingCamera(monitor: ActorRef,
                               peer: MCPeerID,
                               lobby: Weak<DeviceScannerViewController>) -> Receive {
        var alertHandle: AlertHandle?
        ^{ [weak self] in
            alertHandle = self?.alertPresenter.showAlert(title: "Requesting camera toggle")
        }
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is UICmd.ToggleCamera:
                if let f = self.sendMessage(
                    peer: [peer], msg: RemoteCmd.ToggleCamera()) as? Failure {
                    self.this ! RemoteCmd.ToggleCameraResp(
                        cameraCapabilities: nil, error: f.error
                    )
                }

            case let t as RemoteCmd.ToggleCameraResp:
                print("🔍 DEBUG: Monitor received ToggleCameraResp with capabilities: \(t.cameraCapabilities != nil)")

                // Extract camera position from capabilities
                let camPosition = t.cameraCapabilities?.currentCamera
                monitor ! UICmd.ToggleCameraResp(
                    flashMode: nil, // Flash mode is no longer provided in ToggleCameraResp
                    camPosition: camPosition, error: t.error)

                // IMPORTANT: Forward the new camera capabilities to update the UI
                if let capabilities = t.cameraCapabilities {
                    print("🔍 DEBUG: Forwarding new camera capabilities after toggle")
                    monitor ! capabilities
                }

                if t.cameraCapabilities != nil {
                    ^{ [weak self] in
                        if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                    }
                    self.unbecome()
                } else if let error = t.error {
                    ^{ [weak self] in
                        if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                        self?.alertPresenter.showError(title: error._domain)
                    }
                    self.unbecome()
                } else {
                    ^{ [weak self] in
                        if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                    }
                    self.unbecome()
                }

            case let c as DisconnectPeer:
                if c.peer.displayName == peer.displayName && self.connectedPeers.count == 0 {
                    ^{ [weak self] in
                        if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                    }
                    self.popAndStartScanning()
                }

            case is Disconnect:
                ^{ [weak self] in
                    if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                }
                self.popAndStartScanning()

            case is UICmd.UnbecomeMonitor:
                ^{ [weak self] in
                    if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                }
                self.popToState(name: self.states.connected)

            default:
                print("ignoring message")
            }
        }
    }
}
