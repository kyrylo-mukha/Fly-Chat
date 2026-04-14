#if canImport(UIKit)
import SwiftUI
import UIKit

// MARK: - FCLMediaEditCropAspect

public enum FCLMediaEditCropAspect: Sendable, Equatable {
    case free
    case square
    case fourThree
    case sixteenNine

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .square: return "1:1"
        case .fourThree: return "4:3"
        case .sixteenNine: return "16:9"
        }
    }

    /// The width:height ratio, or nil for .free (no crop).
    var ratio: CGFloat? {
        switch self {
        case .free: return nil
        case .square: return 1.0
        case .fourThree: return 4.0 / 3.0
        case .sixteenNine: return 16.0 / 9.0
        }
    }
}

// MARK: - FCLMediaEditState

struct FCLMediaEditState: Equatable {
    var rotationSteps: Int = 0          // 0..3 (×90°)
    var flippedHorizontally: Bool = false
    var cropAspect: FCLMediaEditCropAspect = .free
}

// MARK: - FCLMediaEditorView

struct FCLMediaEditorView: View {
    let sourceImage: UIImage
    @State private var state: FCLMediaEditState
    let initialState: FCLMediaEditState
    let onConfirm: (UIImage, FCLMediaEditState) -> Void
    let onCancel: () -> Void

    @State private var isProcessing: Bool = false
    @State private var showCropMenu: Bool = false

    init(
        sourceImage: UIImage,
        initialState: FCLMediaEditState = .init(),
        onConfirm: @escaping (UIImage, FCLMediaEditState) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.sourceImage = sourceImage
        self.initialState = initialState
        self._state = State(initialValue: initialState)
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.top, 8)

                Spacer(minLength: 0)

                imagePreview

                Spacer(minLength: 0)

                bottomToolbar
                    .padding(.bottom, 24)
            }

            if isProcessing {
                processingOverlay
            }
        }
        .statusBarHidden(true)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 17))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }

            Spacer()

            Button {
                applyAndConfirm()
            } label: {
                Text("Done")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(isProcessing ? Color.white.opacity(0.4) : .white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .disabled(isProcessing)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Image Preview

    private var imagePreview: some View {
        Image(uiImage: sourceImage)
            .resizable()
            .scaledToFit()
            .rotationEffect(.degrees(Double(state.rotationSteps) * 90))
            .scaleEffect(x: state.flippedHorizontally ? -1 : 1, y: 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 12)
            .animation(.easeInOut(duration: 0.2), value: state.rotationSteps)
            .animation(.easeInOut(duration: 0.2), value: state.flippedHorizontally)
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            Spacer()

            // Rotate 90° CW
            toolbarButton(
                systemName: "rotate.right",
                accessibilityLabel: "Rotate 90° clockwise"
            ) {
                state.rotationSteps = (state.rotationSteps + 1) % 4
            }

            Spacer()

            // Flip horizontal
            toolbarButton(
                systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                accessibilityLabel: "Flip horizontal"
            ) {
                state.flippedHorizontally.toggle()
            }

            Spacer()

            // Crop aspect ratio
            cropButton

            Spacer()

            // Reset
            toolbarButton(
                systemName: "arrow.uturn.backward",
                accessibilityLabel: "Reset edits"
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    state = initialState
                }
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
    }

    private var cropButton: some View {
        Menu {
            ForEach(
                [FCLMediaEditCropAspect.free, .square, .fourThree, .sixteenNine],
                id: \.self
            ) { aspect in
                Button {
                    state.cropAspect = aspect
                } label: {
                    if state.cropAspect == aspect {
                        Label(aspect.displayName, systemImage: "checkmark")
                    } else {
                        Text(aspect.displayName)
                    }
                }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "crop")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(state.cropAspect == .free ? .white : .yellow)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())

                Text(state.cropAspect == .free ? "Crop" : state.cropAspect.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(state.cropAspect == .free ? .white.opacity(0.7) : .yellow)
            }
        }
    }

    private func toolbarButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemName)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())

                Color.clear.frame(height: 14) // balance height with crop button label
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Processing Overlay

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
            ProgressView()
                .tint(.white)
                .scaleEffect(1.5)
        }
    }

    // MARK: - Apply Edits

    private func applyAndConfirm() {
        guard !isProcessing else { return }
        isProcessing = true
        let capturedState = state
        let capturedSource = sourceImage
        Task.detached(priority: .userInitiated) {
            let result = capturedSource.fcl_applying(capturedState)
            await MainActor.run {
                self.isProcessing = false
                self.onConfirm(result, capturedState)
            }
        }
    }
}

// MARK: - UIImage Transform Extensions

private extension UIImage {

