//
//  FrameStreamReceiver.swift
//  RemoteShutter
//
//  Monitor-side streaming pipeline: decodes incoming frames off the actor
//  mailbox on a dedicated queue, watches for stalls (no frame for
//  stallTimeout -> onStall so the state machine re-requests one), recovers on
//  foreground, and logs sequence gaps + per-second stream stats.
//
//  Stills (JPEG/HEIC, and frames from legacy peers) decode through
//  UIImage(data:), which sniffs the container from magic bytes. VP9 is a
//  stateful video stream, decoded by `PeerVP9PreviewDecoder`; an undecodable
//  VP9 frame (joined mid-stream, transient loss) asks the camera for a keyframe
//  via `onKeyframeNeeded`, rate-limited, so the decoder re-syncs.
//

import UIKit
import Accelerate
import CoreImage
import VideoToolbox
import VideocallCodecs

/// `@unchecked Sendable`: `receive(_:)` hops straight to `decodeQueue`, and all
/// mutable decode state is confined there; the `onImage`/`onStall`/
/// `onKeyframeNeeded` callbacks are wired once before `start()`. This lets the
/// multicam controller hold a per-lane frame sink that calls `receive` from the
/// actor without reaching into a `UIViewController`.
final class FrameStreamReceiver: @unchecked Sendable {

    /// Decoded frame ready for display. Called on the decode queue — hop to
    /// main before touching UI.
    var onImage: ((UIImage) -> Void)?
    /// No frame has arrived for `config.stallTimeout`. Called on the decode
    /// queue, at most once per timeout while the stall persists.
    var onStall: (() -> Void)?
    /// The VP9 decoder is desynced (undecodable frame) — the camera should send a
    /// keyframe. Called on the decode queue, rate-limited to at most once per
    /// `config.keyframeRequestInterval` while the desync persists.
    var onKeyframeNeeded: (() -> Void)?

    private let config: StreamingConfig
    private let now: () -> TimeInterval
    let decodeQueue = DispatchQueue(label: "frame stream decode queue", qos: .userInteractive)

    private var timer: DispatchSourceTimer?
    private var foregroundObserver: NSObjectProtocol?

    // State below is confined to decodeQueue.
    private var lastFrameAt: TimeInterval = 0
    private var lastStallReportAt: TimeInterval = 0
    private var lastSequenceNumber: UInt32 = 0
    private(set) var sequenceGapCount = 0
    private var statsFrames = 0
    private var statsBytes = 0
    private var statsWindowStart: TimeInterval = 0
    private var lastKeyframeRequestAt: TimeInterval = 0
    /// Stateful VP9 decoder, confined to `decodeQueue` (single-threaded).
    private lazy var vp9Decoder = PeerVP9PreviewDecoder()
    /// Stateful HEVC decoder (VideoToolbox), confined to `decodeQueue`. The
    /// preferred peer codec; VP9 remains for peers that negotiated the fallback.
    private lazy var hevcDecoder = PeerHEVCPreviewDecoder()

