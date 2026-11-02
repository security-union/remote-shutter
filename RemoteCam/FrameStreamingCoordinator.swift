//
//  FrameStreamingCoordinator.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import Atomics
import Foundation
import AVFoundation
import CoreImage
import UIKit

/**
 The preview's own lane: a serial queue that holds at most one frame beyond
 the one being encoded. `offer` is a zero-copy hand-off (the capture buffer
 is retained, never copied) that returns at once; while the lane is still
 busy with the previous frame the new one is skipped, never queued — the
 preview loses a frame, the movie does not, and the camera's small buffer
 pool never backs up.
 */
final class PreviewLane {
    private let queue: DispatchQueue
    private let busy = ManagedAtomic(false)
    private let encodedCount = ManagedAtomic(0)
    private let skippedCount = ManagedAtomic(0)

    /// Frames encoded and frames skipped because the lane was busy.
    var encoded: Int { encodedCount.load(ordering: .relaxed) }
    var skipped: Int { skippedCount.load(ordering: .relaxed) }

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    /// Runs `encode` on the lane unless it is still encoding the previous
    /// frame. Returns whether the frame was taken.
    @discardableResult
    func offer(_ encode: @escaping () -> Void) -> Bool {
        guard busy.compareExchange(expected: false, desired: true, ordering: .acquiringAndReleasing).exchanged else {
            skippedCount.wrappingIncrement(ordering: .relaxed)
            return false
        }
        queue.async { [self] in
            encode()
            encodedCount.wrappingIncrement(ordering: .relaxed)
            busy.store(false, ordering: .releasing)
        }
        return true
    }
}

/**
 The capture session's sample-buffer delegate: fans every frame out to the
 recording pipeline (on the capture queue, where it arrives) and to the
 live-preview streamers (phone monitor or Apple Watch) on their own
 `PreviewLane`, so preview work can never make the capture queue late.
 Non-UI — its only UIKit dependency is `UIInterfaceOrientation` for the
 frame streamer.

 Owned by `CameraRig`, which injects the actor sink and two providers
 instead of the coordinator keeping its own copies of the rig's state.
 */
final class FrameStreamingCoordinator: NSObject {

    private let engine: CaptureEngine
    private let pipeline: RecordingPipeline
    /// Where every preview encoder runs; the streamers below are confined to it.
    private let previewQueue = DispatchQueue(label: "camera preview lane", attributes: [], target: nil)
    private(set) lazy var previewLane = PreviewLane(queue: previewQueue)
    /// Feeds encoded monitor frames to the FrameSender actor.
    private let frameSink: FrameStreamer.Send
    /// Reads the VC's orientation. Called on the preview queue.
    private let orientationProvider: () -> UIInterfaceOrientation
    /// True when the Apple Watch is the remote (no connected remote peer).
    private let isWatchRemoteMode: () -> Bool
    /// The credit window has room — the lazy back-pressure gate for VP9.
    private let frameCreditAvailable: () -> Bool
    /// Reads-and-clears a monitor keyframe request (decoder re-sync).
    private let takePeerKeyframeRequest: () -> Bool

