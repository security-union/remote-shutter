//
//  AppDelegate.swift
//  RemoteCam
//
//  Created by Dario Lencina on 10/31/15.
//  Copyright © 2015 dario. All rights reserved.
//

import UIKit
import Photos

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Task { await StoreManager.shared.loadProducts() }

        UIApplication.shared.isIdleTimerDisabled = true
        WatchSessionManager.shared.activate()

        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}
