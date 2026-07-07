import SwiftUI

struct LocalNetworkPermissionView: View {
    @Environment(\.dismiss) private var dismiss
    let permissionType: PermissionType
    let onAllow: () -> Void
    let onOpenSettings: () -> Void
    
    enum PermissionType {
        case initial
        case denied
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    // Header section with icon and title
                    VStack(spacing: 24) {
                        // Network icon
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.1))
                                .frame(width: 88, height: 88)
                            
                            Image(systemName: "network")
                                .font(.system(size: 36, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        
                        VStack(spacing: 12) {
                            Text(localizedTitle)
                                .font(.title2)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.primary)
                            
                            Text(localizedSubtitle)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    
                    // Content section
                    VStack(spacing: 24) {
                        Spacer()
                            .frame(height: 50)
                        
                        // Feature explanation cards
                        VStack(spacing: 16) {
                            FeatureCard(
                                icon: "iphone.and.arrow.forward",
                                title: NSLocalizedString("local_network_feature_title", comment: ""),
                                description: NSLocalizedString("local_network_feature_description", comment: "")
                            )
                            
                            FeatureCard(
                                icon: "lock.shield",
                                title: NSLocalizedString("local_network_privacy_title", comment: ""),
                                description: NSLocalizedString("local_network_privacy_description", comment: "")
                            )
                            
                            FeatureCard(
                                icon: "bolt.circle",
                                title: NSLocalizedString("local_network_benefits_title", comment: ""),
                                description: NSLocalizedString("local_network_benefits_description", comment: "")
                            )
                        }
                        
                        Spacer()
                            .frame(height: 40)
                        
                        // Action buttons
                        VStack(spacing: 12) {
                            Button(action: primaryAction) {
                                HStack {
                                    Text(primaryButtonTitle)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.blue)
                                .cornerRadius(12)
                            }
                            
                            // App Review 5.1.1(iv): the pre-permission message must not offer
                            // an exit — the only way forward is into the system prompt, so
                            // `.initial` has no secondary button.
                            if permissionType == .denied {
                                Button(action: dismissAction) {
                                    Text(NSLocalizedString("local_network_cancel", comment: ""))
                                        .font(.body)
                                        .foregroundColor(.blue)
                                        .frame(height: 44)
                                }
                            }
                        }
                        
                        Spacer()
                            .frame(height: max(40, geometry.safeAreaInsets.bottom + 20))
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .background(Color(.systemBackground))
        .interactiveDismissDisabled()
    }
    
    // MARK: - Computed Properties
    
    private var localizedTitle: String {
        switch permissionType {
        case .initial:
            return NSLocalizedString("local_network_title", comment: "")
        case .denied:
            return NSLocalizedString("local_network_subtitle", comment: "")
        }
    }
    
    private var localizedSubtitle: String {
        switch permissionType {
        case .initial:
            return NSLocalizedString("local_network_subtitle", comment: "")
        case .denied:
            return NSLocalizedString("local_network_required_subtitle", comment: "")
        }
    }
    
    private var primaryButtonTitle: String {
        switch permissionType {
        case .initial:
            return NSLocalizedString("local_network_continue", comment: "")
        case .denied:
            return NSLocalizedString("local_network_open_settings", comment: "")
        }
    }
    
    private var primaryAction: () -> Void {
        switch permissionType {
        case .initial:
            return onAllow
        case .denied:
            return onOpenSettings
        }
    }
    
    private var dismissAction: () -> Void {
        return {
            dismiss()
        }
    }
}

// MARK: - Feature Card Component

struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(AppTheme.accentSubtle)
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(AppTheme.accent)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            // Premium glassmorphism card background
            ZStack {
                // Backdrop blur effect with proper clipping
                Color.black.opacity(0.3)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                
                // Subtle border highlight
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.4),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
        )
        .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 4)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Preview

struct LocalNetworkPermissionView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LocalNetworkPermissionView(
                permissionType: .initial,
                onAllow: {},
                onOpenSettings: {}
            )
            .previewDisplayName("Initial Permission")

            LocalNetworkPermissionView(
                permissionType: .denied,
                onAllow: {},
                onOpenSettings: {}
            )
            .previewDisplayName("Access Denied")
        }
    }
} 
