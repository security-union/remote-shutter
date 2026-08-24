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

/// The self-timer preset, one preference shared by the classic remote and the
/// multicam director — a single key and accessor so the two can never drift.
enum TimerPreference {
    static let key = "timerDefault"
    static var seconds: Int {
        get { UserDefaults.standard.integer(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

let AppStoreURL = URL(string: "https://apps.apple.com/us/app/remote-shutter/id633274861")!
// SKStoreReviewController is rate-limited by the system (~3/year) and can show
// nothing at all, so it is only fit for the unsolicited prompt. A deliberate tap
// goes here instead: the write-review deep link is never throttled.
let AppStoreReviewURL = URL(string: "https://apps.apple.com/us/app/remote-shutter/id633274861?action=write-review")!
let GearURL = URL(string: "https://remoteshutter.app/gear?src=app")!
public let disableAdsPID = "05"
public let enableVideoPID = "06"
public let enableTorchPID = "07"
public let enableVideoOnlyPID = "08"
public let tapToFocusPID = "09"
/// Pro controls (issue #206): manual shutter/ISO + Cinematic aperture from
/// the remote. One product covers both.
public let proControlsPID = "10"
/// One-time pack: multicam directing at the paid camera cap. The id is
/// cap-agnostic on purpose — the same purchase grows with `maxPaidCameras`
/// as larger rigs are validated; only the marketing copy names a number.
public let maxCamerasPID = "max_cameras"
// Auto-renewable "Pro" subscription (group "Pro"). Unlocks every feature for
// the subscription period — the recurring equivalent of the one-time 06 bundle.
public let proMonthlyPID = "pro_monthly"
public let proYearlyPID = "pro_yearly"
public let reviewCounterKey = "reviewCounter"
public let lastVersionPromptedForReviewKey = "lastVersionPromptedForReview"
public let mediaCaptureCounterKey = "mediaCaptureCounter"
public let mediaCapturedBeforeRequestingReview = 5

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

// MARK: - Rate on App Store

/// The single gate for every surface that offers the "Rate on App Store" heart,
/// so they can't drift apart. Someone earns the ask by having actually captured
/// something — purchasing isn't a proxy for it, and asking before the app has
/// worked for them samples the wrong people. Surfaces the user navigates to
/// deliberately (Settings) skip this: they already asked.
func hasEarnedReviewAsk(captureCount: Int) -> Bool {
    captureCount >= mediaCapturedBeforeRequestingReview
}

func hasEarnedReviewAsk() -> Bool {
    hasEarnedReviewAsk(captureCount: UserDefaults.standard.integer(forKey: mediaCaptureCounterKey))
}

func openAppStoreReview() {
    UIApplication.shared.open(AppStoreReviewURL)
}

public func showReviewPromptIfAppropriate() {
    var count = UserDefaults.standard.integer(forKey: mediaCaptureCounterKey)
    count += 1
    UserDefaults.standard.set(count, forKey: mediaCaptureCounterKey)
    
    if count >= mediaCapturedBeforeRequestingReview {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            privateShowReviewPromptIfAppropriate()
        }
    }
}

// MARK: - Recommended Gear Web Page

// Deliberately the system browser rather than SFSafariViewController. The gear
// page sends people on to Amazon, and since iOS 11 an SFSafariViewController
// keeps its own cookie store, isolated from Safari — so an affiliate cookie set
// inside one is stranded there the moment the shopper continues in the Amazon
// app, and the referral goes uncredited. Handing off to Safari also lets
// Amazon's universal links open its app directly, which is what Amazon asks
// Associates to do.
func openGearPage() {
    UIApplication.shared.open(GearURL)
}
