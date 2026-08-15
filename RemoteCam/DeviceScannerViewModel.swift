import Foundation
import MPCCompat
import Stormo
import Network
import dnssd

/// Where a settled multicam connect hands off to, decided purely by how many
/// cameras actually connected: none → stay (error), one → the classic 1:1
/// monitor (unchanged), two or more → the director screen.
enum MulticamHandoff: Equatable {
    case none
    case classicMonitor(MCPeerID)
    case director([MCPeerID])

    static func decide(connected: [MCPeerID]) -> MulticamHandoff {
        switch connected.count {
        case 0: return .none
        case 1: return .classicMonitor(connected[0])
        default: return .director(connected)
        }
    }
}

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
    // MARK: - Multicam director: select-then-connect

    /// The multicam scanner is an edit-mode selector: pick cameras (pure, zero
    /// network), THEN connect the chosen set. Selecting never invites. Row
    /// states and the CTA derive from the four fact sets below; nothing is
    /// latched across cycles.

    /// Cameras the user has picked (client-side only, no transport activity).
    @Published var multicamSelectedPeers: Set<MCPeerID> = []
    /// Selected cameras whose invite is in flight right now.
    @Published var multicamConnectingPeers: Set<MCPeerID> = []
    /// Cameras whose invite failed (timed out after the retry) this cycle.
    @Published var multicamFailedPeers: Set<MCPeerID> = []
    /// Peers that currently hold a live link, as reported by the coordinator.
    @Published var multicamLiveLinks: Set<MCPeerID> = []
    /// Set when the user taps Connect this cycle; cleared when the round
    /// settles into a handoff or the cycle resets.
    private(set) var multicamConnectRequested = false

    /// Pure selection toggle — no invite, no coordinator message. Blocked only
    /// while invites are actually in flight.
    func toggleMulticamSelection(_ peer: MCPeerID) {
        guard multicamConnectingPeers.isEmpty else { return }
        if multicamSelectedPeers.contains(peer) {
            multicamSelectedPeers.remove(peer)
        } else {
            multicamSelectedPeers.insert(peer)
        }
    }

    /// Select every discovered, not-yet-selected camera up to the cap (pure).
    func selectAllMulticam(maxCameras: Int) {
        guard multicamConnectingPeers.isEmpty else { return }
        for peer in connectedPeers where !multicamSelectedPeers.contains(peer) {
            guard multicamSelectedPeers.count < maxCameras else { break }
            multicamSelectedPeers.insert(peer)
        }
    }

    /// The "Connect (N)" CTA: shown whenever cameras are selected and no invite
    /// round is in flight.
    var canConnectMulticam: Bool {
        !multicamSelectedPeers.isEmpty && multicamConnectingPeers.isEmpty
    }
    var multicamSelectionCount: Int { multicamSelectedPeers.count }

    /// Begin a connect round. Returns only the selected peers that need an
    /// invite — a peer whose link already survived (still-connected re-entry)
    /// is left alone, never re-invited. If every selected peer is already live,
    /// nothing is returned and `multicamConnectSettled` is already true.
    func beginMulticamConnecting() -> [MCPeerID] {
        guard !multicamSelectedPeers.isEmpty else { return [] }
        multicamConnectRequested = true
        multicamFailedPeers = []
        multicamConnectingPeers = multicamSelectedPeers.subtracting(multicamLiveLinks)
        return connectedPeers.filter { multicamConnectingPeers.contains($0) }
    }

    /// Reconcile the set of established cameras (the coordinator's live links).
    func reconcileMulticamConnected(_ peers: [MCPeerID]) {
        multicamLiveLinks = Set(peers)
        multicamConnectingPeers.subtract(multicamLiveLinks)
    }

    /// One camera's invite failed for good.
    func markMulticamFailed(_ peer: MCPeerID) {
        multicamConnectingPeers.remove(peer)
        if !multicamLiveLinks.contains(peer) { multicamFailedPeers.insert(peer) }
    }

    /// The connect round is over once the user asked to connect and no invite
    /// is still outstanding.
    var multicamConnectSettled: Bool {
        multicamConnectRequested && multicamConnectingPeers.isEmpty
    }

    /// The selected cameras that actually connected — the input to the handoff
    /// decision.
    var multicamConnectedPeers: Set<MCPeerID> {
        multicamSelectedPeers.intersection(multicamLiveLinks)
    }

    /// Reset the connect-round bookkeeping on scanner (re)entry WITHOUT
    /// tearing down live links: a peer whose link survived is reseeded as
    /// selected + checked, so starting again is one tap.
    func resetMulticamCycle() {
        multicamConnectRequested = false
        multicamConnectingPeers = []
        multicamFailedPeers = []
        multicamSelectedPeers = multicamLiveLinks
    }

    /// Row state for the edit-mode circle. Empty/filled while selecting;
    /// spinner while its invite is in flight; check once its link is live.
    enum MulticamRowState { case unselected, selected, connecting, connected, failed }
    func multicamRowState(_ peer: MCPeerID) -> MulticamRowState {
        if multicamFailedPeers.contains(peer) { return .failed }
        if multicamConnectingPeers.contains(peer) { return .connecting }
        if multicamLiveLinks.contains(peer) { return .connected }
        if multicamSelectedPeers.contains(peer) { return .selected }
        return .unselected
    }

    /// An unselected row is locked (→ paywall) when the cap is already met and
    /// no invite round is in flight.
    func multicamRowLocked(_ peer: MCPeerID, maxCameras: Int) -> Bool {
        multicamConnectingPeers.isEmpty
            && multicamRowState(peer) == .unselected
            && multicamSelectedPeers.count >= maxCameras
    }

    /// Whether "Select All" should be offered — some discovered camera is still
    /// unselected, and no invite round is in flight.
    var showsMulticamSelectAll: Bool {
        multicamConnectingPeers.isEmpty
            && connectedPeers.contains { !multicamSelectedPeers.contains($0) }
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
