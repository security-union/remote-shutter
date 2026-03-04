import Foundation
import VideoToolbox
import CoreMedia
import CoreImage

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

protocol VideoDecoderDelegate: AnyObject {
    #if canImport(UIKit)
    func videoDecoder(_ decoder: VideoDecoder, didDecodeFrame image: UIImage)
    #elseif canImport(AppKit)
    func videoDecoder(_ decoder: VideoDecoder, didDecodeFrame image: NSImage)
    #endif
    func videoDecoderNeedsKeyframe(_ decoder: VideoDecoder)
}

final class VideoDecoder {
    weak var delegate: VideoDecoderDelegate?

    private var decompressionSession: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    private let ciContext: CIContext

    init() {
        self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
    }

    func decode(frameData: Data, isKeyframe: Bool, parameterSets: Data?) {
        if isKeyframe, let parameterSets = parameterSets {
            if !setupDecoder(from: parameterSets) {
                delegate?.videoDecoderNeedsKeyframe(self)
                return
            }
        }

        guard let session = decompressionSession, let formatDesc = formatDescription else {
            delegate?.videoDecoderNeedsKeyframe(self)
            return
        }

        guard let sampleBuffer = createSampleBuffer(from: frameData, formatDescription: formatDesc) else {
            return
        }

        var infoFlags = VTDecodeInfoFlags()
        var outputImage: CGImage?

        VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: [._1xRealTimePlayback],
            infoFlagsOut: &infoFlags
        ) { [weak self] status, _, imageBuffer, _, _ in
            guard status == noErr, let imageBuffer = imageBuffer, let self = self else { return }
            let ciImage = CIImage(cvPixelBuffer: imageBuffer)
            if let cgImage = self.ciContext.createCGImage(ciImage, from: ciImage.extent) {
                outputImage = cgImage
            }
        }

        if let cgImage = outputImage {
            #if canImport(UIKit)
            let image = UIImage(cgImage: cgImage)
            #elseif canImport(AppKit)
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            #endif
            delegate?.videoDecoder(self, didDecodeFrame: image)
        }
    }

    func invalidate() {
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
        }
        decompressionSession = nil
        formatDescription = nil
    }

    deinit {
        invalidate()
    }

    // MARK: - Private

    private func setupDecoder(from parameterSetsData: Data) -> Bool {
        let paramSets = parseParameterSets(parameterSetsData)
        guard paramSets.count >= 3 else { return false }

        let newFormatDesc = createFormatDescription(from: paramSets)
        guard let newFormatDesc = newFormatDesc else { return false }

        // Check if existing session can accept the new format
        if let existingSession = decompressionSession {
            if VTDecompressionSessionCanAcceptFormatDescription(existingSession, formatDescription: newFormatDesc) {
                formatDescription = newFormatDesc
                return true
            }
            VTDecompressionSessionInvalidate(existingSession)
            decompressionSession = nil
        }

        formatDescription = newFormatDesc

        let destAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]

        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: newFormatDesc,
            decoderSpecification: nil,
            imageBufferAttributes: destAttributes as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &session
        )

        guard status == noErr, let session = session else { return false }

        VTSessionSetProperty(session, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        decompressionSession = session
        return true
    }

    /// Parse parameter sets from encoded format: [UInt32-LE count][UInt32-LE len][bytes]...
    /// Uses alignment-safe reads (readUInt32LE) to avoid EXC_BAD_ACCESS on unaligned Data.
    private func parseParameterSets(_ data: Data) -> [Data] {
        var offset = 0
        let uint32Size = 4

        guard data.count >= uint32Size else { return [] }

        let count = data.readUInt32LE(at: offset)
        offset += uint32Size

        var sets: [Data] = []
        for _ in 0..<count {
            guard offset + uint32Size <= data.count else { return [] }
            let size = data.readUInt32LE(at: offset)
            offset += uint32Size

            guard offset + Int(size) <= data.count else { return [] }
            sets.append(data.subdata(in: offset..<(offset + Int(size))))
            offset += Int(size)
        }

        return sets
    }

    private func createFormatDescription(from paramSets: [Data]) -> CMVideoFormatDescription? {
        // HEVC requires VPS(0), SPS(1), PPS(2)
        return paramSets[0].withUnsafeBytes { vpsBuffer in
            paramSets[1].withUnsafeBytes { spsBuffer in
                paramSets[2].withUnsafeBytes { ppsBuffer in
                    var pointers: [UnsafePointer<UInt8>] = [
                        vpsBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        spsBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        ppsBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
                    ]
                    var sizes: [Int] = [paramSets[0].count, paramSets[1].count, paramSets[2].count]

                    var desc: CMVideoFormatDescription?
                    let status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                        allocator: kCFAllocatorDefault,
                        parameterSetCount: 3,
                        parameterSetPointers: &pointers,
                        parameterSetSizes: &sizes,
                        nalUnitHeaderLength: 4,
                        extensions: nil,
                        formatDescriptionOut: &desc
                    )

                    return status == noErr ? desc : nil
                }
            }
        }
    }

    private func createSampleBuffer(from data: Data, formatDescription: CMVideoFormatDescription) -> CMSampleBuffer? {
        var blockBuffer: CMBlockBuffer?

        // Create block buffer and copy data into it
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: data.count,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: kCMBlockBufferAssureMemoryNowFlag,
            blockBufferOut: &blockBuffer
        )

        guard status == kCMBlockBufferNoErr, let blockBuffer = blockBuffer else { return nil }

        data.withUnsafeBytes { rawBuffer in
            CMBlockBufferReplaceDataBytes(
                with: rawBuffer.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: data.count
            )
        }

        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )

        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        return status == noErr ? sampleBuffer : nil
    }
}
