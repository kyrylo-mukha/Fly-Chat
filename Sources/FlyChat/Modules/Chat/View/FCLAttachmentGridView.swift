import Foundation
import SwiftUI

// MARK: - Legacy Row-Based Grid Layout (preserved for test compatibility)

/// Utility that computes a row-based grid layout for attachment thumbnails.
///
/// This legacy helper is preserved for test coverage and backward compatibility.
/// New rendering uses ``FCLAttachmentGridLayoutPlanner`` for Telegram-style dynamic layouts.
enum FCLAttachmentGridLayout {
    /// Returns row-based layout as array of arrays of indices.
    /// - 1 item: [[0]]
    /// - 2 items: [[0, 1]]
    /// - 3 items: [[0], [1, 2]]
    /// - 4 items: [[0, 1], [2, 3]]
    /// - 5 items: [[0, 1], [2, 3], [4]]
    ///
    /// - Parameter count: The total number of items to lay out.
    /// - Returns: An array of rows, where each row is an array of item indices.
    static func grid(for count: Int) -> [[Int]] {
        guard count > 0 else { return [] }
        if count == 1 { return [[0]] }
        if count == 2 { return [[0, 1]] }
        if count == 3 { return [[0], [1, 2]] }
        var rows: [[Int]] = []
        var i = 0
        while i < count {
            if i + 1 < count {
                rows.append([i, i + 1])
                i += 2
            } else {
                rows.append([i])
                i += 1
            }
        }
        return rows
    }
}

// MARK: - Telegram-Style Dynamic Grid Layout

/// A computed frame for a single cell within an attachment grid.
struct FCLGridCellFrame {
    /// Index into the attachments array that this frame represents.
    let index: Int
    /// Frame in the grid's local coordinate space (origin at top-left of the grid content area).
    let rect: CGRect
}

/// Telegram-inspired dynamic grid layout planner for up to 4 attachments.
///
/// For 5+ attachments the planner falls back to paired-row layout.
/// All computations are in the grid's local coordinate space. The caller is responsible
/// for applying `insets` as outer padding and for positioning cells.
enum FCLAttachmentGridLayoutPlanner {

    // MARK: - Public entry point

    /// Computes cell frames for all attachments and the total grid height.
    ///
    /// - Parameters:
    ///   - attachments: The attachments to lay out.
    ///   - aspects: Known aspect ratios (width / height) keyed by attachment ID.
    ///             Missing entries default to `4/3`.
    ///   - maxWidth: Full available width (outer bubble width, before insets).
    ///   - spacing: Gap between adjacent cells.
    ///   - insets: Outer padding to subtract from the available width.
    /// - Returns: Cell frames in local coordinate space and the total grid height (including insets).
    static func plan(
        attachments: [FCLAttachment],
        aspects: [UUID: CGFloat],
        maxWidth: CGFloat,
        spacing: CGFloat,
        insets: FCLEdgeInsets
    ) -> (frames: [FCLGridCellFrame], totalHeight: CGFloat) {
        guard !attachments.isEmpty else { return ([], 0) }

        let innerWidth = max(1, maxWidth - insets.leading - insets.trailing)
        let count = attachments.count

        let resolvedAspects: [CGFloat] = attachments.map { att in
            aspects[att.id] ?? (4.0 / 3.0)
        }

        let localFrames: [FCLGridCellFrame]
        let innerHeight: CGFloat

        switch count {
        case 1:
            (localFrames, innerHeight) = layout1(aspects: resolvedAspects, width: innerWidth)
        case 2:
            (localFrames, innerHeight) = layout2(aspects: resolvedAspects, width: innerWidth, spacing: spacing)
        case 3:
            (localFrames, innerHeight) = layout3(aspects: resolvedAspects, width: innerWidth, spacing: spacing)
        case 4:
            (localFrames, innerHeight) = layout4(aspects: resolvedAspects, width: innerWidth, spacing: spacing)
        default:
            (localFrames, innerHeight) = layoutPairedRows(aspects: resolvedAspects, width: innerWidth, spacing: spacing)
        }

        // Offset all frames by the leading + top insets so they live in the outer coordinate space.
        let offsetFrames = localFrames.map { cell in
            FCLGridCellFrame(
                index: cell.index,
                rect: CGRect(
                    x: cell.rect.origin.x + insets.leading,
                    y: cell.rect.origin.y + insets.top,
                    width: cell.rect.width,
                    height: cell.rect.height
                )
            )
        }

        let totalHeight = innerHeight + insets.top + insets.bottom
        return (offsetFrames, totalHeight)
    }

