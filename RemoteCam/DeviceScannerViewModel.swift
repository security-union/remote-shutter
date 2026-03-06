import Foundation
import MultipeerConnectivity

final class DeviceScannerViewModel: ObservableObject {

    // MARK: - Published State

    @Published var connectedPeers: [MCPeerID] = []
    @Published var isScanning: Bool = false
    @Published var hasLocalNetworkAccess: Bool = true
    @Published var hasScanningError: Bool = false
    @Published var isConnecting: Bool = false

    // MARK: - UserDefaults

    private let speedRunScanningKey = userDefaultsSpeedRunScanning

    var speedRunScanning: Bool {
        get { UserDefaults.standard.bool(forKey: speedRunScanningKey) }
        set { UserDefaults.standard.set(newValue, forKey: speedRunScanningKey) }
    }

    // MARK: - Computed

    var statusMessage: String {
        if hasScanningError {
            return NSLocalizedString("SCANNING ERROR - CHECK NETWORK SETTINGS", comment: "")
        } else if isScanning {
            return NSLocalizedString("SEARCHING FOR NEARBY DEVICES...", comment: "")
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
    }

    func stoppedScanning() {
        isScanning = false
        isConnecting = false
    }

    func scanningFailed() {
        speedRunScanning = false
        hasScanningError = true
        isScanning = false
        isConnecting = false
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
    }

    func connectedToPeer() {
        isConnecting = false
    }
}
