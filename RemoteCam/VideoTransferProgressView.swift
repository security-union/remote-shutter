import SwiftUI
import Foundation

// MARK: - Video Transfer Progress View
struct VideoTransferProgressView: View {
    let progress: Double // 0.0 to 1.0
    let transferSizeText: String // e.g., "15.2 MB / 45.8 MB"
    let transferSpeedText: String // e.g., "2.1 MB/s"
    let isVisible: Bool
    
    var body: some View {
        if isVisible {
            VStack(spacing: 12) {
                // Transfer status text
                Text("Transferring Video")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .tracking(0.3)
                
                // Progress percentage
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .tracking(0.5)
                
                // Progress bar with refined styling
                VStack(spacing: 6) {
                    // Enhanced progress bar
                    ZStack(alignment: .leading) {
                        // Background track with subtle gradient
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.15),
                                        Color.white.opacity(0.25)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 200, height: 12)
                        
                        // Progress fill with beautiful gradient
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.0, green: 0.48, blue: 1.0), // iOS blue
                                        Color(red: 0.0, green: 0.68, blue: 1.0)  // Lighter blue
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: CGFloat(200 * progress), 
                                height: 12
                            )
                            .shadow(color: Color.blue.opacity(0.4), radius: 3, x: 0, y: 1)
                            .animation(.easeInOut(duration: 0.3), value: progress)
                    }
                    
                    // Transfer size and speed info
                    HStack {
                        Text(transferSizeText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Spacer()
                        
                        Text(transferSpeedText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .frame(width: 200)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(
                // Premium glassmorphism card background
                ZStack {
                    // Backdrop blur effect with proper clipping
                    Color.black.opacity(0.35)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    
                    // Subtle border highlight
                    RoundedRectangle(cornerRadius: 18)
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
            .transition(.asymmetric(
                insertion: .scale(scale: 0.8).combined(with: .opacity),
                removal: .scale(scale: 0.9).combined(with: .opacity)
            ))
        }
    }
}

// MARK: - Helper Extensions
extension VideoTransferProgressView {
    static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    static func formatTransferSpeed(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }
}

// MARK: - Preview
struct VideoTransferProgressView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 40) {
                VideoTransferProgressView(
                    progress: 0.35,
                    transferSizeText: "15.2 MB / 45.8 MB",
                    transferSpeedText: "2.1 MB/s",
                    isVisible: true
                )
                
                VideoTransferProgressView(
                    progress: 0.75,
                    transferSizeText: "34.5 MB / 45.8 MB",
                    transferSpeedText: "1.8 MB/s",
                    isVisible: true
                )
            }
        }
        .preferredColorScheme(.dark)
    }
} 