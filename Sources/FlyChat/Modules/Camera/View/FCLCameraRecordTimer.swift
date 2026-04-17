import SwiftUI

/// Compact elapsed-time pill shown while recording video.
///
/// Rendered as a red-filled capsule with monospaced white digits and a
/// small pulsing white square indicator at the leading edge.
struct FCLCameraRecordTimer: View {
    let duration: TimeInterval
    let isRecording: Bool

    @State private var pulse: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.white)
                .frame(width: 4, height: 4)
                .opacity(pulse ? 1.0 : 0.4)
                .animation(
                    isRecording
                    ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                    : nil,
                    value: pulse
                )
            Text(formatted)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.red))
        .accessibilityLabel(Text("Recording time \(formatted)"))
        .onAppear {
            if isRecording { pulse = true }
        }
        .onChange(of: isRecording) { _, newValue in
            pulse = newValue
        }
    }

    private var formatted: String {
        let total = max(0, Int(duration))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if total >= 3600 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#if DEBUG
#Preview("Record timer — idle") {
    ZStack {
        Color.black
        FCLCameraRecordTimer(duration: 0, isRecording: false)
    }
}

#Preview("Record timer — recording") {
    ZStack {
        Color.black
        FCLCameraRecordTimer(duration: 73, isRecording: true)
    }
}

#Preview("Record timer — long recording") {
    ZStack {
        Color.black
        FCLCameraRecordTimer(duration: 3725, isRecording: true)
    }
}
#endif

