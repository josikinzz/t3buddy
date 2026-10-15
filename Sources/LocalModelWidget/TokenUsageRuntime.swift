import Foundation
import LocalModelWidgetPanel
import ModelWidgetCore

/// Refreshes the token usage card about once a minute. The reader scans the session logs on its own dispatch
/// queue, so the first full scan and every incremental refresh run off the main thread.
@MainActor
final class TokenUsageRuntime: ObservableObject {
    @Published private(set) var presentation: TokenUsagePresentation
    @Published private(set) var updated: Date?
    @Published private(set) var refreshing = false

    private let reader: TokenUsageReader
    private let refreshInterval: TimeInterval
    private let calendar: Calendar
    private var timer: Timer?

    init(
        reader: TokenUsageReader = TokenUsageReader(),
        refreshInterval: TimeInterval = 60,
        calendar: Calendar = .current
    ) {
        self.reader = reader
        self.refreshInterval = refreshInterval
        self.calendar = calendar
        self.presentation = .empty(calendar: calendar)
    }

    deinit {
        timer?.invalidate()
    }

    func startRefreshing() {
        timer?.invalidate()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func refresh() {
        guard refreshing == false else { return }
        refreshing = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let now = Date()
            let snapshot = await reader.refresh(now: now)
            presentation = TokenUsagePresentation.make(buckets: snapshot.buckets, now: now, calendar: calendar)
            updated = now
            refreshing = false
        }
    }
}
