import SwiftUI

/// The id a subview of `MasonryLayout` keeps across height changes. Set it with `.masonryKey(_:)`.
public struct MasonryKey: LayoutValueKey {
    public static let defaultValue = ""
}

/// False while a subview shows a placeholder height (still loading). Set it with `.masonryReady(_:)`.
public struct MasonryReady: LayoutValueKey {
    public static let defaultValue = true
}

public extension View {
    func masonryKey(_ key: String) -> some View {
        layoutValue(key: MasonryKey.self, value: key)
    }

    /// Tells the grid whether this card's height is still a placeholder; the grid repacks until every card is ready.
    func masonryReady(_ ready: Bool) -> some View {
        layoutValue(key: MasonryReady.self, value: ready)
    }
}

/// A masonry grid of fixed-width columns. Each subview keeps its natural height; the grid places it
/// with `MasonryPlacement`. Once every subview is ready (see `MasonryColumns`), a subview keeps its column until
/// the subview order or column count changes.
public struct MasonryLayout: Layout {
    public var columns: Int
    public var columnWidth: CGFloat
    public var gap: CGFloat

    public init(
        columns: Int,
        columnWidth: CGFloat = DashboardLayout.columnWidth,
        gap: CGFloat = DashboardLayout.gap
    ) {
        self.columns = max(1, columns)
        self.columnWidth = columnWidth
        self.gap = gap
    }

    public struct Cache {
        var columns = MasonryColumns()
    }

    public func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    /// Keep the column assignment between updates; `points` decides when to repack.
    public func updateCache(_ cache: inout Cache, subviews: Subviews) {}

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let heights = heights(of: subviews)
        let points = points(heights: heights, subviews: subviews, cache: &cache)
        return CGSize(
            width: DashboardLayout.gridWidth(columns: columns, columnWidth: columnWidth, gap: gap),
            height: MasonryPlacement.contentHeight(heights: heights, points: points)
        )
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let heights = heights(of: subviews)
        let points = points(heights: heights, subviews: subviews, cache: &cache)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + points[index].x, y: bounds.minY + points[index].y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: columnWidth, height: heights[index])
            )
        }
    }

    private func heights(of subviews: Subviews) -> [CGFloat] {
        subviews.map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }
    }

    private func points(heights: [CGFloat], subviews: Subviews, cache: inout Cache) -> [CGPoint] {
        let assignment = cache.columns.assignment(
            keys: subviews.map { $0[MasonryKey.self] },
            heights: heights,
            ready: subviews.map { $0[MasonryReady.self] },
            columns: columns,
            gap: gap
        )
        return MasonryPlacement.stack(heights: heights, assignment: assignment, gap: gap, columnWidth: columnWidth)
    }
}
