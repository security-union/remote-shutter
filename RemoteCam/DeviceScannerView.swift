import SwiftUI
import MultipeerConnectivity

private let qrCodeImage: UIImage? = generateQRCode(remoteShutterUrl)

struct DeviceScannerView: View {
    @ObservedObject var viewModel: DeviceScannerViewModel

    let onStartScanning: () -> Void
    let onStopScanning: () -> Void
    let onSelectPeer: (MCPeerID) -> Void
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
        VStack(spacing: 24) {
            Spacer()

            // Camera icon
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.12))
                    .frame(width: 120, height: 120)

                Circle()
                    .strokeBorder(AppTheme.accent.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 120, height: 120)

                Image(systemName: "camera.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(AppTheme.accent)
            }

            VStack(spacing: 8) {
                Text(NSLocalizedString("Camera Mode", comment: ""))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text(NSLocalizedString("On another device, open Remote Shutter and select Remote. This camera will appear in their device list.", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Status
            statusBadge

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

            Spacer()

            // QR code + tip
            qrCodeSection
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            // Remote icon
            ZStack {
                Circle()
                    .fill(AppTheme.secondary.opacity(0.12))
                    .frame(width: 120, height: 120)

                Circle()
                    .strokeBorder(AppTheme.secondary.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 120, height: 120)

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(AppTheme.secondary)
            }

            VStack(spacing: 8) {
                Text(NSLocalizedString("Remote Mode", comment: ""))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text(NSLocalizedString("You need at least 2 devices running Remote Shutter", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Status
            statusBadge

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

            Spacer()

            // QR code + tip
            qrCodeSection
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

            HStack(spacing: 8) {
                Image(systemName: "qrcode")
                    .font(.caption)
                    .foregroundColor(AppTheme.accent)
                Text(NSLocalizedString("Scan the QR code on another device to download Remote Shutter", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 20)
    }

    // MARK: - Components

    private var statusBadge: some View {
        HStack(spacing: 8) {
            if viewModel.isScanning {
                ProgressView()
                    .scaleEffect(0.7)
            } else if viewModel.hasScanningError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
            }
            Text(viewModel.statusMessage)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(viewModel.hasScanningError ? .orange : .secondary)
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
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
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
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
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
            }
            .padding(32)
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
                onShareApp: {},
                onOpenSettings: {},
                onHelp: {}
            )
            .navigationTitle(NSLocalizedString("Scan for devices", comment: ""))
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
