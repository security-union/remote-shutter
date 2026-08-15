import SwiftUI
import MPCCompat
import Stormo

private let qrCodeImage: UIImage? = generateQRCode(remoteShutterUrl)

struct DeviceScannerView: View {
    @ObservedObject var viewModel: DeviceScannerViewModel

    let onStartScanning: () -> Void
    let onStopScanning: () -> Void
    let onSelectPeer: (MCPeerID) -> Void
    let onCancelConnect: () -> Void
    let onShareApp: () -> Void
    let onOpenSettings: () -> Void
    let onHelp: () -> Void
    /// Multicam only: select every discovered camera up to the tier cap (pure).
    var onSelectAll: (() -> Void)? = nil
    /// Multicam only: connect the selected cameras (the bottom CTA).
    var onConnectSelected: (() -> Void)? = nil

    /// The scanner is in multicam edit-mode selection (monitor role, flag on).
    private var isMulticamScanner: Bool {
        FeatureFlags.ENABLE_MULTICAM && viewModel.role == .monitor
    }

    /// Peer-link state; the reconnect overlay is a function of it.
    @ObservedObject var peerLink: PeerLinkStatus = .shared

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient

            if viewModel.role == .camera {
                cameraWaitingState
            } else if viewModel.hasPeers {
                peerList
            } else {
                emptyState
            }

            if viewModel.isConnecting {
                connectingOverlay
            }

            if isMulticamScanner, let onConnectSelected {
                connectSelectedButton(onConnectSelected)
                    .animation(.spring(response: 0.32, dampingFraction: 0.85),
                               value: viewModel.multicamConnectingPeers.isEmpty)
            }

