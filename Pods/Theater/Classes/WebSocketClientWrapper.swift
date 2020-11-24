//
//  WebSocketClientWrapper.swift
//  Actors
//
//  Created by Dario Lencina on 9/29/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation
import Starscream

/**
WebSocketClientWrapper messages
*/

extension WebSocketClientWrapper {
    
    /**
    Connect command
    */

    public class Connect : Actor.Message {
        public let url : NSURL
        
        public init(url : NSURL, sender : ActorRef?) {
            self.url = url
            super.init(sender: sender)
        }
    }
    
    /**
     Disconnect command
     */

    public class Disconnect : Actor.Message {}
    
    /**
     Send message command
     */
    
    public class SendMessage : OnMessage {}
    
    /**
     Message broadcasted when there is an incoming WebSocket message
     */

    public class OnMessage : Actor.Message {
        public let message : String
        
        public init(sender: ActorRef?, message : String) {
            self.message = message
            super.init(sender: sender)
        }
    }
    
    /**
     Message broadcasted when there is incoming WebSocket data
     */

    public class OnData : Actor.Message {
        public let data : Data
        
        public init(sender: ActorRef?, data : Data) {
            self.data = data
            super.init(sender: sender)
        }
    }
    
    /**
     Message broadcasted when the websocket get's disconnected
     */

    public class OnDisconnect : Actor.Message {
        public let error : String?
        
        init(sender: ActorRef?, error :String?) {
            self.error = error
            super.init(sender: sender)
        }
    }
    
    /**
     Message broadcasted when the websocket get's connected
     */

    public class OnConnect : Actor.Message {}
        
}

/**
 Actor Wrapper for Starscream WebSocket
 */

public class WebSocketClientWrapper : Actor , WebSocketDelegate,  WithListeners {
    
    /**
     Collection with actors that care about changes in BLECentral
     */

    public var listeners : [ActorRef] = [ActorRef]()
    
    override public func preStart() {
        super.preStart()
        become(name: "disconnected", state: disconnected)
    }
    
    /**
         Websocket events
     */
    public func didReceive(event: WebSocketEvent, client: WebSocket) {
        switch event {
        case .connected(_):
            self.broadcast(msg: OnConnect(sender: this))
            self.become(name: "connected", state: self.connected(socket: client))
        
        case .disconnected(let error, _):
            self.broadcast(msg: OnDisconnect(sender: self.this, error: error))
            self.become(name: "disconnected", state: disconnected)
        case .text(let text):
            self.broadcast(msg: OnMessage(sender: this, message: text))
        case .binary(let data):
            self.broadcast(msg: OnData(sender: this, data: data))
            
        default:
            break
        }
    }
    
    /**
    stupid variable to keep websocket around.
    */
    var socket : WebSocket?
    
    /**
     disconnected is the initial state of the websocket
     */
    
    lazy var disconnected : Receive = {[unowned self](msg : Actor.Message) in
        switch (msg) {
        case let c as Connect:
            let socket = WebSocket(request:URLRequest(url:URL(string: c.url.absoluteString!)!))
            self.socket = socket
            socket.delegate = self
            self.addListener(sender: c.sender)
            socket.connect()
            
        default:
            self.receive(msg: msg)
        }
    }
    
    /**
     state when the websocket is connected
     */
    
    func connected(socket: WebSocketClient) -> Receive {
        return {[unowned self](msg : Actor.Message) in
            switch(msg) {
            case let c as SendMessage:
                socket.write(string:c.message)
                
            case is Disconnect:
                socket.disconnect()
                self.unbecome()
                
            default:
                self.receive(msg: msg)
            }
        }
    }
    
    /**
    Cleanup
    */
    
    deinit {
        self.this ! Disconnect(sender: nil)
    }
    
}
