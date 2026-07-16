import XCTest
@testable import RemoteShutter

final class SettingsViewModelTests: XCTestCase {

    private let sendMediaKey = "sendMediaToRemote"

    private let proSubscriptionKey = "hasActiveProSubscription"

    override func tearDown() {
        super.tearDown()
        // Clean up UserDefaults changes made during tests
        UserDefaults.standard.removeObject(forKey: sendMediaKey)
        UserDefaults.standard.removeObject(forKey: proSubscriptionKey)
    }

    // MARK: - Double-charge protection

    func testSubscriberCannotRedundantlyBuyOneTimePro() {
        UserDefaults.standard.set(true, forKey: proSubscriptionKey)
        let vm = SettingsViewModel()
        vm.refreshPurchaseStates()
        // A subscriber already has full access, so the one-time "Pro: All
        // Features" and both subscription rows are marked owned (purchase blocked).
        XCTAssertTrue(vm.proMode.isPurchased)
        XCTAssertTrue(vm.proSubscriptionMonthly.isPurchased)
        XCTAssertTrue(vm.proSubscriptionYearly.isPurchased)
        XCTAssertTrue(vm.tapToFocus.isPurchased)
    }

    // MARK: - Send Media to Remote

    func testSendMediaToRemoteDefaultsToTrue() {
        // Ensure the key has no value
        UserDefaults.standard.removeObject(forKey: sendMediaKey)

        let vm = SettingsViewModel()
        XCTAssertTrue(vm.sendMediaToRemote, "Should default to true when UserDefaults key is absent")
    }

    func testSendMediaToRemoteReadsExistingFalse() {
        UserDefaults.standard.set(false, forKey: sendMediaKey)

        let vm = SettingsViewModel()
        XCTAssertFalse(vm.sendMediaToRemote, "Should read false from UserDefaults")
    }

    func testSendMediaToRemoteWritesToUserDefaults() {
        UserDefaults.standard.removeObject(forKey: sendMediaKey)

        let vm = SettingsViewModel()
        vm.sendMediaToRemote = false

        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: sendMediaKey),
            "Setting sendMediaToRemote should persist to UserDefaults"
        )
    }

    func testSendMediaToRemotePersistsAcrossInstances() {
        UserDefaults.standard.set(false, forKey: sendMediaKey)

        let vm1 = SettingsViewModel()
        XCTAssertFalse(vm1.sendMediaToRemote, "Should read persisted false")

        vm1.sendMediaToRemote = true

        let vm2 = SettingsViewModel()
        XCTAssertTrue(vm2.sendMediaToRemote, "New instance should read value written by previous instance")
    }

    // MARK: - App Version

    func testAppVersionIsNotEmpty() {
        let vm = SettingsViewModel()
        XCTAssertFalse(vm.appVersion.isEmpty, "App version should not be empty")
        XCTAssertTrue(vm.appVersion.contains("("), "App version should contain build number in parens")
    }

    // MARK: - Purchase State Initialization

    func testInitialPurchaseStatesMatchStoreManager() {
        let vm = SettingsViewModel()
        let store = StoreManager.shared

        XCTAssertEqual(vm.proMode.isPurchased, store.hasFullAccess())
        XCTAssertEqual(vm.removeAds.isPurchased, store.hasAdRemovalFeature())
        XCTAssertEqual(vm.enableTorch.isPurchased, store.hasTorchFeature())
        XCTAssertEqual(vm.enableVideo.isPurchased, store.hasVideoRecordingFeature())
        XCTAssertEqual(vm.tapToFocus.isPurchased, store.hasTapToFocusFeature())
        // Full-access products block each other so a subscriber can't re-buy the
        // one-time Pro (and vice-versa).
        XCTAssertEqual(vm.proSubscriptionMonthly.isPurchased, store.hasFullAccess())
        XCTAssertEqual(vm.proSubscriptionYearly.isPurchased, store.hasFullAccess())
    }

    func testPurchaseItemIdsMatchProductConstants() {
        let vm = SettingsViewModel()
        XCTAssertEqual(vm.proMode.id, enableVideoPID)
        XCTAssertEqual(vm.removeAds.id, disableAdsPID)
        XCTAssertEqual(vm.enableTorch.id, enableTorchPID)
        XCTAssertEqual(vm.enableVideo.id, enableVideoOnlyPID)
        XCTAssertEqual(vm.tapToFocus.id, tapToFocusPID)
        XCTAssertEqual(vm.proSubscriptionMonthly.id, proMonthlyPID)
        XCTAssertEqual(vm.proSubscriptionYearly.id, proYearlyPID)
    }

    // MARK: - Purchase Notification Handling

    func testRefreshesPurchaseStateOnNotification() {
        let vm = SettingsViewModel()

        // Simulate a purchase by setting the UserDefaults flag directly
        let key = "didBuyEnableTorchFeature"
        let oldValue = UserDefaults.standard.bool(forKey: key)
        UserDefaults.standard.set(true, forKey: key)

        // Post notification (same as StoreManager does on purchase)
        NotificationCenter.default.post(name: .enableTorch, object: nil)

        // The ViewModel should have refreshed
        XCTAssertTrue(vm.enableTorch.isPurchased, "Should refresh purchase state on notification")

        // Restore
        UserDefaults.standard.set(oldValue, forKey: key)
    }

    // MARK: - Flags

    func testIsNotPurchasingByDefault() {
        let vm = SettingsViewModel()
        XCTAssertFalse(vm.isPurchasing)
        XCTAssertFalse(vm.isRestoringPurchases)
        XCTAssertFalse(vm.showAlert)
    }
}
