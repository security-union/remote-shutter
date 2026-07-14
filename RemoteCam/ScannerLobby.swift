//
//  ScannerLobby.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union. All rights reserved.
//

import Foundation
import MultipeerConnectivity

/// Everything `RemoteCamSession` needs from the device-scanner screen.
///
/// `DeviceScannerViewController` is the production implementation; tests
/// drive the session with a fake. This is the seam that keeps the session
/// actor ignorant of UIKit.
///
/// `Sendable` because the session actor captures the lobby in main-queue
/// hops; the production conformer is a main-actor view controller.
protocol ScannerLobby: AnyObject, Sendable {

    var peerID: MCPeerID { get }
    var role: DeviceRole { get }
    var scannerViewModel: DeviceScannerViewModel { get }

    /// Navigate to the role picker after a peer connects.
    func goToRole()

    /// Pop navigation back to the scanner screen (called when scanning restarts).
    func returnToLobby()

    /// Surface a "can't scan for nearby devices" failure to the user.
    func presentScanningError()
}

/// Binds a `ScannerLobby` to `RemoteCamSession` — the protocol-typed
/// counterpart of Theater's `SetViewCtrl` (whose generic parameter requires
/// a concrete class).
public class SetScannerLobby: Message, @unchecked Sendable {
    let lobby: ScannerLobby

    init(lobby: ScannerLobby) {
        self.lobby = lobby
        super.init(sender: nil)
    }
}

/// Weak box for the lobby — `Weak<T>` requires a concrete class type, and
/// the lobby is deliberately a protocol existential.
final class WeakScannerLobby {
    weak var value: ScannerLobby?
    init(_ value: ScannerLobby) { self.value = value }
}