    // MARK: - Per-count layouts

    private static func layout1(aspects: [CGFloat], width: CGFloat) -> ([FCLGridCellFrame], CGFloat) {
        let aspect = aspects[0]
        let maxHeight: CGFloat = 320
        let height = min(width / aspect, maxHeight)
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        return ([FCLGridCellFrame(index: 0, rect: frame)], height)
    }

    private static func layout2(aspects: [CGFloat], width: CGFloat, spacing: CGFloat) -> ([FCLGridCellFrame], CGFloat) {
        let a0 = aspects[0], a1 = aspects[1]
        let class0 = aspectClass(a0), class1 = aspectClass(a1)

        // Mixed portrait+landscape: stack vertically (each row full width)
        if class0 != class1, (class0 == .narrow || class1 == .narrow) {
            let h0 = width / a0
            let h1 = width / a1
            let totalH = h0 + spacing + h1
            let f0 = CGRect(x: 0, y: 0, width: width, height: h0)
            let f1 = CGRect(x: 0, y: h0 + spacing, width: width, height: h1)
            return ([.init(index: 0, rect: f0), .init(index: 1, rect: f1)], totalH)
        }

        // Same class (both wide/square/narrow): side by side, equal row height
        let rowH = (width - spacing) / (a0 + a1)
        let w0 = rowH * a0
        let w1 = rowH * a1
        let f0 = CGRect(x: 0, y: 0, width: w0, height: rowH)
        let f1 = CGRect(x: w0 + spacing, y: 0, width: w1, height: rowH)
        return ([.init(index: 0, rect: f0), .init(index: 1, rect: f1)], rowH)
    }

    private static func layout3(aspects: [CGFloat], width: CGFloat, spacing: CGFloat) -> ([FCLGridCellFrame], CGFloat) {
        let a0 = aspects[0], a1 = aspects[1], a2 = aspects[2]
        let c0 = aspectClass(a0), c1 = aspectClass(a1), c2 = aspectClass(a2)

        // One narrow portrait + two wide/square: portrait column on left, two stacked on right
        if c0 == .narrow && c1 != .narrow && c2 != .narrow {
            return layout3PortraitLeft(aspects: aspects, width: width, spacing: spacing)
        }
        if c1 == .narrow && c0 != .narrow && c2 != .narrow {
            // Rearrange: put the narrow one first for the portrait-left layout
            let reordered = [aspects[1], aspects[0], aspects[2]]
            let (frames, h) = layout3PortraitLeft(aspects: reordered, width: width, spacing: spacing)
            let remapped = frames.map { f -> FCLGridCellFrame in
                let originalIndex = [1, 0, 2][f.index]
                return FCLGridCellFrame(index: originalIndex, rect: f.rect)
            }
            return (remapped, h)
        }
        if c2 == .narrow && c0 != .narrow && c1 != .narrow {
            let reordered = [aspects[2], aspects[0], aspects[1]]
            let (frames, h) = layout3PortraitLeft(aspects: reordered, width: width, spacing: spacing)
            let remapped = frames.map { f -> FCLGridCellFrame in
                let originalIndex = [2, 0, 1][f.index]
                return FCLGridCellFrame(index: originalIndex, rect: f.rect)
            }
            return (remapped, h)
        }

        // All narrow: three columns in one row
        if c0 == .narrow && c1 == .narrow && c2 == .narrow {
            let totalAspect = a0 + a1 + a2
            let rowH = (width - 2 * spacing) / totalAspect
            var x: CGFloat = 0
            var frames: [FCLGridCellFrame] = []
            for (i, a) in [a0, a1, a2].enumerated() {
                let w = rowH * a
                frames.append(.init(index: i, rect: CGRect(x: x, y: 0, width: w, height: rowH)))
                x += w + spacing
            }
            return (frames, rowH)
        }

        // Default: one on top, two on bottom
        let topH = (width) / a0
        let bottomRowH = (width - spacing) / (a1 + a2)
        let w1 = bottomRowH * a1
        let w2 = bottomRowH * a2
        let totalH = topH + spacing + bottomRowH
        let f0 = CGRect(x: 0, y: 0, width: width, height: topH)
        let f1 = CGRect(x: 0, y: topH + spacing, width: w1, height: bottomRowH)
        let f2 = CGRect(x: w1 + spacing, y: topH + spacing, width: w2, height: bottomRowH)
        return ([.init(index: 0, rect: f0), .init(index: 1, rect: f1), .init(index: 2, rect: f2)], totalH)
    }

