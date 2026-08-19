//
//  RecordingPipeline.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import Foundation
import AVFoundation
import Photos
import CoreImage

/// Single-point storage policy for recording video. Pure, pinned by unit
/// tests — the one place a free-space number becomes a go/no-go decision.
enum RecordingStoragePolicy {
    /// Minimum available capacity to start a video recording.
    static let minimumFreeBytesToStart: Int64 = 100_000_000

    /// `freeBytes` is `volumeAvailableCapacityForImportantUsage` — the space
    /// the system will actually grant a user-initiated write (raw free blocks
    /// plus purgeable space it reclaims on demand), which is also the number
    /// Settings shows the user. nil = the capacity could not be read; that
    /// never blocks the user (fail open — the writer-death funnel is the
    /// backstop if the disk really is full).
    static func canStart(freeBytes: Int64?) -> Bool {
        guard let freeBytes else { return true }
        return freeBytes >= minimumFreeBytesToStart
    }
}

/**
 Owns the video-recording path: the asset writer, its inputs, the recording
 state machine, per-frame writing/cropping, and saving/sending the finished
 movie. Non-UI — the frame streaming coordinator feeds it sample buffers, and
 the rig/shell reach back in through the closure seams below.

 Threading: ALL recording state lives on the engine's `dataOutputQueue` — the
 same serial queue that delivers both video and audio sample buffers, so
 `processFrame` is naturally serialized. Record start syncs once into the
 engine's `sessionQueue` for the audio-input configuration (one-way; the
 session queue never syncs back). The only cross-queue reads are through
 `recordingStartedAt`/`isRecording`, backed by one `Locked<Date?>`.
 */
class RecordingPipeline {

    /// The capture session, outputs, queues and configuration live on the engine.
    private let engine: CaptureEngine

    private var dataQueue: DispatchQueue { engine.dataOutputQueue }

    // MARK: - UI/actor seams

    /// Relays actor messages (`StartRecordingVideoAck`, `StopRecordingVideoResp`,
    /// `SendVideoResource`) — the pipeline never touches the actor system directly.
    var sendMessage: ((Message) -> Void)?
    /// Recording actually began (first frames written). Main thread. The ack to the
    /// monitor is sent through `sendMessage` right after this fires.
    var onRecordingStarted: ((Date) -> Void)?
    /// Recording is stopping — clear the timer display. Main thread.
    var onRecordingStopped: (() -> Void)?
    /// Chrome update: `idle == true` → idle mode, else video-recording mode. Main thread.
    var onModeChanged: ((_ idle: Bool) -> Void)?
    /// Unrecoverable start failure ("Unable to start recording"). Fires on the
    /// data queue — hop to main before touching UIKit.
    var onError: ((String) -> Void)?
    /// Photos-library access denied while saving the finished movie. Main thread.
    var onPhotosAccessDenied: (() -> Void)?

    // MARK: - Recording state (dataQueue-confined)

    /// The recording's real start instant — non-nil exactly while the writer
    /// is accepting frames, and the ONLY stored recording truth. Everything
    /// else derives from it: `isRecording`, the wire's
    /// `recording_start_unix_ms` (nil ⇔ 0), the cross-queue readers
    /// (`shouldAutorotate` on main, `setVideoQuality`'s guard on the actor
    /// mailbox, watch snapshots), and both timers. Lock-backed so those
    /// readers never touch the data queue.
    private let recordingStartShared = Locked<Date?>(nil)
    var isRecording: Bool { recordingStartShared.value != nil }
    var recordingStartedAt: Date? { recordingStartShared.value }

    private(set) var recordingWillBeStarted: Bool = false
    private(set) var recordingWillBeStopped: Bool = false
    private var readyToRecordVideo: Bool = false
    private var readyToRecordAudio: Bool = false

    private var assetWriter: AVAssetWriter?
    private(set) var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private(set) var cachedVideoCropRect: CGRect? // Computed once at recording start, reused per frame

