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
        // Attach as `.simultaneousGesture` so the underlying TabView
        // pager keeps receiving horizontal drag samples. The previous
        // `.gesture(...)` attachment installed a higher-priority recognizer
        // at the ZStack root that intercepted every drag, including the
        // horizontal pan that should reach the pager — making swipe between
        // assets feel sluggish or completely blocked.
        .simultaneousGesture(
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
        .overlay {
            // In-place editor replacement for the legacy fullScreenCover path.
            // The gallery preview currently exposes only the rotate/crop tool
            // via this entry point; markup routing from the gallery-picker
            // preview is a follow-up.
            if isEditorPresented, let sourceImage = editorSourceImage, let assetID = currentAssetID {
                FCLRotateCropEditor(
                    original: sourceImage,
                    onCommit: { edited in
                        presenter.setEditedImage(edited, for: assetID)
                        isEditorPresented = false
                    },
                    onCancel: {
                        isEditorPresented = false
                    }
                )
                .id(assetID)
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isEditorPresented)
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
struct FCLPickerAssetPreview_Previews: PreviewProvider {
    static var previews: some View {
        FCLPickerAssetPreviewWrapper()
            .previewDisplayName("Picker Asset Preview")
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
