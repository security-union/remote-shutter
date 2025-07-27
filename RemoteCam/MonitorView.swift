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
            
            // Recording indicator
            if viewModel.isRecording {
                VStack {
                    HStack {
                        Spacer()
                        recordingIndicator
                            .padding(.top, 20)
                            .padding(.trailing, 20)
                    }
                    Spacer()
                }
            }
            
            // Zoom controls overlay
            if viewModel.showZoomControls {
                VStack {
                    Spacer()
                    zoomControlsOverlay
                        .padding(.bottom, 100)
                }
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
                    let newZoom = max(1.0, min(viewModel.maxZoomFactor, viewModel.currentZoomFactor * value))
                    onZoomChange(newZoom)
                    viewModel.showZoomControlsTemporarily()
                }
        )
    }
    
    // MARK: - Recording Indicator
    private var recordingIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
                .scaleEffect(1.0)
                .animation(.easeInOut(duration: 1.0).repeatForever(), value: viewModel.isRecording)
            
            Text("REC")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.6))
        .cornerRadius(8)
    }
    
    // MARK: - Zoom Controls Overlay
    private var zoomControlsOverlay: some View {
        VStack(spacing: 12) {
            Text("\(String(format: "%.1f", viewModel.currentZoomFactor))x")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
            
            Slider(
                value: Binding(
                    get: { viewModel.currentZoomFactor },
                    set: { onZoomChange($0) }
                ),
                in: 1.0...viewModel.maxZoomFactor
            )
            .accentColor(.blue)
            .disabled(!viewModel.isZoomSliderEnabled)
            .frame(width: 200)
        }
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
             modeButton(title: "Shorts", mode: .Shorts)
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
        .disabled(!viewModel.isFlashButtonEnabled)
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