import XCTest
import MultipeerConnectivity
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

    func testStatusMessageScanning() {
        let vm = DeviceScannerViewModel()
        vm.startedScanning()

        XCTAssertEqual(
            vm.statusMessage,
            NSLocalizedString("SEARCHING FOR NEARBY DEVICES...", comment: "")
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

    // MARK: - VC Bridge Tests

    func testVCBridgeConnectedPeersGetter() {
        let vm = DeviceScannerViewModel()
        let peer = MCPeerID(displayName: "Test")
        vm.addPeer(peer)

        // Simulate what the VC computed property does
        let fromVM: [MCPeerID] = vm.connectedPeers
        XCTAssertEqual(fromVM.count, 1)
        XCTAssertEqual(fromVM.first?.displayName, "Test")
    }

    func testVCBridgeConnectedPeersSetter() {
        let vm = DeviceScannerViewModel()
        let peer = MCPeerID(displayName: "Test")

        // Simulate the VC setter: scannerViewModel.connectedPeers = newValue
        vm.connectedPeers = [peer]
        XCTAssertEqual(vm.connectedPeers.count, 1)
        XCTAssertTrue(vm.hasPeers)
    }

    func testVCBridgeIsScanningBidirectional() {
        let vm = DeviceScannerViewModel()

        // Through ViewModel method
        vm.startedScanning()
        XCTAssertTrue(vm.isScanning)

        // Direct property set (simulating VC setter)
        vm.isScanning = false
        XCTAssertFalse(vm.isScanning)
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
}
