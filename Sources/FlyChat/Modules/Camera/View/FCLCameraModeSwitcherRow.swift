import SwiftUI

/// Horizontal row containing the flip-camera button and a photo/video segmented chip group.
///
/// Layout: `[flip icon button]` + `[Photo chip | Video chip]` centered together.
/// The flip button is disabled during recording to prevent mid-capture hardware handoff.
struct FCLCameraModeSwitcherRow: View {
    let mode: FCLCameraMode
    let isRecording: Bool
    let allowsVideo: Bool
    let onFlip: () -> Void
    let onSetMode: (FCLCameraMode) -> Void

    var body: some View {
        HStack(spacing: 16) {
            flipButton
            if allowsVideo && !isRecording {
                modeChips
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 4)
    }

    private var flipButton: some View {
        FCLGlassIconButton(
            systemImage: "camera.rotate",
            size: 44,
            action: onFlip
        )
        .disabled(isRecording)
        .opacity(isRecording ? 0.4 : 1)
        .accessibilityLabel("Flip camera")
    }

    private var modeChips: some View {
        HStack(spacing: 8) {
            modeChip(.photo, title: "Photo")
            modeChip(.video, title: "Video")
        }
    }

    private func modeChip(_ target: FCLCameraMode, title: String) -> some View {
        let selected = mode == target
        return FCLGlassChip(
            title: title,
            tint: selected ? FCLChatColorToken(red: 1.0, green: 0.84, blue: 0.0) : nil,
            action: { onSetMode(target) }
        )
        .accessibilityLabel("Switch to \(title.lowercased()) mode")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#if DEBUG
#Preview("ModeSwitcherRow — photo, idle") {
    ZStack {
        Color.black
        VStack {
            Spacer()
            FCLCameraModeSwitcherRow(
                mode: .photo,
                isRecording: false,
                allowsVideo: true,
                onFlip: {},
                onSetMode: { _ in }
            )
            .padding(.bottom, 12)
        }
    }
}

#Preview("ModeSwitcherRow — video, idle") {
    ZStack {
        Color.black
        VStack {
            Spacer()
            FCLCameraModeSwitcherRow(
                mode: .video,
                isRecording: false,
                allowsVideo: true,
                onFlip: {},
                onSetMode: { _ in }
            )
            .padding(.bottom, 12)
        }
    }
}

#Preview("ModeSwitcherRow — recording (chips hidden)") {
    ZStack {
        Color.black
        VStack {
            Spacer()
            FCLCameraModeSwitcherRow(
                mode: .video,
                isRecording: true,
                allowsVideo: true,
                onFlip: {},
                onSetMode: { _ in }
            )
            .padding(.bottom, 12)
        }
    }
}
#endif

