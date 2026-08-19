import XCTest
@testable import RemoteShutter

final class StoreManagerTests: XCTestCase {

    // MARK: - UserDefaults keys (must match StoreManager's internal keys)
    private let removeAdsKey = "didBuyRemoveiAdsFeature"
    private let proModeKey = "didBuyProMode"
    private let torchKey = "didBuyEnableTorchFeature"
    private let videoOnlyKey = "didBuyEnableVideoOnlyFeature"
    private let tapToFocusKey = "didBuyTapToFocusFeature"
    private let fourCamerasKey = "didBuyFourCamerasFeature"
    private let proSubscriptionKey = "hasActiveProSubscription"

    private var savedValues: [String: Bool] = [:]

    override func setUp() {
        super.setUp()
        // Save existing values so tests don't corrupt real state
        let keys = [removeAdsKey, proModeKey, torchKey, videoOnlyKey,
                    tapToFocusKey, fourCamerasKey, proSubscriptionKey]
        for key in keys {
            savedValues[key] = UserDefaults.standard.bool(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        // Restore original values
        for (key, value) in savedValues {
            UserDefaults.standard.set(value, forKey: key)
        }
        super.tearDown()
    }

    // MARK: - Feature Availability (Default State)

    func testNoFeaturesAvailableByDefault() {
        let store = StoreManager.shared
        // With all keys cleared, no features should be available
        XCTAssertFalse(store.hasProMode())
        XCTAssertFalse(store.hasAdRemovalFeature())
        XCTAssertFalse(store.hasTorchFeature())
        XCTAssertFalse(store.hasVideoRecordingFeature())
        XCTAssertFalse(store.hasProSubscription())
        XCTAssertFalse(store.hasFullAccess())
        XCTAssertFalse(store.hasTapToFocusFeature())
        XCTAssertFalse(store.hasFourCamerasFeature())
    }

    // MARK: - Multicam camera cap

    func testFreeTierGetsTwoCameras() {
        XCTAssertEqual(StoreManager.shared.maxCameras(), 2)
    }

    /// Pro unlocks everything, paid-cap directing included — the one-time
    /// bundle and the subscription both land on the full paid cap.
    func testProModeUnlocksPaidCameraCap() {
        UserDefaults.standard.set(true, forKey: proModeKey)
        XCTAssertTrue(StoreManager.shared.hasFourCamerasFeature())
        XCTAssertEqual(StoreManager.shared.maxCameras(), StoreManager.maxPaidCameras)
    }

    func testProSubscriptionUnlocksPaidCameraCap() {
        UserDefaults.standard.set(true, forKey: proSubscriptionKey)
        XCTAssertEqual(StoreManager.shared.maxCameras(), StoreManager.maxPaidCameras)
    }

    /// The à la carte pack reaches the same cap without Pro.
    func testFourCameraPackAloneUnlocksPaidCameraCap() {
        UserDefaults.standard.set(true, forKey: fourCamerasKey)
        XCTAssertEqual(StoreManager.shared.maxCameras(), StoreManager.maxPaidCameras)
    }

    /// The constants every gate and every piece of copy derive from.
    func testCameraCapConstants() {
        XCTAssertEqual(StoreManager.maxFreeCameras, 2)
        XCTAssertEqual(StoreManager.maxPaidCameras, 4)
    }

    /// The paywall offers the 4-camera pack whenever the cap honors what
    /// the product sells — true today (both are 4); raising the pack's
    /// promise past the cap withholds the row.
    func testFourCameraPackIsOfferedWhileTheCapHonorsItsPromise() {
        XCTAssertTrue(StoreManager.offersFourCamerasPack)
        XCTAssertEqual(StoreManager.fourCamerasPackCameraCount, 4)
    }

    // MARK: - Individual Feature Flags

    func testHasAdRemovalWhenPurchased() {
        UserDefaults.standard.set(true, forKey: removeAdsKey)
        XCTAssertTrue(StoreManager.shared.hasAdRemovalFeature())
    }

    func testHasTorchWhenPurchased() {
        UserDefaults.standard.set(true, forKey: torchKey)
        XCTAssertTrue(StoreManager.shared.hasTorchFeature())
    }

    func testHasVideoRecordingWhenPurchased() {
        UserDefaults.standard.set(true, forKey: videoOnlyKey)
        XCTAssertTrue(StoreManager.shared.hasVideoRecordingFeature())
    }

    // MARK: - Pro Mode Grants All Features

    func testProModeGrantsAllFeatures() {
        UserDefaults.standard.set(true, forKey: proModeKey)

        let store = StoreManager.shared
        XCTAssertTrue(store.hasProMode())
        XCTAssertTrue(store.hasFullAccess())
        XCTAssertTrue(store.hasAdRemovalFeature(), "Pro mode should include ad removal")
        XCTAssertTrue(store.hasTorchFeature(), "Pro mode should include torch")
        XCTAssertTrue(store.hasVideoRecordingFeature(), "Pro mode should include video recording")
        XCTAssertTrue(store.hasTapToFocusFeature(), "Pro mode should include tap to focus")
    }

    // MARK: - Pro Subscription Grants All Features

    func testProSubscriptionGrantsAllFeatures() {
        UserDefaults.standard.set(true, forKey: proSubscriptionKey)

        let store = StoreManager.shared
        XCTAssertTrue(store.hasProSubscription())
        XCTAssertTrue(store.hasFullAccess())
        XCTAssertTrue(store.hasAdRemovalFeature(), "Subscription should include ad removal")
        XCTAssertTrue(store.hasTorchFeature(), "Subscription should include torch")
        XCTAssertTrue(store.hasVideoRecordingFeature(), "Subscription should include video recording")
        XCTAssertTrue(store.hasTapToFocusFeature(), "Subscription should include tap to focus")
        // The subscription is not the one-time Pro bundle.
        XCTAssertFalse(store.hasProMode(), "Subscription must not be conflated with the one-time 06 bundle")
    }

    /// The subscription flag is revocable (unlike the append-only one-time
    /// flags): clearing it — as refreshPurchaseState does when the subscription
    /// is absent from currentEntitlements — removes access, while an
    /// independently-owned one-time feature survives.
    func testClearingSubscriptionRevokesAccessButKeepsOneTimePurchases() {
        UserDefaults.standard.set(true, forKey: proSubscriptionKey)
        UserDefaults.standard.set(true, forKey: torchKey)   // separately owned one-time IAP
        let store = StoreManager.shared
        XCTAssertTrue(store.hasVideoRecordingFeature())

        UserDefaults.standard.set(false, forKey: proSubscriptionKey)   // lapsed

        XCTAssertFalse(store.hasProSubscription())
        XCTAssertFalse(store.hasFullAccess())
        XCTAssertFalse(store.hasVideoRecordingFeature(), "video was only via the lapsed subscription")
        XCTAssertTrue(store.hasTorchFeature(), "the separately-owned one-time torch survives")
    }

    // MARK: - Tap to Focus

    func testTapToFocusUnlockedByOwnPurchase() {
        UserDefaults.standard.set(true, forKey: tapToFocusKey)
        let store = StoreManager.shared
        XCTAssertTrue(store.hasTapToFocusFeature())
        // The dedicated IAP unlocks only tap-to-focus, nothing else.
        XCTAssertFalse(store.hasVideoRecordingFeature())
        XCTAssertFalse(store.hasTorchFeature())
    }

    // MARK: - Individual Purchase Does Not Grant Other Features

    func testAdRemovalDoesNotGrantTorch() {
        UserDefaults.standard.set(true, forKey: removeAdsKey)
        XCTAssertFalse(StoreManager.shared.hasTorchFeature())
    }

    func testTorchDoesNotGrantVideoRecording() {
        UserDefaults.standard.set(true, forKey: torchKey)
        XCTAssertFalse(StoreManager.shared.hasVideoRecordingFeature())
    }

    func testVideoOnlyDoesNotGrantAdRemoval() {
        UserDefaults.standard.set(true, forKey: videoOnlyKey)
        XCTAssertFalse(StoreManager.shared.hasAdRemovalFeature())
    }

    // MARK: - Product IDs

    func testProductIDConstants() {
        XCTAssertEqual(disableAdsPID, "05")
        XCTAssertEqual(enableVideoPID, "06")
        XCTAssertEqual(enableTorchPID, "07")
        XCTAssertEqual(enableVideoOnlyPID, "08")
        XCTAssertEqual(tapToFocusPID, "09")
        XCTAssertEqual(fourCamerasPID, "four_cameras")
        XCTAssertEqual(proMonthlyPID, "pro_monthly")
        XCTAssertEqual(proYearlyPID, "pro_yearly")
    }

    func testAllProductIDsContainsEveryProduct() {
        let ids = StoreManager.allProductIDs
        XCTAssertEqual(ids.count, 8)
        XCTAssertTrue(ids.contains(disableAdsPID))
        XCTAssertTrue(ids.contains(enableVideoPID))
        XCTAssertTrue(ids.contains(enableTorchPID))
        XCTAssertTrue(ids.contains(enableVideoOnlyPID))
        XCTAssertTrue(ids.contains(tapToFocusPID))
        XCTAssertTrue(ids.contains(fourCamerasPID))
        XCTAssertTrue(ids.contains(proMonthlyPID))
        XCTAssertTrue(ids.contains(proYearlyPID))
    }

    func testSubscriptionProductIDs() {
        XCTAssertEqual(StoreManager.subscriptionProductIDs, [proMonthlyPID, proYearlyPID])
    }

    // MARK: - Notification Names

    func testNotificationNamesMatchLegacyStrings() {
        // These must match the ObjC Constants.h values for backward compat
        XCTAssertEqual(Notification.Name.removeAds.rawValue, "RemoveAds")
        XCTAssertEqual(Notification.Name.proModeAcquired.rawValue, "ProModeAquired")
        XCTAssertEqual(Notification.Name.enableTorch.rawValue, "EnableTorch")
        XCTAssertEqual(Notification.Name.enableVideoOnly.rawValue, "EnableVideoOnly")
    }

    // MARK: - Singleton

    func testSharedInstanceIsSingleton() {
        let a = StoreManager.shared
        let b = StoreManager.shared
        XCTAssertTrue(a === b)
    }
}
