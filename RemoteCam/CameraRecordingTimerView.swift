import SwiftUI

// MARK: - Camera Recording Timer Overlay
struct CameraRecordingTimerView: View {
    let recordingStartTime: Date?
    let isRecording: Bool

    var body: some View {
        GeometryReader { geometry in
            VStack {
                HStack {
                    Spacer()
                                         if isRecording {
                         CameraRecordingTimer(
                             startTime: recordingStartTime,
                             isRecording: isRecording
                         )
                         .padding(.top, 60) // Account for status bar and safe area
                         .padding(.trailing, 20)
                     }
                }
                Spacer()
            }
        }
        .allowsHitTesting(false) // Allow touches to pass through to camera controls
        .background(Color.clear)
    }
}

// MARK: - Camera-Specific Large Recording Timer
struct CameraRecordingTimer: View {
    @State private var recordingDuration: TimeInterval = 0

    let startTime: Date?
    let isRecording: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Large recording indicator dot
            Circle()
                .fill(Color.red)
                .frame(width: 24, height: 24) // Double the size
                .scaleEffect(isRecording ? 1.0 : 0.8)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isRecording)

            // Large recording duration text
            Text(formattedDuration)
                .font(.system(size: 28, weight: .bold, design: .monospaced)) // Double the size
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.8), radius: 2, x: 1, y: 1) // Add shadow for better visibility
                .animation(.none, value: recordingDuration)
        }
        .padding(.horizontal, 20) // Larger padding
        .padding(.vertical, 12)   // Larger padding
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.85)) // Slightly more opaque background
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2) // Add drop shadow
        )
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            updateDuration()
        }
        .onAppear {
            updateDuration()
        }
        .onChange(of: isRecording) { recording in
            if !recording {
                recordingDuration = 0
            }
        }
    }

    private var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func updateDuration() {
        guard isRecording, let startTime = startTime else {
            recordingDuration = 0
            return
        }
        recordingDuration = Date().timeIntervalSince(startTime)
    }
}

// MARK: - Preview
struct CameraRecordingTimerView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 30) {
            // Camera timer (large)
            CameraRecordingTimer(
                startTime: Date().addingTimeInterval(-65),
                isRecording: true
            )

            // Regular timer for comparison
            RecordingTimer(
                elapsedMillis: 65_000,
                isRecording: true
            )

            Text("Camera (top) vs Monitor (bottom) timer sizes")
                .foregroundColor(.white)
                .font(.caption)
        }
        .padding()
        .background(Color.black)
    }
}