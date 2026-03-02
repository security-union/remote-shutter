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
 Convenience operator that asynchronously executes a block on the main queue.
 Use this for UI updates from actor message handlers.

 ```
 ^{print("blah")}
 ```
 */

public prefix func ^ (block : @escaping () -> (Void)) -> Void {
    OperationQueue.main.addOperations([BlockOperation(block: block)], waitUntilFinished: false)
}

prefix operator ^^

/**
 Convenience operator that asynchronously executes a block on the main queue.
 Identical to `^` — both dispatch asynchronously.

 ```
 ^^{print("blah")}
 ```
 */

public prefix func ^^ (block : @escaping () -> (Void)) -> Void {
    OperationQueue.main.addOperations([BlockOperation(block: block)], waitUntilFinished: false)
}
