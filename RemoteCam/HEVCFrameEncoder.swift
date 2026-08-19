//
//  HEVCFrameEncoder.swift
//  RemoteShutter
//
//  Peer (phone/Mac camera → phone/Mac monitor) preview encoder: hardware HEVC
//  via VideoToolbox (`VTCompressionSession`, `kCMVideoCodecType_HEVC`). This is
//  the preferred peer codec — the software VP9 path (`VP9FrameEncoder`) is the
//  fallback for peers that can't hardware-encode HEVC (pre-A10) and remains the
//  only option for the Watch (no VideoToolbox on watchOS).
//
//  Like VP9, HEVC is a STATEFUL video stream: inter frames are deltas against
//  the decoder's reference, so a dropped frame corrupts decode until the next
//  keyframe. It therefore lives behind `StreamVideoEncoding` (lazy encode +
//  credit-window back-pressure + `forceKeyframe` in `FrameStreamer`), never the
//  drop-happy still chain.
//
//  Self-describing wire container: `VTCompressionSession` emits length-prefixed
//  (AVCC, 4-byte) NAL units and carries the VPS/SPS/PPS parameter sets in the
//  sample's format description, NOT in the elementary stream. We prepend those
//  parameter sets to every keyframe payload (see `HEVCFrameContainer`) so a
//  monitor joining mid-stream rebuilds its decoder from the next keyframe alone —
//  the exact re-sync guarantee VP9's keyframes give.
//
//  Synchronous contract: `StreamVideoEncoding.encode` returns the compressed
//  frame inline, but `VTCompressionSessionEncodeFrame` completes on VideoToolbox's
//  own queue. Because frame reordering is disabled and the session is realtime,
//  each input yields exactly one output promptly; we bridge the callback to the
//  synchronous return with a `DispatchSemaphore`. Confined to the capture queue
//  like every `FrameEncoding` conformer.
//

import Foundation
import CoreVideo
import CoreImage
import VideoToolbox

/// Wire container for one HEVC preview frame: an optional parameter-set blob
/// (present on keyframes) followed by the AVCC frame data. Serialized so the
/// receiver can rebuild its decoder from a keyframe without a side channel.
///
/// Layout: `[UInt32-LE paramBlobLen][paramBlob (paramBlobLen bytes)][frame …]`.
/// `paramBlobLen == 0` marks an inter frame (no parameter sets). All multi-byte
/// integers are little-endian and read with alignment-safe copies — FlatBuffers-
/// deserialized `Data` is not guaranteed 4-byte aligned.
enum HEVCFrameContainer {
    static func pack(parameterSets: Data?, frame: Data) -> Data {
        var out = Data(capacity: 4 + (parameterSets?.count ?? 0) + frame.count)
        out.appendUInt32LE(UInt32(parameterSets?.count ?? 0))
        if let parameterSets { out.append(parameterSets) }
        out.append(frame)
        return out
    }

    /// Splits a payload back into its parameter-set blob (nil on inter frames)
    /// and frame bytes. Returns nil if the header is truncated or lies.
    static func unpack(_ data: Data) -> (parameterSets: Data?, frame: Data)? {
        guard data.count >= 4 else { return nil }
        let paramLen = Int(data.readUInt32LE(at: 0))
        let frameStart = 4 + paramLen
        guard frameStart <= data.count else { return nil }
        let params = paramLen > 0 ? data.subdata(in: 4..<frameStart) : nil
        let frame = data.subdata(in: frameStart..<data.count)
        return (params, frame)
    }
}

final class HEVCFrameEncoder: StreamVideoEncoding {

    let codec: RemoteCmd.StreamCodec = .hevc

    private let maxLongEdge: Int
    private let settings: HEVCSettings

    /// GPU context that scales each capture buffer into the encoder's input size.
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    /// Pool of BGRA buffers at the current session geometry, fed to VideoToolbox.
    private var pixelBufferPool: CVPixelBufferPool?

    /// Hardware compression session plus the geometry it was created for.
    private var session: VTCompressionSession?
    private var sessionWidth = 0
    private var sessionHeight = 0
    private var pts: Int64 = 0
    private var forceNextKeyframe = false

    init(maxLongEdge: CGFloat, settings: HEVCSettings) {
        self.maxLongEdge = Int(maxLongEdge)
        self.settings = settings
    }

    deinit {
        invalidateSession()
    }

