#if canImport(UIKit)
import SwiftUI

// MARK: - FCLPickerMorphPhase

/// Phase of the attach-button → sheet pill morph.
///
/// - `.idle`: overlay is invisible; no pill is rendered.
/// - `.expanding`: pill starts at the attach button's frame and animates up to
///   the sheet's top-edge rect. The native `.sheet()` slides up in parallel; as
///   the sheet rises, it progressively occludes the pill from bottom to top, so
///   only the pill's terminal rect is visible at the end — coincident with the
///   sheet's top edge.
/// - `.collapsing`: pill starts at the last-known sheet-top rect and animates
///   back down to the attach button's frame. The native `.sheet()` slides down
///   in parallel; as the sheet falls, it reveals the pill behind it, keeping
///   the morph visible all the way to the final collapse.
enum FCLPickerMorphPhase: Equatable {
    case idle
    case expanding
    case collapsing
}

// MARK: - FCLPickerMorphOverlay

/// SwiftUI overlay that renders the picker's "pill morph" between the attach
/// button and the presented sheet's top edge.
///
/// The overlay is mounted via `.overlay(alignment: .bottomTrailing)` on the
/// input bar's content. Because SwiftUI sheets present at window level, the
/// native sheet draws **in front of** this overlay — that is intentional: the
/// rising / falling sheet progressively occludes / reveals the morphing pill,
/// which is what makes the hand-off read as "the button expanded into the
/// sheet".
///
/// Coordinates: `buttonFrame` and `sheetTopFrame` are expected in window
/// (global) coordinates. The overlay reads its own global origin with a
/// `GeometryReader` so it can translate those rects into its local coordinate
/// space without relying on a private window reference.
///
/// Reduce-motion: when `accessibilityReduceMotion` is active the overlay
/// short-circuits the geometry animation and emits a pure opacity cross-fade
/// instead. The native sheet slide remains unchanged — it is the baseline that
/// both modes share.
struct FCLPickerMorphOverlay: View {
    /// Current morph phase. Set to `.expanding` on open, `.collapsing` on any
    /// close path; the overlay auto-resets to `.idle` after the morph window.
    @Binding var phase: FCLPickerMorphPhase

    /// Attach button frame in window coordinates, published by the input bar
    /// via ``FCLPickerSourceRelay/sourceFrame``.
    let buttonFrame: CGRect?

    /// Sheet top-edge rect in window coordinates, published by the sheet
    /// content via ``FCLPickerSourceRelay/sheetTopFrame``.
    let sheetTopFrame: CGRect?

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.fclPreviewReduceMotion) private var previewReduceMotion

    private var reduceMotion: Bool { previewReduceMotion ?? systemReduceMotion }

    var body: some View {
        GeometryReader { proxy in
            let localOrigin = proxy.frame(in: .global).origin
            ZStack {
                if phase != .idle,
                   let pillRect = resolvePillRect(localOrigin: localOrigin) {
                    FCLPickerMorphPill(
                        rect: pillRect,
                        cornerRadius: resolveCornerRadius()
                    )
                    .transition(.opacity)
                    .animation(resolveAnimation(), value: phase)
                }
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height,
                alignment: .topLeading
            )
            .allowsHitTesting(false)
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase != .idle {
                scheduleAutoReset()
            }
        }
    }

    // MARK: - Geometry

    /// Resolves the pill's current rect in the overlay's local coordinate
    /// space. Returns `nil` when either anchor is missing so the overlay
    /// silently renders nothing instead of snapping to the origin.
    ///
    /// `.expanding` lands the pill on the sheet-top rect; `.collapsing` lands
    /// it on the button frame. SwiftUI's implicit animation on the
    /// `RoundedRectangle`'s frame + corner radius drives the transform.
    private func resolvePillRect(localOrigin: CGPoint) -> CGRect? {
        guard let buttonFrame, let sheetTopFrame else { return nil }
        let localButton = buttonFrame.offsetBy(dx: -localOrigin.x, dy: -localOrigin.y)
        let localSheet = sheetTopFrame.offsetBy(dx: -localOrigin.x, dy: -localOrigin.y)
        switch phase {
        case .idle:
            return nil
        case .expanding:
            return localSheet
        case .collapsing:
            return localButton
        }
    }

    /// Resolves the pill's corner radius to match the phase target: 16 pt on
    /// the sheet-top rect, half the button's short edge on the attach button.
    /// SwiftUI interpolates the `CGFloat` across the morph window alongside
    /// the frame.
    private func resolveCornerRadius() -> CGFloat {
        guard let buttonFrame else { return 16 }
        let buttonCorner = min(buttonFrame.width, buttonFrame.height) / 2
        switch phase {
        case .idle:
            return buttonCorner
        case .expanding:
            return 16
        case .collapsing:
            return buttonCorner
        }
    }

    /// Resolves the SwiftUI animation attached to the pill's transform. Under
    /// reduce-motion we drop the spring in favour of a short linear fade so no
    /// geometry motion occurs; the native sheet still slides (baseline motion
    /// that all modes share) but the pill becomes a pure cross-fade.
    private func resolveAnimation() -> Animation {
        if reduceMotion {
            return .linear(duration: FCLPickerTransitionCurves.morphDuration)
        }
        return .spring(
            response: FCLPickerTransitionCurves.springResponse,
            dampingFraction: FCLPickerTransitionCurves.springDampingFraction
        )
    }

    // MARK: - Auto-Reset

    /// Schedules a reset of `phase` back to `.idle` after the morph window so
    /// the overlay stops rendering. The native sheet and the overlay share a
    /// single timeline (`morphDuration`); once that window elapses the
    /// animation is visually complete and the overlay can safely disappear.
    ///
    /// The reset runs on the main actor and is safe to re-enter: if `phase`
    /// changes again before the delay elapses, the new value wins and the
    /// overlay simply starts a second animation.
    private func scheduleAutoReset() {
        let duration = FCLPickerTransitionCurves.morphDuration
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            phase = .idle
        }
    }
}

