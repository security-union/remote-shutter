//
//  CaptureTally.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import Foundation
import StoreKit
import UIKit

public let reviewCounterKey = "reviewCounter"
public let lastVersionPromptedForReviewKey = "lastVersionPromptedForReview"
public let mediaCaptureCounterKey = "mediaCaptureCounter"
public let mediaCapturedBeforeRequestingReview = 5

// MARK: - Capture tally

/// Verified captures saved into this device's photo library — the one counter
/// behind every review surface. The director's collect points record on the
/// save's own success signal, never on intent, so the ask is only earned by
/// captures that actually landed. Each collected lane counts: a 3-camera rig
/// capture is 3 captures.
enum CaptureTally {
    /// Test seam; the app always runs on `.standard`.
    static var defaults: UserDefaults = .standard

    static var count: Int { defaults.integer(forKey: mediaCaptureCounterKey) }

    static func record() {
        defaults.set(count + 1, forKey: mediaCaptureCounterKey)
    }

    /// Record the capture and, once the ask is earned, request the system
    /// review sheet after a beat (2s, the classic monitor's cadence) so the
    /// sheet never lands on top of the shot that was just collected.
    static func recordAndMaybeRequestReview() {
        record()
        guard hasEarnedReviewAsk(captureCount: count) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            requestSystemReviewIfAppropriate()
        }
    }
}

// MARK: - The earn gate

/// The single gate for every surface that offers the "Rate on App Store" heart,
/// so they can't drift apart. Someone earns the ask by having actually captured
/// something — purchasing isn't a proxy for it, and asking before the app has
/// worked for them samples the wrong people. Surfaces the user navigates to
/// deliberately (Settings) skip this: they already asked.
func hasEarnedReviewAsk(captureCount: Int) -> Bool {
    captureCount >= mediaCapturedBeforeRequestingReview
}

func hasEarnedReviewAsk() -> Bool {
    hasEarnedReviewAsk(captureCount: CaptureTally.count)
}

// MARK: - The system review sheet

private func requestSystemReviewIfAppropriate() {
    let reviewCount = CaptureTally.defaults.integer(forKey: reviewCounterKey)
    let infoDictionaryKey = kCFBundleVersionKey as String
    guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: infoDictionaryKey) as? String
        else { return }

    let lastVersionPromptedForReview = CaptureTally.defaults.string(forKey: lastVersionPromptedForReviewKey)

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
                CaptureTally.defaults.set(currentVersion, forKey: lastVersionPromptedForReviewKey)
                var count = CaptureTally.defaults.integer(forKey: reviewCounterKey)
                count += 1
                CaptureTally.defaults.set(count, forKey: reviewCounterKey)
            }
        }
    }
}
