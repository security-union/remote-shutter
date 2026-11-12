//
//  PortraitPreviewBlur.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union. All rights reserved.
//

import Foundation
import Atomics
import AVFoundation
import CoreImage
import CoreVideo
import Metal
import UIKit

/// The live disparity stream from `CaptureEngine.depthPreviewOutput`. The
/// depth queue writes the newest map; the preview lane reads it. `stop()`
/// drops the map, and a frame delivered after it is ignored, so a stale map
/// is never used once Portrait ends.
final class LiveDepth: NSObject, AVCaptureDepthDataOutputDelegate, @unchecked Sendable {
    private let streaming = ManagedAtomic(false)
    private let latestDepth = Locked<AVDepthData?>(nil)
    private let deliveredCount = ManagedAtomic(0)

    /// Whether the depth output is attached. One atomic load: the check the
    /// preview makes on every frame outside Portrait.
    var isStreaming: Bool { streaming.load(ordering: .acquiring) }
    /// Depth maps delivered since launch, for the hardware probe.
    var delivered: Int { deliveredCount.load(ordering: .relaxed) }

    /// The newest map, or nil when the output is detached or none arrived yet.
    var latest: AVDepthData? {
        guard isStreaming else { return nil }
        return latestDepth.value
    }

    func start() {
        streaming.store(true, ordering: .releasing)
    }

    func stop() {
        streaming.store(false, ordering: .releasing)
        latestDepth.value = nil
    }

    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData,
                         timestamp: CMTime, connection: AVCaptureConnection) {
        // Checked under the lock `stop()` clears through, so a late map can
        // never land after the clear.
        latestDepth.mutate { latest in
            if streaming.load(ordering: .acquiring) { latest = depthData }
        }
        deliveredCount.wrappingIncrement(ordering: .relaxed)
    }
}

/// Blurs a streamed preview frame from live depth at the rig's aperture, so
/// the director frames Portrait shots with the effect. Pixels at the
/// subject's disparity stay sharp; the blur grows with the distance from it,
/// in front and behind, and with a wider aperture. The output has the input's
/// pixel format and size, so the encoders downstream see an ordinary frame.
/// Confined to the preview lane.
final class PortraitPreviewBlur {

    /// Blur radius at f/1.4 as a fraction of the frame's long edge. Smaller
    /// apertures scale it down by `1.4 / f`, so f/16 is about a pixel.
    static let maxRadiusFraction: Float = 0.02
    /// Relative disparity difference from the subject that still reads sharp.
    static let sharpBand: Float = 0.08
    /// How fast the blur ramps to full outside the sharp band.
    static let maskGain: Float = 4

    private let context: CIContext
    private var pool: CVPixelBufferPool?
    private var poolKey: (format: OSType, width: Int, height: Int)?
    private let framesCount = ManagedAtomic(0)
    private let nanosTotal = ManagedAtomic(0)

    /// Frames blurred and their summed render time, for the hardware probe.
    var framesBlurred: Int { framesCount.load(ordering: .relaxed) }
    var averageMillis: Double {
        let frames = framesBlurred
        return frames == 0 ? 0 : Double(nanosTotal.load(ordering: .relaxed)) / Double(frames) / 1_000_000
    }

