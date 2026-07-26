//
//  MultipeerMessages.swift
//  Actors
//
//  Created by Dario on 10/7/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation
import MPCCompat
import PeerMesh
import AVFoundation

enum DeviceRole {
    case camera
    case monitor
}

public class Disconnect: Message, @unchecked Sendable {

}

public class ConnectToDevice: Message, @unchecked Sendable {
    public let peer: PeerID

    public init(peer: PeerID, sender: AnyObject?) {
        self.peer = peer
        super.init(sender: sender)
    }
}

public class DisconnectPeer: Message, @unchecked Sendable {
    public let peer: PeerID?

    public init(peer: PeerID?, sender: AnyObject?) {
        self.peer = peer
        super.init(sender: sender)
    }
}

public class OnConnectToDevice: Message, @unchecked Sendable {
    public let peer: PeerID

    public init(peer: PeerID, sender: AnyObject?) {
        self.peer = peer
        super.init(sender: sender)
    }
}

