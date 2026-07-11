//
//  MultipeerMessages.swift
//  Actors
//
//  Created by Dario on 10/7/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation
import MultipeerConnectivity
import AVFoundation

enum DeviceRole {
    case camera
    case monitor
}

public class Disconnect: Message {

}

public class ConnectToDevice: Message {
    public let peer: MCPeerID

    public init(peer: MCPeerID, sender: AnyObject?) {
        self.peer = peer
        super.init(sender: sender)
    }
}

public class DisconnectPeer: Message {
    public let peer: MCPeerID?

    public init(peer: MCPeerID?, sender: AnyObject?) {
        self.peer = peer
        super.init(sender: sender)
    }
}

public class OnConnectToDevice: Message {
    public let peer: MCPeerID

    public init(peer: MCPeerID, sender: AnyObject?) {
        self.peer = peer
        super.init(sender: sender)
    }
}

