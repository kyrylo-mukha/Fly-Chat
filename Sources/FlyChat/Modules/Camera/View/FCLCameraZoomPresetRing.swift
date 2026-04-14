#if canImport(UIKit)
import SwiftUI

/// Compact zoom preset segmented ring shown above the shutter while not
/// recording — mirrors the iOS Camera 0.5× / 1× / 2× chip cluster.
///
/// The ring is visual only: the active preset is highlighted by the smallest
/// difference between `currentZoom` and each preset's factor. Tapping a chip
/// invokes `onSelect` with the preset's raw factor; the consumer drives the
/// underlying `AVCaptureDevice.videoZoomFactor` change. Pinch-to-zoom on the
/// preview continues to work as a fine-grain override.
///
/// Note: this view does not attempt to detect available device zoom ranges.
/// Single-lens devices (e.g. front camera) will simply clamp the requested
/// factor inside the presenter's `setZoom` path.
struct FCLCameraZoomPresetRing: View {
    let currentZoom: CGFloat
    let onSelect: (CGFloat) -> Void

    /// Presets aligned with system iOS Camera. Labels are static text — there
    /// is no SF Symbol for fractional/integer zoom indicators.
    private static let presets: [Preset] = [
        Preset(factor: 0.5, label: "0.5"),
        Preset(factor: 1.0, label: "1"),
        Preset(factor: 2.0, label: "2")
    ]

    private struct Preset: Hashable {
        let factor: CGFloat
        let label: String
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Self.presets, id: \.self) { preset in
                chip(for: preset)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color.black.opacity(0.45))
        )
    }

    private func chip(for preset: Preset) -> some View {
        let active = isActive(preset)
        return Button {
            onSelect(preset.factor)
        } label: {
            Text(label(for: preset, active: active))
                .font(.system(size: active ? 13 : 12, weight: .semibold))
                .foregroundStyle(active ? Color.yellow : Color.white)
                .frame(width: 32, height: 32)
                .background(
                    Circle().fill(active ? Color.white.opacity(0.18) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Zoom \(preset.label) times"))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func label(for preset: Preset, active: Bool) -> String {
        if active {
            // Active preset shows the live zoom factor (e.g. "1.4×") to match
            // iOS Camera, falling back to the preset label when zoom is at the
            // exact preset value.
            let rounded = (currentZoom * 10).rounded() / 10
            if abs(rounded - preset.factor) < 0.05 {
                return "\(preset.label)×"
            }
            return String(format: "%.1f×", currentZoom)
        }
        return "\(preset.label)×"
    }

    private func isActive(_ preset: Preset) -> Bool {
        // Pick the preset whose factor is closest to currentZoom.
        let nearest = Self.presets.min(by: { lhs, rhs in
            abs(lhs.factor - currentZoom) < abs(rhs.factor - currentZoom)
        })
        return nearest == preset
    }
}

#if DEBUG
#Preview("Zoom ring — 1×") {
    ZStack {
        Color.black
        FCLCameraZoomPresetRing(currentZoom: 1.0, onSelect: { _ in })
    }
}

#Preview("Zoom ring — 0.5×") {
    ZStack {
        Color.black
        FCLCameraZoomPresetRing(currentZoom: 0.5, onSelect: { _ in })
    }
}

#Preview("Zoom ring — 1.4× (active 1×)") {
    ZStack {
        Color.black
        FCLCameraZoomPresetRing(currentZoom: 1.4, onSelect: { _ in })
    }
}
#endif

#endif
