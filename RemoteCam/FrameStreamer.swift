//
//  FrameStreamer.swift
//  RemoteShutter
//
//  Camera-side streaming pipeline: paces capture callbacks, encodes, stamps
//  sequence numbers, and hands the result to the FrameSender actor for
//  ack-gated transport.
//
//  A new camera streams a stateful video codec to every peer monitor. Two codec
//  strategies share one pacer:
//   • Video (HEVC preferred, VP9 fallback) — the normal path. A dropped delta
//     frame corrupts decode until a keyframe, so a video frame must NOT be
//     encoded-then-dropped: it is encoded LAZILY, only when the credit window has
//     room, and sent .reliable so the transport never drops it either. Skipping a
//     frame before the encoder sees it keeps the stream continuous (the encoder
//     just runs at a lower frame rate). The concrete codec is chosen by the
//     injected `makeVideoEncoder` factory (HEVC when the hardware encodes it,
//     else VP9); the emitted frame carries the encoder's own `codec` tag.
//   • Stills (HEIC with JPEG fallback) — a DEV-ONLY fallback for the case where
//     no video codec is available at runtime (`makeVideoEncoder` returns nil,
//     e.g. a broken/absent VideoToolbox + VideocallCodecs). Every shipping config
//     has at least one video codec, so this path does not run in production; it
//     only keeps the preview alive on an odd build. Stills are independent
//     frames, sent .unreliable; the FrameSender drops them under back-pressure.
//
//  Confined to the capture queue: `handle` must only be called from the
//  AVCaptureVideoDataOutput callback queue (same contract as
//  WatchPreviewStreamer).
//

import UIKit
import AVFoundation

final class FrameStreamer {

    typealias Send = (RemoteCmd.SendFrame) -> Void

    private let config: StreamingConfig
    private let send: Send

    /// Remaining still-codec chain; first entry is the active still encoder.
    private var encoders: [FrameEncoding]
    private var frameCount = 0
    private var sequenceNumber: UInt32 = 0
    /// Last codec announced at .info, so the selected format is visible in
    /// Console without per-frame chatter. Capture-queue confined.
    private var lastAnnouncedCodec: RemoteCmd.StreamCodec?

    /// True when the credit window has room for another in-flight frame — the
    /// lazy back-pressure gate for the stateful VP9 stream.
    private let creditAvailable: () -> Bool
    /// Reads-and-clears a pending keyframe request from the monitor (decoder
    /// re-sync). Returns true at most once per request.
    private let takeKeyframeRequest: () -> Bool
    /// Builds the stateful video encoder (HEVC preferred, VP9 fallback) on first
    /// use; nil when no video codec is available at runtime or in tests that
    /// don't exercise video.
    private let makeVideoEncoder: () -> StreamVideoEncoding?
    private var videoEncoder: StreamVideoEncoding?
    /// Latched when the video encoder fails on this hardware: never retried, the
    /// stream stays on stills for the rest of the connection.
    private var videoFailed = false

    /// - Parameters:
    ///   - encoders: injectable still chain for tests; nil builds it from
    ///     `config.preferredCodecs`.
    ///   - makeVideoEncoder: builds the stateful video encoder (HEVC preferred,
    ///     VP9 fallback) on first use; its default (nil) disables video (stills
    ///     only), the behavior the still-path tests pin. Production passes a
    ///     factory gated on `HEVCSupport.canEncode` / `VP9Support.isAvailable`.
    ///   - creditAvailable/takeKeyframeRequest: the video back-pressure and
    ///     keyframe seams.
    init(config: StreamingConfig = .default,
         encoders: [FrameEncoding]? = nil,
         creditAvailable: @escaping () -> Bool = { true },
         takeKeyframeRequest: @escaping () -> Bool = { false },
         makeVideoEncoder: @escaping () -> StreamVideoEncoding? = { nil },
         send: @escaping Send) {
        self.config = config
        self.send = send
        self.encoders = encoders ?? Self.makeEncoders(config: config)
        self.creditAvailable = creditAvailable
        self.takeKeyframeRequest = takeKeyframeRequest
        self.makeVideoEncoder = makeVideoEncoder
    }

