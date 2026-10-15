import Foundation
import ModelWidgetCore

/// What the token usage card draws: today's fresh total, a zero-filled hourly series per provider for the
/// stacked area, and cache reads as their own series so they never stack into the fresh area (fork F7).
public struct TokenUsagePresentation: Equatable {
    public struct Point: Identifiable, Equatable {
        public let provider: TokenProvider
        public let hour: Date
        public let tokens: Int
        public var id: String { "\(provider.rawValue)-\(hour.timeIntervalSince1970)" }
    }

    public struct CachePoint: Identifiable, Equatable {
        public let hour: Date
        public let tokens: Int
        public var id: TimeInterval { hour.timeIntervalSince1970 }
    }

    public struct ProviderTotal: Identifiable, Equatable {
        public let provider: TokenProvider
        public let today: Int
        public let week: Int
        public var id: TokenProvider { provider }
    }

    /// Fresh input plus output since local midnight, all providers.
    public let todayTotal: Int
    public let todayText: String
    /// The 168 hour starts the graph covers, oldest first; the last is the current hour.
    public let hours: [Date]
    /// One point per hour per provider, in `TokenProvider.allCases` order within each hour.
    public let freshPoints: [Point]
    /// Cache reads per hour across providers.
    public let cachePoints: [CachePoint]
    public let cacheWeekTotal: Int
    /// Providers with any fresh usage in the window, in `TokenProvider.allCases` order.
    public let legend: [ProviderTotal]

    public static func make(
        buckets: [TokenBucket],
        now: Date,
        calendar: Calendar = .current,
        hourCount: Int = 7 * 24
    ) -> TokenUsagePresentation {
        let currentHour = (now.timeIntervalSince1970 / 3600).rounded(.down) * 3600
        let hours = (0..<hourCount).map { Date(timeIntervalSince1970: currentHour - Double(hourCount - 1 - $0) * 3600) }
        let first = hours.first ?? now
        let startOfDay = calendar.startOfDay(for: now)
        let inWindow = buckets.filter { $0.hour >= first && $0.hour <= now }

        var fresh: [TokenProvider: [Date: Int]] = [:]
        var cache: [Date: Int] = [:]
        for bucket in inWindow {
            fresh[bucket.provider, default: [:]][bucket.hour, default: 0] += bucket.fresh
            cache[bucket.hour, default: 0] += bucket.counts.cacheRead
        }

        let freshPoints = hours.flatMap { hour in
            TokenProvider.allCases.map { Point(provider: $0, hour: hour, tokens: fresh[$0]?[hour] ?? 0) }
        }
        let cachePoints = hours.map { CachePoint(hour: $0, tokens: cache[$0] ?? 0) }
        let legend: [ProviderTotal] = TokenProvider.allCases.compactMap { provider in
            let byHour = fresh[provider] ?? [:]
            let week = byHour.values.reduce(0, +)
            guard week > 0 else { return nil }
            let today = byHour.filter { $0.key >= startOfDay }.values.reduce(0, +)
            return ProviderTotal(provider: provider, today: today, week: week)
        }
        let todayTotal = legend.reduce(0) { $0 + $1.today }

        return TokenUsagePresentation(
            todayTotal: todayTotal,
            todayText: compact(todayTotal),
            hours: hours,
            freshPoints: freshPoints,
            cachePoints: cachePoints,
            cacheWeekTotal: cachePoints.reduce(0) { $0 + $1.tokens },
            legend: legend
        )
    }

    public static func empty(now: Date = Date(), calendar: Calendar = .current) -> TokenUsagePresentation {
        make(buckets: [], now: now, calendar: calendar)
    }

    /// `999`, `45.6k`, `456k`, `1.2M`, `12.3M`, `1.2B`.
    public static func compact(_ value: Int) -> String {
        let magnitude = Double(abs(value))
        let units: [(Double, String)] = [(1e9, "B"), (1e6, "M"), (1e3, "k")]
        for (scale, suffix) in units where magnitude >= scale {
            let scaled = Double(value) / scale
            let text = abs(scaled) >= 100 ? String(format: "%.0f", scaled) : String(format: "%.1f", scaled)
            return text + suffix
        }
        return "\(value)"
    }
}
