//
//  SceneDelegate.swift
//  RemoteCam
//
//  Copyright © 2026 dario. All rights reserved.
//

import UIKit

/// A navigation bar that lets taps on its empty (non-button) area fall through to
/// the content below. The monitor's live preview bleeds full-screen under this
/// transparent bar; without pass-through, the bar would swallow tap-to-focus
/// taps aimed at the top of the frame. Taps on the back/help bar-button items
/// still hit the buttons.
final class PassThroughNavigationBar: UINavigationBar {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        // Keep touches that land on an actual interactive control (the back /
        // help bar-button items render as UIControls); pass everything else —
        // the transparent background and empty area — through to the preview so
        // tap-to-focus can reach the top of the frame.
        var view: UIView? = hit
        while let current = view, current !== self {
            if current is UIControl { return hit }
            view = current.superview
        }
        return nil
    }
}

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        let navigationController = UINavigationController(
            navigationBarClass: PassThroughNavigationBar.self, toolbarClass: nil)
        navigationController.setViewControllers([RolePickerController()], animated: false)
        window.rootViewController = navigationController
        window.makeKeyAndVisible()
        self.window = window
    }
}