    /// Dedicated context for the tiny Apple Watch preview, kept off the recording
    /// pipeline's crop context to avoid cross-queue contention.
    private let watchPreviewContext = CIContext(options: [.useSoftwareRenderer: false])
    /// Streams preview frames to the Apple Watch with ack back-pressure and lazy encoding.
    /// Runs on `previewQueue`, where the preview lane hands it sample buffers.
    private lazy var watchPreviewStreamer = WatchPreviewStreamer(
        queue: previewQueue,
        maxInFlight: StreamingConfig.default.watchPreviewMaxInFlight,
        ackTimeout: StreamingConfig.default.watchPreviewAckTimeout)
    /// Streams preview frames to the phone monitor: paces, encodes, and hands
    /// frames to the FrameSender actor. Uses a stateful video stream (lazy +
    /// credit-gated): HEVC (VideoToolbox hardware) when this device can encode
    /// it, else VP9 (software). Falls back to HEIC/JPEG stills only when no video
    /// codec is available at runtime (dev-only). Runs on `previewQueue`.
    private lazy var frameStreamer = FrameStreamer(
        creditAvailable: frameCreditAvailable,
        takeKeyframeRequest: takePeerKeyframeRequest,
        makeVideoEncoder: { profile in
            // Prefer hardware HEVC; fall back to software VP9; nil only on an
            // arch with neither (dev-only), where the stream drops to stills.
            // The multicam profile overrides resolution/bitrate/fps; the rest of
            // the encoder tuning (keyframe interval, quantizers) stays put.
            let config = StreamingConfig.default
            if HEVCSupport.canEncode {
                let hevc = HEVCSettings(bitrateKbps: profile.bitrateKbps, fps: profile.fps,
                                        keyframeInterval: config.peerHEVC.keyframeInterval)
                return HEVCFrameEncoder(maxLongEdge: profile.maxLongEdge, settings: hevc)
            }
            if VP9Support.isAvailable {
                var vp9 = config.peerVP9
                vp9.bitrateKbps = profile.bitrateKbps
                vp9.fps = profile.fps
                return VP9FrameEncoder(maxLongEdge: profile.maxLongEdge, settings: vp9)
            }
            return nil
        },
        send: frameSink)
    /// Encoder chain for the Watch preview, built from
    /// `StreamingConfig.watchPreferredCodecs` (VP9 video stream first, with
    /// permanent HEIC-then-JPEG still fallback).
    /// Runs on `previewQueue` via `watchPreviewStreamer.offer`.
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

    /// Multicam: retune the phone-monitor preview stream. Hops onto the preview
    /// lane the streamer lives on, so the reconfigure is serialized with frame
    /// encoding.
    func applyStreamProfile(_ profile: StreamProfile) {
        previewQueue.async { [weak self] in
            self?.frameStreamer.applyProfile(profile)
        }
    }

    /// Capture interruption: drop the hardware video encoder so post-wake
    /// frames build a fresh session — never feed a background-killed one.
    func handleCaptureInterruption() {
        previewQueue.async { [weak self] in
            self?.frameStreamer.dropVideoEncoder()
        }
    }

    /// Wall-clock of the most recent video sample buffer, for the rig's
    /// first-frame watchdog (a suspended or stalled camera delivers nothing,
    /// forever). Written per-frame on the data queue, read from the watchdog.
    private let lastVideoFrameBits = ManagedAtomic<UInt64>(0)
    var lastVideoFrameAt: TimeInterval { Double(bitPattern: lastVideoFrameBits.load(ordering: .relaxed)) }

    /// Video frames the camera delivered, frames it discarded because this
    /// queue was still busy with the previous one
    /// (`alwaysDiscardsLateVideoFrames`), and the last discard reason. A
    /// discarded frame is missing from the movie; this is where that shows.
    private let deliveredCount = ManagedAtomic(0)
    private let droppedCount = ManagedAtomic(0)
    var videoFramesDelivered: Int { deliveredCount.load(ordering: .relaxed) }
    var videoFramesDropped: Int { droppedCount.load(ordering: .relaxed) }
    let lastDropReason = Locked<String?>(nil)

    /// Preview-output discards (no hole in the movie) and the newest buffer
    /// size each path received, packed width:height, for the hardware probe.
    private let previewDiscardedCount = ManagedAtomic(0)
    private let recordingFrameBits = ManagedAtomic<UInt64>(0)
    private let previewFrameBits = ManagedAtomic<UInt64>(0)
    var previewFramesDiscarded: Int { previewDiscardedCount.load(ordering: .relaxed) }
    var lastRecordingFrameSize: CGSize { Self.size(bits: recordingFrameBits.load(ordering: .relaxed)) }
    var lastPreviewFrameSize: CGSize { Self.size(bits: previewFrameBits.load(ordering: .relaxed)) }

    /// Last Watch-preview codec announced at .info, so the selected format is
    /// visible in Console without per-frame chatter. Preview-queue confined.
    private var lastAnnouncedWatchCodec: RemoteCmd.StreamCodec?