    /// Layout for 3 items where item[0] is portrait: portrait column on left, items[1]+[2] stacked on right.
    private static func layout3PortraitLeft(aspects: [CGFloat], width: CGFloat, spacing: CGFloat) -> ([FCLGridCellFrame], CGFloat) {
        let a0 = aspects[0], a1 = aspects[1], a2 = aspects[2]
        // Left column width derived from portrait column filling available height
        // Right side is (width - spacing - leftW). Try balancing so heights match.
        // Left column height = leftW / a0
        // Right col: rowH1 = rightW/a1, rowH2 = rightW/a2 → total right = rightW/a1 + spacing + rightW/a2
        // Equate: leftW/a0 = rightW*(1/a1 + 1/a2) + spacing  → approx leftW/a0 ≈ rightW*(1/a1+1/a2)
        let rightSumInvAspect = 1.0 / a1 + 1.0 / a2
        let leftW = (width - spacing) / (1.0 / a0 * 1.0 / rightSumInvAspect + 1.0)
        // Safe fallback: split evenly
        let safeLeftW = leftW.isFinite && leftW > 0 ? min(leftW, width * 0.6) : width / 2
        let rightW = width - safeLeftW - spacing
        let leftH = safeLeftW / a0
        let rowH1 = rightW / a1
        let rowH2 = rightW / a2
        let totalH = max(leftH, rowH1 + spacing + rowH2)

        let f0 = CGRect(x: 0, y: 0, width: safeLeftW, height: totalH)
        let f1 = CGRect(x: safeLeftW + spacing, y: 0, width: rightW, height: rowH1)
        let f2 = CGRect(x: safeLeftW + spacing, y: rowH1 + spacing, width: rightW, height: rowH2)
        return ([.init(index: 0, rect: f0), .init(index: 1, rect: f1), .init(index: 2, rect: f2)], totalH)
    }

    private static func layout4(aspects: [CGFloat], width: CGFloat, spacing: CGFloat) -> ([FCLGridCellFrame], CGFloat) {
        let a0 = aspects[0], a1 = aspects[1], a2 = aspects[2], a3 = aspects[3]
        let c0 = aspectClass(a0), c1 = aspectClass(a1), c2 = aspectClass(a2), c3 = aspectClass(a3)

        // One narrow + three others: narrow on left, three stacked on right
        let narrowIndices = [c0, c1, c2, c3].enumerated().filter { $0.element == .narrow }.map { $0.offset }
        if narrowIndices.count == 1 {
            let narrowIdx = narrowIndices[0]
            let otherIndices = (0..<4).filter { $0 != narrowIdx }
            let narrowAspect = aspects[narrowIdx]
            let otherAspects = otherIndices.map { aspects[$0] }
            let (frames, h) = layout4NarrowLeft(
                narrowAspect: narrowAspect,
                otherAspects: otherAspects,
                width: width, spacing: spacing
            )
            // Remap indices back to original
            var remapped: [FCLGridCellFrame] = []
            for f in frames {
                let originalIndex: Int
                if f.index == 0 {
                    originalIndex = narrowIdx
                } else {
                    originalIndex = otherIndices[f.index - 1]
                }
                remapped.append(FCLGridCellFrame(index: originalIndex, rect: f.rect))
            }
            return (remapped, h)
        }

        // All narrow: 2x2 grid scaled down
        if narrowIndices.count == 4 {
            return layout4Grid2x2(aspects: aspects, width: width, spacing: spacing)
        }

        // Default: 2x2 uniform grid
        return layout4Grid2x2(aspects: aspects, width: width, spacing: spacing)
    }

