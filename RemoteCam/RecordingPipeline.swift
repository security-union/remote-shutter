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
 movie. Non-UI — the view controller keeps the sample-buffer delegate role,
 the microphone-permission flow, and all overlays, and reaches back in through
 the closure seams below. Collaborates with `CaptureEngine`, which owns the
 capture session and its outputs/queues.
 */
class RecordingPipeline {

    /// The capture session, outputs, queues and aspect-ratio config live on the engine.
    private let engine: CaptureEngine

    // MARK: - UI/actor seams

    /// Relays actor messages (`StartRecordingVideoAck`, `StopRecordingVideoResp`,
    /// `SendVideoResource`) — the pipeline never touches the actor system directly.
    var sendMessage: ((Actor.Message) -> Void)?
    /// Recording actually began (first frames written). Main thread. The ack to the
    /// monitor is sent through `sendMessage` right after this fires.
    var onRecordingStarted: ((Date) -> Void)?
    /// Recording is stopping — clear the timer display. Main thread.
    var onRecordingStopped: (() -> Void)?
    /// Chrome update: `idle == true` → idle mode, else video-recording mode. Main thread.
    var onModeChanged: ((_ idle: Bool) -> Void)?
    /// Unrecoverable start failure ("Unable to start recording"). Fires on the
    /// writing queue — hop to main before touching UIKit.
    var onError: ((String) -> Void)?
    /// Photos-library access denied while saving the finished movie. Main thread.
    var onPhotosAccessDenied: (() -> Void)?

    // MARK: - Recording state
    // Mutated on writingQueue and the capture queues, read from main — same
    // (unsynchronized) behavior as before the extraction; the single-owned-queue
    // fix is a queued follow-up.

    private(set) var isRecording: Bool = false
    private(set) var recordingWillBeStarted: Bool = false
    private(set) var recordingWillBeStopped: Bool = false
    private var readyToRecordVideo: Bool = false
    private var readyToRecordAudio: Bool = false

    private var assetWriter: AVAssetWriter?
    private(set) var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private(set) var cachedVideoCropRect: CGRect? // Computed once at recording start, reused per frame

    private let videoCropContext = CIContext(options: [.useSoftwareRenderer: false])

    private let writingQueue = DispatchQueue(label: "asset recorder writing queue", attributes: [], target: nil)

    private var videoInput: AVAssetWriterInput!
    private var audioInput: AVAssetWriterInput!

    init(engine: CaptureEngine) {
        self.engine = engine
    }

    // MARK: - Start / stop

