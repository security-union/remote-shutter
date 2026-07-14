//
//  UIAlertPresenter.swift
//  RemoteShutter
//
//  Created by Modernization refactor.
//

import UIKit

/// Shows a modal error alert from any thread (dispatches to main).
/// Routes through the presenter's dedup gate — identical errors never stack.
public func showError(_ error: String) {
    OperationQueue.main.addOperation {
        UIAlertPresenter.presentErrorDeduped(
            title: NSLocalizedString("Error", comment: ""),
            message: error
        )
    }
}

/// Wraps a live `UIAlertController` as an `AlertHandle`.
/// `@unchecked Sendable`: main-thread-confined (see `AlertHandle`).
class UIAlertHandle: AlertHandle, @unchecked Sendable {
    let alertController: UIAlertController
    var currentTitle: String? { alertController.title }
    init(_ alert: UIAlertController) { self.alertController = alert }
}

/// Production implementation that uses the existing `UIAlertController.show()` extension.
/// `@unchecked Sendable`: main-thread-confined (see `AlertPresenting`).
class UIAlertPresenter: AlertPresenting, @unchecked Sendable {

    /// The one error alert on screen, if any. Every error in the app funnels
    /// through `presentErrorDeduped`, so an error identical to the visible one
    /// is dropped instead of stacked — a peer disconnect can fail dozens of
    /// queued sends in a burst, and the user needs to hear about it once.
    private static weak var visibleErrorAlert: UIAlertController?

    /// Main thread only. Returns whether the alert was actually presented
    /// (false = deduped against the identical alert already on screen).
    @discardableResult
    static func presentErrorDeduped(title: String, message: String? = nil) -> Bool {
        if let visible = visibleErrorAlert,
           visible.view.window != nil || visible.presentingViewController != nil,
           visible.title == title, visible.message == message {
            return false
        }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.simpleOkAction()
        alert.show(true)
        visibleErrorAlert = alert
        return true
    }

    func showAlert(title: String) -> AlertHandle {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.show(true)
        return UIAlertHandle(alert)
    }

    func updateAlert(_ handle: AlertHandle, title: String) {
        (handle as? UIAlertHandle)?.alertController.title = title
    }

    func dismissAlert(_ handle: AlertHandle) {
        (handle as? UIAlertHandle)?.alertController.dismiss(animated: true)
    }

    func showError(title: String) {
        Self.presentErrorDeduped(title: title)
    }
}
