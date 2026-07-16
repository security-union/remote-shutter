import SwiftUI
import StoreKit

struct WelcomeView: View {
    @ObservedObject var viewModel: WelcomeViewModel

    let onContinue: () -> Void
    let onHelp: () -> Void
    let onReviewApp: () -> Void

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient

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

                    if viewModel.canShowReview {
                        rateSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
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
                .foregroundColor(.secondary)
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
                    .foregroundColor(AppTheme.accent)
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
                        .foregroundColor(AppTheme.accent)
                    Text(item.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                }

                Text(NSLocalizedString("Unlock all features: video recording, torch control, and ad-free experience.", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if item.price.isEmpty {
                    ProgressView()
                } else {
                    Text(item.price)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(AppTheme.accent)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(AppTheme.accent.opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: AppTheme.accent.opacity(0.1), radius: 8, y: 4)
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
                    .foregroundColor(AppTheme.accent)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(item.title)
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                if item.price.isEmpty {
                    ProgressView()
                } else {
                    Text(item.price)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppTheme.accent)
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

    // MARK: - Thank You

    private var thankYouSection: some View {
        Text(NSLocalizedString("Thank you for your support!", comment: ""))
            .font(.subheadline)
            .foregroundColor(.secondary)
    }

    // MARK: - Rate

    private var rateSection: some View {
        Button {
            onReviewApp()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .font(.caption)
                Text(NSLocalizedString("Rate on App Store", comment: ""))
                    .font(.subheadline)
            }
            .foregroundColor(AppTheme.accent)
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
