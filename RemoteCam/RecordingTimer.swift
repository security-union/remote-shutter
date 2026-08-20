import SwiftUI

/// The remote's recording timecode — CAMERA-DRIVEN, deliberately dumb.
///
/// The value shown is exactly the last elapsed tick the camera sent
/// (`CameraStateReport`, ~1/s while recording). There is NO local clock, no
/// `Timer`, and no interpolation on the remote: a display that computes time
/// itself can disagree with the device doing the recording (negative timers,
/// drift after rejoins); a display that only echoes the camera cannot.
struct RecordingTimer: View {
    /// Milliseconds recorded so far, as last reported by the camera.
    let elapsedMillis: UInt64?
    let isRecording: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Recording indicator dot
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
                .scaleEffect(isRecording ? 1.0 : 0.8)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isRecording)

            // Recording duration text — the camera's tick, verbatim.
            Text(Self.format(elapsedMillis))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
    }

    static func format(_ elapsedMillis: UInt64?) -> String {
        guard let elapsedMillis else { return "--:--" }
        let totalSeconds = elapsedMillis / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct RecordingTimer_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            RecordingTimer(elapsedMillis: 65_000, isRecording: true)
            RecordingTimer(elapsedMillis: 5_000, isRecording: true)
            RecordingTimer(elapsedMillis: nil, isRecording: false)
        }
        .padding()
    }
}
