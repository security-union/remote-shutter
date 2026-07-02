//
//  SceneDelegate.swift
//  RemoteCam
//
//  Copyright © 2026 dario. All rights reserved.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UINavigationController(rootViewController: WelcomeViewController())
        window.makeKeyAndVisible()
        self.window = window
    }
}
