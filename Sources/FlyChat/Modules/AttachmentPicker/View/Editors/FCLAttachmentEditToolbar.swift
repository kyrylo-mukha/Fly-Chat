import SwiftUI

// MARK: - FCLAttachmentEditToolbar

/// Shared chrome for any attachment editor: a top row with Cancel (discard
/// tool changes) and Done (commit tool changes), plus a bottom-left
/// Undo/Redo pair. Tool-specific controls are supplied via the
/// `toolControls` view builder and are rendered between the two rows.
///
/// The full-exit button (top-right X) is deliberately omitted here: the host
/// preview screen owns the single X that is always visible, and its action
/// branches on edit state (see `FCLAttachmentPreviewScreen`).
@MainActor
struct FCLAttachmentEditToolbar<ToolControls: View>: View {
    let title: String
    let canUndo: Bool
    let canRedo: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onCancel: () -> Void
    let onDone: () -> Void
    @ViewBuilder var toolControls: () -> ToolControls

    var body: some View {
        VStack(spacing: 0) {
            topRow
            toolControls()
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            undoRedoRow
        }
        .background(Color.black.opacity(0.85))
    }

    // MARK: Rows

    private var topRow: some View {
        HStack {
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityLabel("Cancel edit")

            Spacer()

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.yellow)
            }
            .accessibilityLabel("Commit edit")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var undoRedoRow: some View {
        HStack(spacing: 22) {
            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(canUndo ? .white : .white.opacity(0.3))
                    .frame(width: 40, height: 40)
            }
            .disabled(!canUndo)
            .accessibilityLabel("Undo")

            Button(action: onRedo) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(canRedo ? .white : .white.opacity(0.3))
                    .frame(width: 40, height: 40)
            }
            .disabled(!canRedo)
            .accessibilityLabel("Redo")

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Toolbar — idle") {
    ZStack {
        Color.gray.ignoresSafeArea()
        VStack {
            Spacer()
            FCLAttachmentEditToolbar(
                title: "Rotate & Crop",
                canUndo: false,
                canRedo: false,
                onUndo: {},
                onRedo: {},
                onCancel: {},
                onDone: {}
            ) {
                Text("Tool controls go here")
                    .foregroundStyle(.white)
                    .frame(height: 60)
            }
        }
    }
}

#Preview("Toolbar — can undo/redo") {
    ZStack {
        Color.gray.ignoresSafeArea()
        VStack {
            Spacer()
            FCLAttachmentEditToolbar(
                title: "Markup",
                canUndo: true,
                canRedo: true,
                onUndo: {},
                onRedo: {},
                onCancel: {},
                onDone: {}
            ) {
                EmptyView()
            }
        }
    }
}
#endif
