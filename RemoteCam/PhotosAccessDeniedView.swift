import SwiftUI

struct PhotosAccessDeniedView: View {
    let contentType: ContentType
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void
    
    @State private var canDismiss = false
    
    enum ContentType {
        case photo
        case video
        
        var iconName: String {
            switch self {
            case .photo: return "photo.circle.fill"
            case .video: return "video.circle.fill"
            }
        }
        
        var title: String {
            switch self {
            case .photo: return NSLocalizedString("photos_access_denied_photo_title", comment: "")
            case .video: return NSLocalizedString("photos_access_denied_video_title", comment: "")
            }
        }
        
        var subtitle: String {
            switch self {
            case .photo: return NSLocalizedString("photos_access_denied_photo_subtitle", comment: "")
            case .video: return NSLocalizedString("photos_access_denied_video_subtitle", comment: "")
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer()
                
                // Content
                VStack(spacing: 32) {
                    // Photos/Video icon
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.1))
                            .frame(width: 88, height: 88)
                        
                        Image(systemName: contentType.iconName)
                            .font(.system(size: 36, weight: .medium))
                            .foregroundColor(.red)
                    }
                    
                    // Text content
                    VStack(spacing: 16) {
                        Text(contentType.title)
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.primary)
                        
                        Text(contentType.subtitle)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                    
                    // Feature explanation
                    VStack(spacing: 12) {
                        FeatureCard(
                            icon: "lock.shield",
                            title: NSLocalizedString("photos_privacy_feature_title", comment: ""),
                            description: NSLocalizedString("photos_privacy_feature_description", comment: "")
                        )
                        
                        FeatureCard(
                            icon: "square.and.arrow.up",
                            title: NSLocalizedString("photos_sharing_feature_title", comment: ""),
                            description: NSLocalizedString("photos_sharing_feature_description", comment: "")
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
                            Text(NSLocalizedString("photos_open_settings", comment: ""))
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.red)
                        .cornerRadius(12)
                    }
                    .disabled(!canDismiss)
                    .opacity(canDismiss ? 1.0 : 0.7)
                    
                    Button(action: {
                        logDebug("📱 DISMISS BUTTON TAPPED - canDismiss: \(canDismiss)")
                        if canDismiss {
                            logDebug("📱 Calling onDismiss callback...")
                            onDismiss()
                        } else {
                            logDebug("📱 Button disabled, not calling onDismiss")
                        }
                    }) {
                        HStack {
                            Text(NSLocalizedString("photos_dismiss", comment: ""))
                                .font(.body)
                                .foregroundColor(.red)
                            
                            // Debug indicator
                            if canDismiss {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            } else {
                                Image(systemName: "clock.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                            }
                        }
                        .frame(height: 44)
                    }
                    .disabled(!canDismiss)
                    .opacity(canDismiss ? 1.0 : 0.7)
                    .onChange(of: canDismiss) { newValue in
                        logDebug("📱 canDismiss changed to: \(newValue)")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, max(20, geometry.safeAreaInsets.bottom))
            }
        }
        .background(Color(.systemBackground))
        .onAppear {
            logDebug("📱 PhotosAccessDeniedView appeared")
            // Enable dismissal after a short delay to prevent accidental auto-dismissal
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                logDebug("📱 Setting canDismiss = true")
                canDismiss = true
                logDebug("📱 PhotosAccessDeniedView buttons enabled - canDismiss is now: \(canDismiss)")
            }
        }
        .onDisappear {
            logDebug("📱 PhotosAccessDeniedView disappeared")
        }
    }
}

// MARK: - Preview

struct PhotosAccessDeniedView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PhotosAccessDeniedView(
                contentType: .photo,
                onOpenSettings: {},
                onDismiss: {}
            )
            .previewDisplayName("Photo Access Denied")
            
            PhotosAccessDeniedView(
                contentType: .video,
                onOpenSettings: {},
                onDismiss: {}
            )
            .previewDisplayName("Video Access Denied")
        }
    }
} 