    /// The active still-codec head (used by tests). The video stream, when
    /// enabled, is a separate path and not reflected here.
    var activeCodec: RemoteCmd.StreamCodec? { encoders.first?.codec }

    /// Capture-queue only. Encodes and sends this frame unless pacing skips it,
    /// back-pressure gates the VP9 stream, or every codec has failed.
    func handle(pixelBuffer: CVPixelBuffer,
                position: AVCaptureDevice.Position,
                orientation: UIInterfaceOrientation,
                fps: Int) {
        frameCount += 1
        guard frameCount % config.frameDivisor == 0 else { return }

        if useVideo {
            handleVideo(pixelBuffer: pixelBuffer, position: position, orientation: orientation, fps: fps)
        } else {
            handleStill(pixelBuffer: pixelBuffer, position: position, orientation: orientation, fps: fps)
        }
    }

    /// Whether the stateful video stream is active for this frame: not
    /// permanently failed and the encoder is constructible (a video codec is
    /// available at runtime). Built lazily on first use; nil means no video codec
    /// is available and the dev-only still fallback runs instead.
    private var useVideo: Bool {
        guard !videoFailed else { return false }
        if videoEncoder == nil { videoEncoder = makeVideoEncoder() }
        return videoEncoder != nil
    }

    private func handleVideo(pixelBuffer: CVPixelBuffer,
                             position: AVCaptureDevice.Position,
                             orientation: UIInterfaceOrientation,
                             fps: Int) {
        guard let video = videoEncoder else { return }
        // Lazy back-pressure: skip BEFORE feeding the encoder when the window is
        // full. Encoding then dropping would advance the encoder past a frame
        // the monitor never receives, corrupting every delta frame until the
        // next keyframe. Skipping keeps the encoded stream continuous.
        guard creditAvailable() else { return }
        if takeKeyframeRequest() { video.forceKeyframe() }

        switch video.encode(pixelBuffer: pixelBuffer) {
        case .encoded(let data):
            emit(data: data, codec: video.codec, position: position, orientation: orientation, fps: fps)
        case .skipped:
            return // encoder buffered the frame: no wire frame, no credit consumed
        case .failed:
            videoFailed = true
            videoEncoder = nil
            StreamLog.encode.error("peer video encoder failed — falling back to stills for this connection")
            handleStill(pixelBuffer: pixelBuffer, position: position, orientation: orientation, fps: fps)
        }
    }

    private func handleStill(pixelBuffer: CVPixelBuffer,
                             position: AVCaptureDevice.Position,
                             orientation: UIInterfaceOrientation,
                             fps: Int) {
        guard let frame = encodeWithFallback(&encoders, pixelBuffer: pixelBuffer) else { return }
        emit(data: frame.data, codec: frame.codec, position: position, orientation: orientation, fps: fps)
    }

    private func emit(data: Data,
                      codec: RemoteCmd.StreamCodec,
                      position: AVCaptureDevice.Position,
                      orientation: UIInterfaceOrientation,
                      fps: Int) {
        if codec != lastAnnouncedCodec {
            lastAnnouncedCodec = codec
            StreamLog.encode.info("peer preview stream codec selected: \(String(describing: codec))")
        }
        sequenceNumber &+= 1
        StreamLog.encode.debug(
            "frame seq=\(self.sequenceNumber) codec=\(String(describing: codec)) bytes=\(data.count)")
        send(RemoteCmd.SendFrame(
            data: data,
            sender: nil,
            fps: fps,
            camPosition: position,
            camOrientation: orientation,
            codec: codec,
            sequenceNumber: sequenceNumber
        ))
    }

    private static func makeEncoders(config: StreamingConfig) -> [FrameEncoding] {
        config.preferredCodecs.compactMap { codec in
            switch codec {
            case .heic:
                return HEICFrameEncoder(maxLongEdge: config.maxLongEdge, quality: config.heicQuality)
            case .jpeg:
                return JPEGFrameEncoder(maxLongEdge: config.maxLongEdge, quality: config.jpegQuality)
            case .hevc:
                return nil // video codec: follow-up PR (HEVCFrameEncoder)
            case .vp9:
                return nil // VP9 is the stateful video path, managed separately (not a still)
            }
        }
    }
}
