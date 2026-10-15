import AppKit

/// Every card the dashboard can host. Add a case to add a card; a saved order picks it up at the end.
public enum DashboardCard: String, CaseIterable, Codable, Identifiable {
    case model
    case usage
    case process
    case tokens

    public var id: Self { self }
}

/// The user's card order, kept as a list of card ids in user defaults.
public enum DashboardCardOrder {
    public static let defaultsKey = "dashboardCardOrder"

    /// Reads a stored id list: unknown ids and repeats drop out, and cards missing from it follow in default order.
    public static func resolve(_ stored: [String]?) -> [DashboardCard] {
        var order: [DashboardCard] = []
        for card in (stored ?? []).compactMap(DashboardCard.init(rawValue:)) where order.contains(card) == false {
            order.append(card)
        }
        return order + DashboardCard.allCases.filter { order.contains($0) == false }
    }

    /// Moves `card` into the slot `target` holds now.
    public static func move(_ card: DashboardCard, onto target: DashboardCard, in order: [DashboardCard]) -> [DashboardCard] {
        guard card != target, let targetIndex = order.firstIndex(of: target), order.contains(card) else { return order }
        var moved = order
        moved.removeAll { $0 == card }
        moved.insert(card, at: min(targetIndex, moved.count))
        return moved
    }

    public static func load(from defaults: UserDefaults = .standard) -> [DashboardCard] {
        resolve(defaults.stringArray(forKey: defaultsKey))
    }

    public static func save(_ order: [DashboardCard], to defaults: UserDefaults = .standard) {
        defaults.set(order.map(\.rawValue), forKey: defaultsKey)
    }
}

/// Geometry of the single dashboard window: 332 pt columns, at most three, anchored top right.
/// Three columns fill the 1080 pt portrait screen: 3 × 332 + 2 × 16 = 1028 ≤ 1080 − 2 × 24.
public enum DashboardLayout {
    public static let columnWidth: CGFloat = 332
    public static let gap: CGFloat = 16
    public static let maxColumns = 3
    /// Distance from the right edge of the visible screen to the grid.
    public static let screenMargin: CGFloat = 24
    /// Distance from the top of the visible screen to the grid.
    public static let topMargin: CGFloat = 32
    /// Transparent border inside the window so card shadows are not clipped.
    public static let shadowInset: CGFloat = 16

    public static func columnCount(screenWidth: CGFloat) -> Int {
        let available = screenWidth - screenMargin * 2
        let fitting = Int(((available + gap) / (columnWidth + gap)).rounded(.down))
        return min(maxColumns, max(1, fitting))
    }

    public static func gridWidth(columns: Int, columnWidth: CGFloat = columnWidth, gap: CGFloat = gap) -> CGFloat {
        let columns = CGFloat(max(1, columns))
        return columnWidth * columns + gap * (columns - 1)
    }

    /// The window frame for a grid of `contentSize`, keeping the grid's top-right corner fixed on screen.
    public static func windowFrame(contentSize: CGSize, visibleFrame: NSRect) -> NSRect {
        let top = visibleFrame.maxY - topMargin + shadowInset
        let height = min(contentSize.height + shadowInset * 2, top - visibleFrame.minY)
        let width = contentSize.width + shadowInset * 2
        return NSRect(
            x: visibleFrame.maxX - screenMargin + shadowInset - width,
            y: top - height,
            width: width,
            height: height
        )
    }
}
