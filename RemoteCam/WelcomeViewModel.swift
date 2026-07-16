import Foundation
import StoreKit
import Combine

final class WelcomeViewModel: ObservableObject, PurchaseManaging {

    struct UpgradeItem: Identifiable {
        let id: String
        var title: String
        var price: String
        var isPurchased: Bool
        let icon: String
        let tint: String // color name
    }

    // MARK: - Published State

    @Published var upgrades: [UpgradeItem] = []
    @Published var hasAnyPurchase = false
    @Published var hasAllFeatures = false
    @Published var isPurchasing = false
    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""

    // MARK: - Private

    var notificationObservers: [NSObjectProtocol] = []

    // MARK: - Init

    init() {
        buildUpgradeItems()
        observePurchaseNotifications()
        loadProducts()
    }

    deinit {
        removeNotificationObservers()
    }

    // MARK: - Product Loading

    func loadProducts() {
        Task { @MainActor in
            await StoreManager.shared.loadProducts()
            updatePrices()
        }
    }

    // MARK: - Purchasing

    func purchase(_ item: UpgradeItem) {
        guard !item.isPurchased else { return }
        purchaseProduct(id: item.id)
    }

    func handlePurchaseError(_ error: Error) {
        alertTitle = NSLocalizedString("Purchase", comment: "")
        alertMessage = error.localizedDescription
        showAlert = true
    }

    func restorePurchases() {
        isPurchasing = true
        Task { @MainActor in
            await StoreManager.shared.restorePurchases()
            isPurchasing = false
            refreshPurchaseStates()
            alertTitle = NSLocalizedString("Restored", comment: "")
            alertMessage = NSLocalizedString("Your purchases have been restored. If you don't see them, check that you're signed in with the correct Apple ID.", comment: "")
            showAlert = true
        }
    }

    // MARK: - Review

    var canShowReview: Bool {
        hasEarnedReviewAsk()
    }

    // MARK: - Private Helpers

    private func buildUpgradeItems() {
        let store = StoreManager.shared
        upgrades = [
            // Featured card: the Pro subscription (best value, yearly).
            UpgradeItem(id: proYearlyPID, title: NSLocalizedString("Pro (Yearly)", comment: ""), price: "",
                        isPurchased: store.hasProSubscription(), icon: "crown.fill", tint: "purple"),
            UpgradeItem(id: proMonthlyPID, title: NSLocalizedString("Pro (Monthly)", comment: ""), price: "",
                        isPurchased: store.hasProSubscription(), icon: "crown", tint: "purple"),
            UpgradeItem(id: enableVideoPID, title: NSLocalizedString("Pro: All Features", comment: ""), price: "",
                        isPurchased: store.hasProMode(), icon: "star.fill", tint: "purple"),
            UpgradeItem(id: disableAdsPID, title: NSLocalizedString("Remove Ads", comment: ""), price: "",
                        isPurchased: store.hasAdRemovalFeature(), icon: "eye.slash.fill", tint: "blue"),
            UpgradeItem(id: enableTorchPID, title: NSLocalizedString("Enable Torch", comment: ""), price: "",
                        isPurchased: store.hasTorchFeature(), icon: "flashlight.on.fill", tint: "orange"),
            UpgradeItem(id: enableVideoOnlyPID, title: NSLocalizedString("Enable Video", comment: ""), price: "",
                        isPurchased: store.hasVideoRecordingFeature(), icon: "video.fill", tint: "red"),
            UpgradeItem(id: tapToFocusPID, title: NSLocalizedString("Tap to Focus", comment: ""), price: "",
                        isPurchased: store.hasTapToFocusFeature(), icon: "camera.metering.spot", tint: "green"),
        ]
        updateFeatureFlags()
    }

    private func updatePrices() {
        for product in StoreManager.shared.products {
            if let idx = upgrades.firstIndex(where: { $0.id == product.id }) {
                upgrades[idx].title = product.displayName
                upgrades[idx].price = product.displayPrice
            }
        }
    }

    func refreshPurchaseStates() {
        let store = StoreManager.shared
        for i in upgrades.indices {
            switch upgrades[i].id {
            case proMonthlyPID, proYearlyPID:
                upgrades[i].isPurchased = store.hasProSubscription()
            case enableVideoPID:
                upgrades[i].isPurchased = store.hasProMode()
            case disableAdsPID:
                upgrades[i].isPurchased = store.hasAdRemovalFeature()
            case enableTorchPID:
                upgrades[i].isPurchased = store.hasTorchFeature()
            case enableVideoOnlyPID:
                upgrades[i].isPurchased = store.hasVideoRecordingFeature()
            case tapToFocusPID:
                upgrades[i].isPurchased = store.hasTapToFocusFeature()
            default:
                break
            }
        }
        updateFeatureFlags()
    }

    private func updateFeatureFlags() {
        let store = StoreManager.shared
        hasAllFeatures = store.hasFullAccess()
        hasAnyPurchase = store.hasAdRemovalFeature() || store.hasTorchFeature()
            || store.hasVideoRecordingFeature() || store.hasFullAccess()
            || store.hasTapToFocusFeature()
    }

}
