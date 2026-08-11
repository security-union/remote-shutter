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
 `isRecording`, a lock-mirrored Bool.
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

    private var isRecordingStorage = false {
        didSet { isRecordingShared.value = isRecordingStorage }
    }
    /// Lock-mirrored for the cross-queue readers (`shouldAutorotate` on main,
    /// `setVideoQuality`'s guard on the actor mailbox, watch snapshots).
    private let isRecordingShared = Locked(false)
    var isRecording: Bool { isRecordingShared.value }

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

    // MARK: - Start / stop

    /// Configures the audio leg (on the engine's session queue) and starts
    /// recording. The caller's coordinator remains the audio delegate.
    func startRecording(audioSampleBufferDelegate: AVCaptureAudioDataOutputSampleBufferDelegate) {
        dataQueue.async { [weak self] in
            guard let self = self else { return }
            if self.recordingWillBeStarted || self.isRecordingStorage {
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
        if self.recordingWillBeStarted || self.isRecordingStorage {
            return
        }

        self.recordingWillBeStarted = true

        // Remove the file if one with the same name already exists
        let outputFilePath = movieUrl()
        cleanupFileAt(outputFilePath)
        // Create an asset writer
        do {
            self.assetWriter = try AVAssetWriter(outputURL: outputFilePath, fileType: .mov)
            // Synced multicam: embed the shot's alignment fields in the file so
            // an editor can group and time-align the angles. The anchor rides
            // as an opaque numeric key, not a wall-clock date.
            if let metadata = pendingSyncMetadata {
                self.assetWriter?.metadata = metadata.quickTimeMetadataItems()
            }
        } catch {
            onError?(NSLocalizedString("Unable to start recording", comment: ""))
        }
        let idle = !self.recordingWillBeStarted && !self.isRecordingStorage
        OperationQueue.main.addOperation { [weak self] in
            self?.onModeChanged?(idle)
        }
    }

    func stopRecording(_ shouldSendVideo: Bool) {
        dataQueue.async { [weak self] in
            guard let self = self else { return }
            if self.recordingWillBeStopped || !self.isRecordingStorage {
                return
            }
            self.isRecordingStorage = false
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
                    self.assetWriter = nil
                    self.pixelBufferAdaptor = nil
                    self.cachedVideoCropRect = nil
                    self.readyToRecordVideo = false
                    self.readyToRecordAudio = false
                    self.recordingWillBeStopped = false
                    self.saveMovieToPhotosAppAndRemotePeer(shouldSendVideo)
                }
            }
            let idle = self.recordingWillBeStopped && !self.isRecordingStorage
            OperationQueue.main.addOperation { [weak self] in
                self?.onModeChanged?(idle)
            }
        }
    }

    // MARK: - Saving / sending the finished movie

    private func saveMovieToPhotosAppAndRemotePeer(_ sendVideoToPeer: Bool) {
        let outputFileURL = movieUrl()

        // Send video to the monitor using resource transfer if requested
        if sendVideoToPeer {
            sendVideoAsResource(outputFileURL)
        } else {
            // Send empty response when not sending video
            sendMessage?(RemoteCmd.StopRecordingVideoResp(sender: nil, pic: nil, error: nil))
        }

        // Check the authorization status.
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            if status == .authorized {
                // Save the movie file to the photo library and cleanup.
                let syncMetadata = self?.pendingSyncMetadata
                PHPhotoLibrary.shared().performChanges({
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = true
                    // Synced clip: name it under the shared RS_ group.
                    if let syncMetadata { options.originalFilename = syncMetadata.videoFilename() }
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    creationRequest.addResource(with: .video, fileURL: outputFileURL, options: options)
                }, completionHandler: { success, error in
                    if !success {
                        print("AVCam couldn't save the movie to your photo library: \(String(describing: error))")
                    }
                    cleanupFileAt(outputFileURL)
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
                print("Cannot add audio input to asset writer")
                return false
            }
        } else {
            print("Cannot apply audio settings to asset writer")
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
                self.isRecordingStorage = true

                // Start recording timer and notify monitor
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    let startTime = Date()
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
        if !isRecordingStorage {
            return
        }
        guard let assetWriter = self.assetWriter else {
            return
        }
        if assetWriter.status == .unknown {
            if assetWriter.startWriting() {
                assetWriter.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            } else {
                self.onError?(NSLocalizedString("Unable to start recording", comment: ""))
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
