import Foundation
import StoreKit
import Combine

private let sendMediaToRemoteKey = "sendMediaToRemote"

final class SettingsViewModel: ObservableObject {

    // MARK: - Purchase State

    struct PurchaseItem: Identifiable {
        let id: String // product identifier
        var title: String
        var price: String
        var isPurchased: Bool
    }

    @Published var proMode = PurchaseItem(id: enableVideoPID, title: "Pro: All Features", price: "", isPurchased: false)
    @Published var removeAds = PurchaseItem(id: disableAdsPID, title: "Remove Ads", price: "", isPurchased: false)
    @Published var enableTorch = PurchaseItem(id: enableTorchPID, title: "Enable Torch", price: "", isPurchased: false)
    @Published var enableVideo = PurchaseItem(id: enableVideoOnlyPID, title: "Enable Video", price: "", isPurchased: false)

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

    private var notificationObservers: [NSObjectProtocol] = []

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
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
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
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
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
            default:
                break
            }
        }
    }

    private func refreshPurchaseStates() {
        let store = StoreManager.shared
        proMode.isPurchased = store.hasProMode()
        removeAds.isPurchased = store.hasAdRemovalFeature()
        enableTorch.isPurchased = store.hasTorchFeature()
        enableVideo.isPurchased = store.hasVideoRecordingFeature()
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
