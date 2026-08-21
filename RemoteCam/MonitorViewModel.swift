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
    /// THE stored screen mode — every mode-dependent surface below (REC dot,
    /// timer visibility, control enables) is a lookup off this one fact, so
    /// they cannot disagree. Leaving the recording mode voids the timer's
    /// start instant with it.
    @Published var uiState: MonitorUIState = .photoMode {
        didSet { if uiState != .videoRecording { recordingElapsedMillis = nil } }
    }
    var isRecording: Bool { uiState == .videoRecording }
    /// Live frames — deliberately NOT @Published here; see FrameDisplayModel.
    let frames = FrameDisplayModel()
    @Published var flashStatus: String = ""
    /// What the monitor is waiting on the camera for, or `nil` when nothing is
    /// in flight. Rendered in place (on the shutter, on the switch glyph)
    /// instead of by a modal that would cover the preview.
    @Published var activity: MonitorActivity?
    /// The frame stream has gone quiet: what is on screen is a stale picture.
    /// Set by the stall watchdog, cleared by the next frame that arrives.
    @Published var isPreviewStale: Bool = false
    @Published var isFlashEnabled: Bool = false
    @Published var isTorchEnabled: Bool = false
    @Published var buttonPrompt: String = ""
    
    // MARK: - Timer Properties
    @Published var timerValue: Int = 0
    @Published var timerSliderValue: Double = 0 {
        didSet {
            TimerPreference.seconds = Int(timerSliderValue)
        }
    }
    @Published var maxTimerValue: Double = 20
    
    // MARK: - Recording Duration Properties
    /// The camera-reported elapsed time (its latest tick) — displayed
    /// VERBATIM, never advanced by a local clock; cleared automatically
    /// whenever `uiState` leaves the recording mode.
    @Published var recordingElapsedMillis: UInt64?
    var isShowingRecordingDuration: Bool { uiState == .videoRecording }
    
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

    /// Mirrored from the hosting controller; picks the dock rail. Size can't
    /// answer that — both landscapes are the same shape.
    @Published var interfaceOrientation: UIInterfaceOrientation = .portrait

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
        self.timerSliderValue = Double(TimerPreference.seconds)
    }
    
    // MARK: - Control State (derived — a lookup off `uiState`, never stored)
    //
    // Every mode-dependent surface reads the one stored mode, so the REC dot,
    // the timer, and the control enables cannot disagree. A mode's whole
    // surface is one row read down this column.
    var isGalleryEnabled: Bool { uiState != .videoRecording }
    var isBackEnabled: Bool { uiState != .videoRecording }
    var isFlashButtonEnabled: Bool { uiState == .photoMode }
    var isTorchButtonEnabled: Bool { true }
    var isSettingsEnabled: Bool { uiState != .videoRecording }
    var isToggleCameraEnabled: Bool { uiState != .videoRecording }
    var isTimerSliderEnabled: Bool { uiState == .photoMode || uiState == .videoMode }
    var isSegmentedControlEnabled: Bool { uiState != .videoRecording }
    var isLensControlEnabled: Bool { true }
    var isZoomSliderEnabled: Bool { true }
    var isQualityControlEnabled: Bool { uiState == .photoMode || uiState == .videoMode }

    /// The shutter's idle label for a mode. `buttonPrompt` itself stays
    /// stored because the self-timer countdown overwrites it with the
    /// remaining seconds, then restores it from this same lookup.
    static func prompt(for state: MonitorUIState) -> String {
        switch state {
        case .photoMode: return NSLocalizedString("Taking photo", comment: "")
        case .videoMode: return NSLocalizedString("Starting video", comment: "")
        case .videoRecording: return NSLocalizedString("Stopping video", comment: "")
        case .shortsMode: return NSLocalizedString("Recording shorts", comment: "")
        }
    }

    // MARK: - UI Configuration Methods
    func configurePhotoMode() { setUIState(.photoMode) }
    func configureVideoMode() { setUIState(.videoMode) }
    func configureVideoRecording() { setUIState(.videoRecording) }
    func configureShortsMode() { setUIState(.shortsMode) }

    /// Synchronous on purpose: every caller is already on main (the presenter
    /// hops before rendering; the view controller's lifecycle is main). Every
    /// write on this path must take the SAME number of main hops — an extra
    /// dispatch would let a stale mode change land after a later-sent write
    /// and reorder the screen.
    private func setUIState(_ state: MonitorUIState) {
        dispatchPrecondition(condition: .onQueue(.main))
        uiState = state
        buttonPrompt = Self.prompt(for: state)
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
    
    func updateZoomFactor(_ factor: CGFloat, maxFactor: CGFloat) {
        DispatchQueue.main.async {
            self.currentZoomFactor = factor
            self.maxZoomFactor = ZoomScaleSeed.clampMaxZoom(maxFactor, wideAngle: self.wideAngleZoomFactor)
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
    /// Whether the peer advertised the `supports_preview_mode` capability. Gates
    /// the standby tray tile — an older camera ignores the command, so offering
    /// a control that does nothing would be worse than hiding it.
    @Published var supportsCameraStandby: Bool = false
    /// Whether the peer's ACTIVE camera can do manual exposure. Gates the
    /// exposure control — absent, not disabled, when the camera can't.
    @Published var supportsManualExposure: Bool = false
    /// The camera's echoed exposure truth (mode, shutter, ISO, ranges). The
    /// monitor renders only this, never the value it last dragged to.
    @Published var exposure: ExposureState?

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
