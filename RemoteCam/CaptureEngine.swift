//
//  CaptureEngine.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union. All rights reserved.
//

import UIKit
import AVFoundation

/// Owns the `AVCaptureSession` and every still-photo / configuration concern for
/// the camera device: device selection, zoom, lens switching, torch, flash,
/// video/photo quality, aspect ratio and photo capture. It knows nothing about
/// views, layers or the actor system — the `CameraRig` wires the recording
/// pipeline and frame streaming around it and forwards captured photos to the
/// session actor via the `onPicture` callback.
final class CaptureEngine: NSObject, AVCapturePhotoCaptureDelegate {

    /// The single owner of all session/device configuration and engine control
    /// state. Public entry points hop here with `.sync` (callers on the actor
    /// mailbox or main); nothing on this queue ever `.sync`s back out, so no
    /// cycle can form.
    let sessionQueue = DispatchQueue(label: "camera session queue", attributes: [], target: nil)

    let captureSession: AVCaptureSession = AVCaptureSession()
    let audioDataOutput = AVCaptureAudioDataOutput()

    let videoDataOutput = AVCaptureVideoDataOutput()
    /// Delivery queue for BOTH the video and audio sample-buffer delegates —
    /// one queue so `processFrame` is naturally serialized — and the home of
    /// all recording state in `RecordingPipeline`.
    let dataOutputQueue = DispatchQueue(
        label: "camera data output queue", attributes: [], target: nil)
    let photoOutput = AVCapturePhotoOutput()
    let cameraSettings = AVCapturePhotoSettings()
    var videoConnection: AVCaptureConnection?
    var audioConnection: AVCaptureConnection?
    var videoDeviceInput: AVCaptureDeviceInput!

    /// The active camera position, mirrored for the frame streamer's per-frame
    /// reads (everything else about the device is sessionQueue-confined).
    let currentPositionShared = Locked(AVCaptureDevice.Position.back)

    /// Orientation the engine last applied to the output/photo connections.
    /// The `CameraRig` keeps its own `orientation` for the preview and
    /// passes it in via `rotateOutputs`.
    var orientation: UIInterfaceOrientation = UIInterfaceOrientation.portrait
    var currentVideoResolution: VideoResolution = .hd1080p
    var currentVideoFrameRate: VideoFrameRate = .fps30
    var currentPhotoFormat: PhotoFormat = .jpeg
    var currentHDRMode: HDRMode = .off

    // MARK: - Zoom and Lens Properties
    private var currentZoomFactor: CGFloat = 1.0
    private var currentLensType: CameraLensType = .wideAngle
    private var availableLensTypes: [CameraLensType] = []
    private var zoomStops: [CGFloat] = [1.0]

    // MARK: - Camera Capabilities
    private var frontCameraInfo: RemoteCmd.CameraInfo?
    private var backCameraInfo: RemoteCmd.CameraInfo?

    // MARK: - Aspect Ratio
    var currentAspectRatio: AspectRatio = .sixteenNine

    // MARK: - Callbacks to the view controller
    /// Forwards a finished photo capture. `(data, nil)` on success, `(nil, error)`
    /// on failure. The VC relays this to the session actor exactly as before.
    var onPicture: ((Data?, Error?) -> Void)?
    /// Fired whenever camera status (resolution/frame rate/format/HDR) changes so
    /// the VC can refresh its status overlay.
    var onStatusChanged: (() -> Void)?

    // MARK: - Setup

    /// Configures the capture session on `sessionQueue` and starts it, then
    /// calls `completion` on main with whether a camera device was available
    /// (the caller skips preview publishing when it wasn't). Runs off the main
    /// thread, so the caller's busy spinner can actually render during setup.
    func setupCamera(sampleBufferDelegate: AVCaptureVideoDataOutputSampleBufferDelegate & AVCaptureAudioDataOutputSampleBufferDelegate,
                     completion: @escaping (Bool) -> Void) {
        sessionQueue.async {
            let hasCamera = self.setupCameraLocked(sampleBufferDelegate: sampleBufferDelegate)
            DispatchQueue.main.async {
                completion(hasCamera)
            }
        }
    }

