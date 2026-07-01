//
//  AppActivityMonitor.swift
//  RemoteShutter
//
//  Single source of truth for whether the iPhone can drive the camera right now.
//

import UIKit

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
/// The monitor owns its lifecycle observation so the flag can't drift from a
/// second observer, and so the notification→flag→callback path is unit-testable
/// with an injected `NotificationCenter`. `isBackgrounded` is lock-guarded because
/// it's written on the main queue (notifications) and read from the actor queue.
final class AppActivityMonitor {

    static let shared = AppActivityMonitor()

    private let lock = NSLock()
    private var _isBackgrounded = false
    private var observers: [NSObjectProtocol] = []
    private var notificationCenter: NotificationCenter?

    /// Invoked synchronously after every transition, on the thread that delivered the
    /// notification (the main queue for lifecycle events). `WatchSessionManager` uses it
    /// to re-push fresh state to the Watch. Because it fires *after* the flag is already
    /// updated, the re-push always observes the new value — no ordering race. Set before
    /// `startObserving()`.
    var onChange: (() -> Void)?

    /// True while the app is backgrounded / the device is locked.
    var isBackgrounded: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isBackgrounded
    }

    /// Registers lifecycle observers that keep `isBackgrounded` current. Idempotent;
    /// expected to be called once, on the main thread. Observers run synchronously
    /// (`queue: nil`) on the posting thread — lifecycle notifications are always posted
    /// on main — so the flag is updated inline before `onChange` triggers the re-push.
    func startObserving(notificationCenter: NotificationCenter = .default) {
        guard observers.isEmpty else { return }
        self.notificationCenter = notificationCenter
        // Locking the device delivers didEnterBackground just like swiping home, so both
        // are covered. Deliberately NOT willResignActive — that also fires for transient
        // interruptions (Control Center, banners, the incoming-call sheet) while the
        // camera is still usable, and would falsely blank the Watch.
        observers.append(notificationCenter.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.setBackgrounded(true) })
        observers.append(notificationCenter.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.setBackgrounded(false) })
    }

    /// Applies a transition and notifies `onChange`. Also the seam tests use to drive
    /// transitions without posting a real notification.
    func setBackgrounded(_ value: Bool) {
        lock.lock(); _isBackgrounded = value; lock.unlock()
        onChange?()
    }

    deinit {
        observers.forEach { notificationCenter?.removeObserver($0) }
    }
}
