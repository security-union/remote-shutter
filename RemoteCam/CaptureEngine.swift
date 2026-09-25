//
//  CaptureEngine.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union. All rights reserved.
//

import UIKit
import AVFoundation

/// Classifies capture-session runtime errors by recency. One error is
/// transient (media services reset — resume and move on); a repeat inside the
/// window is the graph saying the current device cannot run, ever — the
/// signal to mark it failed instead of retrying into a start-fail loop.
/// Pure so the rule is unit-testable without capture hardware.
enum CaptureErrorStrikes {
    static let window: TimeInterval = 3

    static func record(_ strikes: [TimeInterval], now: TimeInterval)
        -> (strikes: [TimeInterval], deterministic: Bool) {
        let recent = strikes.filter { now - $0 < window } + [now]
        return (recent, recent.count >= 2)
    }
}

/// Owns the `AVCaptureSession` and every still-photo / configuration concern for
/// the camera device: device selection, zoom, lens switching, torch, flash,
/// video/photo quality, aspect ratio and photo capture. It knows nothing about
/// views, layers or the actor system — the `CameraRig` wires the recording
/// pipeline and frame streaming around it and forwards captured photos to the
/// session actor via the `onPicture` callback.
final class CaptureEngine: NSObject, AVCapturePhotoCaptureDelegate {

    /// The single owner of all session/device configuration and engine control
    /// state. Synchronous accessors hop here re-entrantly (`syncOnSessionQueue`);
    /// async commands hop via continuations; nothing on this queue ever `.sync`s
    /// back out, so no cycle can form.
    let sessionQueue = DispatchQueue(label: "camera session queue", attributes: [], target: nil)

    private static let sessionQueueKey = DispatchSpecificKey<Void>()

    override init() {
        super.init()
        sessionQueue.setSpecific(key: Self.sessionQueueKey, value: ())
        observeDeviceConnections()
    }

