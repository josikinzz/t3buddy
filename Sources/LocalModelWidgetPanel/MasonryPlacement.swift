import CoreGraphics
import Foundation

/// Places cards of fixed width and natural height into columns.
public enum MasonryPlacement {
    /// Puts each card, in source order, at the top of the shortest column. Ties go to the leftmost column.
    public static func place(
        heights: [CGFloat],
        columns: Int,
        gap: CGFloat,
        columnWidth: CGFloat = DashboardLayout.columnWidth
    ) -> [CGPoint] {
        stack(
            heights: heights,
            assignment: assign(heights: heights, columns: columns, gap: gap),
            gap: gap,
            columnWidth: columnWidth
        )
    }

    /// The column index for each card under the shortest-column rule.
    public static func assign(heights: [CGFloat], columns: Int, gap: CGFloat) -> [Int] {
        var nextY = [CGFloat](repeating: 0, count: max(1, columns))
        return heights.map { height in
            // min(by:) returns the first minimum, so ties go to the leftmost column.
            let column = nextY.indices.min { nextY[$0] < nextY[$1] } ?? 0
            nextY[column] += height + gap
            return column
        }
    }

    /// Stacks each card under the earlier cards of its assigned column, keeping source order.
    public static func stack(
        heights: [CGFloat],
        assignment: [Int],
        gap: CGFloat,
        columnWidth: CGFloat = DashboardLayout.columnWidth
    ) -> [CGPoint] {
        var nextY: [Int: CGFloat] = [:]
        return zip(heights, assignment).map { height, column in
            let y = nextY[column, default: 0]
            nextY[column] = y + height + gap
            return CGPoint(x: CGFloat(column) * (columnWidth + gap), y: y)
        }
    }

    /// The height from the top of the grid to the bottom of its lowest card.
    public static func contentHeight(heights: [CGFloat], points: [CGPoint]) -> CGFloat {
        zip(heights, points).map { $1.y + $0 }.max() ?? 0
    }
}

/// Remembers which column each card sits in, so a card that changes height only moves the
/// cards below it in its own column.
///
/// Columns are not frozen from the very first layout: at launch some cards show a short placeholder (the token
/// card reads its logs, the process card has not sampled yet), and packing on those heights leaves the grid
/// lopsided. Until every card reports it is ready, or `settleInterval` has passed since the first layout, the grid
/// repacks on every pass. From the pass where it settles, columns stick, and the grid repacks only when the card
/// order or column count changes.
public struct MasonryColumns: Equatable {
    /// The longest the grid waits for placeholder cards before it stops repacking on height changes.
    public static let defaultSettleInterval: TimeInterval = 10

    public private(set) var keys: [String] = []
    public private(set) var columns = 0
    public private(set) var assignment: [Int] = []
    /// When the first layout ran; the settle deadline counts from here.
    public private(set) var firstLayout: Date?
    /// True once every card was ready (or the deadline passed); columns stick from then on.
    public private(set) var settled = false
    public let settleInterval: TimeInterval

    public init(settleInterval: TimeInterval = defaultSettleInterval) {
        self.settleInterval = settleInterval
    }

    /// The column for each card. `ready[i]` is false while card `i` shows a placeholder height; a missing entry counts as ready.
    public mutating func assignment(
        keys: [String],
        heights: [CGFloat],
        ready: [Bool] = [],
        columns: Int,
        gap: CGFloat,
        now: Date = Date()
    ) -> [Int] {
        let firstLayout = firstLayout ?? now
        self.firstLayout = firstLayout
        let reshaped = keys != self.keys || columns != self.columns || assignment.count != heights.count
        if reshaped || settled == false {
            self.keys = keys
            self.columns = columns
            assignment = MasonryPlacement.assign(heights: heights, columns: columns, gap: gap)
        }
        if settled == false {
            let allReady = ready.allSatisfy { $0 }
            settled = allReady || now.timeIntervalSince(firstLayout) >= settleInterval
        }
        return assignment
    }
}
