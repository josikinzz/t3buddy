import Foundation

/// Grok Bot's own cached reading of its weekly usage, read-only and offline.
///
/// Grok Bot keeps it in the blob for `sand.client.slice.account.<account>.weekly-usage.cache` (named as in
/// `GrokRosterReader`): `{"schemaVersion":2,"value":{"kind":"present"|"absent","selectedTeamId":…,
/// "expiresAtMs":…,"reading":{"readAtMs":…,"usage":{"percentUsed":…,"nextResetMs":…,"isSandTrial":…,
/// "hasNonZeroIncludedLimit":…,"isTeamSeat":…,"onDemand":null|{"usedCents":…,"limitCents":…},
/// "grokPlanLabel":…}}}}`. It holds no email. Grok Bot rewrites it only when it launches or its account
/// menu opens, so a reading is often a day or more old, and the card says how old.
public enum GrokUsageReader {
    public static let supportedSchemaVersion = 2
    public static let provider = "Grok Bot"
    private static let usageSuffix = ".weekly-usage.cache"

    public enum Reading: Equatable, Sendable {
        case absent
        case present(Usage)
    }

    public struct Usage: Equatable, Sendable {
        public var checked: Date
        public var expires: Date
        public var reset: Date
        public var percentUsed: Double
        public var hasIncludedLimit: Bool
        public var planLabel: String
        public var isTrial: Bool
        public var onDemand: OnDemand?

        public func freshness(at now: Date) -> Freshness {
            if now >= reset { return .pastReset }
            if now >= expires { return .stale }
            return .current
        }
    }

    public struct OnDemand: Equatable, Sendable {
        public var usedCents: Double
        public var limitCents: Double
    }

    public enum Freshness: Equatable, Sendable {
        case current
        /// Past Grok Bot's own expiry but still in the week it was read in.
        case stale
        /// The week it was read in is over, so its percent no longer applies.
        case pastReset
    }

    /// The newest reading among the account blobs in `persistenceFolder`, as the card's row; nil when there is none.
    public static func read(persistenceFolder: URL = GrokOrbitSource.defaultPersistenceFolder, now: Date) -> SubscriptionUsage? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: persistenceFolder.path) else { return nil }
        let readings = names.compactMap { name -> Reading? in
            guard let key = GrokRosterReader.persistenceKey(forBlobFileName: name),
                  key.hasPrefix(GrokRosterReader.accountPrefix), key.hasSuffix(usageSuffix),
                  let data = try? Data(contentsOf: persistenceFolder.appendingPathComponent(name)) else { return nil }
            return parse(data)
        }
        let newest = readings.max { checked($0) < checked($1) }
        return newest.map { row($0, now: now) }
    }

    /// nil for an unreadable blob or another schema version.
    public static func parse(_ data: Data) -> Reading? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (object["schemaVersion"] as? NSNumber)?.intValue == supportedSchemaVersion,
              let value = object["value"] as? [String: Any] else { return nil }
        switch value["kind"] as? String {
        case "absent":
            return .absent
        case "present":
            guard let reading = value["reading"] as? [String: Any],
                  let usage = reading["usage"] as? [String: Any],
                  let checked = milliseconds(reading["readAtMs"]),
                  let expires = milliseconds(value["expiresAtMs"]),
                  let reset = milliseconds(usage["nextResetMs"]),
                  let percent = number(usage["percentUsed"]) else { return nil }
            let onDemand = (usage["onDemand"] as? [String: Any]).flatMap { entry -> OnDemand? in
                guard let used = number(entry["usedCents"]), let limit = number(entry["limitCents"]) else { return nil }
                return OnDemand(usedCents: used, limitCents: limit)
            }
            return .present(Usage(
                checked: checked,
                expires: expires,
                reset: reset,
                percentUsed: min(100, max(0, percent)),
                hasIncludedLimit: (usage["hasNonZeroIncludedLimit"] as? Bool) ?? false,
                planLabel: (usage["grokPlanLabel"] as? String) ?? "",
                isTrial: (usage["isSandTrial"] as? Bool) ?? false,
                onDemand: onDemand
            ))
        default:
            return nil
        }
    }

    /// The card's row for a reading at `now`: a stale reading is marked, and one from before the weekly reset shows no percent.
    public static func row(_ reading: Reading, now: Date) -> SubscriptionUsage {
        var row = SubscriptionUsage(id: provider, provider: provider, email: "", plan: "", windows: [], checked: nil)
        guard case let .present(usage) = reading else {
            row.note = "No usage reading in Grok Bot"
            return row
        }
        row.plan = [usage.planLabel, usage.isTrial ? "Trial" : ""].filter { !$0.isEmpty }.joined(separator: " ")
        row.checked = usage.checked
        let checked = "Checked \(age(since: usage.checked, now: now)) in Grok Bot"
        switch usage.freshness(at: now) {
        case .pastReset:
            row.note = "No reading since the weekly reset · \(checked)"
            return row
        case .stale:
            row.error = checked
        case .current:
            row.note = checked
        }
        if usage.hasIncludedLimit {
            row.windows.append(UsageWindow(id: "grok-weekly", title: "Weekly", used: usage.percentUsed, reset: usage.reset))
        } else {
            row.note = ["No included weekly usage on this plan", row.note].compactMap { $0 }.joined(separator: " · ")
        }
        if let onDemand = usage.onDemand, onDemand.limitCents > 0 {
            row.windows.append(UsageWindow(id: "grok-on-demand", title: "On-demand", used: min(100, max(0, onDemand.usedCents / onDemand.limitCents * 100)), reset: nil))
        }
        return row
    }

    private static func age(since checked: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(checked) / 60))
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        if minutes < 48 * 60 { return "\(minutes / 60)h ago" }
        return "\(minutes / (24 * 60))d ago"
    }

    private static func checked(_ reading: Reading) -> Date {
        if case let .present(usage) = reading { return usage.checked }
        return .distantPast
    }

    private static func milliseconds(_ value: Any?) -> Date? {
        number(value).map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    private static func number(_ value: Any?) -> Double? {
        // A JSON 0 or 1 also casts to Bool, so tell true/false apart by their CF type.
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }
}
