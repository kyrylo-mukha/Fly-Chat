#if canImport(UIKit)
import AVFoundation
import Combine
import SwiftUI
import UIKit

// MARK: - FCLAttachmentPreviewScreen

/// Telegram-style attachment preview shown after the user captures or selects
/// one or more assets.
///
/// The layout is a vertical stack:
/// 1. Media preview area (horizontal pager between assets).
/// 2. Thumbnail carousel (only when there are 2+ assets), centered with
///    Photos-like parallax.
/// 3. Input row: expanding caption field + send button.
/// 4. Edit toolbar row: rotate/crop + markup stubs.
/// 5. Optional top-right "+" add-more button when the origin was the camera.
///
/// Keyboard behavior:
/// - Focusing the caption field dims the background slightly and glides the
///   send button into the text-field row via `matchedGeometryEffect`.
/// - Tapping any non-interactive area or swiping down dismisses the keyboard
///   and returns to the baseline layout.
/// - The caption field rises smoothly with the keyboard using SwiftUI's
///   built-in keyboard-avoidance (the media area opts out via
///   `.ignoresSafeArea(.keyboard)` so only the bottom cluster moves).
///
/// The screen does not animate its own dismissal — callers decide when to
/// dismiss the containing modal via the supplied `onSend` / `onCancel` hooks.
@MainActor
struct FCLAttachmentPreviewScreen: View {
    // MARK: Inputs

    @ObservedObject var presenter: FCLAttachmentPickerPresenter
    @Binding var captionText: String
    /// Attachments to render. Supplied by the caller so the screen can work for
    /// both camera and gallery origins without reading presenter internals.
    let attachments: [FCLAttachment]
    /// When true, the add-more button is shown in the top-right and invokes
    /// ``onAddMore``.
    let showsAddMore: Bool
    /// Chat input's configured max visible line count, fed through the delegate
    /// to compute this screen's effective max.
    let chatMaxLines: Int
    /// Optional delegate that can adjust the caption field's max lines.
    weak var inputDelegate: (any FCLAttachmentInputDelegate)?

    let onSend: () -> Void
    let onCancel: () -> Void
    let onAddMore: () -> Void
    /// Invoked when the user taps the rotate/crop toolbar button. Retained for
    /// backward compatibility with callers that want to observe tool entry;
    /// the in-place editor is hosted by this screen itself.
    let onRotateCrop: () -> Void
    /// Invoked when the user taps the markup toolbar button. See
    /// ``onRotateCrop`` for the same backward-compat note.
    let onMarkup: () -> Void
    /// Invoked after a tool commits its changes. Receives the asset ID, the
    /// committed bitmap, and a stable file URL for the burned-in result.
    /// Owners can use this to replace the underlying ``FCLAttachment`` (its
    /// `url` and thumbnail) so the send path picks up the edited file.
    let onImageEdited: (FCLAttachmentEditCommit, UIImage) -> Void

    // MARK: State

    @State private var selectedAssetID: UUID
    @State private var pageProgress: CGFloat
    @FocusState private var captionFocused: Bool

    /// In-place editor state machine. `.preview` shows the pager; `.editing`
    /// swaps the pager for the active editor and hides top bar, input row,
    /// carousel, and edit-toolbar row.
    @State private var editState: FCLAttachmentEditState = .preview
    /// Locally overridden bitmaps per asset (keyed by asset UUID). Populated
    /// when a tool commits; consumed by the pager to render the edited
    /// result immediately without waiting for the owner to update the
    /// underlying ``FCLAttachment`` URL.
    @State private var localEdits: [UUID: UIImage] = [:]
    /// Controls the full-exit confirmation dialog.
    @State private var showsExitConfirm: Bool = false

    // MARK: Init

