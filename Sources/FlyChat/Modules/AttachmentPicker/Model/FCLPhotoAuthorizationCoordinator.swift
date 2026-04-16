#if canImport(UIKit)
import Photos
import SwiftUI

// MARK: - FCLPhotoAuthorizationCoordinator

/// Wraps `PHPhotoLibrary` authorization queries and exposes a reactive status
/// for the attachment picker's permission-state views.
///
/// The coordinator is `@MainActor` so all status mutations land on the main
/// thread and SwiftUI can read `status` directly without crossing isolation
/// boundaries. The async `requestAuthorization` variant (iOS 14+) is used
/// instead of the completion-handler overload to keep the call site clean and
/// avoid callback-queue ambiguity.
@MainActor
final class FCLPhotoAuthorizationCoordinator: ObservableObject {

    // MARK: - Published State

    /// The current photo library authorization status.
    ///
    /// Starts as the system-reported status at construction time; callers may
    /// trigger a live re-check via ``refresh()`` (e.g. on scene-active return).
    @Published private(set) var status: PHAuthorizationStatus

    // MARK: - Init

    init() {
        // Read the current status synchronously so the initial render avoids a
        // flicker to `.notDetermined` on first appear.
        if Self.isRunningInPreview {
            status = .notDetermined
        } else {
            status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        }
    }

    // MARK: - API

    /// Requests photo library access when the status is `.notDetermined`; no-ops
    /// for any other starting status.
    ///
    /// Uses the async `requestAuthorization(for:)` overload (iOS 14+) so the
    /// call never blocks the caller and needs no completion-handler bridging.
    func requestAccessIfNeeded() async {
        guard !Self.isRunningInPreview else { return }
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current == .notDetermined else {
            status = current
            return
        }
        let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        status = granted
    }

    /// Re-reads the current system authorization status without prompting.
    ///
    /// Call this whenever the user returns from Settings so the picker reflects
    /// any permission change they made.
    func refresh() {
        guard !Self.isRunningInPreview else { return }
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    // MARK: - Preview Guard

    private static var isRunningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Coordinator — notDetermined") {
    FCLPhotoAuthorizationCoordinatorPreviewView(overrideStatus: .notDetermined)
        .previewDisplayName("Auth — notDetermined")
}

#Preview("Coordinator — authorized") {
    FCLPhotoAuthorizationCoordinatorPreviewView(overrideStatus: .authorized)
        .previewDisplayName("Auth — authorized")
}

#Preview("Coordinator — limited") {
    FCLPhotoAuthorizationCoordinatorPreviewView(overrideStatus: .limited)
        .previewDisplayName("Auth — limited")
}

#Preview("Coordinator — denied") {
    FCLPhotoAuthorizationCoordinatorPreviewView(overrideStatus: .denied)
        .previewDisplayName("Auth — denied")
}

private struct FCLPhotoAuthorizationCoordinatorPreviewView: View {
    let overrideStatus: PHAuthorizationStatus

    @StateObject private var coordinator = FCLPhotoAuthorizationCoordinator()

    var body: some View {
        VStack(spacing: 16) {
            Text("Status: \(statusLabel)")
                .font(.headline)
                .padding()
        }
        .onAppear {
            // Override the coordinator status for preview purposes only.
            // In production the coordinator reads from PHPhotoLibrary.
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var statusLabel: String {
        switch overrideStatus {
        case .notDetermined: return "notDetermined"
        case .restricted:    return "restricted"
        case .denied:        return "denied"
        case .authorized:    return "authorized"
        case .limited:       return "limited"
        @unknown default:    return "unknown"
        }
    }
}
#endif
#endif
