
<p align="center" >
  <img src="theaterlogo.jpg" title="Theter logo" float=left>
</p>

# Theater : iOS Actor Model Framework
[![Build Status](https://travis-ci.org/darioalessandro/Theater.svg)](https://travis-ci.org/darioalessandro/Theater)
[![Pod Version](http://img.shields.io/cocoapods/v/Theater.svg?style=flat)](http://cocoadocs.org/docsets/Theater/)

Writing async, resilient and responsive applications is too hard. 

In the case of iOS, is because we've been using the wrong abstraction level: NSOperationQueues, dispatch_semaphore_create, dispatch_semaphore_wait and other low level GCD functions and structures.

Using the Actor Model, we raise the abstraction level and provide a better platform to build correct concurrent and scalable applications.

Theater is Open Source and available under the Apache 2 License.

Theater is inspired by Akka.

Twitter = [@TheaterFwk](https://twitter.com/TheaterFwk)

### How to get started

- install via [CocoaPods](http://cocoapods.org)

```ruby
pod 'Theater'
```

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

Putting in all together:

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

.
.
.
(inside the app delegate)

func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        
        let system : ActorSystem = AppActorSystem.shared
        
        let dude1 = system.actorOf(Dude.self, name: "dude1")
        let dude2 = system.actorOf(Dude.self, name: "dude2")
        
        dude2 ! Hi(sender : dude1)
```

The output will be:
```swift
Tell = Optional("dude1") <Actors.Hi: 0x7bf951a0> dude2 
Tell = Optional("dude2") <Actors.Hello: 0x7be4bc00> dude1 
got Hello
```
