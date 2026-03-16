import SwiftUI
import UIKit

// MARK: - Camera Progress Overlay View
struct CameraProgressOverlayView: View {
    @ObservedObject var viewModel: CameraViewModel
    
    var body: some View {
        ZStack {
            // Transparent background
            Color.clear

            // Mode & quality status (bottom-left)
            VStack {
                Spacer()
                HStack {
                    HStack(spacing: 6) {
                        Text(viewModel.currentMode == .Photo ? "Photo" : "Video")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                        Text(viewModel.qualityInfo)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(6)
                    .padding(.leading, 12)
                    .padding(.bottom, 12)
                    Spacer()
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
            }
        }
        .allowsHitTesting(false) // Allow touches to pass through
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