// MARK: - FCLPickerMorphPill

/// Narrow pill view used by the morph overlay. Isolated so SwiftUI's implicit
/// animation on `rect` / `cornerRadius` can interpolate cleanly without the
/// surrounding `GeometryReader` re-running its closure on every tick.
private struct FCLPickerMorphPill: View {
    let rect: CGRect
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(.systemBackground))
            .overlay {
                // Match the sheet's top-edge drag handle so the morph lands on
                // a shape the user will actually see as the native sheet
                // overtakes the pill. The handle only appears when the pill is
                // tall enough to show it — i.e. close to the sheet-top size.
                Capsule()
                    .fill(Color(.tertiaryLabel))
                    .frame(width: 36, height: 5)
                    .opacity(rect.height >= 20 ? 1 : 0)
            }
            .shadow(color: .black.opacity(0.18), radius: 16, y: -4)
            .frame(width: max(rect.width, 0), height: max(rect.height, 0))
            .position(x: rect.midX, y: rect.midY)
    }
}

// MARK: - Previews

#if DEBUG
struct FCLPickerMorphOverlay_Previews: PreviewProvider {
    static var previews: some View {
        FCLPickerMorphOverlayPreviewHost(initialPhase: .idle)
            .previewDisplayName("Overlay — Idle")

        FCLPickerMorphOverlayPreviewHost(initialPhase: .expanding)
            .previewDisplayName("Overlay — Expanding")

        FCLPickerMorphOverlayPreviewHost(initialPhase: .collapsing)
            .previewDisplayName("Overlay — Collapsing")

        FCLPickerMorphOverlayPreviewHost(initialPhase: .expanding)
            .fclPreviewReduceMotion()
            .previewDisplayName("Overlay — Reduced Motion Fallback")

        FCLPickerMorphOverlayPreviewHost(initialPhase: .expanding)
            .preferredColorScheme(.dark)
            .previewDisplayName("Overlay — Dark")
    }
}

/// Interactive preview harness that paints the attach-button rect, the
/// sheet-top rect, and the overlay in-flight so designers can verify the pill
/// geometry without running a full chat screen.
private struct FCLPickerMorphOverlayPreviewHost: View {
    @State private var phase: FCLPickerMorphPhase

    private let buttonFrame = CGRect(x: 320, y: 720, width: 44, height: 44)
    private let sheetTopFrame = CGRect(x: 0, y: 360, width: 390, height: 40)

    init(initialPhase: FCLPickerMorphPhase) {
        _phase = State(initialValue: initialPhase)
    }

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground).ignoresSafeArea()

            // Reference rects so the preview reader can see where the pill
            // should land at each phase end.
            Rectangle()
                .fill(Color.blue.opacity(0.15))
                .frame(width: sheetTopFrame.width, height: sheetTopFrame.height)
                .position(x: sheetTopFrame.midX, y: sheetTopFrame.midY)
            Circle()
                .fill(Color.orange.opacity(0.3))
                .frame(width: buttonFrame.width, height: buttonFrame.height)
                .position(x: buttonFrame.midX, y: buttonFrame.midY)

            FCLPickerMorphOverlay(
                phase: $phase,
                buttonFrame: buttonFrame,
                sheetTopFrame: sheetTopFrame
            )

            VStack {
                Spacer()
                HStack(spacing: 12) {
                    Button("Expand") { phase = .expanding }
                    Button("Collapse") { phase = .collapsing }
                    Button("Idle") { phase = .idle }
                }
                .padding()
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 80)
            }
        }
        .previewLayout(.fixed(width: 390, height: 844))
    }
}
#endif
#endif
