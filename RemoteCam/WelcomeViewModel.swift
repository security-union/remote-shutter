import Foundation
import StoreKit
import Combine

final class WelcomeViewModel: ObservableObject {

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

    private var notificationObservers: [NSObjectProtocol] = []

    // MARK: - Init

    init() {
        buildUpgradeItems()
        observePurchaseNotifications()
        loadProducts()
    }

    deinit {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
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
        guard let product = StoreManager.shared.products.first(where: { $0.id == item.id }) else { return }

        isPurchasing = true
        Task { @MainActor in
            do {
                let transaction = try await StoreManager.shared.purchase(product)
                isPurchasing = false
                if transaction != nil {
                    refreshPurchaseStates()
                }
            } catch {
                isPurchasing = false
                alertTitle = NSLocalizedString("Purchase", comment: "")
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
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
        let store = StoreManager.shared
        guard store.hasAdRemovalFeature() || store.hasTorchFeature()
                || store.hasVideoRecordingFeature() || store.hasProMode() else {
            return false
        }
        let count = UserDefaults.standard.integer(forKey: reviewCounterKey)
        guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String else {
            return false
        }
        let lastVersion = UserDefaults.standard.string(forKey: lastVersionPromptedForReviewKey)
        return count <= 4 && currentVersion != lastVersion
    }

    // MARK: - Private Helpers

    private func buildUpgradeItems() {
        let store = StoreManager.shared
        upgrades = [
            UpgradeItem(id: enableVideoPID, title: "Pro: All Features", price: "",
                        isPurchased: store.hasProMode(), icon: "star.fill", tint: "purple"),
            UpgradeItem(id: disableAdsPID, title: "Remove Ads", price: "",
                        isPurchased: store.hasAdRemovalFeature(), icon: "eye.slash.fill", tint: "blue"),
            UpgradeItem(id: enableTorchPID, title: "Enable Torch", price: "",
                        isPurchased: store.hasTorchFeature(), icon: "flashlight.on.fill", tint: "orange"),
            UpgradeItem(id: enableVideoOnlyPID, title: "Enable Video", price: "",
                        isPurchased: store.hasVideoRecordingFeature(), icon: "video.fill", tint: "red"),
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

    private func refreshPurchaseStates() {
        let store = StoreManager.shared
        for i in upgrades.indices {
            switch upgrades[i].id {
            case enableVideoPID:
                upgrades[i].isPurchased = store.hasProMode()
            case disableAdsPID:
                upgrades[i].isPurchased = store.hasAdRemovalFeature()
            case enableTorchPID:
                upgrades[i].isPurchased = store.hasTorchFeature()
            case enableVideoOnlyPID:
                upgrades[i].isPurchased = store.hasVideoRecordingFeature()
            default:
                break
            }
        }
        updateFeatureFlags()
    }

    private func updateFeatureFlags() {
        let store = StoreManager.shared
        hasAllFeatures = store.hasProMode()
        hasAnyPurchase = store.hasAdRemovalFeature() || store.hasTorchFeature()
            || store.hasVideoRecordingFeature() || store.hasProMode()
    }

    private func observePurchaseNotifications() {
        let names: [Notification.Name] = [
            .removeAds, .proModeAcquired, .enableTorch, .enableVideoOnly
        ]
        for name in names {
            let observer = NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                self?.refreshPurchaseStates()
            }
            notificationObservers.append(observer)
        }
    }
}