    init(config: StreamingConfig = .default,
         now: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate },
         notificationCenter: NotificationCenter = .default) {
        self.config = config
        self.now = now
        foregroundObserver = notificationCenter.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.decodeQueue.async {
                // iOS may have frozen both peers while backgrounded; the
                // in-flight ping-pong message is likely gone. Re-request
                // immediately instead of waiting for the stall watchdog.
                StreamLog.lifecycle.info("monitor foregrounded — re-requesting frame")
                self.resetStallClock()
                self.onStall?()
                // A frame alone isn't enough: this decoder still holds references
                // from before the freeze while the camera's encoder moved on.
                // Deltas built on those decode without error and render as smears,
                // so nothing would ever prompt a request — ask up front.
                self.requestKeyframe(at: self.now())
            }
        }
    }

    deinit {
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
        timer?.cancel()
    }

    /// Arms the stall watchdog. Call once the monitor UI is up.
    func start() {
        decodeQueue.async { self.resetStallClock() }
        let timer = DispatchSource.makeTimerSource(queue: decodeQueue)
        timer.schedule(deadline: .now() + config.stallCheckInterval,
                       repeating: config.stallCheckInterval)
        timer.setEventHandler { [weak self] in self?.checkForStall() }
        timer.resume()
        self.timer = timer
    }

    func invalidate() {
        timer?.cancel()
        timer = nil
    }

    /// Thread-safe entry point: decode + display a received frame.
    func receive(_ frame: RemoteCmd.OnFrame) {
        decodeQueue.async { self.process(frame) }
    }

    // MARK: - decodeQueue

    private func process(_ frame: RemoteCmd.OnFrame) {
        let time = now()
        lastFrameAt = time
        trackSequence(frame)
        trackStats(frame, at: time)

        // Stateful video streams (HEVC preferred, VP9 fallback): an undecodable
        // frame (joined mid-stream, transient loss) asks the camera for a
        // keyframe so the decoder re-syncs.
        if frame.codec == .hevc || frame.codec == .vp9 {
            let image = frame.codec == .hevc
                ? hevcDecoder.decode(frame.data)
                : vp9Decoder.decode(frame.data)
            if let image {
                onImage?(image)
            } else {
                requestKeyframe(at: time)
            }
            return
        }

        // Stills (JPEG/HEIC/legacy): UIImage(data:) sniffs the container.
        guard let image = UIImage(data: frame.data) else {
            StreamLog.decode.error(
                "undecodable frame seq=\(frame.sequenceNumber) codec=\(String(describing: frame.codec)) bytes=\(frame.data.count)")
            return
        }
        onImage?(image)
    }

    /// Asks the camera for a keyframe when the VP9 decoder can't decode, but no
    /// more than once per `keyframeRequestInterval` — a burst of undecodable
    /// delta frames all point at the same missing keyframe.
    private func requestKeyframe(at time: TimeInterval) {
        guard time - lastKeyframeRequestAt > config.keyframeRequestInterval else { return }
        lastKeyframeRequestAt = time
        StreamLog.decode.info("VP9 decoder desynced — requesting keyframe")
        onKeyframeNeeded?()
    }

    /// Sequence gaps are expected occasionally (frames ride .unreliable); for
    /// stills the next frame self-heals, so gaps are a debug signal only.
    private func trackSequence(_ frame: RemoteCmd.OnFrame) {
        defer { lastSequenceNumber = frame.sequenceNumber }
        guard frame.sequenceNumber != 0, lastSequenceNumber != 0,
              frame.sequenceNumber > lastSequenceNumber &+ 1 else { return }
        sequenceGapCount += 1
        StreamLog.decode.debug("sequence gap: \(self.lastSequenceNumber) -> \(frame.sequenceNumber)")
    }

    private func trackStats(_ frame: RemoteCmd.OnFrame, at time: TimeInterval) {
        if statsWindowStart == 0 { statsWindowStart = time }
        statsFrames += 1
        statsBytes += frame.data.count
        let elapsed = time - statsWindowStart
        guard elapsed >= 1.0 else { return }
        let fps = Double(statsFrames) / elapsed
        let kbPerFrame = Double(statsBytes) / Double(statsFrames) / 1024.0
        StreamLog.decode.debug(
            """
            stream stats: \(fps, format: .fixed(precision: 1))fps \
            \(kbPerFrame, format: .fixed(precision: 1))KB/frame codec=\(String(describing: frame.codec))
            """)
        statsWindowStart = time
        statsFrames = 0
        statsBytes = 0
    }

    func checkForStall() {
        let time = now()
        guard time - lastFrameAt > config.stallTimeout,
              time - lastStallReportAt > config.stallTimeout else { return }
        lastStallReportAt = time
        StreamLog.transport.info(
            "no frame for \(time - self.lastFrameAt, format: .fixed(precision: 1))s — raising StreamStalled")
        onStall?()
    }

    private func resetStallClock() {
        lastFrameAt = now()
        lastStallReportAt = 0
    }
}

/// Decodes the camera's VP9 preview stream with the pure-Rust `Vp9Decoder`
/// (VideocallCodecs). The decoder is stateful — it needs a keyframe first, then
/// inter frames in order — so it follows a drop-but-recover policy: an
/// undecodable frame (monitor joined mid-stream, a delta frame was lost) returns
/// nil, the caller asks the camera for a keyframe, and the stream re-syncs. A
/// failure streak longer than one keyframe interval recreates the decoder to
/// drain any poisoned state.
///
/// Not thread-safe: confined to the caller's serial queue (the
/// `FrameStreamReceiver.decodeQueue`), mirroring the Watch's decoder.
///
/// Output frames are tightly-packed I420; vImage converts them to ARGB with the
/// same full-range ITU-R 601 tables the camera used on the way in
/// (`VP9FrameEncoder`).
final class PeerVP9PreviewDecoder {

