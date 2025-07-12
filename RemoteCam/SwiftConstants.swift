//
//  SwiftConstants.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 10/12/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import StoreKit

public let tempFile = "tempfile.mov"
public let disableAdsPID = "05"
public let enableVideoPID = "06"
public let enableTorchPID = "07"
public let enableVideoOnlyPID = "08"
public let reviewCounterKey = "reviewCounter"
public let lastVersionPromptedForReviewKey = "lastVersionPromptedForReview"
public let mediaCaptureCounterKey = "mediaCaptureCounter"

// MARK: - Shared Review Prompt Utility
public func showReviewPromptIfAppropriate() {
    let reviewCount = UserDefaults.standard.integer(forKey: reviewCounterKey)
    let infoDictionaryKey = kCFBundleVersionKey as String
    guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: infoDictionaryKey) as? String
        else { return }
    
    let lastVersionPromptedForReview = UserDefaults.standard.string(forKey: lastVersionPromptedForReviewKey)
    
    if reviewCount <= 4 && currentVersion != lastVersionPromptedForReview {
        if let topViewController = UIApplication.shared.keyWindow?.rootViewController {
            var presentedVC = topViewController
            while let presented = presentedVC.presentedViewController {
                presentedVC = presented
            }
            
            if !(presentedVC is WelcomeViewController) {
                SKStoreReviewController.requestReview()
                UserDefaults.standard.set(currentVersion, forKey: lastVersionPromptedForReviewKey)
                var count = UserDefaults.standard.integer(forKey: reviewCounterKey)
                count += 1
                UserDefaults.standard.set(count, forKey: reviewCounterKey)
            }
        }
    }
}