    /// Forces the next encoded frame to be a keyframe — answers a monitor's
    /// RequestKeyframe so a desynced decoder re-syncs without waiting for the
    /// periodic keyframe. Capture-queue confined like `encode`.
    func forceKeyframe() {
        forceNextKeyframe = true
    }

    func encode(pixelBuffer: CVPixelBuffer) -> FrameEncodeResult {
        let srcWidth = CVPixelBufferGetWidth(pixelBuffer)
        let srcHeight = CVPixelBufferGetHeight(pixelBuffer)
        guard srcWidth > 0, srcHeight > 0 else { return .failed }

        // Even dimensions: HEVC 4:2:0 chroma is subsampled by two.
        let scale = min(1.0, Double(maxLongEdge) / Double(max(srcWidth, srcHeight)))
        let dstWidth = max(2, Int(Double(srcWidth) * scale) / 2 * 2)
        let dstHeight = max(2, Int(Double(srcHeight) * scale) / 2 * 2)

        if dstWidth != sessionWidth || dstHeight != sessionHeight {
            guard remakeSession(width: dstWidth, height: dstHeight) else { return .failed }
        }
        guard let session, let scaled = scaledBuffer(from: pixelBuffer, width: dstWidth, height: dstHeight) else {
            return .failed
        }

        var frameProperties: [CFString: Any]?
        if forceNextKeyframe {
            frameProperties = [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue as Any]
            forceNextKeyframe = false
        }

        // Bridge the async VideoToolbox callback to the synchronous protocol:
        // the handler stashes the packaged payload in a lock-box; the
        // semaphore releases when it runs. Realtime + no reordering ⇒ one
        // output per input, promptly — WHEN the session is alive. The wait is
        // BOUNDED because backgrounding revokes hardware sessions: a submit
        // into a revoked session returns noErr and then never calls back,
        // and an unbounded wait here froze the whole capture data queue
        // (recording start included) for as long as the daemon took to
        // recover — tens of seconds after a wake.
        let box = Locked<FrameEncodeResult>(.failed)
        let done = DispatchSemaphore(value: 0)
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: scaled,
            presentationTimeStamp: CMTimeMake(value: pts, timescale: Int32(max(settings.fps, 1))),
            duration: .invalid,
            frameProperties: frameProperties as CFDictionary?,
            infoFlagsOut: nil
        ) { encodeStatus, _, sampleBuffer in
            if encodeStatus == noErr, let sampleBuffer,
               let payload = Self.package(sampleBuffer) {
                box.value = .encoded(payload)
            }
            done.signal()
        }

