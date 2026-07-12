//
//  AppDelegate.swift
//  RemoteCam
//
//  Created by Dario Lencina on 10/31/15.
//  Copyright © 2015 dario. All rights reserved.
//

import UIKit
import Photos

/// Keeps the display awake while the app runs — a camera/monitor session dies
/// if the screen sleeps. iOS: the idle timer. Catalyst: a ProcessInfo
/// activity (the idle timer is a no-op on the Mac).
enum SleepPreventer {
    #if targetEnvironment(macCatalyst)
    private static var activity: NSObjectProtocol?
    #endif

    static func preventDisplaySleep() {
        #if targetEnvironment(macCatalyst)
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .userInitiated],
            reason: "Remote Shutter keeps the display awake during camera sessions")
        #else
        UIApplication.shared.isIdleTimerDisabled = true
        #endif
    }
}

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Task { await StoreManager.shared.loadProducts() }

        SleepPreventer.preventDisplaySleep()
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
