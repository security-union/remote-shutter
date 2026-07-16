//
//  CameraScreenView.swift
//  RemoteShutter
//
//  Copyright © 2026 Security Union LLC. All rights reserved.
//

import SwiftUI
import AVFoundation

// MARK: - Camera Screen (SwiftUI chrome)

/// The camera device's whole screen: full-bleed live preview under the
/// recording indicator, activity spinner, recording timer, and the
/// countdown/status/transfer overlay. Hosted by `CameraHostController`;
/// capture ownership and actor glue live on `CameraRig`.
struct CameraScreenView: View {
    @ObservedObject var viewModel: CameraViewModel
    /// Local device selection from the picker chrome (nil in previews/tests).
    var onSelectCameraDevice: ((String) -> Void)?
    /// The letterbox-fitted video rect (view coords), reported by the preview so
    /// the focus reticle lands on the image, not the black bars.
    @State private var videoRect: CGRect = .zero
    /// Whether the preview is horizontally mirrored (front camera, by default).
    /// The monitor's frame is never mirrored (the data output isn't), so the
    /// reticle's x is flipped to match what the camera operator actually sees.
    @State private var previewMirrored: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let session = viewModel.previewSession {
                CameraPreviewView(session: session,
                                  videoOrientation: viewModel.previewVideoOrientation,
                                  onGeometryChange: { rect, mirrored in
                                      videoRect = rect
                                      previewMirrored = mirrored
                                  })
                    .ignoresSafeArea()
            }

            // Remote focus reticle — the same box/animation the monitor draws,
            // positioned within the fitted video rect at the tapped point. x is
            // flipped when the preview is mirrored (front camera) so the box
            // lands on the same subject the monitor operator tapped.
            if let indicator = viewModel.focusIndicator, videoRect.width > 0 {
                let nx = previewMirrored ? (1 - indicator.normalized.x) : indicator.normalized.x
                FocusReticleView()
                    .id(indicator.id)
                    .position(x: videoRect.minX + nx * videoRect.width,
                              y: videoRect.minY + indicator.normalized.y * videoRect.height)
                    .allowsHitTesting(false)
            }

            // Animated "recording" badge, top center — visible only in video mode.
            VStack {
                if viewModel.isRecordingIndicatorVisible {
                    AnimatedImageView(image: UIImage.gifImageWithName("recording"))
                        .frame(width: 45, height: 45)
                        .padding(.top, 17)
                }
                Spacer()
            }
            .allowsHitTesting(false)

            // Local camera-device picker, top leading — a Mac has N cameras.
            if FeatureFlags.ENABLE_LOCAL_CAMERA_PICKER,
               viewModel.availableCameraDevices.count > 1 {
                VStack {
                    HStack {
                        cameraDevicePicker
                        Spacer()
                    }
                    Spacer()
                }
                .padding(.top, 17)
                .padding(.leading, 16)
            }

            if viewModel.isBusy {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.4) // visual parity with UIActivityIndicatorView .large
            }

            CameraRecordingTimerView(
                recordingStartTime: viewModel.recordingStartTime,
                isRecording: viewModel.isRecordingTimerActive)

            CameraProgressOverlayView(viewModel: viewModel)
        }
    }

    private var cameraDevicePicker: some View {
        Menu {
            ForEach(viewModel.availableCameraDevices, id: \.uniqueID) { device in
                CameraDeviceMenuItem(
                    name: device.localizedName,
                    isActive: device.uniqueID == viewModel.activeCameraDeviceID,
                    isSuspended: device.isSuspended,
                    select: { onSelectCameraDevice?(device.uniqueID) })
            }
        } label: {
            Image(systemName: "web.camera")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.4))
                .clipShape(Circle())
        }
    }
}

// MARK: - Live preview

/// Hosts an `AVCaptureVideoPreviewLayer` as the view's backing layer, so the
/// layer tracks the view's bounds through rotation and layout for free — no
/// manual frame gluing.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let videoOrientation: AVCaptureVideoOrientation
    /// Reports the letterbox-fitted video rect (view coords) and whether the
    /// preview is mirrored, whenever either changes, so overlays can position
    /// against the image (not the black bars) and account for front-camera mirror.
    var onGeometryChange: ((CGRect, Bool) -> Void)?

    final class PreviewHostView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }
        var onGeometryChange: ((CGRect, Bool) -> Void)?
        private var last: (rect: CGRect, mirrored: Bool) = (.zero, false)

        /// The rect the video image occupies under .resizeAspect (view coords)
        /// plus the connection's mirror state. Deferred off the layout pass to
        /// avoid mutating SwiftUI state mid-update. Called on layout and on
        /// updateUIView (a camera swap can flip mirroring without a resize).
        func reportGeometry() {
            let rect = previewLayer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
            let mirrored = previewLayer.connection?.isVideoMirrored ?? false
            guard rect.width > 0, rect.height > 0, (rect, mirrored) != last else { return }
            last = (rect, mirrored)
            let callback = onGeometryChange
            DispatchQueue.main.async { callback?(rect, mirrored) }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            reportGeometry()
        }
    }

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.previewLayer.videoGravity = .resizeAspect
        view.previewLayer.session = session
        view.onGeometryChange = onGeometryChange
        return view
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {
        uiView.onGeometryChange = onGeometryChange
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        defer { uiView.reportGeometry() }
        // Same policy as the capture connections (OrientationUtils): iOS
        // rotates the preview to the interface; Mac cameras render native.
        guard OrientationUtils.appliesInterfaceRotation,
              let connection = uiView.previewLayer.connection,
              connection.isVideoOrientationSupported,
              connection.videoOrientation != videoOrientation else { return }
        connection.videoOrientation = videoOrientation
    }
}

// MARK: - Animated GIF bridge

/// `SwiftUI.Image` cannot play a multi-frame `UIImage`; a `UIImageView` can.
private struct AnimatedImageView: UIViewRepresentable {
    let image: UIImage?

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        // Let the SwiftUI .frame() decide the size, not the image dimensions.
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {}
}

// MARK: - Preview

struct CameraScreenView_Previews: PreviewProvider {
    static var previews: some View {
        CameraScreenView(viewModel: {
            let model = CameraViewModel()
            model.isRecordingIndicatorVisible = true
            model.recordingStartTime = Date().addingTimeInterval(-42)
            model.isRecordingTimerActive = true
            return model
        }())
    }
}
