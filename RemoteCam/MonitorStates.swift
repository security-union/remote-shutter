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

    private static let transientStateTimeout: TimeInterval = 10.0

    func scheduleTimeout(stateName: RemoteCamState) -> Int {
        _timeoutGeneration += 1
        let generation = _timeoutGeneration
        let actorRef = self.this
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.transientStateTimeout) { [weak self] in
            guard self != nil else { return }
            actorRef ! UICmd.StateTimeout(stateName: stateName, generation: generation)
        }
        return generation
    }

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
        let gen = self.scheduleTimeout(stateName: .monitorTogglingFlash)
        return { [unowned self] (msg: Actor.Message) in
            switch msg {

            case let timeout as UICmd.StateTimeout:
                if timeout.stateName == .monitorTogglingFlash && timeout.generation == gen {
                    ^{ [weak self] in
                        if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                    }
                    self.unbecome()
                }

            case is UICmd.ToggleFlash:
                break // Already sent from parent state; ignore duplicate taps

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
                ^{ [weak self] in
                    if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                }
                self.cameraRegistry.remove(peer: c.peer)
                if self.cameraRegistry.isEmpty {
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
                self.popToState(name: .connected)

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
        let gen = self.scheduleTimeout(stateName: .monitorSwitchingLens)
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case let timeout as UICmd.StateTimeout:
                if timeout.stateName == .monitorSwitchingLens && timeout.generation == gen {
                    ^{ [weak self] in
                        if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                    }
                    self.unbecome()
                }

            case is UICmd.SwitchLens:
                break // Already sent from parent state; ignore duplicate taps

            case let lensResp as RemoteCmd.SwitchLensResp:
                debugLog("✅ DEBUG: Monitor received SwitchLensResp - lensType: \(lensResp.lensType?.displayName ?? "nil"), error: \(lensResp.error?.localizedDescription ?? "nil")")

                if let lensType = lensResp.lensType {
                    debugLog("✅ DEBUG: Lens switch response success - lens: \(lensType.displayName)")
                    monitor ! lensResp
                    ^{ [weak self] in
                        if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                    }
                    debugLog("🔍 DEBUG: Monitor lens switching state unbecoming")
                    self.unbecome()
                } else if let error = lensResp.error {
                    debugLog("❌ DEBUG: Lens switch response error: \(error.localizedDescription)")
                    ^{ [weak self] in
                        if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                        self?.alertPresenter.showError(title: error._domain)
                    }
                    self.unbecome()
                } else {
                    debugLog("❌ DEBUG: Received SwitchLensResp with no lensType and no error - this should not happen!")
                    ^{ [weak self] in
                        if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                    }
                    debugLog("🔍 DEBUG: Force unbecoming from stuck lens switching state")
                    self.unbecome()
                }

            case let c as DisconnectPeer:
                ^{ [weak self] in
                    if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                }
                self.cameraRegistry.remove(peer: c.peer)
                if self.cameraRegistry.isEmpty {
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
                self.popToState(name: .connected)

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
        let gen = self.scheduleTimeout(stateName: .monitorTogglingCamera)
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case let timeout as UICmd.StateTimeout:
                if timeout.stateName == .monitorTogglingCamera && timeout.generation == gen {
                    ^{ [weak self] in
                        if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                    }
                    self.unbecome()
                }

            case is UICmd.ToggleCamera:
                break // Already sent from parent state; ignore duplicate taps

            case let t as RemoteCmd.ToggleCameraResp:
                debugLog("🔍 DEBUG: Monitor received ToggleCameraResp with capabilities: \(t.cameraCapabilities != nil)")

                // Extract camera position from capabilities
                let camPosition = t.cameraCapabilities?.currentCamera
                monitor ! UICmd.ToggleCameraResp(
                    flashMode: nil, // Flash mode is no longer provided in ToggleCameraResp
                    camPosition: camPosition, error: t.error)

                // IMPORTANT: Forward the new camera capabilities to update the UI
                if let capabilities = t.cameraCapabilities {
                    debugLog("🔍 DEBUG: Forwarding new camera capabilities after toggle")
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
                ^{ [weak self] in
                    if let h = alertHandle { self?.alertPresenter.dismissAlert(h) }
                }
                self.cameraRegistry.remove(peer: c.peer)
                if self.cameraRegistry.isEmpty {
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
                self.popToState(name: .connected)

            default:
                print("ignoring message")
            }
        }
    }
}
