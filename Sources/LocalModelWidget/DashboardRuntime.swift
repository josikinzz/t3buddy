import AppKit
import LocalModelWidgetPanel
import SwiftUI

/// Owns the single transparent desktop-level window that hosts every card in a masonry grid.
/// Each card's runtime keeps its own refresh logic and timers; this only hosts them.
@MainActor
final class DashboardRuntime: ObservableObject {
    @Published private(set) var order: [DashboardCard]
    @Published private(set) var columns: Int
    /// The one Desktop/Float mode for the whole dashboard. Every card's gear menu binds to it.
    @Published private(set) var windowMode: DesktopPanelWindowMode = .desktop

    let model: DesktopPanelRuntime
    let subscriptions: SubscriptionPanelRuntime
    let process: ProcessPanelRuntime
    let tokenUsage: TokenUsageRuntime

    private let defaults: UserDefaults
    private var window: NSPanel?
    private var gridSize: CGSize = .zero
    private var screenObserver: NSObjectProtocol?

    init(
        model: DesktopPanelRuntime,
        subscriptions: SubscriptionPanelRuntime,
        process: ProcessPanelRuntime,
        tokenUsage: TokenUsageRuntime,
        defaults: UserDefaults = .standard
    ) {
        self.model = model
        self.subscriptions = subscriptions
        self.process = process
        self.tokenUsage = tokenUsage
        self.defaults = defaults
        self.order = DashboardCardOrder.load(from: defaults)
        self.columns = DashboardLayout.columnCount(screenWidth: NSScreen.main?.visibleFrame.width ?? 1080)
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        apply(windowMode, to: window)
        // The grid may have measured itself while the window was being built, before `window` was set.
        placeWindow()
        window.orderFrontRegardless()
        screenObserver = screenObserver ?? NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.screenDidChange() }
        }
    }

    func startRefreshing() {
        subscriptions.startRefreshing()
        model.startRefreshing()
        process.startRefreshing()
        tokenUsage.startRefreshing()
    }

    /// Drops `card` into the slot `target` holds and remembers the order.
    func move(_ card: DashboardCard, onto target: DashboardCard) {
        let moved = DashboardCardOrder.move(card, onto: target, in: order)
        guard moved != order else { return }
        order = moved
        DashboardCardOrder.save(moved, to: defaults)
    }

    /// The grid measured itself; resize the window around it, keeping its top-right corner in place.
    func fit(gridSize: CGSize) {
        guard gridSize.width > 0, gridSize.height > 0 else { return }
        self.gridSize = gridSize
        placeWindow()
    }

    /// A card's Desktop/Float picker changed. Every card's menu reads `windowMode`, so they all follow.
    func selectWindowMode(_ mode: DesktopPanelWindowMode) {
        guard mode != windowMode else { return }
        windowMode = mode
        guard let window else { return }
        apply(mode, to: window)
        window.orderFrontRegardless()
    }

    private func screenDidChange() {
        columns = DashboardLayout.columnCount(screenWidth: visibleFrame.width)
        placeWindow()
    }

    private var visibleFrame: NSRect {
        (window?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1080, height: 1920)
    }

    private func placeWindow() {
        guard let window, gridSize != .zero else { return }
        let frame = DashboardLayout.windowFrame(contentSize: gridSize, visibleFrame: visibleFrame).integral
        guard frame != window.frame else { return }
        window.setFrame(frame, display: true)
    }

    private func makeWindow() -> NSPanel {
        let hostingView = NSHostingView(rootView: DashboardView(dashboard: self))
        // The window follows the measured grid, not the hosting view's own size preferences.
        hostingView.sizingOptions = []
        let initialSize = CGSize(width: DashboardLayout.gridWidth(columns: columns), height: 400)
        let panel = NSPanel(
            contentRect: DashboardLayout.windowFrame(contentSize: initialSize, visibleFrame: visibleFrame),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Dashboard"
        panel.contentView = hostingView
        // Dragging a card reorders the grid, so the background must not move the window.
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // Cards draw their own shadows; a window shadow would outline the transparent frame.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func apply(_ mode: DesktopPanelWindowMode, to window: NSPanel) {
        window.collectionBehavior = mode.collectionBehavior
        window.level = mode.windowLevel
    }
}
