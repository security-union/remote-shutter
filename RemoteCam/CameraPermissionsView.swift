import SwiftUI
import AVFoundation
import Photos

struct CameraPermissionsView: View {
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
                        Spacer()
                            .frame(height: max(60, geometry.safeAreaInsets.top + 40))
                        
                        // Camera icon
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.1))
                                .frame(width: 88, height: 88)
                            
                            Image(systemName: "camera.fill")
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
                                icon: "camera.circle",
                                title: NSLocalizedString("camera_permission_feature_title", comment: ""),
                                description: NSLocalizedString("camera_permission_feature_description", comment: "")
                            )
                            
                            FeatureCard(
                                icon: "photo.on.rectangle",
                                title: NSLocalizedString("photos_permission_feature_title", comment: ""),
                                description: NSLocalizedString("photos_permission_feature_description", comment: "")
                            )
                            
                            FeatureCard(
                                icon: "iphone.and.arrow.forward",
                                title: NSLocalizedString("remote_control_feature_title", comment: ""),
                                description: NSLocalizedString("remote_control_feature_description", comment: "")
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
                                    Text(NSLocalizedString("camera_permissions_cancel", comment: ""))
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
            return NSLocalizedString("camera_permissions_title", comment: "")
        case .denied:
            return NSLocalizedString("camera_permissions_required_title", comment: "")
        }
    }
    
    private var localizedSubtitle: String {
        switch permissionType {
        case .initial:
            return NSLocalizedString("camera_permissions_subtitle", comment: "")
        case .denied:
            return NSLocalizedString("camera_permissions_required_subtitle", comment: "")
        }
    }
    
    private var primaryButtonTitle: String {
        switch permissionType {
        case .initial:
            return NSLocalizedString("camera_permissions_continue", comment: "")
        case .denied:
            return NSLocalizedString("camera_permissions_open_settings", comment: "")
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

// MARK: - Feature Card Component (reusing from LocalNetworkPermissionView)

// MARK: - Preview

struct CameraPermissionsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CameraPermissionsView(
                permissionType: .initial,
                onAllow: {},
                onOpenSettings: {}
            )
            .previewDisplayName("Initial Permission")

            CameraPermissionsView(
                permissionType: .denied,
                onAllow: {},
                onOpenSettings: {}
            )
            .previewDisplayName("Access Denied")
        }
    }
} 