    /// Who gets a delivered buffer: the recorder only sees the recording
    /// outputs; the preview reads the dedicated output when attached, else
    /// the recording output.
    struct FrameRoute: Equatable {
        let toRecorder: Bool
        let toPreview: Bool

        static func decide(isRecordingVideo: Bool, isAudio: Bool,
                           isPreviewOutput: Bool, hasDedicatedPreview: Bool) -> FrameRoute {
            FrameRoute(toRecorder: isRecordingVideo || isAudio,
                       toPreview: isPreviewOutput || (isRecordingVideo && !hasDedicatedPreview))
        }
    }

    private static func bits(of sampleBuffer: CMSampleBuffer) -> UInt64 {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return 0 }
        return UInt64(CVPixelBufferGetWidth(buffer)) << 32 | UInt64(CVPixelBufferGetHeight(buffer))
    }

    private static func size(bits: UInt64) -> CGSize {
        CGSize(width: Int(bits >> 32), height: Int(bits & 0xFFFF_FFFF))
    }
}

extension FrameStreamingCoordinator: AVCaptureVideoDataOutputSampleBufferDelegate,
                                     AVCaptureAudioDataOutputSampleBufferDelegate {

    func captureOutput(_ captureOutput: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Route by output identity (`let`s, safe from any thread) rather than
        // comparing connections, which are sessionQueue-owned mutable state.
        let isRecordingVideo = captureOutput === engine.videoDataOutput
        let route = FrameRoute.decide(
            isRecordingVideo: isRecordingVideo,
            isAudio: captureOutput === engine.audioDataOutput,
            isPreviewOutput: captureOutput === engine.previewDataOutput,
            hasDedicatedPreview: engine.isPreviewOutputAttached)
        if isRecordingVideo {
            lastVideoFrameBits.store(Date().timeIntervalSinceReferenceDate.bitPattern, ordering: .relaxed)
            deliveredCount.wrappingIncrement(ordering: .relaxed)
            recordingFrameBits.store(Self.bits(of: sampleBuffer), ordering: .relaxed)
        }
        // Recording first: the append is the only work left on the data queue.
        if route.toRecorder,
           (pipeline.recordingWillBeStarted || pipeline.isRecording) && !pipeline.recordingWillBeStopped {
            pipeline.processFrame(captureOutput, didOutput: sampleBuffer)
        }
        if route.toPreview {
            previewFrameBits.store(Self.bits(of: sampleBuffer), ordering: .relaxed)
            previewLane.offer { [weak self] in self?.sendFrameToMonitor(sampleBuffer) }
        }
    }

    func captureOutput(_ captureOutput: AVCaptureOutput,
                       didDrop sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        if captureOutput === engine.previewDataOutput {
            previewDiscardedCount.wrappingIncrement(ordering: .relaxed)
            return
        }
        guard captureOutput === engine.videoDataOutput else { return }
        droppedCount.wrappingIncrement(ordering: .relaxed)
        if let reason = CMGetAttachment(sampleBuffer,
                                        key: kCMSampleBufferAttachmentKey_DroppedFrameReason,
                                        attachmentModeOut: nil) {
            lastDropReason.value = String(describing: reason)
        }
    }

    /// Preview-lane only: encodes one frame for whichever remote is attached.
    func sendFrameToMonitor(_ sampleBuffer: CMSampleBuffer) {
        dispatchPrecondition(condition: .onQueue(previewQueue))
        // Watch Remote mode has no connected remote peer — the iPhone is the camera
        // and the only consumer is the Apple Watch. The streamer applies ack back-pressure
        // and only invokes the encode when it's actually ready to send.
        if isWatchRemoteMode() {
            watchPreviewStreamer.offer { [weak self] in self?.watchPreviewFrame(from: sampleBuffer) }
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameStreamer.handle(pixelBuffer: pixelBuffer,
                             position: engine.currentPositionShared.load(ordering: .relaxed),
                             orientation: orientationProvider(),
                             fps: fpsSetting.load(ordering: .relaxed))
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
