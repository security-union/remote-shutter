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
                        Text("How Remote Shutter Works")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        Text("Take perfect photos and videos using two devices")
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
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
                .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
                
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
                    
                    Button("Got It!") {
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
                        Button("Done") {
                            onDismiss()
                        }
                        .font(.body)
                        .fontWeight(.medium)
                    } else {
                        // Fallback on earlier versions
                        Button("Done") {
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
                        Text("1. Connect Devices")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Make sure both devices are on the same Wi-Fi network, then tap 'Start Scanning Devices' to find nearby devices running Remote Shutter.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                    }
                }
                
                VStack(spacing: 16) {
                    HelpTipCard(
                        icon: "qrcode",
                        title: "Quick Setup",
                        description: "Use the QR code to download Remote Shutter on your second device from the App Store"
                    )
                    
                    HelpTipCard(
                        icon: "network",
                        title: "Same Network",
                        description: "Both devices must be connected to the same Wi-Fi network to discover each other"
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
                        Text("2. Choose Device Roles")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Once connected, each device chooses its role. One becomes the camera, the other becomes the remote control.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                    }
                }
                
                VStack(spacing: 16) {
                    RoleCard(
                        icon: "camera.fill",
                        title: "Camera Device",
                        description: "Takes photos and videos, shows camera preview",
                        color: .blue
                    )
                    
                    RoleCard(
                        icon: "remote.fill",
                        title: "Remote Device",
                        description: "Controls the camera, shows live preview, adjusts settings",
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
                        Text("3. Capture Perfect Moments")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Use the remote device to control the camera, adjust settings, and capture photos or videos from a distance.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                    }
                }
                
                VStack(spacing: 16) {
                    FeatureCard(
                        icon: "camera.shutter.button",
                        title: "Remote Shutter",
                        description: "Take photos without touching the camera device"
                    )
                    
                    FeatureCard(
                        icon: "video.fill",
                        title: "Video Recording",
                        description: "Start and stop video recording remotely"
                    )
                    
                    FeatureCard(
                        icon: "flashlight.on.fill",
                        title: "Camera Controls",
                        description: "Adjust flash, torch, timer, and camera settings"
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
                        Text("Tips & Tricks")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Get the most out of Remote Shutter with these helpful tips")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                    }
                }
                
                VStack(spacing: 16) {
                    TipCard(
                        icon: "person.2.fill",
                        title: "Group Photos",
                        description: "Perfect for group selfies - set up the camera and use the remote to capture everyone in the shot"
                    )
                    
                    TipCard(
                        icon: "timer",
                        title: "Timer Feature",
                        description: "Use the timer on the remote device to get ready before the photo is taken"
                    )
                    
                    TipCard(
                        icon: "camera.rotate",
                        title: "Switch Cameras",
                        description: "Toggle between front and back cameras directly from the remote device"
                    )
                    
                    TipCard(
                        icon: "photo.stack",
                        title: "Auto Save",
                        description: "Photos and videos are automatically saved to both devices' photo libraries"
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
