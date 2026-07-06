//
//  UIViewController+SwiftUIHosting.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union. All rights reserved.
//

import UIKit
import SwiftUI

extension UIViewController {

    /// Embeds a SwiftUI view as a child hosting controller pinned to this
    /// controller's view bounds — the standard shell pattern for screens
    /// whose UI is already SwiftUI.
    @discardableResult
    func embedSwiftUIView<Content: View>(_ content: Content) -> UIHostingController<Content> {
        let hostingController = UIHostingController(rootView: content)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        return hostingController
    }

    /// Presents the shared help sheet used by every screen's "?" button.
    func presentHelpSheet() {
        let helpView = RemoteShutterHelpView(onDismiss: { [weak self] in
            self?.dismiss(animated: true)
        })
        let hostingController = UIHostingController(rootView: helpView)
        hostingController.modalPresentationStyle = .pageSheet
        if let sheet = hostingController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        present(hostingController, animated: true)
    }
}
