//
//  AlertPresenting.swift
//  RemoteShutter
//
//  Created by Modernization refactor.
//

import Foundation
import UIKit

/// Handle returned by `AlertPresenting.showAlert` for later update/dismiss.
/// `Sendable` because the session actor hands handles to the main queue;
/// conformers are main-thread-confined.
protocol AlertHandle: AnyObject, Sendable {
    var currentTitle: String? { get }
}

/// Abstracts UIAlertController presentation so state-machine logic is testable.
/// All methods must be called from the main thread. `Sendable` because the
/// session actor captures the presenter in main-queue hops; conformers are
/// main-thread-confined.
protocol AlertPresenting: AnyObject, Sendable {
    /// Show a progress alert. Returns handle for update/dismiss.
    func showAlert(title: String) -> AlertHandle
    /// Update title of existing alert.
    func updateAlert(_ handle: AlertHandle, title: String)
    /// Dismiss alert.
    func dismissAlert(_ handle: AlertHandle)
    /// Show standalone error alert with OK button.
    func showError(title: String)
    /// Show a persistent alert with a single cancel button (the
    /// peer-backgrounded reconnect dialog). Dismissed programmatically on
    /// reconnect, or by the user via `onCancel`.
    func showCancelableAlert(title: String, cancelTitle: String,
                             onCancel: @escaping @Sendable () -> Void) -> AlertHandle
}
