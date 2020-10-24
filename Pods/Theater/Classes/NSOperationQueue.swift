//
//  NSOperationQueue.swift
//  Actors
//
//  Created by Dario on 10/5/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation

prefix operator ^

/**
 Convenience operator that executes a block with type (Void) -> (Void) in the main queue.
 
 Replaces:
 
 ```
 let blockOp = NSBlockOperation({
 print("blah")
 })
 
 NSOperationQueue.mainQueue().addOperations([blockOp], waitUntilFinished: true)
 
 ```
 
 with
 
 ```
 ^{print("blah")}
 ```
 
 */

public prefix func ^ (block : @escaping () -> (Void)) -> Void {
    OperationQueue.main.addOperations([BlockOperation(block: block)], waitUntilFinished: true)
}

prefix operator ^^

/**
 Convenience operator that executes a block with type (Void) -> (Void) in the main queue and blocks until it's finished.
 
 Replaces:
 

 
 ```
 NSOperationQueue.mainQueue().addOperationWithBlock({
 print("blah")
 })
 ```
 
 with
 
 ```
 ^^{print("blah")}
 ```
 
 */

public prefix func ^^ (block : @escaping () -> (Void)) -> Void {
    OperationQueue.main.addOperations([BlockOperation(block: block)], waitUntilFinished: false)
}
