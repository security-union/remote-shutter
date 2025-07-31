//
//  ShortsMonitorView.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 2025.
//  Copyright © 2025 Security Union. All rights reserved.
//

import SwiftUI
import UIKit
import Combine

// MARK: - Shorts Monitor View (Remote-Side Primary Interface)
struct ShortsMonitorView: View {
    @ObservedObject var viewModel: MonitorViewModel
    
    // Callbacks to MonitorViewController for Actor integration
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onToggleCamera: () -> Void
    let onToggleFlash: () -> Void
    let onToggleTorch: () -> Void
    let onFinalize: () -> Void
    let onExitShorts: () -> Void
    let onDeleteClip: (UUID) -> Void
    let onPreviewClip: (ShortsClip) -> Void
    let onConfigurationChange: (ShortsConfig) -> Void
    
    @State private var recordingDuration: TimeInterval = 0
    @State private var recordingTimer: Timer?
    
    // Use viewModel.isRecording instead of local state
    
    init(
        viewModel: MonitorViewModel,
        onStartRecording: @escaping () -> Void,
        onStopRecording: @escaping () -> Void,
        onToggleCamera: @escaping () -> Void,
        onToggleFlash: @escaping () -> Void,
        onToggleTorch: @escaping () -> Void,
        onFinalize: @escaping () -> Void,
        onExitShorts: @escaping () -> Void,
        onDeleteClip: @escaping (UUID) -> Void,
        onPreviewClip: @escaping (ShortsClip) -> Void,
        onConfigurationChange: @escaping (ShortsConfig) -> Void
    ) {
        self.viewModel = viewModel
        self.onStartRecording = onStartRecording
        self.onStopRecording = onStopRecording
        self.onToggleCamera = onToggleCamera
        self.onToggleFlash = onToggleFlash
        self.onToggleTorch = onToggleTorch
        self.onFinalize = onFinalize
        self.onExitShorts = onExitShorts
        self.onDeleteClip = onDeleteClip
        self.onPreviewClip = onPreviewClip
        self.onConfigurationChange = onConfigurationChange
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // MARK: - Duration Selection & Status
                    headerSection
                        .padding(.top, 20)
                    
                    // MARK: - Camera Preview
                    cameraPreviewSection
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // MARK: - Recording Controls
                    recordingControlsSection
                        .padding(.vertical, 20)
                    
                    // MARK: - Clips Timeline
                    timelineSection
                        .frame(height: 120)
                    
                    // MARK: - Action Buttons
                    actionButtonsSection
                        .padding(.bottom, 20)
                }
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden()
        .onDisappear {
            stopRecordingTimer()
        }
        .onChange(of: viewModel.isRecording) { isRecording in
            if isRecording {
                startRecordingTimer()
            } else {
                stopRecordingTimer()
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Duration Selection Chips
            HStack(spacing: 8) {
                durationChip(config: .fifteenSeconds, title: "15s")
                durationChip(config: .thirtySeconds, title: "30s") 
                durationChip(config: .oneMinute, title: "1min")
            }
            
            // Duration Progress
            if let session = viewModel.shortsSession {
                VStack(spacing: 4) {
                    Text("\(Int(session.totalDuration))s / \(Int(session.config.maxDuration))s used")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    
                    ProgressView(value: session.totalDuration, total: session.config.maxDuration)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        .scaleEffect(y: 2)
                }
                .padding(.horizontal, 40)
            }
        }
        .padding(.horizontal, 20)
    }
    
