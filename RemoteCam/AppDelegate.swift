//
//  AppDelegate.swift
//  RemoteCam
//
//  Created by Dario Lencina on 10/31/15.
//  Copyright © 2015 dario. All rights reserved.
//

import UIKit
import GoogleMobileAds
import Photos

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        InAppPurchasesManager.shared().reloadProducts { (_, _) in

        }
        if !InAppPurchasesManager.shared().didUserBuyRemoveiAdsFeature() &&
            !InAppPurchasesManager.shared().didUserBuyRemoveiAdsFeatureAndEnableVideo() {
            GADMobileAds.sharedInstance().start(completionHandler: nil)
        }

        UIApplication.shared.isIdleTimerDisabled = true
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
    }

    func applicationWillTerminate(_ application: UIApplication) {
    }

}

// Helper function inserted by Swift 4.2 migrator.
private func convertFromNSAttributedStringKey(_ input: NSAttributedString.Key) -> String {
    input.rawValue
}

// Helper function inserted by Swift 4.2 migrator.
private func convertToOptionalNSAttributedStringKeyDictionary(_ input: [String: Any]?) -> [NSAttributedString.Key: Any]? {
    guard let input = input else {
        return nil
    }
    return Dictionary(uniqueKeysWithValues: input.map { key, value in
        (NSAttributedString.Key(rawValue: key), value)
    })
}
