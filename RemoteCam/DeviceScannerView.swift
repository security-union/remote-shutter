import SwiftUI
import MPCCompat
import PeerMesh

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
        }
    }

    // MARK: - Peer List

    private var peerList: some View {
        ScrollView {
            VStack(spacing: 12) {
                statusBadge
                    .padding(.top, 8)

                ForEach(viewModel.connectedPeers, id: \.self) { peer in
                    Button {
                        onSelectPeer(peer)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "iphone.radiowaves.left.and.right")
                                .font(.title3)
                                .foregroundColor(AppTheme.accent)
                                .frame(width: 40, height: 40)
                                .background(AppTheme.accentSubtle)
                                .clipShape(Circle())

                            Text(peer.displayName)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)

                            Spacer()

                            Text(NSLocalizedString("Connect", comment: ""))
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(AppTheme.accent)
                        }
                        .padding(14)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(AppTheme.glassBorder, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(GlassPressStyle())
                }

                stopScanButton
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Camera Waiting State

    private var cameraWaitingState: some View {
        ScrollView {
            VStack(spacing: 20) {
                wifiBanner
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

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
                wifiBanner
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

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

    // MARK: - Wi-Fi Guidance

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
