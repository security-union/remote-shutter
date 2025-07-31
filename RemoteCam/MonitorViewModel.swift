import Foundation
import SwiftUI
import Combine

// MARK: - UI State
enum MonitorUIState {
    case photoMode
    case videoMode
    case videoRecording
    case shortsMode
    case shortsRecording
    case shortsPreview
}

// MARK: - Monitor View Model
class MonitorViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var currentMode: RecordingMode = .Photo
    @Published var uiState: MonitorUIState = .photoMode
    @Published var isRecording: Bool = false
    @Published var cameraImage: UIImage?
    @Published var flashStatus: String = ""
    @Published var isFlashEnabled: Bool = false
    @Published var isTorchEnabled: Bool = false
    @Published var buttonPrompt: String = ""
    
    // MARK: - Timer Properties
    @Published var timerValue: Int = 0
    @Published var timerSliderValue: Double = 0 {
        didSet {
            UserDefaults.standard.set(Int(timerSliderValue), forKey: "timerDefault")
            UserDefaults.standard.synchronize()
        }
    }
    @Published var maxTimerValue: Double = 10
    
    // MARK: - Recording Duration Properties
    @Published var recordingStartTime: Date?
    @Published var isShowingRecordingDuration: Bool = false
    
    // MARK: - Zoom and Lens Properties
    @Published var currentZoomFactor: CGFloat = 1.0
    @Published var maxZoomFactor: CGFloat = 10.0
    @Published var availableLensTypes: [CameraLensType] = [.wideAngle]
    @Published var currentLensType: CameraLensType = .wideAngle
    @Published var showZoomControls: Bool = false
    
    // MARK: - Video Transfer Progress Properties
    @Published var isVideoTransferring: Bool = false
    @Published var videoTransferProgress: Double = 0.0 // 0.0 to 1.0
    @Published var videoTransferBytesCompleted: Int64 = 0
    @Published var videoTransferBytesTotal: Int64 = 0
    @Published var videoTransferSpeed: Double = 0.0 // bytes per second
    
    // MARK: - Shorts Mode Properties
    @Published var shortsSession: ShortsSession?
    @Published var selectedShortsConfig: ShortsConfig = .thirtySeconds
    @Published var isInShortsMode: Bool = false
    @Published var shortsPreviewClip: ShortsClip?
    @Published var shortsPlaybackTime: TimeInterval = 0
    @Published var shortsClipTransferProgress: [UUID: Double] = [:]
    
    // MARK: - Zoom Controls Watchdog Timer (DispatchSourceTimer for performance)
    private var zoomControlsWatchdog: DispatchSourceTimer?
    
    // MARK: - Initializer
    init() {
        // Load timer value from UserDefaults
        self.timerSliderValue = Double(UserDefaults.standard.integer(forKey: "timerDefault"))
    }
    
    // MARK: - Control State
    @Published var isGalleryEnabled: Bool = true
    @Published var isBackEnabled: Bool = true
    @Published var isFlashButtonEnabled: Bool = true
    @Published var isTorchButtonEnabled: Bool = true
    @Published var isSettingsEnabled: Bool = true
    @Published var isToggleCameraEnabled: Bool = true
    @Published var isTimerSliderEnabled: Bool = true
    @Published var isSegmentedControlEnabled: Bool = true
    @Published var isLensControlEnabled: Bool = true
    @Published var isZoomSliderEnabled: Bool = true
    
    // MARK: - UI Configuration Methods
    func configurePhotoMode() {
        DispatchQueue.main.async {
            self.uiState = .photoMode
            self.isRecording = false
            self.isGalleryEnabled = true
            self.isBackEnabled = true
            self.isFlashButtonEnabled = true
            self.isTorchButtonEnabled = true
            self.isSettingsEnabled = true
            self.isToggleCameraEnabled = true
            self.isTimerSliderEnabled = true
            self.isSegmentedControlEnabled = true
            self.isLensControlEnabled = true
            self.isZoomSliderEnabled = true
            self.buttonPrompt = NSLocalizedString("Taking photo", comment: "")
        }
    }
    
    func configureVideoMode() {
        DispatchQueue.main.async {
            self.uiState = .videoMode
            self.isRecording = false
            self.recordingStartTime = nil
            self.isShowingRecordingDuration = false
            self.isGalleryEnabled = true
            self.isBackEnabled = true
            self.isFlashButtonEnabled = false
            self.isTorchButtonEnabled = true
            self.isSettingsEnabled = true
            self.isToggleCameraEnabled = true
            self.isTimerSliderEnabled = true
            self.isSegmentedControlEnabled = true
            self.isLensControlEnabled = true
            self.isZoomSliderEnabled = true
            self.buttonPrompt = NSLocalizedString("Starting video", comment: "")
        }
    }
    
    func configureVideoRecording() {
        DispatchQueue.main.async {
            self.uiState = .videoRecording
            self.isRecording = true
            self.recordingStartTime = Date()
            self.isShowingRecordingDuration = true
            self.isGalleryEnabled = false
            self.isBackEnabled = false
            self.isFlashButtonEnabled = false
            self.isTorchButtonEnabled = true
            self.isSettingsEnabled = false
            self.isToggleCameraEnabled = false
            self.isTimerSliderEnabled = false
            self.isSegmentedControlEnabled = false
            self.isLensControlEnabled = false
            self.isZoomSliderEnabled = false
            self.buttonPrompt = NSLocalizedString("Stopping video", comment: "")
        }
    }
    
    func configureShortsMode() {
        DispatchQueue.main.async {
            self.uiState = .shortsMode
            self.isRecording = false
            self.isInShortsMode = true
            self.shortsSession = ShortsSession(config: self.selectedShortsConfig)
            self.isGalleryEnabled = true
            self.isBackEnabled = true
            self.isFlashButtonEnabled = false
            self.isTorchButtonEnabled = true
            self.isSettingsEnabled = true
            self.isToggleCameraEnabled = true
            self.isTimerSliderEnabled = false // Shorts will have its own duration controls
            self.isSegmentedControlEnabled = true
            self.isLensControlEnabled = true
            self.isZoomSliderEnabled = true
            self.buttonPrompt = NSLocalizedString("Ready to record shorts", comment: "")
        }
    }
    
    func configureShortsRecording() {
        DispatchQueue.main.async {
            self.uiState = .shortsRecording
            self.isRecording = true
            self.isGalleryEnabled = false
            self.isBackEnabled = false
            self.isSettingsEnabled = false
            self.isToggleCameraEnabled = false
            self.isSegmentedControlEnabled = false
            self.shortsSession?.state = .recording
            self.buttonPrompt = NSLocalizedString("Recording clip...", comment: "")
        }
    }
    
    func configureShortsPreview() {
        DispatchQueue.main.async {
            self.uiState = .shortsPreview
            self.isRecording = false
            self.isGalleryEnabled = true
            self.isBackEnabled = true
            self.isSettingsEnabled = true
            self.shortsSession?.state = .previewing
            self.buttonPrompt = NSLocalizedString("Previewing shorts", comment: "")
        }
    }
    
    // MARK: - Shorts Session Management
    
    func startShortsSession(with config: ShortsConfig) {
        DispatchQueue.main.async {
            self.selectedShortsConfig = config
            self.shortsSession = ShortsSession(config: config)
            self.isInShortsMode = true
        }
    }
    
    func exitShortsMode() {
        DispatchQueue.main.async {
            self.isInShortsMode = false
            self.shortsSession = nil
            self.shortsPreviewClip = nil
            self.shortsPlaybackTime = 0
            self.shortsClipTransferProgress.removeAll()
            // Return to photo mode by default
            self.configurePhotoMode()
        }
    }
    
    func updateShortsClipTransferProgress(clipId: UUID, progress: Double) {
        DispatchQueue.main.async {
            self.shortsClipTransferProgress[clipId] = progress
        }
    }
    
    // MARK: - Update Methods (called from MonitorViewController Actor messages)
    func updateCameraImage(_ image: UIImage?) {
        DispatchQueue.main.async {
            self.cameraImage = image
        }
    }
    
    func updateFlashStatus(_ status: String, isEnabled: Bool) {
        DispatchQueue.main.async {
            self.flashStatus = status
            self.isFlashEnabled = isEnabled
        }
    }
    
    func updateTorchStatus(_ isEnabled: Bool) {
        DispatchQueue.main.async {
            self.isTorchEnabled = isEnabled
        }
    }
    
    func updateZoomFactor(_ factor: CGFloat, maxFactor: CGFloat) {
        DispatchQueue.main.async {
            self.currentZoomFactor = factor
            self.maxZoomFactor = maxFactor
        }
    }
    
    func updateAvailableLenses(_ lenses: [CameraLensType], current: CameraLensType) {
        DispatchQueue.main.async {
            self.availableLensTypes = lenses
            self.currentLensType = current
        }
    }
    
    func showZoomControlsTemporarily() {
        // Show controls immediately (already on main thread from SwiftUI)
        showZoomControls = true
        
        // Create timer only once, then reuse by resetting deadline
        if zoomControlsWatchdog == nil {
            zoomControlsWatchdog = DispatchSource.makeTimerSource(queue: .main)
            zoomControlsWatchdog?.setEventHandler { [weak self] in
                self?.showZoomControls = false
            }
            zoomControlsWatchdog?.resume()
        }
        
        // Reset the timer deadline (much faster than recreating)
        zoomControlsWatchdog?.schedule(deadline: .now() + 0.5)
    }
    
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
    
    deinit {
        // Clean up timer on deinit
        zoomControlsWatchdog?.cancel()
        zoomControlsWatchdog = nil
    }
} 