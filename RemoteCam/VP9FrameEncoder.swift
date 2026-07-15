//
//  VP9FrameEncoder.swift
//  RemoteShutter
//
//  Preview video encoder for the Apple Watch stream: pure-Rust VP9 from the
//  VideocallCodecs framework (no VideoToolbox on watchOS, so the Watch decodes
//  with the matching Rust Vp9Decoder). Inter frames are a fraction of a
//  still's size, which is the whole point — more preview fps through the same
//  WCSession byte budget.
//
//  Per frame: downscale the 32BGRA capture buffer with vImage, convert to
//  planar I420 (full-range ITU-R 601, mirrored by the Watch decoder), feed the
//  Rust encoder. The Rust session is recreated whenever the scaled dimensions
//  change (rotation, lens switch, camera flip) — a fresh session's first frame
//  is a keyframe, so every geometry change re-syncs the stream for free.
//
//  Confined to the capture queue like every FrameEncoding conformer; all
//  buffers are reused across frames and never shared across threads.
//

import Foundation
import CoreVideo
import Accelerate
import VideocallCodecs

final class VP9FrameEncoder: StreamVideoEncoding {

    let codec: RemoteCmd.StreamCodec = .vp9

    private let maxLongEdge: Int
    private let settings: StreamingConfig.VP9Settings

    /// BGRA -> planar YpCbCr conversion tables, generated once.
    private var conversion = vImage_ARGBToYpCbCr()
    /// vImage permute map reading our BGRA memory order as ARGB.
    private let bgraToARGB: [UInt8] = [3, 2, 1, 0]

    /// Rust encoder session plus the geometry it was created for.
    private var session: Vp9Encoder?
    private var sessionWidth = 0
    private var sessionHeight = 0
    private var pts: Int64 = 0

    /// Scratch buffers reused across frames (capture-queue confined).
    private var scaledBGRA: UnsafeMutableRawPointer?
    private var scaledBGRACapacity = 0
    private var i420 = Data()

    init(maxLongEdge: CGFloat, settings: StreamingConfig.VP9Settings) {
        self.maxLongEdge = Int(maxLongEdge)
        self.settings = settings

        // Full-range 8-bit YpCbCr (Apple's documented full-range pixel range);
        // WatchVP9PreviewDecoder uses the identical range on the way back.
        var pixelRange = vImage_YpCbCrPixelRange(
            Yp_bias: 0, CbCr_bias: 128,
            YpRangeMax: 255, CbCrRangeMax: 255,
            YpMax: 255, YpMin: 1,
            CbCrMax: 255, CbCrMin: 0)
        vImageConvert_ARGBToYpCbCr_GenerateConversion(
            kvImage_ARGBToYpCbCrMatrix_ITU_R_601_4,
            &pixelRange,
            &conversion,
            kvImageARGB8888,
            kvImage420Yp8_Cb8_Cr8,
            vImage_Flags(kvImageNoFlags))
    }

    deinit {
        scaledBGRA?.deallocate()
    }

    /// Forces the next encoded frame to be a keyframe by dropping the current
    /// Rust session; `encode` remakes it on the next call and a fresh session's
    /// first frame is always a keyframe. Capture-queue confined like `encode` —
    /// answers a monitor's RequestKeyframe so a desynced decoder re-syncs
    /// immediately instead of waiting for the periodic keyframe.
    func forceKeyframe() {
        session = nil
        sessionWidth = 0
        sessionHeight = 0
    }

    func encode(pixelBuffer: CVPixelBuffer) -> FrameEncodeResult {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            return .failed
        }

        let srcWidth = CVPixelBufferGetWidth(pixelBuffer)
        let srcHeight = CVPixelBufferGetHeight(pixelBuffer)
        guard srcWidth > 0, srcHeight > 0 else { return .failed }

        // Even dimensions are a hard encoder requirement (4:2:0 chroma).
        let scale = min(1.0, Double(maxLongEdge) / Double(max(srcWidth, srcHeight)))
        let dstWidth = max(2, Int(Double(srcWidth) * scale) / 2 * 2)
        let dstHeight = max(2, Int(Double(srcHeight) * scale) / 2 * 2)