    /// Aspect ratio snapshotted from the engine when recording starts — the
    /// writer geometry must not chase a mid-recording aspect change.
    var recordingAspectRatio: AspectRatio = .sixteenNine

    /// Set for a synced multicam recording only: embeds the shot's alignment
    /// fields as QuickTime metadata in the .mov and names the saved clip
    /// `RS_<sess>_<cap>_cam<k>.mov`. Nil for ordinary single-camera recording,
    /// which writes and saves exactly as before. Consumed (cleared) when the
    /// clip is saved.
    var pendingSyncMetadata: CaptureSyncMetadata?

    private let videoCropContext = CIContext(options: [.useSoftwareRenderer: false])

    private var videoInput: AVAssetWriterInput!
    private var audioInput: AVAssetWriterInput!

    init(engine: CaptureEngine) {
        self.engine = engine
    }

    /// Seam for the audio-configuration leg. Tests pin it (simulators differ
    /// on whether an audio capture device exists); production configures the
    /// engine's audio input on its session queue.
    lazy var configureAudio: (AVCaptureAudioDataOutputSampleBufferDelegate) -> Bool = { [weak self] delegate in
        self?.engine.configureAudioForRecording(delegate: delegate) ?? false
    }

    /// Seam for the storage gate (tests pin the refusal deterministically);
    /// production reads the recording volume's important-usage capacity.
    lazy var freeSpaceForRecording: () -> Int64? = {
        RecordingPipeline.availableCapacity(at: movieUrl())
    }

    // MARK: - Start / stop

    /// Configures the audio leg (on the engine's session queue) and starts
    /// recording. The caller's coordinator remains the audio delegate.
    func startRecording(audioSampleBufferDelegate: AVCaptureAudioDataOutputSampleBufferDelegate) {
        dataQueue.async { [weak self] in
            guard let self = self else { return }
            if self.recordingWillBeStarted || self.isRecording {
                return
            }

            // Refuse to start on a nearly full disk — the writer would die
            // mid-take instead of failing cleanly here. One upfront check, no
            // polling; the writer-death funnel below covers the disk filling
            // AFTER a legitimate start.
            guard RecordingStoragePolicy.canStart(freeBytes: self.freeSpaceForRecording()) else {
                self.failRecording(Self.localizedRecordingError("insufficient_storage_error"),
                                   hasClip: false)
                return
            }

            // One-way hop: data queue may sync into the session queue, never
            // the reverse. No usable microphone (hardware missing, or the
            // audio session is held — e.g. an active phone call): refuse to
            // record rather than silently produce soundless video the user
            // only discovers at playback. The session states route this to
            // error acks on the remote and an error alert on the camera.
            guard self.configureAudio(audioSampleBufferDelegate) else {
                let message = NSLocalizedString("Unable to record audio", comment: "")
                self.sendMessage?(UICmd.MicrophoneAccessDenied(error: NSError(
                    domain: "RemoteShutterError", code: 1002,
                    userInfo: [NSLocalizedDescriptionKey: message])))
                self.onError?(message)
                return
            }
            self.recordingAspectRatio = self.engine.currentAspectRatioValue()

            self.startVideoRecordingProcess()
        }
    }

    private func startVideoRecordingProcess() {
        dispatchPrecondition(condition: .onQueue(dataQueue))
        if self.recordingWillBeStarted || self.isRecording {
            return
        }

        self.recordingWillBeStarted = true

        // Remove the file if one with the same name already exists
        let outputFilePath = movieUrl()
        cleanupFileAt(outputFilePath)
        // Create an asset writer
        do {
            let writer = try AVAssetWriter(outputURL: outputFilePath, fileType: .mov)
            // Fragmented QuickTime: without this an interrupted take (disk
            // full, crash, kill) has no moov atom and is unplayable — with it
            // the file stays playable up to the last written fragment, so
            // footage that was written is never lost.
            writer.movieFragmentInterval = CMTime(seconds: 5, preferredTimescale: 600)
            // Synced multicam: embed the shot's alignment fields in the file so
            // an editor can group and time-align the angles. The anchor rides
            // as an opaque numeric key, not a wall-clock date.
            if let metadata = pendingSyncMetadata {
                writer.metadata = metadata.quickTimeMetadataItems()
            }
            self.assetWriter = writer
        } catch {
            failRecording(Self.localizedRecordingError("Unable to start recording"), hasClip: false)
            return
        }
        OperationQueue.main.addOperation { [weak self] in
            self?.onModeChanged?(false)
        }
    }

