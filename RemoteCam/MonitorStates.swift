//
//  SessionMonitorStates.swift
//  Actors
//
//  Created by Dario Lencina on 11/1/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation
import Theater
import MultipeerConnectivity
import Photos

extension RemoteCamSession {
    
    func requestFrame(_ peer : [MCPeerID]) {
        // Use FlatBuffers for frame requests
        self.sendFlatBuffersFrameRequest(peer: peer)
    }
    
    func monitorTogglingFlash(monitor: ActorRef,
                              peer: MCPeerID,
                              lobby: Weak<DeviceScannerViewController>) -> Receive {
        var alert: UIAlertController?
        ^{
        alert = UIAlertController(title: "Requesting flash toggle",
                message: nil,
                preferredStyle: .alert)
        }
        return { [unowned self] (msg: Actor.Message) in
            switch msg {

            case is UICmd.ToggleFlash:
                ^{
                    alert?.show(true) {
                        self.mailbox.addOperation(BlockOperation {
                            self.sendFlatBuffersFlashToggle(peer: [peer])
                        })
                    }
                }

            case let fbResponse as FlatBuffersCameraStateResponse:
                print("🔍 DEBUG: Monitor toggling flash received FlatBuffers camera state response")
                print("🔍 DEBUG: Command success: \(fbResponse.response.success)")
                
                if fbResponse.response.success {
                    print("✅ Flash toggle success via FlatBuffers")
                    
                    // Create a legacy response for the UI
                    // For flash toggle, we'll create a ToggleFlashResp with a default flash mode
                    let legacyResponse = RemoteCmd.ToggleFlashResp(
                        flashMode: .auto, // Default flash mode since FlatBuffers doesn't include specific mode
                        error: nil
                    )
                    
                    monitor ! legacyResponse
                    
                    ^{
                        alert?.dismiss(animated: true) {
                            self.mailbox.addOperation(BlockOperation {
                                self.unbecome()
                            })
                        }
                    }
                } else {
                    let error = NSError(domain: "FlashError", code: 1, userInfo: [NSLocalizedDescriptionKey: fbResponse.response.error ?? "Flash toggle failed"])
                    ^{
                        alert?.dismiss(animated: true) {
                            let errorAlert = UIAlertController(title: error.domain,
                                                               message: error.localizedDescription,
                                                               preferredStyle: .alert)
                            errorAlert.simpleOkAction()
                            errorAlert.show(true)
                            self.mailbox.addOperation(BlockOperation {
                                self.unbecome()
                            })
                        }
                    }
                }

            case let c as DisconnectPeer:
                if c.peer.displayName == peer.displayName && self.session.connectedPeers.count == 0 {
                    ^{
                        alert?.dismiss(animated: true) {
                            self.mailbox.addOperation(BlockOperation {
                                self.popAndStartScanning()
                            })
                        }
                    }
                }

            case is Disconnect:
                ^{
                    alert?.dismiss(animated: true) {
                        self.mailbox.addOperation(BlockOperation {
                            self.popAndStartScanning()
                        })
                    }
                }

            case is UICmd.UnbecomeMonitor:
                ^{
                    alert?.dismiss(animated: true) {
                        self.mailbox.addOperation(BlockOperation {
                            self.popToState(name: self.states.connected)
                        })
                    }
                }

            default:
                print("ignoring message")
            }
        }
    }
    
