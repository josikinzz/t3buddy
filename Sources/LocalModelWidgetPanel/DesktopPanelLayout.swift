import AppKit

/// Card dimensions. The dashboard window and its placement live in `DashboardLayout`.
/// Every card takes its natural height; the process list is capped at 12 rows instead of scrolling.
public enum DesktopPanelLayout {
    public static let panelWidth: CGFloat = DashboardLayout.columnWidth
    public static let refreshInterval: TimeInterval = 3
}
