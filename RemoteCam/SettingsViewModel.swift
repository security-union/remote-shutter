import Foundation
import StoreKit
import Combine

private let sendMediaToRemoteKey = "sendMediaToRemote"

final class SettingsViewModel: ObservableObject, PurchaseManaging {

    // MARK: - Purchase State

    struct PurchaseItem: Identifiable {
        let id: String // product identifier
        var title: String
        var price: String
        var isPurchased: Bool
    }

    @Published var proSubscriptionMonthly = PurchaseItem(id: proMonthlyPID, title: NSLocalizedString("Pro (Monthly)", comment: ""), price: "", isPurchased: false)
    @Published var proSubscriptionYearly = PurchaseItem(id: proYearlyPID, title: NSLocalizedString("Pro (Yearly)", comment: ""), price: "", isPurchased: false)
    @Published var proMode = PurchaseItem(id: enableVideoPID, title: NSLocalizedString("Pro: All Features", comment: ""), price: "", isPurchased: false)
    @Published var removeAds = PurchaseItem(id: disableAdsPID, title: NSLocalizedString("Remove Ads", comment: ""), price: "", isPurchased: false)
    @Published var enableTorch = PurchaseItem(id: enableTorchPID, title: NSLocalizedString("Enable Torch", comment: ""), price: "", isPurchased: false)
    @Published var enableVideo = PurchaseItem(id: enableVideoOnlyPID, title: NSLocalizedString("Enable Video", comment: ""), price: "", isPurchased: false)
    @Published var tapToFocus = PurchaseItem(id: tapToFocusPID, title: NSLocalizedString("Tap to Focus", comment: ""), price: "", isPurchased: false)

    @Published var isRestoringPurchases = false
    @Published var isPurchasing = false
    @Published var alertMessage: String?
    @Published var showAlert = false

    // MARK: - Settings

    @Published var sendMediaToRemote: Bool {
        didSet {
            UserDefaults.standard.set(sendMediaToRemote, forKey: sendMediaToRemoteKey)
        }
    }

    // MARK: - App Info

    let appVersion: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }()

    // MARK: - Private

    var notificationObservers: [NSObjectProtocol] = []

    // MARK: - Init

    init() {
        // Read current value; default to true if key doesn't exist
        if UserDefaults.standard.object(forKey: sendMediaToRemoteKey) != nil {
            self.sendMediaToRemote = UserDefaults.standard.bool(forKey: sendMediaToRemoteKey)
        } else {
            self.sendMediaToRemote = true
        }

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
            updateItems(with: StoreManager.shared.products)
        }
    }

    // MARK: - Purchasing

    func purchase(_ item: PurchaseItem) {
        guard !item.isPurchased else { return }
        purchaseProduct(id: item.id)
    }

    func handlePurchaseError(_ error: Error) {
        alertMessage = error.localizedDescription
        showAlert = true
    }

    func restorePurchases() {
        isRestoringPurchases = true
        Task { @MainActor in
            await StoreManager.shared.restorePurchases()
            isRestoringPurchases = false
            refreshPurchaseStates()
            alertMessage = NSLocalizedString("Purchases restored successfully.", comment: "")
            showAlert = true
        }
    }

    // MARK: - Private Helpers

    private func updateItems(with products: [Product]) {
        let store = StoreManager.shared

        for product in products {
            switch product.id {
            case enableVideoPID:
                proMode.title = product.displayName
                proMode.price = product.displayPrice
                proMode.isPurchased = store.hasProMode()
            case disableAdsPID:
                removeAds.title = product.displayName
                removeAds.price = product.displayPrice
                removeAds.isPurchased = store.hasAdRemovalFeature()
            case enableTorchPID:
                enableTorch.title = product.displayName
                enableTorch.price = product.displayPrice
                enableTorch.isPurchased = store.hasTorchFeature()
            case enableVideoOnlyPID:
                enableVideo.title = product.displayName
                enableVideo.price = product.displayPrice
                enableVideo.isPurchased = store.hasVideoRecordingFeature()
            case tapToFocusPID:
                tapToFocus.title = product.displayName
                tapToFocus.price = product.displayPrice
                tapToFocus.isPurchased = store.hasTapToFocusFeature()
            case proMonthlyPID:
                proSubscriptionMonthly.title = product.displayName
                proSubscriptionMonthly.price = product.displayPrice
                proSubscriptionMonthly.isPurchased = store.hasProSubscription()
            case proYearlyPID:
                proSubscriptionYearly.title = product.displayName
                proSubscriptionYearly.price = product.displayPrice
                proSubscriptionYearly.isPurchased = store.hasProSubscription()
            default:
                break
            }
        }
    }

    func refreshPurchaseStates() {
        let store = StoreManager.shared
        proSubscriptionMonthly.isPurchased = store.hasProSubscription()
        proSubscriptionYearly.isPurchased = store.hasProSubscription()
        proMode.isPurchased = store.hasProMode()
        removeAds.isPurchased = store.hasAdRemovalFeature()
        enableTorch.isPurchased = store.hasTorchFeature()
        enableVideo.isPurchased = store.hasVideoRecordingFeature()
        tapToFocus.isPurchased = store.hasTapToFocusFeature()
    }

}
