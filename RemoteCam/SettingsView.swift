import SwiftUI
import StoreKit

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        List {
            upgradesSection
            settingsSection
            aboutSection
        }
        .navigationTitle(NSLocalizedString("Settings", comment: ""))
        .navigationBarTitleDisplayMode(.large)
        .alert(
            NSLocalizedString("In-App Purchases", comment: ""),
            isPresented: $viewModel.showAlert
        ) {
            Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
        } message: {
            if let msg = viewModel.alertMessage {
                Text(msg)
            }
        }
    }

    // MARK: - Upgrades Section

    private var upgradesSection: some View {
        Section {
            purchaseRow(item: viewModel.proMode, icon: "star.fill", tint: .purple)
            purchaseRow(item: viewModel.removeAds, icon: "eye.slash.fill", tint: .blue)
            purchaseRow(item: viewModel.enableTorch, icon: "flashlight.on.fill", tint: .orange)
            purchaseRow(item: viewModel.enableVideo, icon: "video.fill", tint: .red)

            Button {
                viewModel.restorePurchases()
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.blue)
                        .frame(width: 28)
                    Text(NSLocalizedString("Restore Purchases", comment: ""))
                    Spacer()
                    if viewModel.isRestoringPurchases {
                        ProgressView()
                    }
                }
            }
            .disabled(viewModel.isRestoringPurchases)
        } header: {
            Text(NSLocalizedString("Upgrades", comment: ""))
        }
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        Section {
            Toggle(isOn: $viewModel.sendMediaToRemote) {
                HStack {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(.green)
                        .frame(width: 28)
                    Text(NSLocalizedString("Send Media to Remote", comment: ""))
                }
            }
        } header: {
            Text(NSLocalizedString("Settings", comment: ""))
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            linkRow(
                icon: "envelope.fill",
                tint: .blue,
                title: NSLocalizedString("Contact Support", comment: ""),
                urlString: "mailto:remoteshutter@securityunion.dev"
            )

            linkRow(
                icon: "bubble.left.and.bubble.right.fill",
                tint: .indigo,
                title: NSLocalizedString("Discord Community", comment: ""),
                urlString: "https://discord.gg/vJ7EqZCmJ7"
            )

            linkRow(
                icon: "chevron.left.forwardslash.chevron.right",
                tint: .gray,
                title: NSLocalizedString("Source Code", comment: ""),
                urlString: "https://github.com/security-union/remote-shutter"
            )

            NavigationLink {
                AcknowledgmentsViewWrapper()
                    .navigationTitle(NSLocalizedString("Acknowledgments", comment: ""))
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(.brown)
                        .frame(width: 28)
                    Text(NSLocalizedString("Acknowledgments", comment: ""))
                }
            }

            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                Text(NSLocalizedString("Version", comment: ""))
                Spacer()
                Text(viewModel.appVersion)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(NSLocalizedString("About", comment: ""))
        }
    }

    // MARK: - Reusable Rows

    private func purchaseRow(
        item: SettingsViewModel.PurchaseItem,
        icon: String,
        tint: Color
    ) -> some View {
        Button {
            viewModel.purchase(item)
        } label: {
            HStack {
                Image(systemName: item.isPurchased ? "checkmark.seal.fill" : icon)
                    .foregroundStyle(item.isPurchased ? .green : tint)
                    .frame(width: 28)

                Text(item.title)
                    .foregroundStyle(item.isPurchased ? .secondary : .primary)

                Spacer()

                if item.isPurchased {
                    Text(NSLocalizedString("Purchased", comment: ""))
                        .font(.subheadline)
                        .foregroundStyle(.green)
                } else if item.price.isEmpty {
                    ProgressView()
                } else {
                    Text(item.price)
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            }
        }
        .disabled(item.isPurchased || viewModel.isPurchasing)
    }

    private func linkRow(icon: String, tint: Color, title: String, urlString: String) -> some View {
        Button {
            if let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .frame(width: 28)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Acknowledgments Wrapper

struct AcknowledgmentsViewWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> AcknowledgmentsViewController {
        let vc = AcknowledgmentsViewController(
            nibName: "AcknowledgmentsViewController",
            bundle: nil
        )
        vc.url = Bundle.main.url(forResource: "Acknowledgments", withExtension: "html")
        return vc
    }

    func updateUIViewController(_ uiViewController: AcknowledgmentsViewController, context: Context) {}
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SettingsView()
        }
    }
}
