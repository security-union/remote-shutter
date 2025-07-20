import SwiftUI

struct LocalNetworkPermissionView: View {
    @Environment(\.dismiss) private var dismiss
    let permissionType: PermissionType
    let onAllow: () -> Void
    let onNotNow: () -> Void
    let onOpenSettings: () -> Void
    
    enum PermissionType {
        case initial
        case denied
    }
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        // Header section with icon and title
                        VStack(spacing: 24) {
                            Spacer()
                                .frame(height: max(60, geometry.safeAreaInsets.top + 40))
                            
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
                                
                                if permissionType == .initial {
                                    Button(action: onNotNow) {
                                        Text(NSLocalizedString("local_network_not_now", comment: ""))
                                            .font(.body)
                                            .foregroundColor(.blue)
                                            .frame(height: 44)
                                    }
                                } else {
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
            .navigationBarHidden(true)
        }
        .interactiveDismissDisabled()
    }
    
    // MARK: - Computed Properties
    
    private var localizedTitle: String {
        switch permissionType {
        case .initial:
            return NSLocalizedString("local_network_permission_title", comment: "")
        case .denied:
            return NSLocalizedString("local_network_access_required_title", comment: "")
        }
    }
    
    private var localizedSubtitle: String {
        switch permissionType {
        case .initial:
            return NSLocalizedString("local_network_permission_subtitle", comment: "")
        case .denied:
            return NSLocalizedString("local_network_access_required_subtitle", comment: "")
        }
    }
    
    private var primaryButtonTitle: String {
        switch permissionType {
        case .initial:
            return NSLocalizedString("local_network_allow", comment: "")
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
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Preview

struct LocalNetworkPermissionView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LocalNetworkPermissionView(
                permissionType: .initial,
                onAllow: {},
                onNotNow: {},
                onOpenSettings: {}
            )
            .previewDisplayName("Initial Permission")
            
            LocalNetworkPermissionView(
                permissionType: .denied,
                onAllow: {},
                onNotNow: {},
                onOpenSettings: {}
            )
            .previewDisplayName("Access Denied")
        }
    }
} 
