<p align="center" >
  <img src="theaterlogo.jpg" title="Theter logo" float=left>
</p>

# Theater : iOS Actor Model Framework
[![Build Status](https://travis-ci.org/darioalessandro/Theater.svg)](https://travis-ci.org/darioalessandro/Theater)
[![Pod Version](http://img.shields.io/cocoapods/v/Theater.svg?style=flat)](http://cocoadocs.org/docsets/Theater/)

A powerful Swift framework for building concurrent, resilient, and responsive applications using the Actor Model.

Traditional iOS development often relies on low-level concurrency primitives like OperationQueues, dispatch semaphores, and GCD functions, which can lead to complex and error-prone code. Theater elevates the abstraction level by implementing the Actor Model, providing a more intuitive and robust platform for building scalable concurrent applications.

## Requirements
- iOS 14.0+ / macOS 14.0+
- Swift 5.0+
- Xcode 12.0+

## Installation

### CocoaPods
```ruby
pod 'Theater'
```

## Features
- Actor-based concurrency model
- Message-passing communication
- Built-in actor system
- Simple and intuitive API
- Inspired by Akka's design patterns

## Usage

Actors should subclass the Actor class:

```swift
public class Dude : Actor {
```

In order to "listen" for messages, actors have to override the receive method:
```swift
override public func receive(msg : Message) -> Void {

}
```

In order to unwrap the message, you can use switch 

```swift
override public func receive(msg : Message) -> Void {
  switch (msg) {
    case let m as Hi:
      m.sender! ! Hello(sender: self.this)
    case is Hello:
      print("got Hello")
    default:
      print("what?")
  }
}
```

All messages must subclass Message:
```swift
public class Hi : Message {}
 
public class Hello : Message {}
```

Actors live inside an actor system, theater provides a default system

```swift
let system : ActorSystem = AppActorSystem.shared
```

## Complete Example

```swift
import Theater
 
public class Hi : Message {}
 
public class Hello : Message {}
 
public class Dude : Actor {
    override public func receive(msg : Message) -> Void {
        switch (msg) {
            case let m as Hi:
                m.sender! ! Hello(sender: self.this)
            case is Hello:
                print("got Hello")
            default:
                print("what?")
        }
    }
}

// Inside the app delegate
func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
    let system : ActorSystem = AppActorSystem.shared
    
    let dude1 = system.actorOf(Dude.self, name: "dude1")
    let dude2 = system.actorOf(Dude.self, name: "dude2")
    
    dude2 ! Hi(sender : dude1)
}
```

The output will be:
```
Tell = Optional("dude1") <Actors.Hi: 0x7bf951a0> dude2 
Tell = Optional("dude2") <Actors.Hello: 0x7be4bc00> dude1 
got Hello
```

## License
Theater is available under the Apache 2 License. See the LICENSE file for more info.

## Contact
- Email: [dario@securityunion.dev](mailto:dario@securityunion.dev)
- GitHub: [darioalessandro/Theater](https://github.com/darioalessandro/Theater)

