import SwiftUI
import UIKit

// MARK: - Camera Progress Overlay View
struct CameraProgressOverlayView: View {
    @ObservedObject var viewModel: CameraViewModel
    
    var body: some View {
        ZStack {
            // Transparent background
            Color.clear
            
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