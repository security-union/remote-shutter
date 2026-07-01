//
//  AppActivityMonitor.swift
//  RemoteShutter
//
//  Single source of truth for whether the iPhone can drive the camera right now.
//

import Foundation

/// Whether the iPhone app is backgrounded or the device is locked, and therefore
/// unable to run the capture session for Watch Remote mode.
///
/// Readiness is decided in exactly one place — this flag, read by
/// `RemoteCamSession.watchStateSnapshot`. Previously every push path asserted
/// `isReady = true` and the truth was patched back in downstream, so a stale
/// "ready" snapshot could race ahead of the real not-ready push and hide the
/// "app closed" screen on the Watch. Concentrating the fact here removes that
/// split-brain.
///
/// Written on the main queue by `WatchSessionManager`'s lifecycle observers and
/// read from the actor queue, so the accessor is lock-guarded.
final class AppActivityMonitor {

    static let shared = AppActivityMonitor()

    private let lock = NSLock()
    private var _isBackgrounded = false

    /// True while the app is backgrounded / the device is locked.
    var isBackgrounded: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _isBackgrounded
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _isBackgrounded = newValue
        }
    }
}