    /// 2x2 grid with aspect-aware row heights.
    private static func layout4Grid2x2(aspects: [CGFloat], width: CGFloat, spacing: CGFloat) -> ([FCLGridCellFrame], CGFloat) {
        // Row 0: items 0 and 1
        let rowH0 = (width - spacing) / (aspects[0] + aspects[1])
        let w0 = rowH0 * aspects[0]
        let w1 = rowH0 * aspects[1]
        // Row 1: items 2 and 3
        let rowH1 = (width - spacing) / (aspects[2] + aspects[3])
        let w2 = rowH1 * aspects[2]
        let w3 = rowH1 * aspects[3]
        let totalH = rowH0 + spacing + rowH1

        let f0 = CGRect(x: 0, y: 0, width: w0, height: rowH0)
        let f1 = CGRect(x: w0 + spacing, y: 0, width: w1, height: rowH0)
        let f2 = CGRect(x: 0, y: rowH0 + spacing, width: w2, height: rowH1)
        let f3 = CGRect(x: w2 + spacing, y: rowH0 + spacing, width: w3, height: rowH1)
        return ([
            .init(index: 0, rect: f0),
            .init(index: 1, rect: f1),
            .init(index: 2, rect: f2),
            .init(index: 3, rect: f3)
        ], totalH)
    }

    /// Narrow portrait item on the left column; three others stacked in a right column.
    private static func layout4NarrowLeft(
        narrowAspect: CGFloat,
        otherAspects: [CGFloat],
        width: CGFloat,
        spacing: CGFloat
    ) -> ([FCLGridCellFrame], CGFloat) {
        // Balance left column height with right column total height
        let rightSumInvAspect = otherAspects.reduce(0) { $0 + 1.0 / $1 }
        let leftW = (width - spacing) / (1.0 / narrowAspect / rightSumInvAspect + 1.0)
        let safeLeftW = leftW.isFinite && leftW > 0 ? min(leftW, width * 0.5) : width * 0.35
        let rightW = width - safeLeftW - spacing
        let leftH = safeLeftW / narrowAspect
        var rightFrames: [FCLGridCellFrame] = []
        var y: CGFloat = 0
        for (i, a) in otherAspects.enumerated() {
            let h = rightW / a
            rightFrames.append(.init(index: i + 1, rect: CGRect(x: safeLeftW + spacing, y: y, width: rightW, height: h)))
            y += h + (i < otherAspects.count - 1 ? spacing : 0)
        }
        let totalH = max(leftH, y)
        let f0 = CGRect(x: 0, y: 0, width: safeLeftW, height: totalH)
        return ([.init(index: 0, rect: f0)] + rightFrames, totalH)
    }

    /// Paired-row fallback for 5+ attachments (same grouping as the original algorithm,
    /// but uses per-row aspect-aware heights).
    private static func layoutPairedRows(aspects: [CGFloat], width: CGFloat, spacing: CGFloat) -> ([FCLGridCellFrame], CGFloat) {
        var rows: [[Int]] = []
        var i = 0
        while i < aspects.count {
            if i + 1 < aspects.count {
                rows.append([i, i + 1])
                i += 2
            } else {
                rows.append([i])
                i += 1
            }
        }

        var frames: [FCLGridCellFrame] = []
        var y: CGFloat = 0
        for (rowIdx, row) in rows.enumerated() {
            let rowAspects = row.map { aspects[$0] }
            let totalAspect = rowAspects.reduce(0, +)
            let innerSpacing = CGFloat(row.count - 1) * spacing
            let rowH = totalAspect > 0 ? (width - innerSpacing) / totalAspect : width / (4.0 / 3.0)
            var x: CGFloat = 0
            for (colIdx, idx) in row.enumerated() {
                let a = aspects[idx]
                let w = rowH * a
                frames.append(.init(index: idx, rect: CGRect(x: x, y: y, width: w, height: rowH)))
                x += w + (colIdx < row.count - 1 ? spacing : 0)
            }
            y += rowH + (rowIdx < rows.count - 1 ? spacing : 0)
        }
        return (frames, y)
    }

