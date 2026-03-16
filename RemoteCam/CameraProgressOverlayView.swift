import SwiftUI
import UIKit

// MARK: - Camera Progress Overlay View
struct CameraProgressOverlayView: View {
    @ObservedObject var viewModel: CameraViewModel
    
    var body: some View {
        ZStack {
            // Transparent background — pass touches through
            Color.clear
                .allowsHitTesting(false)

            // Timer countdown display (centered)
            if viewModel.countdownValue > 0 {
                Text("\(viewModel.countdownValue)")
                    .font(.system(size: 120, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 2)
                    .allowsHitTesting(false)
            } else if viewModel.countdownCancelled {
                Text("Cancelled")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 8, x: 0, y: 2)
                    .allowsHitTesting(false)
            }

            // Toast: "Control settings from the remote"
            if viewModel.showRemoteHint {
                VStack {
                    Spacer()
                    Text("Control settings from the remote")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(10)
                        .padding(.bottom, 60)
                        .transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.3), value: viewModel.showRemoteHint)
                .allowsHitTesting(false)
            }

            // Mode & quality status (bottom center) — tappable
            VStack {
                Spacer()
                HStack(spacing: 6) {
                    Text(modeLabel)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                    Text("\u{00B7}")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(.white.opacity(0.5))
                    Text(viewModel.qualityInfo)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.5))
                .cornerRadius(8)
                .padding(.bottom, 12)
                .onTapGesture {
                    viewModel.showRemoteControlHint()
                }
            }

            // Progress overlay centered
            if viewModel.isVideoTransferring {
                VideoTransferProgressView(
                    progress: viewModel.videoTransferProgress,
                    transferSizeText: viewModel.videoTransferSizeText,
                    transferSpeedText: viewModel.videoTransferSpeedText,
                    isVisible: viewModel.isVideoTransferring
                )
                .allowsHitTesting(false)
            }
        }
    }

    private var modeLabel: String {
        switch viewModel.currentMode {
        case .Photo: return "Photo"
        case .Video: return "Video"
        case .Shorts: return "Shorts"
        }
    }
}

// MARK: - Preview
struct CameraProgressOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            CameraProgressOverlayView(viewModel: {
                let vm = CameraViewModel()
                vm.startVideoTransfer(totalBytes: 45_800_000)
                vm.updateVideoTransferProgress(completedBytes: 15_200_000, totalBytes: 45_800_000)
                vm.updateVideoTransferSpeed(2_100_000)
                return vm
            }())
        }
        .preferredColorScheme(.dark)
    }
} 