    func stopRecording(_ shouldSendVideo: Bool) {
        dataQueue.async { [weak self] in
            guard let self = self else { return }
            if self.recordingWillBeStopped || !self.isRecording {
                return
            }
            // A writer that already died (disk full) cannot be finalized —
            // `finishWriting` traps on a failed writer. The funnel salvages
            // the fragmented file instead.
            if let writer = self.assetWriter, writer.status == .failed {
                self.failRecording(Self.writerFailureError(writer), hasClip: true)
                return
            }
            // The stop raced the ready edge: no frame was ever written, so the
            // writer never started (`finishWriting` traps on .unknown) and
            // there is no footage. Reset and answer the stop as an empty take.
            if let writer = self.assetWriter, writer.status == .unknown {
                self.resetRecordingState()
                cleanupFileAt(movieUrl())
                DispatchQueue.main.async { [weak self] in
                    self?.onRecordingStopped?()
                    self?.onModeChanged?(true)
                }
                self.sendMessage?(RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: nil))
                return
            }
            self.recordingStartShared.value = nil
            self.recordingWillBeStopped = true

            // Stop recording timer
            DispatchQueue.main.async { [weak self] in
                self?.onRecordingStopped?()
            }
            self.assetWriter?.finishWriting { [weak self] in
                // The writer calls back on its own queue — hop home before
                // touching recording state.
                guard let self = self else { return }
                self.dataQueue.async { [weak self] in
                    guard let self = self else { return }
                    let finalizeError: NSError? = (self.assetWriter?.status == .completed)
                        ? nil
                        : Self.writerFailureError(self.assetWriter)
                    self.resetRecordingState()
                    if let finalizeError {
                        // Finalize failed under the stop — the fragmented
                        // file is still playable up to the last fragment:
                        // save what exists and report the truth instead of
                        // pretending the stop succeeded.
                        self.saveMovieToPhotosApp()
                        self.onError?(finalizeError.localizedDescription)
                        self.sendMessage?(UICmd.RecordingTerminated(error: finalizeError))
                    } else {
                        self.saveMovieToPhotosAppAndRemotePeer(shouldSendVideo)
                    }
                }
            }
            OperationQueue.main.addOperation { [weak self] in
                self?.onModeChanged?(true)
            }
        }
    }

    /// Tears down every piece of per-recording state — the phase flags, the
    /// writer references, and the shared truth — leaving the pipeline idle.
    /// The one reset used by the stop completion, the empty-take stop, and
    /// the failure funnel, so no path can forget a field. Data queue only.
    private func resetRecordingState() {
        dispatchPrecondition(condition: .onQueue(dataQueue))
        recordingWillBeStarted = false
        recordingWillBeStopped = false
        readyToRecordVideo = false
        readyToRecordAudio = false
        assetWriter = nil
        pixelBufferAdaptor = nil
        cachedVideoCropRect = nil
        recordingStartShared.value = nil
    }

    // MARK: - Failure funnel

    /// Every abnormal end of a recording lands here, on the data queue: the
    /// storage gate refusing a start, a writer that cannot start, and a
    /// writer that dies mid-take (disk full). One funnel so no path can leave
    /// the flags wedged or the peers believing a dead recording is rolling:
    /// state is reset, salvageable footage is saved to Photos (`hasClip`),
    /// the user sees the error, and the coordinator gets
    /// `UICmd.RecordingTerminated` to route the truth to the remote.
    private func failRecording(_ error: NSError, hasClip: Bool) {
        dispatchPrecondition(condition: .onQueue(dataQueue))
        // Dropping a failed writer is safe — it is not mid-finalize (a failed
        // writer cannot be finalized at all); the fragmented file on disk is
        // the recording.
        resetRecordingState()
        DispatchQueue.main.async { [weak self] in
            self?.onRecordingStopped?()
            self?.onModeChanged?(true)
        }
        if hasClip { saveMovieToPhotosApp() }
        onError?(error.localizedDescription)
        sendMessage?(UICmd.RecordingTerminated(error: error))
    }

    /// A user-facing error for a dead writer: names the storage cause when
    /// that is what killed it (the overwhelmingly common case), otherwise a
    /// generic recording failure carrying the system's description.
    private static func writerFailureError(_ writer: AVAssetWriter?) -> NSError {
        let underlying = writer?.error as NSError?
        let diskFull = underlying?.domain == AVFoundationErrorDomain
            && underlying?.code == AVError.diskFull.rawValue
        return localizedRecordingError(
            diskFull ? "recording_stopped_disk_full_error" : "recording_failed_error")
    }

    /// The message rides in BOTH the domain and the localized description:
    /// the monitor's two error-display conventions read one or the other.
    private static func localizedRecordingError(_ key: String) -> NSError {
        let message = NSLocalizedString(key, comment: "")
        return NSError(domain: message, code: 0,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }

    /// `volumeAvailableCapacityForImportantUsage` for the volume holding the
    /// recording's output file. nil when unreadable.
    private static func availableCapacity(at url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }

    // MARK: - Saving / sending the finished movie

    private func saveMovieToPhotosAppAndRemotePeer(_ sendVideoToPeer: Bool) {
        // Send video to the monitor using resource transfer if requested
        if sendVideoToPeer {
            sendVideoAsResource(movieUrl())
        } else {
            // Send empty response when not sending video
            sendMessage?(RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: nil))
        }
        saveMovieToPhotosApp()
    }

    /// Saves the movie file to Photos. Also the salvage half of the failure
    /// funnel: with fragmented writing, a dead writer's file is playable up to
    /// its last fragment and is saved like any finished clip.
    private func saveMovieToPhotosApp() {
        let outputFileURL = movieUrl()

        // Check the authorization status.
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            if status == .authorized {
                // Save the movie file to the photo library and cleanup.
                let syncMetadata = self?.pendingSyncMetadata
                PHPhotoLibrary.shared().performChanges({
                    let options = PHAssetResourceCreationOptions()
                    // A multicam clip is COPIED (not moved) so the temp file
                    // survives the staggered/retried auto-collect transfer to
                    // the director; the next recording cleans it up.
                    options.shouldMoveFile = (syncMetadata == nil)
                    // Synced clip: name it under the shared RS_ group.
                    if let syncMetadata { options.originalFilename = syncMetadata.videoFilename() }
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    creationRequest.addResource(with: .video, fileURL: outputFileURL, options: options)
                }, completionHandler: { [weak self] success, error in
                    if !success {
                        logWarning("AVCam couldn't save the movie to your photo library: \(String(describing: error))")
                        // A failed save is a lost clip — never just a log line.
                        self?.onError?(NSLocalizedString("Unable to save video", comment: ""))
                    }
                    if syncMetadata == nil { cleanupFileAt(outputFileURL) }
                }
                )
                self?.pendingSyncMetadata = nil
            } else {
                DispatchQueue.main.async {
                    self?.onPhotosAccessDenied?()
                }
                cleanupFileAt(outputFileURL)
            }
        }
    }

    private func sendVideoAsResource(_ videoURL: URL) {
        // Send message to RemoteCamSession actor to handle video resource transfer
        let sendVideoMsg = UICmd.SendVideoResource(
            videoURL: videoURL,
            peers: [], // Will be populated by the actor from its session
            shouldSendToPeer: true,
            sender: nil
        )

        sendMessage?(sendVideoMsg)
    }

    // MARK: - Asset writer inputs

    func setupAssetWriterVideoInput(_ formatDescription: CMVideoFormatDescription,
                                    assetWriter: AVAssetWriter) -> Bool {
        // Ask for settings that are COHERENT with the codec we want, rather than taking
        // the generic recommendation and overwriting AVVideoCodecKey. The recommendation
        // carries compression properties keyed to the codec it chose: on a Mac it returns
        // avc1 with H.264 profile levels, so patching HEVC over the top produced a
        // dictionary `canApply` refused — the video input was never added,
        // readyToRecordVideo never flipped, recording never started, and `stopRecording`
        // then early-returned in silence while the monitor waited forever. (On iPhone the
        // recommendation is already HEVC, so the overwrite was a no-op and it worked.)
        // Fall back to the plain recommendation where HEVC isn't offered: a recording in
        // the device's preferred codec beats no recording at all.
        var videoSettings = self.engine.videoDataOutput.recommendedVideoSettings(
            forVideoCodecType: .hevc, assetWriterOutputFileType: .mov)
            ?? self.engine.videoDataOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov)

        let dims = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let sourceWidth = CGFloat(dims.width)
        let sourceHeight = CGFloat(dims.height)

        // Compute and cache the crop rect once — reused for every frame
        let needsCrop = recordingAspectRatio != .sixteenNine
        if needsCrop, let rawRect = CaptureEngine.cropRect(sourceWidth: sourceWidth, sourceHeight: sourceHeight, aspectRatio: recordingAspectRatio) {
            // Round to even for codec compatibility
            let evenRect = CGRect(
                x: floor(rawRect.origin.x / 2) * 2,
                y: floor(rawRect.origin.y / 2) * 2,
                width: floor(rawRect.width / 2) * 2,
                height: floor(rawRect.height / 2) * 2
            )
            cachedVideoCropRect = evenRect

            if var settings = videoSettings {
                settings[AVVideoWidthKey] = Int(evenRect.width)
                settings[AVVideoHeightKey] = Int(evenRect.height)
                videoSettings = settings
            }
        } else {
            cachedVideoCropRect = nil
        }

        if assetWriter.canApply(outputSettings: videoSettings, forMediaType: .video) {
            videoInput = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true

            if let cropRect = cachedVideoCropRect {
                // Pool attributes match output dimensions — avoids per-frame CVPixelBufferCreate
                let poolAttrs: [String: Any] = [
                    kCVPixelBufferWidthKey as String: Int(cropRect.width),
                    kCVPixelBufferHeightKey as String: Int(cropRect.height),
                    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
                ]
                pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: videoInput,
                    sourcePixelBufferAttributes: poolAttrs)
            } else {
                pixelBufferAdaptor = nil
            }

            if assetWriter.canAdd(videoInput) {
                assetWriter.add(videoInput)
            } else {
                debugLog("❌ recording: asset writer refused the video input")
                return false
            }
        } else {
            debugLog("❌ recording: video settings rejected by canApply — \(String(describing: videoSettings))")
            return false
        }
        return true
    }

    func setupAssetWriterAudioInput(_ formatDescription: CMFormatDescription,
                                    assetWriter: AVAssetWriter) -> Bool {
        let audioSettings = [AVFormatIDKey: kAudioFormatMPEG4AAC]
        if assetWriter.canApply(outputSettings: audioSettings, forMediaType: .audio) {
            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings, sourceFormatHint: formatDescription)
            audioInput.expectsMediaDataInRealTime = true

            if assetWriter.canAdd(audioInput) {
                assetWriter.add(audioInput)
            } else {
                logWarning("Cannot add audio input to asset writer")
                return false
            }
        } else {
            logWarning("Cannot apply audio settings to asset writer")
            return false
        }
        return true
    }

    // MARK: - Per-frame path (dataQueue: both delegates deliver here)

    func processFrame(_ captureOutput: AVCaptureOutput,
                      didOutput sampleBuffer: CMSampleBuffer) {
        dispatchPrecondition(condition: .onQueue(dataQueue))

        if let assetWriter = self.assetWriter {
            let wasReadyToRecord = (readyToRecordAudio && readyToRecordVideo)
            if captureOutput === self.engine.videoDataOutput {
                if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer), !readyToRecordVideo {
                    readyToRecordVideo = self.setupAssetWriterVideoInput(formatDescription, assetWriter: assetWriter)
                }

                if readyToRecordVideo && readyToRecordAudio {
                    self.writeSampleBuffer(sampleBuffer: sampleBuffer, ofType: .video)
                }
            } else if captureOutput === self.engine.audioDataOutput {
                if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer), !readyToRecordAudio {
                    readyToRecordAudio = self.setupAssetWriterAudioInput(formatDescription,
                                                                         assetWriter: assetWriter)
                }

                if readyToRecordAudio && readyToRecordVideo {
                    self.writeSampleBuffer(sampleBuffer: sampleBuffer, ofType: .audio)
                }
            }
            let isReadyToRecord = readyToRecordAudio && readyToRecordVideo
            if !wasReadyToRecord && isReadyToRecord {
                recordingWillBeStarted = false
                // THE recording-started instant: everything downstream — both
                // timers, the monitor's ack, the wire's
                // `recording_start_unix_ms`, and `isRecording` itself —
                // derives from this one stamp.
                let startTime = Date()
                self.recordingStartShared.value = startTime

                // Start recording timer and notify monitor
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.onRecordingStarted?(startTime)

                    // Send recording start time to monitor for synchronization
                    self.sendMessage?(RemoteCmd.StartRecordingVideoAck(sender: nil, recordingStartTime: startTime))
                }
            }
        }
    }

    private func writeSampleBuffer(sampleBuffer: CMSampleBuffer,
                                   ofType mediaType: AVMediaType) {
        dispatchPrecondition(condition: .onQueue(dataQueue))
        if !isRecording {
            return
        }
        guard let assetWriter = self.assetWriter else {
            return
        }
        if assetWriter.status == .unknown {
            if assetWriter.startWriting() {
                assetWriter.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            } else {
                failRecording(Self.writerFailureError(assetWriter), hasClip: false)
                return
            }
        }

        if mediaType == .video, let adaptor = self.pixelBufferAdaptor {
            // Crop video frame for non-16:9 aspect ratios
            if self.videoInput.isReadyForMoreMediaData,
               let croppedBuffer = self.cropSampleBuffer(sampleBuffer) {
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                adaptor.append(croppedBuffer, withPresentationTime: pts)
            }
        } else if let input = (mediaType == .video) ? self.videoInput : self.audioInput {
            if input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
            }
        }

        // Disk-full and other write failures surface HERE, not as thrown
        // errors: appends silently no-op once the writer is `.failed`, so the
        // status is the only signal. Without this check the app keeps showing
        // REC while writing nothing (the shipped disk-full behavior).
        if assetWriter.status == .failed {
            failRecording(Self.writerFailureError(assetWriter), hasClip: true)
        }
    }

    /// Crops a video frame using the cached crop rect and the adaptor's pixel buffer pool.
    /// Called on every video frame during recording — must be fast.
    private func cropSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> CVPixelBuffer? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        // No crop needed — pass through the original buffer
        guard let cropRect = cachedVideoCropRect,
              let pool = pixelBufferAdaptor?.pixelBufferPool else {
            return pixelBuffer
        }

        // Get a buffer from the pool (reuses memory, no per-frame allocation)
        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
        guard status == kCVReturnSuccess, let output = outputBuffer else { return nil }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            .cropped(to: cropRect)
            .transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))
        videoCropContext.render(ciImage, to: output)
        return output
    }
}