    private func setupCameraLocked(sampleBufferDelegate: AVCaptureVideoDataOutputSampleBufferDelegate & AVCaptureAudioDataOutputSampleBufferDelegate) -> Bool {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        self.cameraSettings.isHighResolutionPhotoEnabled = true
        self.videoDataOutput.setSampleBufferDelegate(sampleBufferDelegate, queue: self.dataOutputQueue)
        self.videoDataOutput.videoSettings =
            [kCVPixelBufferPixelFormatTypeKey: Int(kCVPixelFormatType_32BGRA)] as [String: Any]
        self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
        if self.captureSession.isRunning {
            self.captureSession.stopRunning()
        }
        self.captureSession.beginConfiguration()
        self.captureSession.sessionPreset = .high

        guard let videoDevice = preferredCamera(for: .back) ?? AVCaptureDevice.default(for: AVMediaType.video) else {
            self.captureSession.commitConfiguration()
            return false
        }
        debugLog("🔍 SETUP CAMERA: using device=\(videoDevice.localizedName) type=\(videoDevice.deviceType.rawValue) isVirtual=\(!videoDevice.virtualDeviceSwitchOverVideoZoomFactors.isEmpty)")

        do {
            self.videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            self.captureSession.addInput(self.videoDeviceInput)
            self.captureSession.addOutput(self.videoDataOutput)

            try self.setFrameRate(framerate: fpsSetting.value, videoDevice: videoDevice)

            // Gather complete camera capabilities for both front and back cameras
            self.gatherAllCameraCapabilitiesLocked()

            // Initialize current state
            self.updateAvailableLensTypes(for: videoDevice.position)
            self.zoomStops = self.discoverZoomStops(for: videoDevice)
            self.currentPositionShared.value = videoDevice.position

            // Start at the wide-angle zoom factor (matches native Camera app "1x")
            let wideZoom = self.wideAngleZoomFactor(for: videoDevice)
            if wideZoom > 1.0 {
                try videoDevice.lockForConfiguration()
                videoDevice.videoZoomFactor = wideZoom
                videoDevice.unlockForConfiguration()
            }
            self.currentZoomFactor = videoDevice.videoZoomFactor

            // Audio setup will be done only when starting video recording
            // This prevents requesting microphone permission upfront
            self.configSessionOutput()
            self.captureSession.commitConfiguration()
            self.applyDesiredTorchLocked()   // commitConfiguration can reset the torch
            self.captureSession.startRunning()
        } catch let error as NSError {
            print("error \(error)")
        }
        return true
    }

