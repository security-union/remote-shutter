//
//  ActorContext.swift
//  Actors
//
//  Created by Dario Lencina on 9/27/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation

/**
 An actor system has a tree like structure, ActorPath gives you an url like way to find an actor inside a given actor system.
 
 @warning: We still do not support multiple levels of actors. Currently all actors are direct children of the ActorSystem that it belongs to.
 */

public class ActorPath {
    
    public let asString : String
    
    public init(path : String) {
        self.asString = path
    }
}

/**
 'ActorRef' provides a reference to a given 'Actor', you should always talk to actors though it's ActorRef.
 */

public class ActorRef {
    
    
    
    /**
     The actor system that this ActorRef belongs to
     */
    
    public let context : ActorSystem
    
    /**
     The Path to this ActorRef
     */
    
    public let path : ActorPath
    
    /**
     This constructor is used by the ActorSystem, should not be used by developers
     */
    
    public init(context : ActorSystem, path : ActorPath) {
        self.context = context
        self.path = path
    }
    
    /**
     This method is used to send a message to the underlying Actor.
     
     - parameter msg : The message to send to the Actor.
     */
    
    public func tell (msg : Actor.Message) -> Void {
        self.context.tell(msg: msg, recipient:self)
    }
    
}

/**
 The first rule about actors is that you should not access them directly, you always talk to them through it's ActorRef, but for testing sometimes is really convenient to just get the actor and inspect it's properties, that is the reason why we provide 'TestActorSystem' please do not use it in your AppCode, only in tests.
 */

public class TestActorSystem : ActorSystem {
    public override func actorForRef(ref : ActorRef) -> Optional<Actor> {
        return super.actorForRef(ref: ref)
    }
}

/**
 
 All actors live in 'ActorSystem'.
 
 You might have more than 1 actor system.
 
 For convenience, we provide AppActorSystem.shared which provides a default actor system.
 
 */

open class ActorSystem  {
    
    lazy private var supervisor : Actor? = Actor.self.init(context: self, ref: ActorRef(context: self, path: ActorPath(path: "\(self.name)/user")))
    
    /**
     DispatchQueue used to perform general maintanence operations.
     */
    private let dispatchQueue : DispatchQueue
    
    
    /**
     
     The name of the 'ActorSystem'
     
     */
    
    let name : String
    
    /**
     Create a new actor system
     
     - parameter name : The name of the ActorSystem
     */
    
    public init(name : String) {
        self.name = name
        self.dispatchQueue = DispatchQueue(label: name)
    }
    
    /**
     This is used to stop or kill an actor
     
     - parameter actorRef : the actorRef of the actor that you want to stop.
     */
    
    public func stop(actorRef : ActorRef) -> Void {
        supervisor!.stop(actorRef: actorRef)
    }
    
    public func stop() {
        supervisor!.stop()
        //TODO: there must be a better way to wait for all actors to die...
        func shutdown(){
            self.dispatchQueue.asyncAfter(deadline: DispatchTime(uptimeNanoseconds: 5000), execute: {
                if(self.supervisor!.children.count == 0) {
                    self.supervisor = nil
                }
            })
        }
        shutdown()
    }
    
    /**
     This method is used to instantiate actors using an Actor class as the 'blueprint' and assigning a unique name to it.
     
     - parameter clz: Actor Class
     - parameter name: name of the actor, it has to be unique
     - returns: Actor ref instance
     
     ## Example
     
     ```
     var wsCtrl : ActorRef = actorSystem.actorOf(WSRViewController.self, name:  "WSRViewController")
     ```
     */
    
    public func actorOf(clz : Actor.Type, name : String) -> ActorRef {
        return supervisor!.actorOf(clz: clz, name: name)
    }
    
    /**
     This method is used to instantiate actors using an Actor class as the 'blueprint' and assigning a unique name to it.
     
     - parameter clz: Actor Class
     - returns: Actor ref instance with a random UUID as name
     
     ##Example:
     
     ```
     var wsCtrl : ActorRef = actorSystem.actorOf(WSRViewController.self)
     ```
     
     */
    
    public func actorOf(clz : Actor.Type) -> ActorRef {
        return actorOf(clz: clz, name: UUID.init().uuidString)
    }
    
    /**
     Private method to get the underlying actor given an actor ref, remember that you shoulf never access an actor directly other than for testing.
     
     - parameter ref: reference to resolve
     */
    
    func actorForRef(ref : ActorRef) -> Optional<Actor> {
        if let s = self.supervisor {
            return s.actorForRef(ref: ref)
        } else {
            return nil
        }
    }
    
    /**
     This method tries finding an actor given it's actorpath as a string
     
     - Parameter actorPath : the actor path as string
     - returns : an ActorRef or None
     */
    
    public func selectActor(actorPath : String) -> Optional<ActorRef>{
        return self.supervisor!.children[actorPath].map({ (a : Actor) -> ActorRef in return a.this})
    }
    
    /**
     All messages go through this method, eventually we will create an scheduler
     
     - parameter msg : message to send
     - parameter recipient : the ActorRef of the Actor that you want to receive the message.
     */
    
    public func tell(msg : Actor.Message, recipient : ActorRef) -> Void {
        
        if let actor = actorForRef(ref: recipient) {
            actor.tell(msg: msg)
        } else if let sender = msg.sender, let _ = actorForRef(ref: sender) {
            sender ! Actor.DeadLetter(message: msg, sender:recipient)
        } else {
            print("Dropped message \(msg)")
        }
    }
    
    deinit {
        print("killing ActorSystem: \(name)")
    }
}
