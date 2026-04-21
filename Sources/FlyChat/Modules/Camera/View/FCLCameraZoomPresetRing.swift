import SwiftUI

/// Zoom preset ring shown above the shutter — mirrors the iOS Camera
/// 0.5× / 1× / 2× / 3× chip cluster with a long-press-to-slider affordance.
///
/// Presets are supplied by the caller (derived by the presenter from the
/// active `AVCaptureDevice` constituent lenses). Tapping a chip invokes
/// `onSelectPreset`, which the consumer wires to an animated ramp. Long
/// pressing a chip reveals an inline horizontal slider that drags exact zoom
/// in user-visible units (0.5×…max); drag deltas are reported via
/// `onSliderDrag`. Ending the long press hides the slider.
struct FCLCameraZoomPresetRing: View {
    let currentZoom: CGFloat
    let presets: [CGFloat]
    let zoomRange: ClosedRange<CGFloat>
    let onSelectPreset: (CGFloat) -> Void
    let onSliderDrag: (CGFloat) -> Void

    @State private var sliderExpanded: Bool = false
    @State private var sliderBaseZoom: CGFloat = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if sliderExpanded {
                sliderRow
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                presetRow
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(
            reduceMotion ? .linear(duration: 0.15) : .spring(response: 0.32, dampingFraction: 0.82),
            value: sliderExpanded
        )
    }

    // MARK: - Preset row

    private var presetRow: some View {
        FCLGlassToolbar(placement: .bottom) {
            ForEach(presets, id: \.self) { factor in
                FCLGlassChip(
                    title: chipLabel(for: factor),
                    tint: isActive(factor)
                        ? FCLChatColorToken(red: 1.0, green: 1.0, blue: 1.0)
                        : nil,
                    action: { onSelectPreset(factor) }
                )
                .accessibilityLabel(Text(String(format: "Zoom %.1f times", Double(factor))))
                .accessibilityAddTraits(isActive(factor) ? .isSelected : [])
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                        sliderBaseZoom = currentZoom
                        sliderExpanded = true
                    }
                )
            }
        }
    }

    private func chipLabel(for factor: CGFloat) -> String {
        if isActive(factor) {
            let rounded = (currentZoom * 10).rounded() / 10
            if abs(rounded - factor) < 0.05 {
                return "\(Self.presetLabel(factor))×"
            }
            return String(format: "%.1f×", Double(currentZoom))
        }
        return Self.presetLabel(factor)
    }

    private static func presetLabel(_ factor: CGFloat) -> String {
        if abs(factor - factor.rounded()) < 0.01 {
            return String(Int(factor.rounded()))
        }
        return String(format: "%.1f", Double(factor))
    }

    private func isActive(_ preset: CGFloat) -> Bool {
        guard let nearest = presets.min(by: { lhs, rhs in
            abs(lhs - currentZoom) < abs(rhs - currentZoom)
        }) else {
            return false
        }
        return nearest == preset
    }

    // MARK: - Slider row

    private var sliderRow: some View {
        let band: CGFloat = 240
        let span = max(zoomRange.upperBound - zoomRange.lowerBound, 0.01)

        return HStack(spacing: 10) {
            Text(String(format: "%.1f×", Double(zoomRange.lowerBound)))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
            ZStack(alignment: .center) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 6)
                Capsule()
                    .fill(Color.white)
                    .frame(width: 6, height: 18)
                    .offset(x: thumbOffset(in: band))
                Text(String(format: "%.1f×", Double(currentZoom)))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.yellow)
                    .offset(y: -18)
            }
            .frame(width: band, height: 28)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let delta = value.translation.width / band * span
                        let target = sliderBaseZoom + delta
                        onSliderDrag(target)
                    }
                    .onEnded { _ in
                        sliderExpanded = false
                    }
            )
            Text(String(format: "%.1f×", Double(zoomRange.upperBound)))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.55))
        )
        .accessibilityLabel(Text("Zoom slider"))
    }

    private func thumbOffset(in band: CGFloat) -> CGFloat {
        let span = max(zoomRange.upperBound - zoomRange.lowerBound, 0.01)
        let normalized = (currentZoom - zoomRange.lowerBound) / span
        return (normalized - 0.5) * band
    }
}

#if DEBUG
#Preview("Zoom ring — back dual (0.5/1/2)") {
    ZStack {
        Color.black
        FCLCameraZoomPresetRing(
            currentZoom: 1.0,
            presets: [0.5, 1.0, 2.0],
            zoomRange: 0.5...10.0,
            onSelectPreset: { _ in },
            onSliderDrag: { _ in }
        )
    }
}

#Preview("Zoom ring — triple (0.5/1/2/3)") {
    ZStack {
        Color.black
        FCLCameraZoomPresetRing(
            currentZoom: 0.5,
            presets: [0.5, 1.0, 2.0, 3.0],
            zoomRange: 0.5...15.0,
            onSelectPreset: { _ in },
            onSliderDrag: { _ in }
        )
    }
}

#Preview("Zoom ring — front (1x only)") {
    ZStack {
        Color.black
        FCLCameraZoomPresetRing(
            currentZoom: 1.0,
            presets: [1.0],
            zoomRange: 1.0...1.0,
            onSelectPreset: { _ in },
            onSliderDrag: { _ in }
        )
    }
}

#Preview("Zoom ring — active 1.4× (mid-preset)") {
    ZStack {
        Color.black
        FCLCameraZoomPresetRing(
            currentZoom: 1.4,
            presets: [0.5, 1.0, 2.0],
            zoomRange: 0.5...10.0,
            onSelectPreset: { _ in },
            onSliderDrag: { _ in }
        )
    }
}
#endif

