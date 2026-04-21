import SwiftUI

/// Top overlay bar with three independently-floating glass elements:
/// close (leading), flash mode pill (center), overflow (trailing).
///
/// Each element sits on its own capsule surface, placed with
/// `HStack(spacing: 0)` + spacers so they span edge-to-edge at 16 pt insets,
/// matching the prototype layout (`top: 12, left/right: 16, justify: space-between`).
///
/// Close behavior is governed by `capturedCount`:
/// - 0, 1 → calls `onClose` immediately.
/// - 2+ → presents a confirmation dialog.
struct FCLCameraTopBar: View {
    let flashMode: FCLCameraFlashMode
    let capturedCount: Int
    let isRecording: Bool
    let onClose: () -> Void
    let onToggleFlash: () -> Void
    let onOverflow: (() -> Void)?
    let onDiscardAssets: () -> Void
    @Binding var showDiscardDialog: Bool

    init(
        flashMode: FCLCameraFlashMode,
        capturedCount: Int,
        isRecording: Bool,
        onClose: @escaping () -> Void,
        onToggleFlash: @escaping () -> Void,
        onOverflow: (() -> Void)? = nil,
        onDiscardAssets: @escaping () -> Void,
        showDiscardDialog: Binding<Bool>
    ) {
        self.flashMode = flashMode
        self.capturedCount = capturedCount
        self.isRecording = isRecording
        self.onClose = onClose
        self.onToggleFlash = onToggleFlash
        self.onOverflow = onOverflow
        self.onDiscardAssets = onDiscardAssets
        self._showDiscardDialog = showDiscardDialog
    }

    var body: some View {
        // Three-slot layout: close (leading) · flash pill (center) · overflow (trailing).
        // Spacers push the slots to the edges and keep the pill floating in the center.
        HStack(spacing: 0) {
            closeButton
            Spacer(minLength: 8)
            flashPill
            Spacer(minLength: 8)
            overflowButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .confirmationDialog(
            String(format: NSLocalizedString(
                "flychat.camera.discard.title",
                comment: "Title asking user to confirm discarding N captured items"
            ), capturedCount),
            isPresented: $showDiscardDialog,
            titleVisibility: .visible
        ) {
            Button(
                NSLocalizedString(
                    "flychat.camera.discard.action",
                    comment: "Destructive action to discard captured items"
                ),
                role: .destructive
            ) {
                onDiscardAssets()
                onClose()
            }
            Button(
                NSLocalizedString(
                    "flychat.camera.discard.cancel",
                    comment: "Cancel discard action and keep camera open"
                ),
                role: .cancel
            ) { }
        }
    }

    // MARK: - Close button

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

    // MARK: - Flash pill

    /// Center pill: SF Symbol glyph + mode label, height 36, horizontal padding 12/14.
    /// Font: 13 pt semibold, matching the prototype's font-size: 13, font-weight: 600.
    private var flashPill: some View {
        let (image, label) = flashLabel
        return FCLGlassChip(title: label, action: onToggleFlash) {
            Image(systemName: image)
                .font(.system(size: 13, weight: .semibold))
        }
        .disabled(isRecording)
        .opacity(isRecording ? 0.4 : 1)
        .accessibilityLabel(Text("Flash \(flashAccessibilityValue)"))
    }

    private var flashLabel: (String, String) {
        switch flashMode {
        case .on:   return ("bolt.fill",       "On")
        case .auto: return ("bolt.badge.a.fill", "Auto")
        case .off:  return ("bolt.slash.fill", "Off")
        }
    }

    private var flashAccessibilityValue: String {
        switch flashMode {
        case .auto: return "automatic"
        case .on:   return "on"
        case .off:  return "off"
        }
    }

    // MARK: - Overflow button

    /// Trailing overflow button (ellipsis). Hidden when no handler is provided;
    /// an invisible same-size placeholder maintains the leading/center/trailing balance.
    private var overflowButton: some View {
        Group {
            if let onOverflow {
                FCLGlassIconButton(systemImage: "ellipsis", size: 44, action: onOverflow)
                    .accessibilityLabel("More options")
            } else {
                // Invisible placeholder keeps the flash pill centered.
                Color.clear.frame(width: 44, height: 44)
            }
        }
    }
}

#if DEBUG
#Preview("Top bar — first enter, flash auto (count=0)") {
    @Previewable @State var showDialog = false
    ZStack {
        Color.gray
        VStack {
            FCLCameraTopBar(flashMode: .auto, capturedCount: 0, isRecording: false,
                            onClose: {}, onToggleFlash: {}, onOverflow: {},
                            onDiscardAssets: {}, showDiscardDialog: $showDialog)
            Spacer()
        }
    }
    .ignoresSafeArea()
}

#Preview("Top bar — count=1, flash on") {
    @Previewable @State var showDialog = false
    ZStack {
        Color.gray
        VStack {
            FCLCameraTopBar(flashMode: .on, capturedCount: 1, isRecording: false,
                            onClose: {}, onToggleFlash: {}, onOverflow: {},
                            onDiscardAssets: {}, showDiscardDialog: $showDialog)
            Spacer()
        }
    }
    .ignoresSafeArea()
}

#Preview("Top bar — count=3 with discard dialog shown, flash on") {
    @Previewable @State var showDialog = true
    ZStack {
        Color.gray
        VStack {
            FCLCameraTopBar(flashMode: .on, capturedCount: 3, isRecording: false,
                            onClose: {}, onToggleFlash: {}, onOverflow: {},
                            onDiscardAssets: {}, showDiscardDialog: $showDialog)
            Spacer()
        }
    }
    .ignoresSafeArea()
}

#Preview("Top bar — recording") {
    @Previewable @State var showDialog = false
    ZStack {
        Color.gray
        VStack {
            FCLCameraTopBar(flashMode: .off, capturedCount: 0, isRecording: true,
                            onClose: {}, onToggleFlash: {}, onDiscardAssets: {},
                            showDiscardDialog: $showDialog)
            Spacer()
        }
    }
    .ignoresSafeArea()
}

#Preview("Top bar — no overflow handler (placeholder maintains balance)") {
    @Previewable @State var showDialog = false
    ZStack {
        Color.gray
        VStack {
            FCLCameraTopBar(flashMode: .auto, capturedCount: 0, isRecording: false,
                            onClose: {}, onToggleFlash: {}, onDiscardAssets: {},
                            showDiscardDialog: $showDialog)
            Spacer()
        }
    }
    .ignoresSafeArea()
}
#endif

