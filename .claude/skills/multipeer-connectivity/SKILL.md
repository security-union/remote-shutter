---
name: multipeer-connectivity
description: Expert in MultipeerConnectivity and the RemoteCmd message protocol. Use when working with peer-to-peer communication, NSCoding serialization, adding new remote commands, or debugging connection issues.
allowed-tools: Read, Grep, Glob, Edit, Write
---

# MultipeerConnectivity & Remote Commands Expert

## Context
Remote Shutter uses Apple's MultipeerConnectivity framework (service type: `"RemoteCam"`) for peer-to-peer communication between camera and monitor devices.

## Message Protocol

### RemoteCmd (RemoteCmds.swift)
- Messages serialized via `NSCoding` and sent over MultipeerConnectivity
- Use `@objc` name annotations for stable serialization
- Example: `@objc(_TtCC10ActorsDemo9RemoteCmd7TakePic)`

### UICmd (UICmds.swift)
- Local messages between actors and view controllers within a single device
- Not serialized over the network

## Serialization Pattern
Messages use `NSKeyedArchiver`/`NSKeyedUnarchiver` and are sent via `MCSession.send()`.

### Adding a New Remote Command
1. Create a new class nested under `RemoteCmd`
2. Add `@objc` class name annotation for backward compatibility
3. Implement `NSCoding`:
   - `encode(with coder: NSCoder)` — Serialize properties
   - `init?(coder: NSCoder)` — Deserialize properties
4. Handle the command in the appropriate state handler

## Large Data Transfers
- Video files use `MCSession.sendResource()` for large transfers
- Progress tracking is built into the resource transfer API

## Rules
1. Always add `@objc` name annotation to new RemoteCmd subclasses
2. Always implement both `encode` and `init?(coder:)` for NSCoding
3. Use the established `@objc(_TtCC10ActorsDemo9RemoteCmd_ClassName)` naming pattern
4. Handle new commands in both camera and monitor state handlers
5. Test serialization round-trips for new commands
