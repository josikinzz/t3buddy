import Foundation
import ModelWidgetCore

extension ModelWidgetChecks {
    static func idleHideEvidenceChecks(_ suite: inout CheckSuite) async {
        let utc = TimeZone(identifier: "UTC")!
        let at1742 = Date(timeIntervalSince1970: 1_791_999_720) // 17:42 UTC

        suite.check("Idle hide minutes from defaults accept a 1-minute override and fall back to the default") {
            try expectEqual(IdleHidePolicy.minutes(fromDefaults: 1), 1)
            try expectEqual(IdleHidePolicy.minutes(fromDefaults: NSNumber(value: 1)), 1)
            try expectEqual(IdleHidePolicy.minutes(fromDefaults: "2"), 2)
            try expectEqual(IdleHidePolicy.minutes(fromDefaults: 15), 15)
            try expectEqual(IdleHidePolicy.minutes(fromDefaults: 0), 0)
            try expectEqual(IdleHidePolicy.minutes(fromDefaults: nil), IdleHidePolicy.defaultMinutes)
            try expectEqual(IdleHidePolicy.minutes(fromDefaults: "soon"), IdleHidePolicy.defaultMinutes)
            try expectEqual(IdleHidePolicy.minutes(fromDefaults: -3), IdleHidePolicy.defaultMinutes)
        }

        suite.check("Idle hide picker keeps a non-choice minutes value visible") {
            try expectEqual(IdleHidePolicy.pickerChoices(including: 1), [0, 1, 5, 10, 15, 30])
            try expectEqual(IdleHidePolicy.pickerChoices(including: 10), IdleHidePolicy.choices)
            try expectEqual(IdleHidePolicy.choiceTitle(0), "Never")
            try expectEqual(IdleHidePolicy.choiceTitle(1), "After 1 min")
        }

        suite.check("A 1-minute threshold hides after 2 idle minutes") {
            var policy = IdleHidePolicy(minutes: 1)
            try expectEqual(policy.evaluate(idleSeconds: 45, displayHeldBy: []), .wait)
            try expectEqual(policy.evaluate(idleSeconds: 120, displayHeldBy: []), .hide)
        }

        suite.check("Idle hide reports each skip reason once per idle stretch") {
            var policy = IdleHidePolicy(minutes: 10)
            let zoom = "zoom.us is keeping the display awake"
            try expectEqual(policy.evaluate(idleSeconds: 600, displayHeldBy: ["zoom.us"]), .skip(zoom))
            try expect(policy.shouldReportSkip(zoom), "first skip of a stretch must log")
            try expectEqual(policy.evaluate(idleSeconds: 615, displayHeldBy: ["zoom.us"]), .skip(zoom))
            try expect(!policy.shouldReportSkip(zoom), "repeat skip in the same stretch must stay quiet")
            try expect(policy.shouldReportSkip("QuickTime Player is keeping the display awake"), "a new reason logs once")
            try expect(!policy.shouldReportSkip(zoom), "an earlier reason stays quiet when it returns")
            try expectEqual(policy.evaluate(idleSeconds: 3, displayHeldBy: ["zoom.us"]), .wait)
            try expectEqual(policy.evaluate(idleSeconds: 600, displayHeldBy: ["zoom.us"]), .skip(zoom))
            try expect(policy.shouldReportSkip(zoom), "input starts a new stretch that logs again")
        }

        suite.check("Last idle hide record round-trips through readable JSON") {
            let record = IdleHideRecord(date: at1742, appCount: 6)
            let text = try expectNotNil(record.encodedString())
            try expect(text.contains("\"appCount\":6"), "stored JSON should be readable with defaults read: \(text)")
            try expectEqual(IdleHideRecord.decode(text), record)
            try expectEqual(IdleHideRecord.decode(nil), nil)
            try expectEqual(IdleHideRecord.decode(""), nil)
            try expectEqual(IdleHideRecord.decode("garbage"), nil)
        }

        suite.check("Last idle hide label shows time and app count, or never") {
            let record = IdleHideRecord(date: at1742, appCount: 6)
            try expectEqual(IdleHideRecord.menuLabel(record, now: at1742.addingTimeInterval(3600), timeZone: utc), "Last idle hide: 17:42, 6 apps")
            try expectEqual(IdleHideRecord.menuLabel(IdleHideRecord(date: at1742, appCount: 1), now: at1742, timeZone: utc), "Last idle hide: 17:42, 1 app")
            try expectEqual(IdleHideRecord.menuLabel(nil, now: at1742, timeZone: utc), "Last idle hide: never")
            let nextDay = at1742.addingTimeInterval(86_400)
            try expect(IdleHideRecord.menuLabel(record, now: nextDay, timeZone: utc).hasSuffix(" 17:42, 6 apps"), "an older hide keeps its time")
            try expect(IdleHideRecord.menuLabel(record, now: nextDay, timeZone: utc) != "Last idle hide: 17:42, 6 apps", "an older hide names its day")
        }
    }
}

private func expectNotNil<T>(_ value: T?) throws -> T {
    guard let value else { throw CheckFailure.message("Expected a value, got nil") }
    return value
}
