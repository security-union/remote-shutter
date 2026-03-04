/// HEVCPlayground — Standalone encode→decode validation for the VideoToolbox HEVC pipeline.
///
/// Creates synthetic CVPixelBuffers, encodes them with VideoEncoder (HEVC),
/// then decodes the compressed NAL data with VideoDecoder and verifies output.
/// Run as a macOS command-line tool; no device or simulator required.

import Foundation
import CoreMedia
import CoreVideo
import VideoToolbox
import CoreImage

#if canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

// MARK: - Collected frame from encoder

struct EncodedFrame {
    let data: Data
    let isKeyframe: Bool
    let parameterSets: Data?
}

// MARK: - Encoder collector delegate

final class EncoderCollector: VideoEncoderDelegate {
    var frames: [EncodedFrame] = []

    func videoEncoder(_ encoder: VideoEncoder, didEncodeFrame data: Data, isKeyframe: Bool, parameterSets: Data?) {
        frames.append(EncodedFrame(data: data, isKeyframe: isKeyframe, parameterSets: parameterSets))
    }
}

// MARK: - Decoder collector delegate

final class DecoderCollector: VideoDecoderDelegate {
    var decodedCount = 0
    var keyframeRequests = 0

    func videoDecoder(_ decoder: VideoDecoder, didDecodeFrame image: PlatformImage) {
        decodedCount += 1
    }

    func videoDecoderNeedsKeyframe(_ decoder: VideoDecoder) {
        keyframeRequests += 1
    }
}

// MARK: - Helpers

func createPixelBuffer(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> CVPixelBuffer? {
    var pixelBuffer: CVPixelBuffer?
    let attrs: [CFString: Any] = [
        kCVPixelBufferWidthKey: width,
        kCVPixelBufferHeightKey: height,
        kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
        kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
    ]
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width, height,
        kCVPixelFormatType_32BGRA,
        attrs as CFDictionary,
        &pixelBuffer
    )
    guard status == kCVReturnSuccess, let pb = pixelBuffer else { return nil }

    CVPixelBufferLockBaseAddress(pb, [])
    defer { CVPixelBufferUnlockBaseAddress(pb, []) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(pb) else { return nil }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
    let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)

    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * 4
            ptr[offset + 0] = b     // B
            ptr[offset + 1] = g     // G
            ptr[offset + 2] = r     // R
            ptr[offset + 3] = 255   // A
        }
    }
    return pb
}

// MARK: - Main

func run() {
    let frameCount = 60
    let width = 640
    let height = 480

    print("=== HEVCPlayground ===")
    print("Encoding \(frameCount) frames at \(width)x\(height)...\n")

    // --- Encode ---
    let config = StreamingConfig(bitrate: 2_000_000, maxKeyFrameInterval: 30, fps: 30, width: width, height: height)
    let encoder = VideoEncoder(config: config)
    let collector = EncoderCollector()
    encoder.delegate = collector

    for i in 0..<frameCount {
        // Vary color so frames aren't all identical (encoder may skip identical frames)
        let shade = UInt8(i * 4 % 256)
        guard let pb = createPixelBuffer(width: width, height: height, r: shade, g: 128, b: UInt8(255 - shade)) else {
            print("FAIL: Could not create pixel buffer for frame \(i)")
            exit(1)
        }

        let pts = CMTimeMake(value: Int64(i), timescale: Int32(config.fps))
        encoder.encode(pb, presentationTime: pts)
    }

    // Flush remaining frames
    if let session = encoder.compressionSession {
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
    }

    // Give the async encoder callbacks a moment to complete
    Thread.sleep(forTimeInterval: 0.5)

    let encodedFrames = collector.frames
    let keyframes = encodedFrames.filter { $0.isKeyframe }
    let totalBytes = encodedFrames.reduce(0) { $0 + $1.data.count }

    print("Encoded: \(encodedFrames.count) frames (\(keyframes.count) keyframes)")
    print("Total compressed size: \(totalBytes) bytes (\(totalBytes / max(encodedFrames.count, 1)) bytes/frame avg)")

    if keyframes.isEmpty {
        print("FAIL: No keyframes produced — encoder may not be working")
        exit(1)
    }

    if keyframes[0].parameterSets == nil {
        print("FAIL: First keyframe has no parameter sets")
        exit(1)
    }

    // Print parameter set details for first keyframe
    if let ps = keyframes[0].parameterSets {
        print("\nFirst keyframe parameter sets: \(ps.count) bytes")
        let count = ps.readUInt32LE(at: 0)
        print("  Parameter set count: \(count)")
        var offset = 4
        for i in 0..<count {
            let size = ps.readUInt32LE(at: offset)
            offset += 4
            print("  Set \(i): \(size) bytes")
            offset += Int(size)
        }
    }

    // --- Decode ---
    print("\nDecoding \(encodedFrames.count) frames...")

    let decoder = VideoDecoder()
    let decoderCollector = DecoderCollector()
    decoder.delegate = decoderCollector

    for (i, frame) in encodedFrames.enumerated() {
        decoder.decode(frameData: frame.data, isKeyframe: frame.isKeyframe, parameterSets: frame.parameterSets)
        if (i + 1) % 10 == 0 || i == encodedFrames.count - 1 {
            print("  Decoded \(i + 1)/\(encodedFrames.count) — output images: \(decoderCollector.decodedCount), keyframe requests: \(decoderCollector.keyframeRequests)")
        }
    }

    print("\n=== Results ===")
    print("Encoded frames:  \(encodedFrames.count)")
    print("Decoded images:  \(decoderCollector.decodedCount)")
    print("Keyframe reqs:   \(decoderCollector.keyframeRequests)")

    if decoderCollector.decodedCount > 0 {
        print("\nSUCCESS: End-to-end HEVC encode/decode pipeline works!")
    } else {
        print("\nFAIL: No frames were decoded")
        exit(1)
    }

    encoder.invalidate()
    decoder.invalidate()
}

run()
