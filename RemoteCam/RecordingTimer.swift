import SwiftUI
import Combine

// MARK: - Recording Timer Component
struct RecordingTimer: View {
    @State private var recordingDuration: TimeInterval = 0
    @State private var timer: Timer?
    
    let startTime: Date?
    let isRecording: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Recording indicator dot
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
                .scaleEffect(isRecording ? 1.0 : 0.8)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isRecording)
            
            // Recording duration text
            Text(formattedDuration)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .animation(.none, value: recordingDuration)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
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
struct RecordingTimer_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            RecordingTimer(startTime: Date().addingTimeInterval(-65), isRecording: true)
            RecordingTimer(startTime: Date().addingTimeInterval(-5), isRecording: true) 
            RecordingTimer(startTime: nil, isRecording: false)
        }
        .padding()
        .background(Color.black)
    }
} 