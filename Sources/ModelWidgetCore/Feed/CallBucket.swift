import Foundation

/// The cap on T3 tool calls (spec §2.3): a bucket of `capacity` calls, refilled at `rate` a
/// second. A call that finds it empty is not refused; it is told how long to wait, so calls
/// queue behind each other and the sustained rate never passes `rate`.
public struct CallBucket: Sendable, Equatable {
    public static let t3 = CallBucket(capacity: 10, rate: 3)

    public let capacity: Double
    public let rate: Double
    /// Below zero while calls wait: each owes its share of the refill.
    private var tokens: Double
    private var at: Date?

    public init(capacity: Double, rate: Double) {
        self.capacity = capacity
        self.rate = rate
        tokens = capacity
    }

    /// Spends one call and returns how long to wait before making it: 0 while the bucket has one.
    public mutating func take(now: Date) -> TimeInterval {
        if let at { tokens = min(capacity, tokens + max(0, now.timeIntervalSince(at)) * rate) }
        at = now
        tokens -= 1
        return tokens >= 0 ? 0 : -tokens / rate
    }
}
