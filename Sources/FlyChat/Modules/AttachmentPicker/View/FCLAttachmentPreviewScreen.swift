#if canImport(UIKit)
import AVFoundation
import Combine
import SwiftUI
import UIKit

// MARK: - FCLAttachmentPreviewScreen

/// Telegram-style attachment preview: media pager, optional thumbnail carousel,
/// caption input, and edit toolbar. Callers drive dismissal via `onSend`/`onCancel`.
@MainActor
struct FCLAttachmentPreviewScreen: View {
    // MARK: Inputs

    @ObservedObject var presenter: FCLAttachmentPickerPresenter
    @Binding var captionText: String
    let attachments: [FCLAttachment]
    let showsAddMore: Bool
    let chatMaxLines: Int
    weak var inputDelegate: (any FCLAttachmentInputDelegate)?

    let onSend: () -> Void
    let onCancel: () -> Void
    let onAddMore: () -> Void
    /// Invoked when the user enters the rotate/crop tool (backward-compat hook).
    let onRotateCrop: () -> Void
    /// Invoked when the user enters the markup tool (backward-compat hook).
    let onMarkup: () -> Void
    /// Invoked after a tool commits changes so callers can refresh the attachment URL.
    let onImageEdited: (FCLAttachmentEditCommit, UIImage) -> Void

    // MARK: State

    @State private var selectedAssetID: UUID
    @State private var pageProgress: CGFloat
    @FocusState private var captionFocused: Bool

    @State private var editState: FCLAttachmentEditState = .preview
    /// Per-asset edited bitmaps; updated on tool commit, consumed by the pager.
    @State private var localEdits: [UUID: UIImage] = [:]
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
                        captionFocused = false
                        return
                    }
                    onCancel()
                }
        )
        .animation(.easeOut(duration: 0.22), value: captionFocused)
        .animation(.easeInOut(duration: 0.22), value: editState)
        .onChange(of: attachments.isEmpty) { _, isEmpty in
            if isEmpty { localEdits.removeAll() }
        }
        .onChange(of: attachments.map(\.id)) { _, newIDs in
            // Clamp selectedAssetID when the staged set shrinks so TabView's
            // selection tag never resolves to nil on the next layout pass.
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

    /// Returns `true` when the exit button should trigger a confirmation dialog.
    private var isFlowDirty: Bool {
        if !localEdits.isEmpty { return true }
        if !captionText.isEmpty { return true }
        if attachments.count >= 2 { return true }
        return false
    }

    private func handleFullExit() {
        if isEditing {
            withAnimation(.easeInOut(duration: 0.22)) {
                editState = .preview
            }
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
        // Only the inputRow (in safeAreaInset) rises with the keyboard;
        // the pager and carousel stay pinned to the bottom edge.
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
                    .padding(.trailing, 48)
                    .background(Color.white.opacity(captionFocused ? 0.22 : 0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(alignment: .bottomTrailing) {
                sendButton
                    .padding(.trailing, 16)
                    .padding(.bottom, captionFocused ? 10 : 12)
                    .offset(y: captionFocused ? 0 : -Self.editToolbarHeight)
                    .animation(.easeOut(duration: 0.22), value: captionFocused)
            }
        }
    }

    /// Approximate edit toolbar row height; drives the send button's glide offset.
    private static let editToolbarHeight: CGFloat = 52

    /// Drops caption focus before invoking `onSend` to prevent a post-dismiss
    /// keyboard flash caused by SwiftUI re-resolving focus during the dismiss transaction.
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
            presenter.setEditedImage(image, for: assetID.uuidString)
        }
        withAnimation(.easeInOut(duration: 0.22)) {
            editState = .preview
        }
    }

    /// Returns the best source image for `attachment`: local edit > presenter cache > thumbnail > raw file.
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

/// Renders a single attachment inside the preview pager. Videos show the first
/// frame with a play icon overlay.
@MainActor
private struct FCLAttachmentPreviewPage: View {
    let attachment: FCLAttachment

    @State private var loadedImage: UIImage?

    var body: some View {
        ZStack {
            Color.black

            if let image = effectiveImage {
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

/// SwiftUI wrapper around a `UIScrollView` with pinch and double-tap zoom (1.0–3.0).
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
        // Disable horizontal bounce at min zoom so panning hands off cleanly to the TabView pager.
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = false

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
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
