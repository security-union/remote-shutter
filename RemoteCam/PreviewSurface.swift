//
//  PreviewSurface.swift
//  RemoteShutter
//
//  The director's live-preview surface. A decoded frame goes straight to a
//  CoreAnimation layer: the HEVC decoder's 4:2:0 pixel buffer as-is to an
//  `AVSampleBufferDisplayLayer`, a still (JPEG/HEIC) or VP9 bitmap as a
//  `CALayer`'s contents. SwiftUI sees only the frame's pixel size.
//

import UIKit
import SwiftUI
import AVFoundation

/// One decoded preview frame, in the form the decoder produced it.
enum PreviewFrame {
    /// A video frame: the decoder's own 4:2:0 pixel buffer.
    case pixelBuffer(CVPixelBuffer)
    /// A still (JPEG/HEIC) or a VP9 bitmap.
    case image(UIImage)

    /// Pixel dimensions, upright as displayed.
    var pixelSize: CGSize {
        switch self {
        case .pixelBuffer(let buffer):
            return CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        case .image(let image):
            return image.size
        }
    }
}

/// Draws preview frames on CoreAnimation layers. Main thread only.
final class PreviewSurfaceView: UIView {

    private let videoLayer = AVSampleBufferDisplayLayer()
    private let stillLayer = CALayer()
    /// Reused across frames of the same dimensions and pixel format.
    private var formatDescription: CMVideoFormatDescription?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        videoLayer.videoGravity = .resizeAspect
        stillLayer.contentsGravity = .resizeAspect
        layer.addSublayer(videoLayer)
        layer.addSublayer(stillLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PreviewSurfaceView is built in code") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = bounds
        stillLayer.frame = bounds
        CATransaction.commit()
    }

    /// Shows a frame; nil clears the surface.
    func show(_ frame: PreviewFrame?) {
        switch frame {
        case .pixelBuffer(let buffer)?:
            if !stillLayer.isHidden { showStill(nil) }
            enqueue(buffer)
        case .image(let image)?:
            clearVideo()
            showStill(image)
        case nil:
            clearVideo()
            showStill(nil)
        }
    }

    private func showStill(_ image: UIImage?) {
        stillLayer.contents = image?.cgImage
        stillLayer.isHidden = image == nil
    }

    private func clearVideo() {
        guard !videoLayer.isHidden else { return }
        videoLayer.flushAndRemoveImage()
        videoLayer.isHidden = true
        formatDescription = nil
    }

    /// Wraps the buffer (no copy) in a sample buffer tagged "display now".
    private func enqueue(_ buffer: CVPixelBuffer) {
        videoLayer.isHidden = false
        if videoLayer.status == .failed || videoLayer.requiresFlushToResumeDecoding {
            videoLayer.flush()
        }
        if let current = formatDescription,
           !CMVideoFormatDescriptionMatchesImageBuffer(current, imageBuffer: buffer) {
            formatDescription = nil
        }
        if formatDescription == nil {
            var created: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &created)
            formatDescription = created
        }
        guard let formatDescription else { return }

        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescription: formatDescription,
            sampleTiming: &timing, sampleBufferOut: &sampleBuffer)
        guard status == noErr, let sampleBuffer,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
              CFArrayGetCount(attachments) > 0 else { return }
        let first = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(first,
                             Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                             Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        videoLayer.enqueue(sampleBuffer)
    }
}

/// The SwiftUI face of a lane's `FrameDisplayModel`: makes a surface and
/// attaches it to the model, which pushes frames to it directly. SwiftUI may
/// keep the view and hand it a different model (the focused viewfinder when
/// focus moves to another camera), so the coordinator tracks the attachment.
struct PreviewSurface: UIViewRepresentable {
    let frames: FrameDisplayModel

    final class Coordinator {
        weak var attachedTo: FrameDisplayModel?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PreviewSurfaceView {
        let view = PreviewSurfaceView()
        attach(view, context.coordinator)
        return view
    }

    func updateUIView(_ uiView: PreviewSurfaceView, context: Context) {
        attach(uiView, context.coordinator)
    }

    static func dismantleUIView(_ uiView: PreviewSurfaceView, coordinator: Coordinator) {
        coordinator.attachedTo?.detach(uiView)
        coordinator.attachedTo = nil
    }

    private func attach(_ view: PreviewSurfaceView, _ coordinator: Coordinator) {
        guard coordinator.attachedTo !== frames else { return }
        coordinator.attachedTo?.detach(view)
        frames.attach(view)
        coordinator.attachedTo = frames
    }
}
