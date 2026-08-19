//
//  StoreManager.swift
//  RemoteShutter
//
//  Unified StoreKit 2 manager replacing PurchasesRestorer,
//  InAppPurchasesManager, and PKIAPHandler.
//

import Foundation
import StoreKit

// MARK: - Notification Names (replacing Constants.h/.m)

extension Notification.Name {
    static let removeAds = Notification.Name("RemoveAds")
    static let proModeAcquired = Notification.Name("ProModeAquired")
    static let enableTorch = Notification.Name("EnableTorch")
    static let enableVideoOnly = Notification.Name("EnableVideoOnly")
    static let tapToFocusAcquired = Notification.Name("TapToFocusAcquired")
    static let proSubscriptionAcquired = Notification.Name("ProSubscriptionAcquired")
    static let fourCamerasAcquired = Notification.Name("FourCamerasAcquired")
}

// MARK: - UserDefaults Keys

private enum PurchaseKey {
    static let removeAds = "didBuyRemoveiAdsFeature"
    static let proMode = "didBuyProMode"
    static let enableTorch = "didBuyEnableTorchFeature"
    static let enableVideoOnly = "didBuyEnableVideoOnlyFeature"
    static let tapToFocus = "didBuyTapToFocusFeature"
    static let fourCameras = "didBuyFourCamerasFeature"
    // Unlike the one-time flags above, this is NOT append-only: refreshPurchaseState
    // recomputes it from Transaction.currentEntitlements so a lapsed subscription
    // is revoked. It is persisted only so the UI is correct at launch before the
    // first async refresh completes.
    static let proSubscription = "hasActiveProSubscription"
}

// MARK: - StoreManager

final class StoreManager: ObservableObject {

    static let shared = StoreManager()

    static let allProductIDs: Set<String> = [
        disableAdsPID, enableVideoPID, enableTorchPID, enableVideoOnlyPID,
        tapToFocusPID, fourCamerasPID, proMonthlyPID, proYearlyPID
    ]

    /// The auto-renewable subscription products (the "Pro" subscription group).
    static let subscriptionProductIDs: Set<String> = [proMonthlyPID, proYearlyPID]

    // MARK: - Published State

    @Published private(set) var products: [Product] = []

    // MARK: - Feature Availability (synchronous, UserDefaults-backed)

    func hasAdRemovalFeature() -> Bool {
        hasFullAccess() || UserDefaults.standard.bool(forKey: PurchaseKey.removeAds)
    }

    func hasVideoRecordingFeature() -> Bool {
        hasFullAccess() || UserDefaults.standard.bool(forKey: PurchaseKey.enableVideoOnly)
    }

    func hasTorchFeature() -> Bool {
        hasFullAccess() || UserDefaults.standard.bool(forKey: PurchaseKey.enableTorch)
    }

    /// Owns the one-time "Pro: All Features" bundle (product 06). This is the raw
    /// 06 flag only — use `hasFullAccess()` to also honor the subscription.
    func hasProMode() -> Bool {
        UserDefaults.standard.bool(forKey: PurchaseKey.proMode)
    }

    /// An active auto-renewable Pro subscription. Recomputed from
    /// `Transaction.currentEntitlements` on every refresh, so it clears when the
    /// subscription lapses.
    func hasProSubscription() -> Bool {
        UserDefaults.standard.bool(forKey: PurchaseKey.proSubscription)
    }

    /// Any bundle that unlocks every feature: the one-time Pro (06) or the Pro
    /// subscription. The single gate every feature check ORs against.
    func hasFullAccess() -> Bool {
        hasProMode() || hasProSubscription()
    }

    /// Tap-to-focus entitlement. Unlocked by full access (Pro/subscription) or
    /// its own IAP (09).
    func hasTapToFocusFeature() -> Bool {
        hasFullAccess() || UserDefaults.standard.bool(forKey: PurchaseKey.tapToFocus)
    }

    /// The multicam camera caps — the single source for every gate and every
    /// piece of copy that names a number, so they can never disagree. The
    /// paid cap is held at 4 until larger rigs are validated on hardware
    /// (N preview streams + N clip uploads per take).
    static let maxFreeCameras = 2
    static let maxPaidCameras = 4