    /// Returns a copy rotated by `steps × 90°` clockwise, preserving scale.
    func fcl_rotated(steps: Int) -> UIImage {
        let normalizedSteps = ((steps % 4) + 4) % 4
        guard normalizedSteps != 0 else { return self }

        let radians = CGFloat(normalizedSteps) * (.pi / 2)

        // Determine new canvas size after rotation
        let originalSize = CGSize(width: size.width * scale, height: size.height * scale)
        let newSize: CGSize
        if normalizedSteps == 1 || normalizedSteps == 3 {
            newSize = CGSize(width: originalSize.height, height: originalSize.width)
        } else {
            newSize = originalSize
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: newSize.width / scale, height: newSize.height / scale), format: format)

        return renderer.image { ctx in
            let context = ctx.cgContext
            // Move origin to center of new canvas
            context.translateBy(x: newSize.width / scale / 2, y: newSize.height / scale / 2)
            context.rotate(by: radians)
            // Draw image centered on origin
            let drawRect = CGRect(
                x: -originalSize.width / scale / 2,
                y: -originalSize.height / scale / 2,
                width: originalSize.width / scale,
                height: originalSize.height / scale
            )
            draw(in: drawRect)
        }
    }

    /// Returns a horizontally mirrored copy, preserving scale.
    func fcl_flippedHorizontally() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let context = ctx.cgContext
            context.translateBy(x: size.width, y: 0)
            context.scaleBy(x: -1, y: 1)
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Returns a copy center-cropped to the given aspect ratio.
    /// For `.free`, the original image is returned unchanged.
    func fcl_centerCropped(aspect: FCLMediaEditCropAspect) -> UIImage {
        guard let ratio = aspect.ratio else { return self }

        let imageWidth = size.width
        let imageHeight = size.height
        let imageRatio = imageWidth / imageHeight

        let cropRect: CGRect
        if imageRatio > ratio {
            // Image is wider than target: crop sides
            let cropWidth = imageHeight * ratio
            cropRect = CGRect(
                x: (imageWidth - cropWidth) / 2,
                y: 0,
                width: cropWidth,
                height: imageHeight
            )
        } else if imageRatio < ratio {
            // Image is taller than target: crop top/bottom
            let cropHeight = imageWidth / ratio
            cropRect = CGRect(
                x: 0,
                y: (imageHeight - cropHeight) / 2,
                width: imageWidth,
                height: cropHeight
            )
        } else {
            return self
        }

        let scaledCropRect = CGRect(
            x: cropRect.origin.x * scale,
            y: cropRect.origin.y * scale,
            width: cropRect.width * scale,
            height: cropRect.height * scale
        )

        guard let cgImage = self.cgImage,
              let croppedCGImage = cgImage.cropping(to: scaledCropRect) else {
            return self
        }

        return UIImage(cgImage: croppedCGImage, scale: scale, orientation: imageOrientation)
    }

    /// Applies all edits in the given state sequentially: rotate → flip → crop.
    func fcl_applying(_ state: FCLMediaEditState) -> UIImage {
        var img = self
        img = img.fcl_rotated(steps: state.rotationSteps)
        if state.flippedHorizontally { img = img.fcl_flippedHorizontally() }
        img = img.fcl_centerCropped(aspect: state.cropAspect)
        return img
    }
}

// MARK: - Previews

#if DEBUG
struct FCLMediaEditorView_Previews: PreviewProvider {
    static var previews: some View {
        FCLMediaEditorPreviewWrapper()
            .previewDisplayName("Editor — Default State")

        FCLMediaEditorRotatedPreviewWrapper()
            .previewDisplayName("Editor — Rotated + Flipped")
    }
}

private struct FCLMediaEditorPreviewWrapper: View {
    var body: some View {
        let placeholder = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.white,
                .font: UIFont.boldSystemFont(ofSize: 32)
            ]
            ("Sample" as NSString).draw(at: CGPoint(x: 140, y: 130), withAttributes: attrs)
        }
        FCLMediaEditorView(
            sourceImage: placeholder,
            onConfirm: { _, _ in },
            onCancel: {}
        )
    }
}

private struct FCLMediaEditorRotatedPreviewWrapper: View {
    var body: some View {
        let placeholder = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 600)).image { ctx in
            UIColor.systemGreen.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 600))
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.white,
                .font: UIFont.boldSystemFont(ofSize: 28)
            ]
            ("Portrait" as NSString).draw(at: CGPoint(x: 130, y: 280), withAttributes: attrs)
        }
        FCLMediaEditorView(
            sourceImage: placeholder,
            initialState: FCLMediaEditState(rotationSteps: 1, flippedHorizontally: true, cropAspect: .square),
            onConfirm: { _, _ in },
            onCancel: {}
        )
    }
}
#endif
#endif
