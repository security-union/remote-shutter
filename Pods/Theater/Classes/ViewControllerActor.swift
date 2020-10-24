//
//  ViewControllerActor.swift
//  ActorsParty
//
//  Created by Dario on 10/30/15.
//  Copyright © 2015 Dario. All rights reserved.
//

import UIKit


/**
    This message is used to set the view controller to a subclass of ViewCtrlActor
*/

public class SetViewCtrl<T : UIViewController> : Actor.Message {
    
    /**
     Da controller
    */
    
    public let ctrl : T
    
    /**
     Constructor
    */
    
    public init(ctrl : T) {
        self.ctrl = ctrl
        super.init(sender: nil)
    }
}

/**
 Convenience subclass of Actor to bind a UIViewController, which is very common when dealing with UIKit.
*/

open class ViewCtrlActor<A : UIViewController> : Actor {
    
    public let waitingForCtrlState = "waitingForCtrl"
    
    public let withCtrlState = "withCtrl"
    
    /**
    Subclasses must override this constructor.
    */
    
    required public init(context : ActorSystem, ref : ActorRef) {
        super.init(context: context, ref: ref)
    }
    
    /**
    By default, the ViewCtrlActor instances go to the waitingForCtrl state.
    */
    
    override open func preStart() {
        super.preStart()
        self.become(name: self.waitingForCtrlState, state: self.waitingForCtrl)
    }
    
    /**
    This built in method waits for a SetViewCtrl message to transition to the withCtrl state.
    */
    
    final lazy var waitingForCtrl : Receive = {[unowned self](msg : Actor.Message) in
        switch(msg) {
            case let a as SetViewCtrl<A>:
                unowned let b = a.ctrl
                self.become(name: self.withCtrlState, state:self.receiveWithCtrl(ctrl:b))
                
            default:
                self.receive(msg: msg)
        }
    }
    
    /**
     Pop states from the statesStack until it finds name
     - Parameter name: the state that you can to pop to.
     */
    
    public override func popToState(name : String) -> Void {
        if let (hName, _ ) = self.statesStack.head() {
            if hName != name && hName != self.withCtrlState {
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
    
    public override func popToRoot() -> Void {
        popToState(name: self.withCtrlState)
    }
    
    /**
     Subclasses of ViewCtrlActor must override this method to handle messages.
     
     - parameter ctrl : controller that was set to this Actor
    */
    
    open func receiveWithCtrl(ctrl : A) -> Receive {
        return { (msg : Actor.Message) in }
    }
    
    deinit {
        print("killing")
    }
    
}

