#if canImport(UIKit)
import Photos
import SwiftUI
import UIKit

// MARK: - FCLPickerPermissionBanner

/// A compact banner rendered above the gallery grid when the user has granted
/// limited photo access (`.limited`).
///
/// The leading label prefers the `"\(selectedCount) of \(totalCount) selected"`
/// format when counts are supplied by the caller; when counts are `nil` the
/// banner falls back to the generic `"You gave access to selected photos only."`
/// sentence so the component stays usable in contexts that don't know the
/// numbers yet.
///
/// "Manage" opens the system limited-library picker via
/// ``FCLLimitedLibraryPickerBridge`` so the user can adjust which assets are
/// visible without leaving the app.
struct FCLPickerPermissionBanner: View {
    /// Number of assets currently selected inside the picker's staging list,
    /// or `nil` when the caller does not have the count to hand.
    let selectedCount: Int?
    /// Total number of assets the user granted access to (the limited set
    /// size), or `nil` when it is not yet available.
    let totalCount: Int?

    @State private var isShowingLimitedPicker = false

    init(selectedCount: Int? = nil, totalCount: Int? = nil) {
        self.selectedCount = selectedCount
        self.totalCount = totalCount
    }

    var body: some View {
        HStack {
            Text(bannerText)
                .font(.caption)
                .foregroundStyle(FCLPalette.secondaryLabel)
            Spacer()
            FCLGlassButton(action: { isShowingLimitedPicker = true }) {
                Text("Manage")
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(FCLPalette.secondarySystemBackground)
        .background(
            FCLLimitedLibraryPickerBridge(isPresented: $isShowingLimitedPicker)
                .frame(width: 0, height: 0)
        )
    }

    private var bannerText: String {
        if let selectedCount, let totalCount {
            return "\(selectedCount) of \(totalCount) selected"
        }
        return "You gave access to selected photos only."
    }
}

// MARK: - FCLPickerDeniedView

/// Full-area prompt shown when photo access is `.denied` or `.restricted`.
///
/// An "Open Settings" button routes the user to the iOS Settings app so they
/// can change the permission. The button uses ``FCLGlassButton`` to match the
/// rest of the picker's visual language.
struct FCLPickerDeniedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(FCLPalette.secondaryLabel)

            Text("Photo access is required to select images.")
                .font(.subheadline)
                .foregroundStyle(FCLPalette.secondaryLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            FCLGlassButton(action: openSettings) {
                Text("Open Settings")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - FCLLimitedLibraryPickerBridge

/// A zero-size `UIViewControllerRepresentable` that presents the system
/// limited-library picker via `PHPhotoLibrary.shared().presentLimitedLibraryPicker(from:)`
/// when `isPresented` flips to `true`.
///
/// The representable hosts a transparent `UIViewController` and presents the
/// system picker on top of it. Dismissal resets `isPresented` to `false` via
/// the `Coordinator`, which conforms to `PHPhotoLibraryChangeObserver` so the
/// caller's gallery data source refreshes automatically after the user selects
/// new photos.
struct FCLLimitedLibraryPickerBridge: UIViewControllerRepresentable {
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Keep the coordinator's binding reference current every update pass so
        // the completion callback always writes to the latest binding.
        context.coordinator.isPresentedBinding = $isPresented

        if isPresented, uiViewController.presentedViewController == nil {
            let binding = $isPresented
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: uiViewController) { _ in
                Task { @MainActor in
                    binding.wrappedValue = false
                }
            }
        }
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator {
        /// Kept up-to-date by `updateUIViewController` so the callback always
        /// writes to the current binding (handles SwiftUI identity changes).
        var isPresentedBinding: Binding<Bool>?
    }
}

// MARK: - Previews

#if DEBUG

#Preview("Permission — notDetermined") {
    FCLPickerPermissionPreviewContainer(state: .notDetermined)
}

#Preview("Permission — authorized") {
    FCLPickerPermissionPreviewContainer(state: .authorized)
}

#Preview("Permission — limited") {
    FCLPickerPermissionPreviewContainer(state: .limited)
}

#Preview("Permission — limited (counted)") {
    FCLPickerPermissionPreviewContainer(state: .limited, selectedCount: 2, totalCount: 8)
}

#Preview("Permission — denied") {
    FCLPickerPermissionPreviewContainer(state: .denied)
}

private struct FCLPickerPermissionPreviewContainer: View {
    let state: PHAuthorizationStatus
    var selectedCount: Int? = nil
    var totalCount: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            switch state {
            case .limited:
                FCLPickerPermissionBanner(
                    selectedCount: selectedCount,
                    totalCount: totalCount
                )
                mockGallery

            case .denied, .restricted:
                FCLPickerDeniedView()

            case .notDetermined:
                VStack {
                    Spacer()
                    Text("Waiting for authorization…")
                        .font(.subheadline)
                        .foregroundStyle(FCLPalette.secondaryLabel)
                    Spacer()
                }

            case .authorized:
                mockGallery

            @unknown default:
                EmptyView()
            }
        }
        .background(FCLPalette.systemBackground)
    }

    private var mockGallery: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)
        let colors: [Color] = [.blue, .orange, .green, .purple, .red, .teal, .indigo, .brown, .pink, .cyan, .mint, .yellow]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<12, id: \.self) { i in
                    colors[i % colors.count]
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }
}
#endif
#endif
