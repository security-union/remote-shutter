import XCTest
import MPCCompat
import Stormo
import Network
import dnssd
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

/// The pre-scan probe may block the user on exactly one signal: the OS's own
/// permission denial. Everything a network can do wrong — no Wi-Fi, no route,
/// a browse that fails outright — proceeds, because off-network is a supported
/// configuration and scanning is the real test.
final class LocalNetworkProbeTests: XCTestCase {

    func testPolicyDeniedIsTheOnlyDenial() {
        let policyDenied = NWError.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))
        XCTAssertEqual(LocalNetworkProbe.verdict(for: .waiting(policyDenied)), .denied)
        XCTAssertEqual(LocalNetworkProbe.verdict(for: .failed(policyDenied)), .denied,
                       "denial counts however the browser surfaces it")
    }

    func testOffNetworkFailuresProceed() {
        // The report from the field: no Wi-Fi ⇒ the probe fails ⇒ the app
        // claimed the user had denied permission. A failed browse is not a
        // permission verdict.
        XCTAssertEqual(LocalNetworkProbe.verdict(for: .failed(.posix(.ENETDOWN))), .proceed)
        XCTAssertEqual(LocalNetworkProbe.verdict(for: .failed(.posix(.ENETUNREACH))), .proceed)
        XCTAssertEqual(
            LocalNetworkProbe.verdict(for: .failed(.dns(DNSServiceErrorType(kDNSServiceErr_NoRouter)))),
            .proceed)
    }

    func testWaitingWithoutDenialProceeds() {
        XCTAssertEqual(LocalNetworkProbe.verdict(for: .waiting(.posix(.ENETDOWN))), .proceed,
                       "a browser waiting for an interface has not been refused")
    }

    func testReadyProceeds() {
        XCTAssertEqual(LocalNetworkProbe.verdict(for: .ready), .proceed)
    }

    // MARK: - Multicam select-then-connect (parametrized screen behavior)

    private func makeVM(discovered: Int) -> ([MCPeerID], DeviceScannerViewModel) {
        let vm = DeviceScannerViewModel()
        vm.role = .monitor
        let peers = (0..<discovered).map { MCPeerID(displayName: "Cam\($0)") }
        peers.forEach { vm.addPeer($0) }
        return (peers, vm)
    }

    /// The core parametric sweep Dario asked for: 0…10 discovered, select
    /// 0…min(discovered,cap), and assert selecting NEVER connects, the CTA
    /// tracks the count, and Connect fires exactly the selected invites.
    func testSelectThenConnectSweep() {
        for discovered in 0...10 {
            for cap in [2, 4] {
                let (peers, vm) = makeVM(discovered: discovered)
                let selectable = min(discovered, cap)

                for k in 0...selectable {
                    vm.resetMulticamCycle()

                    // Select k rows (a) — pure, so a fresh fake transport would
                    // see zero invites; the VM itself performs no network.
                    for i in 0..<k where !vm.multicamRowLocked(peers[i], maxCameras: cap) {
                        vm.toggleMulticamSelection(peers[i])
                    }
                    XCTAssertEqual(vm.multicamSelectedPeers.count, k,
                                   "discovered=\(discovered) cap=\(cap) k=\(k)")

                    // (b) Connect CTA disabled iff k == 0; label = k.
                    XCTAssertEqual(vm.canConnectMulticam, k > 0)
                    XCTAssertEqual(vm.multicamSelectionCount, k)

                    // (c) tap Connect → exactly the k selected peers to invite.
                    let toInvite = vm.beginMulticamConnecting()
                    XCTAssertEqual(Set(toInvite), Set(peers.prefix(k)))
                    XCTAssertEqual(toInvite.count, k)
                    // No phase flag: an in-flight round is simply a non-empty
                    // connecting set, which suppresses the CTA and settles only
                    // once every invite resolves.
                    if k > 0 {
                        XCTAssertEqual(vm.multicamConnectingPeers, Set(peers.prefix(k)))
                        XCTAssertFalse(vm.canConnectMulticam)
                        XCTAssertFalse(vm.multicamConnectSettled)
                    }
                }
            }
        }
    }

    /// (d) Rows transition selected → connecting → connected, and the handoff
    /// decision matches the connected count.
    func testConnectingTransitionsAndHandoffDestination() {
        for connectCount in 0...4 {
            let (peers, vm) = makeVM(discovered: 4)
            let selected = Array(peers.prefix(max(connectCount, 1)))
            selected.forEach { vm.toggleMulticamSelection($0) }
            let toInvite = vm.beginMulticamConnecting()

            // All selected are "connecting" right after Connect.
            for p in toInvite { XCTAssertEqual(vm.multicamRowState(p), .connecting) }

            // The first `connectCount` connect; the rest fail.
            let connected = Array(selected.prefix(connectCount))
            vm.reconcileMulticamConnected(connected)
            for p in selected where !connected.contains(p) { vm.markMulticamFailed(p) }

            for p in connected { XCTAssertEqual(vm.multicamRowState(p), .connected) }
            XCTAssertTrue(vm.multicamConnectSettled)

            switch MulticamHandoff.decide(connected: connected) {
            case .none: XCTAssertEqual(connectCount, 0)
            case .classicMonitor(let p): XCTAssertEqual(connectCount, 1); XCTAssertEqual(p, connected[0])
            case .director(let ps): XCTAssertGreaterThanOrEqual(connectCount, 2); XCTAssertEqual(ps, connected)
            }
        }
    }

    /// Cap: with 10 discovered you can select up to `cap`; the (cap+1)th row
    /// locks, and Select All stops at the cap.
    func testCapLocksBeyondMaxCameras() {
        for cap in [2, 4] {
            let (peers, vm) = makeVM(discovered: 10)
            for i in 0..<cap { vm.toggleMulticamSelection(peers[i]) }
            XCTAssertEqual(vm.multicamSelectedPeers.count, cap)
            // Every remaining row is locked (the host routes a tap to the
            // paywall instead of selecting).
            for i in cap..<10 {
                XCTAssertTrue(vm.multicamRowLocked(peers[i], maxCameras: cap),
                              "row \(i) must lock at cap \(cap)")
            }
            // An already-selected row is never locked (it can still deselect).
            XCTAssertFalse(vm.multicamRowLocked(peers[0], maxCameras: cap))

            // Select All also stops exactly at the cap.
            let (peers2, vm2) = makeVM(discovered: 10)
            vm2.selectAllMulticam(maxCameras: cap)
            XCTAssertEqual(vm2.multicamSelectedPeers.count, cap)
            XCTAssertEqual(Set(vm2.multicamSelectedPeers), Set(peers2.prefix(cap)))
        }
    }

    /// Empty state: nothing discovered → no Select All, CTA disabled.
    func testEmptyStateHasNoSelectAllAndDisabledConnect() {
        let (_, vm) = makeVM(discovered: 0)
        XCTAssertFalse(vm.showsMulticamSelectAll)
        XCTAssertFalse(vm.canConnectMulticam)
        XCTAssertEqual(vm.multicamSelectionCount, 0)
    }

    /// Partial: 3 selected, 1 never connects → settles with 2 connected, the
    /// straggler marked failed.
    func testPartialConnectMarksFailedAndSettles() {
        let (peers, vm) = makeVM(discovered: 3)
        peers.forEach { vm.toggleMulticamSelection($0) }
        _ = vm.beginMulticamConnecting()

        vm.reconcileMulticamConnected([peers[0], peers[1]])
        XCTAssertFalse(vm.multicamConnectSettled, "one invite still outstanding")

        vm.markMulticamFailed(peers[2])
        XCTAssertTrue(vm.multicamConnectSettled)
        XCTAssertEqual(vm.multicamRowState(peers[2]), .failed)
        XCTAssertEqual(vm.multicamConnectedPeers.count, 2)
        XCTAssertEqual(MulticamHandoff.decide(
            connected: peers.filter { vm.multicamConnectedPeers.contains($0) }),
            .director([peers[0], peers[1]]))
    }

    func testSelectingNeverEntersConnectingWithoutConnectTap() {
        let (peers, vm) = makeVM(discovered: 3)
        peers.forEach { vm.toggleMulticamSelection($0) }
        // Selection only — nothing in flight, no connect requested.
        XCTAssertTrue(vm.multicamConnectingPeers.isEmpty)
        XCTAssertFalse(vm.multicamConnectRequested)
        XCTAssertTrue(vm.canConnectMulticam)
    }

    // MARK: - Back-navigation re-entry (Dario's repro)

    /// The exact reported bug: pair a single camera, hand off to the classic
    /// monitor, navigate back, and the scanner must be usable again — CTA
    /// visible with the right count, rows selectable, a second connect works.
    /// Parametrized over how many cameras the first cycle connected (1 = classic
    /// monitor, ≥2 = director) and whether the link survived the detour.
    func testSecondCycleAfterBackNavigationIsUsable() {
        for firstConnected in 1...4 {
            for linkSurvived in [true, false] {
                let (peers, vm) = makeVM(discovered: 4)
                let first = Array(peers.prefix(firstConnected))

                // Cycle 1: select, connect, all establish, handoff would fire.
                first.forEach { vm.toggleMulticamSelection($0) }
                _ = vm.beginMulticamConnecting()
                vm.reconcileMulticamConnected(first)
                XCTAssertTrue(vm.multicamConnectSettled,
                              "cycle 1 settles (firstConnected=\(firstConnected))")

                // Back-navigation re-arm: the coordinator reports the current
                // live set (all survived, or none), then the cycle resets.
                vm.reconcileMulticamConnected(linkSurvived ? first : [])
                vm.resetMulticamCycle()

                // The frozen-CTA bug: nothing must be latched from cycle 1.
                XCTAssertTrue(vm.multicamConnectingPeers.isEmpty)
                XCTAssertFalse(vm.multicamConnectRequested)
                XCTAssertTrue(vm.multicamFailedPeers.isEmpty)

                if linkSurvived {
                    // Still-connected re-entry: the survivors are reseeded as
                    // selected+checked and the CTA is immediately actionable.
                    XCTAssertEqual(vm.multicamSelectedPeers, Set(first))
                    XCTAssertTrue(vm.canConnectMulticam)
                    for p in first { XCTAssertEqual(vm.multicamRowState(p), .connected) }
                    // A second connect on live links invites nobody and settles.
                    let toInvite = vm.beginMulticamConnecting()
                    XCTAssertTrue(toInvite.isEmpty, "live links are not re-invited")
                    XCTAssertTrue(vm.multicamConnectSettled)
                } else {
                    // Dropped-link re-entry: clean slate, re-select and go.
                    XCTAssertTrue(vm.multicamSelectedPeers.isEmpty)
                    XCTAssertFalse(vm.canConnectMulticam, "nothing selected yet")
                    vm.toggleMulticamSelection(peers[0])
                    XCTAssertTrue(vm.canConnectMulticam, "CTA returns after re-select")
                    XCTAssertEqual(vm.beginMulticamConnecting(), [peers[0]],
                                   "a dropped peer is invited afresh")
                }
            }
        }
    }

    func testStatesWithNoEvidenceKeepWaiting() {
        XCTAssertEqual(LocalNetworkProbe.verdict(for: .setup), .keepWaiting)
        XCTAssertEqual(LocalNetworkProbe.verdict(for: .cancelled), .keepWaiting)
    }
}