    init() {
        let options: [CIContextOption: Any] = [.cacheIntermediates: false, .name: "portrait preview blur"]
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: options)
        } else {
            context = CIContext(options: options.merging([.useSoftwareRenderer: false]) { $1 })
        }
    }

    // MARK: - Pure decisions

    /// Blur radius in pixels for an f-number on a frame of `longEdge` pixels:
    /// inversely proportional to the f-number, as a lens's blur disc is.
    static func blurRadius(aperture: Float, longEdge: Int) -> Float {
        let fNumber = max(aperture, 0.1)
        return Float(longEdge) * maxRadiusFraction * (1.4 / fNumber)
    }

    /// The subject's disparity: the median of the finite, positive values in
    /// the middle third of the map (both axes), sampled every `stride` pixels.
    /// nil when that region holds no usable value. `values` is row-major,
    /// `rowStride` floats per row.
    static func focusDisparity(_ values: UnsafeBufferPointer<Float>, width: Int, height: Int,
                               rowStride: Int, stride step: Int = 2) -> Float? {
        guard width > 0, height > 0, rowStride >= width, values.count >= rowStride * (height - 1) + width else {
            return nil
        }
        var samples: [Float] = []
        samples.reserveCapacity((width / 3 / step + 1) * (height / 3 / step + 1))
        for row in Swift.stride(from: height / 3, to: max(height / 3 + 1, height * 2 / 3), by: step) {
            for column in Swift.stride(from: width / 3, to: max(width / 3 + 1, width * 2 / 3), by: step) {
                let value = values[row * rowStride + column]
                if value.isFinite && value > 0 { samples.append(value) }
            }
        }
        guard !samples.isEmpty else { return nil }
        samples.sort()
        return samples[samples.count / 2]
    }

    /// How a disparity map pinned to `.landscapeRight` must turn to match a
    /// frame delivered at `orientation` from a camera at `position`. Front
    /// cameras face the other way, so their portrait turns are reversed.
    static func depthOrientation(for orientation: AVCaptureVideoOrientation,
                                 position: AVCaptureDevice.Position) -> CGImagePropertyOrientation {
        guard OrientationUtils.appliesInterfaceRotation else { return .up }
        let front = position == .front
        switch orientation {
        case .landscapeRight: return .up
        case .landscapeLeft: return .down
        case .portrait: return front ? .left : .right
        case .portraitUpsideDown: return front ? .right : .left
        @unknown default: return .up
        }
    }

    // MARK: - Rendering

    /// A blurred copy of `pixelBuffer`, or `pixelBuffer` itself when there is
    /// no disparity or the render fails.
    func blurred(_ pixelBuffer: CVPixelBuffer, disparity: AVDepthData?, aperture: Float,
                 orientation: CGImagePropertyOrientation = .up) -> CVPixelBuffer {
        guard let disparity else { return pixelBuffer }
        let map = disparity.depthDataType == kCVPixelFormatType_DisparityFloat32
            ? disparity : disparity.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
        return blurred(pixelBuffer, disparityMap: map.depthDataMap, aperture: aperture, orientation: orientation)
    }

    /// The core: `disparityMap` is a one-component Float32 buffer
    /// (`kCVPixelFormatType_DisparityFloat32`) in sensor orientation.
    func blurred(_ pixelBuffer: CVPixelBuffer, disparityMap: CVPixelBuffer, aperture: Float,
                 orientation: CGImagePropertyOrientation = .up) -> CVPixelBuffer {
        let started = DispatchTime.now().uptimeNanoseconds
        guard let focus = Self.focusDisparity(of: disparityMap, orientation: orientation),
              let output = makeOutputBuffer(like: pixelBuffer) else { return pixelBuffer }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let extent = CGRect(x: 0, y: 0, width: width, height: height)
        let frame = CIImage(cvPixelBuffer: pixelBuffer)
        let mask = Self.mask(disparityMap, focus: focus, orientation: orientation, size: extent.size)
        let radius = Self.blurRadius(aperture: aperture, longEdge: max(width, height))
        let blurred = frame.clampedToExtent()
            .applyingFilter("CIMaskedVariableBlur", parameters: [
                "inputMask": mask,
                kCIInputRadiusKey: radius
            ])
            .cropped(to: extent)

        CVBufferPropagateAttachments(pixelBuffer, output)
        let colorSpace = frame.colorSpace ?? CGColorSpace(name: CGColorSpace.itur_709)
        context.render(blurred, to: output, bounds: extent, colorSpace: colorSpace)

        framesCount.wrappingIncrement(ordering: .relaxed)
        nanosTotal.wrappingIncrement(by: Int(DispatchTime.now().uptimeNanoseconds - started), ordering: .relaxed)
        return output
    }

    /// The focus disparity of the map as the viewer sees it: the middle third
    /// is the same region in any orientation, so the map is read unturned.
    private static func focusDisparity(of map: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> Float? {
        guard CVPixelBufferGetPixelFormatType(map) == kCVPixelFormatType_DisparityFloat32 else { return nil }
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let width = CVPixelBufferGetWidth(map)
        let height = CVPixelBufferGetHeight(map)
        let rowStride = CVPixelBufferGetBytesPerRow(map) / MemoryLayout<Float>.stride
        let values = UnsafeBufferPointer(start: base.assumingMemoryBound(to: Float.self),
                                         count: rowStride * height)
        return focusDisparity(values, width: width, height: height, rowStride: rowStride)
    }

    /// 0 where the disparity is within `sharpBand` of the subject's, ramping
    /// to 1 in front and behind; turned and scaled onto the frame.
    private static func mask(_ map: CVPixelBuffer, focus: Float, orientation: CGImagePropertyOrientation,
                             size: CGSize) -> CIImage {
        // Raw values, no color management: the mask is a number, not a color.
        let oriented = CIImage(cvPixelBuffer: map, options: [.colorSpace: NSNull()]).oriented(orientation)
        let disparity = oriented.transformed(by: CGAffineTransform(
            translationX: -oriented.extent.minX, y: -oriented.extent.minY))
        let scaled = disparity.transformed(by: CGAffineTransform(
            scaleX: size.width / disparity.extent.width, y: size.height / disparity.extent.height))

        // behind = gain * (1 - band - d/f), in front = gain * (d/f - 1 - band)
        let slope = CGFloat(maskGain / focus)
        let behind = ramp(scaled, scale: -slope, bias: CGFloat(maskGain * (1 - sharpBand)))
        let inFront = ramp(scaled, scale: slope, bias: CGFloat(-maskGain * (1 + sharpBand)))
        return behind.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: inFront])
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    /// `clamp(scale * d + bias, 0, 1)` on every color channel, alpha 1.
    private static func ramp(_ image: CIImage, scale: CGFloat, bias: CGFloat) -> CIImage {
        let fromDisparity = CIVector(x: scale, y: 0, z: 0, w: 0)
        return image
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": fromDisparity, "inputGVector": fromDisparity, "inputBVector": fromDisparity,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 1)
            ])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])
    }

    /// A buffer from a pool matching the input's pixel format and size;
    /// the pool is rebuilt when either changes.
    private func makeOutputBuffer(like input: CVPixelBuffer) -> CVPixelBuffer? {
        let format = CVPixelBufferGetPixelFormatType(input)
        let width = CVPixelBufferGetWidth(input)
        let height = CVPixelBufferGetHeight(input)
        if poolKey.map({ $0.format != format || $0.width != width || $0.height != height }) ?? true {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(format),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            var created: CVPixelBufferPool?
            CVPixelBufferPoolCreate(kCFAllocatorDefault,
                                    [kCVPixelBufferPoolMinimumBufferCountKey as String: 3] as CFDictionary,
                                    attributes as CFDictionary, &created)
            pool = created
            poolKey = (format, width, height)
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        return buffer
    }
}