    private var decoder = Vp9Decoder()
    private var failureStreak = 0
    private let maxFailureStreak: Int
    private var announcedStreamLive = false
    private var conversion = vImage_YpCbCrToARGB()
    private let identityPermute: [UInt8] = [0, 1, 2, 3]
    /// Reused ARGB destination for every frame — allocating a multi-MB buffer
    /// per frame at stream rate churns memory. vImage converts into the
    /// context's backing store in place; `makeImage()` snapshots it with
    /// copy-on-write pages, so overwriting it for the next frame cannot corrupt
    /// an image already handed out. Recreated only when the stream dimensions
    /// change. Queue-confined like the decoder.
    private var argbContext: CGContext?

    init(maxFailureStreak: Int = 30) {
        self.maxFailureStreak = maxFailureStreak

        // Full-range 8-bit YpCbCr — identical range to VP9FrameEncoder's output.
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

    /// Decodes one VP9 frame on the caller's queue. Returns the rendered image,
    /// or nil for a dropped/undecodable frame (the caller then requests a
    /// keyframe). A long failure streak recreates the decoder.
    func decode(_ frame: Data) -> UIImage? {
        do {
            let decoded = try decoder.decode(frame: frame)
            failureStreak = 0
            if !announcedStreamLive {
                announcedStreamLive = true
                StreamLog.decode.info("VP9 preview stream live (\(decoded.width)x\(decoded.height))")
            }
            return makeImage(from: decoded)
        } catch {
            failureStreak += 1
            StreamLog.decode.debug("dropped undecodable VP9 frame (streak \(self.failureStreak)): \(error)")
            if failureStreak >= maxFailureStreak {
                StreamLog.decode.info("VP9 failure streak exceeded keyframe interval — resetting decoder")
                decoder = Vp9Decoder()
                failureStreak = 0
                announcedStreamLive = false
            }
            return nil
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

/// Decodes the camera's HEVC preview stream with VideoToolbox
/// (`VTDecompressionSession`). Mirrors `PeerVP9PreviewDecoder`'s contract exactly
/// — stateful, drop-but-recover — so `FrameStreamReceiver` treats the two video
/// codecs uniformly.
///
/// Each keyframe payload carries its VPS/SPS/PPS parameter sets inline (see
/// `HEVCFrameContainer`), from which the session's `CMFormatDescription` is
/// (re)built; inter frames carry only AVCC NAL units. A frame that arrives before
/// any keyframe (monitor joined mid-stream), or a lost delta, returns nil and the
/// caller asks the camera for a keyframe. A failure streak longer than one
/// keyframe interval tears the session down to drain poisoned state.
///
/// Not thread-safe: confined to `FrameStreamReceiver.decodeQueue`.
final class PeerHEVCPreviewDecoder {

    private var session: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var failureStreak = 0
    private let maxFailureStreak: Int
    private var announcedStreamLive = false

    init(maxFailureStreak: Int = 30) {
        self.maxFailureStreak = maxFailureStreak
    }

    deinit {
        if let session { VTDecompressionSessionInvalidate(session) }
    }

    /// Decodes one HEVC frame on the caller's queue. Returns the rendered image,
    /// or nil for a dropped/undecodable frame (the caller then requests a
    /// keyframe).
    func decode(_ data: Data) -> UIImage? {
        guard let (parameterSets, frame) = HEVCFrameContainer.unpack(data) else {
            return recordFailure("malformed HEVC container (\(data.count) bytes)")
        }
        if let parameterSets, !rebuildSession(from: parameterSets) {
            return recordFailure("could not rebuild HEVC decoder from parameter sets")
        }
        guard let session, let formatDescription else {
            return recordFailure("HEVC frame before first keyframe")
        }
        guard let sampleBuffer = makeSampleBuffer(frame: frame, format: formatDescription) else {
            return recordFailure("could not wrap HEVC frame")
        }

        var image: UIImage?
        let done = DispatchSemaphore(value: 0)
        let status = VTDecompressionSessionDecodeFrame(
            session, sampleBuffer: sampleBuffer, flags: [._1xRealTimePlayback], infoFlagsOut: nil
        ) { [ciContext] decodeStatus, _, imageBuffer, _, _ in
            defer { done.signal() }
            guard decodeStatus == noErr, let imageBuffer else { return }
            let ciImage = CIImage(cvPixelBuffer: imageBuffer)
            if let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
                image = UIImage(cgImage: cgImage)
            }
        }
        guard status == noErr else { return recordFailure("VTDecompressionSessionDecodeFrame: \(status)") }
        done.wait()

        guard let image else { return recordFailure("HEVC decode produced no image") }
        failureStreak = 0
        if !announcedStreamLive {
            announcedStreamLive = true
            StreamLog.decode.info("HEVC preview stream live")
        }
        return image
    }

    private func recordFailure(_ reason: String) -> UIImage? {
        failureStreak += 1
        StreamLog.decode.debug("dropped undecodable HEVC frame (streak \(self.failureStreak)): \(reason)")
        if failureStreak >= maxFailureStreak {
            StreamLog.decode.info("HEVC failure streak exceeded keyframe interval — resetting decoder")
            invalidate()
        }
        return nil
    }

    private func invalidate() {
        if let session { VTDecompressionSessionInvalidate(session) }
        session = nil
        formatDescription = nil
        failureStreak = 0
        announcedStreamLive = false
    }

    /// Builds a fresh format description from the keyframe's parameter sets and,
    /// if the running session can't accept it, a new decompression session.
    private func rebuildSession(from parameterSets: Data) -> Bool {
        let sets = parseParameterSets(parameterSets)
        guard sets.count >= 3, let format = makeFormatDescription(sets) else { return false }

        if let session, VTDecompressionSessionCanAcceptFormatDescription(session, formatDescription: format) {
            formatDescription = format
            return true
        }
        if let session { VTDecompressionSessionInvalidate(session) }
        session = nil
        formatDescription = format

        let destAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        var newSession: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: format,
            decoderSpecification: nil,
            imageBufferAttributes: destAttributes as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &newSession)
        guard status == noErr, let newSession else { return false }
        VTSessionSetProperty(newSession, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        session = newSession
        return true
    }

    /// Parses `[UInt32-LE count]([UInt32-LE len][bytes])…` — the mirror of
    /// `HEVCFrameEncoder.extractParameterSets`. Alignment-safe.
    private func parseParameterSets(_ data: Data) -> [Data] {
        guard data.count >= 4 else { return [] }
        var offset = 0
        let count = Int(data.readUInt32LE(at: offset)); offset += 4
        var sets: [Data] = []
        for _ in 0..<count {
            guard offset + 4 <= data.count else { return [] }
            let size = Int(data.readUInt32LE(at: offset)); offset += 4
            guard offset + size <= data.count else { return [] }
            sets.append(data.subdata(in: offset..<(offset + size)))
            offset += size
        }
        return sets
    }

    /// HEVC parameter sets are VPS(0), SPS(1), PPS(2) with a 4-byte NAL length
    /// header (matching VideoToolbox's AVCC output).
    private func makeFormatDescription(_ sets: [Data]) -> CMVideoFormatDescription? {
        sets[0].withUnsafeBytes { vps in
            sets[1].withUnsafeBytes { sps in
                sets[2].withUnsafeBytes { pps in
                    guard let vpsBase = vps.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let spsBase = sps.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let ppsBase = pps.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
                    var pointers = [vpsBase, spsBase, ppsBase]
                    var sizes = [sets[0].count, sets[1].count, sets[2].count]
                    var desc: CMVideoFormatDescription?
                    let status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: 3,
                        parameterSetPointers: &pointers,
                        parameterSetSizes: &sizes,
                        nalUnitHeaderLength: 4,
                        extensions: nil,
                        formatDescriptionOut: &desc)
                    return status == noErr ? desc : nil
                }
            }
        }
    }

    private func makeSampleBuffer(frame: Data, format: CMFormatDescription) -> CMSampleBuffer? {
        var blockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: frame.count,
            blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: frame.count,
            flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &blockBuffer)
        guard status == kCMBlockBufferNoErr, let blockBuffer else { return nil }
        let copied: Bool = frame.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return false }
            return CMBlockBufferReplaceDataBytes(
                with: base, blockBuffer: blockBuffer, offsetIntoDestination: 0,
                dataLength: frame.count) == kCMBlockBufferNoErr
        }
        guard copied else { return nil }

        var sampleBuffer: CMSampleBuffer?
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: blockBuffer, formatDescription: format,
            sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
            sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sampleBuffer)
        return status == noErr ? sampleBuffer : nil
    }
}
