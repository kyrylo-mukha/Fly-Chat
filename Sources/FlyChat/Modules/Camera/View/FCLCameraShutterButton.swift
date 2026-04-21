import SwiftUI

/// Large shutter button at the center of the bottom bar.
///
/// Rendering:
/// - Photo mode: white filled disc inside a white ring.
/// - Video mode, idle: red filled disc inside a white ring.
/// - Video mode, recording: red rounded square inside a white ring.
///
/// The white outer ring stays constant across all modes and states.
struct FCLCameraShutterButton: View {
    let mode: FCLCameraMode
    let isRecording: Bool
    let isEnabled: Bool
    let action: () -> Void

    // Outer ring diameter matches the prototype (78 pt). Inner fill is
    // outer - 14 = 64 pt, giving a 7 pt gap on each side for the ring.
    private let outerSize: CGFloat = 78

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: outerSize, height: outerSize)

                innerShape
            }
            .contentShape(Circle())
            .animation(
                .interactiveSpring(response: 0.25, dampingFraction: 0.65),
                value: isRecording
            )
            .animation(
                .interactiveSpring(response: 0.25, dampingFraction: 0.65),
                value: mode
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var innerShape: some View {
        if mode == .video && isRecording {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.red)
                .frame(width: 36, height: 36)
        } else {
            Circle()
                .fill(mode == .video ? Color.red : Color.white)
                // Inner disc: outerSize - 14 = 64 pt (7 pt ring gap each side)
                .frame(width: outerSize - 14, height: outerSize - 14)
        }
    }

    private var accessibilityLabel: Text {
        switch (mode, isRecording) {
        case (.photo, _): return Text("Take photo")
        case (.video, false): return Text("Start recording")
        case (.video, true): return Text("Stop recording")
        }
    }
}

#if DEBUG
#Preview("Shutter — photo idle") {
    FCLCameraShutterButton(mode: .photo, isRecording: false, isEnabled: true) { }
        .padding(40)
        .background(Color.black)
}

#Preview("Shutter — video idle") {
    FCLCameraShutterButton(mode: .video, isRecording: false, isEnabled: true) { }
        .padding(40)
        .background(Color.black)
}

#Preview("Shutter — video recording") {
    FCLCameraShutterButton(mode: .video, isRecording: true, isEnabled: true) { }
        .padding(40)
        .background(Color.black)
}

#Preview("Shutter — disabled") {
    FCLCameraShutterButton(mode: .photo, isRecording: false, isEnabled: false) { }
        .padding(40)
        .background(Color.black)
}
#endif