        if dstWidth != sessionWidth || dstHeight != sessionHeight {
            guard remakeSession(width: dstWidth, height: dstHeight) else { return .failed }
        }
        guard let session, let scaledBGRA else { return .failed }

        // 1. Downscale BGRA with vImage (channel-order agnostic).
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let srcBase = CVPixelBufferGetBaseAddress(pixelBuffer) else { return .failed }

        var src = vImage_Buffer(data: srcBase,
                                height: vImagePixelCount(srcHeight),
                                width: vImagePixelCount(srcWidth),
                                rowBytes: CVPixelBufferGetBytesPerRow(pixelBuffer))
        var dst = vImage_Buffer(data: scaledBGRA,
                                height: vImagePixelCount(dstHeight),
                                width: vImagePixelCount(dstWidth),
                                rowBytes: dstWidth * 4)
        guard vImageScale_ARGB8888(&src, &dst, nil, vImage_Flags(kvImageNoFlags)) == kvImageNoError else {
            return .failed
        }

        // 2. BGRA -> tightly-packed planar I420 (Yp, then Cb, then Cr).
        let lumaBytes = dstWidth * dstHeight
        let chromaWidth = dstWidth / 2
        let chromaBytes = chromaWidth * (dstHeight / 2)
        let converted: Bool = i420.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return false }
            var yp = vImage_Buffer(data: base,
                                   height: vImagePixelCount(dstHeight),
                                   width: vImagePixelCount(dstWidth),
                                   rowBytes: dstWidth)
            var cb = vImage_Buffer(data: base + lumaBytes,
                                   height: vImagePixelCount(dstHeight / 2),
                                   width: vImagePixelCount(chromaWidth),
                                   rowBytes: chromaWidth)
            var cr = vImage_Buffer(data: base + lumaBytes + chromaBytes,
                                   height: vImagePixelCount(dstHeight / 2),
                                   width: vImagePixelCount(chromaWidth),
                                   rowBytes: chromaWidth)
            return vImageConvert_ARGB8888To420Yp8_Cb8_Cr8(
                &dst, &yp, &cb, &cr, &conversion, bgraToARGB,
                vImage_Flags(kvImageNoFlags)) == kvImageNoError
        }
        guard converted else { return .failed }

        // 3. Compress. nil = the encoder buffered the frame: skip, don't fail.
        do {
            let compressed = try session.encode(pts: pts, i420: i420)
            pts += 1
            guard let compressed else { return .skipped }
            return .encoded(compressed)
        } catch {
            StreamLog.encode.error("VP9 encode failed: \(error)")
            return .failed
        }
    }

    /// (Re)creates the Rust encoder and scratch buffers for a new geometry.
    private func remakeSession(width: Int, height: Int) -> Bool {
        do {
            session = try Vp9Encoder(
                width: UInt32(width), height: UInt32(height),
                fps: settings.fps,
                bitrateKbps: settings.bitrateKbps,
                keyframeInterval: settings.keyframeInterval,
                minQuantizer: settings.minQuantizer,
                maxQuantizer: settings.maxQuantizer,
                cpuUsed: settings.cpuUsed)
        } catch {
            StreamLog.encode.error("VP9 encoder init failed (\(width)x\(height)): \(error)")
            session = nil
            return false
        }
        sessionWidth = width
        sessionHeight = height
        pts = 0
        StreamLog.encode.info("""
            VP9 encoder session started: \(width)x\(height) @ \(self.settings.bitrateKbps) kbps, \
            keyframe every \(self.settings.keyframeInterval) frames
            """)

        let bgraBytes = width * 4 * height
        if bgraBytes > scaledBGRACapacity {
            scaledBGRA?.deallocate()
            scaledBGRA = UnsafeMutableRawPointer.allocate(byteCount: bgraBytes, alignment: 64)
            scaledBGRACapacity = bgraBytes
        }
        i420 = Data(count: width * height + 2 * (width / 2) * (height / 2))
        return true
    }
}