    init(
        presenter: FCLAttachmentPickerPresenter,
        captionText: Binding<String>,
        attachments: [FCLAttachment],
        showsAddMore: Bool,
        chatMaxLines: Int,
        inputDelegate: (any FCLAttachmentInputDelegate)?,
        onSend: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onAddMore: @escaping () -> Void,
        onRotateCrop: @escaping () -> Void = {},
        onMarkup: @escaping () -> Void = {},
        onImageEdited: @escaping (FCLAttachmentEditCommit, UIImage) -> Void = { _, _ in }
    ) {
        self.presenter = presenter
        self._captionText = captionText
        self.attachments = attachments
        self.showsAddMore = showsAddMore
        self.chatMaxLines = chatMaxLines
        self.inputDelegate = inputDelegate
        self.onSend = onSend
        self.onCancel = onCancel
        self.onAddMore = onAddMore
        self.onRotateCrop = onRotateCrop
        self.onMarkup = onMarkup
        self.onImageEdited = onImageEdited
        let initialID = attachments.first?.id ?? UUID()
        _selectedAssetID = State(initialValue: initialID)
        _pageProgress = State(initialValue: 0)
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if isEditing {
                editorStack
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                mainStack
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))

                if captionFocused {
                    Color.black
                        .opacity(0.35)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture { captionFocused = false }
                        .allowsHitTesting(true)
                }