    /// What the `four_cameras` product sells. Distinct from the cap: the
    /// paywall offers the pack only while the cap honors this promise.
    static let fourCamerasPackCameraCount = 4
    static var offersFourCamerasPack: Bool { maxPaidCameras >= fourCamerasPackCameraCount }

    /// Directing at the paid camera cap: unlocked by full access (Pro
    /// unlocks everything) or the à la carte `four_cameras` pack.
    func hasFourCamerasFeature() -> Bool {
        hasFullAccess() || UserDefaults.standard.bool(forKey: PurchaseKey.fourCameras)
    }

    /// How many cameras a multicam director may connect: a free 2-camera
    /// teaser, or the paid cap with Pro or the 4-camera pack. The director's
    /// entitlement is what counts (matching every other gate — checked locally
    /// on this device).
    func maxCameras() -> Int {
        hasFourCamerasFeature() ? Self.maxPaidCameras : Self.maxFreeCameras
    }

    // MARK: - Init

    private var updateListenerTask: Task<Void, Never>?

    private init() {
        updateListenerTask = listenForTransactions()
        Task { await refreshPurchaseState() }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Product Loading

    @MainActor
    func loadProducts() async {
        do {
            products = try await Product.products(for: Self.allProductIDs)
                .sorted { $0.price > $1.price }
        } catch {
            logWarning("Failed to load products: \(error)")
        }
    }

    // MARK: - Purchasing

    func purchase(_ product: Product) async throws -> Transaction? {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            grantEntitlement(for: transaction.productID)
            await transaction.finish()
            postNotifications()
            return transaction
        case .userCancelled, .pending:
            return nil
        @unknown default:
            return nil
        }
    }

    // MARK: - Restore

    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshPurchaseState()
    }

    // MARK: - Private

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if let transaction = try? result.payloadValue {
                    self?.grantEntitlement(for: transaction.productID)
                    await transaction.finish()
                    self?.postNotifications()
                }
            }
        }
    }

    private func refreshPurchaseState() async {
        // Subscription entitlement is derived fresh each pass so an expired
        // subscription is revoked; one-time flags stay append-only in grantEntitlement.
        var activeSubscription = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                grantEntitlement(for: transaction.productID)
                if Self.subscriptionProductIDs.contains(transaction.productID) {
                    activeSubscription = true
                }
            }
        }
        UserDefaults.standard.set(activeSubscription, forKey: PurchaseKey.proSubscription)
        postNotifications()
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let value):
            return value
        }
    }

    private func grantEntitlement(for productID: String) {
        let defaults = UserDefaults.standard
        switch productID {
        case disableAdsPID:
            defaults.set(true, forKey: PurchaseKey.removeAds)
        case enableVideoPID:
            defaults.set(true, forKey: PurchaseKey.proMode)
        case enableTorchPID:
            defaults.set(true, forKey: PurchaseKey.enableTorch)
        case enableVideoOnlyPID:
            defaults.set(true, forKey: PurchaseKey.enableVideoOnly)
        case tapToFocusPID:
            defaults.set(true, forKey: PurchaseKey.tapToFocus)
        case fourCamerasPID:
            defaults.set(true, forKey: PurchaseKey.fourCameras)
        case proMonthlyPID, proYearlyPID:
            // Live purchase/renewal is always active; refreshPurchaseState is the
            // authority that later clears this if the subscription lapses.
            defaults.set(true, forKey: PurchaseKey.proSubscription)
        default:
            break
        }
    }

    private func postNotifications() {
        let post = { (name: Notification.Name) in
            NotificationCenter.default.post(name: name, object: nil)
        }
        if hasAdRemovalFeature() { post(.removeAds) }
        if hasProMode() { post(.proModeAcquired) }
        if hasTorchFeature() { post(.enableTorch) }
        if hasVideoRecordingFeature() { post(.enableVideoOnly) }
        if hasProSubscription() { post(.proSubscriptionAcquired) }
        if hasTapToFocusFeature() { post(.tapToFocusAcquired) }
        if hasFourCamerasFeature() { post(.fourCamerasAcquired) }
    }

    enum StoreError: Error {
        case failedVerification
    }
}