        guard status == noErr else {
            StreamLog.encode.error("HEVC encode submit failed: \(status)")
            return .failed
        }
        guard done.wait(timeout: .now() + Self.encodeCallbackTimeout) == .success else {
            // The callback never came — the revoked-session shape. Drop the
            // corpse (no flush: flushing waits on the same dead session) and
            // report SKIPPED, not failed: the next frame builds a fresh
            // session and the stream heals itself. A late callback lands in
            // the lock-box of an abandoned frame, harmlessly.
            StreamLog.encode.error("HEVC encode callback timed out — rebuilding the session")
            SessionDebug.note("⚠︎ HEVC encode callback timeout — session rebuilt")
            invalidateSession()
            return .skipped
        }
        pts += 1
        return box.value
    }

    /// How long one realtime encode may take before the session is presumed
    /// dead (a healthy one answers in milliseconds).
    private static let encodeCallbackTimeout: TimeInterval = 1.0

    // MARK: - Session

    /// (Re)creates the compression session and buffer pool for a new geometry.
    private func remakeSession(width: Int, height: Int) -> Bool {
        invalidateSession()

        let encoderSpec: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableLowLatencyRateControl: kCFBooleanTrue as Any
        ]
        var newSession: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: encoderSpec as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &newSession)
        guard status == noErr, let newSession else {
            StreamLog.encode.error("HEVC encoder init failed (\(width)x\(height)): \(status)")
            return false
        }

        VTSessionSetProperty(newSession, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(newSession, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(newSession, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_HEVC_Main_AutoLevel)
        VTSessionSetProperty(newSession, key: kVTCompressionPropertyKey_AverageBitRate, value: Int(settings.bitrateKbps) * 1000 as CFNumber)
        VTSessionSetProperty(newSession, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: Int(settings.fps) as CFNumber)
        VTSessionSetProperty(newSession, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: Int(settings.keyframeInterval) as CFNumber)
        VTCompressionSessionPrepareToEncodeFrames(newSession)

        session = newSession
        sessionWidth = width
        sessionHeight = height
        pts = 0
        forceNextKeyframe = false
        pixelBufferPool = Self.makePool(width: width, height: height)
        StreamLog.encode.info("""
            HEVC encoder session started: \(width)x\(height) @ \(self.settings.bitrateKbps) kbps, \
            keyframe every \(self.settings.keyframeInterval) frames
            """)
        return pixelBufferPool != nil
    }

    /// Deliberately NO flush (`VTCompressionSessionCompleteFrames`): for a
    /// realtime one-in-one-out preview stream there is never a trailing frame
    /// worth waiting for, and the flush blocks UNBOUNDEDLY on a session that
    /// backgrounding killed — it froze the whole capture data queue for tens
    /// of seconds. Drop the session; the next keyframe resyncs the decoder.
    private func invalidateSession() {
        if let session {
            VTCompressionSessionInvalidate(session)
        }
        session = nil
        sessionWidth = 0
        sessionHeight = 0
        pixelBufferPool = nil
    }

    private static func makePool(width: Int, height: Int) -> CVPixelBufferPool? {
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &pool)
        return pool
    }

    /// Scales the capture buffer into a pooled BGRA buffer at the session size.
    private func scaledBuffer(from source: CVPixelBuffer, width: Int, height: Int) -> CVPixelBuffer? {
        guard let pool = pixelBufferPool else { return nil }
        var dst: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &dst) == kCVReturnSuccess,
              let dst else { return nil }

        let image = CIImage(cvPixelBuffer: source)
        let longEdge = max(image.extent.width, image.extent.height)
        guard longEdge > 0 else { return nil }
        let s = min(1.0, CGFloat(max(width, height)) / longEdge)
        ciContext.render(image.transformed(by: CGAffineTransform(scaleX: s, y: s)), to: dst)
        return dst
    }

    // MARK: - Packaging

    /// Serializes one encoded sample into the wire container, prepending the
    /// VPS/SPS/PPS parameter sets on keyframes so the stream self-describes.
    private static func package(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil,
                                          totalLengthOut: &totalLength, dataPointerOut: &dataPointer) == kCMBlockBufferNoErr,
              let dataPointer else { return nil }
        let frame = Data(bytes: dataPointer, count: totalLength)

        var parameterSets: Data?
        if isKeyframe(sampleBuffer), let format = CMSampleBufferGetFormatDescription(sampleBuffer) {
            parameterSets = extractParameterSets(from: format)
        }
        return HEVCFrameContainer.pack(parameterSets: parameterSets, frame: frame)
    }

    private static func isKeyframe(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[CFString: Any]], let first = attachments.first else { return true }
        return !(first[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
    }

    /// Serializes the format description's HEVC parameter sets as
    /// `[UInt32-LE count]([UInt32-LE len][bytes])…`. Mirrored by
    /// `PeerHEVCPreviewDecoder`.
    private static func extractParameterSets(from format: CMFormatDescription) -> Data? {
        var count = 0
        guard CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                format, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil,
                parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil) == noErr, count > 0 else { return nil }

        var out = Data()
        out.appendUInt32LE(UInt32(count))
        for i in 0..<count {
            var pointer: UnsafePointer<UInt8>?
            var size = 0
            guard CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                    format, parameterSetIndex: i, parameterSetPointerOut: &pointer, parameterSetSizeOut: &size,
                    parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr, let pointer else { return nil }
            out.appendUInt32LE(UInt32(size))
            out.append(pointer, count: size)
        }
        return out
    }
}

// MARK: - Alignment-safe little-endian UInt32 (de)serialization

extension Data {
    /// Append a UInt32 as 4 little-endian bytes (alignment-safe).
    mutating func appendUInt32LE(_ value: UInt32) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }

    /// Read a UInt32 from 4 little-endian bytes at `offset` (alignment-safe:
    /// FlatBuffers-deserialized `Data` may not be 4-byte aligned).
    func readUInt32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        var value: UInt32 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { dest in
            copyBytes(to: dest, from: (startIndex + offset)..<(startIndex + offset + 4))
        }
        return UInt32(littleEndian: value)
    }
}
