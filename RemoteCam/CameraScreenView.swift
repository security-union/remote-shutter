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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let session = viewModel.previewSession {
                CameraPreviewView(session: session,
                                  videoOrientation: viewModel.previewVideoOrientation)
                    .ignoresSafeArea()
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

    final class PreviewHostView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }
    }

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.previewLayer.videoGravity = .resizeAspect
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
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
