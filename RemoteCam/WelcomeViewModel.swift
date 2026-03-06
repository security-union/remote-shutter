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

    private var products: [SKProduct] = []
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
        let productIds = [disableAdsPID, enableVideoPID, enableTorchPID, enableVideoOnlyPID]
        PKIAPHandler.shared.setProductIds(ids: productIds)
        PKIAPHandler.shared.fetchAvailableProducts { [weak self] products in
            DispatchQueue.main.async {
                self?.products = products
                self?.updatePrices()
            }
        }
    }

    // MARK: - Purchasing

    func purchase(_ item: UpgradeItem) {
        guard !item.isPurchased else { return }
        guard let product = products.first(where: { $0.productIdentifier == item.id }) else { return }

        isPurchasing = true
        PKIAPHandler.shared.purchase(product: product) { [weak self] alert, _, transaction in
            DispatchQueue.main.async {
                self?.isPurchasing = false
                if transaction != nil {
                    self?.refreshPurchaseStates()
                } else {
                    self?.alertTitle = NSLocalizedString("Purchase", comment: "")
                    self?.alertMessage = alert.message
                    self?.showAlert = true
                }
            }
        }
    }

    func restorePurchases() {
        isPurchasing = true
        PKIAPHandler.shared.restorePurchase { [weak self] alert, _, _ in
            DispatchQueue.main.async {
                self?.isPurchasing = false
                self?.refreshPurchaseStates()
                if alert == .restored {
                    self?.alertTitle = NSLocalizedString("Restored", comment: "")
                    self?.alertMessage = NSLocalizedString("Your purchases have been restored. If you don't see them, check that you're signed in with the correct Apple ID.", comment: "")
                    self?.showAlert = true
                }
            }
        }
    }

    // MARK: - Review

    var canShowReview: Bool {
        let manager = InAppPurchasesManager.shared()!
        guard manager.hasAdRemovalFeature() || manager.hasTorchFeature()
                || manager.hasVideoRecordingFeature() || manager.hasProMode() else {
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
        let manager = InAppPurchasesManager.shared()!
        upgrades = [
            UpgradeItem(id: enableVideoPID, title: "Pro: All Features", price: "",
                        isPurchased: manager.hasProMode(), icon: "star.fill", tint: "purple"),
            UpgradeItem(id: disableAdsPID, title: "Remove Ads", price: "",
                        isPurchased: manager.hasAdRemovalFeature(), icon: "eye.slash.fill", tint: "blue"),
            UpgradeItem(id: enableTorchPID, title: "Enable Torch", price: "",
                        isPurchased: manager.hasTorchFeature(), icon: "flashlight.on.fill", tint: "orange"),
            UpgradeItem(id: enableVideoOnlyPID, title: "Enable Video", price: "",
                        isPurchased: manager.hasVideoRecordingFeature(), icon: "video.fill", tint: "red"),
        ]
        updateFeatureFlags()
    }

    private func updatePrices() {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency

        for product in products {
            formatter.locale = product.priceLocale
            let price = formatter.string(from: product.price) ?? ""

            if let idx = upgrades.firstIndex(where: { $0.id == product.productIdentifier }) {
                upgrades[idx].title = product.localizedTitle
                upgrades[idx].price = price
            }
        }
    }

    private func refreshPurchaseStates() {
        let manager = InAppPurchasesManager.shared()!
        for i in upgrades.indices {
            switch upgrades[i].id {
            case enableVideoPID:
                upgrades[i].isPurchased = manager.hasProMode()
            case disableAdsPID:
                upgrades[i].isPurchased = manager.hasAdRemovalFeature()
            case enableTorchPID:
                upgrades[i].isPurchased = manager.hasTorchFeature()
            case enableVideoOnlyPID:
                upgrades[i].isPurchased = manager.hasVideoRecordingFeature()
            default:
                break
            }
        }
        updateFeatureFlags()
    }

    private func updateFeatureFlags() {
        let manager = InAppPurchasesManager.shared()!
        hasAllFeatures = manager.hasProMode()
        hasAnyPurchase = manager.hasAdRemovalFeature() || manager.hasTorchFeature()
            || manager.hasVideoRecordingFeature() || manager.hasProMode()
    }

    private func observePurchaseNotifications() {
        let names = [
            Constants.removeAds(), Constants.proModeAquired(),
            Constants.enableTorch(), Constants.enableVideoOnly()
        ]
        for name in names {
            let observer = NotificationCenter.default.addObserver(
                forName: NSNotification.Name(rawValue: name),
                object: nil, queue: .main
            ) { [weak self] _ in
                self?.refreshPurchaseStates()
            }
            notificationObservers.append(observer)
        }
    }
}