    /// Adds the audio input/output to the capture session and starts recording.
    /// The caller (the VC) remains the audio sample-buffer delegate.
    func startRecording(audioSampleBufferDelegate: AVCaptureAudioDataOutputSampleBufferDelegate) {
        writingQueue.async { [weak self] in
            guard let self = self else { return }
            if self.recordingWillBeStarted || self.isRecording {
                return
            }

            // Setup audio input for video recording
            do {
                // No microphone (simulator, some iPads) — record without audio.
                guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
                    self.startVideoRecordingProcess()
                    return
                }
                let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)

                self.engine.captureSession.beginConfiguration()

                if self.engine.captureSession.canAddInput(audioDeviceInput) {
                    self.engine.captureSession.addInput(audioDeviceInput)
                } else {
                    print("Could not add audio device input to the session")
                }

                if self.engine.captureSession.canAddOutput(self.engine.audioDataOutput) {
                    self.engine.captureSession.addOutput(self.engine.audioDataOutput)
                    self.engine.audioDataOutput.setSampleBufferDelegate(audioSampleBufferDelegate, queue: self.engine.audioDataOutputQueue)
                }

                self.engine.captureSession.commitConfiguration()

                // Restore the user's torch preference — iOS resets the torch on commitConfiguration.
                self.engine.applyDesiredTorch()

                // Update audio connection
                self.engine.audioConnection = self.engine.audioDataOutput.connection(with: .audio)

                self.startVideoRecordingProcess()

            } catch {
                print("Error setting up audio for video recording: \(error)")
                // Start recording without audio
                self.startVideoRecordingWithoutAudio()
            }
        }
    }

    private func startVideoRecordingWithoutAudio() {
        writingQueue.async { [weak self] in
            self?.startVideoRecordingProcess()
        }
    }

    private func startVideoRecordingProcess() {
        if self.recordingWillBeStarted || self.isRecording {
            return
        }

        self.recordingWillBeStarted = true

        // Remove the file if one with the same name already exists
        let outputFilePath = movieUrl()
        cleanupFileAt(outputFilePath)
        // Create an asset writer
        do {
            self.assetWriter = try AVAssetWriter(outputURL: outputFilePath, fileType: .mov)
        } catch {
            onError?(NSLocalizedString("Unable to start recording", comment: ""))
        }
        OperationQueue.main.addOperation { [weak self] in
            guard let self = self else { return }
            let idle = !self.recordingWillBeStarted && !self.isRecording
            self.onModeChanged?(idle)
        }
    }

    func stopRecording(_ shouldSendVideo: Bool) {
        writingQueue.async { [weak self] in
            guard let self = self else { return }
            if self.recordingWillBeStopped || !self.isRecording {
                return
            }
            self.isRecording = false
            self.recordingWillBeStopped = true

            // Stop recording timer
            DispatchQueue.main.async { [weak self] in
                self?.onRecordingStopped?()
            }
            self.assetWriter?.finishWriting { [weak self] in
                self?.assetWriter = nil
                self?.pixelBufferAdaptor = nil
                self?.cachedVideoCropRect = nil
                self?.readyToRecordVideo = false
                self?.readyToRecordAudio = false
                self?.recordingWillBeStopped = false
                self?.saveMovieToPhotosAppAndRemotePeer(shouldSendVideo)
            }
            OperationQueue.main.addOperation { [weak self] in
                guard let self = self else { return }
                let idle = self.recordingWillBeStopped && !self.isRecording
                self.onModeChanged?(idle)
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
                PHPhotoLibrary.shared().performChanges({
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = true
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    creationRequest.addResource(with: .video, fileURL: outputFileURL, options: options)
                }, completionHandler: { success, error in
                    if !success {
                        print("AVCam couldn't save the movie to your photo library: \(String(describing: error))")
                    }
                    cleanupFileAt(outputFileURL)
                }
                )
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
        var videoSettings = self.engine.videoDataOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov)
        videoSettings?[AVVideoCodecKey] = AVVideoCodecType.hevc

        let dims = CMVideoFormatDescriptionGetDimensions(formatDescription)
        let sourceWidth = CGFloat(dims.width)
        let sourceHeight = CGFloat(dims.height)

        // Compute and cache the crop rect once — reused for every frame
        let needsCrop = engine.currentAspectRatio != .sixteenNine
        if needsCrop, let rawRect = CaptureEngine.cropRect(sourceWidth: sourceWidth, sourceHeight: sourceHeight, aspectRatio: engine.currentAspectRatio) {
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

            if cachedVideoCropRect != nil {
                // Pool attributes match output dimensions — avoids per-frame CVPixelBufferCreate
                let poolAttrs: [String: Any] = [
                    kCVPixelBufferWidthKey as String: Int(cachedVideoCropRect!.width),
                    kCVPixelBufferHeightKey as String: Int(cachedVideoCropRect!.height),
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
                return false
            }
        } else {
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

    // MARK: - Per-frame path

    func processFrame(_ captureOutput: AVCaptureOutput,
                      didOutput sampleBuffer: CMSampleBuffer,
                      from connection: AVCaptureConnection) {

        if let assetWriter = self.assetWriter {
            let wasReadyToRecord = (readyToRecordAudio && readyToRecordVideo)
            if connection == self.engine.videoConnection {
                if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer), !readyToRecordVideo {
                    readyToRecordVideo = self.setupAssetWriterVideoInput(formatDescription, assetWriter: assetWriter)
                }

                if readyToRecordVideo && readyToRecordAudio {
                    self.writeSampleBuffer(sampleBuffer: sampleBuffer, ofType: .video)
                }
            } else if connection == self.engine.audioConnection {
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
                self.isRecording = true

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
        if !isRecording {
            return
        }
        writingQueue.async { [weak self] in
            guard let self = self else { return }
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

            if mediaType == .video, let adaptor = self.pixelBufferAdaptor,
               self.engine.currentAspectRatio != .sixteenNine {
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
