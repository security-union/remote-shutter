//
//  Locked.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import Foundation

/// Lock-guarded box for the few non-word values that cross queue domains (a
/// string, a continuation, a dictionary). A word — Int, Bool, an enum, a bit
/// pattern — is a `ManagedAtomic` instead; everything else is confined to one
/// queue. (`NSLock` because the iOS 15 floor rules out
/// `OSAllocatedUnfairLock`/`Mutex`.)
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
