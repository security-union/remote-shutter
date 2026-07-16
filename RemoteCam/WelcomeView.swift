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

    /// Product IDs that unlock everything (the three Pro plans). The rest are
    /// à la carte individual features.
    private static let everythingIDs: Set<String> = [proYearlyPID, proMonthlyPID, enableVideoPID]

    private var upgradesSection: some View {
        // Before load: show every non-purchased item (as skeletons). After load:
        // drop items whose product isn't on the store (empty name).
        let ready = viewModel.productsLoaded
        let visible = viewModel.upgrades.filter { !$0.isPurchased && (!ready || !$0.title.isEmpty) }
        let everything = visible.filter { Self.everythingIDs.contains($0.id) }
        let featured = everything.first                 // yearly (first in the upgrades order)
        let otherPlans = Array(everything.dropFirst())  // monthly, lifetime
        let alaCarte = visible.filter { !Self.everythingIDs.contains($0.id) }

        return VStack(spacing: 12) {
            // Everything tier: featured plan card + the remaining Pro plans.
            if let featured {
                proCard(featured)
            }
            if !otherPlans.isEmpty {
                upgradeCardGroup(otherPlans)
            }

            // À la carte: individual features.
            if !alaCarte.isEmpty {
                Text(NSLocalizedString("À la carte", comment: ""))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                upgradeCardGroup(alaCarte)
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

    /// A rounded card of upgrade rows separated by dividers.
    private func upgradeCardGroup(_ items: [WelcomeViewModel.UpgradeItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                upgradeRow(item)
                if index < items.count - 1 {
                    Divider()
                        .padding(.leading, 52)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func proCard(_ item: WelcomeViewModel.UpgradeItem) -> some View {
        Button {
            viewModel.purchase(item)
        } label: {
            let ready = viewModel.productsLoaded
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: item.icon)
                        .font(.title2)
                        .foregroundColor(AppTheme.accent)
                    // Plan name from StoreKit; placeholder sizes the skeleton.
                    Text(ready ? item.title : "Placeholder plan")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .redacted(reason: ready ? [] : .placeholder)
                    Spacer()
                }

                Text(NSLocalizedString("Any Pro plan unlocks every feature: video recording, torch control, tap to focus, and no ads.", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(ready ? item.price : "$00.00")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .redacted(reason: ready ? [] : .placeholder)
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
        .disabled(viewModel.isPurchasing || !viewModel.productsLoaded)
    }

    private func upgradeRow(_ item: WelcomeViewModel.UpgradeItem) -> some View {
        let ready = viewModel.productsLoaded
        return Button {
            viewModel.purchase(item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.body)
                    .foregroundColor(AppTheme.accent)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(ready ? item.title : "Placeholder feature")
                    .font(.body)
                    .foregroundColor(.primary)

                Spacer()

                Text(ready ? item.price : "$0.00")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .redacted(reason: ready ? [] : .placeholder)
        }
        .disabled(viewModel.isPurchasing || !ready)
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
