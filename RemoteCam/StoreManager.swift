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
}

// MARK: - UserDefaults Keys

private enum PurchaseKey {
    static let removeAds = "didBuyRemoveiAdsFeature"
    static let proMode = "didBuyProMode"
    static let enableTorch = "didBuyEnableTorchFeature"
    static let enableVideoOnly = "didBuyEnableVideoOnlyFeature"
}

// MARK: - StoreManager

final class StoreManager: ObservableObject {

    static let shared = StoreManager()

    static let allProductIDs: Set<String> = [
        disableAdsPID, enableVideoPID, enableTorchPID, enableVideoOnlyPID
    ]

    // MARK: - Published State

    @Published private(set) var products: [Product] = []

    // MARK: - Feature Availability (synchronous, UserDefaults-backed)

    func hasAdRemovalFeature() -> Bool {
        hasProMode() || UserDefaults.standard.bool(forKey: PurchaseKey.removeAds)
    }

    func hasVideoRecordingFeature() -> Bool {
        hasProMode() || UserDefaults.standard.bool(forKey: PurchaseKey.enableVideoOnly)
    }

    func hasTorchFeature() -> Bool {
        hasProMode() || UserDefaults.standard.bool(forKey: PurchaseKey.enableTorch)
    }

    func hasProMode() -> Bool {
        UserDefaults.standard.bool(forKey: PurchaseKey.proMode)
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
            print("Failed to load products: \(error)")
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
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                grantEntitlement(for: transaction.productID)
            }
        }
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
    }

    enum StoreError: Error {
        case failedVerification
    }
}
