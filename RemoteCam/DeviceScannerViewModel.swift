import Foundation
import MPCCompat
import Stormo
import Network
import dnssd

/// Classifies the pre-scan local-network probe: one browse whose only job is
/// to learn whether the user denied Local Network permission, so the app can
/// route them to Settings instead of scanning into silence.
///
/// The only state that may read as denial is the OS's own denial code,
/// `kDNSServiceErr_PolicyDenied`. Every other outcome — including outright
/// browse failure — proceeds: a probe can fail because there is no Wi-Fi
/// network, and off-network is a configuration this app supports (peer-to-peer
/// Wi-Fi needs no router). Scanning itself is the real test, and the transport
/// reports its own failures through its own path.
enum LocalNetworkProbe {

    enum Verdict: Equatable {
        /// `kDNSServiceErr_PolicyDenied`: the user said no. Only Settings fixes it.
        case denied
        /// Permission is not the problem — start scanning.
        case proceed
        /// No evidence yet; let the probe keep listening.
        case keepWaiting
    }

    static func verdict(for state: NWBrowser.State) -> Verdict {
        switch state {
        case .waiting(let error), .failed(let error):
            if case .dns(let dnsError) = error,
               Int(dnsError) == Int(kDNSServiceErr_PolicyDenied) {
                return .denied
            }
            return .proceed
        case .ready:
            return .proceed
        case .setup, .cancelled:
            return .keepWaiting
        @unknown default:
            return .keepWaiting
        }
    }
}

final class DeviceScannerViewModel: ObservableObject {

    // MARK: - Published State

    @Published var connectedPeers: [MCPeerID] = []
    @Published var isScanning: Bool = false
    @Published var hasLocalNetworkAccess: Bool = true
    @Published var hasScanningError: Bool = false
    @Published var isConnecting: Bool = false
    @Published var hasConnectionError: Bool = false
    /// Multicam director collecting: how many cameras are connected so far.
    /// Drives the "Start (N)" affordance; stays 0 in the single-camera build.
    @Published var multicamCollectedCount: Int = 0
    /// The cameras currently in the rig (selected), for the per-row checkmark.
    @Published var multicamSelectedPeers: Set<MCPeerID> = []
    /// Cameras whose invite is in flight, for the per-row spinner (a set so
    /// "Connect All" can show several at once).
    @Published var multicamConnectingPeers: Set<MCPeerID> = []

    /// Reconcile the multicam selection from the coordinator's effective set:
    /// updates the checkmarks and count, and clears the spinner for any camera
    /// that has now joined.
    func updateMulticamSelection(_ peers: [MCPeerID]) {
        multicamSelectedPeers = Set(peers)
        multicamCollectedCount = peers.count
        multicamConnectingPeers.subtract(multicamSelectedPeers)
    }

    /// Row selection state for the edit-mode circle.
    enum MulticamRowState { case unselected, connecting, selected }
    func multicamRowState(_ peer: MCPeerID) -> MulticamRowState {
        if multicamSelectedPeers.contains(peer) { return .selected }
        if multicamConnectingPeers.contains(peer) { return .connecting }
        return .unselected
    }

    /// The discovered cameras "Connect All" should invite: every unselected
    /// one, in list order, up to the remaining room under `maxCameras` (already
    /// selected and in-flight cameras count against it).
    func peersToConnectAll(maxCameras: Int) -> [MCPeerID] {
        var pending = multicamSelectedPeers.count + multicamConnectingPeers.count
        var result: [MCPeerID] = []
        for peer in connectedPeers where multicamRowState(peer) == .unselected {
            guard pending < maxCameras else { break }
            result.append(peer)
            pending += 1
        }
        return result
    }

    /// When the current scan began. Not @Published: the view samples it on a
    /// TimelineView clock, so publishing would only cause redundant redraws.
    private(set) var scanStartedAt: Date?

    // MARK: - Role

    var role: DeviceRole = .monitor

    // MARK: - UserDefaults

    private let speedRunScanningKey = userDefaultsSpeedRunScanning

    var speedRunScanning: Bool {
        get { UserDefaults.standard.bool(forKey: speedRunScanningKey) }
        set { UserDefaults.standard.set(newValue, forKey: speedRunScanningKey) }
    }

    // MARK: - Computed

    var statusMessage: String {
        if hasConnectionError {
            return NSLocalizedString("ConnectionFailedStatus", comment: "Shown after a connection attempt (with retry) fails")
        } else if hasScanningError {
            return NSLocalizedString("SCANNING ERROR - CHECK NETWORK SETTINGS", comment: "")
        } else if isScanning {
            return role == .camera
                ? NSLocalizedString("WAITING FOR A REMOTE TO CONNECT...", comment: "")
                : NSLocalizedString("SEARCHING FOR NEARBY CAMERAS...", comment: "")
        } else {
            return NSLocalizedString("TAP THE BUTTON TO GET STARTED", comment: "")
        }
    }

    var hasPeers: Bool { !connectedPeers.isEmpty }

    // MARK: - Peer Management

    func addPeer(_ peer: MCPeerID) {
        // A re-found peer compares equal (identity is key-hash-only) but may
        // carry an upgraded display name — the transport re-delivers when TXT
        // enrichment replaces the AWDL placeholder. Update in place; dropping
        // would freeze the hash-prefix name in the UI.
        if let index = connectedPeers.firstIndex(of: peer) {
            connectedPeers[index] = peer
        } else {
            connectedPeers.append(peer)
        }
        speedRunScanning = true
    }

    func removePeer(_ peer: MCPeerID) {
        connectedPeers.removeAll { $0 == peer }
    }

    func clearPeers() {
        connectedPeers.removeAll()
    }

    func startedScanning() {
        connectedPeers.removeAll()
        isScanning = true
        hasScanningError = false
        isConnecting = false
        hasConnectionError = false
        scanStartedAt = Date()
    }

    func stoppedScanning() {
        isScanning = false
        isConnecting = false
        hasConnectionError = false
        scanStartedAt = nil
    }

    func scanningFailed() {
        speedRunScanning = false
        hasScanningError = true
        isScanning = false
        isConnecting = false
        scanStartedAt = nil
    }

    // MARK: - Wi-Fi Escalation

    /// Whether to show the "still searching — check Wi-Fi" tip. Pure function
    /// of state + clock: no stored flag or timer exists to go stale.
    static func shouldShowWifiEscalation(isScanning: Bool,
                                         hasPeers: Bool,
                                         scanStartedAt: Date?,
                                         now: Date) -> Bool {
        guard isScanning, !hasPeers, let start = scanStartedAt else { return false }
        return now.timeIntervalSince(start) >= 15
    }

    func shouldShowWifiEscalation(now: Date) -> Bool {
        Self.shouldShowWifiEscalation(isScanning: isScanning,
                                      hasPeers: hasPeers,
                                      scanStartedAt: scanStartedAt,
                                      now: now)
    }

    func networkAccessDenied() {
        speedRunScanning = false
        hasLocalNetworkAccess = false
        hasScanningError = true
    }

    func networkAccessGranted() {
        hasLocalNetworkAccess = true
        hasScanningError = false
    }

    func connectingToPeer() {
        isConnecting = true
        hasConnectionError = false
    }

    func connectedToPeer() {
        isConnecting = false
    }

    func connectionFailed() {
        isConnecting = false
        hasConnectionError = true
    }

    func connectCancelled() {
        isConnecting = false
    }
}
