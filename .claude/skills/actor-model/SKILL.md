---
name: actor-model
description: Expert in the Theater actor framework used in Remote Shutter. Use when working with actors, message passing, the `!` operator, actor registration, `ViewCtrlActor`, or any code involving `RemoteCamSystem.shared`.
allowed-tools: Read, Grep, Glob, Edit, Write
---

# Theater Actor Model Expert

## Context
Remote Shutter uses the **Theater** pod (~1.1) — an actor-model framework where all communication happens via asynchronous messages.

## Key Patterns

### Message Sending
- The `!` operator sends a message to an actor: `actorRef ! MyMessage()`
- Never call actor methods directly — always send messages

### Actor References
- Actors are registered under `RemoteCamSystem.shared`
- Retrieve references via: `RemoteCamSystem.shared.selectActor(actorPath: "RemoteCam/user/<name>")`
- Key actors: `RemoteCam Session`, `MonitorActor`, `FrameSender`

### ViewCtrlActor
- `RemoteCamSession` subclasses `ViewCtrlActor<DeviceScannerViewController>`
- This binds an actor to a view controller lifecycle
- The `lobby` property references the associated VC

### Main Thread Dispatch
- The `^{ }` prefix operator dispatches closures to the main thread
- Used extensively for UI updates from actor message handlers
- State transitions happen inside actor message handlers, never on the main thread

### Actor Mailbox
- Each actor has a serial mailbox that processes messages sequentially
- This ensures thread safety without explicit locks

## Rules
1. Never perform UI updates directly in actor handlers — use `^{ }` operator
2. Never access actor state from outside the actor's message handler
3. Always use the `!` operator for inter-actor communication
4. When creating new actors, register them under `RemoteCamSystem.shared`
