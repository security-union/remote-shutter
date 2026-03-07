import XCTest
@testable import RemoteShutter

final class StoreManagerTests: XCTestCase {

    // MARK: - UserDefaults keys (must match StoreManager's internal keys)
    private let removeAdsKey = "didBuyRemoveiAdsFeature"
    private let proModeKey = "didBuyProMode"
    private let torchKey = "didBuyEnableTorchFeature"
    private let videoOnlyKey = "didBuyEnableVideoOnlyFeature"

    private var savedValues: [String: Bool] = [:]

    override func setUp() {
        super.setUp()
        // Save existing values so tests don't corrupt real state
        let keys = [removeAdsKey, proModeKey, torchKey, videoOnlyKey]
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
        XCTAssertTrue(store.hasAdRemovalFeature(), "Pro mode should include ad removal")
        XCTAssertTrue(store.hasTorchFeature(), "Pro mode should include torch")
        XCTAssertTrue(store.hasVideoRecordingFeature(), "Pro mode should include video recording")
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
    }

    func testAllProductIDsContainsAllFour() {
        let ids = StoreManager.allProductIDs
        XCTAssertEqual(ids.count, 4)
        XCTAssertTrue(ids.contains(disableAdsPID))
        XCTAssertTrue(ids.contains(enableVideoPID))
        XCTAssertTrue(ids.contains(enableTorchPID))
        XCTAssertTrue(ids.contains(enableVideoOnlyPID))
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