                topBar
            }
        }
        .statusBarHidden(true)
        .gesture(
            DragGesture(minimumDistance: 24, coordinateSpace: .local)
                .onEnded { value in
                    guard !isEditing,
                          value.translation.height > 60,
                          abs(value.translation.width) < 80
                    else { return }
                    if captionFocused {
                        // Keyboard up → swallow the drag to retract it
                        // first; the next downward swipe will fall through
                        // to the dismiss path below.
                        captionFocused = false
                        return
                    }
                    // Parity with the in-chat preview: when the keyboard is
                    // already down, a downward drag dismisses the entire
                    // preview screen instead of being a no-op.
                    onCancel()
                }
        )
        .animation(.easeOut(duration: 0.22), value: captionFocused)
        .animation(.easeInOut(duration: 0.22), value: editState)
        .onChange(of: attachments.isEmpty) { _, isEmpty in
            // When the staged asset set empties (send completed, or the user
            // removed the last capture/selection), drop every per-asset edit
            // so a subsequent use of this screen starts from a clean slate.
            if isEmpty { localEdits.removeAll() }
        }
        .onChange(of: attachments.map(\.id)) { _, newIDs in
            // Clamp `selectedAssetID` whenever the staged asset set shrinks
            // (or reorders) to a state that no longer contains the current
            // selection. Without this clamp, TabView's selection tag
            // resolves to nil on the next layout pass — `beginEditing` and
            // any `selectedAssetID`-driven lookup then operate on a missing
            // attachment, producing a blank pager and a no-op editor entry.
            // The clamp also prunes any local edit entries whose owning
            // asset no longer exists.
            if !newIDs.contains(selectedAssetID), let firstID = newIDs.first {
                selectedAssetID = firstID
                if let idx = newIDs.firstIndex(of: firstID) {
                    pageProgress = CGFloat(idx)
                }
            }
            let liveSet = Set(newIDs)
            localEdits = localEdits.filter { liveSet.contains($0.key) }
        }
        .onDisappear {
            // Final safety net: releasing the screen always drops the local
            // edits map. The presenter's matching dictionary is cleared by
            // the send / cancel code paths on the picker presenter itself.
            localEdits.removeAll()
        }
        .confirmationDialog(
            Text("Discard changes?"),
            isPresented: $showsExitConfirm,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { onCancel() }
            Button("Keep editing", role: .cancel) {}
        }
    }

    private var isEditing: Bool {
        if case .editing = editState { return true }
        return false
    }

    // MARK: - Dirty check

    /// The preview is "dirty" if the user has produced any committed edit,
    /// typed a caption, or has 2+ selected assets staged. Tapping the full
    /// exit button while dirty triggers a confirmation dialog.
    private var isFlowDirty: Bool {
        if !localEdits.isEmpty { return true }
        if !captionText.isEmpty { return true }
        if attachments.count >= 2 { return true }
        return false
    }

    /// Shared handler for the X button. In editing, first discards the tool
    /// (returns to `.preview`) and falls through to the preview exit rules.
    private func handleFullExit() {
        if isEditing {
            withAnimation(.easeInOut(duration: 0.22)) {
                editState = .preview
            }
            // After discarding the tool, re-evaluate against preview rules.
        }
        if isFlowDirty {
            showsExitConfirm = true
        } else {
            onCancel()
        }
    }

    // MARK: - Main Stack

    private var mainStack: some View {
        VStack(spacing: 0) {
            mediaPager
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if attachments.count >= 2 {
                FCLPreviewThumbCarousel(
                    items: carouselItems,
                    selectedAttachmentID: $selectedAssetID,
                    pageProgress: pageProgress
                )
                .padding(.vertical, 6)
            }

            if !captionFocused {
                editToolbar
                    .transition(.opacity)
            }
        }
        // Pin the whole vertical stack against the bottom edge so the media
        // pager, thumbnail carousel, and edit toolbar do not lift or re-layout
        // when the keyboard appears. Only the inputRow — hosted in the
        // safeAreaInset below — rises with the keyboard.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            inputRow
        }
    }

    // MARK: - Media Pager

    private var mediaPager: some View {
        Group {
            if attachments.isEmpty {
                Color.black
            } else {
                TabView(selection: $selectedAssetID) {
                    ForEach(attachments) { attachment in
                        FCLAttachmentPreviewPage(attachment: attachment)
                            .tag(attachment.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: selectedAssetID) { _, newID in
                    if let idx = attachments.firstIndex(where: { $0.id == newID }) {
                        pageProgress = CGFloat(idx)
                    }
                }
            }
        }
        .onTapGesture {
            if captionFocused { captionFocused = false }
        }
    }

    private var carouselItems: [(messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment)] {
        let msgID = UUID()
        return attachments.enumerated().map { idx, att in
            (messageID: msgID, attachmentIndex: idx, attachment: att)
        }
    }

    // MARK: - Input Row

    private var inputRow: some View {
        let effectiveMax = fclAttachmentInputEffectiveLines(
            chatMax: chatMaxLines,
            delta: inputDelegate?.attachmentInputLineCountDelta(chatMaxLines: chatMaxLines) ?? -3
        )

        return VStack(spacing: 6) {
            // "+" add-more sits above the text field, trailing. Only visible
            // when `showsAddMore` and not focused (avoid clutter while typing).
            if showsAddMore && !captionFocused {
                HStack {
                    Spacer()
                    FCLGlassIconButton(
                        systemImage: "plus",
                        size: 44,
                        action: onAddMore
                    )
                    .accessibilityLabel("Add more")
                }
                .padding(.horizontal, 16)
                .transition(.opacity)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Add a caption…", text: $captionText, axis: .vertical)
                    .lineLimit(1...effectiveMax)
                    .font(.system(size: 16))
                    .focused($captionFocused)
                    .submitLabel(.return)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .padding(.trailing, 48) // persistent reserved space for the glide send button
                    // Use 0.22 white when focused so the caption field reads
                    // against the dim overlay instead of dissolving into it;
                    // idle state stays at 0.14 to match the unfocused chrome
                    // weight.
                    .background(Color.white.opacity(captionFocused ? 0.22 : 0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(alignment: .bottomTrailing) {
                // Single persistent send button. Glides between the edit-toolbar
                // row (unfocused) and the text-field row (focused) via a
                // vertical offset. Keeping one instance mounted avoids the
                // branch-and-reinsert jump that matchedGeometryEffect produces
                // when paired with `transition(.identity)`.
                sendButton
                    .padding(.trailing, 16)
                    .padding(.bottom, captionFocused ? 10 : 12)
                    .offset(y: captionFocused ? 0 : -Self.editToolbarHeight)
                    .animation(.easeOut(duration: 0.22), value: captionFocused)
            }
        }
    }

    /// Approximate height of the edit toolbar row (icon frame + bottom
    /// padding). Used to drive the send button's glide offset.
    private static let editToolbarHeight: CGFloat = 52

    /// Drop caption focus *before* invoking `onSend`. The sheet
    /// owner reacts to send by dismissing the picker modal; if the
    /// `@FocusState` is still `true` at that moment, SwiftUI's focus
    /// cascade can re-resolve focus on a transient UIResponder during
    /// the dismiss transaction, which momentarily re-shows the keyboard
    /// in the chat view behind the cover. Forcing focus to `false` first
    /// guarantees the keyboard is already torn down before dismissal
    /// begins, eliminating the post-send keyboard flash.
    private func performSend() {
        if captionFocused { captionFocused = false }
        onSend()
    }

    private var sendButton: some View {
        FCLGlassIconButton(
            systemImage: "paperplane.fill",
            size: 44,
            tint: FCLAppearanceDefaults.senderBubbleColor,
            action: performSend
        )
        .accessibilityLabel("Send")
    }

    // MARK: - Edit Toolbar

    private var editToolbar: some View {
        FCLGlassToolbar(placement: .bottom) {
            FCLGlassIconButton(
                systemImage: "crop.rotate",
                size: 44,
                action: { beginEditing(tool: .rotateCrop) }
            )
            .accessibilityLabel("Rotate and crop")

            FCLGlassIconButton(
                systemImage: "scribble",
                size: 44,
                action: { beginEditing(tool: .markup) }
            )
            .accessibilityLabel("Markup")

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Editor hosting

    @ViewBuilder
    private var editorStack: some View {
        if case .editing(let tool, let assetID) = editState,
           let attachment = attachments.first(where: { $0.id == assetID }),
           let image = sourceImage(for: attachment) {
            switch tool {
            case .rotateCrop:
                FCLRotateCropEditor(
                    original: image,
                    onCommit: { edited in
                        finishEditing(commit: true, tool: tool, assetID: assetID, image: edited)
                    },
                    onCancel: {
                        finishEditing(commit: false, tool: tool, assetID: assetID, image: image)
                    }
                )
                // Force a fresh editor identity per asset so the editor's
                // @StateObject history cannot bleed across different source
                // images. See FCLRotateCropEditor.HistoryBox.
                .id(assetID)
            case .markup:
                FCLMarkupEditor(
                    original: image,
                    onCommit: { edited in
                        finishEditing(commit: true, tool: tool, assetID: assetID, image: edited)
                    },
                    onCancel: {
                        finishEditing(commit: false, tool: tool, assetID: assetID, image: image)
                    }
                )
                .id(assetID)
            }
        } else {
            // Defensive fallback: unknown state → pop back to preview.
            Color.black.onAppear { editState = .preview }
        }
    }

    private func beginEditing(tool: FCLAttachmentEditTool) {
        guard let current = attachments.first(where: { $0.id == selectedAssetID }) ?? attachments.first else { return }
        if captionFocused { captionFocused = false }
        withAnimation(.easeInOut(duration: 0.22)) {
            editState = .editing(tool: tool, assetID: current.id)
        }
        switch tool {
        case .rotateCrop: onRotateCrop()
        case .markup: onMarkup()
        }
    }

    private func finishEditing(commit: Bool, tool: FCLAttachmentEditTool, assetID: UUID, image: UIImage) {
        if commit {
            localEdits[assetID] = image
            if let url = FCLAttachmentEditScratch.writeJPEG(image, assetID: assetID) {
                let commitInfo = FCLAttachmentEditCommit(assetID: assetID, tool: tool, fileURL: url)
                onImageEdited(commitInfo, image)
            }
            // Mirror into the presenter's String-keyed cache so existing
            // send-path lookups see the edit too.
            presenter.setEditedImage(image, for: assetID.uuidString)
        }
        withAnimation(.easeInOut(duration: 0.22)) {
            editState = .preview
        }
    }

    /// Returns the current best source image for `attachment`: the most
    /// recently committed local edit wins; otherwise the presenter's cached
    /// edited bitmap; otherwise the attachment's thumbnail or its raw file.
    private func sourceImage(for attachment: FCLAttachment) -> UIImage? {
        if let edited = localEdits[attachment.id] { return edited }
        if let cached = presenter.editedImage(for: attachment.id.uuidString) { return cached }
        if let thumb = attachment.thumbnailImage { return thumb }
        if attachment.type == .image,
           let data = try? Data(contentsOf: attachment.url),
           let img = UIImage(data: data) {
            return img
        }
        return nil
    }

    // MARK: - Top Bar

    private var topBar: some View {
        FCLGlassToolbar(placement: .top) {
            FCLGlassIconButton(
                systemImage: "xmark",
                size: 44,
                action: handleFullExit
            )
            .accessibilityLabel("Cancel")

            Spacer()
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

// MARK: - FCLAttachmentPreviewPage

/// Renders a single attachment (image or video thumbnail w/ play affordance)
/// inside the preview pager. Images use aspect-fit to match system Photos
/// behavior. Video playback is wired in a follow-up task; for now the first
/// frame is shown with a play icon overlay.
@MainActor
private struct FCLAttachmentPreviewPage: View {
    let attachment: FCLAttachment

    @State private var loadedImage: UIImage?

    var body: some View {
        ZStack {
            Color.black

            if let image = effectiveImage {
                // Wrap the rendered bitmap in a UIScrollView so each
                // page supports pinch-zoom and double-tap-zoom (min 1.0,
                // max 3.0). When zoomScale > 1 the inner scroll view's pan
                // recognizer naturally outranks the surrounding TabView's
                // paging recognizer (the TabView only wins when the inner
                // content is already at its leading/trailing edge), giving
                // Photos-like behavior without an explicit paging gate.
                FCLZoomableImageView(image: image)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .tint(.white)
            }

            if attachment.type == .video {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 4)
                    .allowsHitTesting(false)
            }
        }
        .task(id: attachment.id) {
            await loadIfNeeded()
        }
    }

    private var effectiveImage: UIImage? {
        if let thumb = attachment.thumbnailImage { return thumb }
        return loadedImage
    }

    private func loadIfNeeded() async {
        guard loadedImage == nil, attachment.thumbnailImage == nil else { return }
        switch attachment.type {
        case .image:
            if let data = try? Data(contentsOf: attachment.url), let img = UIImage(data: data) {
                loadedImage = img
            }
        case .video:
            loadedImage = await Self.firstFrame(of: attachment.url)
        case .file:
            break
        }
    }

    private static func firstFrame(of url: URL) async -> UIImage? {
        await Task.detached { () -> UIImage? in
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            // Cap the produced bitmap so first-frame decoding never
            // hitches on oversized source media (e.g. 4K HDR clips). The
            // generator scales aspect-fit into this bounding box before
            // returning the CGImage.
            generator.maximumSize = CGSize(width: 1920, height: 1920)
            let time = CMTime(seconds: 0.1, preferredTimescale: 600)
            do {
                let cg = try generator.copyCGImage(at: time, actualTime: nil)
                return UIImage(cgImage: cg)
            } catch {
                return nil
            }
        }.value
    }
}

// MARK: - FCLZoomableImageView

/// SwiftUI wrapper around a `UIScrollView` that hosts a single
/// `UIImageView` and supports pinch + double-tap zoom in the range
/// `1.0 ... 3.0`. The view is intentionally simple: it does not own any
/// per-asset state beyond what the contained `UIImageView` carries, so
/// `FCLAttachmentPreviewScreen`'s pager can reuse the same SwiftUI surface
/// across pages without leaking zoom between assets (each page mounts a
/// fresh representable identity via the parent `ForEach`).
@MainActor
private struct FCLZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 3.0
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        // Match Photos: no rubber-banding off the leading/trailing edges
        // when at min zoom, so horizontal pans cleanly hand off to the
        // surrounding TabView pager.
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = false

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        // Pin image view to the scroll view's content layout guide so it
        // tracks the scroll view's bounds and zooms cleanly.
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        // Double-tap toggles between min zoom and 2× centered on the tap.
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        // Idempotent: only swap the image when the source bitmap actually
        // changed. SwiftUI may re-invoke `updateUIView` for unrelated
        // ancestor invalidations; guarding here prevents the zoom scale
        // from being reset on every parent re-render.
        if context.coordinator.imageView?.image !== image {
            context.coordinator.imageView?.image = image
            uiView.zoomScale = uiView.minimumZoomScale
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let target: CGFloat = min(scrollView.maximumZoomScale, 2.0)
                let point = recognizer.location(in: imageView)
                let scrollSize = scrollView.bounds.size
                let width = scrollSize.width / target
                let height = scrollSize.height / target
                let rect = CGRect(
                    x: point.x - width / 2,
                    y: point.y - height / 2,
                    width: width,
                    height: height
                )
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
@MainActor
private func previewAttachment(index: Int, video: Bool = false) -> FCLAttachment {
    FCLAttachment(
        id: UUID(),
        type: video ? .video : .image,
        url: URL(string: "file:///tmp/preview_\(index).jpg")!,
        fileName: "preview_\(index).jpg"
    )
}

@MainActor
private struct FCLAttachmentPreviewScreenPreviewWrapper: View {
    let attachments: [FCLAttachment]
    let showsAddMore: Bool
    let longCaption: Bool

    @StateObject private var presenter = FCLAttachmentPickerPresenter(delegate: nil) { _, _ in }
    @State private var caption: String = ""

    var body: some View {
        FCLAttachmentPreviewScreen(
            presenter: presenter,
            captionText: $caption,
            attachments: attachments,
            showsAddMore: showsAddMore,
            chatMaxLines: 6,
            inputDelegate: nil,
            onSend: {},
            onCancel: {},
            onAddMore: {},
            onRotateCrop: {},
            onMarkup: {}
        )
        .onAppear {
            if longCaption {
                caption = "This is a longer caption that spans multiple lines to demonstrate the expanding text field behavior in the attachment preview screen."
            }
        }
    }
}

#Preview("Single asset — keyboard closed") {
    FCLAttachmentPreviewScreenPreviewWrapper(
        attachments: [previewAttachment(index: 0)],
        showsAddMore: false,
        longCaption: false
    )
}

#Preview("Three assets — keyboard closed") {
    FCLAttachmentPreviewScreenPreviewWrapper(
        attachments: (0 ..< 3).map { previewAttachment(index: $0) },
        showsAddMore: true,
        longCaption: false
    )
}

#Preview("Three assets — long caption (multi-line)") {
    FCLAttachmentPreviewScreenPreviewWrapper(
        attachments: (0 ..< 3).map { previewAttachment(index: $0) },
        showsAddMore: true,
        longCaption: true
    )
}

#Preview("Single video asset") {
    FCLAttachmentPreviewScreenPreviewWrapper(
        attachments: [previewAttachment(index: 0, video: true)],
        showsAddMore: false,
        longCaption: false
    )
}

#Preview("Three assets — with add more button") {
    FCLAttachmentPreviewScreenPreviewWrapper(
        attachments: (0 ..< 3).map { previewAttachment(index: $0) },
        showsAddMore: true,
        longCaption: false
    )
}
#endif
#endif
