//
//  Actor.Message.swift
//  Actors
//
//  Created by Dario Lencina on 9/26/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation

extension Actor {
    
    /**
     Actor send and receive objects that must subclass Message, the Message class provides a sender, which Actors can use to reply.
     */
    
    @objc open class Message : NSObject {
        
        /**
         The ActorRef of the Actor that sent this message
         */
        
        public let sender : Optional<ActorRef>
        
        /**
         The constuctor requires an Optional<ActorRef> to setup the sender
         */
        
        public init(sender : Optional<ActorRef> = nil) {
            self.sender = sender
        }
        
    }
    
    /**
     Harakiri is the default Message that forces an Actor to commit suicide, this behaviour can be changed once you override the #Actor.receive method.
     */
    
    public class Harakiri : Message {}
    
    /**
         Called when an actor transitions to a particular state.
     */
    public class OnEnter: Message {}
    
    /**
     PoisonPill is the same than Harakiri but for Akka fans, like me.
     */
    
    public class PoisonPill : Message {}
    
    /**
     Convenient Message subclass which has an operationId that can be used to track a transaction or some sort of message that needs to be tracked
     */
    
    open class MessageWithOperationId : Message {
        
        /**
         
         The operationId used to track the Operation
         
         */
        public let operationId : UUID
        
        public init(sender: Optional<ActorRef>, operationId : UUID) {
            self.operationId = operationId
            super.init(sender : sender)
        }
    }
    
    /**
     This is an Actor System generated message that is sent to the sender when it tries to send a message to an Actor that has been stopped beforehand.
     */
    
    public class DeadLetter : Message {
        
        public let message : Message
        
        public init(message : Actor.Message, sender: Optional<ActorRef>) {
            self.message = message
            super.init(sender: sender)
        }
    }
    
}
