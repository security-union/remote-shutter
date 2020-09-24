//
//  AppDelegate.swift
//  RemoteCam
//
//  Created by Dario Lencina on 10/31/15.
//  Copyright © 2015 dario. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    private func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        InAppPurchasesManager.shared().reloadProducts { (i, e) in
        }
        self.setCustomNavBarTheme()
        return true
    }

    func setCustomNavBarTheme() {
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black
        shadow.shadowOffset = CGSize.init(width: 0.0, height: 1.0)

        let app = UINavigationBar.appearance()

        app.setBackgroundImage(UIImage(named: "blueBar"), for: .default)
        let atts = [
            convertFromNSAttributedStringKey(NSAttributedString.Key.foregroundColor): UIColor.white,
            convertFromNSAttributedStringKey(NSAttributedString.Key.shadow): shadow
        ]

        app.titleTextAttributes = convertToOptionalNSAttributedStringKeyDictionary(atts)

        let buttonApp = UIBarButtonItem.appearance()
        buttonApp.setTitleTextAttributes(convertToOptionalNSAttributedStringKeyDictionary(atts), for: .normal)
        buttonApp.setBackgroundImage(UIImage(named: "navigationBarButton"), for: .normal, barMetrics: .default)


        let backButtonPressed = UIImage(named: "navigationBarBack")
        let _backButtonPressed = backButtonPressed!.resizableImage(withCapInsets: UIEdgeInsets.init(top: 0, left: 14, bottom: 0, right: 4))

        buttonApp.setBackButtonBackgroundImage(_backButtonPressed, for: .normal, barMetrics: .default)

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
fileprivate func convertFromNSAttributedStringKey(_ input: NSAttributedString.Key) -> String {
    input.rawValue
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertToOptionalNSAttributedStringKeyDictionary(_ input: [String: Any]?) -> [NSAttributedString.Key: Any]? {
    guard let input = input else {
        return nil
    }
    return Dictionary(uniqueKeysWithValues: input.map { key, value in
        (NSAttributedString.Key(rawValue: key), value)
    })
}
