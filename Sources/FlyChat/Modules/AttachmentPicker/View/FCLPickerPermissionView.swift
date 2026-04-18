#if canImport(UIKit)
import Photos
import SwiftUI
import UIKit

// MARK: - FCLPickerPermissionSurface

/// Unified permission surface rendered under the picker's top toolbar.
///
/// Shown whenever ``PHAuthorizationStatus`` is not `.authorized`. Renders:
/// - a slim banner at the top (always when visible), and
/// - a full empty state beneath it for ``.denied`` and ``.restricted``.
///
/// The color palette uses ``FCLPalette`` system semantic colors so the surface
/// stays legible across light, dark, and high-contrast traits (see HIG). Status
/// is indicated by a small leading dot: info-blue for limited, neutral for
/// not-determined (with a spinner), warning-orange for denied/restricted.
///
/// The surface observes ``presenter.isPresentationComplete`` to decide whether
/// `.notDetermined` should appear "pending" (spinner) or blank — before the
/// sheet animation has finished, it stays blank to avoid competing with the
/// presentation.
struct FCLPickerPermissionSurface: View {
    let status: PHAuthorizationStatus
    let selectedCount: Int?
    let totalCount: Int?
    let isPresentationComplete: Bool

    @State private var isShowingLimitedPicker = false

    var body: some View {
        VStack(spacing: 12) {
            if shouldShowBanner {
                banner
            }
            if shouldShowFullEmptyState {
                fullEmptyState
            }
        }
    }

    private var shouldShowBanner: Bool {
        switch status {
        case .authorized: return false
        case .limited, .denied, .restricted: return true
        case .notDetermined: return isPresentationComplete
        @unknown default: return false
        }
    }

    private var shouldShowFullEmptyState: Bool {
        switch status {
        case .denied, .restricted: return true
        default: return false
        }
    }

    // MARK: - Banner

    @ViewBuilder
    private var banner: some View {
        HStack(spacing: 10) {
            statusDot
            VStack(alignment: .leading, spacing: 1) {
                Text(bannerHeadline)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(FCLPalette.label)
                Text(bannerSubtitle)
                    .font(.caption2)
                    .foregroundStyle(FCLPalette.secondaryLabel)
            }
            Spacer(minLength: 8)
            trailingControl
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(FCLPalette.secondarySystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .background(
            FCLLimitedLibraryPickerBridge(isPresented: $isShowingLimitedPicker)
                .frame(width: 0, height: 0)
        )
    }

    @ViewBuilder
    private var statusDot: some View {
        ZStack {
            Circle()
                .fill(statusDotColor)
                .frame(width: 18, height: 18)
            Text(statusDotGlyph)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var statusDotColor: Color {
        switch status {
        case .limited: return FCLChatColorToken(red: 0.0, green: 0.48, blue: 1.0).color
        case .notDetermined: return FCLChatColorToken(red: 0.47, green: 0.47, blue: 0.50).color
        case .denied, .restricted: return FCLChatColorToken(red: 1.0, green: 0.58, blue: 0.0).color
        default: return Color.clear
        }
    }

    private var statusDotGlyph: String {
        switch status {
        case .limited: return "i"
        case .notDetermined: return "•"
        case .denied, .restricted: return "!"
        default: return ""
        }
    }

    private var bannerHeadline: String {
        switch status {
        case .limited:
            if let selectedCount, let totalCount {
                return "\(selectedCount) of \(totalCount) photos accessible"
            }
            return "Limited photo access"
        case .notDetermined: return "Requesting photo access…"
        case .denied, .restricted: return "Photo access is off"
        default: return ""
        }
    }

    private var bannerSubtitle: String {
        switch status {
        case .limited: return "Manage which photos FlyChat can see."
        case .notDetermined: return "Respond to the system dialog to continue."
        case .denied, .restricted: return "FlyChat can't show your library until you allow access."
        default: return ""
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch status {
        case .limited:
            Button(action: { isShowingLimitedPicker = true }) {
                Text("Manage")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(FCLPickerBannerCTAStyle())
            .accessibilityLabel("Manage photo library access")

        case .notDetermined:
            ProgressView()
                .controlSize(.small)
                .padding(.trailing, 2)

        case .denied, .restricted:
            Button(action: openSettings) {
                Text("Settings")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(FCLPickerBannerCTAStyle())
            .accessibilityLabel("Open Settings")

        default:
            EmptyView()
        }
    }

    // MARK: - Full empty state (denied/restricted only)

    @ViewBuilder
    private var fullEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(FCLPalette.secondaryLabel)

            Text("Grant photo access to select\nmedia from your library.")
                .font(.subheadline)
                .foregroundStyle(FCLPalette.label)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: openSettings) {
                Text("Open Settings")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
            }
            .buttonStyle(FCLPickerPrimaryFilledButtonStyle())
            .accessibilityLabel("Open Settings")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 32)
    }

    // MARK: - Actions

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Button styles

private struct FCLPickerBannerCTAStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(FCLChatColorToken(red: 0.0, green: 0.48, blue: 1.0).color.opacity(0.14))
            )
            .foregroundStyle(FCLChatColorToken(red: 0.0, green: 0.48, blue: 1.0).color)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

private struct FCLPickerPrimaryFilledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                Capsule(style: .continuous)
                    .fill(FCLChatColorToken(red: 0.0, green: 0.48, blue: 1.0).color)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

// MARK: - Limited library bridge (unchanged from previous file)

/// A zero-size `UIViewControllerRepresentable` that presents the system
/// limited-library picker via `PHPhotoLibrary.shared().presentLimitedLibraryPicker(from:)`
/// when `isPresented` flips to `true`.
///
/// The representable hosts a transparent `UIViewController` and presents the
/// system picker on top of it. Dismissal resets `isPresented` to `false` via
/// the `Coordinator`.
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

    @MainActor
    final class Coordinator {
        var isPresentedBinding: Binding<Bool>?
    }
}

// MARK: - Previews

#if DEBUG

#Preview("Permission — authorized (no surface)") {
    FCLPickerPermissionSurfacePreviewHost(status: .authorized, isPresentationComplete: true)
}

#Preview("Permission — limited (banner only)") {
    FCLPickerPermissionSurfacePreviewHost(
        status: .limited,
        selectedCount: 3,
        totalCount: 12,
        isPresentationComplete: true
    )
}

#Preview("Permission — notDetermined (banner + spinner)") {
    FCLPickerPermissionSurfacePreviewHost(status: .notDetermined, isPresentationComplete: true)
}

#Preview("Permission — notDetermined (pre-presentation blank)") {
    FCLPickerPermissionSurfacePreviewHost(status: .notDetermined, isPresentationComplete: false)
}

#Preview("Permission — denied (banner + full empty state)") {
    FCLPickerPermissionSurfacePreviewHost(status: .denied, isPresentationComplete: true)
}

#Preview("Permission — restricted (banner + full empty state)") {
    FCLPickerPermissionSurfacePreviewHost(status: .restricted, isPresentationComplete: true)
}

private struct FCLPickerPermissionSurfacePreviewHost: View {
    let status: PHAuthorizationStatus
    var selectedCount: Int? = nil
    var totalCount: Int? = nil
    let isPresentationComplete: Bool

    var body: some View {
        ZStack {
            FCLPalette.systemBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                FCLPickerPermissionSurface(
                    status: status,
                    selectedCount: selectedCount,
                    totalCount: totalCount,
                    isPresentationComplete: isPresentationComplete
                )
                Spacer()
            }
        }
    }
}
#endif
#endif
