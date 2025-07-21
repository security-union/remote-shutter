import SwiftUI

struct CameraPermissionErrorView: View {
    let onOpenSettings: () -> Void
    let onGoBack: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer()
                
                // Error content
                VStack(spacing: 32) {
                    // Lock icon
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.1))
                            .frame(width: 88, height: 88)
                        
                        Image(systemName: "lock.circle.fill")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundColor(.red)
                    }
                    
                    // Error text
                    VStack(spacing: 16) {
                        Text(NSLocalizedString("camera_error_title", comment: ""))
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.primary)
                        
                        Text(NSLocalizedString("camera_error_subtitle", comment: ""))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                    
                    // Feature requirements
                    VStack(spacing: 12) {
                        PermissionRequirementRow(
                            icon: "camera.fill",
                            title: NSLocalizedString("camera_access_required", comment: ""),
                            isGranted: PermissionManager.shared.cameraStatus == .authorized
                        )
                        
                        PermissionRequirementRow(
                            icon: "photo.fill",
                            title: NSLocalizedString("photos_access_required", comment: ""),
                            isGranted: PermissionManager.shared.photosStatus == .authorized || PermissionManager.shared.photosStatus == .limited
                        )
                    }
                    .padding(.horizontal, 20)
                }
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: onOpenSettings) {
                        HStack {
                            Image(systemName: "gear")
                                .font(.system(size: 16, weight: .medium))
                            Text(NSLocalizedString("camera_error_open_settings", comment: ""))
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    
                    Button(action: onGoBack) {
                        Text(NSLocalizedString("camera_error_go_back", comment: ""))
                            .font(.body)
                            .foregroundColor(.blue)
                            .frame(height: 44)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, max(20, geometry.safeAreaInsets.bottom))
            }
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Permission Requirement Row

struct PermissionRequirementRow: View {
    let icon: String
    let title: String
    let isGranted: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(isGranted ? .green : .red)
                .frame(width: 24, height: 24)
            
            Text(title)
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
            
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(isGranted ? .green : .red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

// MARK: - Preview

struct CameraPermissionErrorView_Previews: PreviewProvider {
    static var previews: some View {
        CameraPermissionErrorView(
            onOpenSettings: {},
            onGoBack: {}
        )
    }
} 