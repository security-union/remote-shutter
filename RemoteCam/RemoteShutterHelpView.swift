import SwiftUI

struct RemoteShutterHelpView: View {
    let onDismiss: () -> Void
    @State private var selectedPage = 0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "camera.circle.fill")
                        .font(.system(size: 60, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    VStack(spacing: 8) {
                        Text(NSLocalizedString("help_title", comment: "Help modal title"))
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        Text(NSLocalizedString("help_subtitle", comment: "Help modal subtitle"))
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 20)
                .padding(.horizontal, 24)
                
                // Content Pages
                TabView(selection: $selectedPage) {
                    ConnectDevicesPage()
                        .tag(0)
                    
                    ChooseRolePage()
                        .tag(1)
                    
                    CaptureMediaPage()
                        .tag(2)
                    
                    TipsAndTricksPage()
                        .tag(3)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                
                // Footer
                VStack(spacing: 16) {
                    HStack(spacing: 20) {
                        ForEach(0..<4, id: \.self) { index in
                            Circle()
                                .fill(selectedPage == index ? Color.blue : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                                .scaleEffect(selectedPage == index ? 1.2 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: selectedPage)
                        }
                    }
                    
                    Button(NSLocalizedString("help_got_it", comment: "Help modal Got It button")) {
                        onDismiss()
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .cornerRadius(12)
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 20)
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if #available(iOS 16.0, *) {
                        Button(NSLocalizedString("help_done", comment: "Help modal Done button")) {
                            onDismiss()
                        }
                        .font(.body)
                        .fontWeight(.medium)
                    } else {
                        // Fallback on earlier versions
                        Button(NSLocalizedString("help_done", comment: "Help modal Done button")) {
                            onDismiss()
                        }.font(.body)
                    }
                }
            }
        }
    }
}

// MARK: - Help Pages

struct ConnectDevicesPage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer()
                    .frame(height: 40)
                
                VStack(spacing: 24) {
                    Image(systemName: "wifi")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundColor(.blue)
                    
                    VStack(spacing: 12) {
                        Text(NSLocalizedString("help_connect_title", comment: "Connect devices step title"))
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(NSLocalizedString("help_connect_description", comment: "Connect devices step description"))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                    }
                }
                
                VStack(spacing: 16) {
                    HelpTipCard(
                        icon: "qrcode",
                        title: NSLocalizedString("help_quick_setup_title", comment: "Quick setup tip title"),
                        description: NSLocalizedString("help_quick_setup_description", comment: "Quick setup tip description")
                    )
                    
                    HelpTipCard(
                        icon: "network",
                        title: NSLocalizedString("help_same_network_title", comment: "Same network tip title"),
                        description: NSLocalizedString("help_same_network_description", comment: "Same network tip description")
                    )
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }
}

struct ChooseRolePage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer()
                    .frame(height: 40)
                
                VStack(spacing: 24) {
                    HStack(spacing: 20) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundColor(.blue)
                        
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.gray)
                        
                        Image(systemName: "iphone")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundColor(.green)
                    }
                    
                    VStack(spacing: 12) {
                        Text(NSLocalizedString("help_roles_title", comment: "Choose roles step title"))
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(NSLocalizedString("help_roles_description", comment: "Choose roles step description"))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                    }
                }
                
                VStack(spacing: 16) {
                    RoleCard(
                        icon: "camera.fill",
                        title: NSLocalizedString("help_camera_device_title", comment: "Camera device title"),
                        description: NSLocalizedString("help_camera_device_description", comment: "Camera device description"),
                        color: .blue
                    )
                    
                    RoleCard(
                        icon: "remote.fill",
                        title: NSLocalizedString("help_remote_device_title", comment: "Remote device title"),
                        description: NSLocalizedString("help_remote_device_description", comment: "Remote device description"),
                        color: .green
                    )
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }
}

struct CaptureMediaPage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer()
                    .frame(height: 40)
                
                VStack(spacing: 24) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundColor(.purple)
                    
                    VStack(spacing: 12) {
                        Text(NSLocalizedString("help_capture_title", comment: "Capture moments step title"))
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(NSLocalizedString("help_capture_description", comment: "Capture moments step description"))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                    }
                }
                
                VStack(spacing: 16) {
                    FeatureCard(
                        icon: "camera.shutter.button",
                        title: NSLocalizedString("help_remote_shutter_title", comment: "Remote shutter feature title"),
                        description: NSLocalizedString("help_remote_shutter_description", comment: "Remote shutter feature description")
                    )
                    
                    FeatureCard(
                        icon: "video.fill",
                        title: NSLocalizedString("help_video_recording_title", comment: "Video recording feature title"),
                        description: NSLocalizedString("help_video_recording_description", comment: "Video recording feature description")
                    )
                    
                    FeatureCard(
                        icon: "flashlight.on.fill",
                        title: NSLocalizedString("help_camera_controls_title", comment: "Camera controls feature title"),
                        description: NSLocalizedString("help_camera_controls_description", comment: "Camera controls feature description")
                    )
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }
}

struct TipsAndTricksPage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer()
                    .frame(height: 40)
                
                VStack(spacing: 24) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundColor(.orange)
                    
                    VStack(spacing: 12) {
                        Text(NSLocalizedString("help_tips_title", comment: "Tips and tricks page title"))
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(NSLocalizedString("help_tips_description", comment: "Tips and tricks page description"))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                    }
                }
                
                VStack(spacing: 16) {
                    TipCard(
                        icon: "person.2.fill",
                        title: NSLocalizedString("help_group_photos_title", comment: "Group photos tip title"),
                        description: NSLocalizedString("help_group_photos_description", comment: "Group photos tip description")
                    )
                    
                    TipCard(
                        icon: "timer",
                        title: NSLocalizedString("help_timer_feature_title", comment: "Timer feature tip title"),
                        description: NSLocalizedString("help_timer_feature_description", comment: "Timer feature tip description")
                    )
                    
                    TipCard(
                        icon: "camera.rotate",
                        title: NSLocalizedString("help_switch_cameras_title", comment: "Switch cameras tip title"),
                        description: NSLocalizedString("help_switch_cameras_description", comment: "Switch cameras tip description")
                    )
                    
                    TipCard(
                        icon: "photo.stack",
                        title: NSLocalizedString("help_auto_save_title", comment: "Auto save tip title"),
                        description: NSLocalizedString("help_auto_save_description", comment: "Auto save tip description")
                    )
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Component Views

struct HelpTipCard: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct RoleCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .medium))
                .foregroundColor(color)
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct TipCard: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.orange)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(10)
    }
}

// MARK: - Preview

struct RemoteShutterHelpView_Previews: PreviewProvider {
    static var previews: some View {
        RemoteShutterHelpView(onDismiss: {})
    }
} 
