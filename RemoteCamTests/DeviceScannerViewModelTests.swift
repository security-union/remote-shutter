import XCTest
import MPCCompat
import Stormo
@testable import RemoteShutter

final class DeviceScannerViewModelTests: XCTestCase {

    private let speedRunKey = "speedrunscanning"

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: speedRunKey)
    }

    // MARK: - Initial State

    func testInitialState() {
        let vm = DeviceScannerViewModel()
        XCTAssertTrue(vm.connectedPeers.isEmpty)
        XCTAssertFalse(vm.isScanning)
        XCTAssertTrue(vm.hasLocalNetworkAccess)
        XCTAssertFalse(vm.hasScanningError)
        XCTAssertFalse(vm.isConnecting)
        XCTAssertFalse(vm.hasPeers)
    }

    // MARK: - Peer Management

    func testAddPeer() {
        let vm = DeviceScannerViewModel()
        let peer = MCPeerID(displayName: "TestDevice")

        vm.addPeer(peer)

        XCTAssertEqual(vm.connectedPeers.count, 1)
        XCTAssertEqual(vm.connectedPeers.first?.displayName, "TestDevice")
        XCTAssertTrue(vm.hasPeers)
    }

    func testAddDuplicatePeerIgnored() {
        let vm = DeviceScannerViewModel()
        let peer = MCPeerID(displayName: "TestDevice")

        vm.addPeer(peer)
        vm.addPeer(peer)

        XCTAssertEqual(vm.connectedPeers.count, 1, "Should not add duplicate peer")
    }

    func testAddPeerSetsSpeedRunScanning() {
        UserDefaults.standard.removeObject(forKey: speedRunKey)
        let vm = DeviceScannerViewModel()
        let peer = MCPeerID(displayName: "TestDevice")

        vm.addPeer(peer)

        XCTAssertTrue(vm.speedRunScanning, "Adding a peer should enable speed run scanning")
    }

    func testRemovePeer() {
        let vm = DeviceScannerViewModel()
        let peer1 = MCPeerID(displayName: "Device1")
        let peer2 = MCPeerID(displayName: "Device2")

        vm.addPeer(peer1)
        vm.addPeer(peer2)
        vm.removePeer(peer1)

        XCTAssertEqual(vm.connectedPeers.count, 1)
        XCTAssertEqual(vm.connectedPeers.first?.displayName, "Device2")
    }

    func testRemoveNonExistentPeerNoOp() {
        let vm = DeviceScannerViewModel()
        let peer = MCPeerID(displayName: "Ghost")

        vm.removePeer(peer)

        XCTAssertTrue(vm.connectedPeers.isEmpty)
    }

    func testClearPeers() {
        let vm = DeviceScannerViewModel()
        vm.addPeer(MCPeerID(displayName: "A"))
        vm.addPeer(MCPeerID(displayName: "B"))

        vm.clearPeers()

        XCTAssertTrue(vm.connectedPeers.isEmpty)
        XCTAssertFalse(vm.hasPeers)
    }

    // MARK: - Scanning State

    func testStartedScanning() {
        let vm = DeviceScannerViewModel()
        vm.addPeer(MCPeerID(displayName: "OldPeer"))

        vm.startedScanning()

        XCTAssertTrue(vm.isScanning)
        XCTAssertFalse(vm.hasScanningError)
        XCTAssertFalse(vm.isConnecting)
        XCTAssertTrue(vm.connectedPeers.isEmpty, "Starting scan should clear existing peers")
    }

    func testStoppedScanning() {
        let vm = DeviceScannerViewModel()
        vm.startedScanning()

        vm.stoppedScanning()

        XCTAssertFalse(vm.isScanning)
        XCTAssertFalse(vm.isConnecting)
    }

    func testScanningFailed() {
        let vm = DeviceScannerViewModel()
        UserDefaults.standard.set(true, forKey: speedRunKey)
        vm.startedScanning()

        vm.scanningFailed()

        XCTAssertFalse(vm.isScanning)
        XCTAssertTrue(vm.hasScanningError)
        XCTAssertFalse(vm.isConnecting)
        XCTAssertFalse(vm.speedRunScanning, "Scanning failure should disable speed run")
    }

    // MARK: - Network Access

    func testNetworkAccessDenied() {
        let vm = DeviceScannerViewModel()
        UserDefaults.standard.set(true, forKey: speedRunKey)

        vm.networkAccessDenied()

        XCTAssertFalse(vm.hasLocalNetworkAccess)
        XCTAssertTrue(vm.hasScanningError)
        XCTAssertFalse(vm.speedRunScanning)
    }

    func testNetworkAccessGranted() {
        let vm = DeviceScannerViewModel()
        vm.networkAccessDenied()

        vm.networkAccessGranted()

        XCTAssertTrue(vm.hasLocalNetworkAccess)
        XCTAssertFalse(vm.hasScanningError)
    }

    // MARK: - Connection State

    func testConnectingToPeer() {
        let vm = DeviceScannerViewModel()

        vm.connectingToPeer()

        XCTAssertTrue(vm.isConnecting)
    }

    func testConnectedToPeer() {
        let vm = DeviceScannerViewModel()
        vm.connectingToPeer()

        vm.connectedToPeer()

        XCTAssertFalse(vm.isConnecting)
    }

    // MARK: - Status Message

    func testStatusMessageIdle() {
        let vm = DeviceScannerViewModel()

        XCTAssertEqual(
            vm.statusMessage,
            NSLocalizedString("TAP THE BUTTON TO GET STARTED", comment: "")
        )
    }

    func testStatusMessageScanningMonitorRole() {
        let vm = DeviceScannerViewModel()
        vm.role = .monitor
        vm.startedScanning()

        XCTAssertEqual(
            vm.statusMessage,
            NSLocalizedString("SEARCHING FOR NEARBY CAMERAS...", comment: "")
        )
    }

    func testStatusMessageScanningCameraRole() {
        let vm = DeviceScannerViewModel()
        vm.role = .camera
        vm.startedScanning()

        XCTAssertEqual(
            vm.statusMessage,
            NSLocalizedString("WAITING FOR A REMOTE TO CONNECT...", comment: "")
        )
    }

    func testStatusMessageError() {
        let vm = DeviceScannerViewModel()
        vm.scanningFailed()

        XCTAssertEqual(
            vm.statusMessage,
            NSLocalizedString("SCANNING ERROR - CHECK NETWORK SETTINGS", comment: "")
        )
    }

    // MARK: - SpeedRunScanning UserDefaults

    func testSpeedRunScanningDefaultsFalse() {
        UserDefaults.standard.removeObject(forKey: speedRunKey)
        let vm = DeviceScannerViewModel()
        XCTAssertFalse(vm.speedRunScanning)
    }

    func testSpeedRunScanningPersists() {
        let vm = DeviceScannerViewModel()
        vm.speedRunScanning = true

        let vm2 = DeviceScannerViewModel()
        XCTAssertTrue(vm2.speedRunScanning, "Speed run setting should persist across instances")
    }

    // MARK: - Full Workflow

    func testTypicalScanAndConnectWorkflow() {
        let vm = DeviceScannerViewModel()

        // Start scanning
        vm.startedScanning()
        XCTAssertTrue(vm.isScanning)
        XCTAssertFalse(vm.hasPeers)

        // Discover peer
        let peer = MCPeerID(displayName: "FriendPhone")
        vm.addPeer(peer)
        XCTAssertTrue(vm.hasPeers)

        // Tap to connect
        vm.connectingToPeer()
        XCTAssertTrue(vm.isConnecting)

        // Connected
        vm.connectedToPeer()
        XCTAssertFalse(vm.isConnecting)
    }

    func testNetworkDeniedThenGrantedWorkflow() {
        let vm = DeviceScannerViewModel()

        // Denied
        vm.networkAccessDenied()
        XCTAssertFalse(vm.hasLocalNetworkAccess)
        XCTAssertTrue(vm.hasScanningError)

        // User fixes settings, granted
        vm.networkAccessGranted()
        XCTAssertTrue(vm.hasLocalNetworkAccess)
        XCTAssertFalse(vm.hasScanningError)

        // Now scan works
        vm.startedScanning()
        XCTAssertTrue(vm.isScanning)
    }

    // MARK: - QR Code Generation

    func testQRCodeGenerationProducesImage() {
        let image = generateQRCode(remoteShutterUrl)
        XCTAssertNotNil(image, "generateQRCode should produce a non-nil UIImage for the app store URL")
    }

    func testQRCodeGenerationWithEmptyStringReturnsImage() {
        let image = generateQRCode("")
        XCTAssertNotNil(image, "generateQRCode should handle empty string")
    }

    // MARK: - MCPeerID Identity Tests

    func testAddPeerWithSameDisplayNameDifferentInstances() {
        let vm = DeviceScannerViewModel()
        let peer1 = MCPeerID(displayName: "SameName")
        let peer2 = MCPeerID(displayName: "SameName")

        vm.addPeer(peer1)
        vm.addPeer(peer2)

        // MCPeerID uses object identity, not display name equality.
        // Two different MCPeerID instances with the same name are NOT equal.
        // This means the duplicate check in addPeer won't catch them.
        XCTAssertEqual(vm.connectedPeers.count, 2,
            "Different MCPeerID instances with same displayName should both be added since MCPeerID uses object identity")
    }

    func testRemovePeerByIdentityNotDisplayName() {
        let vm = DeviceScannerViewModel()
        let peer1 = MCPeerID(displayName: "SameName")
        let peer2 = MCPeerID(displayName: "SameName")

        vm.addPeer(peer1)
        vm.addPeer(peer2)

        // Removing peer1 should only remove the first, not the second
        vm.removePeer(peer1)
        XCTAssertEqual(vm.connectedPeers.count, 1,
            "Removing by identity should only remove the matching instance")
    }

    // MARK: - Combine Publishing Tests

    func testAddPeerTriggersPublishedUpdate() {
        let vm = DeviceScannerViewModel()
        let peer = MCPeerID(displayName: "PubTest")
        let expectation = XCTestExpectation(description: "connectedPeers should publish change")

        let cancellable = vm.$connectedPeers
            .dropFirst() // skip initial value
            .sink { peers in
                if peers.count == 1 && peers.first?.displayName == "PubTest" {
                    expectation.fulfill()
                }
            }

        vm.addPeer(peer)

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()
    }

    func testStartedScanningTriggersIsScanningPublish() {
        let vm = DeviceScannerViewModel()
        let expectation = XCTestExpectation(description: "isScanning should publish true")

        let cancellable = vm.$isScanning
            .dropFirst()
            .sink { isScanning in
                if isScanning {
                    expectation.fulfill()
                }
            }

        vm.startedScanning()

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()
    }

    // MARK: - Wi-Fi Escalation

    func testScanStartedAtLifecycle() {
        let vm = DeviceScannerViewModel()
        XCTAssertNil(vm.scanStartedAt)

        vm.startedScanning()
        XCTAssertNotNil(vm.scanStartedAt)

        vm.stoppedScanning()
        XCTAssertNil(vm.scanStartedAt)

        vm.startedScanning()
        vm.scanningFailed()
        XCTAssertNil(vm.scanStartedAt)
    }

    func testWifiEscalationRequiresScanning() {
        let start = Date(timeIntervalSince1970: 1_000)
        let later = start.addingTimeInterval(60)
        XCTAssertFalse(DeviceScannerViewModel.shouldShowWifiEscalation(
            isScanning: false, hasPeers: false, scanStartedAt: start, now: later))
    }

    func testWifiEscalationSuppressedWhenPeersFound() {
        let start = Date(timeIntervalSince1970: 1_000)
        let later = start.addingTimeInterval(60)
        XCTAssertFalse(DeviceScannerViewModel.shouldShowWifiEscalation(
            isScanning: true, hasPeers: true, scanStartedAt: start, now: later))
    }

    func testWifiEscalationRequiresStartDate() {
        XCTAssertFalse(DeviceScannerViewModel.shouldShowWifiEscalation(
            isScanning: true, hasPeers: false, scanStartedAt: nil,
            now: Date(timeIntervalSince1970: 1_000)))
    }

    func testWifiEscalationBeforeThreshold() {
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(DeviceScannerViewModel.shouldShowWifiEscalation(
            isScanning: true, hasPeers: false, scanStartedAt: start,
            now: start.addingTimeInterval(14.9)))
    }

    func testWifiEscalationAtAndAfterThreshold() {
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(DeviceScannerViewModel.shouldShowWifiEscalation(
            isScanning: true, hasPeers: false, scanStartedAt: start,
            now: start.addingTimeInterval(15)))
        XCTAssertTrue(DeviceScannerViewModel.shouldShowWifiEscalation(
            isScanning: true, hasPeers: false, scanStartedAt: start,
            now: start.addingTimeInterval(300)))
    }

    func testWifiEscalationInstanceMethodReflectsState() throws {
        let vm = DeviceScannerViewModel()
        vm.startedScanning()
        let start = try XCTUnwrap(vm.scanStartedAt)
        XCTAssertFalse(vm.shouldShowWifiEscalation(now: start.addingTimeInterval(5)))
        XCTAssertTrue(vm.shouldShowWifiEscalation(now: start.addingTimeInterval(20)))

        vm.addPeer(MCPeerID(displayName: "TestDevice"))
        XCTAssertFalse(vm.shouldShowWifiEscalation(now: start.addingTimeInterval(20)))
    }

    func testWifiEscalationSuppressedAfterStopScanning() throws {
        let vm = DeviceScannerViewModel()
        vm.startedScanning()
        let start = try XCTUnwrap(vm.scanStartedAt)
        vm.stoppedScanning()
        XCTAssertFalse(vm.shouldShowWifiEscalation(now: start.addingTimeInterval(60)))
    }

    // MARK: - Connection failure

    func testConnectionFailedDropsOverlayAndShowsError() {
        let vm = DeviceScannerViewModel()
        vm.connectingToPeer()
        vm.connectionFailed()

        XCTAssertFalse(vm.isConnecting)
        XCTAssertTrue(vm.hasConnectionError)
        XCTAssertEqual(vm.statusMessage,
                       NSLocalizedString("ConnectionFailedStatus", comment: ""))
    }

    func testConnectionErrorClearedByNextAttemptAndByRescan() {
        let vm = DeviceScannerViewModel()
        vm.connectionFailed()
        vm.connectingToPeer()
        XCTAssertFalse(vm.hasConnectionError)
        XCTAssertTrue(vm.isConnecting)

        vm.connectionFailed()
        vm.startedScanning()
        XCTAssertFalse(vm.hasConnectionError)
    }

    func testConnectCancelledDropsOverlayWithoutError() {
        let vm = DeviceScannerViewModel()
        vm.connectingToPeer()
        vm.connectCancelled()

        XCTAssertFalse(vm.isConnecting)
        XCTAssertFalse(vm.hasConnectionError)
    }
}

extension DeviceScannerViewModelTests {
    /// A re-found peer (same key hash, upgraded display name — the transport's
    /// TXT enrichment replacing the AWDL placeholder) must update the stored
    /// row in place, never be dropped as a duplicate.
    func testAddPeerUpdatesDisplayNameInPlace() {
        let vm = DeviceScannerViewModel()
        let hash = Data([0x12, 0x20]) + Data(repeating: 0xAB, count: 32)
        vm.addPeer(PeerID(keyHash: hash, displayName: "Qm3f9a2c…"))
        vm.addPeer(PeerID(keyHash: hash, displayName: "Dario's iPhone"))

        XCTAssertEqual(vm.connectedPeers.count, 1)
        XCTAssertEqual(vm.connectedPeers[0].displayName, "Dario's iPhone")
    }
}
