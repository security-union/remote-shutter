//
//  Actor.swift
//  Actors
//
//  Created by Dario Lencina on 9/26/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation

infix operator ! : SendMessagePrecedence

precedencegroup SendMessagePrecedence {
    associativity: left
}

/**
 
 '!' Is a shortcut for typing:
 
 ```
 actor ! msg
 ```
 
 instead of
 
 ```
 actorRef.tell(msg)
 ```
 
 */

public func !(actorRef : ActorRef, msg : Actor.Message) -> Void {
    actorRef.tell(msg: msg)
}

public typealias Receive = (Actor.Message) -> (Void)

/**
 
 'Actor'
 
 Actors are the central elements of Theater.
 
 ## Subclassing notes
 
 You must subclass Actor to implement your own actor classes such as: BankAccount, Device, Person etc.
 
 the single most important to override is
 
 ```
 public func receive(msg : Actor.Message) -> Void
 ```
 
 Which will be called when some other actor tries to ! (tell) you something
 
 */

open class Actor : NSObject {
    
    public func actorForRef(ref : ActorRef) -> Optional<Actor> {
        let path = ref.path.asString
        if path == this.path.asString {
            return self
        }else if let selected = self.children[path] {
            return selected
        } else {
            //TODO: this is expensive an wasteful
            let recursiveSearch = self.children.map({return $0.1.actorForRef(ref:ref)})
            
            let withoutOpt = recursiveSearch.filter({return $0 != nil}).compactMap({return $0})
            
            return withoutOpt.first
        }
    }
    
    public func stop() {
        this ! Harakiri(sender:nil)
    }
    
    public func stop(actorRef : ActorRef) -> Void {
        self.mailbox.addOperation { () -> Void in
            let path = actorRef.path.asString
            self.children.removeValue(forKey:path)
        }
    }
    
    public func actorOf(clz : Actor.Type) -> ActorRef {
        return actorOf(clz: clz, name: UUID.init().uuidString)
    }
    
    public func actorOf(clz : Actor.Type, name : String) -> ActorRef {
        
        //TODO: should we kill or throw an error when user wants to reuse address of actor?
        let completePath = "\(self.this.path.asString)/\(name)"
        let ref = ActorRef(context:self.context, path:ActorPath(path:completePath))
        let actorInstance : Actor = clz.init(context: self.context, ref: ref)
        self.children[completePath] = actorInstance
        return ref
    }
    
    /**
     
     */
    
    final var children  = [String : Actor]()
    
    public func getChildrenActors() -> [String: ActorRef] {
        var newDict : [String:ActorRef] = [String : ActorRef]()
        
        for (k,v) in self.children {
            newDict[k] = v.this
        }
        return newDict
    }
    
    /**
     Here we save all the actor states
     */
    
    final let statesStack : Stack<(String,Receive)> = Stack()
    
    /**
     Each actor has it's own mailbox to process Actor.Messages.
     */
    
    final public let mailbox : OperationQueue = OperationQueue()
    
    /**
     Sender has a reference to the last actor ref that sent this actor a message
     */
    
    public var sender : Optional<ActorRef>
    
    /**
     Reference to the ActorRef of the current actor
     */
    
    public let this : ActorRef
    
    /**
     Context refers to the Actor System that this actor belongs to.
     */
    
    public let context : ActorSystem
    
    /**
     Actors can adopt diferent behaviours or states, you can "push" a new state into the statesStack by using this method.
     
     - Parameter state: the new state to push
     - Parameter name: The name of the new state, it is used in the logs which is very useful for debugging
     */
    
    final public func become(name : String, state : @escaping Receive) -> Void  {
        become(name: name, state : state, discardOld : false)
    }
    
    /**
     Actors can adopt diferent behaviours or states, you can "push" a new state into the statesStack by using this method.
     
     - Parameter state: the new state to push
     - Parameter name: The name of the new state, it is used in the logs which is very useful for debugging
     */
    
