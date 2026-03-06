import SwiftUI
import StoreKit

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                upgradesSection
                settingsSection
                aboutSection
            }
            .navigationTitle(NSLocalizedString("Settings", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                            Text(NSLocalizedString("Back", comment: ""))
                        }
                    }
                }
            }
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
                AcknowledgmentsView()
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

// MARK: - Acknowledgments View

struct AcknowledgmentsView: View {
    private let credits: [(role: String, name: String)] = [
        ("QA", "Mariela Cruz Rodriguez"),
        ("Dev", "Griffin Obeid"),
        ("Dev", "Dario A Lencina Talarico"),
        ("Logo", "Franco Talarico"),
        ("Translations", "Romina Lencina Talarico"),
        ("Translations", "Oskar Roar Andersen"),
    ]

    var body: some View {
        List {
            Section {
                ForEach(credits, id: \.name) { credit in
                    HStack {
                        Text(credit.name)
                        Spacer()
                        Text(credit.role)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Security Union")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Theater Framework")
                        .font(.headline)
                    Text("Created by Dario Talarico, 2015.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Licensed under the Apache License, Version 2.0. You may obtain a copy at apache.org/licenses/LICENSE-2.0.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Open Source")
            }

            Section {
                Text("To my Wife Mariela for supporting me at all times. To Franco Talarico for helping me out and trusting me. To my family, Laura Talarico, my sis Romina and Ruben Lencina for helping me to test this app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Special Thanks")
            }
        }
    }
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SettingsView()
        }
    }
}
