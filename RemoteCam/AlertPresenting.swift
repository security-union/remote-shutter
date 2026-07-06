//
//  AlertPresenting.swift
//  RemoteShutter
//
//  Created by Modernization refactor.
//

import Foundation
import UIKit

/// Handle returned by `AlertPresenting.showAlert` for later update/dismiss.
protocol AlertHandle: AnyObject {
    var currentTitle: String? { get }
}

/// Abstracts UIAlertController presentation so state-machine logic is testable.
/// All methods must be called from the main thread (dispatched via `^{}`).
protocol AlertPresenting: AnyObject {
    /// Show a progress alert. Returns handle for update/dismiss.
    func showAlert(title: String) -> AlertHandle
    /// Update title of existing alert.
    func updateAlert(_ handle: AlertHandle, title: String)
    /// Dismiss alert.
    func dismissAlert(_ handle: AlertHandle)
    /// Show standalone error alert with OK button.
    func showError(title: String)
}
