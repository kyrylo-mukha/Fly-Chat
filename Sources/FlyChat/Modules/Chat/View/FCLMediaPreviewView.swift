#if canImport(UIKit)
import Photos
import SwiftUI
import UIKit

// MARK: - Collection Safe Subscript

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - FCLTransparentFullScreenCover

/// Presents `content` over the current view as a transparent full-screen overlay.
/// Unlike `.fullScreenCover`, the backing hosting controller has a clear background,
/// so the underlying chat remains visible during drag-to-dismiss.
///
/// The helper tracks a single hosting controller it owns via the coordinator. It only
/// dismisses that specific controller; it never touches unrelated `presentedViewController`
/// modals (e.g., sheets presented from ancestors), which previously caused accidental
/// dismissal of the attachment picker sheet when this helper re-evaluated.
struct FCLTransparentFullScreenCover<CoverContent: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let content: () -> CoverContent

    final class Coordinator {
        weak var ownedHost: UIViewController?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        vc.view.isUserInteractionEnabled = false
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        let ownedHost = context.coordinator.ownedHost
        if isPresented {
            // Already presenting our own host — update its rootView and bail out.
            if let ownedHost, ownedHost.presentingViewController != nil {
                (ownedHost as? UIHostingController<CoverContent>)?.rootView = content()
                return
            }
            // Do not compete with an unrelated modal on the same anchor; wait for next update.
            guard uiViewController.presentedViewController == nil else { return }
            let host = UIHostingController(rootView: content())
            host.view.backgroundColor = .clear
            host.modalPresentationStyle = .overFullScreen
            host.modalTransitionStyle = .crossDissolve
            context.coordinator.ownedHost = host
            uiViewController.present(host, animated: true)
        } else {
            // Dismiss ONLY the host we own. Never touch unrelated presented view controllers.
            guard let ownedHost, ownedHost.presentingViewController != nil else { return }
            ownedHost.dismiss(animated: true)
            context.coordinator.ownedHost = nil
        }
    }
}

extension View {
    func fclTransparentFullScreenCover<CoverContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> CoverContent
    ) -> some View {
        background(
            FCLTransparentFullScreenCover(isPresented: isPresented, content: content)
                .frame(width: 0, height: 0)
        )
    }
}

// MARK: - FCLDragDirection

private enum FCLDragDirection {
    case undetermined, vertical, horizontal
}

// MARK: - FCLMediaPreviewView

/// A full-screen media preview that displays all conversation attachments with horizontal swipe
/// navigation, drag-to-dismiss, chrome toggling, and a message-scoped bottom thumbnail carousel.
struct FCLMediaPreviewView: View {
    let presenter: FCLChatPresenter
    let initialAttachmentID: UUID
    let namespace: Namespace.ID
    let onDismiss: () -> Void

    @State private var currentIndex: Int = 0
    @State private var chromeVisible: Bool = true
    @State private var dragOffset: CGSize = .zero
    @State private var backgroundOpacity: Double = 1.0
    @State private var dragDirection: FCLDragDirection = .undetermined

    // MARK: - Computed helpers

    private var allMedia: [(messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment)] {
        presenter.allConversationMedia
    }

