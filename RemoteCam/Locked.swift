//
//  Locked.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import Foundation

/// Minimal lock-guarded value box for the few values that legitimately cross
/// the capture stack's queue domains (orientation, recording flag, fps, camera
/// position). Everything else is confined to a single queue — reach for this
/// only when a per-frame or cross-domain read genuinely can't hop queues.
/// (`NSLock` because the iOS 15 floor rules out `OSAllocatedUnfairLock`/`Mutex`.)
final class Locked<Value>: @unchecked Sendable {
    private var storage: Value
    private let lock = NSLock()

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storage = newValue
        }
    }

    /// Read-modify-write under one lock acquisition (e.g. counters).
    func mutate(_ transform: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        transform(&storage)
    }
}
