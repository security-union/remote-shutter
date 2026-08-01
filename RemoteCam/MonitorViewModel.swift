import Foundation
import SwiftUI
import Combine

// MARK: - UI State
enum MonitorUIState {
    case photoMode
    case videoMode
    case videoRecording
    case shortsMode
}

// MARK: - Frame Display Model

/// The live-preview frame stream, isolated from the rest of the monitor's
/// state: frames arrive ~20×/sec, and publishing them through the main view
/// model re-rendered every control on each frame (the device menu visibly
/// flickered). Only the preview's `LiveFrameView` observes this.
final class FrameDisplayModel: ObservableObject {
    @Published var cameraImage: UIImage?
}

// MARK: - Monitor View Model
class MonitorViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var currentMode: RecordingMode = .Photo
    @Published var uiState: MonitorUIState = .photoMode
    @Published var isRecording: Bool = false
    /// Live frames — deliberately NOT @Published here; see FrameDisplayModel.
    let frames = FrameDisplayModel()
    @Published var flashStatus: String = ""
    @Published var isFlashEnabled: Bool = false
    @Published var isTorchEnabled: Bool = false
    @Published var buttonPrompt: String = ""
    
    // MARK: - Timer Properties
    @Published var timerValue: Int = 0
    @Published var timerSliderValue: Double = 0 {
        didSet {
            UserDefaults.standard.set(Int(timerSliderValue), forKey: "timerDefault")
        }
    }
    @Published var maxTimerValue: Double = 20
    
    // MARK: - Recording Duration Properties
    @Published var recordingStartTime: Date?
    @Published var isShowingRecordingDuration: Bool = false
    
    // MARK: - Zoom and Lens Properties
    @Published var currentZoomFactor: CGFloat = 1.0
    @Published var maxZoomFactor: CGFloat = 10.0
    @Published var availableLensTypes: [CameraLensType] = [.wideAngle]
    @Published var currentLensType: CameraLensType = .wideAngle
    @Published var zoomStops: [CGFloat] = [1.0]
    @Published var wideAngleZoomFactor: CGFloat = 1.0 // Hardware zoom for "1x" reference

    /// Zoom math for every control on this screen — pinch and the zoom pill. Derived
    /// rather than stored so it can never disagree with the published values it is
    /// built from.
    var zoomScale: ZoomScale {
        ZoomScale(stops: zoomStops,
                  maxZoomFactor: maxZoomFactor,
                  wideAngleZoomFactor: wideAngleZoomFactor)
    }

    // MARK: - Aspect Ratio Properties
    @Published var currentAspectRatio: AspectRatio = .sixteenNine

    // MARK: - Remote Camera Devices (empty = peer predates device selection)
    @Published var remoteCameraDevices: [RemoteCmd.CameraDeviceEntry] = []
    @Published var activeRemoteDeviceID: String?

    // MARK: - Camera Preview Mode (the peer camera's local preview: on / standby)
    /// The connected camera's current local-preview mode, reflected so the
    /// operator can see whether the camera is showing a live preview or sitting
    /// in standby. The standby button icon is a function of this.
    @Published var cameraPreviewMode: CameraPreviewMode = .on

    /// Which switch control the monitor shows for the peer's cameras.
    enum CameraSwitchControl {
        /// One camera — nothing to switch to.
        case hidden
        /// Two usable cameras (or a legacy peer with no device list):
        /// the classic flip button, tap toggles.
        case flipButton
        /// Three or more cameras — or a suspended one worth *seeing* grayed
        /// out: a menu, tap opens the device list.
        case deviceMenu
    }

    static func switchControl(for devices: [RemoteCmd.CameraDeviceEntry]) -> CameraSwitchControl {
        guard !devices.isEmpty else { return .flipButton }   // legacy peer: count unknown
        let healthy = devices.filter { !$0.isSuspended }
        switch (devices.count, healthy.count) {
        case (1, _): return .hidden
        case (2, 2): return .flipButton
        default: return .deviceMenu
        }
    }

    var cameraSwitchControl: CameraSwitchControl {
        Self.switchControl(for: remoteCameraDevices)
    }
    
    // MARK: - Video Transfer Progress Properties
    @Published var isVideoTransferring: Bool = false
    @Published var videoTransferProgress: Double = 0.0 // 0.0 to 1.0
    @Published var videoTransferBytesCompleted: Int64 = 0
    @Published var videoTransferBytesTotal: Int64 = 0
    @Published var videoTransferSpeed: Double = 0.0 // bytes per second
    
    // MARK: - Zoom Controls Watchdog Timer (DispatchSourceTimer for performance)
    
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
    @Published var isQualityControlEnabled: Bool = true
    @Published var areControlsExpanded: Bool = UserDefaults.standard.object(forKey: "areControlsExpanded") == nil
        ? true
        : UserDefaults.standard.bool(forKey: "areControlsExpanded") {
        didSet {
            UserDefaults.standard.set(areControlsExpanded, forKey: "areControlsExpanded")
        }
    }
    
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
            self.isQualityControlEnabled = true
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
            self.isQualityControlEnabled = true
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
            self.isLensControlEnabled = true
            self.isZoomSliderEnabled = true
            self.isQualityControlEnabled = false
            self.buttonPrompt = NSLocalizedString("Stopping video", comment: "")
        }
    }
    
    func configureShortsMode() {
        DispatchQueue.main.async {
            self.uiState = .shortsMode
            self.isRecording = false
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
            self.buttonPrompt = NSLocalizedString("Recording shorts", comment: "")
        }
    }
    
    // MARK: - Update Methods (called from MonitorViewController Actor messages)
    func updateCameraImage(_ image: UIImage?) {
        DispatchQueue.main.async {
            self.frames.cameraImage = image
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
    
    /// Max display zoom (5x relative to wide-angle)
    private static let maxDisplayZoom: CGFloat = 5.0

    func updateZoomFactor(_ factor: CGFloat, maxFactor: CGFloat) {
        DispatchQueue.main.async {
            let maxHardwareZoom = Self.maxDisplayZoom * self.wideAngleZoomFactor
            self.currentZoomFactor = factor
            self.maxZoomFactor = min(maxFactor, maxHardwareZoom)
        }
    }
    
    func updateAvailableLenses(_ lenses: [CameraLensType], current: CameraLensType) {
        DispatchQueue.main.async {
            self.availableLensTypes = lenses
            self.currentLensType = current
        }
    }

    func updateZoomStops(_ stops: [CGFloat], wideAngleZoomFactor: CGFloat) {
        DispatchQueue.main.async {
            self.zoomStops = stops
            self.wideAngleZoomFactor = wideAngleZoomFactor
        }
    }

    func updateAspectRatio(_ ratio: AspectRatio) {
        DispatchQueue.main.async {
            self.currentAspectRatio = ratio
        }
    }

    func updateCameraDevices(_ devices: [RemoteCmd.CameraDeviceEntry], activeID: String?) {
        DispatchQueue.main.async {
            // Capabilities re-broadcasts are frequent (device switches,
            // hot-plug); only publish real changes so the picker menu isn't
            // rebuilt for identical content.
            if self.remoteCameraDevices != devices {
                self.remoteCameraDevices = devices
            }
            if self.activeRemoteDeviceID != activeID {
                self.activeRemoteDeviceID = activeID
            }
        }
    }

    
    // MARK: - Video Quality Properties
    @Published var currentVideoResolution: VideoResolution = .hd1080p
    @Published var currentVideoFrameRate: VideoFrameRate = .fps30
    @Published var supportedResolutions: [VideoResolution] = [.hd1080p]
    @Published var supportedFrameRates: [VideoFrameRate] = [.fps30]
    @Published var resolutionFrameRates: [VideoResolution: [VideoFrameRate]] = [:]

    // MARK: - Photo Quality Properties
    @Published var currentPhotoFormat: PhotoFormat = .jpeg
    @Published var currentHDRMode: HDRMode = .off
    @Published var supportsHEIF: Bool = false
    @Published var supportsHDR: Bool = false

    // MARK: - Video Quality Update Methods
    func updateVideoQuality(resolution: VideoResolution, frameRate: VideoFrameRate) {
        DispatchQueue.main.async {
            self.currentVideoResolution = resolution
            self.currentVideoFrameRate = frameRate
        }
    }

    func updateVideoCapabilities(resolutions: [VideoResolution], frameRates: [VideoFrameRate], resolutionFrameRates: [VideoResolution: [VideoFrameRate]]) {
        DispatchQueue.main.async {
            self.supportedResolutions = resolutions
            self.supportedFrameRates = frameRates
            self.resolutionFrameRates = resolutionFrameRates
        }
    }

    // MARK: - Photo Quality Update Methods
    func updatePhotoQuality(format: PhotoFormat, hdrMode: HDRMode) {
        DispatchQueue.main.async {
            self.currentPhotoFormat = format
            self.currentHDRMode = hdrMode
        }
    }

    func updatePhotoCapabilities(supportsHEIF: Bool, supportsHDR: Bool) {
        DispatchQueue.main.async {
            self.supportsHEIF = supportsHEIF
            self.supportsHDR = supportsHDR
        }
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
    
}