    // MARK: - Lens Switching State
    func monitorSwitchingLens(monitor: ActorRef,
                             peer: MCPeerID,
                             lobby: Weak<DeviceScannerViewController>) -> Receive {
        var alert: UIAlertController?
        ^{
            alert = UIAlertController(title: "Switching lens",
                    message: nil,
                    preferredStyle: .alert)
        }
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case let lensCmd as UICmd.SwitchLens:
                ^{
                    alert?.show(true) {
                        self.mailbox.addOperation(BlockOperation {
                            if let f = self.sendMessage(
                                peer: [peer], msg: RemoteCmd.SwitchLens(lensType: lensCmd.lensType)) as? Failure {
                                self.this ! RemoteCmd.SwitchLensResp(lensType: nil, availableLenses: nil, currentZoom: nil, zoomRange: nil, error: f.error)
                            }
                        })
                    }
                }
                
            case let lensResp as RemoteCmd.SwitchLensResp:
                print("✅ DEBUG: Monitor received SwitchLensResp - lensType: \(lensResp.lensType?.displayName ?? "nil"), error: \(lensResp.error?.localizedDescription ?? "nil")")
                
                if let lensType = lensResp.lensType {
                    print("✅ DEBUG: Lens switch response success - lens: \(lensType.displayName)")
                    monitor ! lensResp
                    ^{
                        alert?.dismiss(animated: true) {
                            self.mailbox.addOperation(BlockOperation {
                                print("🔍 DEBUG: Monitor lens switching state unbecoming")
                                self.unbecome()
                            })
                        }
                    }
                } else if let error = lensResp.error {
                    print("❌ DEBUG: Lens switch response error: \(error.localizedDescription)")
                    ^{
                        alert?.dismiss(animated: true) {
                            let errorAlert = UIAlertController(title: error._domain,
                                                               message: nil,
                                                               preferredStyle: .alert)
                            errorAlert.simpleOkAction()
                            errorAlert.show(true)
                            self.mailbox.addOperation(BlockOperation {
                                self.unbecome()
                            })
                        }
                    }
                } else {
                    print("❌ DEBUG: Received SwitchLensResp with no lensType and no error - this should not happen!")
                    // Force dismiss the alert since we're stuck
                    ^{
                        alert?.dismiss(animated: true) {
                            self.mailbox.addOperation(BlockOperation {
                                print("🔍 DEBUG: Force unbecoming from stuck lens switching state")
                                self.unbecome()
                            })
                        }
                    }
                }
                
            case let c as DisconnectPeer:
                ^{
                    alert?.dismiss(animated: true)
                    if c.peer.displayName == peer.displayName && self.session.connectedPeers.count == 0 {
                        self.mailbox.addOperation(BlockOperation {
                            self.popAndStartScanning()
                        })
                    }
                }
                
            case is UICmd.UnbecomeMonitor:
                ^{
                    alert?.dismiss(animated: true) {
                        self.mailbox.addOperation(BlockOperation {
                            self.popToState(name: self.states.connected)
                        })
                    }
                }
                
            default:
                print("ignoring lens message")
            }
        }
    }

    func monitorTogglingCamera(monitor: ActorRef,
                               peer: MCPeerID,
                               lobby: Weak<DeviceScannerViewController>) -> Receive {
        var alert: UIAlertController?
        ^{
            alert = UIAlertController(title: "Requesting camera toggle",
                    message: nil,
                    preferredStyle: .alert)
        }
        return { [unowned self] (msg: Actor.Message) in
            switch msg {
            case is UICmd.ToggleCamera:
                ^{
                    alert?.show(true) {
                        self.mailbox.addOperation(BlockOperation {
                            self.sendFlatBuffersCameraToggle(peer: [peer])
                        })
                    }
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
                
                ^{
                    if t.cameraCapabilities != nil {
                        alert?.dismiss(animated: true) {
                            self.mailbox.addOperation(BlockOperation {
                                self.unbecome()
                            })
                        }
                    } else if let error = t.error {
                        alert?.dismiss(animated: true, completion: {
                            let errorAlert = UIAlertController(title: error._domain, message: nil, preferredStyle: .alert)
                            errorAlert.simpleOkAction()
                            errorAlert.show(true)
                            self.mailbox.addOperation(BlockOperation {
                                self.unbecome()
                            })
                        })
                    }
                }

            case let fbResponse as FlatBuffersCameraStateResponse:
                print("🔍 DEBUG: Monitor toggling camera received FlatBuffers camera state response")
                print("🔍 DEBUG: Command success: \(fbResponse.response.success)")
                
                if fbResponse.response.success {
                    print("✅ Camera toggle success via FlatBuffers")
                    
                    // Create a legacy response for the UI
                    // Since FlatBuffers doesn't include full capabilities, we'll request them separately
                    monitor ! UICmd.ToggleCameraResp(
                        flashMode: nil, // Flash mode not included in FlatBuffers response
                        camPosition: nil, // Camera position not included in FlatBuffers response
                        error: nil
                    )
                    
                    // Request fresh capabilities after successful toggle
                    self.sendCommandOrGoToScanning(peer: [peer], msg: RemoteCmd.RequestCameraCapabilities())
                    
                    ^{
                        alert?.dismiss(animated: true) {
                            self.mailbox.addOperation(BlockOperation {
                                self.unbecome()
                            })
                        }
                    }
                } else {
                    print("❌ Camera toggle failed via FlatBuffers")
                    let error = fbResponse.response.error != nil ? 
                        NSError(domain: "CameraError", code: 1, userInfo: [NSLocalizedDescriptionKey: fbResponse.response.error!]) : 
                        NSError(domain: "CameraError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"])
                    
                    monitor ! UICmd.ToggleCameraResp(
                        flashMode: nil,
                        camPosition: nil,
                        error: error
                    )
                    
                    ^{
                        alert?.dismiss(animated: true, completion: {
                            let errorAlert = UIAlertController(title: error.domain, message: error.localizedDescription, preferredStyle: .alert)
                            errorAlert.simpleOkAction()
                            errorAlert.show(true)
                            self.mailbox.addOperation(BlockOperation {
                                self.unbecome()
                            })
                        })
                    }
                }

            case let c as DisconnectPeer:
                if c.peer.displayName == peer.displayName && self.session.connectedPeers.count == 0 {
                    ^{
                        alert?.dismiss(animated: true) {
                            self.mailbox.addOperation(BlockOperation {
                                self.popAndStartScanning()
                            })
                        }
                    }
                }

            case is Disconnect:
                ^{
                    alert?.dismiss(animated: true) {
                        self.mailbox.addOperation(BlockOperation {
                            self.popAndStartScanning()
                        })
                    }
                }

            case is UICmd.UnbecomeMonitor:
                ^{
                    alert?.dismiss(animated: true) {
                        self.mailbox.addOperation(BlockOperation {
                            self.popToState(name: self.states.connected)
                        })
                    }
                }

            default:
                print("ignoring message")
            }
        }
    }
}
