#if canImport(UIKit)
import SwiftUI

/// Bottom-left stack counter showing how many assets have been captured in
/// a multi-capture session. Tapping it finishes the session.
///
/// Renders as a single 56×56 rounded tile with a 2pt white border. A yellow
/// circular count badge is shown at the top-trailing corner only when
/// `count > 1`.
struct FCLCameraStackCounter: View {
    let count: Int
    let latestThumbnail: UIImage?
    let action: () -> Void

    private let tileSize: CGFloat = 56
    private let cornerRadius: CGFloat = 6

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                tile
                if count > 1 {
                    badge
                        .offset(x: 6, y: -6)
                }
            }
            .frame(width: tileSize, height: tileSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(count) captured. Tap to finish."))
    }

    @ViewBuilder
    private var tile: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(Color.black.opacity(0.55))
            if let latestThumbnail {
                Image(uiImage: latestThumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: tileSize, height: tileSize)
                    .clipShape(shape)
            }
        }
        .frame(width: tileSize, height: tileSize)
        .overlay(shape.stroke(Color.white, lineWidth: 2))
    }

    private var badge: some View {
        Text("\(count)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.black)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Color.yellow))
    }
}

#if DEBUG
#Preview("Stack — count 1") {
    ZStack {
        Color.black
        FCLCameraStackCounter(count: 1, latestThumbnail: nil, action: {})
    }
}

#Preview("Stack — count 5") {
    ZStack {
        Color.black
        FCLCameraStackCounter(count: 5, latestThumbnail: nil, action: {})
    }
}
#endif

#endif
