//
//  ShortsView.swift
//  RemoteShutter
//
//  Created by Dario Lencina on 2025.
//  Copyright © 2025 Security Union. All rights reserved.
//

import SwiftUI
import UIKit
import Combine

// MARK: - Shorts Camera View (SwiftUI)
struct ShortsView: View {
    @ObservedObject var session: ShortsSession
    @State private var currentClipDuration: TimeInterval = 0
    @State private var isRecording = false
    @State private var recordingStartTime: Date?
    
    // Callbacks to CameraViewController for Actor integration
    let onBackTapped: () -> Void
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    
    // Timer for updating recording duration
    @State private var timer: Timer?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.clear // Transparent so camera preview shows through
                
                VStack {
                    // MARK: - Top Status Bar
                    topStatusBar
                        .padding(.top, geometry.safeAreaInsets.top)
                    
                    Spacer()
                    
                    // MARK: - Recording Indicator
                    recordingIndicator
                    
                    Spacer()
                    
                    // MARK: - Bottom Status Info
                    bottomStatusInfo
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 20)
                }
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden()
        .onReceive(session.$state) { state in
            handleSessionStateChange(state)
        }
    }
    
    // MARK: - Top Status Bar
    private var topStatusBar: some View {
        HStack {
            // Back Button
            Button(action: onBackTapped) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding()
            }
            
            Spacer()
            
            // Shorts Mode Indicator
            Text("SHORTS")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(0.8))
                )
            
            Spacer()
            
            // Duration Configuration Display
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(session.config.maxDuration))s")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("MAX")
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundColor(.gray)
            }
            .padding(.trailing)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Recording Indicator
    private var recordingIndicator: some View {
        VStack(spacing: 16) {
            // Record Button Visual Feedback
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red : Color.white.opacity(0.8))
                    .frame(width: 80, height: 80)
                    .scaleEffect(isRecording ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isRecording)
                
                if isRecording {
                    Text("REC")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            
            // Current clip duration
            if isRecording {
                Text(formatDuration(currentClipDuration))
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .transition(.opacity)
            }
            
            // Status Message
            Text(statusMessage)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    // MARK: - Bottom Status Info
    private var bottomStatusInfo: some View {
        VStack(spacing: 12) {
            // Clips Timeline Summary
            HStack(spacing: 8) {
                ForEach(session.clips.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.8))
                        .frame(width: max(20, CGFloat(session.clips[index].duration / session.config.maxDuration) * 120), height: 8)
                }
                
                // Remaining time indicator
                if session.remainingDuration > 0 {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: max(10, CGFloat(session.remainingDuration / session.config.maxDuration) * 120), height: 8)
                }
            }
            .frame(height: 8)
            
            // Duration Info
            HStack {
                Text("\(session.clips.count) clips")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.gray)
                
                Spacer()
                
                Text("\(formatDuration(session.totalDuration)) / \(formatDuration(session.config.maxDuration))")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(formatDuration(session.remainingDuration)) left")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Computed Properties
    
    private var statusMessage: String {
        switch session.state {
        case .idle:
            return "Ready to record shorts\nControlled by remote device"
        case .recording:
            return "Recording clip \(session.clips.count + 1)..."
        case .processing:
            return "Processing clip..."
        case .previewing:
            return "Previewing clips..."
        case .finalizing:
            return "Creating final video..."
        case .completed:
            return "Shorts session complete!"
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
    
    private func handleSessionStateChange(_ state: ShortsSession.SessionState) {
        switch state {
        case .recording:
            startRecordingTimer()
        case .idle, .processing, .previewing, .finalizing, .completed:
            stopRecordingTimer()
        }
    }
    
    private func startRecordingTimer() {
        isRecording = true
        recordingStartTime = Date()
        currentClipDuration = 0
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if let startTime = recordingStartTime {
                currentClipDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func stopRecordingTimer() {
        isRecording = false
        timer?.invalidate()
        timer = nil
        recordingStartTime = nil
        currentClipDuration = 0
    }
}

// MARK: - Preview
struct ShortsView_Previews: PreviewProvider {
    static var previews: some View {
        ShortsView(
            session: ShortsSession(config: .fifteenSeconds),
            onBackTapped: {},
            onStartRecording: {},
            onStopRecording: {}
        )
        .preferredColorScheme(.dark)
    }
} 