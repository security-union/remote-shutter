//
//  WatchVP9PreviewDecoder.swift
//  RemoteShutterWatch
//
//  Decodes the phone's VP9 preview stream with the pure-Rust Vp9Decoder from
//  the VideocallCodecs framework (watchOS has no VideoToolbox). The decoder is
//  stateful — it needs a keyframe first, then inter frames in order — so all
//  work is confined to one serial queue and failures follow a drop-but-ack
//  policy: an undecodable frame (Watch joined mid-stream, WCSession dropped a
//  frame while unreachable) is discarded, the caller still acks so the phone
//  keeps streaming, and the phone's periodic keyframe re-syncs the stream. A
//  failure streak longer than one keyframe interval recreates the decoder to
//  drain any poisoned state.
//
//  Output frames are tightly-packed I420; vImage converts them to ARGB with
//  the same full-range ITU-R 601 tables the phone used on the way in.
//

import Foundation
import UIKit
import Accelerate
import VideocallCodecs

final class WatchVP9PreviewDecoder {

    /// Serial home for the stateful Rust decoder and the conversion scratch state.
    private let queue = DispatchQueue(label: "watch.vp9.preview.decode", qos: .userInteractive)

    // All below confined to `queue`.
    private var decoder = Vp9Decoder()
    private var failureStreak = 0
    /// One "stream is live" log per decoder generation, so the selected format
    /// shows up in the Watch console without per-frame chatter.
    private var announcedStreamLive = false
    /// One encoder keyframe interval: if this many consecutive frames fail, the
    /// stream has outrun recovery — start a fresh decoder.
    private let maxFailureStreak: Int
    /// YpCbCr -> ARGB tables, generated once (mirror of the phone's encode side).
    private var conversion = vImage_YpCbCrToARGB()
    /// Identity channel order: emit A,R,G,B exactly as the CGImage expects.
    private let identityPermute: [UInt8] = [0, 1, 2, 3]
    /// Reused ARGB destination for every frame — allocating a fresh buffer per
    /// frame at stream rate churns memory. vImage converts into the context's
    /// backing store in place; `makeImage()` snapshots it with copy-on-write
    /// pages, so overwriting it for the next frame cannot corrupt an image
    /// already handed out. Recreated only when the stream dimensions change.
    /// Queue-confined like the decoder.
    private var argbContext: CGContext?

    init(maxFailureStreak: Int = 30) {
        self.maxFailureStreak = maxFailureStreak

        // Full-range 8-bit YpCbCr — identical pixel range to VP9FrameEncoder.
        var pixelRange = vImage_YpCbCrPixelRange(
            Yp_bias: 0, CbCr_bias: 128,
            YpRangeMax: 255, CbCrRangeMax: 255,
            YpMax: 255, YpMin: 1,
            CbCrMax: 255, CbCrMin: 0)
        vImageConvert_YpCbCrToARGB_GenerateConversion(
            kvImage_YpCbCrToARGBMatrix_ITU_R_601_4,
            &pixelRange,
            &conversion,
            kvImage420Yp8_Cb8_Cr8,
            kvImageARGB8888,
            vImage_Flags(kvImageNoFlags))
    }

    /// Decodes one VP9 frame off the caller's thread. `completion` fires on the
    /// decode queue with the rendered image, or nil for a dropped frame (the
    /// caller acks either way — see the drop-but-ack policy above).
    func decode(frame: Data, completion: @escaping (UIImage?) -> Void) {
        queue.async { [self] in
            do {
                let decoded = try decoder.decode(frame: frame)
                failureStreak = 0
                if !announcedStreamLive {
                    announcedStreamLive = true
                    debugLog("WatchVP9PreviewDecoder: VP9 preview stream live (\(decoded.width)x\(decoded.height))")
                }
                completion(makeImage(from: decoded))
            } catch {
                failureStreak += 1
                debugLog("WatchVP9PreviewDecoder: dropped undecodable frame "
                    + "(streak \(failureStreak)): \(error)")
                if failureStreak >= maxFailureStreak {
                    debugLog("WatchVP9PreviewDecoder: failure streak exceeded keyframe interval — resetting decoder")
                    decoder = Vp9Decoder()
                    failureStreak = 0
                    announcedStreamLive = false
                }
                completion(nil)
            }
        }
    }

    /// Tightly-packed I420 -> ARGB8888 -> CGImage -> UIImage.
    private func makeImage(from decoded: DecodedFrame) -> UIImage? {
        let width = Int(decoded.width)
        let height = Int(decoded.height)
        let chromaWidth = (width + 1) / 2
        let chromaHeight = (height + 1) / 2
        let lumaBytes = width * height
        let chromaBytes = chromaWidth * chromaHeight
        guard width > 0, height > 0,
              decoded.data.count >= lumaBytes + 2 * chromaBytes else { return nil }

        if argbContext == nil || argbContext?.width != width || argbContext?.height != height {
            argbContext = CGContext(
                data: nil,                       // CG owns (and reuses) the buffer
                width: width, height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,                  // CG picks an aligned stride
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        }
        guard let context = argbContext, let dstBase = context.data else { return nil }

        let converted: Bool = decoded.data.withUnsafeBytes { srcRaw -> Bool in
            guard let srcBase = srcRaw.baseAddress else { return false }
            var yp = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: srcBase),
                                   height: vImagePixelCount(height),
                                   width: vImagePixelCount(width),
                                   rowBytes: width)
            var cb = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: srcBase + lumaBytes),
                                   height: vImagePixelCount(chromaHeight),
                                   width: vImagePixelCount(chromaWidth),
                                   rowBytes: chromaWidth)
            var cr = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: srcBase + lumaBytes + chromaBytes),
                                   height: vImagePixelCount(chromaHeight),
                                   width: vImagePixelCount(chromaWidth),
                                   rowBytes: chromaWidth)
            var dst = vImage_Buffer(data: dstBase,
                                    height: vImagePixelCount(height),
                                    width: vImagePixelCount(width),
                                    rowBytes: context.bytesPerRow)
            return vImageConvert_420Yp8_Cb8_Cr8ToARGB8888(
                &yp, &cb, &cr, &dst, &conversion, identityPermute, 255,
                vImage_Flags(kvImageNoFlags)) == kvImageNoError
        }
        guard converted, let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
