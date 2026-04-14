#if canImport(UIKit)
import SwiftUI

/// Bottom overlay bar: mode switch, shutter, flip, and stack counter.
struct FCLCameraBottomBar: View {
    let mode: FCLCameraMode
    let isRecording: Bool
    let allowsVideo: Bool
    let capturedCount: Int
    let latestThumbnail: UIImage?
    let canShowStack: Bool
    let currentZoom: CGFloat
    let showsZoomPresets: Bool
    let onSetMode: (FCLCameraMode) -> Void
    let onShutter: () -> Void
    let onFlip: () -> Void
    let onOpenStack: () -> Void
    let onSelectZoomPreset: (CGFloat) -> Void

    var body: some View {
        VStack(spacing: 12) {
            if showsZoomPresets {
                FCLCameraZoomPresetRing(
                    currentZoom: currentZoom,
                    onSelect: onSelectZoomPreset
                )
            }
            if allowsVideo && !isRecording {
                modeSwitch
            }
            ZStack {
                // Shutter is centered unconditionally.
                FCLCameraShutterButton(
                    mode: mode,
                    isRecording: isRecording,
                    isEnabled: true,
                    action: onShutter
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                // Stack anchored leading.
                HStack {
                    if canShowStack && capturedCount > 0 {
                        FCLCameraStackCounter(count: capturedCount,
                                              latestThumbnail: latestThumbnail,
                                              action: onOpenStack)
                    } else {
                        Color.clear.frame(width: 56, height: 56)
                    }
                    Spacer(minLength: 0)
                }

                // Flip anchored trailing.
                HStack {
                    Spacer(minLength: 0)
                    flipButton
                }
            }
            .frame(height: 72)
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 20)
    }

    private var modeSwitch: some View {
        HStack(spacing: 24) {
            modeLabel(.photo, title: "Photo")
            modeLabel(.video, title: "Video")
        }
        .padding(.vertical, 4)
    }

    private func modeLabel(_ target: FCLCameraMode, title: String) -> some View {
        let selected = mode == target
        return Button {
            onSetMode(target)
        } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? Color.yellow : Color.white.opacity(0.7))
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 4, height: 4)
                    .opacity(selected ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch to \(title.lowercased()) mode")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var flipButton: some View {
        Button(action: onFlip) {
            Image(systemName: "camera.rotate")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.black.opacity(0.45)))
        }
        .disabled(isRecording)
        .opacity(isRecording ? 0.4 : 1)
        .accessibilityLabel("Flip camera")
    }
}

#if DEBUG
#Preview("Bottom bar — photo idle") {
    ZStack {
        Color.black
        VStack { Spacer()
            FCLCameraBottomBar(
                mode: .photo, isRecording: false, allowsVideo: true,
                capturedCount: 0, latestThumbnail: nil, canShowStack: false,
                currentZoom: 1, showsZoomPresets: true,
                onSetMode: { _ in }, onShutter: {}, onFlip: {}, onOpenStack: {},
                onSelectZoomPreset: { _ in }
            )
        }
    }
}

#Preview("Bottom bar — video recording") {
    ZStack {
        Color.black
        VStack { Spacer()
            FCLCameraBottomBar(
                mode: .video, isRecording: true, allowsVideo: true,
                capturedCount: 0, latestThumbnail: nil, canShowStack: false,
                currentZoom: 1, showsZoomPresets: false,
                onSetMode: { _ in }, onShutter: {}, onFlip: {}, onOpenStack: {},
                onSelectZoomPreset: { _ in }
            )
        }
    }
}

#Preview("Bottom bar — with stack") {
    ZStack {
        Color.black
        VStack { Spacer()
            FCLCameraBottomBar(
                mode: .photo, isRecording: false, allowsVideo: true,
                capturedCount: 3, latestThumbnail: nil, canShowStack: true,
                currentZoom: 1, showsZoomPresets: true,
                onSetMode: { _ in }, onShutter: {}, onFlip: {}, onOpenStack: {},
                onSelectZoomPreset: { _ in }
            )
        }
    }
}
#endif

#endif
