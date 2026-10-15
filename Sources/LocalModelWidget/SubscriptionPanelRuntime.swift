import AppKit
import LocalModelWidgetPanel
import ModelWidgetCore
import SwiftUI

/// Refreshes the subscription usage card (Claude, Codex and Kimi accounts) every 5 minutes, caching rows on disk.
@MainActor
final class SubscriptionPanelRuntime: ObservableObject {
    @Published var rows: [SubscriptionUsage] = []
    @Published var updated: Date?
    @Published var refreshing = false
    @Published var message: String?
    private var timer: Timer?
    private let cache = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/LocalModelWidget/subscriptions.json")

    init() {
        if let data = try? Data(contentsOf: cache), let rows = try? JSONDecoder().decode([SubscriptionUsage].self, from: data) {
            self.rows = rows
            updated = rows.compactMap(\.checked).min()
        }
    }

    func startRefreshing() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        Task {
            let fresh = await SubscriptionUsageReader.read()
            rows = fresh.map { row in
                guard row.error != nil, var previous = rows.first(where: { $0.id == row.id }), !previous.windows.isEmpty else { return row }
                previous.error = row.error
                return previous
            }
            message = fresh.isEmpty ? "No signed-in Codex or Claude accounts found" : nil
            updated = Date()
            refreshing = false
            if let data = try? JSONEncoder().encode(rows) {
                try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try? data.write(to: cache, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cache.path)
            }
        }
    }
}
