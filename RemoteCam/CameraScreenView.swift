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
    /// Sets the local preview mode (standby button / tap-to-restore). Routed
    /// through the session so the change persists and the monitor is told.
    var onSetPreviewMode: ((CameraPreviewMode) -> Void)?
    /// The on-camera stop, available whenever a recording is running
    /// (nil in previews/tests).
    var onStopRecordingLocally: (() -> Void)?
    /// The letterbox-fitted video rect (view coords), reported by the preview so
    /// the focus reticle lands on the image, not the black bars.
    @State private var videoRect: CGRect = .zero
    /// Whether the preview is horizontally mirrored (front camera, by default).
    /// The monitor's frame is never mirrored (the data output isn't), so the
    /// reticle's x is flipped to match what the camera operator actually sees.
    @State private var previewMirrored: Bool = false
    /// Peer-link state; the reconnect overlay is a function of it.
    @ObservedObject var peerLink: PeerLinkStatus = .shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Always mounted: it owns CameraPreviewView, whose backing layer is
            // the AVCaptureVideoPreviewLayer on the live session. Unmounting it
            // stops frame delivery — standby covers the preview, never unmounts it.
            liveContent

            if viewModel.previewMode == .standby {
                CameraStandbyView(viewModel: viewModel,
                                  onRestore: { onSetPreviewMode?(.on) })
            }
        }
    }

    /// The full-screen live preview and its chrome.
    private var liveContent: some View {
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
                    // The reticle overlays the preview so it shares the preview
                    // layer's full-screen coordinate space — `videoRect` is in
                    // those coords, so positioning here has no safe-area offset.
                    .overlay(focusReticleOverlay)
            }

            // Pro-controls chip, top edge: the remote is driving exposure or
            // Cinematic; the person at the camera should see what it's set to.
            if let readout = viewModel.proReadout {
                VStack {
                    Text(readout)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .padding(.top, 54)
                    Spacer()
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            // Animated "recording" badge, top center — visible only in video mode.
            VStack {
                if viewModel.isRecordingIndicatorVisible {
                    AnimatedImageView(image: UIImage.gifImageWithName("recording"))
                        .frame(width: 45, height: 45)
                        .padding(.top, 17)
                }
                // Passive status chip, not a modal: the recording continues
                // through the drop, so nothing may cover the shot or demand
                // a decision.
                if viewModel.isAwaitingRemoteReconnect {
                    reconnectingChip
                }
                Spacer()
            }
            .allowsHitTesting(false)

            #if DEBUG
            SessionDebugOverlay()
            #endif

            // The operator can always stop a recording from the camera —
            // bottom center, where a shutter belongs. The remote observes
            // the resulting state change through the camera's report.
            if viewModel.isRecordingIndicatorVisible {
                VStack {
                    Spacer()
                    localStopButton
                        .padding(.bottom, 40)
                }
            }

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

            // Standby toggle, top trailing (the device picker owns top leading).
            VStack {
                HStack {
                    Spacer()
                    standbyButton
                }
                Spacer()
            }
            .padding(.top, 17)
            .padding(.trailing, 16)

            PeerLinkOverlay(status: peerLink)
        }
    }

    private var reconnectingChip: some View {
        HStack(spacing: 6) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(0.7)
            Text(NSLocalizedString("reconnecting_to_remote", comment: "camera lost its remote mid-recording"))
                .font(.footnote)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.55))
        .clipShape(Capsule())
        .padding(.top, 8)
    }

    private var localStopButton: some View {
        Button(action: { onStopRecordingLocally?() }) {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: 68, height: 68)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.red)
                    .frame(width: 30, height: 30)
            }
        }
        .accessibilityLabel(Text(NSLocalizedString("stop_recording_button", comment: "on-camera stop while the remote is away")))
    }

    /// Puts the camera into standby (stops the local preview only). Frames keep
    /// streaming to the monitor.
    private var standbyButton: some View {
        Button(action: { onSetPreviewMode?(.standby) }) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 20))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.4))
                .clipShape(Circle())
        }
        .accessibilityLabel(Text(NSLocalizedString("Turn off preview", comment: "camera standby")))
    }

    /// The remote focus reticle — the same box/animation the monitor draws. The
    /// tapped point is normalized in the displayed image; we recompute the fitted
    /// (letterboxed) video rect inside a GeometryReader measuring THIS overlay's
    /// own space, using only the video's aspect ratio (which is coordinate-space
    /// invariant). That avoids any safe-area/coordinate offset between the preview
    /// layer and SwiftUI. x is flipped when the preview is mirrored (front camera).
    @ViewBuilder
    private var focusReticleOverlay: some View {
        if let indicator = viewModel.focusIndicator, videoRect.width > 0, videoRect.height > 0 {
            let aspect = videoRect.width / videoRect.height
            GeometryReader { geo in
                let fitted = Self.fittedRect(aspect: aspect, in: geo.size)
                let nx = previewMirrored ? (1 - indicator.normalized.x) : indicator.normalized.x
                FocusReticleView()
                    .id(indicator.id)
                    .position(x: fitted.minX + nx * fitted.width,
                              y: fitted.minY + indicator.normalized.y * fitted.height)
            }
            .allowsHitTesting(false)
        }
    }

    /// The rect an `aspect` (width/height) image occupies when aspect-fit into
    /// `size` — matches the preview layer's `.resizeAspect` letterboxing.
    static func fittedRect(aspect: CGFloat, in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0, aspect > 0 else { return .zero }
        let viewAspect = size.width / size.height
        let w: CGFloat
        let h: CGFloat
        if aspect > viewAspect {
            w = size.width
            h = size.width / aspect
        } else {
            h = size.height
            w = size.height * aspect
        }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
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

// MARK: - Standby screen

/// The minimal status screen shown on the camera device while preview is in
/// standby. It deliberately draws almost nothing — the whole point is to stop
/// compositing the ~30fps preview to save battery and heat. The capture session
/// and the frames streamed to the monitor keep running; only this display is
/// idle. Tapping anywhere restores the live preview.
struct CameraStandbyView: View {
    @ObservedObject var viewModel: CameraViewModel
    let onRestore: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.white.opacity(0.55))

                Text(NSLocalizedString("Preview off", comment: "camera standby title"))
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)

                // Recording indicator + elapsed time (only while recording).
                if viewModel.isRecordingTimerActive {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                        CameraRecordingTimerView(
                            recordingStartTime: viewModel.recordingStartTime,
                            isRecording: viewModel.isRecordingTimerActive)
                    }
                }

                // Current mode + quality, so the operator knows what's armed.
                Text("\(modeLabel) · \(viewModel.qualityInfo)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))

                // Who is driving the camera.
                if let peer = viewModel.connectedPeerName, !peer.isEmpty {
                    Text(String(format: NSLocalizedString("Controlled by %@", comment: "standby peer name"), peer))
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.5))
                }

                Text(NSLocalizedString("Tap to restore preview", comment: "camera standby hint"))
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.top, 8)
            }
            .multilineTextAlignment(.center)
            .padding(28)
        }
        .contentShape(Rectangle())
        .onTapGesture { onRestore() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(NSLocalizedString("Restore preview", comment: "camera standby restore")))
    }

    private var modeLabel: String {
        switch viewModel.currentMode {
        case .Photo: return NSLocalizedString("Photo", comment: "capture mode")
        case .Video: return NSLocalizedString("Video", comment: "capture mode")
        case .Shorts: return NSLocalizedString("Shorts", comment: "capture mode")
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
