//
//  FrameStreamingCoordinator.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import Foundation
import AVFoundation
import CoreImage
import UIKit

/**
 The capture session's sample-buffer delegate: fans every frame out to the
 live-preview streamers (phone monitor or Apple Watch) and, while recording,
 to the `RecordingPipeline`. Non-UI — its only UIKit dependency is
 `UIInterfaceOrientation` for the frame streamer.

 Owned by `CameraRig`, which injects the actor sink and two providers
 instead of the coordinator keeping its own copies of the rig's state.
 */
final class FrameStreamingCoordinator: NSObject {

    private let engine: CaptureEngine
    private let pipeline: RecordingPipeline
    /// Feeds encoded monitor frames to the FrameSender actor.
    private let frameSink: FrameStreamer.Send
    /// Reads the VC's orientation. Called on the capture queue — the same
    /// cross-thread property read this code did before the extraction.
    private let orientationProvider: () -> UIInterfaceOrientation
    /// True when the Apple Watch is the remote (no MultipeerConnectivity peer).
    private let isWatchRemoteMode: () -> Bool

    /// Dedicated context for the tiny Apple Watch preview, kept off the recording
    /// pipeline's crop context to avoid cross-queue contention.
    private let watchPreviewContext = CIContext(options: [.useSoftwareRenderer: false])
    /// Streams preview frames to the Apple Watch with ack back-pressure and lazy encoding.
    /// Runs on `videoDataOutputQueue`, where the capture callback hands it sample buffers.
    private lazy var watchPreviewStreamer = WatchPreviewStreamer(
        queue: engine.videoDataOutputQueue,
        maxInFlight: StreamingConfig.default.watchPreviewMaxInFlight,
        ackTimeout: StreamingConfig.default.watchPreviewAckTimeout)
    /// Streams preview frames to the phone monitor: paces, encodes (HEIC with
    /// JPEG fallback), and hands frames to the FrameSender actor.
    /// Runs on `videoDataOutputQueue`.
    private lazy var frameStreamer = FrameStreamer(send: frameSink)
    /// Encoder chain for the Watch preview (HEIC with permanent JPEG fallback).
    /// Runs on `videoDataOutputQueue` via `watchPreviewStreamer.offer`.
    private lazy var watchFrameEncoders: [FrameEncoding] = {
        let config = StreamingConfig.default
        return [
            HEICFrameEncoder(context: watchPreviewContext,
                             maxLongEdge: config.watchMaxLongEdge,
                             quality: config.watchHEICQuality),
            JPEGFrameEncoder(context: watchPreviewContext,
                             maxLongEdge: config.watchMaxLongEdge,
                             quality: config.watchJPEGQuality)
        ]
    }()

    init(engine: CaptureEngine,
         pipeline: RecordingPipeline,
         orientationProvider: @escaping () -> UIInterfaceOrientation,
         isWatchRemoteMode: @escaping () -> Bool,
         frameSink: @escaping FrameStreamer.Send) {
        self.engine = engine
        self.pipeline = pipeline
        self.orientationProvider = orientationProvider
        self.isWatchRemoteMode = isWatchRemoteMode
        self.frameSink = frameSink
    }

    /// The Watch acked the in-flight preview frame — let the streamer send the next.
    func acknowledgeWatchPreview() {
        watchPreviewStreamer.acknowledge()
    }
}

extension FrameStreamingCoordinator: AVCaptureVideoDataOutputSampleBufferDelegate,
                                     AVCaptureAudioDataOutputSampleBufferDelegate {

    func captureOutput(_ captureOutput: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if connection == engine.videoConnection {
            sendFrameToMonitor(captureOutput, didOutput: sampleBuffer, from: connection)
        }
        if (pipeline.recordingWillBeStarted || pipeline.isRecording) && !pipeline.recordingWillBeStopped {
            pipeline.processFrame(captureOutput, didOutput: sampleBuffer, from: connection)
        }
    }

    func sendFrameToMonitor(_ captureOutput: AVCaptureOutput,
                            didOutput sampleBuffer: CMSampleBuffer,
                            from connection: AVCaptureConnection) {
        // Watch Remote mode has no MultipeerConnectivity peer — the iPhone is the camera
        // and the only consumer is the Apple Watch. The streamer applies ack back-pressure
        // and only invokes the encode when it's actually ready to send.
        if isWatchRemoteMode() {
            watchPreviewStreamer.offer { [weak self] in self?.watchPreviewImageData(from: sampleBuffer) }
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let device = self.engine.videoDeviceInput?.device else { return }
        frameStreamer.handle(pixelBuffer: pixelBuffer,
                             position: device.position,
                             orientation: orientationProvider(),
                             fps: fps)
    }

    /// Builds a compact still of the current frame for the Apple Watch live
    /// preview: long edge ~320 px (matching the Watch screen width), HEIC when
    /// the hardware supports it (~half the bytes of JPEG, so roughly double the
    /// frame rate over the WCSession pipe), JPEG otherwise. The Watch decodes
    /// either transparently via UIImage(data:). The sample buffer is already
    /// oriented by `videoConnection.videoOrientation`, so it renders upright.
    private func watchPreviewImageData(from sampleBuffer: CMSampleBuffer) -> Data? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        return encodeWithFallback(&watchFrameEncoders, pixelBuffer: pixelBuffer)
    }
}
