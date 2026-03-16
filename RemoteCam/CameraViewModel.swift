import Foundation
import SwiftUI
import Combine

// MARK: - Camera View Model
class CameraViewModel: ObservableObject {
    // MARK: - Mode & Quality Status
    @Published var currentMode: RecordingMode = .Photo
    @Published var qualityInfo: String = "1080p 30fps"

    func updateStatus(mode: RecordingMode, resolution: VideoResolution, frameRate: VideoFrameRate,
                      photoFormat: PhotoFormat, hdrMode: HDRMode) {
        DispatchQueue.main.async {
            self.currentMode = mode
            switch mode {
            case .Video, .Shorts:
                self.qualityInfo = "\(resolution.displayName) \(frameRate.displayName)fps"
            case .Photo:
                var info = photoFormat.displayName
                if hdrMode == .on { info += " HDR" }
                self.qualityInfo = info
            }
        }
    }

    // MARK: - Video Transfer Progress Properties
    @Published var isVideoTransferring: Bool = false
    @Published var videoTransferProgress: Double = 0.0 // 0.0 to 1.0
    @Published var videoTransferBytesCompleted: Int64 = 0
    @Published var videoTransferBytesTotal: Int64 = 0
    @Published var videoTransferSpeed: Double = 0.0 // bytes per second
    
    // MARK: - Video Transfer Progress Methods
    func startVideoTransfer(totalBytes: Int64) {
        DispatchQueue.main.async {
            self.isVideoTransferring = true
            self.videoTransferProgress = 0.0
            self.videoTransferBytesCompleted = 0
            self.videoTransferBytesTotal = totalBytes
            self.videoTransferSpeed = 0.0
        }
    }
    
    func updateVideoTransferProgress(completedBytes: Int64, totalBytes: Int64) {
        DispatchQueue.main.async {
            self.videoTransferBytesCompleted = completedBytes
            self.videoTransferBytesTotal = totalBytes
            self.videoTransferProgress = totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : 0.0
        }
    }
    
    func updateVideoTransferSpeed(_ bytesPerSecond: Double) {
        DispatchQueue.main.async {
            self.videoTransferSpeed = bytesPerSecond
        }
    }
    
    func finishVideoTransfer() {
        DispatchQueue.main.async {
            self.isVideoTransferring = false
            self.videoTransferProgress = 1.0
            self.videoTransferSpeed = 0.0
            
            // Hide the progress after a brief delay to show completion
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.videoTransferProgress = 0.0
                self.videoTransferBytesCompleted = 0
                self.videoTransferBytesTotal = 0
            }
        }
    }
    
    var videoTransferSizeText: String {
        VideoTransferProgressView.formatFileSize(videoTransferBytesCompleted) + " / " + 
        VideoTransferProgressView.formatFileSize(videoTransferBytesTotal)
    }
    
    var videoTransferSpeedText: String {
        VideoTransferProgressView.formatTransferSpeed(videoTransferSpeed)
    }

    // MARK: - Timer Countdown Properties
    @Published var countdownValue: Int = 0
    @Published var countdownCancelled: Bool = false

    // MARK: - Timer Countdown Methods
    func showCountdown(_ value: Int) {
        DispatchQueue.main.async {
            self.countdownCancelled = false
            self.countdownValue = value
        }
    }

    func cancelCountdown() {
        DispatchQueue.main.async {
            self.countdownCancelled = true
            self.countdownValue = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.countdownCancelled = false
            }
        }
    }

    func clearCountdown() {
        DispatchQueue.main.async {
            self.countdownValue = 0
            self.countdownCancelled = false
        }
    }

    // MARK: - Toast
    @Published var showRemoteHint: Bool = false

    func showRemoteControlHint() {
        DispatchQueue.main.async {
            self.showRemoteHint = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                self.showRemoteHint = false
            }
        }
    }
} 