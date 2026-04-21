#if os(iOS)
import Photos
import SwiftUI

// MARK: - FCLPhotoAuthorizationCoordinator

/// Wraps `PHPhotoLibrary` authorization and exposes a reactive status for the
/// picker's permission-state views.
@MainActor
final class FCLPhotoAuthorizationCoordinator: ObservableObject {

    // MARK: - Published State

    @Published private(set) var status: PHAuthorizationStatus

    // MARK: - Init

    init() {
        if Self.isRunningInPreview {
            status = .notDetermined
        } else {
            status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        }
    }

    // MARK: - API

    /// Requests photo library access when status is `.notDetermined`; no-ops otherwise.
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

    /// Re-reads the system authorization status without prompting.
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
}

#Preview("Coordinator — authorized") {
    FCLPhotoAuthorizationCoordinatorPreviewView(overrideStatus: .authorized)
}

#Preview("Coordinator — limited") {
    FCLPhotoAuthorizationCoordinatorPreviewView(overrideStatus: .limited)
}

#Preview("Coordinator — denied") {
    FCLPhotoAuthorizationCoordinatorPreviewView(overrideStatus: .denied)
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
        .onAppear {}
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FCLPalette.systemGroupedBackground)
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
