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

public class Disconnect: Actor.Message {

}

public class ConnectToDevice: Actor.Message {
    public let peer: MCPeerID

    public init(peer: MCPeerID, sender: ActorRef?) {
        self.peer = peer
        super.init(sender: sender)
    }
}

public class DisconnectPeer: Actor.Message {
    public let peer: MCPeerID?

    public init(peer: MCPeerID?, sender: ActorRef?) {
        self.peer = peer
        super.init(sender: sender)
    }
}

public class OnConnectToDevice: Actor.Message {
    public let peer: MCPeerID

    public init(peer: MCPeerID, sender: ActorRef?) {
        self.peer = peer
        super.init(sender: sender)
    }
}

