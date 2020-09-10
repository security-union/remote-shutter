//
//  WithListeners.swift
//  Actors
//
//  Created by Dario Lencina on 10/24/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation

/**
 Generic protocol so that Actors can have a collection of observers.
 */

public protocol WithListeners : class {
    
    var listeners : [ActorRef] { get set }
    
    /**
     adds sender to listeners
     
     - parameter sender : ActorRef to add to the listeners
     */
    
    func addListener(sender : ActorRef?)
    
    /**
     removes sender from listeners
     
     - parameter sender : ActorRef to remove from the listeners collection
     */
    
    func removeListener(sender : ActorRef?)
    
    /**
     Send message to all listeners
     
     -parameter m : message to send
     */
    
    func broadcast(msg : Actor.Message)
    
}

/**
 This default implementation of WithListeners mantains the listeners collection so that the Actor does not have to deal with that.
 */

extension WithListeners {
    
    /**
     adds sender to listeners
     
     - parameter sender : ActorRef to add to the listeners
     */
    
    public func addListener(sender : ActorRef?) {
        if let s = sender {
            
            if (listeners.contains(where: { a -> Bool in return s.path.asString == a.path.asString}) == false) {
                listeners.append(s)
            }
        }
    }
    
    /**
     removes sender from listeners
     
     - parameter sender : ActorRef to remove from the listeners collection
     */
    
    public func removeListener(sender : ActorRef?) {
        if let l = sender,
            let n = listeners.firstIndex(where:{ a -> Bool in  return l.path.asString == a.path.asString}) {
            listeners.removeFirst(n)
        }
    }
    
    /**
     Send message to all listeners
     
     -parameter msg : message to send
     */
    
    public func broadcast(msg : Actor.Message) { listeners.forEach { $0 ! msg} }
}
