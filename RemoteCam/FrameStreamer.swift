//
//  FrameStreamer.swift
//  RemoteShutter
//
//  Camera-side streaming pipeline: paces capture callbacks, encodes with the
//  first working codec from StreamingConfig.preferredCodecs (permanent
//  fallback on encoder failure), stamps sequence numbers, and hands the
//  result to the FrameSender actor for ack-gated transport.
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

    /// Remaining codec chain; first entry is the active encoder.
    private var encoders: [FrameEncoding]
    private var frameCount = 0
    private var sequenceNumber: UInt32 = 0
    /// Last codec announced at .info, so the selected format is visible in
    /// Console without per-frame chatter. Capture-queue confined.
    private var lastAnnouncedCodec: RemoteCmd.StreamCodec?

    /// - Parameter encoders: injectable for tests; nil builds the chain from
    ///   `config.preferredCodecs`.
    init(config: StreamingConfig = .default,
         encoders: [FrameEncoding]? = nil,
         send: @escaping Send) {
        self.config = config
        self.send = send
        self.encoders = encoders ?? Self.makeEncoders(config: config)
    }

    var activeCodec: RemoteCmd.StreamCodec? { encoders.first?.codec }

    /// Capture-queue only. Encodes and sends this frame unless pacing skips it
    /// or every codec in the chain has failed.
    func handle(pixelBuffer: CVPixelBuffer,
                position: AVCaptureDevice.Position,
                orientation: UIInterfaceOrientation,
                fps: Int) {
        frameCount += 1
        guard frameCount % config.frameDivisor == 0 else { return }

        guard let frame = encodeWithFallback(&encoders, pixelBuffer: pixelBuffer) else { return }

        if frame.codec != lastAnnouncedCodec {
            lastAnnouncedCodec = frame.codec
            StreamLog.encode.info("peer preview stream codec selected: \(String(describing: frame.codec))")
        }
        sequenceNumber &+= 1
        StreamLog.encode.debug(
            "frame seq=\(self.sequenceNumber) codec=\(String(describing: frame.codec)) bytes=\(frame.data.count)")
        send(RemoteCmd.SendFrame(
            data: frame.data,
            sender: nil,
            fps: fps,
            camPosition: position,
            camOrientation: orientation,
            codec: frame.codec,
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
                return nil // Watch-preview codec today; peer-monitor VP9 is a follow-up
            }
        }
    }
}
