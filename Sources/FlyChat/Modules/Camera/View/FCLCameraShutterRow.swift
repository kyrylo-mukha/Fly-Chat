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
        ZStack {
            // Shutter is always centered.
            FCLCameraShutterButton(
                mode: mode,
                isRecording: isRecording,
                isEnabled: true,
                action: onShutter
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            // Left slot: Done chip or invisible placeholder for symmetry.
            HStack {
                if showsDoneChip {
                    doneChip
                } else {
                    Color.clear.frame(width: 72, height: 44)
                }
                Spacer(minLength: 0)
            }

            // Right slot: always empty placeholder so shutter stays centered.
            HStack {
                Spacer(minLength: 0)
                Color.clear.frame(width: 72, height: 44)
            }
        }
        .frame(height: 72)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
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
            // Scope 05/07: rely on `FCLGlassChip`'s own 8pt corner + 4pt
            // padding. An inner `.clipShape(RoundedRectangle(cornerRadius: 4))`
            // would mask the outer 8pt radius the primitive applies.
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 24, height: 24)
        } else {
            // Placeholder when thumbnail is not yet loaded. Same no-inner-clip
            // rule applies — the primitive owns the corner.
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
