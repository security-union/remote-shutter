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
    /// The credit window has room — the lazy back-pressure gate for VP9.
    private let frameCreditAvailable: () -> Bool
    /// Reads-and-clears a monitor keyframe request (decoder re-sync).
    private let takePeerKeyframeRequest: () -> Bool

    /// Dedicated context for the tiny Apple Watch preview, kept off the recording
    /// pipeline's crop context to avoid cross-queue contention.
    private let watchPreviewContext = CIContext(options: [.useSoftwareRenderer: false])
    /// Streams preview frames to the Apple Watch with ack back-pressure and lazy encoding.
    /// Runs on `dataOutputQueue`, where the capture callback hands it sample buffers.
    private lazy var watchPreviewStreamer = WatchPreviewStreamer(
        queue: engine.dataOutputQueue,
        maxInFlight: StreamingConfig.default.watchPreviewMaxInFlight,
        ackTimeout: StreamingConfig.default.watchPreviewAckTimeout)
    /// Streams preview frames to the phone monitor: paces, encodes, and hands
    /// frames to the FrameSender actor. Uses VP9 (a stateful video stream, lazy
    /// + credit-gated) whenever the codec is available at runtime — the monitor
    /// is version-gated by the coordinator, so it can always decode VP9. Falls
    /// back to HEIC/JPEG stills only when VP9 is unavailable at runtime (dev-only).
    /// Runs on `videoDataOutputQueue`.
    private lazy var frameStreamer = FrameStreamer(
        creditAvailable: frameCreditAvailable,
        takeKeyframeRequest: takePeerKeyframeRequest,
        makeVP9Encoder: {
            // Runtime-gated: nil on any arch without the VP9 codec, so the
            // stream falls back to stills there (dev-only; every shipping arm64
            // config has VP9).
            guard VP9Support.isAvailable else { return nil }
            let config = StreamingConfig.default
            return VP9FrameEncoder(maxLongEdge: config.maxLongEdge, settings: config.peerVP9)
        },
        send: frameSink)
    /// Encoder chain for the Watch preview, built from
    /// `StreamingConfig.watchPreferredCodecs` (VP9 video stream first, with
    /// permanent HEIC-then-JPEG still fallback).
    /// Runs on `videoDataOutputQueue` via `watchPreviewStreamer.offer`.
    private lazy var watchFrameEncoders: [FrameEncoding] = {
        let config = StreamingConfig.default
        return config.watchPreferredCodecs.compactMap { codec in
            switch codec {
            case .vp9:
                return VP9FrameEncoder(maxLongEdge: config.watchMaxLongEdge,
                                       settings: config.watchVP9)
            case .heic:
                return HEICFrameEncoder(context: watchPreviewContext,
                                        maxLongEdge: config.watchMaxLongEdge,
                                        quality: config.watchHEICQuality)
            case .jpeg:
                return JPEGFrameEncoder(context: watchPreviewContext,
                                        maxLongEdge: config.watchMaxLongEdge,
                                        quality: config.watchJPEGQuality)
            case .hevc:
                return nil // never a watch codec (no VideoToolbox on watchOS)
            }
        }
    }()

    init(engine: CaptureEngine,
         pipeline: RecordingPipeline,
         orientationProvider: @escaping () -> UIInterfaceOrientation,
         isWatchRemoteMode: @escaping () -> Bool,
         frameSink: @escaping FrameStreamer.Send,
         frameCreditAvailable: @escaping () -> Bool = { true },
         takePeerKeyframeRequest: @escaping () -> Bool = { false }) {
        self.engine = engine
        self.pipeline = pipeline
        self.orientationProvider = orientationProvider
        self.isWatchRemoteMode = isWatchRemoteMode
        self.frameSink = frameSink
        self.frameCreditAvailable = frameCreditAvailable
        self.takePeerKeyframeRequest = takePeerKeyframeRequest
    }

    /// The Watch acked the in-flight preview frame — let the streamer send the next.
    func acknowledgeWatchPreview() {
        watchPreviewStreamer.acknowledge()
    }

    /// Wall-clock of the most recent video sample buffer, for the rig's
    /// first-frame watchdog (a suspended or stalled camera delivers nothing,
    /// forever). Written per-frame on the data queue, read from the watchdog.
    let lastVideoFrameAt = Locked<TimeInterval>(0)

    /// Last Watch-preview codec announced at .info, so the selected format is
    /// visible in Console without per-frame chatter. Capture-queue confined.
    private var lastAnnouncedWatchCodec: RemoteCmd.StreamCodec?
}

extension FrameStreamingCoordinator: AVCaptureVideoDataOutputSampleBufferDelegate,
                                     AVCaptureAudioDataOutputSampleBufferDelegate {

    func captureOutput(_ captureOutput: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Route by output identity (`let`s, safe from any thread) rather than
        // comparing connections, which are sessionQueue-owned mutable state.
        if captureOutput === engine.videoDataOutput {
            lastVideoFrameAt.value = Date().timeIntervalSinceReferenceDate
            sendFrameToMonitor(captureOutput, didOutput: sampleBuffer, from: connection)
        }
        if (pipeline.recordingWillBeStarted || pipeline.isRecording) && !pipeline.recordingWillBeStopped {
            pipeline.processFrame(captureOutput, didOutput: sampleBuffer)
        }
    }

    func sendFrameToMonitor(_ captureOutput: AVCaptureOutput,
                            didOutput sampleBuffer: CMSampleBuffer,
                            from connection: AVCaptureConnection) {
        // Watch Remote mode has no MultipeerConnectivity peer — the iPhone is the camera
        // and the only consumer is the Apple Watch. The streamer applies ack back-pressure
        // and only invokes the encode when it's actually ready to send.
        if isWatchRemoteMode() {
            watchPreviewStreamer.offer { [weak self] in self?.watchPreviewFrame(from: sampleBuffer) }
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameStreamer.handle(pixelBuffer: pixelBuffer,
                             position: engine.currentPositionShared.value,
                             orientation: orientationProvider(),
                             fps: fpsSetting.value)
    }

    /// Builds a compact frame of the current capture for the Apple Watch live
    /// preview: long edge ~320 px (matching the Watch screen width), VP9 when
    /// the codec runs (a fraction of a still's bytes), HEIC/JPEG still
    /// otherwise. The payload is tagged with its codec so the Watch routes it
    /// to the right decoder. The sample buffer is already oriented by
    /// `videoConnection.videoOrientation`, so it renders upright.
    private func watchPreviewFrame(from sampleBuffer: CMSampleBuffer) -> EncodedFrame? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let frame = encodeWithFallback(&watchFrameEncoders, pixelBuffer: pixelBuffer)
        if let frame, frame.codec != lastAnnouncedWatchCodec {
            lastAnnouncedWatchCodec = frame.codec
            StreamLog.encode.info("Watch preview stream codec selected: \(String(describing: frame.codec))")
        }
        return frame
    }
}
