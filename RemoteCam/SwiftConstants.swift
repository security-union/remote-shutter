//
//  SwiftConstants.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 10/12/20.
//  Copyright © 2020 Security Union. All rights reserved.
//

import Foundation
import StoreKit
import UIKit

public let tempFile = "remoteshutter_video.mov"

let AppStoreURL = URL(string: "https://apps.apple.com/us/app/remote-shutter/id633274861")!
public let disableAdsPID = "05"
public let enableVideoPID = "06"
public let enableTorchPID = "07"
public let enableVideoOnlyPID = "08"
public let reviewCounterKey = "reviewCounter"
public let lastVersionPromptedForReviewKey = "lastVersionPromptedForReview"
public let mediaCaptureCounterKey = "mediaCaptureCounter"
public let mediaCapturedBeforeRequestingReview = 10

// MARK: - Shared Review Prompt Utility
func privateShowReviewPromptIfAppropriate() {
    let reviewCount = UserDefaults.standard.integer(forKey: reviewCounterKey)
    let infoDictionaryKey = kCFBundleVersionKey as String
    guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: infoDictionaryKey) as? String
        else { return }
    
    let lastVersionPromptedForReview = UserDefaults.standard.string(forKey: lastVersionPromptedForReviewKey)
    
    if reviewCount <= 4 && currentVersion != lastVersionPromptedForReview {
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           let topViewController = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            var presentedVC = topViewController
            while let presented = presentedVC.presentedViewController {
                presentedVC = presented
            }

            if !(presentedVC is WelcomeViewController) {
                SKStoreReviewController.requestReview(in: windowScene)
                UserDefaults.standard.set(currentVersion, forKey: lastVersionPromptedForReviewKey)
                var count = UserDefaults.standard.integer(forKey: reviewCounterKey)
                count += 1
                UserDefaults.standard.set(count, forKey: reviewCounterKey)
            }
        }
    }
}

public func showReviewPromptIfAppropriate() {
    var count = UserDefaults.standard.integer(forKey: mediaCaptureCounterKey)
    count += 1
    UserDefaults.standard.set(count, forKey: mediaCaptureCounterKey)
    
    // Show review prompt after 10 captures
    if count >= mediaCapturedBeforeRequestingReview {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            privateShowReviewPromptIfAppropriate()
        }
    }
}
