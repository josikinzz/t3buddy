import Foundation

/// Decides when the dashboard should hide other apps after the Mac sits untouched.
public struct IdleHidePolicy: Equatable, Sendable {
    public static let defaultsKey = "idleHideMinutes"
    public static let defaultMinutes = 10
    public static let choices = [0, 5, 10, 15, 30]

    /// Processes that keep the display awake on this machine without meaning someone is watching it.
    public static let ignoredDisplayAssertionOwners: Set<String> = ["caffeinate", "powerd"]

    public var minutes: Int
    /// Set after hiding so one idle stretch hides at most once; cleared by any input.
    public private(set) var hidForCurrentIdle = false
    /// Skip reasons already logged in this idle stretch; cleared by any input.
    public private(set) var reportedSkips: Set<String> = []

    public init(minutes: Int) {
        self.minutes = minutes
    }

    public enum Decision: Equatable, Sendable {
        case wait
        case hide
        case skip(String)
    }

    public mutating func evaluate(idleSeconds: TimeInterval, displayHeldBy: [String]) -> Decision {
        guard minutes > 0, idleSeconds >= TimeInterval(minutes * 60) else {
            if idleSeconds < 60 {
                hidForCurrentIdle = false
                reportedSkips = []
            }
            return .wait
        }
        guard !hidForCurrentIdle else { return .wait }
        let watchers = displayHeldBy.filter { !Self.ignoredDisplayAssertionOwners.contains($0) }
        if let first = watchers.first { return .skip("\(first) is keeping the display awake") }
        hidForCurrentIdle = true
        return .hide
    }

    /// True the first time `reason` comes up in the current idle stretch, so a skip logs once, not every tick.
    public mutating func shouldReportSkip(_ reason: String) -> Bool {
        reportedSkips.insert(reason).inserted
    }

    /// Reads the stored threshold as-is, so `defaults write … idleHideMinutes -int 1` works for testing.
    public static func minutes(fromDefaults value: Any?) -> Int {
        let minutes: Int?
        switch value {
        case let number as NSNumber: minutes = number.intValue
        case let text as String: minutes = Int(text.trimmingCharacters(in: .whitespaces))
        default: minutes = nil
        }
        guard let minutes, minutes >= 0 else { return defaultMinutes }
        return minutes
    }

    /// The menu choices, plus a stored value that is not one of them so the picker still shows it.
    public static func pickerChoices(including current: Int) -> [Int] {
        choices.contains(current) ? choices : (choices + [current]).sorted()
    }

    public static func choiceTitle(_ minutes: Int) -> String {
        minutes == 0 ? "Never" : "After \(minutes) min"
    }
}

/// The last time idle-hide fired, kept in user defaults as readable JSON for the gear menu and `defaults read`.
public struct IdleHideRecord: Codable, Equatable, Sendable {
    public static let defaultsKey = "lastIdleHide"

    public var date: Date
    public var appCount: Int

    public init(date: Date, appCount: Int) {
        self.date = date
        self.appCount = appCount
    }

    public func encodedString() -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    public static func decode(_ text: String?) -> IdleHideRecord? {
        guard let data = text?.data(using: .utf8), !data.isEmpty else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(IdleHideRecord.self, from: data)
    }

    /// `Last idle hide: 17:42, 6 apps`; a hide from an earlier day also names the day.
    public static func menuLabel(_ record: IdleHideRecord?, now: Date, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        guard let record else { return "Last idle hide: never" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        var when = formatter.string(from: record.date)
        if !calendar.isDate(record.date, inSameDayAs: now) {
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
            when = "\(formatter.string(from: record.date)) \(when)"
        }
        return "Last idle hide: \(when), \(record.appCount) \(record.appCount == 1 ? "app" : "apps")"
    }
}
