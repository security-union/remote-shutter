import Foundation
import MPCCompat
import PeerMesh

final class DeviceScannerViewModel: ObservableObject {

    // MARK: - Published State

    @Published var connectedPeers: [MCPeerID] = []
    @Published var isScanning: Bool = false
    @Published var hasLocalNetworkAccess: Bool = true
    @Published var hasScanningError: Bool = false
    @Published var isConnecting: Bool = false
    @Published var hasConnectionError: Bool = false

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
        if !connectedPeers.contains(peer) {
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