    // MARK: - Helpers

    private enum AspectClass { case wide, square, narrow }

    private static func aspectClass(_ aspect: CGFloat) -> AspectClass {
        if aspect >= 1.2 { return .wide }
        if aspect < 0.8 { return .narrow }
        return .square
    }
}

// MARK: - Attachment Grid View

#if canImport(UIKit)
import UIKit

/// Preference key used to aggregate per-cell window-space frames reported by the grid.
///
/// Each cell writes a single-entry dictionary keyed by `attachment.id.uuidString`; the
/// reduction merges entries so the grid surfaces one consolidated dictionary per update.
private struct FCLAttachmentCellFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Renders a grid of image and video attachment thumbnails inside a chat bubble.
///
/// Media attachments are arranged using a Telegram-inspired dynamic layout algorithm
/// that adapts cell sizes based on each image's aspect-ratio class (wide, square, narrow).
/// For 1–4 images the layout minimises cropping; for 5+ a paired-row fallback is used.
///
/// Each cell loads its thumbnail asynchronously via ``FCLAsyncThumbnailLoader``.
/// Video attachments display a centred play-button overlay.
///
/// Supply ``containerCorners`` to clip the grid container with an `UnevenRoundedRectangle`
/// whose corners match the enclosing bubble. Corners that touch an adjacent content element
/// (text row above or below) should be `0`; corners flush with the bubble edge inherit the
/// bubble's corner radius. Use ``FCLChatBubbleShape/imageContainerCorners(side:tailStyle:contentAbove:contentBelow:)``
/// to compute the right values.
struct FCLAttachmentGridView: View {
    /// The media attachments to display (filtered to `.image` and `.video` types only).
    let attachments: [FCLAttachment]
    /// The maximum width of the grid, matching the bubble's max width.
    let maxWidth: CGFloat
    /// Outer edge insets applied around the grid content area.
    var insets: FCLEdgeInsets = FCLEdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1)
    /// Spacing between adjacent cells.
    var itemSpacing: CGFloat = 1
    /// Optional hero namespace for matched geometry transitions.
    var heroNamespace: Namespace.ID?
    /// Called when the user taps an attachment thumbnail to open a preview.
    var onAttachmentTap: ((FCLAttachment) -> Void)?
    /// Optional callback invoked with the window-space frames of each rendered cell,
    /// keyed by `attachment.id.uuidString`.
    ///
    /// The grid measures every visible cell using a `GeometryReader` in `.global`
    /// coordinate space and reports the aggregated dictionary whenever it changes.
    /// Hosts use this to drive the media-preview dismiss animation, which needs to
    /// know where the originating cell currently is on screen.
    var onCellFramesChange: (([String: CGRect]) -> Void)?
    /// Invoked when the grid leaves the view hierarchy, passing the set of
    /// attachment keys that this grid was reporting. Hosts use this to
    /// prune stale entries from the preview-relay's window-frame cache so
    /// the media preview's dismiss animation never targets a frame for a
    /// cell that is no longer on screen.
    var onCellFramesInvalidate: ((Set<String>) -> Void)?
    /// Per-corner radii used to clip the image container with an `UnevenRoundedRectangle`.
    ///
    /// When `nil` (default) no additional clipping is applied — the parent bubble shape
    /// is relied upon to clip the grid (suitable for media-only bubbles where the bubble
    /// shape itself provides the mask). When non-nil, the grid is clipped to the given
    /// corner radii. Compute the correct values with
    /// ``FCLChatBubbleShape/imageContainerCorners(side:tailStyle:contentAbove:contentBelow:)``.
    var containerCorners: FCLBubbleCorners?

    /// Loaded thumbnail images keyed by attachment ID.
    @State private var thumbnailsByID: [UUID: UIImage] = [:]
    /// Measured aspect ratios (width/height) keyed by attachment ID.
    @State private var aspectByID: [UUID: CGFloat] = [:]

    var body: some View {
        let (frames, totalHeight) = FCLAttachmentGridLayoutPlanner.plan(
            attachments: attachments,
            aspects: aspectByID,
            maxWidth: maxWidth,
            spacing: itemSpacing,
            insets: insets
        )

        let gridContent = ZStack(alignment: .topLeading) {
            // Invisible full-size canvas
            Color.clear
                .frame(width: maxWidth, height: totalHeight)

            ForEach(frames, id: \.index) { cell in
                let attachment = attachments[cell.index]
                attachmentCell(attachment, frame: cell.rect)
                    .frame(width: cell.rect.width, height: cell.rect.height)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(
                                    key: FCLAttachmentCellFramesKey.self,
                                    value: [attachment.id.uuidString: geo.frame(in: .global)]
                                )
                        }
                    )
                    .position(
                        x: cell.rect.midX,
                        y: cell.rect.midY
                    )
            }
        }
        .frame(width: maxWidth, height: totalHeight)
        .onPreferenceChange(FCLAttachmentCellFramesKey.self) { newFrames in
            onCellFramesChange?(newFrames)
        }
        .onDisappear {
            // Prune this grid's keys from any parent-held frame cache.
            // Without this, a scrolled-off or disappearing row leaves stale
            // window-space rects in the cache, causing the preview's dismiss
            // animation to fly to a location that is no longer visible.
            let keys = Set(attachments.map { $0.id.uuidString })
            onCellFramesInvalidate?(keys)
        }

        if let corners = containerCorners {
            gridContent
                .clipShape(
                    UnevenRoundedRectangle(
                        cornerRadii: RectangleCornerRadii(
                            topLeading: corners.topLeft,
                            bottomLeading: corners.bottomLeft,
                            bottomTrailing: corners.bottomRight,
                            topTrailing: corners.topRight
                        )
                    )
                )
        } else {
            gridContent
        }
    }

    /// Renders a single attachment cell with an async-loaded thumbnail and an optional video overlay.
    @ViewBuilder
    private func attachmentCell(_ attachment: FCLAttachment, frame: CGRect) -> some View {
        Button {
            onAttachmentTap?(attachment)
        } label: {
            ZStack {
                imageLayer(for: attachment, size: frame.size)

                // Play overlay for video
                if attachment.type == .video {
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "play.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 20))
                        )
                }
            }
            .frame(width: frame.width, height: frame.height)
            .clipped()
        }
        .buttonStyle(.plain)
        .task(id: attachment.id) {
            await loadAspect(for: attachment)
        }
        .task(id: attachment.id) {
            await loadThumbnail(for: attachment, targetSize: CGSize(width: frame.width * 2, height: frame.height * 2))
        }
    }

    /// The image layer for a cell: async-loaded thumbnail, thumbnailData fallback, or placeholder.
    @ViewBuilder
    private func imageLayer(for attachment: FCLAttachment, size: CGSize) -> some View {
        if let loaded = thumbnailsByID[attachment.id] {
            if let ns = heroNamespace {
                Image(uiImage: loaded)
                    .resizable()
                    .scaledToFill()
                    .matchedGeometryEffect(id: attachment.id, in: ns)
            } else {
                Image(uiImage: loaded)
                    .resizable()
                    .scaledToFill()
            }
        } else if let data = attachment.thumbnailData, let image = UIImage(data: data) {
            if let ns = heroNamespace {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .matchedGeometryEffect(id: attachment.id, in: ns)
            } else {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: size.width, height: size.height)
        }
    }

    /// Loads the pixel size of an attachment and updates `aspectByID`.
    private func loadAspect(for attachment: FCLAttachment) async {
        guard aspectByID[attachment.id] == nil else { return }
        if let size = await FCLAsyncThumbnailLoader.shared.pixelSize(for: attachment), size.height > 0 {
            aspectByID[attachment.id] = size.width / size.height
        }
    }

    /// Loads a downscaled thumbnail for an attachment and updates `thumbnailsByID`.
    private func loadThumbnail(for attachment: FCLAttachment, targetSize: CGSize) async {
        guard thumbnailsByID[attachment.id] == nil else { return }
        if let image = await FCLAsyncThumbnailLoader.shared.thumbnail(for: attachment, targetSize: targetSize) {
            thumbnailsByID[attachment.id] = image
        }
    }
}

