#if canImport(UIKit)
import SwiftUI
import UIKit

// MARK: - FCLRotateCropAspect

/// Aspect-ratio presets available in the rotate/crop editor.
enum FCLRotateCropAspect: CaseIterable, Hashable {
    case free
    case square
    case fourThree
    case sixteenNine

    var label: String {
        switch self {
        case .free: return "Free"
        case .square: return "1:1"
        case .fourThree: return "4:3"
        case .sixteenNine: return "16:9"
        }
    }

    /// width / height, or `nil` for free.
    var ratio: CGFloat? {
        switch self {
        case .free: return nil
        case .square: return 1
        case .fourThree: return 4.0 / 3.0
        case .sixteenNine: return 16.0 / 9.0
        }
    }
}

// MARK: - FCLRotateCropEditor

/// In-place rotate/crop/flip editor. Heavy transforms run on a detached task
/// to keep the main thread responsive.
@MainActor
struct FCLRotateCropEditor: View {
    let original: UIImage

    let onCommit: (UIImage) -> Void
    let onCancel: () -> Void

    @StateObject private var historyBox: HistoryBox
    @State private var displayImage: UIImage
    @State private var aspect: FCLRotateCropAspect = .free
    @State private var rotationAngle: CGFloat = 0          // live slider value, degrees
    @State private var committedRotation: CGFloat = 0      // last snapshot angle
    @State private var cropRectUnit: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var isProcessing: Bool = false

    init(
        original: UIImage,
        onCommit: @escaping (UIImage) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.original = original
        self.onCommit = onCommit
        self.onCancel = onCancel
        let normalized = original.fcl_normalizedOrientation()
        _displayImage = State(initialValue: normalized)
        _historyBox = StateObject(wrappedValue: HistoryBox(initial: normalized))
    }

