//
//  Messages.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import Foundation

/**
 Base class for every message in the app — the `UICmd`/`RemoteCmd` vocabulary
 the wire protocol and the session state machine share. Messages are immutable
 value carriers; the FlatBuffers codec keys on their concrete types.

 The `sender` field is an opaque reference for the handful of messages that
 carry a reply target; new code should prefer explicit seams over
 sender-replies.
 */
public class Message: NSObject, @unchecked Sendable {
    public let sender: AnyObject?

    public init(sender: AnyObject? = nil) {
        self.sender = sender
        super.init()
    }
}

infix operator !: AssignmentPrecedence

/// Fire-and-forget send to the session coordinator — the successor of
/// Theater's `actorRef ! msg`, preserving call-site shape app-wide.
/// Enqueues into the coordinator's FIFO inbox and returns immediately.
public func ! (coordinator: SessionCoordinator, msg: Message) {
    coordinator.tell(msg)
}