// MARK: - Previews

#if DEBUG

/// Generates a solid-color `UIImage` as preview thumbnail data.
private func previewThumbnailData(color: UIColor, size: CGSize = CGSize(width: 100, height: 100)) -> Data? {
    UIGraphicsBeginImageContextWithOptions(size, true, 1)
    color.setFill()
    UIRectFill(CGRect(origin: .zero, size: size))
    let image = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return image?.jpegData(compressionQuality: 0.8)
}

/// Makes a mock `FCLAttachment` with inline thumbnail data so previews render without disk I/O.
private func mockImageAttachment(
    color: UIColor,
    aspectWidth: CGFloat = 1,
    aspectHeight: CGFloat = 1,
    fileName: String = "mock.jpg"
) -> FCLAttachment {
    let thumbSize = CGSize(width: aspectWidth * 60, height: aspectHeight * 60)
    let data = previewThumbnailData(color: color, size: thumbSize)
    return FCLAttachment(
        type: .image,
        url: URL(string: "file:///tmp/\(fileName)")!,
        thumbnailData: data,
        fileName: fileName
    )
}

struct FCLAttachmentGridView_Previews: PreviewProvider {
    static var previews: some View {
        imageOnlyOutgoingPreview
        imageOnlyIncomingPreview
        imagePlusTextBelowPreview
        textAboveImagePreview
        multiImageGridPreview
    }

