//
//  ArrayAsStack.swift
//  Actors
//
//  Created by Dario on 10/5/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation

/**
 Stack data structure implementation for general purposes.
 */

public class Stack<A> {
    
    /**
     Undelying array, do not modify it directly
     */
    
    private var array : [A]
    
    /**
     Stack default construction
     
     - returns : empty Stack
     */
    
    public init() {
        self.array = [A]()
    }
    
    /**
     Push an element of type A into the Stack
     
     - parameter element : element to push
     */
    
    public func push(element : A) -> Void {
        self.array.insert(element, at: 0)
    }
    
    /**
     Pop an element from the Stack, if the stack is empty, it returns None
     */
    
    public func pop() -> Optional<A> {
        if let first = self.array.first {
            self.array.removeFirst()
            return first
        } else {
            return nil
        }
    }
    
    /**
     Pop an element from the Stack if not empty
     */
    
    public func popAndThrowAway() -> Void {
        if !self.isEmpty() {
            self.array.removeFirst()
        }
    }
    
    /**
     Peek into the stack, handy when you want to determine what's left in the Stack without removing the element from the stack
     */
    
    public func head() -> Optional<A> {
        return self.array.first
    }
    
    /**
     Method to determine if the stack is empty
     
     - returns : returns if the Stack is empty or not
     */
    
    public func isEmpty() -> Bool {
        return self.array.isEmpty
    }
    
}