    private var dragProgress: Double {
        min(abs(dragOffset.height) / 300, 1)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.opacity(backgroundOpacity)
                .ignoresSafeArea()

            if allMedia.isEmpty {
                ProgressView()
                    .tint(.white)
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(allMedia.enumerated()), id: \.element.attachment.id) { index, item in
                        FCLMediaPreviewPage(
                            attachment: item.attachment,
                            namespace: namespace,
                            isCurrentPage: index == currentIndex
                        )
                        .tag(index)
                        .offset(dragOffset)
                        .scaleEffect(1 - dragProgress * 0.15)
                        .simultaneousGesture(dragGesture)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        chromeVisible.toggle()
                    }
                }
            }

            // Chrome overlay
            VStack(spacing: 0) {
                // Top chrome: close button
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(16)
                    }
                }

                Spacer()

                // Bottom chrome: message-scoped thumbnail carousel
                bottomCarousel
            }
            .opacity(chromeVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: chromeVisible)
        }
        .statusBarHidden(true)
        .onAppear { resolveInitialIndex() }
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if dragDirection == .undetermined {
                    if abs(value.translation.height) > abs(value.translation.width) * 1.5 {
                        dragDirection = .vertical
                    } else if abs(value.translation.width) > 6 {
                        dragDirection = .horizontal
                        return
                    } else {
                        return
                    }
                }
                guard dragDirection == .vertical else { return }
                dragOffset = CGSize(width: 0, height: value.translation.height)
                let progress = min(abs(value.translation.height) / 300, 1)
                backgroundOpacity = 1 - progress
            }
            .onEnded { value in
                defer { dragDirection = .undetermined }
                guard dragDirection == .vertical else {
                    withAnimation(.spring()) { dragOffset = .zero; backgroundOpacity = 1.0 }
                    return
                }
                let shouldDismiss = abs(value.translation.height) > 100 || abs(value.predictedEndTranslation.height) > 200
                if shouldDismiss { onDismiss() }
                else {
                    withAnimation(.spring()) { dragOffset = .zero; backgroundOpacity = 1.0 }
                }
            }
    }

    // MARK: - Bottom Carousel

    @ViewBuilder
    private var bottomCarousel: some View {
        let currentMediaItem = allMedia[safe: currentIndex]
        if let currentMessageID = currentMediaItem?.messageID {
            let messageMedia = allMedia.filter { $0.messageID == currentMessageID }
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(messageMedia, id: \.attachment.id) { item in
                            carouselThumbnail(
                                item: item,
                                isFocused: item.attachment.id == currentMediaItem?.attachment.id
                            )
                            .id(item.attachment.id)
                            .onTapGesture {
                                if let targetIndex = allMedia.firstIndex(where: { $0.attachment.id == item.attachment.id }) {
                                    withAnimation {
                                        currentIndex = targetIndex
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .onChange(of: currentIndex) { _, _ in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if let id = allMedia[safe: currentIndex]?.attachment.id {
                            scrollProxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
            .frame(height: 72)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Carousel Thumbnail

    private func carouselThumbnail(
        item: (messageID: UUID, attachmentIndex: Int, attachment: FCLAttachment),
        isFocused: Bool
    ) -> some View {
        FCLCarouselThumbnailView(attachment: item.attachment, isFocused: isFocused)
    }

    // MARK: - Private

    private func resolveInitialIndex() {
        if let index = allMedia.firstIndex(where: { $0.attachment.id == initialAttachmentID }) {
            currentIndex = index
        }
    }
}

// MARK: - FCLCarouselThumbnailView

private struct FCLCarouselThumbnailView: View {
    let attachment: FCLAttachment
    let isFocused: Bool

    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            if let image = thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipped()
            } else {
                Color.white.opacity(0.15)
                    .frame(width: 60, height: 60)
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white, lineWidth: isFocused ? 3 : 0)
        )
        .task {
            thumbnail = await FCLAsyncThumbnailLoader.shared.thumbnail(
                for: attachment,
                targetSize: CGSize(width: 120, height: 120)
            )
        }
    }
}

// MARK: - FCLMediaPreviewPage

private struct FCLMediaPreviewPage: View {
    let attachment: FCLAttachment
    let namespace: Namespace.ID
    let isCurrentPage: Bool

    @State private var loadedImage: UIImage?

    var body: some View {
        ZStack {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .matchedGeometryEffect(id: attachment.id, in: namespace, isSource: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let data = attachment.thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .matchedGeometryEffect(id: attachment.id, in: namespace, isSource: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadFullImage() }
    }

    private func loadFullImage() {
        guard attachment.type == .image || attachment.type == .video else { return }
        let url = attachment.url
        Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else { return }
            await MainActor.run {
                self.loadedImage = image
            }
        }
    }
}

// MARK: - FCLPickerAssetPreview

/// Full-screen preview for gallery assets in the attachment picker. Allows browsing all assets,
/// toggling selection, rotating images, adding a caption, and sending.
struct FCLPickerAssetPreview: View {
    @ObservedObject var presenter: FCLAttachmentPickerPresenter
    @ObservedObject var galleryDataSource: FCLGalleryDataSource
    let initialAssetID: String
    let onSend: () -> Void
    let onDismiss: () -> Void

    @State private var currentIndex: Int = 0
    @State private var rotationByID: [String: Int] = [:]
    @FocusState private var captionFocused: Bool
    @State private var isEditorPresented: Bool = false
    @State private var editorSourceImage: UIImage?

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if galleryDataSource.assets.count > 0 {
                TabView(selection: $currentIndex) {
                    ForEach(0 ..< galleryDataSource.assets.count, id: \.self) { index in
                        let asset = galleryDataSource.assets[index]
                        FCLPickerAssetPageView(
                            asset: asset,
                            galleryDataSource: galleryDataSource,
                            rotationSteps: rotationByID[asset.localIdentifier] ?? 0,
                            editedImage: presenter.editedImage(for: asset.localIdentifier)
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }

            // Chrome overlay
            VStack(spacing: 0) {
                topChrome
                Spacer()
            }

            // Send button fixed at bottom-trailing
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: onSend) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(presenter.selectedAssets.isEmpty ? Color.gray : Color.blue)
                            .clipShape(Circle())
                    }
                    .disabled(presenter.selectedAssets.isEmpty)
                    .padding(.trailing, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomCaptionBar
        }
        .statusBarHidden(true)
        .onAppear { resolveInitialIndex() }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    // Light downward swipe while keyboard is open dismisses keyboard only
                    if captionFocused,
                       value.translation.height > 20,
                       value.translation.height < 60,
                       abs(value.velocity.height) < 800 {
                        captionFocused = false
                    }
                }
        )
        .onTapGesture {
            if captionFocused {
                captionFocused = false
            }
        }
        .fullScreenCover(isPresented: $isEditorPresented) {
            if let sourceImage = editorSourceImage, let assetID = currentAssetID {
                FCLMediaEditorView(
                    sourceImage: sourceImage,
                    initialState: presenter.editState(for: assetID),
                    onConfirm: { edited, editState in
                        presenter.setEditState(editState, for: assetID)
                        presenter.setEditedImage(edited, for: assetID)
                        isEditorPresented = false
                    },
                    onCancel: {
                        isEditorPresented = false
                    }
                )
            }
        }
    }

    // MARK: - Top Chrome

    private var topChrome: some View {
        HStack(spacing: 12) {
            // Selection indicator (top-left)
            selectionIndicator
                .padding(.leading, 16)

            Spacer()

            // Close button (top-right)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.trailing, 16)
        }
        .padding(.top, 16)
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        let assetID = currentAssetID
        if let assetID {
            let selectionIndex = presenter.selectedAssets.firstIndex(of: assetID)
            Button {
                presenter.toggleAssetSelection(assetID)
            } label: {
                if let order = selectionIndex {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 30, height: 30)
                        Text("\(order + 1)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                } else {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 30, height: 30)
                }
            }
        }
    }

    // MARK: - Bottom Caption Bar

    private var bottomCaptionBar: some View {
        HStack(spacing: 8) {
            // Rotate button (bottom-left)
            Button {
                if let assetID = currentAssetID {
                    rotationByID[assetID] = ((rotationByID[assetID] ?? 0) + 1) % 4
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }

            // Edit button
            Button {
                openEditor()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        currentAssetID.flatMap { presenter.editedImage(for: $0) } != nil
                            ? Color.yellow.opacity(0.5)
                            : Color.white.opacity(0.2)
                    )
                    .clipShape(Circle())
            }

            // Caption field
            TextField("Add a caption…", text: $presenter.captionText)
                .focused($captionFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white)
                .foregroundColor(.black)
                .clipShape(RoundedRectangle(cornerRadius: 20))

            // Spacer so send button overlay stays visible
            Spacer()
                .frame(width: 52) // matches send button width + trailing padding
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 24)
        .background(Color.black.opacity(0.3))
    }

    // MARK: - Open Editor

    private func openEditor() {
        guard let assetID = currentAssetID else { return }
        // Prefer edited image as source if already edited, otherwise load fresh
        if let edited = presenter.editedImage(for: assetID) {
            editorSourceImage = edited
            isEditorPresented = true
        } else {
            guard galleryDataSource.assets.count > currentIndex else { return }
            let asset = galleryDataSource.assets[currentIndex]
            Task {
                let image = try? await galleryDataSource.fullSizeImage(for: asset)
                editorSourceImage = image
                isEditorPresented = image != nil
            }
        }
    }

    // MARK: - Private

    private var currentAssetID: String? {
        guard galleryDataSource.assets.count > currentIndex else { return nil }
        return galleryDataSource.assets[currentIndex].localIdentifier
    }

    private func resolveInitialIndex() {
        for i in 0 ..< galleryDataSource.assets.count {
            if galleryDataSource.assets[i].localIdentifier == initialAssetID {
                currentIndex = i
                return
            }
        }
    }
}

// MARK: - FCLPickerAssetPageView

private struct FCLPickerAssetPageView: View {
    let asset: PHAsset
    let galleryDataSource: FCLGalleryDataSource
    let rotationSteps: Int
    /// When non-nil, displayed in place of the gallery-loaded full-size image.
    let editedImage: UIImage?

    @State private var loadedImage: UIImage?

    /// The image to display: edited override takes precedence over gallery-loaded.
    private var displayImage: UIImage? {
        editedImage ?? loadedImage
    }

    var body: some View {
        ZStack {
            if let image = displayImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    // Only apply visual rotation when using the gallery image (not the already-rendered edit).
                    .rotationEffect(.degrees(editedImage == nil ? Double(rotationSteps) * 90 : 0))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await loadAsset() }
    }

    private func loadAsset() async {
        guard loadedImage == nil else { return }
        let image = try? await galleryDataSource.fullSizeImage(for: asset)
        loadedImage = image
    }
}

// MARK: - Previews

#if DEBUG
struct FCLMediaPreviewView_Previews: PreviewProvider {
    @Namespace static var namespace

    static var previews: some View {
        FCLMediaPreviewPreviewWrapper()
            .previewDisplayName("Media Preview — Empty")

        FCLPickerAssetPreviewWrapper()
            .previewDisplayName("Picker Asset Preview")
    }
}

private struct FCLMediaPreviewPreviewWrapper: View {
    @Namespace var namespace

    var body: some View {
        let sender = FCLChatMessageSender(id: "user1", displayName: "Alice")
        let presenter = FCLChatPresenter(
            messages: [],
            currentUser: sender
        )
        FCLMediaPreviewView(
            presenter: presenter,
            initialAttachmentID: UUID(),
            namespace: namespace,
            onDismiss: {}
        )
        .background(Color.black)
    }
}

private struct FCLPickerAssetPreviewWrapper: View {
    var body: some View {
        let pickerPresenter = FCLAttachmentPickerPresenter(delegate: nil, onSend: { _, _ in })
        let dataSource = FCLGalleryDataSource(isVideoEnabled: true)
        FCLPickerAssetPreview(
            presenter: pickerPresenter,
            galleryDataSource: dataSource,
            initialAssetID: "",
            onSend: {},
            onDismiss: {}
        )
    }
}
#endif
#endif
