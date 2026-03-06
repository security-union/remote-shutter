import SwiftUI
import StoreKit

struct WelcomeView: View {
    @ObservedObject var viewModel: WelcomeViewModel

    let onContinue: () -> Void
    let onHelp: () -> Void
    let onReviewApp: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                headerSection
                    .padding(.top, 20)

                if !viewModel.hasAllFeatures {
                    upgradesSection
                }

                continueButton

                if viewModel.hasAnyPurchase {
                    thankYouSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .alert(
            viewModel.alertTitle,
            isPresented: $viewModel.showAlert
        ) {
            Button(NSLocalizedString("OK", comment: ""), role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 16) {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)

            Text("Remote Shutter")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(NSLocalizedString("Turn two devices into a professional remote camera system", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Upgrades

    private var upgradesSection: some View {
        VStack(spacing: 12) {
            // Pro item — featured card
            if let pro = viewModel.upgrades.first, !pro.isPurchased {
                proCard(pro)
            }

            // Individual items
            let individuals = viewModel.upgrades.dropFirst().filter { !$0.isPurchased }
            if !individuals.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(individuals.enumerated()), id: \.element.id) { index, item in
                        upgradeRow(item)
                        if index < individuals.count - 1 {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Restore
            Button {
                viewModel.restorePurchases()
            } label: {
                Text(NSLocalizedString("Restore Purchases", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.blue)
            }
            .disabled(viewModel.isPurchasing)
            .padding(.top, 4)
        }
    }

    private func proCard(_ item: WelcomeViewModel.UpgradeItem) -> some View {
        Button {
            viewModel.purchase(item)
        } label: {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "star.fill")
                        .font(.title2)
                        .foregroundStyle(.purple)
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                }

                Text(NSLocalizedString("Unlock all features: video recording, torch control, and ad-free experience.", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if item.price.isEmpty {
                    ProgressView()
                } else {
                    Text(item.price)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.purple)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.purple.opacity(0.5), .blue.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .purple.opacity(0.15), radius: 8, y: 4)
        }
        .disabled(viewModel.isPurchasing)
    }

    private func upgradeRow(_ item: WelcomeViewModel.UpgradeItem) -> some View {
        Button {
            viewModel.purchase(item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.body)
                    .foregroundStyle(tintColor(for: item.tint))
                    .frame(width: 32, height: 32)
                    .background(tintColor(for: item.tint).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(item.title)
                    .font(.body)
                    .foregroundStyle(.primary)

                Spacer()

                if item.price.isEmpty {
                    ProgressView()
                } else {
                    Text(item.price)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .disabled(viewModel.isPurchasing)
    }

    // MARK: - Continue

    private var continueButton: some View {
        Button(action: onContinue) {
            HStack {
                Text(NSLocalizedString("Get Started", comment: ""))
                    .font(.headline)
                Image(systemName: "arrow.right")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                LinearGradient(
                    colors: [.blue, Color(red: 0.0, green: 0.4, blue: 0.9)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
        }
    }

    // MARK: - Thank You

    private var thankYouSection: some View {
        VStack(spacing: 12) {
            Text(NSLocalizedString("Thank you for your support!", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if viewModel.canShowReview {
                Button {
                    onReviewApp()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                        Text(NSLocalizedString("Rate on App Store", comment: ""))
                            .font(.subheadline)
                    }
                    .foregroundStyle(.pink)
                }
            }
        }
    }

    // MARK: - Helpers

    private func tintColor(for name: String) -> Color {
        switch name {
        case "purple": return .purple
        case "blue": return .blue
        case "orange": return .orange
        case "red": return .red
        default: return .blue
        }
    }
}

// MARK: - Preview

struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView(
            viewModel: WelcomeViewModel(),
            onContinue: {},
            onHelp: {},
            onReviewApp: {}
        )
    }
}
