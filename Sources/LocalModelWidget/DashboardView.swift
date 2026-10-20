import LocalModelWidgetPanel
import SwiftUI

struct DashboardView: View {
    @ObservedObject var dashboard: DashboardRuntime
    @State private var dragging: DashboardCard?
    @State private var dragOffset: CGSize = .zero
    @State private var dropTarget: DashboardCard?
    @State private var cardFrames: [DashboardCard: CGRect] = [:]

    private static let space = "dashboard"

    var body: some View {
        MasonryLayout(columns: dashboard.columns) {
            ForEach(dashboard.order) { card in
                cardView(card)
                    .shadow(color: .black.opacity(0.22), radius: 9, x: 0, y: 3)
                    .overlay {
                        if dropTarget == card {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 2)
                                .allowsHitTesting(false)
                        }
                    }
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: CardFramesKey.self, value: [card: proxy.frame(in: .named(Self.space))])
                        }
                    }
                    .opacity(dragging == card ? 0.85 : 1)
                    .offset(dragging == card ? dragOffset : .zero)
                    .gesture(reorderGesture(for: card))
                    .zIndex(dragging == card ? 1 : 0)
                    .masonryKey(card.rawValue)
            }
        }
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(CardFramesKey.self) { cardFrames = $0 }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { dashboard.fit(gridSize: $0) }
        .animation(.easeInOut(duration: 0.2), value: dashboard.order)
        .padding(DashboardLayout.shadowInset)
        .fixedSize()
        // Take exactly the window's size and pin the grid to its top edge; a grid taller than the
        // screen is clipped at the bottom instead of being centred off both edges.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func cardView(_ card: DashboardCard) -> some View {
        switch card {
        case .model: DesktopPanelView(runtime: dashboard.model, windowMode: windowMode)
        case .usage: SubscriptionPanelView(runtime: dashboard.subscriptions, windowMode: windowMode)
        case .process: ProcessPanelView(runtime: dashboard.process, windowMode: windowMode)
        case .tokens: TokenUsageCardView(runtime: dashboard.tokenUsage, windowMode: windowMode)
        }
    }

    /// The dashboard's one window mode, shown and set by every card's gear menu.
    private var windowMode: Binding<DesktopPanelWindowMode> {
        Binding(
            get: { dashboard.windowMode },
            set: { dashboard.selectWindowMode($0) }
        )
    }

    private func reorderGesture(for card: DashboardCard) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
            .onChanged { value in
                dragging = card
                dragOffset = value.translation
                dropTarget = target(at: value.location, excluding: card)
            }
            .onEnded { value in
                if let target = target(at: value.location, excluding: card) {
                    dashboard.move(card, onto: target)
                }
                dragging = nil
                dragOffset = .zero
                dropTarget = nil
            }
    }

    private func target(at location: CGPoint, excluding card: DashboardCard) -> DashboardCard? {
        cardFrames.first { $0.key != card && $0.value.contains(location) }?.key
    }
}

private struct CardFramesKey: PreferenceKey {
    static var defaultValue: [DashboardCard: CGRect] = [:]
    static func reduce(value: inout [DashboardCard: CGRect], nextValue: () -> [DashboardCard: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
