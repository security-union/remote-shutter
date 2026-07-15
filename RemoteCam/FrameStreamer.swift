//
//  FrameStreamer.swift
//  RemoteShutter
//
//  Camera-side streaming pipeline: paces capture callbacks, encodes, stamps
//  sequence numbers, and hands the result to the FrameSender actor for
//  ack-gated transport.
//
//  Two codec strategies share one pacer:
//   • Stills (HEIC with JPEG fallback) — independent frames, sent .unreliable.
//     Encoded eagerly; the FrameSender drops under back-pressure because a lost
//     still just means the viewfinder shows the previous one.
//   • VP9 (a stateful video stream) — enabled only once the monitor advertises
//     VP9 decode support. A dropped delta frame corrupts decode until a
//     keyframe, so VP9 must NOT be encoded-then-dropped: it is encoded LAZILY,
//     only when the credit window has room, and sent .reliable so the transport
//     never drops it either. Skipping a frame before the encoder sees it keeps
//     the stream continuous (the encoder just runs at a lower frame rate).
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

    /// True once the monitor has advertised VP9 decode support (negotiation) —
    /// read per frame on the capture queue.
    private let vp9Enabled: () -> Bool
    /// True when the credit window has room for another in-flight frame — the
    /// lazy back-pressure gate for the stateful VP9 stream.
    private let creditAvailable: () -> Bool
    /// Reads-and-clears a pending keyframe request from the monitor (decoder
    /// re-sync). Returns true at most once per request.
    private let takeKeyframeRequest: () -> Bool
    /// Builds the VP9 encoder on first use; nil when VP9 is unavailable at
    /// runtime (excluded arch) or in tests that don't exercise VP9.
    private let makeVP9Encoder: () -> StreamVideoEncoding?
    private var vp9Encoder: StreamVideoEncoding?
    /// Latched when the VP9 encoder fails on this hardware: never retried, the
    /// stream stays on stills for the rest of the connection.
    private var vp9Failed = false

    /// - Parameters:
    ///   - encoders: injectable still chain for tests; nil builds it from
    ///     `config.preferredCodecs`.
    ///   - vp9Enabled/creditAvailable/takeKeyframeRequest/makeVP9Encoder: the
    ///     VP9 seams; their defaults disable VP9 entirely (stills only), which
    ///     is the behavior the still-path tests pin.
    init(config: StreamingConfig = .default,
         encoders: [FrameEncoding]? = nil,
         vp9Enabled: @escaping () -> Bool = { false },
         creditAvailable: @escaping () -> Bool = { true },
         takeKeyframeRequest: @escaping () -> Bool = { false },
         makeVP9Encoder: @escaping () -> StreamVideoEncoding? = { nil },
         send: @escaping Send) {
        self.config = config
        self.send = send
        self.encoders = encoders ?? Self.makeEncoders(config: config)
        self.vp9Enabled = vp9Enabled
        self.creditAvailable = creditAvailable
        self.takeKeyframeRequest = takeKeyframeRequest
        self.makeVP9Encoder = makeVP9Encoder
    }

    /// The active still-codec head (used by tests). The VP9 stream, when
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

        if useVP9 {
            handleVP9(pixelBuffer: pixelBuffer, position: position, orientation: orientation, fps: fps)
        } else {
            handleStill(pixelBuffer: pixelBuffer, position: position, orientation: orientation, fps: fps)
        }
    }

    /// Whether the VP9 stream is active for this frame (negotiated, not failed,
    /// encoder constructible). Builds the encoder lazily on first use.
    private var useVP9: Bool {
        guard vp9Enabled(), !vp9Failed else { return false }
        if vp9Encoder == nil { vp9Encoder = makeVP9Encoder() }
        return vp9Encoder != nil
    }

    private func handleVP9(pixelBuffer: CVPixelBuffer,
                           position: AVCaptureDevice.Position,
                           orientation: UIInterfaceOrientation,
                           fps: Int) {
        guard let vp9 = vp9Encoder else { return }
        // Lazy back-pressure: skip BEFORE feeding the encoder when the window is
        // full. Encoding then dropping would advance the encoder past a frame
        // the monitor never receives, corrupting every delta frame until the
        // next keyframe. Skipping keeps the encoded stream continuous.
        guard creditAvailable() else { return }
        if takeKeyframeRequest() { vp9.forceKeyframe() }

        switch vp9.encode(pixelBuffer: pixelBuffer) {
        case .encoded(let data):
            emit(data: data, codec: .vp9, position: position, orientation: orientation, fps: fps)
        case .skipped:
            return // encoder buffered the frame: no wire frame, no credit consumed
        case .failed:
            vp9Failed = true
            vp9Encoder = nil
            StreamLog.encode.error("peer VP9 encoder failed — falling back to stills for this connection")
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