    /// Adds the audio input/output for video recording — the config half of
    /// record-start, kept on `sessionQueue` (the pipeline's data-queue work
    /// syncs in here once, then continues on its own queue).
    func configureAudioForRecording(delegate: AVCaptureAudioDataOutputSampleBufferDelegate) -> Bool {
        sessionQueue.sync {
            do {
                guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
                    return false
                }
                let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)

                captureSession.beginConfiguration()
                if captureSession.canAddInput(audioDeviceInput) {
                    captureSession.addInput(audioDeviceInput)
                } else {
                    print("Could not add audio device input to the session")
                }
                if captureSession.canAddOutput(audioDataOutput) {
                    captureSession.addOutput(audioDataOutput)
                    audioDataOutput.setSampleBufferDelegate(delegate, queue: dataOutputQueue)
                }
                captureSession.commitConfiguration()

                // Restore the user's torch preference — iOS resets the torch on commitConfiguration.
                applyDesiredTorchLocked()

                audioConnection = audioDataOutput.connection(with: .audio)
                return true
            } catch {
                print("Error setting up audio for video recording: \(error)")
                return false
            }
        }
    }

    /// Stops the capture session (screen teardown).
    func stopSession() {
        sessionQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }

    func toggleCamera(orientation: UIInterfaceOrientation) -> Try<(AVCaptureDevice.FlashMode?, AVCaptureDevice.Position)> {
        sessionQueue.sync {
            do {
                let captureSession = self.captureSession
                captureSession.beginConfiguration()
                let device = self.videoDeviceInput?.device
                let newPosition = device?.position.toggle().toOptional()
                let newDevice = cameraForPosition(position: newPosition!)
                let newInput = try AVCaptureDeviceInput(device: newDevice!)
                captureSession.removeInput(self.videoDeviceInput)
                captureSession.addInput(newInput)
                self.videoDeviceInput = newInput
                configSessionOutput()
                try setFrameRate(framerate: fpsSetting.value, videoDevice: newDevice!)

                // Update available lens types and zoom stops for new camera position
                self.updateAvailableLensTypes(for: newPosition!)
                self.zoomStops = self.discoverZoomStops(for: newDevice!)
                self.currentPositionShared.value = newInput.device.position

                do {
                    self.rotateOutputsLocked(orientation: orientation)
                    let newFlashMode: AVCaptureDevice.FlashMode? = (newInput.device.hasFlash) ? self.cameraSettings.flashMode : nil
                    captureSession.commitConfiguration()
                    self.applyDesiredTorchLocked()   // restore torch onto the new camera (no-op if it has none)

                    // Camera capabilities are now sent via RemoteCmd.ToggleCameraResp in CamStates.swift
                    // No need to send separate capabilities message here

                    return Success((newFlashMode, newInput.device.position))
                }
            } catch let error as NSError {
                return Failure(error: error)
            }
        }
    }

    private func configSessionOutput() {
        self.captureSession.beginConfiguration()
        captureSession.removeOutput(videoDataOutput)
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        } else {
            print("Could not add still image output to the session")
            return
        }

        captureSession.removeOutput(photoOutput)
        if captureSession.canAddOutput(photoOutput) {
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.maxPhotoQualityPrioritization = .quality
            captureSession.addOutput(photoOutput)
        } else {
            print("Could not add movie file output to the session")
            return
        }
        videoConnection = videoDataOutput.connection(with: .video)
        audioConnection = audioDataOutput.connection(with: .audio)
        self.captureSession.commitConfiguration()
    }

    func toggleFlash() -> Try<AVCaptureDevice.FlashMode> {
        sessionQueue.sync {
            let genericDevice = self.videoDeviceInput
            let device = genericDevice?.device
            if let hasFlash = device?.hasFlash, hasFlash {
                let newFlashMode = self.cameraSettings.flashMode.next()
                self.cameraSettings.flashMode = newFlashMode
                return Success(newFlashMode)
            } else {
                return Failure(error: NSError(domain: "Current camera does not support flash.", code: 0, userInfo: nil))
            }
        }
    }

    // MARK: - Torch Methods for Video Recording
    func toggleTorch() -> Try<AVCaptureDevice.TorchMode> {
        sessionQueue.sync { toggleTorchLocked() }
    }

    private func toggleTorchLocked() -> Try<AVCaptureDevice.TorchMode> {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        let genericDevice = self.videoDeviceInput
        let device = genericDevice?.device
        if let hasTorch = device?.hasTorch, hasTorch {
            do {
                try device?.lockForConfiguration()
                let currentTorchMode = device?.torchMode ?? .off
                let newTorchMode: AVCaptureDevice.TorchMode

                switch currentTorchMode {
                case .off:
                    newTorchMode = .on
                case .on:
                    newTorchMode = .off
                case .auto:
                    newTorchMode = .off
                @unknown default:
                    newTorchMode = .off
                }

                device?.torchMode = newTorchMode
                device?.unlockForConfiguration()
                desiredTorchOnStorage = newTorchMode == .on
                return Success(newTorchMode)
            } catch let error as NSError {
                return Failure(error: error)
            }
        } else {
            return Failure(error: NSError(domain: "Current camera does not support torch.", code: 0, userInfo: nil))
        }
    }

    func setTorchMode(mode: AVCaptureDevice.TorchMode) -> Try<AVCaptureDevice.TorchMode> {
        sessionQueue.sync { setTorchModeLocked(mode: mode) }
    }

    private func setTorchModeLocked(mode: AVCaptureDevice.TorchMode) -> Try<AVCaptureDevice.TorchMode> {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        let genericDevice = self.videoDeviceInput
        let device = genericDevice?.device
        if let hasTorch = device?.hasTorch, hasTorch {
            do {
                try device?.lockForConfiguration()
                device?.torchMode = mode
                device?.unlockForConfiguration()
                desiredTorchOnStorage = mode == .on
                return Success(mode)
            } catch let error as NSError {
                return Failure(error: error)
            }
        } else {
            return Failure(error: NSError(domain: "Current camera does not support torch.", code: 0, userInfo: nil))
        }
    }

    // MARK: - Torch Intent

    /// The single source of truth for whether the user wants the torch on. Set only by the
    /// user-facing torch controls (`toggleTorch` / `setTorchMode`); the countdown strobe
    /// drives the hardware directly and never touches this, so it survives a countdown.
    /// sessionQueue-confined storage; the public getter hops for outside readers.
    private var desiredTorchOnStorage = false
    var desiredTorchOn: Bool {
        sessionQueue.sync { desiredTorchOnStorage }
    }

    /// Clears the user's torch intent (screen teardown). Called by the rig's `ensureTorchOff`.
    func clearTorchIntent() {
        sessionQueue.sync { desiredTorchOnStorage = false }
    }

    /// Applies `desiredTorchOn` to the hardware. Reused to restore the torch after any
    /// event that resets it (rotation, session reconfiguration, timer countdown).
    func applyDesiredTorch() {
        sessionQueue.sync { applyDesiredTorchLocked() }
    }

    private func applyDesiredTorchLocked() {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard let device = videoDeviceInput?.device, device.hasTorch else { return }
        let mode: AVCaptureDevice.TorchMode = desiredTorchOnStorage ? .on : .off
        guard device.torchMode != mode else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = mode
            device.unlockForConfiguration()
        } catch {}
    }

    /// The active capture device, for callers outside the session queue (the
    /// rig's countdown torch). The device object itself is thread-safe to hold.
    func currentDevice() -> AVCaptureDevice? {
        sessionQueue.sync { videoDeviceInput?.device }
    }

    /// Whether the torch is currently lit (protocol surface for the states).
    func isTorchActive() -> Bool {
        sessionQueue.sync { videoDeviceInput?.device.isTorchActive ?? false }
    }

    /// The flash mode the next photo will use (protocol surface for the states).
    func currentFlashModeValue() -> AVCaptureDevice.FlashMode {
        sessionQueue.sync { cameraSettings.flashMode }
    }

    /// Snapshot of the status-overlay fields, for the rig's view-model update
    /// from any thread.
    func statusSnapshot() -> (VideoResolution, VideoFrameRate, PhotoFormat, HDRMode) {
        sessionQueue.sync {
            (currentVideoResolution, currentVideoFrameRate, currentPhotoFormat, currentHDRMode)
        }
    }

    // MARK: - Virtual Device Preference

    /// Returns the best camera device for the given position, preferring virtual devices.
    /// Virtual devices automatically switch between physical cameras at appropriate zoom factors.
    func preferredCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if let triple = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: position) {
            return triple
        }
        if let dualWide = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: position) {
            return dualWide
        }
        if let dual = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: position) {
            return dual
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    /// Discovers hardware zoom stop factors from a virtual device's switchOverVideoZoomFactors.
    ///
    /// For builtInTripleCamera: base (1.0) = ultra-wide, switchovers e.g. [2.0, 6.0]
    /// - Hardware 1.0 = ultra-wide (displayed as "0.5x" by dividing by wideAngleZoomFactor)
    /// - Hardware 2.0 = wide-angle (displayed as "1x")
    /// - Hardware 6.0 = telephoto (displayed as "3x")
    func discoverZoomStops(for device: AVCaptureDevice) -> [CGFloat] {
        if device.position == .front {
            return [1.0]
        }

        let switchOverFactors = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        debugLog("🔍 ZOOM STOPS: device=\(device.localizedName) switchOverFactors=\(switchOverFactors) minZoom=\(device.minAvailableVideoZoomFactor) maxZoom=\(device.maxAvailableVideoZoomFactor)")

        // Start with the base (1.0) which is the widest constituent camera
        var stops: [CGFloat] = [device.minAvailableVideoZoomFactor]

        // Add each switchover factor
        for f in switchOverFactors {
            if !stops.contains(f) {
                stops.append(f)
            }
        }

        // If no switchover factors, this is a single camera — just return [1.0]
        if switchOverFactors.isEmpty && stops == [1.0] {
            return [1.0]
        }

        let result = stops.sorted()
        debugLog("🔍 ZOOM STOPS: final=\(result)")
        return result
    }

    /// Returns the hardware zoom factor that corresponds to the wide-angle camera.
    /// For virtual devices with ultra-wide base, this is the first switchover factor.
    /// For single cameras or dual (wide+telephoto), this is 1.0.
    func wideAngleZoomFactor(for device: AVCaptureDevice) -> CGFloat {
        let switchOverFactors = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        // If there are switchover factors and the base zoom < 1.5 (i.e., ultra-wide is base),
        // the first switchover is where the wide-angle starts
        if let first = switchOverFactors.first, device.minAvailableVideoZoomFactor < 1.5 {
            return first
        }
        return 1.0
    }

    func cameraForPosition(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        return preferredCamera(for: position)
    }

    func getAllDeviceTypes() -> [AVCaptureDevice.DeviceType] {
        var deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInDualCamera,
            .builtInTelephotoCamera
        ]

        if #available(iOS 13.0, *) {
            deviceTypes.append(.builtInUltraWideCamera)
            deviceTypes.append(.builtInTripleCamera)
        }

        return deviceTypes
    }

    func updateAvailableLensTypes(for position: AVCaptureDevice.Position) {
        let deviceTypes = getAllDeviceTypes()
        let videoDevices = AVCaptureDevice.DiscoverySession.init(
                deviceTypes: deviceTypes,
                mediaType: .video, position: position).devices

        availableLensTypes = CameraLensType.allCases.filter { lensType in
            return videoDevices.contains { $0.deviceType == lensType.deviceType }
        }
    }

    // MARK: - Camera Capabilities Gathering
    func gatherAllCameraCapabilities() {
        sessionQueue.sync { gatherAllCameraCapabilitiesLocked() }
    }

    private func gatherAllCameraCapabilitiesLocked() {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        debugLog("🔍 DEBUG: gatherAllCameraCapabilities called")

        // Gather front camera capabilities
        frontCameraInfo = gatherCameraInfo(for: .front)
        debugLog("🔍 DEBUG: Front camera info: \(frontCameraInfo != nil ? "available" : "nil")")

        // Gather back camera capabilities
        backCameraInfo = gatherCameraInfo(for: .back)
        debugLog("🔍 DEBUG: Back camera info: \(backCameraInfo != nil ? "available" : "nil")")

        if let backInfo = backCameraInfo {
            debugLog("🔍 DEBUG: - Back camera available lenses: \(backInfo.availableLenses)")
            debugLog("🔍 DEBUG: - Back camera has flash: \(backInfo.hasFlash)")
        }

        if let frontInfo = frontCameraInfo {
            debugLog("🔍 DEBUG: - Front camera available lenses: \(frontInfo.availableLenses)")
            debugLog("🔍 DEBUG: - Front camera has flash: \(frontInfo.hasFlash)")
        }
    }

    func gatherCameraInfo(for position: AVCaptureDevice.Position) -> RemoteCmd.CameraInfo? {
        let positionName = position == .front ? "Front" : "Back"
        debugLog("🔍 DEBUG: gatherCameraInfo for \(positionName) camera")

        let deviceTypes = getAllDeviceTypes()
        let videoDevices = AVCaptureDevice.DiscoverySession.init(
                deviceTypes: deviceTypes,
                mediaType: .video, position: position).devices

        debugLog("🔍 DEBUG: - Found \(videoDevices.count) devices for \(positionName) position")
        for device in videoDevices {
            debugLog("🔍 DEBUG: - \(device.localizedName) (\(device.deviceType.rawValue))")
        }

        guard !videoDevices.isEmpty else {
            debugLog("🔍 DEBUG: - No devices found for \(positionName) position")
            return nil
        }

        // Find available lens types for this position
        let availableLenses = CameraLensType.allCases.filter { lensType in
            return videoDevices.contains { $0.deviceType == lensType.deviceType }
        }

        debugLog("🔍 DEBUG: - Final available lenses: \(availableLenses.map { $0.displayName })")

        // Check if any camera on this position has flash
        let hasFlash = videoDevices.contains { $0.hasFlash }

        // Check if any camera on this position has torch
        let hasTorch = videoDevices.contains { $0.hasTorch }

        // Gather zoom capabilities for each lens type
        var zoomCapabilities: [CameraLensType: RemoteCmd.ZoomRange] = [:]

        for lensType in availableLenses {
            if let device = videoDevices.first(where: { $0.deviceType == lensType.deviceType }) {
                let zoomRange = RemoteCmd.ZoomRange(
                    minZoom: device.minAvailableVideoZoomFactor,
                    maxZoom: device.maxAvailableVideoZoomFactor
                )
                zoomCapabilities[lensType] = zoomRange
            }
        }

        // Gather quality capabilities — probe each resolution's actual FPS limits
        let supportedResolutions = VideoResolution.selectableCases.filter { r in
            captureSession.canSetSessionPreset(r.sessionPreset)
        }

        var resolutionFrameRates: [VideoResolution: [VideoFrameRate]] = [:]
        var allSupportedFrameRates: Set<VideoFrameRate> = []

        if let dev = videoDevices.first {
            for res in supportedResolutions {
                let maxFPS = maxFPSAcrossFormats(for: dev, resolution: res)
                let rates = VideoFrameRate.selectableCases.filter { $0.value <= Int(maxFPS) }
                resolutionFrameRates[res] = rates
                rates.forEach { allSupportedFrameRates.insert($0) }
            }
        }

        let supportedFrameRates = VideoFrameRate.selectableCases.filter { allSupportedFrameRates.contains($0) }

        let supportsHEIF = photoOutput.availablePhotoCodecTypes.contains(.hevc)
        let supportsHDR = true // All iOS 15+ devices support .quality prioritization (HDR)

        // Discover zoom stops from the preferred (virtual) device
        let preferredDevice = preferredCamera(for: position)
        let discoveredZoomStops = preferredDevice.map { discoverZoomStops(for: $0) } ?? [1.0]
        let wideAngle = preferredDevice.map { wideAngleZoomFactor(for: $0) } ?? 1.0

        return RemoteCmd.CameraInfo(
            availableLenses: availableLenses,
            hasFlash: hasFlash,
            hasTorch: hasTorch,
            zoomCapabilities: zoomCapabilities,
            supportedResolutions: supportedResolutions,
            supportedFrameRates: supportedFrameRates,
            resolutionFrameRates: resolutionFrameRates,
            supportsHEIF: supportsHEIF,
            supportsHDR: supportsHDR,
            zoomStops: discoveredZoomStops,
            wideAngleZoomFactor: wideAngle
        )
    }

    // MARK: - Current Camera Capabilities for Toggle Response
    func gatherCurrentCameraCapabilities() -> RemoteCmd.CameraCapabilitiesResp? {
        sessionQueue.sync { gatherCurrentCameraCapabilitiesLocked() }
    }

    private func gatherCurrentCameraCapabilitiesLocked() -> RemoteCmd.CameraCapabilitiesResp? {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        debugLog("🔍 DEBUG: gatherCurrentCameraCapabilities called")

        guard let currentDevice = self.videoDeviceInput?.device else {
            debugLog("❌ DEBUG: No videoDeviceInput.device available")
            debugLog("❌ DEBUG: videoDeviceInput is \(self.videoDeviceInput != nil ? "not nil" : "nil")")
            return nil
        }

        debugLog("🔍 DEBUG: Current device: \(currentDevice.localizedName)")
        debugLog("🔍 DEBUG: frontCameraInfo: \(frontCameraInfo != nil ? "available" : "nil")")
        debugLog("🔍 DEBUG: backCameraInfo: \(backCameraInfo != nil ? "available" : "nil")")

        let capabilities = RemoteCmd.CameraCapabilitiesResp(
            frontCamera: frontCameraInfo,
            backCamera: backCameraInfo,
            currentCamera: currentDevice.position,
            currentLens: currentLensType,
            currentZoom: currentZoomFactor,
            currentVideoResolution: currentVideoResolution,
            currentVideoFrameRate: currentVideoFrameRate,
            currentPhotoFormat: currentPhotoFormat,
            currentHDRMode: currentHDRMode,
            error: nil
        )

        debugLog("🔍 DEBUG: Created capabilities response successfully")
        return capabilities
    }

    // MARK: - Enhanced Zoom Control Methods
    func setZoom(zoomFactor: CGFloat) -> Try<(CGFloat, CameraLensType, RemoteCmd.ZoomRange)> {
        sessionQueue.sync { setZoomLocked(zoomFactor: zoomFactor) }
    }

    private func setZoomLocked(zoomFactor: CGFloat) -> Try<(CGFloat, CameraLensType, RemoteCmd.ZoomRange)> {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        debugLog("🔍 DEBUG: setZoom called with factor: \(zoomFactor)")

        guard let device = self.videoDeviceInput?.device else {
            debugLog("❌ DEBUG: No camera device available")
            return Failure(error: NSError(domain: "No camera device available", code: 0, userInfo: nil))
        }

        debugLog("🔍 DEBUG: Current device: \(device.localizedName), position: \(device.position.rawValue)")
        debugLog("🔍 DEBUG: Zoom range: \(device.minAvailableVideoZoomFactor) - \(device.maxAvailableVideoZoomFactor)")
        debugLog("🔍 DEBUG: Current zoom: \(device.videoZoomFactor)")

        do {
            try device.lockForConfiguration()

            let clampedZoom = max(device.minAvailableVideoZoomFactor,
                                 min(zoomFactor, device.maxAvailableVideoZoomFactor))

            debugLog("🔍 DEBUG: Setting zoom from \(device.videoZoomFactor) to \(clampedZoom)")
            device.videoZoomFactor = clampedZoom
            currentZoomFactor = clampedZoom

            // Update currentLensType based on which lens the virtual device is using
            currentLensType = lensTypeForZoomFactor(clampedZoom, device: device)

            device.unlockForConfiguration()

            debugLog("✅ DEBUG: Zoom set successfully to \(device.videoZoomFactor), lens: \(currentLensType.displayName)")

            let zoomRange = RemoteCmd.ZoomRange(
                minZoom: device.minAvailableVideoZoomFactor,
                maxZoom: device.maxAvailableVideoZoomFactor
            )

            return Success((clampedZoom, currentLensType, zoomRange))
        } catch let error as NSError {
            debugLog("❌ DEBUG: Error setting zoom: \(error.localizedDescription)")
            return Failure(error: error)
        }
    }

    func getCurrentZoomFactor() -> CGFloat {
        sessionQueue.sync { videoDeviceInput?.device.videoZoomFactor ?? 1.0 }
    }

    func getMaxZoomFactor() -> CGFloat {
        sessionQueue.sync { videoDeviceInput?.device.maxAvailableVideoZoomFactor ?? 1.0 }
    }

    func getMinZoomFactor() -> CGFloat {
        sessionQueue.sync { videoDeviceInput?.device.minAvailableVideoZoomFactor ?? 1.0 }
    }

    // MARK: - Enhanced Lens Switching Methods

    /// Determines which lens is active based on the current zoom factor and switchover points.
    private func lensTypeForZoomFactor(_ zoom: CGFloat, device: AVCaptureDevice) -> CameraLensType {
        let switchOverFactors = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        guard !switchOverFactors.isEmpty else { return .wideAngle }

        if switchOverFactors.count >= 2 && zoom >= switchOverFactors[1] {
            return .telephoto
        } else if zoom >= switchOverFactors[0] {
            return .wideAngle
        } else {
            return .ultraWide
        }
    }

    /// Maps a CameraLensType to the appropriate hardware zoom factor on the current virtual device.
    ///
    /// For builtInTripleCamera with switchOverFactors [2, 6]:
    ///   .ultraWide → 1.0 (base = ultra-wide)
    ///   .wideAngle → 2.0 (first switchover)
    ///   .telephoto → 6.0 (second switchover)
    private func zoomFactorForLensType(_ lensType: CameraLensType, device: AVCaptureDevice) -> CGFloat {
        let switchOverFactors = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }

        switch lensType {
        case .ultraWide:
            // Ultra-wide is the base lens of the virtual device
            return device.minAvailableVideoZoomFactor
        case .wideAngle:
            // Wide-angle is at the first switchover factor
            return switchOverFactors.first ?? 1.0
        case .telephoto:
            // Telephoto is at the last switchover factor
            return switchOverFactors.last ?? switchOverFactors.first ?? 2.0
        case .dualCamera:
            return switchOverFactors.first ?? 2.0
        }
    }

    func switchLens(to lensType: CameraLensType) -> Try<(CameraLensType, [CameraLensType], CGFloat, RemoteCmd.ZoomRange)> {
        sessionQueue.sync { switchLensLocked(to: lensType) }
    }

    private func switchLensLocked(to lensType: CameraLensType) -> Try<(CameraLensType, [CameraLensType], CGFloat, RemoteCmd.ZoomRange)> {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard let device = self.videoDeviceInput?.device else {
            return Failure(error: NSError(domain: "No camera device available", code: 0, userInfo: nil))
        }

        let targetZoom = zoomFactorForLensType(lensType, device: device)
        do {
            try device.lockForConfiguration()
            let clampedZoom = max(device.minAvailableVideoZoomFactor,
                                 min(targetZoom, device.maxAvailableVideoZoomFactor))
            device.videoZoomFactor = clampedZoom
            currentZoomFactor = clampedZoom
            currentLensType = lensType
            device.unlockForConfiguration()

            let zoomRange = RemoteCmd.ZoomRange(
                minZoom: device.minAvailableVideoZoomFactor,
                maxZoom: device.maxAvailableVideoZoomFactor
            )
            return Success((lensType, availableLensTypes, currentZoomFactor, zoomRange))
        } catch let error as NSError {
            return Failure(error: error)
        }
    }

    func getAvailableLensTypes() -> [CameraLensType] {
        sessionQueue.sync { availableLensTypes }
    }

    func getCurrentLensType() -> CameraLensType {
        sessionQueue.sync { currentLensType }
    }

    func getZoomStops() -> [CGFloat] {
        sessionQueue.sync { zoomStops }
    }

    func getWideAngleZoomFactor() -> CGFloat {
        sessionQueue.sync {
            guard let device = videoDeviceInput?.device else { return 1.0 }
            return wideAngleZoomFactor(for: device)
        }
    }

    /// Applies `orientation` to the video-data and photo output connections and
    /// caches it for still capture. Returns whether the photo connection existed,
    /// so the caller can mirror the original preview-frame refresh timing.
    @discardableResult
    func rotateOutputs(orientation: UIInterfaceOrientation) -> Bool {
        sessionQueue.sync { rotateOutputsLocked(orientation: orientation) }
    }

    @discardableResult
    private func rotateOutputsLocked(orientation: UIInterfaceOrientation) -> Bool {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        self.orientation = orientation
        let o = OrientationUtils.transform(o: orientation)
        if let videoConnection = self.videoConnection {
            videoConnection.videoOrientation = o
        }
        if let photoConnection = self.photoOutput.connection(with: AVMediaType.video) {
            photoConnection.videoOrientation = o
            return true
        }
        return false
    }

    func setFrameRate(framerate: Int, videoDevice: AVCaptureDevice) throws {
        let maxFPS = Int(maxSupportedFPS(for: videoDevice))
        let safeFPS = max(1, min(framerate, maxFPS))
        try videoDevice.lockForConfiguration()
        videoDevice.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: Int32(safeFPS))
        videoDevice.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(safeFPS))
        videoDevice.unlockForConfiguration()
        if safeFPS != framerate {
            fpsSetting.value = safeFPS
            currentVideoFrameRate = VideoFrameRate.selectableCases.last(where: { $0.value <= safeFPS }) ?? .fps30
            onStatusChanged?()
        }
    }

    /// Max FPS supported by the device's *current active format*.
    func maxSupportedFPS(for device: AVCaptureDevice) -> Double {
        device.activeFormat.videoSupportedFrameRateRanges.reduce(30.0) { max($0, $1.maxFrameRate) }
    }

    /// Max FPS across *all* device formats at a given resolution.
    func maxFPSAcrossFormats(for device: AVCaptureDevice, resolution: VideoResolution) -> Double {
        let targetDims = resolution.dimensions
        var result: Double = 30
        for format in device.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.width >= targetDims.width && dims.height >= targetDims.height else { continue }
            for range in format.videoSupportedFrameRateRanges {
                result = max(result, range.maxFrameRate)
            }
        }
        return result
    }

    /// Finds a device format supporting both the target resolution and FPS.
    func findFormat(for device: AVCaptureDevice, resolution: VideoResolution, fps: Double) -> AVCaptureDevice.Format? {
        let targetDims = resolution.dimensions
        for format in device.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.width >= targetDims.width && dims.height >= targetDims.height else { continue }
            if format.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= fps }) {
                return format
            }
        }
        return nil
    }

    func setVideoQuality(resolution: VideoResolution, frameRate: VideoFrameRate, isRecording: Bool) -> (VideoResolution, VideoFrameRate)? {
        sessionQueue.sync { setVideoQualityLocked(resolution: resolution, frameRate: frameRate, isRecording: isRecording) }
    }

    private func setVideoQualityLocked(resolution: VideoResolution, frameRate: VideoFrameRate, isRecording: Bool) -> (VideoResolution, VideoFrameRate)? {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard !isRecording else { return nil }
        guard let device = videoDeviceInput?.device else { return nil }

        captureSession.beginConfiguration()

        var appliedFrameRate = frameRate

        if let format = findFormat(for: device, resolution: resolution, fps: Double(frameRate.value)) {
            captureSession.sessionPreset = .inputPriority
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                device.unlockForConfiguration()
            } catch {
                captureSession.commitConfiguration()
                return nil
            }
        } else {
            guard captureSession.canSetSessionPreset(resolution.sessionPreset) else {
                captureSession.commitConfiguration()
                return nil
            }
            captureSession.sessionPreset = resolution.sessionPreset
            let maxFPS = Int(maxSupportedFPS(for: device))
            appliedFrameRate = VideoFrameRate.selectableCases
                .filter { $0.value <= maxFPS }
                .last ?? .fps30
        }

        do {
            try setFrameRate(framerate: appliedFrameRate.value, videoDevice: device)
        } catch {
            captureSession.commitConfiguration()
            return nil
        }
        captureSession.commitConfiguration()

        // Restore zoom factor — changing activeFormat/sessionPreset resets it to 1.0
        let savedZoom = currentZoomFactor
        do {
            try device.lockForConfiguration()
            let clampedZoom = max(device.minAvailableVideoZoomFactor,
                                 min(savedZoom, device.maxAvailableVideoZoomFactor))
            device.videoZoomFactor = clampedZoom
            currentZoomFactor = clampedZoom
            device.unlockForConfiguration()
        } catch {
            debugLog("❌ DEBUG: Failed to restore zoom after quality change: \(error)")
        }

        applyDesiredTorchLocked()   // changing activeFormat/preset also resets the torch

        currentVideoResolution = resolution
        currentVideoFrameRate = appliedFrameRate
        fpsSetting.value = appliedFrameRate.value
        onStatusChanged?()

        return (resolution, appliedFrameRate)
    }

    // MARK: - Aspect Ratio Methods

    func setAspectRatio(_ ratio: AspectRatio) -> AspectRatio {
        sessionQueue.sync {
            currentAspectRatio = ratio
            onStatusChanged?()
            return ratio
        }
    }

    /// Aspect ratio for callers outside the session queue (the photo-capture
    /// callback and the pipeline's record-start snapshot).
    func currentAspectRatioValue() -> AspectRatio {
        sessionQueue.sync { currentAspectRatio }
    }

    /// Computes a centered crop rect for the given aspect ratio within source dimensions.
    /// Returns nil if the source already matches the target ratio.
    static func cropRect(sourceWidth: CGFloat, sourceHeight: CGFloat, aspectRatio: AspectRatio) -> CGRect? {
        let isLandscape = sourceWidth > sourceHeight
        let targetRatio = isLandscape ? aspectRatio.widthToHeight : (1.0 / aspectRatio.widthToHeight)
        let currentRatio = sourceWidth / sourceHeight

        if abs(currentRatio - targetRatio) < 0.01 {
            return nil // Already matches
        } else if currentRatio > targetRatio {
            let newWidth = sourceHeight * targetRatio
            return CGRect(x: (sourceWidth - newWidth) / 2, y: 0, width: newWidth, height: sourceHeight)
        } else {
            let newHeight = sourceWidth / targetRatio
            return CGRect(x: 0, y: (sourceHeight - newHeight) / 2, width: sourceWidth, height: newHeight)
        }
    }

    /// Crops photo data to the selected aspect ratio.
    func cropPhotoData(_ data: Data, to aspectRatio: AspectRatio) -> Data? {
        guard let image = UIImage(data: data),
              let cgImage = image.cgImage else {
            debugLog("cropPhotoData: failed to create UIImage/CGImage from data (\(data.count) bytes)")
            return nil
        }

        guard let rect = Self.cropRect(
            sourceWidth: CGFloat(cgImage.width),
            sourceHeight: CGFloat(cgImage.height),
            aspectRatio: aspectRatio
        ) else { return data }

        guard let croppedCG = cgImage.cropping(to: rect) else {
            debugLog("cropPhotoData: cgImage.cropping failed for rect \(rect)")
            return nil
        }
        let croppedImage = UIImage(cgImage: croppedCG, scale: image.scale, orientation: image.imageOrientation)
        return croppedImage.jpegData(compressionQuality: 0.95)
    }

    func setPhotoQuality(format: PhotoFormat, hdrMode: HDRMode) -> (PhotoFormat, HDRMode)? {
        sessionQueue.sync {
            if format == .heif {
                guard photoOutput.availablePhotoCodecTypes.contains(.hevc) else { return nil }
            }

            currentPhotoFormat = format
            currentHDRMode = hdrMode
            onStatusChanged?()
            return (format, hdrMode)
        }
    }

    func cloneCameraSettings(_ settings: AVCapturePhotoSettings) -> AVCapturePhotoSettings {
        let newSettings: AVCapturePhotoSettings
        if currentPhotoFormat == .heif && photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            newSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            newSettings = AVCapturePhotoSettings()
        }
        newSettings.flashMode = settings.flashMode
        newSettings.isHighResolutionPhotoEnabled = settings.isHighResolutionPhotoEnabled
        if currentHDRMode == .on {
            newSettings.photoQualityPrioritization = .quality
        } else {
            newSettings.photoQualityPrioritization = .balanced
        }
        return newSettings
    }

    func takePicture(_ sendMediaToRemote: Bool) {
        // Clone the settings where they live (sessionQueue), then keep the
        // capture initiation on main exactly as before.
        sessionQueue.async {
            let cameraSettings = self.cloneCameraSettings(self.cameraSettings)
            OperationQueue.main.addOperation {
                self.photoOutput.capturePhoto(with: cameraSettings, delegate: self)
            }
        }
    }

    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if error != nil {
            onPicture?(nil, error!)
            return
        }
        guard let photoData = photo.fileDataRepresentation() else {
            return
        }
        // Apply aspect ratio cropping if needed (delivered on an AVFoundation
        // callback queue; read the aspect through the session queue).
        let aspectRatio = currentAspectRatioValue()
        if aspectRatio != .sixteenNine,
           let croppedData = cropPhotoData(photoData, to: aspectRatio) {
            onPicture?(croppedData, nil)
        } else {
            onPicture?(photoData, nil)
        }
    }
}
