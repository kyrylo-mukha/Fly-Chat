#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import SwiftUI
import UIKit

// MARK: - FCLMarkupEditor

/// Draw-on-image editor backed by `PencilKit`. Committing burns strokes into a
/// new bitmap. Undo/redo delegates to the canvas's own `UndoManager`.
@MainActor
struct FCLMarkupEditor: View {
    let original: UIImage
    let onCommit: (UIImage) -> Void
    let onCancel: () -> Void

    @StateObject private var state = MarkupState()

    var body: some View {
        VStack(spacing: 0) {
            MarkupCanvasContainer(image: original, state: state)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

            FCLAttachmentEditToolbar(
                title: "Markup",
                canUndo: state.canUndo,
                canRedo: state.canRedo,
                onUndo: { state.performUndo() },
                onRedo: { state.performRedo() },
                onCancel: { onCancel() },
                onDone: { commit() }
            ) {
                EmptyView()
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onDisappear {
            state.canvas?.drawing = PKDrawing()
            state.canvas?.undoManager?.removeAllActions()
            state.refreshUndoState()
        }
    }

    private func commit() {
        guard let canvas = state.canvas else {
            onCommit(original)
            return
        }
        let drawing = canvas.drawing
        let canvasBounds = canvas.bounds
        let image = original
        let bounds = CGRect(origin: .zero, size: image.size)
        Task.detached(priority: .userInitiated) {
            let rendered = await MainActor.run { () -> UIImage in
                let format = UIGraphicsImageRendererFormat.default()
                format.scale = image.scale
                let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
                return renderer.image { _ in
                    image.draw(in: bounds)
                        let strokes = drawing.image(from: canvasBounds, scale: image.scale)
                    strokes.draw(in: bounds)
                }
            }
            await MainActor.run { onCommit(rendered) }
        }
    }
}

// MARK: - MarkupState

/// Observes canvas undo/redo state and retains the active `PKCanvasView`.
@MainActor
final class MarkupState: ObservableObject {
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
    weak var canvas: PKCanvasView?

    func refreshUndoState() {
        guard let um = canvas?.undoManager else {
            canUndo = false
            canRedo = false
            return
        }
        canUndo = um.canUndo
        canRedo = um.canRedo
    }

    func performUndo() {
        canvas?.undoManager?.undo()
        refreshUndoState()
    }

    func performRedo() {
        canvas?.undoManager?.redo()
        refreshUndoState()
    }
}

// MARK: - MarkupCanvasContainer

/// UIKit bridge hosting a `PKCanvasView` over a `UIImageView` with a docked `PKToolPicker`.
@MainActor
struct MarkupCanvasContainer: UIViewRepresentable {
    let image: UIImage
    let state: MarkupState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeUIView(context: Context) -> MarkupContainerView {
        let container = MarkupContainerView()
        container.imageView.image = image
        container.canvas.delegate = context.coordinator
        container.canvas.drawingPolicy = .anyInput
        container.canvas.isOpaque = false
        container.canvas.backgroundColor = .clear
        state.canvas = container.canvas
        context.coordinator.attachToolPicker(to: container.canvas)
        return container
    }

    func updateUIView(_ uiView: MarkupContainerView, context: Context) {
        uiView.imageView.image = image
    }

    static func dismantleUIView(_ uiView: MarkupContainerView, coordinator: Coordinator) {
        coordinator.detachToolPicker(from: uiView.canvas)
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let state: MarkupState
        private lazy var toolPicker: PKToolPicker = PKToolPicker()

        init(state: MarkupState) {
            self.state = state
        }

        func attachToolPicker(to canvas: PKCanvasView) {
            toolPicker.addObserver(canvas)
            toolPicker.setVisible(true, forFirstResponder: canvas)
            DispatchQueue.main.async {
                canvas.becomeFirstResponder()
            }
        }

        func detachToolPicker(from canvas: PKCanvasView) {
            toolPicker.setVisible(false, forFirstResponder: canvas)
            toolPicker.removeObserver(canvas)
            canvas.resignFirstResponder()
        }

        // MARK: PKCanvasViewDelegate

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            state.refreshUndoState()
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            state.refreshUndoState()
        }
    }
}

// MARK: - MarkupContainerView

@MainActor
final class MarkupContainerView: UIView {
    let imageView = UIImageView()
    let canvas = PKCanvasView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        canvas.translatesAutoresizingMaskIntoConstraints = true
        canvas.autoresizingMask = []
        addSubview(imageView)
        addSubview(canvas)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Canvas is constrained to the aspect-fit image rect so stroke coordinates
        // map 1:1 to the visible image area on commit.
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0 else {
            canvas.frame = bounds
            return
        }
        let containerSize = bounds.size
        let imageRatio = image.size.width / image.size.height
        let containerRatio = containerSize.width / max(containerSize.height, 0.001)
        var fit = CGRect.zero
        if imageRatio > containerRatio {
            fit.size.width = containerSize.width
            fit.size.height = containerSize.width / imageRatio
            fit.origin.x = 0
            fit.origin.y = (containerSize.height - fit.size.height) / 2
        } else {
            fit.size.height = containerSize.height
            fit.size.width = containerSize.height * imageRatio
            fit.origin.y = 0
            fit.origin.x = (containerSize.width - fit.size.width) / 2
        }
        canvas.frame = fit
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
private func markupPreviewImage() -> UIImage {
    let size = CGSize(width: 400, height: 300)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { ctx in
        UIColor.systemIndigo.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
        UIColor.white.setFill()
        ctx.fill(CGRect(x: 50, y: 60, width: 300, height: 180))
        UIColor.systemPink.setFill()
        ctx.fill(CGRect(x: 120, y: 110, width: 80, height: 80))
    }
}

#Preview("Markup — idle") {
    FCLMarkupEditor(
        original: markupPreviewImage(),
        onCommit: { _ in },
        onCancel: {}
    )
}

#Preview("Markup — with SF symbol") {
    FCLMarkupEditor(
        original: UIImage(systemName: "photo.artframe")!
            .withTintColor(.white, renderingMode: .alwaysOriginal),
        onCommit: { _ in },
        onCancel: {}
    )
}
#endif
#endif
