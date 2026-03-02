//
//  Try.swift
//  Actors
//
//  Created by Dario Lencina on 9/26/15.
//  Copyright © 2015 dario. All rights reserved.
//

import Foundation

/**
Try<T> is an attempt to expose the posibility of a function failing without throwing an exception.

Provides a cleaner way to express that a method might fail.

A computation, generally, might succeed or fail, that is why, we implement Success<T> and Failure<T>.

This implementation is based on Scala, it would be nice if Swift protocols would allow you to use generics, but because it does not, I had to use a class.
*/

public class Try<T> : NSCoder {
    
    /**
    Exception used in case that developers try to use this class directly, Success or Failure should be used instead, I'll try to replace this for a protocol when Apple supports generics on protocols.
    */
    
    private let e : NSException = NSException(name: NSExceptionName(rawValue: "invalid usage"), reason: "please do not use this class directly, use Success || Failure", userInfo: nil)

    /**
    flag to determine if the computation was successful or not
    */
    
    public func isFailure() -> Bool {e.raise(); return false}
    
    /**
    flag to determine if the computation was successful or not
    */
    
    public func isSuccess() -> Bool {e.raise(); return false}
    
    /**
    Convenience method to transform Try<T> into Optional<T> if Success<T> -> Optional.Some(T) else Failure<T> -> nil, that way, we can use it like this
      ```
        wsResult : Try<Number> = getNumberOfLikes()
        .
        .
        .
        
        if let double = wsResult.toOptional {
            //Success
        } else {
            //Failure
        }
      ```
    */
    
    public func toOptional() -> Optional<T> {
        return  nil
    }
    
    public func get() -> T { e.raise(); return NSObject() as! T}
    
    /**
    Functional way to unwrap the Try<T>
    */
    
    public func map<U>(f : (T) -> (U)) -> Try<U> {return Try<U>()}
    
    public func getOrElse(d : () -> T) -> T {
        if self.isSuccess() {
            return get()
        }else{
            return d()
        }
    }
    
    class func gen(r: T) -> Try<T> {
        do {
            let s = Success(r)
            return s
        } catch let error as Error {
            return Failure(error : error)
        }
    }
    
    override public init() {
        super.init()
    }
    
    /**
     encoder used to serialize a Try<T>
     */
    
    public func encodeWithCoder(aCoder: NSCoder) {

    }
    
    
    /**
     coder used to decode a Try<T>
     */
    
    public init?(coder aDecoder: NSCoder) {
        super.init()
    }
}

/**
Success<T> is a way to express that a given computation was successful.
*/

public class Success<T> : Try<T> {
    
    private let value : T
    
    public init( _ value : T) {
        self.value = value
        super.init()
    }
    
    /**
    flag to determine if the computation was successful or not
    */
    
    override public func isFailure() -> Bool {return false}
    
    /**
    flag to determine if the computation was successful or not
    */
    
    override public func isSuccess() -> Bool { return true}
    
    /**
    gets the underlying value
    - returns : underlying value
    */
    
    override public func get() -> T {return self.value}
    
    /**
    Functional way to unwrap the Try<T>
    */
    
    override public func map<U>(f : (T) -> (U)) -> Try<U> {
        return Try<U>.gen(r: f(self.value))
    }
    
    /**
    Convenience method to transform Try<T> into Optional<T> if Success<T> -> Optional.Some(T) else Failure<T> -> nil, that way, we can use it like this
         ```
        wsResult : Try<Number> = getNumberOfLikes()
        .
        .
        .
        
        if let number = wsResult.toOptional {
            showNumberOfLikes(number)
        } else {
        //Failure
        }
         ```
    */
    
    override public func toOptional() -> T? {
        return  Optional.some(self.value)
    }
    
    /**
     encoder used to serialize a success
     */
    
    override public func encodeWithCoder(aCoder: NSCoder) {
        aCoder.encode(self.value as! NSObject, forKey:"value")
    }
    
    /**
     coder used to decode a success
     */
    
    override public init?(coder aDecoder: NSCoder) {
        self.value = aDecoder.decodeObject(forKey: "value") as! T
        super.init()
    }
    
}

/**
Failure<T> is a way to express that a given computation failed.
*/

public class Failure<T> : Try<T> {
    
    /**
    Failure reason
    */
    
    public let tryError : Error
    
    /**
    Public constructor
     
     - parameter error : failure reason
    */
    
    public init(error : Error) {
        self.tryError = error
        super.init()
    }
    
    /**
    flag to determine if the computation was successful or not
    */

    override public func isFailure() -> Bool {return true}
    
    /**
    flag to determine if the computation was successful or not
    */
    
    override public func isSuccess() -> Bool { return false}
    
    /**
     - Throws: failure reason
    */
    
    override public func get() -> T {
        NSException.raise(NSExceptionName(rawValue: self.tryError.localizedDescription), format: "", arguments: getVaList([""]))
        return NSObject() as! T
    }
    
    
    /**
    encoder used to serialize a failure
    */
    
    override public func encodeWithCoder(aCoder: NSCoder) {
        aCoder.encode(self.tryError, forKey:"exception")
    }
    
    /**
     coder used to decode a failure
     */
    
    override public init?(coder aDecoder: NSCoder) {
        self.tryError = aDecoder.decodeObject(forKey: "exception") as! Error
        super.init()
    }
    
    /**
    Functional way to unwrap the Try<T>
    */
    
    override public func map<U>(f : (T) -> (U)) -> Failure<U> {
        return self as! Failure<U>
    }

}