    var body: some View {
        VStack(spacing: 0) {
            imageArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)

            FCLAttachmentEditToolbar(
                title: "Rotate & Crop",
                canUndo: historyBox.history.canUndo,
                canRedo: historyBox.history.canRedo,
                onUndo: performUndo,
                onRedo: performRedo,
                onCancel: { onCancel() },
                onDone: commit
            ) {
                controls
            }
        }
        .background(Color.black.ignoresSafeArea())
        .disabled(isProcessing)
        .overlay {
            if isProcessing {
                ProgressView().tint(.white)
            }
        }
        .onDisappear {
            historyBox.history.reset()
        }
    }

    // MARK: - Image area (preview with crop overlay)

    private var imageArea: some View {
        GeometryReader { geo in
            ZStack {
                Image(uiImage: displayImage)
                    .resizable()
                    .scaledToFit()
                    .rotationEffect(.degrees(rotationAngle - committedRotation))
                    .frame(width: geo.size.width, height: geo.size.height)

                CropOverlay(cropRectUnit: $cropRectUnit, aspect: aspect, imageSize: geo.size)
                    .allowsHitTesting(true)
            }
        }
        .padding(12)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Button(action: flipHorizontal) {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                            .font(.system(size: 18))
                    Text("Flip H").font(.system(size: 11))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 48)
                }

                Button(action: flipVertical) {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down")
                            .font(.system(size: 18))
                        Text("Flip V").font(.system(size: 11))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 48)
                }

                Spacer()

                Picker("Aspect", selection: $aspect) {
                    ForEach(FCLRotateCropAspect.allCases, id: \.self) { a in
                        Text(a.label).tag(a)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                .onChange(of: aspect) { _, _ in
                    cropRectUnit = CGRect(x: 0, y: 0, width: 1, height: 1)
                }
            }

            HStack(spacing: 10) {
                Button(action: rotateLeft90) {
                    Image(systemName: "rotate.left")
                        .foregroundStyle(.white)
                        .font(.system(size: 18))
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("Rotate 90 degrees left")

                Slider(
                    value: $rotationAngle,
                    in: -45 ... 45,
                    step: 1,
                    onEditingChanged: { editing in
                        if !editing { commitRotationSnapshot() }
                    }
                )
                .tint(.white)

                Image(systemName: "rotate.right").foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    // MARK: - Actions

    private func flipHorizontal() {
        runTransform { img in img.fcl_flipped(horizontal: true) }
    }

    private func flipVertical() {
        runTransform { img in img.fcl_flipped(horizontal: false) }
    }

    private func rotateLeft90() {
        runTransform { img in img.fcl_rotated(radians: -.pi / 2) }
        rotationAngle = 0
        committedRotation = 0
    }

    private func commitRotationSnapshot() {
        let delta = rotationAngle - committedRotation
        guard abs(delta) > 0.5 else { return }
        let radians = delta * .pi / 180
        runTransform { img in img.fcl_rotated(radians: radians) }
        committedRotation = rotationAngle
    }

    private func performUndo() {
        if let snap = historyBox.history.undo() {
            displayImage = snap
            rotationAngle = 0
            committedRotation = 0
        }
    }

    private func performRedo() {
        if let snap = historyBox.history.redo() {
            displayImage = snap
            rotationAngle = 0
            committedRotation = 0
        }
    }

    private func commit() {
        commitRotationSnapshot()
        // Capture cropRectUnit on MainActor before entering the @Sendable closure.
        let cropRect = cropRectUnit
        runTransform(push: false) { img in
            img.fcl_cropped(to: cropRect)
        } completion: { final in
            onCommit(final)
        }
    }

    // MARK: - Processing pipeline

    private func runTransform(
        push: Bool = true,
        _ transform: @escaping @Sendable (UIImage) -> UIImage,
        completion: ((UIImage) -> Void)? = nil
    ) {
        let source = displayImage
        isProcessing = true
        Task { @MainActor in
            let result = await Self.applyTransform(transform, to: source)
            self.displayImage = result
            if push {
                self.historyBox.history.push(result)
            }
            self.isProcessing = false
            completion?(result)
        }
    }

    private static func applyTransform(
        _ transform: @escaping @Sendable (UIImage) -> UIImage,
        to source: UIImage
    ) async -> UIImage {
        await Task.detached(priority: .userInitiated) {
            transform(source)
        }.value
    }

    // MARK: - History box

    @MainActor
    final class HistoryBox: ObservableObject {
        let history: FCLAttachmentEditHistory

        init(initial: UIImage) {
            let h = FCLAttachmentEditHistory()
            h.push(initial)
            self.history = h
        }
    }
}

// MARK: - CropOverlay

@MainActor
private struct CropOverlay: View {
    @Binding var cropRectUnit: CGRect
    let aspect: FCLRotateCropAspect
    let imageSize: CGSize

    @State private var isDragging: Bool = false
    @State private var dragBaseRect: CGRect?

    private let cornerArmLength: CGFloat = 20
    private let cornerLineWidth: CGFloat = 2
    private let edgeHandleLength: CGFloat = 32
    private let edgeHandleThickness: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(
                x: cropRectUnit.origin.x * geo.size.width,
                y: cropRectUnit.origin.y * geo.size.height,
                width: cropRectUnit.size.width * geo.size.width,
                height: cropRectUnit.size.height * geo.size.height
            )
            ZStack {
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                if isDragging {
                    thirdsGrid(in: rect)
                }

                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: max(0, rect.width - 40), height: max(0, rect.height - 40))
                    .position(x: rect.midX, y: rect.midY)
                    .gesture(panGesture(containerSize: geo.size))

                ForEach(Corner.allCases, id: \.self) { corner in
                    CornerMark(
                        corner: corner,
                        armLength: cornerArmLength,
                        lineWidth: cornerLineWidth
                    )
                    .frame(width: cornerArmLength, height: cornerArmLength)
                    .position(cornerPoint(corner, in: rect))
                    .contentShape(Rectangle().inset(by: -12))
                    .gesture(cornerDragGesture(for: corner, containerSize: geo.size))
                }

                ForEach(Edge.allCases, id: \.self) { edge in
                    edgeHandle(edge: edge)
                        .position(edgePoint(edge, in: rect))
                        .contentShape(Rectangle().inset(by: -10))
                        .gesture(edgeDragGesture(for: edge, containerSize: geo.size))
                }
            }
        }
    }

    // MARK: Subviews

    @ViewBuilder
    private func thirdsGrid(in rect: CGRect) -> some View {
        let xs = [rect.minX + rect.width / 3, rect.minX + rect.width * 2 / 3]
        let ys = [rect.minY + rect.height / 3, rect.minY + rect.height * 2 / 3]
        ZStack {
            ForEach(xs, id: \.self) { x in
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 0.5, height: rect.height)
                    .position(x: x, y: rect.midY)
            }
            ForEach(ys, id: \.self) { y in
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: rect.width, height: 0.5)
                    .position(x: rect.midX, y: y)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func edgeHandle(edge: Edge) -> some View {
        switch edge {
        case .top, .bottom:
            Rectangle()
                .fill(Color.white)
                .frame(width: edgeHandleLength, height: edgeHandleThickness)
                .cornerRadius(edgeHandleThickness / 2)
        case .leading, .trailing:
            Rectangle()
                .fill(Color.white)
                .frame(width: edgeHandleThickness, height: edgeHandleLength)
                .cornerRadius(edgeHandleThickness / 2)
        }
    }

    // MARK: Geometry helpers

    private func cornerPoint(_ corner: Corner, in rect: CGRect) -> CGPoint {
        switch corner {
        case .topLeft:     return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:    return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:  return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private func edgePoint(_ edge: Edge, in rect: CGRect) -> CGPoint {
        switch edge {
        case .top:      return CGPoint(x: rect.midX, y: rect.minY)
        case .bottom:   return CGPoint(x: rect.midX, y: rect.maxY)
        case .leading:  return CGPoint(x: rect.minX, y: rect.midY)
        case .trailing: return CGPoint(x: rect.maxX, y: rect.midY)
        }
    }

    // MARK: Gestures

    private func cornerDragGesture(for corner: Corner, containerSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDragging { isDragging = true }
                if dragBaseRect == nil { dragBaseRect = cropRectUnit }
                let base = dragBaseRect ?? cropRectUnit
                var r = base
                let dx = value.translation.width / containerSize.width
                let dy = value.translation.height / containerSize.height
                switch corner {
                case .topLeft:
                    r.origin.x = clampUnit(base.origin.x + dx, max: base.maxX - 0.1)
                    r.origin.y = clampUnit(base.origin.y + dy, max: base.maxY - 0.1)
                    r.size.width = base.maxX - r.origin.x
                    r.size.height = base.maxY - r.origin.y
                case .topRight:
                    let newMaxX = clampUnit(base.maxX + dx, min: base.origin.x + 0.1, max: 1)
                    r.origin.y = clampUnit(base.origin.y + dy, max: base.maxY - 0.1)
                    r.size.width = newMaxX - r.origin.x
                    r.size.height = base.maxY - r.origin.y
                case .bottomLeft:
                    let newMaxY = clampUnit(base.maxY + dy, min: base.origin.y + 0.1, max: 1)
                    r.origin.x = clampUnit(base.origin.x + dx, max: base.maxX - 0.1)
                    r.size.width = base.maxX - r.origin.x
                    r.size.height = newMaxY - r.origin.y
                case .bottomRight:
                    let newMaxX = clampUnit(base.maxX + dx, min: base.origin.x + 0.1, max: 1)
                    let newMaxY = clampUnit(base.maxY + dy, min: base.origin.y + 0.1, max: 1)
                    r.size.width = newMaxX - r.origin.x
                    r.size.height = newMaxY - r.origin.y
                }
                cropRectUnit = applyAspect(r)
            }
            .onEnded { _ in
                isDragging = false
                dragBaseRect = nil
            }
    }

    private func edgeDragGesture(for edge: Edge, containerSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDragging { isDragging = true }
                if dragBaseRect == nil { dragBaseRect = cropRectUnit }
                let base = dragBaseRect ?? cropRectUnit
                var r = base
                let dx = value.translation.width / containerSize.width
                let dy = value.translation.height / containerSize.height
                switch edge {
                case .top:
                    r.origin.y = clampUnit(base.origin.y + dy, max: base.maxY - 0.1)
                    r.size.height = base.maxY - r.origin.y
                case .bottom:
                    let newMaxY = clampUnit(base.maxY + dy, min: base.origin.y + 0.1, max: 1)
                    r.size.height = newMaxY - r.origin.y
                case .leading:
                    r.origin.x = clampUnit(base.origin.x + dx, max: base.maxX - 0.1)
                    r.size.width = base.maxX - r.origin.x
                case .trailing:
                    let newMaxX = clampUnit(base.maxX + dx, min: base.origin.x + 0.1, max: 1)
                    r.size.width = newMaxX - r.origin.x
                }
                cropRectUnit = applyAspect(r)
            }
            .onEnded { _ in
                isDragging = false
                dragBaseRect = nil
            }
    }

    private func panGesture(containerSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDragging { isDragging = true }
                if dragBaseRect == nil { dragBaseRect = cropRectUnit }
                let base = dragBaseRect ?? cropRectUnit
                let dx = value.translation.width / containerSize.width
                let dy = value.translation.height / containerSize.height
                var r = base
                r.origin.x = clampUnit(base.origin.x + dx, max: 1 - base.size.width)
                r.origin.y = clampUnit(base.origin.y + dy, max: 1 - base.size.height)
                cropRectUnit = r
            }
            .onEnded { _ in
                isDragging = false
                dragBaseRect = nil
            }
    }

    private func applyAspect(_ r: CGRect) -> CGRect {
        guard let ratio = aspect.ratio else { return r }
        var out = r
        let newH = out.size.width / ratio
        if out.origin.y + newH <= 1 {
            out.size.height = newH
        } else {
            out.size.height = 1 - out.origin.y
            out.size.width = out.size.height * ratio
        }
        return out
    }

    private func clampUnit(_ value: CGFloat, min lower: CGFloat = 0, max upper: CGFloat = 1) -> CGFloat {
        Swift.max(lower, Swift.min(upper, value))
    }

    enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }
    enum Edge: CaseIterable { case top, bottom, leading, trailing }
}

