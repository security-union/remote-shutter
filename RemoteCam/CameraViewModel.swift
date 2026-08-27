import Foundation
import SwiftUI
import Combine
import AVFoundation

// MARK: - Camera View Model
class CameraViewModel: ObservableObject {
    // MARK: - Screen Chrome (CameraScreenView)
    // All set from the main thread by CameraRig and its shell.
    /// The live capture session, published once the engine has configured it.
    @Published var previewSession: AVCaptureSession?
    @Published var previewVideoOrientation: AVCaptureVideoOrientation = .portrait
    /// The animated "recording" badge — visible while in video mode.
    @Published var isRecordingIndicatorVisible = false
    @Published var recordingStartTime: Date?
    @Published var isRecordingTimerActive = false
    /// Spinner shown while the capture session is being configured.
    @Published var isBusy = false

    // MARK: - Local Preview Mode (on / standby)
    /// The camera's own preview mode. `.standby` renders the minimal status
    /// screen instead of the live preview; the capture session and the frames
    /// streamed to the monitor keep running either way. Seeded from the
    /// persisted preference and updated by `CameraRig`.
    @Published var previewMode: CameraPreviewMode = .on
    /// The connected monitor's display name, shown on the standby screen so the
    /// operator knows who is driving the camera. Nil when no peer is connected.
    @Published var connectedPeerName: String?

    /// On the camera screen with the remote's link down: shows the reconnect
    /// chip and — while recording — the on-camera stop button (the escape
    /// hatch). Exactly two writers, both in the coordinator: the drop sets
    /// it, the rebind clears it.
    @Published var isAwaitingRemoteReconnect = false

    /// Main-thread setter for the connected peer's name (called from the rig /
    /// coordinator glue, which may be off-main).
    func setConnectedPeerName(_ name: String?) {
        DispatchQueue.main.async {
            if self.connectedPeerName != name { self.connectedPeerName = name }
        }
    }

    /// Main-thread setter for the local preview mode.
    func setPreviewMode(_ mode: CameraPreviewMode) {
        DispatchQueue.main.async {
            if self.previewMode != mode { self.previewMode = mode }
        }
    }

    // MARK: - Local Camera Devices (picker chrome; a Mac has N cameras)
    @Published var availableCameraDevices: [CameraDeviceDescriptor] = []
    @Published var activeCameraDeviceID: String?

    func updateCameraDevices(_ devices: [CameraDeviceDescriptor], activeID: String?) {
        DispatchQueue.main.async {
            // Refreshes are frequent (Continuity cameras flap as the phone
            // locks/idles); only publish real changes so the picker menu
            // isn't rebuilt for identical content.
            if self.availableCameraDevices != devices {
                self.availableCameraDevices = devices
            }
            if self.activeCameraDeviceID != activeID {
                self.activeCameraDeviceID = activeID
            }
        }
    }

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
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isVideoTransferring = false
            self.videoTransferProgress = 1.0
            self.videoTransferSpeed = 0.0

            // Hide the progress after a brief delay to show completion
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.videoTransferProgress = 0.0
                self?.videoTransferBytesCompleted = 0
                self?.videoTransferBytesTotal = 0
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
    private var cancelGeneration: Int = 0

    // MARK: - Timer Countdown Methods
    func showCountdown(_ value: Int) {
        DispatchQueue.main.async {
            self.countdownCancelled = false
            self.countdownValue = value
        }
    }

    func cancelCountdown() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.countdownCancelled = true
            self.countdownValue = 0
            self.cancelGeneration += 1
            let expectedGeneration = self.cancelGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.cancelGeneration == expectedGeneration else { return }
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

    // MARK: - Pro-controls readout
    /// What the remote is driving, shown as a chip on the preview so the
    /// person holding the camera can see it ("M 1/125 · ISO 400 · f/2.8").
    /// nil when everything is automatic.
    @Published var proReadout: String?

    private var exposureReadoutText: String?
    private var cinematicReadoutText: String?

    func updateExposureReadout(_ state: ExposureState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.exposureReadoutText = state.mode == .manual
                ? "M \(ProStops.shutterLabel(state.durationSeconds)) · \(ProStops.isoLabel(state.iso))"
                : nil
            self.recomposeProReadout()
        }
    }

    func updateCinematicReadout(_ state: CinematicState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.cinematicReadoutText = state.enabled
                ? "CINEMATIC \(ProStops.apertureLabel(state.simulatedAperture))"
                : nil
            self.recomposeProReadout()
        }
    }

    private func recomposeProReadout() {
        let parts = [exposureReadoutText, cinematicReadoutText].compactMap { $0 }
        proReadout = parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Remote Focus Indicator
    /// Shown when a remote focus command arrives, so the person holding the
    /// camera sees the tap register — the same reticle the monitor draws.
    /// `normalized` is 0..1 in the upright display image (origin top-left).
    @Published var focusIndicator: RemoteFocusIndicator?

    struct RemoteFocusIndicator: Equatable {
        let id = UUID()
        let normalized: CGPoint
    }

    func showRemoteFocus(x: Float, y: Float) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let indicator = RemoteFocusIndicator(normalized: CGPoint(x: CGFloat(x), y: CGFloat(y)))
            self.focusIndicator = indicator
            // Match the monitor reticle's lifetime.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                if self?.focusIndicator?.id == indicator.id { self?.focusIndicator = nil }
            }
        }
    }

    // MARK: - Toast
    @Published var showRemoteHint: Bool = false
    private var remoteHintWorkItem: DispatchWorkItem?

    func showRemoteControlHint() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.remoteHintWorkItem?.cancel()
            self.showRemoteHint = true
            let workItem = DispatchWorkItem { [weak self] in
                self?.showRemoteHint = false
            }
            self.remoteHintWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: workItem)
        }
    }
}