import SwiftUI
import UIKit
import Combine

// MARK: - Monitor View
struct MonitorView: View {
    @ObservedObject var viewModel: MonitorViewModel
    
    // Callbacks to MonitorViewController for Actor integration
    let onTakePicture: () -> Void
    let onToggleCamera: () -> Void
    let onToggleFlash: () -> Void
    let onToggleTorch: () -> Void
    let onTimerChange: (Int) -> Void
    let onModeChange: (RecordingMode) -> Void
    let onBackTapped: () -> Void
    let onGalleryTapped: () -> Void
    let onSettingsTapped: () -> Void
    let onZoomChange: (CGFloat) -> Void
    let onLensChange: (CameraLensType) -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // MARK: - Camera Preview
                    cameraPreviewSection
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // MARK: - Controls Section
                    controlsSection
                        .background(Color.black.opacity(0.8))
                }
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden()
    }
    
    // MARK: - Camera Preview Section
    private var cameraPreviewSection: some View {
        ZStack {
            // Camera preview background
            Color.black
            
            // Camera image
            if let image = viewModel.cameraImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipped()
            } else {
                // Placeholder
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "camera")
                            .font(.system(size: 50))
                            .foregroundColor(.white.opacity(0.5))
                    )
            }
            
            // Recording indicator with duration timer
            if viewModel.isShowingRecordingDuration {
                VStack {
                    HStack {
                        Spacer()
                        RecordingTimer(
                            startTime: viewModel.recordingStartTime,
                            isRecording: viewModel.isRecording
                        )
                        .padding(.top, 20)
                        .padding(.trailing, 20)
                    }
                    Spacer()
                }
            }
            
            // Zoom controls overlay - positioned at top for right-handed accessibility
            if viewModel.showZoomControls {
                VStack {
                    zoomControlsOverlay
                        .padding(.top, 50) // Below status bar
                    Spacer()
                }
            }
            
            // Video transfer progress overlay - positioned at center
            if viewModel.isVideoTransferring {
                VideoTransferProgressView(
                    progress: viewModel.videoTransferProgress,
                    transferSizeText: viewModel.videoTransferSizeText,
                    transferSpeedText: viewModel.videoTransferSpeedText,
                    isVisible: viewModel.isVideoTransferring
                )
            }
            
            // Flash status overlay
            if !viewModel.flashStatus.isEmpty && viewModel.uiState == .photoMode {
                VStack {
                    HStack {
                        Text(viewModel.flashStatus)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(8)
                            .padding(.leading, 20)
                            .padding(.top, 20)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .onTapGesture(count: 2) {
            // Double tap to toggle camera
            onToggleCamera()
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    // Apply sensitivity multiplier to make zoom less sensitive
                    let sensitivity: CGFloat = 0.5 // Reduce sensitivity by half
                    let zoomChange = (value - 1.0) * sensitivity + 1.0
                    let newZoom = max(1.0, min(viewModel.maxZoomFactor, viewModel.currentZoomFactor * zoomChange))
                    onZoomChange(newZoom)
                    viewModel.showZoomControlsTemporarily()
                }
        )
    }
    
    // MARK: - Recording Indicator
    // Note: Replaced with RecordingTimer component that includes duration
    
    // MARK: - Zoom Controls Overlay
    private var zoomControlsOverlay: some View {
        VStack(spacing: 10) {
            // Current zoom level - prominent display
            Text("\(String(format: "%.1f", viewModel.currentZoomFactor))×")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .tracking(0.5)
            
            // Progress bar with refined styling
            HStack(spacing: 8) {
                // Start label
                Text("1×")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                
                // Enhanced progress bar
                ZStack(alignment: .leading) {
                    // Background track with subtle gradient
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.25)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 140, height: 8)
                    
                    // Progress fill with beautiful gradient
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.0, green: 0.48, blue: 1.0), // iOS blue
                                    Color(red: 0.0, green: 0.68, blue: 1.0)  // Lighter blue
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: CGFloat(140 * Double((viewModel.currentZoomFactor - 1.0) / (viewModel.maxZoomFactor - 1.0))), 
                            height: 8
                        )
                        .shadow(color: Color.blue.opacity(0.3), radius: 2, x: 0, y: 1)
                }
                
                // End label
                Text("\(String(format: "%.0f", viewModel.maxZoomFactor))×")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            // Premium glassmorphism card background
            ZStack {
                // Backdrop blur effect with proper clipping
                Color.black.opacity(0.3)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                
                // Subtle border highlight
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.4),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            }
        )
        .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 4)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    // MARK: - Controls Section
    private var controlsSection: some View {
        VStack(spacing: 20) {
            // Mode Selector
            modeSelector
            
            // Timer Controls (only for Photo/Video modes)
            if viewModel.uiState != .shortsMode {
                timerControls
            }
            
            // Lens Controls
            if viewModel.availableLensTypes.count > 1 {
                lensControls
            }
            
            // Main Action Buttons
            mainActionButtons
            
            // Bottom Navigation
            bottomNavigation
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    // MARK: - Mode Selector
    private var modeSelector: some View {
        HStack(spacing: 0) {
            modeButton(title: "Photo", mode: .Photo)
            modeButton(title: "Video", mode: .Video)
            
            // Shorts mode - feature flagged
            if FeatureFlags.ENABLE_SHORTS_MODE {
                modeButton(title: "Shorts", mode: .Shorts)
            }
        }
        .background(Color.gray.opacity(0.2))
        .cornerRadius(8)
        .disabled(!viewModel.isSegmentedControlEnabled)
    }
    
    private func modeButton(title: String, mode: RecordingMode) -> some View {
        Button(action: {
            onModeChange(mode)
        }) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(viewModel.currentMode == mode ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    viewModel.currentMode == mode ? 
                    Color.blue : Color.clear
                )
                .cornerRadius(6)
        }
    }
    
    // MARK: - Timer Controls
    private var timerControls: some View {
        HStack(spacing: 16) {
            Text("Timer:")
                .font(.system(size: 16))
                .foregroundColor(.white)
            
            Slider(
                value: Binding(
                    get: { viewModel.timerSliderValue },
                    set: { newValue in
                        viewModel.timerSliderValue = newValue
                        onTimerChange(Int(newValue))
                    }
                ),
                in: 0...viewModel.maxTimerValue,
                step: 1
            )
            .accentColor(.blue)
            .disabled(!viewModel.isTimerSliderEnabled)
            
            Text("\(Int(viewModel.timerSliderValue))s")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 30)
        }
    }
    
    // MARK: - Lens Controls
    private var lensControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.availableLensTypes, id: \.self) { lensType in
                    lensButton(for: lensType)
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private func lensButton(for lensType: CameraLensType) -> some View {
        Button(action: {
            onLensChange(lensType)
        }) {
            Text(lensType.displayName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(viewModel.currentLensType == lensType ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    viewModel.currentLensType == lensType ? 
                    Color.blue : Color.gray.opacity(0.3)
                )
                .cornerRadius(6)
        }
        .disabled(!viewModel.isLensControlEnabled)
    }
    
    // MARK: - Main Action Buttons
    private var mainActionButtons: some View {
        HStack(spacing: 40) {
            // Gallery Button
            actionButton(
                systemImage: "photo.on.rectangle",
                action: onGalleryTapped,
                isEnabled: viewModel.isGalleryEnabled
            )
            
            // Main Action Button (Take Photo/Record Video)
            mainActionButton
            
            // Toggle Camera Button
            actionButton(
                systemImage: "arrow.triangle.2.circlepath.camera",
                action: onToggleCamera,
                isEnabled: viewModel.isToggleCameraEnabled
            )
        }
    }
    
    private var mainActionButton: some View {
        Button(action: onTakePicture) {
            ZStack {
                // Outer border (always white)
                Circle()
                    .fill(Color.white)
                    .frame(width: 80, height: 80)
                
                // Main button styling based on mode and recording state
                if viewModel.isRecording {
                    // Recording: Red background with white stop square
                    Circle()
                        .fill(Color.red)
                        .frame(width: 70, height: 70)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white)
                        .frame(width: 22, height: 22)
                } else if viewModel.uiState == .videoMode || viewModel.uiState == .shortsMode {
                    // Video mode (not recording): Red circle ready to record
                    Circle()
                        .fill(Color.red)
                        .frame(width: 70, height: 70)
                } else {
                    // Photo mode: White with black inner border
                    Circle()
                        .stroke(Color.black, lineWidth: 3)
                        .frame(width: 65, height: 65)
                }
                
                // Show countdown number if timer is active
                if viewModel.timerValue > 0 {
                    Text("\(viewModel.timerValue)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(viewModel.uiState == .photoMode ? .black : .white)
                }
            }
        }
        .disabled(!viewModel.isSegmentedControlEnabled && !viewModel.isRecording)
    }
    
    private func actionButton(systemImage: String, action: @escaping () -> Void, isEnabled: Bool) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 24))
                .foregroundColor(isEnabled ? .white : .gray)
                .frame(width: 44, height: 44)
        }
        .disabled(!isEnabled)
    }
    
    // MARK: - Bottom Navigation
    private var bottomNavigation: some View {
        HStack {
            // Back Button
            Button(action: onBackTapped) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }
            .disabled(!viewModel.isBackEnabled)
            
            Spacer()
            
            // Flash/Torch Controls (context-dependent)
            if viewModel.uiState == .photoMode {
                // Show both flash and torch for photo mode
                HStack(spacing: 20) {
                    flashButton
                    torchButton
                }
            } else if viewModel.uiState == .videoMode || viewModel.uiState == .shortsMode {
                torchButton
            }
            
            Spacer()
            
            // Settings Button
            Button(action: onSettingsTapped) {
                Image(systemName: "gearshape")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
            }
            .disabled(!viewModel.isSettingsEnabled)
        }
    }
    
    private var flashButton: some View {
        Button(action: onToggleFlash) {
            Image(systemName: viewModel.isFlashEnabled ? "bolt.fill" : "bolt.slash")
                .font(.system(size: 20))
                .foregroundColor(viewModel.isFlashEnabled ? .yellow : .white)
        }
        .disabled(!viewModel.isFlashButtonEnabled)
    }
    
    private var torchButton: some View {
        Button(action: onToggleTorch) {
            Image(systemName: viewModel.isTorchEnabled ? "flashlight.on.fill" : "flashlight.off.fill")
                .font(.system(size: 20))
                .foregroundColor(viewModel.isTorchEnabled ? .yellow : .white)
        }
        .disabled(!viewModel.isTorchButtonEnabled)
    }
}

// MARK: - Preview
struct MonitorView_Previews: PreviewProvider {
    static var previews: some View {
        MonitorView(
            viewModel: MonitorViewModel(),
            onTakePicture: {},
            onToggleCamera: {},
            onToggleFlash: {},
            onToggleTorch: {},
            onTimerChange: { _ in },
            onModeChange: { _ in },
            onBackTapped: {},
            onGalleryTapped: {},
            onSettingsTapped: {},
            onZoomChange: { _ in },
            onLensChange: { _ in }
        )
        .preferredColorScheme(.dark)
    }
} 