// MARK: - CornerMark

/// Draws an L-shaped corner mark; `corner` selects which quadrant the arms point into.
@MainActor
private struct CornerMark: View {
    let corner: CropOverlay.Corner
    let armLength: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            let w = size.width
            let h = size.height
            switch corner {
            case .topLeft:
                path.move(to: CGPoint(x: 0, y: h)); path.addLine(to: CGPoint(x: 0, y: 0))
                path.move(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: w, y: 0))
            case .topRight:
                path.move(to: CGPoint(x: w, y: h)); path.addLine(to: CGPoint(x: w, y: 0))
                path.move(to: CGPoint(x: w, y: 0)); path.addLine(to: CGPoint(x: 0, y: 0))
            case .bottomLeft:
                path.move(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: 0, y: h))
                path.move(to: CGPoint(x: 0, y: h)); path.addLine(to: CGPoint(x: w, y: h))
            case .bottomRight:
                path.move(to: CGPoint(x: w, y: 0)); path.addLine(to: CGPoint(x: w, y: h))
                path.move(to: CGPoint(x: w, y: h)); path.addLine(to: CGPoint(x: 0, y: h))
            }
            ctx.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: lineWidth, lineCap: .square))
            _ = armLength
        }
    }
}

// MARK: - UIImage helpers

