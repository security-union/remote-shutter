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

        guard let data = encodeWithFallback(&encoders, pixelBuffer: pixelBuffer),
              let codec = activeCodec else { return }

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
            }
        }
    }
}