    deinit {
        deviceConnectionObservers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Runs `body` on the session queue, inline when already there — so
    /// callbacks fired from inside the queue (e.g. `onStatusChanged`) can
    /// safely read state without deadlocking on a nested `.sync`.
    private func syncOnSessionQueue<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: Self.sessionQueueKey) != nil {
            return body()
        }
        return sessionQueue.sync(execute: body)
    }

    /// Non-blocking hop for the async command surface.
    private func onSessionQueue<T>(_ body: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            sessionQueue.async { continuation.resume(returning: body()) }
        }
    }

    private func onSessionQueueThrowing<T>(_ body: @escaping () throws -> T) async throws -> T {
        let result: Result<T, Error> = await withCheckedContinuation { continuation in
            sessionQueue.async { continuation.resume(returning: Result { try body() }) }
        }
        return try result.get()
    }

    let captureSession: AVCaptureSession = AVCaptureSession()

    /// Whether the session is supposed to be running (between setup and
    /// stopSession) — the reference for runtime-error recovery, per Apple's
    /// AVCam resume pattern. sessionQueue-confined.
    private var isExpectedToRun = false

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
    // TEMP seam for WP-B2 — WP-B provides the real one (non-nil while
    // Editable Cinematic is on). sessionQueue-confined.
    var cinematicMovieOutput: AVCaptureMovieFileOutput?

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
    /// The capture device was swapped underneath the running outputs — a flip, a
    /// device pick, or a lens switch. The scene cuts completely, but the preview
    /// encoder is not recreated unless the *scaled* dimensions happen to change
    /// (they don't on a flip: both cameras land on the same long edge), so it
    /// would otherwise encode a delta frame across the cut. Fires on `sessionQueue`.
    var onDeviceSwapped: (() -> Void)?
    /// The system interrupted the capture session (lock, backgrounding, phone
    /// call, camera claimed by another app) — capture has factually stopped.
    /// The rig uses this to finalize + save any rolling recording. Fires on
    /// the notification's delivery thread.
    var onSessionInterrupted: (() -> Void)?

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

        guard let videoDevice = initialCameraLocked() else {
            self.captureSession.commitConfiguration()
            return false
        }
        refreshSuspensionObserversLocked()
        lastNotifiedDevices = selectableDevicesLocked().map { self.descriptorLocked($0) }
        debugLog("🔍 SETUP CAMERA: using device=\(videoDevice.localizedName) type=\(videoDevice.deviceType.rawValue) isVirtual=\(!videoDevice.virtualDeviceSwitchOverVideoZoomFactors.isEmpty)")

        do {
            self.videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            self.captureSession.addInput(self.videoDeviceInput)
            self.captureSession.addOutput(self.videoDataOutput)

            try self.setFrameRate(framerate: fpsSetting.value, videoDevice: videoDevice)

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
            self.isExpectedToRun = true

            // Capability probing AFTER the session is live (AVCam configures
            // minimally and probes nothing at setup): on a Mac this walks
            // every attached camera's formats — including a wireless
            // Continuity iPhone — and must never delay the first frame.
            self.gatherAllCameraCapabilitiesLocked()
        } catch let error as NSError {
            logWarning("error \(error)")
        }
        return true
    }

    /// Adds the audio input/output for video recording — the config half of
    /// record-start, kept on `sessionQueue` (the pipeline's data-queue work
    /// syncs in here once, then continues on its own queue).
    func configureAudioForRecording(delegate: AVCaptureAudioDataOutputSampleBufferDelegate) -> Bool {
        syncOnSessionQueue {
            // Already wired from a previous take: re-adding inside a live
            // begin/commitConfiguration is pure thrash on the record hot
            // path (a commit can stall for seconds right after a wake).
            // Configure once; later takes just re-point the delegate.
            if self.captureSession.outputs.contains(self.audioDataOutput),
               self.audioConnection != nil {
                self.audioDataOutput.setSampleBufferDelegate(delegate, queue: self.dataOutputQueue)
                return true
            }
            do {
                guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
                    return false
                }
                let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)

                captureSession.beginConfiguration()
                if captureSession.canAddInput(audioDeviceInput) {
                    captureSession.addInput(audioDeviceInput)
                } else {
                    logWarning("Could not add audio device input to the session")
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
                logWarning("Error setting up audio for video recording: \(error)")
                return false
            }
        }
    }

    /// Stops the capture session (screen teardown).
    func stopSession() {
        syncOnSessionQueue {
            // The AVCaptureDevice outlives this session: leave it in auto so
            // the next session (or the system Camera app) starts clean.
            exposureIntent = .auto(bias: 0)
            hopRestoreDeviceID = nil
            applyExposureIntentLocked()
            cinematicIntent = CinematicIntent(enabled: false)
            applyCinematicEffectLocked()
        }
        sessionQueue.async {
            self.isExpectedToRun = false
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }

    func toggleCamera(orientation: UIInterfaceOrientation) async throws -> (AVCaptureDevice.FlashMode?, AVCaptureDevice.Position) {
        try await onSessionQueueThrowing {
            guard let newDevice = self.nextToggleDeviceLocked() else {
                throw NSError(domain: "Unable to find camera position", code: 0, userInfo: nil)
            }
            let result = try self.selectLogicalDeviceLocked(newDevice, orientation: orientation)
            return (result.flashMode, result.device.position)
        }
    }

    /// The camera a fresh session starts on. iOS: the preferred (virtual)
    /// back device. Mac: the system's preferred camera when healthy — it
    /// tracks the user's choice across apps — else the first non-suspended
    /// device (a clamshell MacBook's built-in camera is connected but
    /// delivers no frames).
    private func initialCameraLocked() -> AVCaptureDevice? {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        #if targetEnvironment(macCatalyst)
        var candidates: [AVCaptureDevice] = []
        if #available(macCatalyst 17.0, *), let system = AVCaptureDevice.systemPreferredCamera {
            candidates.append(system)
        }
        if let systemDefault = AVCaptureDevice.default(for: .video) {
            candidates.append(systemDefault)
        }
        candidates += selectableDevicesLocked()
        return candidates.first { !$0.isSuspended }
        #else
        return preferredCamera(for: .back) ?? AVCaptureDevice.default(for: .video)
        #endif
    }

    /// The device the front/back flip lands on. The decision is the pure
    /// `CameraDeviceDescriptor.nextToggleSelection` (unit-tested): iOS flips
    /// position, a Mac cycles the attached cameras skipping suspended ones —
    /// an old-protocol monitor's flip button still does something sensible
    /// against a Mac camera.
    private func nextToggleDeviceLocked() -> AVCaptureDevice? {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        #if targetEnvironment(macCatalyst)
        let flipPosition = false
        #else
        let flipPosition = true
        #endif
        let available = selectableDevicesLocked()
        guard let next = CameraDeviceDescriptor.nextToggleSelection(
                currentID: logicalDeviceIDLocked(),
                available: available.map { self.descriptorLocked($0) },
                flipPosition: flipPosition) else { return nil }
        return available.first { $0.uniqueID == next.uniqueID }
    }

    /// Swaps the session input to `newDevice`, reapplying frame rate, lens
    /// state, orientation and torch — the shared core of `toggleCamera` and
    /// `selectCameraDevice`.
    private func swapToDeviceLocked(_ newDevice: AVCaptureDevice,
                                    orientation: UIInterfaceOrientation) throws -> CameraSelectionResult {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        let newInput = try AVCaptureDeviceInput(device: newDevice)
        captureSession.beginConfiguration()
        let previousInput = videoDeviceInput
        if let previousInput {
            captureSession.removeInput(previousInput)
        }
        guard captureSession.canAddInput(newInput) else {
            // AVCam pattern: restore the previous input and report, instead
            // of letting addInput raise an uncatchable ObjC exception (a
            // device can reject the session's current preset).
            if let previousInput, captureSession.canAddInput(previousInput) {
                captureSession.addInput(previousInput)
            }
            captureSession.commitConfiguration()
            throw NSError(
                domain: "\(newDevice.localizedName) is not compatible with the current session",
                code: 0, userInfo: nil)
        }
        captureSession.addInput(newInput)
        videoDeviceInput = newInput
        // AVCam's changeCamera keeps the outputs in place across an input
        // swap — connections re-form automatically; only the cached refs
        // need refreshing. (Removing/re-adding outputs here is gratuitous
        // session churn and diverges from Apple's reference.)
        videoConnection = videoDataOutput.connection(with: .video)
        audioConnection = audioDataOutput.connection(with: .audio)
        try setFrameRate(framerate: fpsSetting.value, videoDevice: newDevice)

        updateAvailableLensTypes(for: newDevice)
        zoomStops = discoverZoomStops(for: newDevice)
        currentPositionShared.value = newDevice.position
        currentZoomFactor = newDevice.videoZoomFactor
        currentLensType = lensTypeForZoomFactor(currentZoomFactor, device: newDevice)

        rotateOutputsLocked(orientation: orientation)
        let newFlashMode: AVCaptureDevice.FlashMode? = newDevice.hasFlash ? cameraSettings.flashMode : nil
        captureSession.commitConfiguration()
        applyDesiredTorchLocked()   // restore torch onto the new camera (no-op if it has none)
        resetFocusExposureToAutoLocked()   // a stale focus point must not carry across a device change
        applyExposureIntentLocked()   // the new device must match the director's exposure intent
        applyCinematicEffectLocked()  // ...and its Cinematic intent (a new input starts with it off)
        // Swapping away from a dead device must also revive a session that a
        // runtime error stopped — otherwise the new camera never delivers.
        if isExpectedToRun && !captureSession.isRunning {
            captureSession.startRunning()
        }
        // Every device swap funnels through here — toggle, device pick and lens
        // switch alike — so this is the one place that has to announce the cut.
        onDeviceSwapped?()

        return CameraSelectionResult(
            device: descriptorLocked(newDevice),
            flashMode: newFlashMode,
            availableLensTypes: availableLensTypes,
            zoomRange: RemoteCmd.ZoomRange(
                minZoom: newDevice.minAvailableVideoZoomFactor,
                maxZoom: newDevice.maxAvailableVideoZoomFactor),
            currentZoom: currentZoomFactor)
    }

    private func configSessionOutput() {
        self.captureSession.beginConfiguration()
        captureSession.removeOutput(videoDataOutput)
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        } else {
            logWarning("Could not add still image output to the session")
            return
        }

        captureSession.removeOutput(photoOutput)
        if captureSession.canAddOutput(photoOutput) {
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.maxPhotoQualityPrioritization = .quality
            captureSession.addOutput(photoOutput)
        } else {
            logWarning("Could not add movie file output to the session")
            return
        }
        videoConnection = videoDataOutput.connection(with: .video)
        audioConnection = audioDataOutput.connection(with: .audio)
        self.captureSession.commitConfiguration()
    }

    func toggleFlash() async throws -> AVCaptureDevice.FlashMode {
        try await onSessionQueueThrowing {
            let genericDevice = self.videoDeviceInput
            let device = genericDevice?.device
            guard let hasFlash = device?.hasFlash, hasFlash else {
                throw NSError(domain: "Current camera does not support flash.", code: 0, userInfo: nil)
            }
            let newFlashMode = self.cameraSettings.flashMode.next()
            self.cameraSettings.flashMode = newFlashMode
            return newFlashMode
        }
    }

    // MARK: - Torch Methods for Video Recording
    func toggleTorch() async throws -> AVCaptureDevice.TorchMode {
        try await onSessionQueueThrowing {
            let device = self.videoDeviceInput?.device
            guard let hasTorch = device?.hasTorch, hasTorch else {
                throw NSError(domain: "Current camera does not support torch.", code: 0, userInfo: nil)
            }
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
            self.desiredTorchOnStorage = newTorchMode == .on
            return newTorchMode
        }
    }

    // MARK: - Torch Intent

    /// The single source of truth for whether the user wants the torch on. Set only by the
    /// user-facing torch control (`toggleTorch`); the countdown strobe
    /// drives the hardware directly and never touches this, so it survives a countdown.
    /// sessionQueue-confined storage; the public getter hops for outside readers.
    // MARK: - Exposure intent

    /// What the director asked for. The device is made to match it by exactly
    /// one function, `applyExposureIntentLocked()`, which every path that
    /// disturbs the device (swap, format change) calls again. sessionQueue-confined.
    private var exposureIntent: ExposureIntent = .auto(bias: 0)
    /// Recording truth lives in the rig's pipeline; the policy needs it to cap
    /// a long shutter at the frame duration while a clip is rolling.
    var isRecordingProvider: () -> Bool = { false }
    /// The chosen (logical) camera while the session runs a different device
    /// for it: Manual on a virtual multi-lens device runs a physical
    /// constituent (virtual devices refuse `.custom`), and Cinematic on a
    /// camera without Cinematic formats runs its Dual Wide / TrueDepth
    /// sibling. Nil = the session runs the chosen camera itself.
    private var hopRestoreDeviceID: String?

    // MARK: - Cinematic intent (iOS 26+)

    /// What the director asked for. The session is made to match it by
    /// exactly one function, `applyCinematicEffectLocked()`, which every path
    /// that disturbs the device (swap, format change, mode change) calls
    /// again. Survives photo mode; cleared when the session ends.
    /// sessionQueue-confined.
    private var cinematicIntent = CinematicIntent(enabled: false)
    /// Cinematic is a video-mode effect; mode truth lives in the rig.
    var isVideoModeProvider: () -> Bool = { false }
    /// Attached exactly while Cinematic is on with the editable output; the
    /// recorder records through it. sessionQueue-confined — read it with
    /// `cinematicMovieOutputForRecording()` from elsewhere.
    private(set) var cinematicMovieOutput: AVCaptureMovieFileOutput?
    /// Attached exactly while the effect is on (its types must equal the
    /// required set, or enabling throws).
    private let cinematicMetadataOutput = AVCaptureMetadataOutput()
    private let cinematicMetadataQueue = DispatchQueue(label: "cinematic metadata queue")
    /// What the metadata callback needs to map boxes into display space.
    /// Written on the session queue, read on the metadata queue.
    private let cinematicSubjectContext = Locked<CinematicSubjectContext?>(nil)
    /// metadata-queue-confined throttle state.
    private var lastSubjectsPublishAt: TimeInterval = 0
    private var lastSubjectsCount = 0
    /// The live subjects report, ~10 Hz while the effect is on. Set once by
    /// the rig before the session starts; called on the metadata queue.
    var onCinematicSubjects: ((CinematicSubjectsReport) -> Void)?
    /// The Cinematic truth after every apply (nil block = unsupported), for
    /// the camera screen's chip. Called on the session queue.
    var onCinematicStateChanged: ((CinematicState?) -> Void)?

    private var desiredTorchOnStorage = false
    var desiredTorchOn: Bool {
        syncOnSessionQueue { desiredTorchOnStorage }
    }

    /// Clears the user's torch intent (screen teardown). Called by the rig's `ensureTorchOff`.
    func clearTorchIntent() {
        syncOnSessionQueue { desiredTorchOnStorage = false }
    }

    /// Applies `desiredTorchOn` to the hardware. Reused to restore the torch after any
    /// event that resets it (rotation, session reconfiguration, timer countdown).
    func applyDesiredTorch() {
        syncOnSessionQueue { applyDesiredTorchLocked() }
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
        syncOnSessionQueue { videoDeviceInput?.device }
    }

    /// Whether the torch is currently lit (protocol surface for the states).
    func isTorchActive() async -> Bool {
        await onSessionQueue { self.videoDeviceInput?.device.isTorchActive ?? false }
    }

    /// The flash mode the next photo will use (protocol surface for the states).
    func currentFlashModeValue() async -> AVCaptureDevice.FlashMode {
        await onSessionQueue { self.cameraSettings.flashMode }
    }

    /// Snapshot of the status-overlay fields, for the rig's view-model update
    /// from any thread.
    func statusSnapshot() -> (VideoResolution, VideoFrameRate, PhotoFormat, HDRMode) {
        syncOnSessionQueue {
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

    // MARK: - Device Selection (uniqueID-based; a Mac has N cameras)

    /// Every camera the user can select on this platform, in stable discovery
    /// order. Catalyst enumerates all attached cameras (built-in, Continuity,
    /// Desk View, external); iOS offers the preferred (virtual) device per
    /// position — lens choice within a position stays the zoom/lens
    /// machinery's job.
    private func selectableDevicesLocked() -> [AVCaptureDevice] {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        #if targetEnvironment(macCatalyst)
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macCatalyst 17.0, *) {
            // Desk View has no Catalyst API; its feed arrives as a regular
            // Continuity Camera device.
            types += [.continuityCamera, .external]
        }
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: types, mediaType: .video, position: .unspecified).devices
        #else
        return [preferredCamera(for: .back), preferredCamera(for: .front)].compactMap { $0 }
        #endif
    }

    func availableCameraDevices() async -> [CameraDeviceDescriptor] {
        await onSessionQueue {
            self.selectableDevicesLocked().map { self.descriptorLocked($0) }
        }
    }

    /// The chosen camera — the logical one, never a hop target: the
    /// coordinator compares it with the device it asked for.
    func currentCameraDevice() async -> CameraDeviceDescriptor? {
        await onSessionQueue {
            self.logicalDeviceLocked().map { self.descriptorLocked($0) }
        }
    }

    func selectCameraDevice(uniqueID: String, orientation: UIInterfaceOrientation) async throws -> CameraSelectionResult {
        try await onSessionQueueThrowing {
            let available = self.selectableDevicesLocked()
            let descriptors = available.map { self.descriptorLocked($0) }
            // Explicitly requesting a suspended camera is an error, not a
            // silent switch to some other device (pickers gray these out;
            // an old-protocol peer can still ask).
            if let requested = descriptors.first(where: { $0.uniqueID == uniqueID }),
               requested.isSuspended {
                throw NSError(
                    domain: "\(requested.localizedName) is unavailable (suspended)",
                    code: 0, userInfo: nil)
            }
            let fallbackPosition = self.videoDeviceInput?.device.position ?? .unspecified
            guard let resolved = CameraDeviceDescriptor.resolveSelection(
                    requestedID: uniqueID, available: descriptors, fallbackPosition: fallbackPosition),
                  let device = available.first(where: { $0.uniqueID == resolved.uniqueID }) else {
                throw NSError(domain: "No camera device available", code: 0, userInfo: nil)
            }
            let result = try self.selectLogicalDeviceLocked(device, orientation: orientation)
            #if targetEnvironment(macCatalyst)
            if #available(macCatalyst 17.0, *) {
                // Apple's "manual mode": feed the system-wide preference so
                // other apps and future launches respect the user's pick.
                AVCaptureDevice.userPreferredCamera = device
            }
            #endif
            return result
        }
    }

    /// Platform-aware lens refresh: iOS keeps its position-based discovery;
    /// Mac cameras have a single lens.
    private func updateAvailableLensTypes(for device: AVCaptureDevice) {
        #if targetEnvironment(macCatalyst)
        availableLensTypes = [.wideAngle]
        #else
        updateAvailableLensTypes(for: device.position)
        #endif
    }

    // MARK: - Device state (hot-plug, suspension, runtime errors)

    /// Fired on the session queue whenever the set or health of attached
    /// cameras changes: hot-plug, lid open/close (suspension), or a session
    /// runtime error. Built-in iOS cameras never fire this.
    var onCameraDevicesChanged: (() -> Void)?

    private var deviceConnectionObservers: [NSObjectProtocol] = []
    /// KVO on `isSuspended` per discovered device — there is no notification
    /// for suspension; Apple documents key-value observing this property.
    private var suspensionObservations: [NSKeyValueObservation] = []

    /// Devices whose capture graph deterministically fails to run this launch
    /// (repeated session runtime errors — e.g. a virtual camera with no sensor).
    /// Folded into every descriptor's `isSuspended`, so pickers gray them,
    /// toggles and fallbacks skip them, and capabilities advertise them
    /// unavailable. Cleared per device when it disconnects, so a replug gets a
    /// fresh chance. sessionQueue-confined.
    private var failedDeviceIDs: Set<String> = []
    /// Recent runtime-error timestamps for `CaptureErrorStrikes`. sessionQueue-confined.
    private var errorStrikes: [TimeInterval] = []

    fileprivate func observeDeviceConnections() {
        let center = NotificationCenter.default
        let handle = { [weak self] (note: Notification, disconnected: Bool) in
            guard let device = note.object as? AVCaptureDevice, device.hasMediaType(.video) else { return }
            self?.handleDeviceStateChange(disconnectedID: disconnected ? device.uniqueID : nil)
        }
        deviceConnectionObservers = [
            center.addObserver(forName: AVCaptureDevice.wasConnectedNotification,
                               object: nil, queue: nil) { handle($0, false) },
            center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification,
                               object: nil, queue: nil) { handle($0, true) },
            center.addObserver(forName: .AVCaptureSessionRuntimeError,
                               object: captureSession, queue: nil) { [weak self] note in
                self?.handleSessionRuntimeError(note.userInfo?[AVCaptureSessionErrorKey] as? NSError)
            },
            center.addObserver(forName: .AVCaptureSessionWasInterrupted,
                               object: captureSession, queue: nil) { [weak self] note in
                debugLog("CaptureEngine: session interrupted (reason \(String(describing: note.userInfo?[AVCaptureSessionInterruptionReasonKey])))")
                // The rig finalizes any rolling recording here: an interrupted
                // session cannot capture, so the take is factually over.
                self?.onSessionInterrupted?()
                self?.handleDeviceStateChange()
            },
            center.addObserver(forName: .AVCaptureSessionInterruptionEnded,
                               object: captureSession, queue: nil) { [weak self] _ in
                debugLog("CaptureEngine: session interruption ended")
                self?.resumeSessionIfNeeded()
            }
        ]
    }

    /// Full stop/start bounce. A session that begins on a source which never
    /// produces a frame (sandboxed-out virtual camera) can stay wedged —
    /// isRunning true, valid graph, zero buffers — even after the input is
    /// swapped to a good device; only a restart revives delivery. Used by the
    /// rig's first-frame watchdog after a stall-triggered fallback.
    func restartSession() {
        sessionQueue.async {
            guard self.isExpectedToRun else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
            self.captureSession.startRunning()
        }
    }

    /// A session runtime error is the graph's own verdict, delivered within
    /// milliseconds — long before any frame-absence timeout notices. A lone
    /// error is transient (media services reset) and gets AVCam's resume; a
    /// second error inside the strike window means the current device
    /// deterministically cannot run, so it is marked failed and the session
    /// moves to a healthy device immediately, sparing the ~10s the frame
    /// watchdog would otherwise take to conclude the same thing. The three
    /// session-queue blocks run FIFO: classify → move off → restart.
    private func handleSessionRuntimeError(_ error: NSError?) {
        sessionQueue.async {
            let verdict = CaptureErrorStrikes.record(self.errorStrikes,
                                                     now: Date().timeIntervalSinceReferenceDate)
            self.errorStrikes = verdict.strikes
            if verdict.deterministic, let dead = self.videoDeviceInput?.device {
                self.errorStrikes = []
                self.failedDeviceIDs.insert(dead.uniqueID)
                logWarning("CaptureEngine: \(dead.localizedName) cannot run"
                    + " (\(error?.localizedDescription ?? "unknown error"))"
                    + " — marked unavailable, moving off")
            } else {
                debugLog("CaptureEngine: session runtime error: \(error?.localizedDescription ?? "unknown")")
            }
        }
        handleDeviceStateChange()
        sessionQueue.async {
            if self.isExpectedToRun && !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }

    /// AVCam's resume pattern, shared by the interruption-ended observer:
    /// an interruption can leave the session stopped; restart when it is
    /// supposed to be running, then run the normal device-state refresh so
    /// both ends re-sync.
    private func resumeSessionIfNeeded() {
        sessionQueue.async {
            if self.isExpectedToRun && !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
        handleDeviceStateChange()
    }

    /// The device set as of the last state-change notification, so flapping
    /// sources (a Continuity iPhone connects/disconnects as it locks and
    /// idles) don't re-notify the rig — and rebuild both picker menus — for
    /// an unchanged list. sessionQueue-confined.
    private var lastNotifiedDevices: [CameraDeviceDescriptor] = []

    /// One event path for every "the cameras changed" trigger: refresh the
    /// suspension observers, move off a dead active device, and tell the rig
    /// — but only when something observable actually changed.
    private func handleDeviceStateChange(disconnectedID: String? = nil) {
        sessionQueue.async {
            // A failed device that unplugs gets amnesty — replugging retries it.
            if let disconnectedID { self.failedDeviceIDs.remove(disconnectedID) }
            let active = self.videoDeviceInput?.device
            let activeIsGone = (disconnectedID != nil && active?.uniqueID == disconnectedID)
                || active.map { self.descriptorLocked($0).isSuspended } ?? false
            if activeIsGone {
                self.fallBackToHealthyDeviceLocked()
            }
            let devices = self.selectableDevicesLocked().map { self.descriptorLocked($0) }
            guard activeIsGone || devices != self.lastNotifiedDevices else { return }
            self.lastNotifiedDevices = devices
            // The device set actually changed — the cached hardware matrix is
            // stale; the next capabilities ask re-scans.
            self.cameraInfoCacheValid = false
            self.refreshSuspensionObserversLocked()
            self.onCameraDevicesChanged?()
        }
    }

    private func refreshSuspensionObserversLocked() {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        suspensionObservations = selectableDevicesLocked().map { device in
            device.observe(\.isSuspended) { [weak self] _, _ in
                self?.handleDeviceStateChange()
            }
        }
    }

    /// Every descriptor the engine hands out is built here: a device on the
    /// per-launch failed list reads as suspended, so pickers gray it, toggles
    /// and fallbacks skip it, explicit selection refuses it, and capabilities
    /// advertise it unavailable — all derived from the one set, no other state.
    private func descriptorLocked(_ device: AVCaptureDevice) -> CameraDeviceDescriptor {
        var descriptor = CameraDeviceDescriptor(device: device)
        if failedDeviceIDs.contains(device.uniqueID) { descriptor.isSuspended = true }
        return descriptor
    }

    /// The active camera was unplugged or suspended: land on the best healthy
    /// device (same position first, then first available) instead of
    /// freezing on a source that will never deliver a frame.
    private func fallBackToHealthyDeviceLocked() {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        let available = selectableDevicesLocked().filter { $0.isConnected }
        let descriptors = available.map { self.descriptorLocked($0) }
        guard let resolved = CameraDeviceDescriptor.resolveSelection(
                requestedID: "", available: descriptors,
                fallbackPosition: currentPositionShared.value),
              let device = available.first(where: { $0.uniqueID == resolved.uniqueID }) else { return }
        _ = try? swapToDeviceLocked(device, orientation: orientation)
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
    func gatherAllCameraCapabilities() async {
        await onSessionQueue { self.gatherAllCameraCapabilitiesLocked() }
    }

    /// The heavy hardware matrix (per-lens, per-format probing across both
    /// positions) changes only when the DEVICE SET changes — and the engine
    /// is the one who observes that (`handleDeviceStateChange`). So the
    /// engine owns the decision: scan when the cache is stale, serve from
    /// memory otherwise. Callers never trigger hardware work by asking.
    /// sessionQueue-confined.
    private var cameraInfoCacheValid = false

    private func gatherAllCameraCapabilitiesLocked() {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        if cameraInfoCacheValid {
            debugLog("🔍 DEBUG: gatherAllCameraCapabilities served from cache")
            return
        }
        defer { cameraInfoCacheValid = true }
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
        if let device = preferredDevice {
            // Exposure hardware probe (Docs/pro-controls.md): which devices can
            // do custom exposure, and what the active format allows.
            let format = device.activeFormat
            let lenses = device.constituentDevices
                .map { "\($0.localizedName):custom=\($0.isExposureModeSupported(.custom))" }
                .joined(separator: ", ")
            debugLog("🌗 EXPOSURE PROBE: \(device.localizedName) custom=\(device.isExposureModeSupported(.custom)) "
                     + "virtual=\(device.isVirtualDevice) lenses=[\(lenses)] "
                     + "shutter \(CMTimeGetSeconds(format.minExposureDuration))–\(CMTimeGetSeconds(format.maxExposureDuration))s "
                     + "ISO \(format.minISO)–\(format.maxISO) bias \(device.minExposureTargetBias)…\(device.maxExposureTargetBias)")
        }
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
    func gatherCurrentCameraCapabilities() async -> RemoteCmd.CameraCapabilitiesResp? {
        await onSessionQueue { self.gatherCurrentCameraCapabilitiesLocked() }
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

        let (deviceEntries, activeDeviceID) = cameraDeviceEntriesLocked()
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
            cameraDevices: deviceEntries,
            activeDeviceID: activeDeviceID,
            // Matches setFocusExposurePointLocked's apply predicate: a device that
            // supports only exposure POI still benefits from a tap.
            supportsFocusPoint: currentDevice.isFocusPointOfInterestSupported
                || currentDevice.isExposurePointOfInterestSupported,
            // This build understands SetCameraPreviewMode; advertise the current
            // persisted mode so the monitor reflects it from the first exchange.
            supportsPreviewMode: true,
            // Every remote is a director now, so every camera takes synced shots.
            supportsMulticam: true,
            previewMode: CameraPreviewModeStore().load(),
            torchOn: currentDevice.hasTorch && currentDevice.torchMode == .on,
            flashMode: cameraSettings.flashMode,
            aspectRatio: currentAspectRatio,
            exposure: exposureStateLocked(currentDevice),
            cinematic: cinematicStateLocked(),
            error: nil
        )

        debugLog("🔍 DEBUG: Created capabilities response successfully")
        return capabilities
    }

    /// The selectable-device list advertised in capabilities — the feature
    /// gate that lets a monitor remote-select this device's cameras.
    private func cameraDeviceEntriesLocked() -> ([RemoteCmd.CameraDeviceEntry], String?) {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        let activeID = logicalDeviceIDLocked()
        let entries = selectableDevicesLocked().map { device in
            RemoteCmd.CameraDeviceEntry(
                uniqueID: device.uniqueID,
                localizedName: device.localizedName,
                positionRaw: device.position.rawValue,
                isActive: device.uniqueID == activeID,
                isSuspended: descriptorLocked(device).isSuspended,
                info: deviceInfoLocked(for: device))
        }
        return (entries, activeID)
    }

    /// Per-device CameraInfo for the advertised list. iOS reuses the cached
    /// position-based info; Mac cameras get a minimal single-lens profile.
    private func deviceInfoLocked(for device: AVCaptureDevice) -> RemoteCmd.CameraInfo? {
        #if targetEnvironment(macCatalyst)
        return RemoteCmd.CameraInfo(
            availableLenses: [.wideAngle],
            hasFlash: device.hasFlash,
            hasTorch: device.hasTorch,
            zoomCapabilities: [.wideAngle: RemoteCmd.ZoomRange(
                minZoom: device.minAvailableVideoZoomFactor,
                maxZoom: device.maxAvailableVideoZoomFactor)])
        #else
        switch device.position {
        case .front: return frontCameraInfo
        case .back: return backCameraInfo
        default: return nil
        }
        #endif
    }

    // MARK: - Focus / Exposure Point

    /// Sets the focus and exposure point of interest from a monitor tap. `point`
    /// is normalized (0..1) in the upright display image (origin top-left). No-op
    /// if the active device supports neither point of interest.
    func setFocusExposurePoint(displayNormalized point: CGPoint) async throws {
        try await onSessionQueueThrowing { try self.setFocusExposurePointLocked(displayNormalized: point) }
    }

    private func setFocusExposurePointLocked(displayNormalized point: CGPoint) throws {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard let device = self.videoDeviceInput?.device else {
            throw NSError(domain: "No camera device available", code: 0, userInfo: nil)
        }

        guard device.isFocusPointOfInterestSupported || device.isExposurePointOfInterestSupported else {
            debugLog("🎯 DEBUG: focus/exposure POI unsupported on \(device.localizedName) — ignoring tap")
            return
        }

        // The buffer the monitor tapped was rotated (and possibly mirrored)
        // before it left the camera; invert both.
        let poi = devicePointLocked(displayNormalized: point)

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        // While Cinematic is on it owns focus: writing focusMode throws, and
        // a tap means "track this subject".
        if #available(iOS 26.0, macCatalyst 26.0, *), videoDeviceInput?.isCinematicVideoCaptureEnabled == true {
            device.setCinematicVideoTrackingFocus(at: poi, focusMode: .strong)
        } else if device.isFocusPointOfInterestSupported {
            device.focusPointOfInterest = poi
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            } else if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            }
        }
        // In manual exposure a tap moves only focus: re-enabling auto exposure
        // here would silently throw away the director's shutter/ISO.
        if device.isExposurePointOfInterestSupported, case .auto = exposureIntent {
            device.exposurePointOfInterest = poi
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            } else if device.isExposureModeSupported(.autoExpose) {
                device.exposureMode = .autoExpose
            }
        }
        debugLog("🎯 DEBUG: focus/exposure POI set to \(poi)")
    }

    /// Restores continuous auto focus/exposure at the center. Called when the
    /// active camera changes so a stale point of interest does not persist.
    func resetFocusExposureToAutoLocked() {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard let device = self.videoDeviceInput?.device,
              device.isFocusPointOfInterestSupported || device.isExposurePointOfInterestSupported,
              (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        let center = CGPoint(x: 0.5, y: 0.5)
        // focusMode is pinned while Cinematic is on (writing it throws).
        var cinematicOwnsFocus = false
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            cinematicOwnsFocus = videoDeviceInput?.isCinematicVideoCaptureEnabled == true
        }
        if device.isFocusPointOfInterestSupported, !cinematicOwnsFocus {
            device.focusPointOfInterest = center
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        }
        if device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = center
            if case .auto = exposureIntent,
               device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        }
    }

    // MARK: - Exposure (EV bias in Auto; shutter + ISO in Manual)

    /// Stores the director's intent and makes the device match it. The
    /// state reply that follows carries the applied truth.
    func setExposure(_ intent: ExposureIntent) async throws {
        // AVFoundation applies exposure settings asynchronously and reports
        // when through the completion handler; the state reply that follows
        // this call must carry the APPLIED value, not the one from a frame
        // ago — so wait for that handler, bounded so a driver that never
        // calls it (some Mac cameras) cannot hang the inbox.
        let applied = Locked(false)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resume: () -> Void = {
                var first = false
                applied.mutate { if !$0 { $0 = true; first = true } }
                if first { continuation.resume() }
            }
            sessionQueue.async {
                guard let device = self.videoDeviceInput?.device else {
                    applied.mutate { $0 = true }
                    return continuation.resume(throwing: NSError(domain: "No camera device available", code: 0, userInfo: nil))
                }
                if case .manual = intent, self.exposureStateLocked(device)?.supportsManual != true {
                    applied.mutate { $0 = true }
                    return continuation.resume(throwing: NSError(
                        domain: NSLocalizedString("This camera can't do manual exposure", comment: "manual exposure refused"),
                        code: 0, userInfo: nil))
                }
                self.exposureIntent = intent
                self.reconcileDeviceLocked()
                self.applyExposureIntentLocked(completion: resume)
                self.sessionQueue.asyncAfter(deadline: .now() + 0.5, execute: resume)
            }
        }
        // A driver can accept the call and change nothing (measured on Mac
        // cameras for the bias). The reply must not claim otherwise.
        let honored = await onSessionQueue { () -> Bool in
            guard let device = self.videoDeviceInput?.device else { return false }
            switch intent {
            case let .auto(bias):
                let expected = min(max(bias, device.minExposureTargetBias), device.maxExposureTargetBias)
                return device.exposureMode != .custom && abs(device.exposureTargetBias - expected) < 0.05
            case .manual:
                return device.exposureMode == .custom
            }
        }
        guard honored else {
            throw NSError(domain: NSLocalizedString("The camera ignored that exposure setting",
                                                    comment: "exposure refused: device did not apply it"),
                          code: 0, userInfo: nil)
        }
    }

    /// The ranges and booleans the policy decides on, read from the active device.
    private func exposureFactsLocked(_ device: AVCaptureDevice) -> ExposureFacts {
        let format = device.activeFormat
        return ExposureFacts(
            supportsCustom: device.isExposureModeSupported(.custom),
            minDurationSeconds: CMTimeGetSeconds(format.minExposureDuration),
            maxDurationSeconds: CMTimeGetSeconds(format.maxExposureDuration),
            minISO: format.minISO,
            maxISO: format.maxISO,
            maxFrameDurationSeconds: CMTimeGetSeconds(device.activeVideoMaxFrameDuration),
            currentDurationSeconds: CMTimeGetSeconds(device.exposureDuration),
            currentISO: device.iso,
            minBias: device.minExposureTargetBias,
            maxBias: device.maxExposureTargetBias)
    }

    /// The exposure block of the state reply, or nil when this device offers
    /// neither EV bias nor manual exposure (capability is presence). Manual
    /// support is judged on the LOGICAL device: a virtual camera counts when
    /// one of its physical lenses accepts `.custom`, since Manual hops there.
    private func exposureStateLocked(_ device: AVCaptureDevice) -> ExposureState? {
        let facts = exposureFactsLocked(device)
        // Cinematic runs on Auto (Manual's physical lens has no Cinematic
        // formats), so the director offers bias only while it is on.
        let logical = logicalDeviceLocked() ?? device
        let supportsManual = manualExposureLensLocked(for: logical) != nil && !cinematicEffectiveLocked(for: logical)
        // A bias moves an AUTO exposure's target, so it is only real on a
        // device that supports an auto exposure mode. The range alone lies:
        // measured 2026-09-22 (CaptureIntegrationTests.testExposureProbe…), a
        // MacBook Pro camera advertises ±8 while supporting no exposure mode
        // at all and ignoring setExposureTargetBias.
        let supportsBias = facts.maxBias > facts.minBias
            && (device.isExposureModeSupported(.continuousAutoExposure) || device.isExposureModeSupported(.autoExpose))
        guard supportsManual || supportsBias else { return nil }
        return ExposureState(
            mode: device.exposureMode == .custom ? .manual : .auto,
            bias: device.exposureTargetBias,
            minBias: facts.minBias,
            maxBias: facts.maxBias,
            targetOffset: device.exposureTargetOffset,
            supportsManual: supportsManual,
            durationSeconds: facts.currentDurationSeconds,
            iso: facts.currentISO,
            minDurationSeconds: facts.minDurationSeconds,
            maxDurationSeconds: facts.maxDurationSeconds,
            minISO: facts.minISO,
            maxISO: facts.maxISO,
            maxFrameDurationSeconds: facts.maxFrameDurationSeconds)
    }

    /// The ONE place that sets the device's exposure mode / bias / duration /
    /// ISO. Called with a fresh intent from the wire, and again after every
    /// device swap and format change so the hardware always reflects
    /// `exposureIntent`.
    /// `completion` runs (on an AVFoundation thread) once the device has
    /// applied the change, or at once when there was nothing to apply.
    private func applyExposureIntentLocked(completion: (() -> Void)? = nil) {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard let device = videoDeviceInput?.device else { completion?(); return }
        let facts = exposureFactsLocked(device)
        let plan = ExposurePolicy.resolve(exposureIntent, facts: facts, isRecording: isRecordingProvider())
        guard (try? device.lockForConfiguration()) != nil else { completion?(); return }
        defer { device.unlockForConfiguration() }
        let done: ((CMTime) -> Void)? = completion.map { done in { _ in done() } }

        switch plan {
        case .unsupported:
            debugLog("🌗 EXPOSURE: \(device.localizedName) cannot do custom exposure — staying auto")
            exposureIntent = .auto(bias: 0)
            fallthrough
        case .auto:
            if device.exposureMode != .continuousAutoExposure,
               device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
                // A long manual shutter may have stretched the frame duration;
                // auto restores the frame rate the quality setting chose.
                try? setFrameRate(framerate: fpsSetting.value, videoDevice: device)
            }
            if case let .auto(bias) = plan, device.exposureTargetBias != bias {
                device.setExposureTargetBias(bias, completionHandler: done)
            } else {
                completion?()
            }
        case let .manual(durationSeconds, iso):
            // Clamp into the format's OWN CMTimes (never rebuild from integers)
            // and re-clamp ISO: out-of-range values raise an NSRangeException
            // that Swift cannot catch.
            let format = device.activeFormat
            var duration = CMTimeMakeWithSeconds(durationSeconds, preferredTimescale: 1_000_000_000)
            if CMTimeCompare(duration, format.minExposureDuration) < 0 { duration = format.minExposureDuration }
            if CMTimeCompare(duration, format.maxExposureDuration) > 0 { duration = format.maxExposureDuration }
            let safeISO = min(max(iso, format.minISO), format.maxISO)
            device.setExposureModeCustom(duration: duration, iso: safeISO, completionHandler: done)
            debugLog("🌗 EXPOSURE: manual \(CMTimeGetSeconds(duration))s ISO \(safeISO) on \(device.localizedName)")
        }
    }

    /// The lens Manual exposure runs on: the device itself when it accepts
    /// `.custom`; for a virtual device (which refuses it), a constituent that
    /// does — the active one while the session runs, else the wide lens.
    ///
    /// Decided from `constituentDevices`, never from `activePrimaryConstituent`
    /// alone: Apple documents that property as nil until the virtual device is
    /// used in a RUNNING session, and the first state exchange happens before
    /// the session starts.
    private func manualExposureLensLocked(for device: AVCaptureDevice) -> AVCaptureDevice? {
        if device.isExposureModeSupported(.custom) { return device }
        guard device.isVirtualDevice else { return nil }
        if let active = device.activePrimaryConstituent, active.isExposureModeSupported(.custom) {
            return active
        }
        let candidates = device.constituentDevices.filter { $0.isExposureModeSupported(.custom) }
        return candidates.first { $0.deviceType == .builtInWideAngleCamera } ?? candidates.first
    }

    /// The physical lens `device` must run on for Manual, or nil when it can
    /// run Manual itself (or Manual is off).
    private func manualExposureHopTargetLocked(for device: AVCaptureDevice) -> AVCaptureDevice? {
        guard case .manual = exposureIntent, !device.isExposureModeSupported(.custom) else { return nil }
        return manualExposureLensLocked(for: device)
    }

    /// The device the session must run for the chosen camera `logical`, or
    /// nil when it runs `logical` itself. Cinematic wins (it forces exposure
    /// to Auto, so the two never both want a hop). Two entry points act on
    /// it — a change of intent (`reconcileDeviceLocked`) and a change of
    /// device (`selectLogicalDeviceLocked`). Re-apply sites never swap:
    /// `swapToDeviceLocked` re-applies both intents, so a swap from there
    /// would recurse.
    private func hopTargetLocked(for logical: AVCaptureDevice) -> AVCaptureDevice? {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        if cinematicEffectiveLocked(for: logical) {
            guard let cinematic = cinematicDeviceLocked(for: logical),
                  cinematic.uniqueID != logical.uniqueID else { return nil }
            return cinematic
        }
        return manualExposureHopTargetLocked(for: logical)
    }

    /// The camera the user chose, as opposed to the one the session is
    /// running: while a hop runs another device for it, the chosen device
    /// stays the LOGICAL camera — the flip decides from it, the picker
    /// highlights it, the state reply reports it, and the hop returns to it.
    private func logicalDeviceIDLocked() -> String? {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        return hopRestoreDeviceID ?? videoDeviceInput?.device.uniqueID
    }

    private func logicalDeviceLocked() -> AVCaptureDevice? {
        guard let id = logicalDeviceIDLocked() else { return nil }
        return selectableDevicesLocked().first { $0.uniqueID == id } ?? videoDeviceInput?.device
    }

    /// A user-chosen device change (flip, picker): re-bases the hop on the
    /// new device — the chosen device becomes the logical camera, and the
    /// session runs whatever device the intents need for it.
    private func selectLogicalDeviceLocked(_ device: AVCaptureDevice,
                                           orientation: UIInterfaceOrientation) throws -> CameraSelectionResult {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        hopRestoreDeviceID = nil
        var target = device
        if let hop = hopTargetLocked(for: device) {
            hopRestoreDeviceID = device.uniqueID
            debugLog("🔀 HOP: \(device.localizedName) runs as \(hop.localizedName)")
            target = hop
        }
        return try swapToDeviceLocked(target, orientation: orientation)
    }

    /// After an intent change: run the device the intents need for the
    /// chosen camera — hop to a physical lens (Manual) or a Cinematic
    /// sibling, or back to the chosen camera itself.
    private func reconcileDeviceLocked() {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard let running = videoDeviceInput?.device, let logical = logicalDeviceLocked() else { return }
        let target = hopTargetLocked(for: logical) ?? logical
        guard target.uniqueID != running.uniqueID else { return }
        hopRestoreDeviceID = target.uniqueID == logical.uniqueID ? nil : logical.uniqueID
        debugLog("🔀 HOP: \(logical.localizedName) now runs as \(target.localizedName)")
        _ = try? swapToDeviceLocked(target, orientation: orientation)
    }

    // MARK: - Cinematic video (iOS 26+)

    /// Stores the director's intent and makes the session match it. Throws
    /// the refusal the state reply carries; the reply's `cinematic` block is
    /// the truth either way.
    func setCinematic(_ intent: CinematicIntent) async throws {
        try await onSessionQueueThrowing {
            guard let running = self.videoDeviceInput?.device else {
                throw NSError(domain: "No camera device available", code: 0, userInfo: nil)
            }
            let logical = self.logicalDeviceLocked() ?? running
            if let refusal = CinematicPolicy.refusal(
                for: intent, isVideoMode: self.isVideoModeProvider(), isRecording: self.isRecordingProvider(),
                aspect: self.currentAspectRatio, supported: self.cinematicDeviceLocked(for: logical) != nil,
                deviceName: logical.localizedName) {
                throw NSError(domain: refusal.message, code: 0, userInfo: nil)
            }
            self.cinematicIntent = intent
            // Exposure first, so the frame rate Auto restores is clamped by
            // the Cinematic apply that follows, never the other way round.
            let exposure = CinematicPolicy.exposureIntent(self.exposureIntent, cinematicOn: intent.enabled)
            if exposure != self.exposureIntent {
                debugLog("🎬 CINEMATIC: Manual exposure off — Cinematic runs on Auto")
                self.exposureIntent = exposure
            }
            self.reconcileDeviceLocked()
            self.applyExposureIntentLocked()
            let on = self.applyCinematicEffectLocked()
            if intent.enabled && !on {
                self.cinematicIntent.enabled = false
                let name = self.videoDeviceInput?.device.localizedName ?? logical.localizedName
                self.reconcileDeviceLocked()
                throw NSError(domain: String(format: NSLocalizedString("%@ refused Cinematic video",
                                                                       comment: "cinematic refused by the session"), name),
                              code: 0, userInfo: nil)
            }
        }
    }

    /// Where Cinematic focuses. A no-op while the effect is off.
    func setCinematicFocus(_ focus: CinematicFocus) async throws {
        try await onSessionQueueThrowing {
            guard #available(iOS 26.0, macCatalyst 26.0, *),
                  let input = self.videoDeviceInput, input.isCinematicVideoCaptureEnabled else { return }
            let device = input.device
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            switch focus {
            case let .subject(id, strength):
                device.setCinematicVideoTrackingFocus(detectedObjectID: id, focusMode: Self.focusMode(strength))
            case let .trackPoint(x, y, strength):
                device.setCinematicVideoTrackingFocus(at: self.devicePointLocked(displayNormalized: CGPoint(x: CGFloat(x), y: CGFloat(y))),
                                                      focusMode: Self.focusMode(strength))
            case let .fixedPoint(x, y):
                device.setCinematicVideoFixedFocus(at: self.devicePointLocked(displayNormalized: CGPoint(x: CGFloat(x), y: CGFloat(y))),
                                                   focusMode: .strong)
            }
            debugLog("🎬 CINEMATIC: focus \(focus)")
        }
    }

    @available(iOS 26.0, macCatalyst 26.0, *)
    private static func focusMode(_ strength: CinematicFocusStrength) -> AVCaptureDevice.CinematicVideoFocusMode {
        switch strength {
        case .weak: return .weak
        case .strong: return .strong
        }
    }

    /// The rig's mode changed: the effect follows video mode (the intent
    /// survives photo mode). Synchronous so the state reply that follows
    /// carries the truth.
    func recordingModeChanged() {
        syncOnSessionQueue {
            guard cinematicIntent.enabled else { return }
            reconcileDeviceLocked()
            applyCinematicEffectLocked()
        }
    }

    /// The editable output's movie file output, for the recorder. Non-nil
    /// exactly while Cinematic is on with `.editable`.
    func cinematicMovieOutputForRecording() -> AVCaptureMovieFileOutput? {
        syncOnSessionQueue { cinematicMovieOutput }
    }

    /// Whether the effect should be on for the chosen camera right now.
    private func cinematicEffectiveLocked(for logical: AVCaptureDevice) -> Bool {
        CinematicPolicy.isEffective(cinematicIntent, isVideoMode: isVideoModeProvider(),
                                    supported: cinematicDeviceLocked(for: logical) != nil)
    }

    /// The device Cinematic runs for the chosen camera (itself, or a
    /// same-position sibling), or nil when there is none. Never on a Mac.
    private func cinematicDeviceLocked(for logical: AVCaptureDevice) -> AVCaptureDevice? {
        #if targetEnvironment(macCatalyst)
        return nil
        #else
        guard #available(iOS 26.0, *) else { return nil }
        let siblings = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInDualWideCamera, .builtInTrueDepthCamera, .builtInTripleCamera,
                          .builtInDualCamera, .builtInWideAngleCamera],
            mediaType: .video, position: logical.position).devices
        func candidate(_ device: AVCaptureDevice) -> CinematicPolicy.DeviceCandidate {
            let kind: CinematicPolicy.DeviceCandidate.Kind
            switch device.deviceType {
            case .builtInDualWideCamera: kind = .dualWide
            case .builtInTrueDepthCamera: kind = .trueDepth
            case .builtInTripleCamera: kind = .triple
            case .builtInDualCamera: kind = .dual
            case .builtInWideAngleCamera: kind = .wide
            default: kind = .other
            }
            let side: CinematicPolicy.DeviceCandidate.Side
            switch device.position {
            case .front: side = .front
            case .back: side = .back
            default: side = .unspecified
            }
            return CinematicPolicy.DeviceCandidate(
                id: device.uniqueID, kind: kind, side: side,
                hasCinematicFormats: device.formats.contains { $0.isCinematicVideoCaptureSupported })
        }
        guard let chosen = CinematicPolicy.device(for: candidate(logical), among: siblings.map(candidate)) else {
            return nil
        }
        return chosen.id == logical.uniqueID ? logical : siblings.first { $0.uniqueID == chosen.id }
        #endif
    }

    @available(iOS 26.0, macCatalyst 26.0, *)
    private static func formatCandidates(_ formats: [AVCaptureDevice.Format]) -> [CinematicPolicy.FormatCandidate] {
        formats.map { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let subtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            let range = format.videoFrameRateRangeForCinematicVideo
            return CinematicPolicy.FormatCandidate(
                width: dims.width, height: dims.height,
                isEightBit: subtype == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                    || subtype == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                minFPS: range?.minFrameRate ?? 0, maxFPS: range?.maxFrameRate ?? 0)
        }
    }

    /// The ONE place that touches `isCinematicVideoCaptureEnabled`,
    /// `simulatedAperture`, the metadata output and the movie output. Runs on
    /// a fresh intent and again after every device swap, quality change and
    /// mode change. Never swaps devices (see `hopTargetLocked`). Returns
    /// whether the effect is on afterwards.
    @discardableResult
    private func applyCinematicEffectLocked() -> Bool {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard #available(iOS 26.0, macCatalyst 26.0, *), let input = videoDeviceInput else { return false }
        // Never reconfigure under a rolling clip (the aperture setter throws
        // mid-take); the coordinator refuses the commands, this is the floor.
        guard !isRecordingProvider() else { return input.isCinematicVideoCaptureEnabled }
        let device = input.device
        let logical = logicalDeviceLocked() ?? device
        let wantOn = cinematicEffectiveLocked(for: logical)
            && cinematicDeviceLocked(for: logical)?.uniqueID == device.uniqueID

        guard wantOn else {
            let attached = captureSession.outputs.contains(cinematicMetadataOutput) || cinematicMovieOutput != nil
            if input.isCinematicVideoCaptureEnabled || attached {
                captureSession.beginConfiguration()
                if input.isCinematicVideoCaptureEnabled { input.isCinematicVideoCaptureEnabled = false }
                captureSession.removeOutput(cinematicMetadataOutput)
                if let movie = cinematicMovieOutput { captureSession.removeOutput(movie) }
                captureSession.commitConfiguration()
                cinematicMovieOutput = nil
                cinematicSubjectContext.value = nil
                debugLog("🎬 CINEMATIC: off on \(device.localizedName)")
                // Back to the format + frame rate the quality setting chose
                // (this also restores zoom, torch and the exposure intent).
                _ = setVideoQualityLocked(resolution: currentVideoResolution, frameRate: currentVideoFrameRate,
                                          isRecording: false)
            }
            onCinematicStateChanged?(cinematicStateLocked())
            return false
        }

        let formats = device.formats.filter { $0.isCinematicVideoCaptureSupported }
        let candidates = Self.formatCandidates(formats)
        // The quality setting follows what Cinematic allows (reported, and
        // restored as-is when Cinematic goes off).
        if let (resolution, frameRate) = CinematicPolicy.quality(
            fitting: currentVideoResolution, currentVideoFrameRate, in: CinematicPolicy.qualities(candidates)) {
            if resolution != currentVideoResolution || frameRate != currentVideoFrameRate {
                currentVideoResolution = resolution
                currentVideoFrameRate = frameRate
                fpsSetting.value = frameRate.value
                onStatusChanged?()
            }
        }
        guard let index = CinematicPolicy.formatIndex(candidates, resolution: currentVideoResolution) else { return false }
        let format = formats[index]

        // Step 1: the format, committed ALONE. The input's support flag reads
        // the session's COMMITTED configuration (measured, and #223's field
        // bug): checked inside the same commit it reads the old answer.
        if device.activeFormat != format {
            captureSession.beginConfiguration()
            captureSession.sessionPreset = .inputPriority
            if (try? device.lockForConfiguration()) != nil {
                device.activeFormat = format
                device.unlockForConfiguration()
            }
            captureSession.commitConfiguration()
        }
        // Step 2: enable, with the metadata output's types set to the
        // required set in the SAME commit (else AVFoundation throws).
        if !input.isCinematicVideoCaptureEnabled {
            guard input.isCinematicVideoCaptureSupported else {
                let outputs = captureSession.outputs.map { String(describing: type(of: $0)) }.joined(separator: ",")
                logWarning("🎬 CINEMATIC: session refuses on \(device.localizedName) outputs=[\(outputs)]")
                return false
            }
            captureSession.beginConfiguration()
            input.isCinematicVideoCaptureEnabled = true
            if !captureSession.outputs.contains(cinematicMetadataOutput),
               captureSession.canAddOutput(cinematicMetadataOutput) {
                captureSession.addOutput(cinematicMetadataOutput)
            }
            if captureSession.outputs.contains(cinematicMetadataOutput) {
                cinematicMetadataOutput.metadataObjectTypes =
                    cinematicMetadataOutput.requiredMetadataObjectTypesForCinematicVideoCapture
            }
            captureSession.commitConfiguration()
            cinematicMetadataOutput.setMetadataObjectsDelegate(self, queue: cinematicMetadataQueue)
            guard input.isCinematicVideoCaptureEnabled else {
                logWarning("🎬 CINEMATIC: enable reverted on \(device.localizedName)")
                return false
            }
            debugLog("🎬 CINEMATIC: on — \(device.localizedName) \(format)")
        }

        // Cinematic narrows frame rate and zoom: clamp into the format's OWN
        // CMTimes, never rebuilt from integers alone.
        if (try? device.lockForConfiguration()) != nil {
            if let range = format.videoFrameRateRangeForCinematicVideo {
                var duration = CMTimeMake(value: 1, timescale: Int32(max(1, currentVideoFrameRate.value)))
                if CMTimeCompare(duration, range.minFrameDuration) < 0 { duration = range.minFrameDuration }
                if CMTimeCompare(duration, range.maxFrameDuration) > 0 { duration = range.maxFrameDuration }
                device.activeVideoMaxFrameDuration = duration
                device.activeVideoMinFrameDuration = duration
            }
            let bounds = cinematicZoomBoundsLocked(device)
            let zoom = min(max(device.videoZoomFactor, bounds.min), bounds.max)
            if device.videoZoomFactor != zoom { device.videoZoomFactor = zoom }
            currentZoomFactor = zoom
            currentLensType = lensTypeForZoomFactor(zoom, device: device)
            device.unlockForConfiguration()
        }

        if format.minSimulatedAperture > 0 {
            let aperture = CinematicPolicy.aperture(
                requested: cinematicIntent.aperture, current: input.simulatedAperture,
                defaultValue: format.defaultSimulatedAperture,
                min: format.minSimulatedAperture, max: format.maxSimulatedAperture)
            if input.simulatedAperture != aperture { input.simulatedAperture = aperture }
        }

        // One output or the other: the editable file needs the movie output.
        if cinematicIntent.output == .editable, cinematicMovieOutput == nil {
            let movie = AVCaptureMovieFileOutput()
            captureSession.beginConfiguration()
            if captureSession.canAddOutput(movie) {
                captureSession.addOutput(movie)
                cinematicMovieOutput = movie
            }
            captureSession.commitConfiguration()
            if cinematicMovieOutput == nil { logWarning("🎬 CINEMATIC: movie output could not be added") }
        } else if cinematicIntent.output == .baked, let movie = cinematicMovieOutput {
            captureSession.beginConfiguration()
            captureSession.removeOutput(movie)
            captureSession.commitConfiguration()
            cinematicMovieOutput = nil
        }
        applyDesiredTorchLocked()   // commits reset the torch
        updateCinematicSubjectContextLocked()
        onCinematicStateChanged?(cinematicStateLocked())
        return input.isCinematicVideoCaptureEnabled
    }

    /// The zoom range the device honors now: Cinematic's own band while on.
    private func cinematicZoomBoundsLocked(_ device: AVCaptureDevice) -> (min: CGFloat, max: CGFloat) {
        let deviceMin = device.minAvailableVideoZoomFactor
        let deviceMax = device.maxAvailableVideoZoomFactor
        if #available(iOS 26.0, macCatalyst 26.0, *), videoDeviceInput?.isCinematicVideoCaptureEnabled == true {
            let low = max(deviceMin, device.activeFormat.videoMinZoomFactorForCinematicVideo)
            let high = min(deviceMax, device.activeFormat.videoMaxZoomFactorForCinematicVideo)
            if high >= low { return (low, high) }
        }
        return (deviceMin, deviceMax)
    }

    /// The Cinematic block of the state reply, or nil when the chosen camera
    /// can't do Cinematic (capability is presence).
    private func cinematicStateLocked() -> CinematicState? {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard #available(iOS 26.0, macCatalyst 26.0, *), let input = videoDeviceInput else { return nil }
        let running = input.device
        let logical = logicalDeviceLocked() ?? running
        guard let target = cinematicDeviceLocked(for: logical) else { return nil }
        let formats = target.formats.filter { $0.isCinematicVideoCaptureSupported }
        let candidates = Self.formatCandidates(formats)
        let enabled = input.isCinematicVideoCaptureEnabled
        let format: AVCaptureDevice.Format
        if enabled {
            format = running.activeFormat
        } else if let index = CinematicPolicy.formatIndex(candidates, resolution: currentVideoResolution) {
            format = formats[index]
        } else {
            return nil
        }
        let aperture = enabled
            ? input.simulatedAperture
            : CinematicPolicy.aperture(requested: cinematicIntent.aperture, current: 0,
                                       defaultValue: format.defaultSimulatedAperture,
                                       min: format.minSimulatedAperture, max: format.maxSimulatedAperture)
        return CinematicState(
            enabled: enabled,
            output: cinematicIntent.output,
            aperture: aperture,
            minAperture: format.minSimulatedAperture,
            maxAperture: format.maxSimulatedAperture,
            defaultAperture: format.defaultSimulatedAperture,
            qualities: CinematicPolicy.qualities(candidates))
    }

    /// The display geometry every point mapping uses — tap to focus and the
    /// Cinematic subject boxes alike: the orientation the streamed buffer was
    /// rotated into, and whether the streamed buffer is mirrored. Mirroring
    /// is read from the data-output connection, never assumed from the
    /// camera position: measured on an iPhone 14 (2026-09-25), the front
    /// camera's data output is NOT mirrored (only the local preview layer is).
    private func displayGeometryLocked() -> (orientation: AVCaptureVideoOrientation, mirrored: Bool) {
        let videoOrientation: AVCaptureVideoOrientation =
            OrientationUtils.appliesInterfaceRotation
            ? OrientationUtils.transform(o: self.orientation)
            : .landscapeRight
        return (videoOrientation, videoConnection?.isVideoMirrored ?? false)
    }

    /// A director point (upright display space) in device space.
    private func devicePointLocked(displayNormalized point: CGPoint) -> CGPoint {
        let geometry = displayGeometryLocked()
        return FocusPointMapping.devicePoint(displayNormalized: point,
                                             videoOrientation: geometry.orientation,
                                             mirrored: geometry.mirrored)
    }

    private func updateCinematicSubjectContextLocked() {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard #available(iOS 26.0, macCatalyst 26.0, *),
              let input = videoDeviceInput, input.isCinematicVideoCaptureEnabled else {
            cinematicSubjectContext.value = nil
            return
        }
        let geometry = displayGeometryLocked()
        cinematicSubjectContext.value = CinematicSubjectContext(
            device: input.device, orientation: geometry.orientation, mirrored: geometry.mirrored)
    }

    // MARK: - Enhanced Zoom Control Methods
    func setZoom(zoomFactor: CGFloat) async throws -> (CGFloat, CameraLensType, RemoteCmd.ZoomRange) {
        try await onSessionQueueThrowing { try self.setZoomLocked(zoomFactor: zoomFactor) }
    }

    private func setZoomLocked(zoomFactor: CGFloat) throws -> (CGFloat, CameraLensType, RemoteCmd.ZoomRange) {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        debugLog("🔍 DEBUG: setZoom called with factor: \(zoomFactor)")

        guard let device = self.videoDeviceInput?.device else {
            debugLog("❌ DEBUG: No camera device available")
            throw NSError(domain: "No camera device available", code: 0, userInfo: nil)
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

            return (clampedZoom, currentLensType, zoomRange)
        } catch let error as NSError {
            debugLog("❌ DEBUG: Error setting zoom: \(error.localizedDescription)")
            throw error
        }
    }

    func getCurrentZoomFactor() async -> CGFloat {
        await onSessionQueue { self.videoDeviceInput?.device.videoZoomFactor ?? 1.0 }
    }

    func getMaxZoomFactor() async -> CGFloat {
        await onSessionQueue { self.videoDeviceInput?.device.maxAvailableVideoZoomFactor ?? 1.0 }
    }

    func getMinZoomFactor() async -> CGFloat {
        await onSessionQueue { self.videoDeviceInput?.device.minAvailableVideoZoomFactor ?? 1.0 }
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

    func switchLens(to lensType: CameraLensType) async throws -> (CameraLensType, [CameraLensType], CGFloat, RemoteCmd.ZoomRange) {
        try await onSessionQueueThrowing { try self.switchLensLocked(to: lensType) }
    }

    private func switchLensLocked(to lensType: CameraLensType) throws -> (CameraLensType, [CameraLensType], CGFloat, RemoteCmd.ZoomRange) {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard let device = self.videoDeviceInput?.device else {
            throw NSError(domain: "No camera device available", code: 0, userInfo: nil)
        }

        let targetZoom = zoomFactorForLensType(lensType, device: device)
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
        return (lensType, availableLensTypes, currentZoomFactor, zoomRange)
    }

    func getAvailableLensTypes() async -> [CameraLensType] {
        await onSessionQueue { self.availableLensTypes }
    }

    func getCurrentLensType() async -> CameraLensType {
        await onSessionQueue { self.currentLensType }
    }

    func getZoomStops() async -> [CGFloat] {
        await onSessionQueue { self.zoomStops }
    }

    func getWideAngleZoomFactor() async -> CGFloat {
        await onSessionQueue {
            guard let device = self.videoDeviceInput?.device else { return 1.0 }
            return self.wideAngleZoomFactor(for: device)
        }
    }

    /// Applies `orientation` to the video-data and photo output connections and
    /// caches it for still capture. Returns whether the photo connection existed,
    /// so the caller can mirror the original preview-frame refresh timing.
    @discardableResult
    func rotateOutputs(orientation: UIInterfaceOrientation) -> Bool {
        syncOnSessionQueue { rotateOutputsLocked(orientation: orientation) }
    }

    @discardableResult
    private func rotateOutputsLocked(orientation: UIInterfaceOrientation) -> Bool {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        self.orientation = orientation
        let o = OrientationUtils.transform(o: orientation)
        if let videoConnection = self.videoConnection {
            applyCaptureOrientationLocked(o, to: videoConnection)
        }
        if let movieConnection = cinematicMovieOutput?.connection(with: .video) {
            applyCaptureOrientationLocked(o, to: movieConnection)
        }
        updateCinematicSubjectContextLocked()   // subject boxes follow the display rotation
        if let photoConnection = self.photoOutput.connection(with: AVMediaType.video) {
            applyCaptureOrientationLocked(o, to: photoConnection)
            return true
        }
        return false
    }

    /// The only place capture-connection orientation is ever written. The
    /// pipeline invariant is that buffers leave the connection upright —
    /// everything downstream (encoders, wire, monitor, Watch, recorder) is
    /// orientation-preserving. iOS sensors are portrait-native and need the
    /// interface-derived rotation; Mac cameras are landscape-native and
    /// already upright, so `appliesInterfaceRotation` is false on Catalyst.
    private func applyCaptureOrientationLocked(_ o: AVCaptureVideoOrientation,
                                               to connection: AVCaptureConnection) {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard OrientationUtils.appliesInterfaceRotation,
              connection.isVideoOrientationSupported else { return }
        connection.videoOrientation = o
    }

    /// Chooses the frame-rate range closest to the request. Supported rates
    /// form disjoint ranges (a Mac camera's format may support exactly
    /// 60–60), and a rate outside every range raises an Objective-C exception
    /// that Swift cannot catch — so the answer is always inside a range,
    /// never merely below the maximum. Ties prefer the lower rate (don't
    /// exceed the request unnecessarily); nil when no ranges are reported.
    static func resolveFrameRate(requested: Int,
                                 supportedRanges: [ClosedRange<Double>]) -> (fps: Int, rangeIndex: Int)? {
        let requestedFPS = Double(requested)
        let nearest = supportedRanges.enumerated()
            .map { (index: $0.offset,
                    fps: min(max(requestedFPS, $0.element.lowerBound), $0.element.upperBound)) }
            .min { (abs($0.fps - requestedFPS), $0.fps) < (abs($1.fps - requestedFPS), $1.fps) }
        return nearest.map { (fps: Int($0.fps), rangeIndex: $0.index) }
    }

    func setFrameRate(framerate: Int, videoDevice: AVCaptureDevice) throws {
        let ranges = videoDevice.activeFormat.videoSupportedFrameRateRanges
        guard let resolved = Self.resolveFrameRate(
                requested: framerate,
                supportedRanges: ranges.map { $0.minFrameRate...$0.maxFrameRate }) else {
            return   // no ranges reported: leave the device's defaults alone
        }
        // Clamp the desired duration into the chosen range's OWN CMTimes —
        // never rebuild from integers. A UVC camera's "60 fps" is often
        // 59.99976 (1000000/60000240): an integer 1/60 falls outside the
        // range, which throws on DAL hardware and silently wedges software
        // cameras (OBS stopped delivering frames entirely).
        let range = ranges[resolved.rangeIndex]
        var duration = CMTimeMake(value: 1, timescale: Int32(max(1, resolved.fps)))
        if CMTimeCompare(duration, range.minFrameDuration) < 0 { duration = range.minFrameDuration }
        if CMTimeCompare(duration, range.maxFrameDuration) > 0 { duration = range.maxFrameDuration }

        try videoDevice.lockForConfiguration()
        videoDevice.activeVideoMaxFrameDuration = duration
        videoDevice.activeVideoMinFrameDuration = duration
        videoDevice.unlockForConfiguration()

        let safeFPS = resolved.fps
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

    func setVideoQuality(resolution: VideoResolution, frameRate: VideoFrameRate, isRecording: Bool) async -> (VideoResolution, VideoFrameRate)? {
        await onSessionQueue { self.setVideoQualityLocked(resolution: resolution, frameRate: frameRate, isRecording: isRecording) }
    }

    private func setVideoQualityLocked(resolution: VideoResolution, frameRate: VideoFrameRate, isRecording: Bool) -> (VideoResolution, VideoFrameRate)? {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard !isRecording else { return nil }
        guard let device = videoDeviceInput?.device else { return nil }

        // While Cinematic is on, only its formats' qualities apply, and the
        // Cinematic apply picks the format.
        if let cinematic = cinematicStateLocked(), cinematic.enabled {
            guard CinematicPolicy.allows(resolution: resolution, frameRate: frameRate, in: cinematic) else { return nil }
            currentVideoResolution = resolution
            currentVideoFrameRate = frameRate
            fpsSetting.value = frameRate.value
            applyCinematicEffectLocked()
            applyExposureIntentLocked()
            onStatusChanged?()
            return (currentVideoResolution, currentVideoFrameRate)
        }

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
        applyExposureIntentLocked()   // ranges and the frame-rate cap changed with the format

        currentVideoResolution = resolution
        currentVideoFrameRate = appliedFrameRate
        fpsSetting.value = appliedFrameRate.value
        onStatusChanged?()

        return (resolution, appliedFrameRate)
    }

    // MARK: - Aspect Ratio Methods

    func setAspectRatio(_ ratio: AspectRatio) async -> AspectRatio {
        await onSessionQueue {
            // The editable Cinematic file is 16:9 only: while it is the
            // output the aspect stays put, and the state reply says so.
            if self.cinematicIntent.enabled,
               !CinematicPolicy.allows(aspect: ratio, output: self.cinematicIntent.output) {
                return self.currentAspectRatio
            }
            self.currentAspectRatio = ratio
            self.onStatusChanged?()
            return ratio
        }
    }

    /// Aspect ratio for callers outside the session queue (the photo-capture
    /// callback and the pipeline's record-start snapshot).
    func currentAspectRatioValue() -> AspectRatio {
        syncOnSessionQueue { currentAspectRatio }
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

    func setPhotoQuality(format: PhotoFormat, hdrMode: HDRMode) async -> (PhotoFormat, HDRMode)? {
        await onSessionQueue {
            if format == .heif {
                guard self.photoOutput.availablePhotoCodecTypes.contains(.hevc) else { return nil }
            }

            self.currentPhotoFormat = format
            self.currentHDRMode = hdrMode
            self.onStatusChanged?()
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

/// What the Cinematic metadata callback needs, snapshotted on the session
/// queue: the device (for the light warning) and the display geometry that
/// maps its boxes into the director's upright image.
struct CinematicSubjectContext {
    let device: AVCaptureDevice
    let orientation: AVCaptureVideoOrientation
    let mirrored: Bool
}

// MARK: - Cinematic subjects (metadata output)

extension CaptureEngine: AVCaptureMetadataOutputObjectsDelegate {

    /// Publish rate for the director's subject boxes.
    static let cinematicSubjectsInterval: TimeInterval = 0.1

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        dispatchPrecondition(condition: .onQueue(cinematicMetadataQueue))
        guard #available(iOS 26.0, macCatalyst 26.0, *),
              let context = cinematicSubjectContext.value else { return }
        let subjects = metadataObjects.compactMap { Self.cinematicSubject($0, context: context) }
        // ~10 Hz, but a scene that just emptied is always published so the
        // director's last boxes don't linger.
        let now = CACurrentMediaTime()
        let emptied = subjects.isEmpty && lastSubjectsCount > 0
        guard emptied || now - lastSubjectsPublishAt >= Self.cinematicSubjectsInterval else { return }
        lastSubjectsPublishAt = now
        lastSubjectsCount = subjects.count
        let notEnoughLight = context.device.cinematicVideoCaptureSceneMonitoringStatuses.contains(.notEnoughLight)
        onCinematicSubjects?(CinematicSubjectsReport(subjects: subjects, notEnoughLight: notEnoughLight))
    }

    @available(iOS 26.0, macCatalyst 26.0, *)
    static func cinematicSubject(_ object: AVMetadataObject, context: CinematicSubjectContext) -> CinematicSubject? {
        let kind: CinematicSubjectKind
        switch object.type {
        case .face: kind = .face
        case .humanBody: kind = .humanBody
        case .catHead: kind = .catHead
        case .catBody: kind = .catBody
        case .dogHead: kind = .dogHead
        case .dogBody: kind = .dogBody
        case .salientObject: kind = .salientObject
        default:
            // A fixed focus arrives as its own object; show it as a subject
            // so the director sees where focus is held.
            guard object.isFixedFocus else { return nil }
            kind = .salientObject
        }
        let focus: CinematicFocusStrength?
        switch object.cinematicVideoFocusMode {
        case .strong: focus = .strong
        case .weak: focus = .weak
        default: focus = nil
        }
        return CinematicSubject(
            id: object.objectID, groupID: object.groupID, kind: kind,
            rect: FocusPointMapping.displayRect(deviceNormalized: object.bounds,
                                                videoOrientation: context.orientation,
                                                mirrored: context.mirrored),
            focus: focus, isFixedFocus: object.isFixedFocus)
    }
}
