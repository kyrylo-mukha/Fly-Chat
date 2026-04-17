import SwiftUI

/// Identifies a single tap-to-focus event. Changing the identifier restarts
/// the indicator animation at a new location.
struct FCLCameraFocusTap: Equatable, Identifiable {
    let id = UUID()
    let location: CGPoint
}

/// Tap-to-focus reticle. Appears at `tap.location`, performs a two-stage
/// pulse, persists briefly, then fades out. No-op while `tap` is `nil`.
struct FCLCameraFocusIndicator: View {
    let tap: FCLCameraFocusTap?

    @State private var scale: CGFloat = 1.4
    @State private var opacity: Double = 0

    private let size: CGFloat = 72
    private let tickLength: CGFloat = 6
    private let strokeWidth: CGFloat = 1

    var body: some View {
        ZStack {
            if let tap {
                reticle
                    .frame(width: size, height: size)
                    .scaleEffect(scale)
                    .opacity(opacity)
                    .position(tap.location)
                    .allowsHitTesting(false)
                    .onAppear { animate() }
                    .id(tap.id)
            }
        }
    }

    private var reticle: some View {
        ZStack {
            Rectangle()
                .stroke(Color.yellow, lineWidth: strokeWidth)
                .frame(width: size, height: size)

            // Four tick marks, each protruding inward from the midpoint of a side.
            // Top tick
            Rectangle()
                .fill(Color.yellow)
                .frame(width: strokeWidth, height: tickLength)
                .offset(y: -size / 2 + tickLength / 2)
            // Bottom tick
            Rectangle()
                .fill(Color.yellow)
                .frame(width: strokeWidth, height: tickLength)
                .offset(y: size / 2 - tickLength / 2)
            // Leading tick
            Rectangle()
                .fill(Color.yellow)
                .frame(width: tickLength, height: strokeWidth)
                .offset(x: -size / 2 + tickLength / 2)
            // Trailing tick
            Rectangle()
                .fill(Color.yellow)
                .frame(width: tickLength, height: strokeWidth)
                .offset(x: size / 2 - tickLength / 2)
        }
    }

    private func animate() {
        // Reset to initial state.
        scale = 1.4
        opacity = 0

        // Stage 1: appear and pulse down 1.4 -> 1.0 over 250ms.
        withAnimation(.easeOut(duration: 0.25)) {
            scale = 1.0
            opacity = 1.0
        }

        // Stage 2: slight bounce 1.0 -> 1.05 -> 1.0 over 150ms.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            withAnimation(.easeInOut(duration: 0.075)) {
                scale = 1.05
            }
            try? await Task.sleep(nanoseconds: 75_000_000)
            withAnimation(.easeInOut(duration: 0.075)) {
                scale = 1.0
            }

            // Persist visible for ~1.2s, then fade over 300ms.
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.easeIn(duration: 0.3)) {
                opacity = 0
            }
        }
    }
}

#if DEBUG
#Preview("Focus — idle") {
    ZStack {
        Color.black
        FCLCameraFocusIndicator(tap: nil)
    }
}

#Preview("Focus — active") {
    ZStack {
        Color.black
        FCLCameraFocusIndicator(tap: FCLCameraFocusTap(location: CGPoint(x: 180, y: 320)))
    }
}
#endif

