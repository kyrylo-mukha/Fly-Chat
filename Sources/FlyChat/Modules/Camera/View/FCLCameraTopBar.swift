#if canImport(UIKit)
import SwiftUI

/// Top overlay bar with close (X) and flash controls.
///
/// Close behavior is governed by `capturedCount`:
/// - 0, 1 → calls `onClose` immediately (direct dismiss).
/// - 2+ → presents a confirmation dialog offering "Discard N captured items?" with a
///   destructive Discard action and a Cancel action that keeps the camera open.
struct FCLCameraTopBar: View {
    let flashMode: FCLCameraFlashMode
    let capturedCount: Int
    let isRecording: Bool
    let onClose: () -> Void
    let onToggleFlash: () -> Void
    let onDiscardAssets: () -> Void
    @Binding var showDiscardDialog: Bool

    var body: some View {
        FCLGlassToolbar(placement: .top) {
            closeButton
            Spacer(minLength: 8)
            flashChip
        }
        .confirmationDialog(
            String(format: NSLocalizedString("flychat.camera.discard.title", comment: "Title asking user to confirm discarding N captured items"), capturedCount),
            isPresented: $showDiscardDialog,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("flychat.camera.discard.action", comment: "Destructive action to discard captured items"), role: .destructive) {
                onDiscardAssets()
                onClose()
            }
            Button(NSLocalizedString("flychat.camera.discard.cancel", comment: "Cancel discard action and keep camera open"), role: .cancel) { }
        }
    }

    private var closeButton: some View {
        FCLGlassIconButton(systemImage: "xmark", size: 44) {
            if capturedCount >= 2 {
                showDiscardDialog = true
            } else {
                onClose()
            }
        }
        .disabled(isRecording)
        .opacity(isRecording ? 0.4 : 1)
        .accessibilityLabel("Close camera")
    }

    private var flashChip: some View {
        let (image, title): (String, String) = {
            switch flashMode {
            case .on:   return ("bolt.fill", "Flash on")
            case .auto: return ("bolt.badge.a.fill", "Flash auto")
            case .off:  return ("bolt.slash.fill", "Flash off")
            }
        }()
        return FCLGlassChip(title: title, action: onToggleFlash) {
            Image(systemName: image)
                .font(.system(size: 14, weight: .semibold))
        }
        .disabled(isRecording)
        .opacity(isRecording ? 0.4 : 1)
        .accessibilityLabel(Text("Flash \(flashAccessibilityValue)"))
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
#Preview("Top bar — first enter, flash auto (count=0)") {
    @State var showDialog = false
    return ZStack {
        Color.gray
        FCLCameraTopBar(flashMode: .auto, capturedCount: 0, isRecording: false,
                        onClose: {}, onToggleFlash: {}, onDiscardAssets: {},
                        showDiscardDialog: $showDialog)
    }
    .previewDisplayName("Top bar — first enter, flash auto (count=0)")
}

#Preview("Top bar — count=1, flash on") {
    @State var showDialog = false
    return ZStack {
        Color.gray
        FCLCameraTopBar(flashMode: .on, capturedCount: 1, isRecording: false,
                        onClose: {}, onToggleFlash: {}, onDiscardAssets: {},
                        showDiscardDialog: $showDialog)
    }
    .previewDisplayName("Top bar — count=1, flash on")
}

#Preview("Top bar — count=3 with discard dialog shown, flash on") {
    @State var showDialog = true
    return ZStack {
        Color.gray
        FCLCameraTopBar(flashMode: .on, capturedCount: 3, isRecording: false,
                        onClose: {}, onToggleFlash: {}, onDiscardAssets: {},
                        showDiscardDialog: $showDialog)
    }
    .previewDisplayName("Top bar — count=3 with discard dialog shown, flash on")
}

#Preview("Top bar — recording") {
    @State var showDialog = false
    return ZStack {
        Color.gray
        FCLCameraTopBar(flashMode: .off, capturedCount: 0, isRecording: true,
                        onClose: {}, onToggleFlash: {}, onDiscardAssets: {},
                        showDiscardDialog: $showDialog)
    }
    .previewDisplayName("Top bar — recording")
}
#endif

#endif
