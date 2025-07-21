import SwiftUI

struct MicrophonePermissionPromptView: View {
    let onOpenSettings: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer()
                
                // Content
                VStack(spacing: 32) {
                    // Microphone icon
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.1))
                            .frame(width: 88, height: 88)
                        
                        Image(systemName: "mic.slash.circle.fill")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    
                    // Text content
                    VStack(spacing: 16) {
                        Text(NSLocalizedString("mic_required_title", comment: ""))
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.primary)
                        
                        Text(NSLocalizedString("mic_required_subtitle", comment: ""))
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
                            icon: "video.fill",
                            title: NSLocalizedString("video_recording_feature_title", comment: ""),
                            description: NSLocalizedString("video_recording_feature_description", comment: "")
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
                            Text(NSLocalizedString("mic_open_settings", comment: ""))
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.orange)
                        .cornerRadius(12)
                    }
                    
                    Button(action: onCancel) {
                        Text(NSLocalizedString("mic_cancel_recording", comment: ""))
                            .font(.body)
                            .foregroundColor(.orange)
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

// MARK: - Preview

struct MicrophonePermissionPromptView_Previews: PreviewProvider {
    static var previews: some View {
        MicrophonePermissionPromptView(
            onOpenSettings: {},
            onCancel: {}
        )
    }
} 