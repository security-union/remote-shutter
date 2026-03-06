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

    private var products: [SKProduct] = []
    private var notificationObservers: [NSObjectProtocol] = []

    // MARK: - Init

    init() {
        // Read current value; default to true if key doesn't exist (matches ObjC behavior)
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
        let manager = InAppPurchasesManager.shared()!
        let existingProducts = manager.products as? [SKProduct] ?? []

        if !existingProducts.isEmpty {
            updateItems(with: existingProducts)
        } else {
            manager.reloadProducts { [weak self] _, error in
                guard error == nil, let self else { return }
                let loaded = manager.products as? [SKProduct] ?? []
                DispatchQueue.main.async {
                    self.updateItems(with: loaded)
                }
            }
        }
    }

    // MARK: - Purchasing

    func purchase(_ item: PurchaseItem) {
        guard !item.isPurchased else { return }
        let manager = InAppPurchasesManager.shared()!

        isPurchasing = true
        manager.userWants(toBuyFeature: item.id) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isPurchasing = false
                if let error {
                    self.alertMessage = error.localizedDescription
                    self.showAlert = true
                } else {
                    self.refreshPurchaseStates()
                }
            }
        }
    }

    func restorePurchases() {
        isRestoringPurchases = true
        InAppPurchasesManager.shared().restorePurchases { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRestoringPurchases = false
                if error == nil {
                    self.refreshPurchaseStates()
                    self.alertMessage = NSLocalizedString("Purchases restored successfully.", comment: "")
                } else {
                    self.alertMessage = error?.localizedDescription
                }
                self.showAlert = true
            }
        }
    }

    // MARK: - Private Helpers

    private func updateItems(with products: [SKProduct]) {
        self.products = products
        let manager = InAppPurchasesManager.shared()!
        let formatter = manager.currencyFormatter()!

        for product in products {
            formatter.locale = product.priceLocale
            let price = formatter.string(from: product.price) ?? ""

            switch product.productIdentifier {
            case enableVideoPID:
                proMode.title = product.localizedTitle
                proMode.price = price
                proMode.isPurchased = manager.hasProMode()
            case disableAdsPID:
                removeAds.title = product.localizedTitle
                removeAds.price = price
                removeAds.isPurchased = manager.hasAdRemovalFeature()
            case enableTorchPID:
                enableTorch.title = product.localizedTitle
                enableTorch.price = price
                enableTorch.isPurchased = manager.hasTorchFeature()
            case enableVideoOnlyPID:
                enableVideo.title = product.localizedTitle
                enableVideo.price = price
                enableVideo.isPurchased = manager.hasVideoRecordingFeature()
            default:
                break
            }
        }
    }

    private func refreshPurchaseStates() {
        let manager = InAppPurchasesManager.shared()!
        proMode.isPurchased = manager.hasProMode()
        removeAds.isPurchased = manager.hasAdRemovalFeature()
        enableTorch.isPurchased = manager.hasTorchFeature()
        enableVideo.isPurchased = manager.hasVideoRecordingFeature()
    }

    private func observePurchaseNotifications() {
        let names: [String] = [
            Constants.removeAds(),
            Constants.proModeAquired(),
            Constants.enableTorch(),
            Constants.enableVideoOnly()
        ]
        for name in names {
            let observer = NotificationCenter.default.addObserver(
                forName: NSNotification.Name(rawValue: name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.refreshPurchaseStates()
            }
            notificationObservers.append(observer)
        }
    }
}