    // MARK: - Image-only bubble (outgoing, right side, edged bottom tail)
    // All four corners should match the bubble corners; bottom-right is reduced (tail).

    private static var imageOnlyOutgoingPreview: some View {
        let corners = FCLChatBubbleShape.imageContainerCorners(
            side: .right,
            tailStyle: .edged(.bottom),
            contentAbove: false,
            contentBelow: false
        )
        return ZStack {
            FCLChatBubbleShape(side: .right, tailStyle: .edged(.bottom))
                .fill(Color.blue)
                .frame(width: 280, height: 200)
            FCLAttachmentGridView(
                attachments: [
                    mockImageAttachment(color: .systemBlue, aspectWidth: 16, aspectHeight: 9, fileName: "out1.jpg")
                ],
                maxWidth: 280,
                containerCorners: corners
            )
        }
        .previewDisplayName("Image-Only — Outgoing (right, edged bottom)")
        .previewLayout(.sizeThatFits)
        .padding()
    }

    // MARK: - Image-only bubble (incoming, left side, edged bottom tail)
    // All four corners match bubble; bottom-left is reduced.

    private static var imageOnlyIncomingPreview: some View {
        let corners = FCLChatBubbleShape.imageContainerCorners(
            side: .left,
            tailStyle: .edged(.bottom),
            contentAbove: false,
            contentBelow: false
        )
        return ZStack {
            FCLChatBubbleShape(side: .left, tailStyle: .edged(.bottom))
                .fill(Color(red: 0.93, green: 0.93, blue: 0.95))
                .frame(width: 280, height: 200)
            FCLAttachmentGridView(
                attachments: [
                    mockImageAttachment(color: .systemGreen, aspectWidth: 4, aspectHeight: 3, fileName: "in1.jpg")
                ],
                maxWidth: 280,
                containerCorners: corners
            )
        }
        .previewDisplayName("Image-Only — Incoming (left, edged bottom)")
        .previewLayout(.sizeThatFits)
        .padding()
    }

