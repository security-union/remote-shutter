import Foundation
import VideoToolbox
import CoreMedia
import AVFoundation

protocol VideoEncoderDelegate: AnyObject {
    func videoEncoder(_ encoder: VideoEncoder, didEncodeFrame data: Data, isKeyframe: Bool, parameterSets: Data?)
}

final class VideoEncoder {
    weak var delegate: VideoEncoderDelegate?

    private(set) var compressionSession: VTCompressionSession?
    private let config: StreamingConfig
    private var forceNextKeyframe = false

    init(config: StreamingConfig) {
        self.config = config
    }

    /// Creates the compression session lazily on first encode using the actual
    /// pixel buffer dimensions. This avoids mismatches between config resolution
    /// and camera output resolution.
    private func ensureSession(width: Int, height: Int) -> VTCompressionSession? {
        if let session = compressionSession { return session }

        let encoderSpec: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true as CFBoolean
        ]

        var session: VTCompressionSession?
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
            compressionSessionOut: &session
        )

        guard status == noErr, let session = session else {
            print("VideoEncoder: failed to create session (\(status)) for \(width)x\(height)")
            return nil
        }

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: config.bitrate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: Double(config.fps) as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: config.maxKeyFrameInterval as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_HEVC_Main_AutoLevel)

        VTCompressionSessionPrepareToEncodeFrames(session)
        self.compressionSession = session
        return session
    }

    func encode(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let session = ensureSession(width: width, height: height) else { return }

        var frameProperties: CFDictionary?
        if forceNextKeyframe {
            let props: [CFString: Any] = [kVTEncodeFrameOptionKey_ForceKeyFrame: true as CFBoolean]
            frameProperties = props as CFDictionary
            forceNextKeyframe = false
        }

        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: .invalid,
            frameProperties: frameProperties,
            infoFlagsOut: nil
        ) { [weak self] status, _, sampleBuffer in
            guard status == noErr, let sampleBuffer = sampleBuffer else { return }
            self?.handleEncodedSampleBuffer(sampleBuffer)
        }
    }

    func forceKeyframe() {
        forceNextKeyframe = true
    }

    func invalidate() {
        if let session = compressionSession {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
        }
        compressionSession = nil
    }

    deinit {
        invalidate()
    }

    // MARK: - Private

    private func handleEncodedSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        let isKeyframe: Bool
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
           let first = attachments.first {
            isKeyframe = !(first[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
        } else {
            isKeyframe = true
        }

        var parameterSetsData: Data?
        if isKeyframe, let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
            parameterSetsData = extractParameterSets(from: formatDescription)
        }

        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )

        guard status == kCMBlockBufferNoErr, let dataPointer = dataPointer else { return }

        let nalData = Data(bytes: dataPointer, count: totalLength)
        delegate?.videoEncoder(self, didEncodeFrame: nalData, isKeyframe: isKeyframe, parameterSets: parameterSetsData)
    }

    private func extractParameterSets(from formatDescription: CMFormatDescription) -> Data? {
        var parameterSetCount = 0
        var status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
            formatDescription,
            parameterSetIndex: 0,
            parameterSetPointerOut: nil,
            parameterSetSizeOut: nil,
            parameterSetCountOut: &parameterSetCount,
            nalUnitHeaderLengthOut: nil
        )

        guard status == noErr, parameterSetCount > 0 else { return nil }

        // Serialize as: [UInt32-LE count][UInt32-LE len0][bytes0][UInt32-LE len1][bytes1]...
        // Uses explicit little-endian encoding to avoid alignment issues on decode.
        var data = Data()
        data.appendUInt32LE(UInt32(parameterSetCount))

        for i in 0..<parameterSetCount {
            var psPointer: UnsafePointer<UInt8>?
            var psSize = 0
            status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                formatDescription,
                parameterSetIndex: i,
                parameterSetPointerOut: &psPointer,
                parameterSetSizeOut: &psSize,
                parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: nil
            )
            guard status == noErr, let pointer = psPointer else { return nil }

            data.appendUInt32LE(UInt32(psSize))
            data.append(pointer, count: psSize)
        }

        return data
    }
}

enum VideoEncoderError: Error {
    case sessionCreationFailed(OSStatus)
}

// MARK: - Alignment-safe UInt32 serialization

extension Data {
    /// Append a UInt32 as 4 little-endian bytes (alignment-safe).
    mutating func appendUInt32LE(_ value: UInt32) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }

    /// Read a UInt32 from 4 little-endian bytes at the given offset (alignment-safe).
    func readUInt32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        var value: UInt32 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { dest in
            copyBytes(to: dest, from: offset..<(offset + 4))
        }
        return UInt32(littleEndian: value)
    }
}
