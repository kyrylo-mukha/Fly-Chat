#if canImport(UIKit)
import SwiftUI

/// Top overlay bar with close (X), flash cycle button, and optional "Done".
struct FCLCameraTopBar: View {
    let flashMode: FCLCameraFlashMode
    let showsDone: Bool
    let isRecording: Bool
    let onClose: () -> Void
    let onToggleFlash: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            closeButton
            flashButton
            Spacer(minLength: 8)
            if showsDone {
                doneButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 28, weight: .regular))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.black.opacity(0.45))
                .frame(width: 34, height: 34)
        }
        .accessibilityLabel("Close camera")
    }

    private var flashButton: some View {
        Button(action: onToggleFlash) {
            flashPillContent
        }
        .disabled(isRecording)
        .opacity(isRecording ? 0.4 : 1)
        .accessibilityLabel(Text("Flash \(flashAccessibilityValue)"))
    }

    @ViewBuilder
    private var flashPillContent: some View {
        switch flashMode {
        case .on:
            Image(systemName: "bolt.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 34, height: 28)
                .background(Capsule().fill(Color.yellow))
        case .auto:
            Image(systemName: "bolt.badge.a.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 28)
                .background(Capsule().fill(Color.black.opacity(0.45)))
        case .off:
            Image(systemName: "bolt.slash.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 28)
                .background(Capsule().fill(Color.black.opacity(0.45)))
        }
    }

    private var doneButton: some View {
        Button(action: onDone) {
            Text("Done")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.yellow)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        }
        .accessibilityLabel("Finish and use captured media")
    }

    private var flashAccessibilityValue: String {
        switch flashMode {
        case .auto: return "automatic"
        case .on: return "on"
        case .off: return "off"
        }
    }
}

#if DEBUG
#Preview("Top bar — flash auto") {
    ZStack {
        Color.gray
        FCLCameraTopBar(flashMode: .auto, showsDone: false, isRecording: false,
                        onClose: {}, onToggleFlash: {}, onDone: {})
    }
}

#Preview("Top bar — flash on + Done") {
    ZStack {
        Color.gray
        FCLCameraTopBar(flashMode: .on, showsDone: true, isRecording: false,
                        onClose: {}, onToggleFlash: {}, onDone: {})
    }
}

#Preview("Top bar — recording") {
    ZStack {
        Color.gray
        FCLCameraTopBar(flashMode: .off, showsDone: false, isRecording: true,
                        onClose: {}, onToggleFlash: {}, onDone: {})
    }
}
#endif

#endif