    private func durationChip(config: ShortsConfig, title: String) -> some View {
        Button(action: {
            if viewModel.selectedShortsConfig != config {
                viewModel.selectedShortsConfig = config
                onConfigurationChange(config)
            }
        }) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(viewModel.selectedShortsConfig == config ? .black : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    viewModel.selectedShortsConfig == config ? 
                    Color.blue : Color.gray.opacity(0.3)
                )
                .cornerRadius(20)
        }
    }
    
    // MARK: - Camera Preview Section
    private var cameraPreviewSection: some View {
        ZStack {
            // Camera preview background
            Color.gray.opacity(0.3)
            
            // Camera image from Remote
            if let image = viewModel.cameraImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipped()
            } else {
                VStack {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.6))
                    Text("Connecting to camera...")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            
            // Recording Indicator  
            if viewModel.isRecording {
                VStack {
                    HStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                            .opacity(0.8)
                        
                        Text("REC \(formatDuration(recordingDuration))")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.red)
                        
                        Spacer()
                    }
                    .padding(.top, 20)
                    .padding(.leading, 20)
                    
                    Spacer()
                }
            }
            
            // Camera Controls Overlay
            VStack {
                Spacer()
                
                HStack {
                    // Toggle Camera
                    controlButton(systemName: "camera.rotate", action: onToggleCamera)
                    
                    Spacer()
                    
                    // Flash
                    controlButton(
                        systemName: viewModel.isFlashEnabled ? "bolt.fill" : "bolt.slash.fill", 
                        action: onToggleFlash
                    )
                    
                    // Torch
                    controlButton(
                        systemName: viewModel.isTorchEnabled ? "flashlight.on.fill" : "flashlight.off.fill",
                        action: onToggleTorch
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .cornerRadius(12)
        .padding(.horizontal, 20)
    }
    
    private func controlButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.6))
                .cornerRadius(22)
        }
    }
    
    // MARK: - Recording Controls Section
    private var recordingControlsSection: some View {
        HStack(spacing: 40) {
            // Exit Button
            Button(action: onExitShorts) {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.gray.opacity(0.6))
                    .cornerRadius(25)
            }
            
            Spacer()
            
            // Large Record Button
            Button(action: {
                if viewModel.isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }) {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .fill(viewModel.isRecording ? Color.red : Color.white)
                        .frame(width: viewModel.isRecording ? 40 : 60, height: viewModel.isRecording ? 40 : 60)
                        .scaleEffect(viewModel.isRecording ? 0.8 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.isRecording)
                }
            }
            .disabled(!canRecord)
            
            Spacer()
            
            // Clip Count
            VStack {
                Text("\(viewModel.shortsSession?.clips.count ?? 0)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                Text("clips")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(width: 50)
        }
        .padding(.horizontal, 40)
    }
    
    private var canRecord: Bool {
        guard let session = viewModel.shortsSession else { return false }
        return !viewModel.isRecording && session.canAddClip
    }
    
    // MARK: - Timeline Section
    private var timelineSection: some View {
        VStack(spacing: 8) {
            if let session = viewModel.shortsSession, !session.clips.isEmpty {
                Text("Timeline")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(session.clips) { clip in
                            clipThumbnailView(clip: clip)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            } else {
                VStack {
                    Text("No clips yet")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                    Text("Tap the record button to add your first clip")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: 120)
        .background(Color.black.opacity(0.3))
    }
    
    private func clipThumbnailView(clip: ShortsClip) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.8))
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
                
                // Thumbnail if available
                if let thumbnailData = clip.thumbnailImageData,
                   let thumbnail = UIImage(data: thumbnailData) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipped()
                        .cornerRadius(8)
                }
                
                // Play button overlay
                Button(action: {
                    onPreviewClip(clip)
                }) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(15)
                }
                
                // Delete button
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            onDeleteClip(clip.id)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.red)
                                .background(Color.white)
                                .cornerRadius(8)
                        }
                    }
                    Spacer()
                }
                .frame(width: 60, height: 60)
            }
            
            Text("\(String(format: "%.1f", clip.duration))s")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    // MARK: - Action Buttons Section
    private var actionButtonsSection: some View {
        HStack(spacing: 20) {
            if let session = viewModel.shortsSession, !session.clips.isEmpty {
                // Preview Button
                Button(action: {
                    // TODO: Implement preview functionality
                }) {
                    HStack {
                        Image(systemName: "play.rectangle")
                        Text("Preview")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.8))
                    .cornerRadius(8)
                }
                
                // Finalize Button
                Button(action: onFinalize) {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text("Finalize")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.green.opacity(0.8))
                    .cornerRadius(8)
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Recording Logic
    private func startRecording() {
        // Don't set isRecording=true until camera acknowledges
        // The MonitorViewModel will update the recording state via proper channels
        recordingDuration = 0
        onStartRecording()
        // Timer will be started when camera confirms recording
    }
    
    private func stopRecording() {
        // Don't immediately set isRecording=false, wait for camera acknowledgment
        onStopRecording()
        // Timer will be stopped when camera confirms stop
    }
    
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            recordingDuration += 0.1
            
            // Auto-stop at max single clip duration
            if let session = viewModel.shortsSession {
                if recordingDuration >= session.config.maxSingleClipDuration {
                    stopRecording()
                }
            }
        }
    }
    
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration * 10).truncatingRemainder(dividingBy: 10))
        
        if minutes > 0 {
            return String(format: "%d:%02d.%d", minutes, seconds, tenths)
        } else {
            return String(format: "%d.%d", seconds, tenths)
        }
    }
}

// MARK: - Preview
struct ShortsMonitorView_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = MonitorViewModel()
        viewModel.selectedShortsConfig = .thirtySeconds
        viewModel.shortsSession = ShortsSession(config: .thirtySeconds)
        
        return ShortsMonitorView(
            viewModel: viewModel,
            onStartRecording: {},
            onStopRecording: {},
            onToggleCamera: {},
            onToggleFlash: {},
            onToggleTorch: {},
            onFinalize: {},
            onExitShorts: {},
            onDeleteClip: { _ in },
            onPreviewClip: { _ in },
            onConfigurationChange: { _ in }
        )
    }
} 