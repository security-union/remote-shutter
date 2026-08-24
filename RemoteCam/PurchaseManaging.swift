import StoreKit

protocol PurchaseManaging: AnyObject {
    var isPurchasing: Bool { get set }
    var notificationObservers: [NSObjectProtocol] { get set }
    func refreshPurchaseStates()
    func handlePurchaseError(_ error: Error)
}

extension PurchaseManaging {

    func observePurchaseNotifications() {
        let names: [Notification.Name] = [
            .removeAds, .proModeAcquired, .enableTorch, .enableVideoOnly,
            .tapToFocusAcquired, .proSubscriptionAcquired
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

    func removeNotificationObservers() {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func purchaseProduct(id: String) {
        guard let product = StoreManager.shared.products.first(where: { $0.id == id }) else { return }
        isPurchasing = true
        Task { @MainActor [weak self] in
            do {
                let transaction = try await StoreManager.shared.purchase(product)
                self?.isPurchasing = false
                if transaction != nil {
                    self?.refreshPurchaseStates()
                }
            } catch {
                self?.isPurchasing = false
                self?.handlePurchaseError(error)
            }
        }
    }
}