    // MARK: - Image + text below (outgoing): top corners rounded, bottom corners square.

    private static var imagePlusTextBelowPreview: some View {
        let corners = FCLChatBubbleShape.imageContainerCorners(
            side: .right,
            tailStyle: .edged(.bottom),
            contentAbove: false,
            contentBelow: true
        )
        return VStack(spacing: 0) {
            FCLAttachmentGridView(
                attachments: [
                    mockImageAttachment(color: .systemOrange, aspectWidth: 4, aspectHeight: 3, fileName: "img_above.jpg"),
                    mockImageAttachment(color: .systemYellow, aspectWidth: 3, aspectHeight: 4, fileName: "img_above2.jpg")
                ],
                maxWidth: 280,
                containerCorners: corners
            )
            Text("Caption below the images")
                .font(.body)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
        .background(Color.blue)
        .clipShape(FCLChatBubbleShape(side: .right, tailStyle: .edged(.bottom)))
        .previewDisplayName("Image + Text Below — Outgoing (bottom corners square)")
        .previewLayout(.sizeThatFits)
        .padding()
    }

    // MARK: - Text above + image below (incoming): top corners square, bottom corners rounded.

    private static var textAboveImagePreview: some View {
        let corners = FCLChatBubbleShape.imageContainerCorners(
            side: .left,
            tailStyle: .edged(.bottom),
            contentAbove: true,
            contentBelow: false
        )
        return VStack(spacing: 0) {
            Text("Caption above the images")
                .font(.body)
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            FCLAttachmentGridView(
                attachments: [
                    mockImageAttachment(color: .systemPurple, aspectWidth: 3, aspectHeight: 5, fileName: "text_above.jpg"),
                    mockImageAttachment(color: .systemTeal, aspectWidth: 16, aspectHeight: 9, fileName: "text_above2.jpg")
                ],
                maxWidth: 280,
                containerCorners: corners
            )
        }
        .background(Color(red: 0.93, green: 0.93, blue: 0.95))
        .clipShape(FCLChatBubbleShape(side: .left, tailStyle: .edged(.bottom)))
        .previewDisplayName("Text Above + Image — Incoming (top corners square)")
        .previewLayout(.sizeThatFits)
        .padding()
    }

    // MARK: - Multi-image grid (4 images, no adjacent content) — both sides.

    private static var multiImageGridPreview: some View {
        let attachments: [FCLAttachment] = [
            mockImageAttachment(color: .systemRed, aspectWidth: 4, aspectHeight: 3, fileName: "r1.jpg"),
            mockImageAttachment(color: .systemYellow, aspectWidth: 1, aspectHeight: 1, fileName: "r2.jpg"),
            mockImageAttachment(color: .systemMint, aspectWidth: 3, aspectHeight: 4, fileName: "r3.jpg"),
            mockImageAttachment(color: .systemCyan, aspectWidth: 16, aspectHeight: 9, fileName: "r4.jpg")
        ]
        return VStack(spacing: 20) {
            // Outgoing
            FCLAttachmentGridView(
                attachments: attachments,
                maxWidth: 280,
                containerCorners: FCLChatBubbleShape.imageContainerCorners(
                    side: .right, tailStyle: .edged(.bottom), contentAbove: false, contentBelow: false
                )
            )
            .clipShape(FCLChatBubbleShape(side: .right, tailStyle: .edged(.bottom)))
            // Incoming
            FCLAttachmentGridView(
                attachments: attachments,
                maxWidth: 280,
                containerCorners: FCLChatBubbleShape.imageContainerCorners(
                    side: .left, tailStyle: .edged(.bottom), contentAbove: false, contentBelow: false
                )
            )
            .clipShape(FCLChatBubbleShape(side: .left, tailStyle: .edged(.bottom)))
        }
        .previewDisplayName("Multi-Image Grid — Both Sides (4 images)")
        .previewLayout(.sizeThatFits)
        .padding()
    }
}
#endif
#endif