extension UIImage {
    /// Returns a copy with `.up` orientation so pixel-level transforms operate on
    /// a predictable coordinate system.
    func fcl_normalizedOrientation() -> UIImage {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Flips horizontally (mirror left/right) or vertically (mirror up/down).
    func fcl_flipped(horizontal: Bool) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            if horizontal {
                cg.translateBy(x: size.width, y: 0)
                cg.scaleBy(x: -1, y: 1)
            } else {
                cg.translateBy(x: 0, y: size.height)
                cg.scaleBy(x: 1, y: -1)
            }
            if let cgImage {
                cg.draw(cgImage, in: CGRect(origin: .zero, size: size))
            }
        }
    }

    /// Rotates the receiver by `radians` around its center, growing the
    /// canvas so the rotated content fits without clipping.
    func fcl_rotated(radians: CGFloat) -> UIImage {
        let newSize = CGRect(origin: .zero, size: size)
            .applying(CGAffineTransform(rotationAngle: radians))
            .integral
            .size
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            cg.rotate(by: radians)
            self.draw(in: CGRect(
                x: -size.width / 2,
                y: -size.height / 2,
                width: size.width,
                height: size.height
            ))
        }
    }

    /// Crops to the unit-space `rect` (values 0–1) relative to the image.
    func fcl_cropped(to unitRect: CGRect) -> UIImage {
        guard let cgImage else { return self }
        let clamped = CGRect(
            x: max(0, min(1, unitRect.origin.x)),
            y: max(0, min(1, unitRect.origin.y)),
            width: max(0.01, min(1, unitRect.size.width)),
            height: max(0.01, min(1, unitRect.size.height))
        )
        let pixelRect = CGRect(
            x: clamped.origin.x * CGFloat(cgImage.width),
            y: clamped.origin.y * CGFloat(cgImage.height),
            width: clamped.size.width * CGFloat(cgImage.width),
            height: clamped.size.height * CGFloat(cgImage.height)
        ).integral
        guard let cropped = cgImage.cropping(to: pixelRect) else { return self }
        return UIImage(cgImage: cropped, scale: scale, orientation: .up)
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
private func rotateCropPreviewImage() -> UIImage {
    let size = CGSize(width: 320, height: 200)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { ctx in
        UIColor.systemTeal.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
        UIColor.white.setFill()
        ctx.fill(CGRect(x: 40, y: 40, width: 120, height: 80))
        UIColor.systemOrange.setFill()
        ctx.fill(CGRect(x: 200, y: 80, width: 80, height: 80))
    }
}

#Preview("Rotate/Crop — idle") {
    FCLRotateCropEditor(
        original: rotateCropPreviewImage(),
        onCommit: { _ in },
        onCancel: {}
    )
}

#Preview("Rotate/Crop — SF symbol image") {
    FCLRotateCropEditor(
        original: UIImage(systemName: "photo.artframe")!
            .withTintColor(.white, renderingMode: .alwaysOriginal),
        onCommit: { _ in },
        onCancel: {}
    )
}
#endif
#endif