    final public func become(name : String, state : @escaping Receive, discardOld : Bool) -> Void  {
        if discardOld { self.statesStack.popAndThrowAway() }
        self.statesStack.push(element: (name, state))
    }
    
    /**
     Pop the state at the head of the statesStack and go to the previous stored state
     */
    
    final public func unbecome() {
        self.statesStack.popAndThrowAway()
    }
    
    /**
     Current state
     - Returns: The state at the top of the statesStack
     */
    
    final public func currentState() -> (String,Receive)? {
        return self.statesStack.head()
    }
    
    /**
     Pop states from the statesStack until it finds name
     - Parameter name: the state that you can to pop to.
     */
    
    public func popToState(name : String) -> Void {
        if let (hName, _ ) = self.statesStack.head() {
            if hName != name {
                unbecome()
                popToState(name: name)
            }
        } else {
            print("unable to find state with name \(name)")
        }
    }
    
    /**
     pop to root state
     */
    
    public func popToRoot() -> Void {
        while !self.statesStack.isEmpty() {
            unbecome()
        }
    }
    
    /**
     This method handles all the system related messages, if the message is not system related, then it calls the state at the head position of the statesstack, if the stack is empty, then it calls the receive method
     */
    
    final public func systemReceive(msg : Actor.Message) -> Void {
        switch msg {
        case is Harakiri, is PoisonPill:
            self.willStop()
            self.children.forEach({ (_,actor) in
                actor.this ! Harakiri(sender:this)
            })
            self.context.stop(actorRef: self.this)
            
        default :
            if let (name,state) : (String,Receive) = self.statesStack.head() {
                print("Sending message to state \(name)")
                state(msg)
            } else {
                self.receive(msg: msg)
            }
        }
    }
    
    /**
     This method will be called when there's an incoming message, notice that if you push a state int the statesStack this method will not be called anymore until you pop all the states from the statesStack.
     
     - Parameter msg: the incoming message
     */
    
    open func receive(msg : Actor.Message) -> Void {
        switch msg {
        default :
            print("message not handled \(NSStringFromClass(type(of: msg)))")
        }
    }
    
    /**
     This method is used by the ActorSystem to communicate with the actors, do not override.
     */
    
    final public func tell(msg : Actor.Message) -> Void {
        mailbox.addOperation { () in
            self.sender = msg.sender
            print("\(self.sender?.path.asString ?? "No Sender") told \(msg) to \(self.this.path.asString)")
            self.systemReceive(msg: msg)
        }
    }
    
    /**
     Is called when an Actor is started. Actors are automatically started asynchronously when created. Empty default implementation.
     */
    
    open func preStart() -> Void {
        
    }
    
    /**
     Method to allow cleanup
     */
    
    open func willStop() -> Void {
        
    }
    
    /**
     Schedule Once is a timer that executes the code in block after seconds
     */
    
    final public func scheduleOnce(seconds:Double, block : @escaping () -> Void) {
        self.mailbox.underlyingQueue!.asyncAfter(deadline: DispatchTime(uptimeNanoseconds: UInt64(seconds)), execute: block)
    }
    
    /**
     Default constructor used by the ActorSystem to create a new actor, you should not call this directly, use  actorOf in the ActorSystem to create a new actor
     */
    
    required public init(context : ActorSystem, ref : ActorRef) {
        mailbox.maxConcurrentOperationCount = 1 //serial queue
        sender = nil
        self.context = context
        self.this = ref
        super.init()
        self.preStart()
    }
    
    public init(context : ActorSystem) {
        mailbox.maxConcurrentOperationCount = 1 //serial queue
        sender = nil
        self.context = context
        self.this = ActorRef(context: context, path: ActorPath(path: ""))
        super.init()
        self.preStart()
    }
    
    deinit {
        print("killing \(self.this.path.asString)")
    }
    
}
