#if canImport(UIKit)
import SwiftUI

/// Bottom shutter row: `[Done chip OR empty]` left, `[shutter]` center, `[empty]` right.
///
/// The left slot shows a `FCLGlassChip` labeled "Done" with a badge count and a
/// thumbnail accessory when `capturedCount >= 2`. Tapping Done calls `onDone`.
/// The right slot is always empty (reserved for symmetry).
struct FCLCameraShutterRow: View {
    let mode: FCLCameraMode
    let isRecording: Bool
    let capturedCount: Int
    let lastCapturedThumbnail: UIImage?
    let onShutter: () -> Void
    let onDone: () -> Void

    /// Show the Done chip when at least 2 assets have been captured and the
    /// camera is not mid-recording.
    private var showsDoneChip: Bool {
        capturedCount >= 2 && !isRecording
    }

    var body: some View {
        HStack(spacing: 16) {
            Group {
                if showsDoneChip {
                    doneChip
                } else {
                    Color.clear.frame(width: 72, height: 44)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            FCLCameraShutterButton(
                mode: mode,
                isRecording: isRecording,
                isEnabled: true,
                action: onShutter
            )

            reservedSlot
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
    }

    private var reservedSlot: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(
                Color.white.opacity(0.22),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )
            .frame(width: 44, height: 44)
            .opacity(0.6)
    }

    private var doneChip: some View {
        FCLGlassChip(
            title: "Done",
            badgeCount: capturedCount,
            action: onDone
        ) {
            thumbnailAccessory
        }
        .accessibilityLabel("Done, \(capturedCount) items captured")
    }

    @ViewBuilder
    private var thumbnailAccessory: some View {
        if let image = lastCapturedThumbnail {
            // Do not add an inner `.clipShape` — `FCLGlassChip` owns the corner radius.
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 24, height: 24)
        } else {
            Color.white.opacity(0.2)
                .frame(width: 24, height: 24)
        }
    }
}

#if DEBUG
#Preview("ShutterRow — first enter, photo (no Done chip)") {
    ZStack {
        Color.black
        VStack {
            Spacer()
            FCLCameraShutterRow(
                mode: .photo,
                isRecording: false,
                capturedCount: 0,
                lastCapturedThumbnail: nil,
                onShutter: {},
                onDone: {}
            )
        }
    }
}

#Preview("ShutterRow — second enter, photo (count 3, with Done chip)") {
    ZStack {
        Color.black
        VStack {
            Spacer()
            FCLCameraShutterRow(
                mode: .photo,
                isRecording: false,
                capturedCount: 3,
                lastCapturedThumbnail: nil,
                onShutter: {},
                onDone: {}
            )
        }
    }
}

#Preview("ShutterRow — video recording (Done chip hidden)") {
    ZStack {
        Color.black
        VStack {
            Spacer()
            FCLCameraShutterRow(
                mode: .video,
                isRecording: true,
                capturedCount: 3,
                lastCapturedThumbnail: nil,
                onShutter: {},
                onDone: {}
            )
        }
    }
}

#Preview("ShutterRow — second enter, count 1 (no Done chip)") {
    ZStack {
        Color.black
        VStack {
            Spacer()
            FCLCameraShutterRow(
                mode: .photo,
                isRecording: false,
                capturedCount: 1,
                lastCapturedThumbnail: nil,
                onShutter: {},
                onDone: {}
            )
        }
    }
}
#endif

#endif
