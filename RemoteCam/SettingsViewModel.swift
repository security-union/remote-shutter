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

    // Titles/prices are intentionally empty — they come from StoreKit
    // (product.displayName/displayPrice, localized by App Store Connect). The UI
    // shows a skeleton until `productsLoaded`, so there are no app-side name strings.
    @Published var proSubscriptionMonthly = PurchaseItem(id: proMonthlyPID, title: "", price: "", isPurchased: false)
    @Published var proSubscriptionYearly = PurchaseItem(id: proYearlyPID, title: "", price: "", isPurchased: false)
    @Published var proMode = PurchaseItem(id: enableVideoPID, title: "", price: "", isPurchased: false)
    @Published var removeAds = PurchaseItem(id: disableAdsPID, title: "", price: "", isPurchased: false)
    @Published var enableTorch = PurchaseItem(id: enableTorchPID, title: "", price: "", isPurchased: false)
    @Published var enableVideo = PurchaseItem(id: enableVideoOnlyPID, title: "", price: "", isPurchased: false)
    @Published var tapToFocus = PurchaseItem(id: tapToFocusPID, title: "", price: "", isPurchased: false)
    @Published var maxCamerasPack = PurchaseItem(id: maxCamerasPID, title: "", price: "", isPurchased: false)
    /// True once the StoreKit product fetch has completed (success or not), so
    /// the paywall can swap skeleton rows for real names/prices.
    @Published var productsLoaded = false

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
            productsLoaded = true
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
                // Full access (one-time OR subscription) marks the one-time Pro
                // as owned so a subscriber can't redundantly buy it on top.
                proMode.isPurchased = store.hasFullAccess()
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
            case maxCamerasPID:
                maxCamerasPack.title = product.displayName
                maxCamerasPack.price = product.displayPrice
                maxCamerasPack.isPurchased = store.hasMaxCamerasFeature()
            case proMonthlyPID:
                proSubscriptionMonthly.title = product.displayName
                proSubscriptionMonthly.price = product.displayPrice
                // Full access blocks re-subscribing (e.g. a one-time 06 owner);
                // plan switches happen via the system Manage Subscriptions sheet.
                proSubscriptionMonthly.isPurchased = store.hasFullAccess()
            case proYearlyPID:
                proSubscriptionYearly.title = product.displayName
                proSubscriptionYearly.price = product.displayPrice
                proSubscriptionYearly.isPurchased = store.hasFullAccess()
            default:
                break
            }
        }
    }

    func refreshPurchaseStates() {
        let store = StoreManager.shared
        proSubscriptionMonthly.isPurchased = store.hasFullAccess()
        proSubscriptionYearly.isPurchased = store.hasFullAccess()
        proMode.isPurchased = store.hasFullAccess()
        removeAds.isPurchased = store.hasAdRemovalFeature()
        enableTorch.isPurchased = store.hasTorchFeature()
        enableVideo.isPurchased = store.hasVideoRecordingFeature()
        tapToFocus.isPurchased = store.hasTapToFocusFeature()
        maxCamerasPack.isPurchased = store.hasMaxCamerasFeature()
    }

}