            PeerLinkOverlay(status: peerLink)
        }
    }

    /// The bottom "Connect (N)" CTA: fires the invites for the selected set.
    /// Disabled at N = 0; hidden only while invites are in flight.
    @ViewBuilder
    private func connectSelectedButton(_ action: @escaping () -> Void) -> some View {
        if viewModel.multicamConnectingPeers.isEmpty {
            VStack {
                Spacer()
                Button(action: action) {
                    Text(String(format: NSLocalizedString("Connect (%d)", comment: "connect N selected cameras"),
                                viewModel.multicamSelectionCount))
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(viewModel.canConnectMulticam ? AppTheme.accent : Color.gray)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!viewModel.canConnectMulticam)
                .animation(.easeInOut(duration: 0.15), value: viewModel.canConnectMulticam)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Peer List

    private var peerList: some View {
        ScrollView {
            VStack(spacing: 12) {
                statusBadge
                    .padding(.top, 8)

                if isMulticamScanner && viewModel.showsMulticamSelectAll {
                    selectAllRow
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                }

                ForEach(viewModel.connectedPeers, id: \.self) { peer in
                    Button {
                        onSelectPeer(peer)
                    } label: {
                        peerRow(peer)
                    }
                    .buttonStyle(GlassPressStyle())
                }

                stopScanButton
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, isMulticamScanner ? 100 : 40) // room for Connect (N)
            .animation(.spring(response: 0.32, dampingFraction: 0.85),
                       value: viewModel.showsMulticamSelectAll)
        }
    }

    /// One discovered-camera row. In multicam it carries a leading selection
    /// circle (Apple edit-mode idiom); otherwise it keeps the classic
    /// icon + "Connect" affordance.
    private func peerRow(_ peer: MCPeerID) -> some View {
        HStack(spacing: 14) {
            if isMulticamScanner {
                multicamSelectionCircle(peer)
            } else {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.title3)
                    .foregroundColor(AppTheme.accent)
                    .frame(width: 40, height: 40)
                    .background(AppTheme.accentSubtle)
                    .clipShape(Circle())
            }

            Text(peer.displayName)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.primary)

            Spacer()

            peerRowTrailing(peer)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(rowBorderColor(peer), lineWidth: rowBorderWidth(peer))
        )
    }

    /// The edit-mode leading circle. Selecting: empty ↔ filled check. Connecting
    /// phase adds spinner (in flight), filled check (connected), warning (failed).
    @ViewBuilder
    private func multicamSelectionCircle(_ peer: MCPeerID) -> some View {
        switch viewModel.multicamRowState(peer) {
        case .selected, .connected:
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(AppTheme.accent)
                .frame(width: 40, height: 40)
        case .connecting:
            ProgressView()
                .frame(width: 40, height: 40)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundColor(.orange)
                .frame(width: 40, height: 40)
        case .unselected:
            Image(systemName: "circle")
                .font(.title2)
                .foregroundColor(.secondary)
                .frame(width: 40, height: 40)
        }
    }

    @ViewBuilder
    private func peerRowTrailing(_ peer: MCPeerID) -> some View {
        if isMulticamScanner {
            // While selecting, an over-cap unselected row shows a lock; tapping
            // it opens the paywall (handled by the host).
            if viewModel.multicamRowLocked(peer, maxCameras: StoreManager.shared.maxCameras()) {
                Image(systemName: "lock.fill")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        } else {
            Text(NSLocalizedString("Connect", comment: ""))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(AppTheme.accent)
        }
    }

    private func rowBorderColor(_ peer: MCPeerID) -> Color {
        guard isMulticamScanner else { return AppTheme.glassBorder }
        switch viewModel.multicamRowState(peer) {
        case .selected, .connected, .connecting: return AppTheme.accent
        default: return AppTheme.glassBorder
        }
    }

    private func rowBorderWidth(_ peer: MCPeerID) -> CGFloat {
        guard isMulticamScanner else { return 0.5 }
        switch viewModel.multicamRowState(peer) {
        case .selected, .connected, .connecting: return 2
        default: return 0.5
        }
    }

    /// "Select All" — picks every discovered, not-yet-selected camera up to the
    /// cap (pure). Offered only while selecting and something is unselected.
    @ViewBuilder
    private var selectAllRow: some View {
        Button {
            onSelectAll?()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .font(.title3)
                Text(NSLocalizedString("Select All", comment: "select every discovered camera"))
                    .fontWeight(.semibold)
                Spacer()
            }
            .foregroundColor(AppTheme.accent)
            .padding(14)
            .background(AppTheme.accentSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(GlassPressStyle())
    }

    // MARK: - Camera Waiting State

    private var cameraWaitingState: some View {
        ScrollView {
            VStack(spacing: 20) {
                connectivityBanners

                // Camera icon
                ZStack {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.12))
                        .frame(width: 100, height: 100)

                    Circle()
                        .strokeBorder(AppTheme.accent.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 100, height: 100)

                    Image(systemName: "camera.fill")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundColor(AppTheme.accent)
                }
                .padding(.top, 24)

                VStack(spacing: 8) {
                    Text(NSLocalizedString("Camera Mode", comment: ""))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Text(NSLocalizedString("On another device, open Remote Shutter and select Remote. This camera will appear in their device list.", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)

                // Status
                statusArea

                // Actions
                VStack(spacing: 12) {
                    if !viewModel.hasLocalNetworkAccess {
                        settingsButton
                    } else if viewModel.isScanning {
                        cameraAdvertisingIndicator
                        goOfflineButton
                    } else {
                        goOnlineButton
                    }

                    shareButton
                }
                .padding(.horizontal, 20)

                // QR code + tip
                qrCodeSection
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 20) {
                connectivityBanners

                // Remote icon
                ZStack {
                    Circle()
                        .fill(AppTheme.secondary.opacity(0.12))
                        .frame(width: 100, height: 100)

                    Circle()
                        .strokeBorder(AppTheme.secondary.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 100, height: 100)

                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundColor(AppTheme.secondary)
                }
                .padding(.top, 24)

                VStack(spacing: 8) {
                    Text(NSLocalizedString("Remote Mode", comment: ""))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Text(NSLocalizedString("You need at least 2 devices running Remote Shutter", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)

                // Status
                statusArea

                // Actions
                VStack(spacing: 12) {
                    if !viewModel.hasLocalNetworkAccess {
                        settingsButton
                    } else if viewModel.isScanning {
                        scanningIndicator
                        stopScanButton
                    } else {
                        startScanButton
                    }

                    shareButton
                }
                .padding(.horizontal, 20)

                // QR code + tip
                qrCodeSection
            }
        }
    }

    // MARK: - QR Code Section

    private var qrCodeSection: some View {
        VStack(spacing: 12) {
            if let qrImage = qrCodeImage {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(AppTheme.glassBorder, lineWidth: 0.5)
                    )
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "qrcode")
                    .font(.caption)
                    .foregroundColor(AppTheme.accent)
                    .padding(.top, 2)
                Text(NSLocalizedString("Scan the QR code on another device to download Remote Shutter", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
    }

    // MARK: - Guidance Banners

    /// The two pairing prerequisites, stacked tight so they read as one block:
    /// Wi-Fi on, and every device on the current version.
    private var connectivityBanners: some View {
        VStack(spacing: 10) {
            wifiBanner
            transportBanner
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var wifiBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wifi")
                .font(.title3.weight(.semibold))
                .foregroundColor(AppTheme.accent)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("WifiBannerTitle", comment: "Wi-Fi required banner title"))
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                Text(NSLocalizedString("WifiBannerBody", comment: "Wi-Fi required banner body"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(AppTheme.accentSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppTheme.accent.opacity(0.4), lineWidth: 1)
        )
    }

    /// Release notice for the Stormo transport swap: the upgrade only lands when
    /// both devices run the current version, so it sits on both scanning screens
    /// right under the Wi-Fi banner. Framed as the win it is, with the
    /// requirement attached.
    private var transportBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            transportLogo

            VStack(alignment: .leading, spacing: 5) {
                // Badge pinned to the trailing edge so a wrapping title can't
                // strand it mid-paragraph.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(NSLocalizedString("TransportBannerTitle",
                                           comment: "Stormo transport upgrade banner title"))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Spacer(minLength: 4)

                    Text(NSLocalizedString("TransportBannerBadge",
                                           comment: "Short 'new' tag on the transport upgrade banner"))
                        .font(.caption2)
                        .fontWeight(.heavy)
                        .foregroundColor(AppTheme.secondary)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(AppTheme.secondarySubtle)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(AppTheme.secondary.opacity(0.45), lineWidth: 0.5)
                        )
                }

                Text(NSLocalizedString("TransportBannerBody",
                                       comment: "Stormo transport upgrade banner body"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                transportSpecs
                    .padding(.top, 1)

                Text(NSLocalizedString("TransportBannerAction",
                                       comment: "Call to action: update every device"))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.secondary)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppTheme.secondary.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: AppTheme.secondary.opacity(0.12), radius: 8, y: 3)
    }

    /// Spec chips — the part that reads as engineering rather than marketing.
    /// `QUIC` and `TLS 1.3` are a protocol name and a version: never localized,
    /// so they stay recognizable in every storefront.
    private var transportSpecs: some View {
        HStack(spacing: 6) {
            specChip(icon: "bolt.fill", label: "QUIC")
            specChip(icon: "lock.fill", label: "TLS 1.3")
            specChip(icon: "arrow.triangle.2.circlepath",
                     label: NSLocalizedString("TransportBannerChipReconnect",
                                              comment: "Spec chip: the link recovers by itself"))
        }
    }

    private func specChip(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundColor(AppTheme.secondary)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(AppTheme.secondarySubtle)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(AppTheme.secondary.opacity(0.3), lineWidth: 0.5)
        )
    }

    /// Reserved 40×40 slot for the transport wordmark. Drop artwork into
    /// `StormoLogo` in Media.xcassets and it replaces the placeholder glyph
    /// without touching the layout.
    private var transportLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.secondarySubtle)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.secondary.opacity(0.3), lineWidth: 0.5)

            if let logo = UIImage(named: "StormoLogo") {
                Image(uiImage: logo)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(6)
            } else {
                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppTheme.secondary)
            }
        }
        .frame(width: 40, height: 40)
    }

    /// Status badge plus the time-based "check Wi-Fi" tip. TimelineView
    /// supplies the clock; visibility is recomputed from state every second,
    /// so there is no timer to cancel and no flag to go stale. Only the tip
    /// lives inside the TimelineView — the badge doesn't depend on the clock
    /// and re-rendering it each tick would reset its ProgressView animation.
    private var statusArea: some View {
        VStack(spacing: 10) {
            statusBadge
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if viewModel.shouldShowWifiEscalation(now: context.date) {
                    wifiEscalationTip
                }
            }
        }
    }

    private var wifiEscalationTip: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.orange)
                .padding(.top, 2)
            Text(NSLocalizedString("WifiEscalationTip", comment: "Shown after 15s of scanning without finding a peer"))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.orange)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.5)
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Components

    private var statusBadge: some View {
        HStack(spacing: 8) {
            if viewModel.hasScanningError || viewModel.hasConnectionError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else if viewModel.isScanning {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
            }
            Text(viewModel.statusMessage)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(viewModel.hasScanningError || viewModel.hasConnectionError
                                 ? .orange : .secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 14)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(AppTheme.glassBorder, lineWidth: 0.5)
        )
    }

    private var startScanButton: some View {
        Button(action: onStartScanning) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                Text(NSLocalizedString("Start Scanning", comment: ""))
                    .font(.headline)
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                LinearGradient(
                    colors: [AppTheme.accent, AppTheme.accentLight],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: AppTheme.accent.opacity(0.3), radius: 8, y: 4)
        }
    }

    private var stopScanButton: some View {
        Button(action: onStopScanning) {
            HStack {
                Image(systemName: "stop.fill")
                    .font(.subheadline)
                Text(NSLocalizedString("Stop Scanning", comment: ""))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var scanningIndicator: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(NSLocalizedString("Scanning for nearby cameras...", comment: ""))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 54)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppTheme.glassBorder, lineWidth: 0.5)
        )
    }

    private var cameraAdvertisingIndicator: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(NSLocalizedString("Waiting for a remote to connect...", comment: ""))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 54)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppTheme.glassBorder, lineWidth: 0.5)
        )
    }

    private var goOnlineButton: some View {
        Button(action: onStartScanning) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                Text(NSLocalizedString("Go Online", comment: ""))
                    .font(.headline)
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                LinearGradient(
                    colors: [AppTheme.accent, AppTheme.accentLight],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: AppTheme.accent.opacity(0.3), radius: 8, y: 4)
        }
    }

    private var goOfflineButton: some View {
        Button(action: onStopScanning) {
            HStack {
                Image(systemName: "stop.fill")
                    .font(.subheadline)
                Text(NSLocalizedString("Go Offline", comment: ""))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var settingsButton: some View {
        Button(action: onOpenSettings) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.headline)
                Text(NSLocalizedString("Open Settings", comment: ""))
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.gray)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var shareButton: some View {
        Button(action: onShareApp) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline)
                Text(NSLocalizedString("Share App Link", comment: ""))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(AppTheme.accent)
        }
        .padding(.top, 4)
    }

    private var connectingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text(NSLocalizedString("Connecting...", comment: ""))
                    .font(.headline)
                    .foregroundColor(.white)
                Text(NSLocalizedString("ConnectingHint", comment: "Shown under the connecting spinner"))
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onCancelConnect) {
                    Text(NSLocalizedString("connect_cancel", comment: "Cancel the connection attempt"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 24)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding(32)
            .frame(maxWidth: 320)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }
}

// MARK: - Press Style

private struct GlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Preview

struct DeviceScannerView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            DeviceScannerView(
                viewModel: DeviceScannerViewModel(),
                onStartScanning: {},
                onStopScanning: {},
                onSelectPeer: { _ in },
                onCancelConnect: {},
                onShareApp: {},
                onOpenSettings: {},
                onHelp: {}
            )
            .navigationTitle(NSLocalizedString("Scan for devices", comment: ""))
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
