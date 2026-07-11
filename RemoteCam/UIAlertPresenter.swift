//
//  UIAlertPresenter.swift
//  RemoteShutter
//
//  Created by Modernization refactor.
//

import UIKit

/// Shows a modal error alert from any thread (dispatches to main).
public func showError(_ error: String) {
    OperationQueue.main.addOperation {
        let alert = UIAlertController(
            title: NSLocalizedString("Error", comment: ""),
            message: error
        )
        alert.simpleOkAction()
        alert.show(true)
    }
}

/// Wraps a live `UIAlertController` as an `AlertHandle`.
class UIAlertHandle: AlertHandle {
    let alertController: UIAlertController
    var currentTitle: String? { alertController.title }
    init(_ alert: UIAlertController) { self.alertController = alert }
}

/// Production implementation that uses the existing `UIAlertController.show()` extension.
class UIAlertPresenter: AlertPresenting {
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
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.simpleOkAction()
        alert.show(true)
    }
}
