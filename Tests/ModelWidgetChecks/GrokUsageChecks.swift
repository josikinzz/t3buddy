import Foundation
import ModelWidgetCore

extension ModelWidgetChecks {
    static func grokUsageChecks(_ suite: inout CheckSuite) async {
        let now = Date(timeIntervalSince1970: 1_792_022_400)
        let hour: TimeInterval = 3600

        func reading(_ blob: Data) throws -> GrokUsageReader.Reading {
            guard let reading = GrokUsageReader.parse(blob) else { throw CheckFailure.message("Fixture blob must parse") }
            return reading
        }

        suite.check("A fresh Grok Bot reading shows its weekly percent, plan and age") {
            let blob = grokUsageBlob(readAt: now - 2 * hour, reset: now + 3 * 24 * hour, percent: 42, trial: true)
            let row = GrokUsageReader.row(try reading(blob), now: now)
            try expectEqual(row.provider, "Grok Bot")
            try expectEqual(row.plan, "Demo Plan Trial")
            try expectEqual(row.email, "")
            try expectEqual(row.windows.map(\.title), ["Weekly"])
            try expectEqual(row.windows[0].used, 42)
            try expectEqual(row.windows[0].reset, now + 3 * 24 * hour)
            try expectEqual(row.checked, now - 2 * hour)
            try expectEqual(row.note, "Checked 2h ago in Grok Bot")
            try expect(row.error == nil, "A fresh reading is not marked stale")
        }

        suite.check("A Grok Bot reading past its expiry but before the reset still shows, marked stale") {
            let blob = grokUsageBlob(readAt: now - 30 * hour, reset: now + 2 * 24 * hour, percent: 61)
            let parsed = try reading(blob)
            guard case let .present(usage) = parsed else { throw CheckFailure.message("Fixture is a present reading") }
            try expectEqual(usage.freshness(at: now), .stale)
            let row = GrokUsageReader.row(parsed, now: now)
            try expectEqual(row.windows.map(\.used), [61])
            try expectEqual(row.error, "Checked 30h ago in Grok Bot")
            try expect(row.note == nil, "The age is shown once, as the stale mark")
        }

        suite.check("A Grok Bot reading from before the weekly reset shows no percent") {
            let blob = grokUsageBlob(readAt: now - 50 * hour, reset: now - hour, percent: 88, onDemand: (500, 2000))
            let row = GrokUsageReader.row(try reading(blob), now: now)
            try expect(row.windows.isEmpty, "Last week's percent and on-demand spend must not show, got \(row.windows.map(\.title))")
            try expectEqual(row.note, "No reading since the weekly reset · Checked 2d ago in Grok Bot")
            try expect(row.error == nil, "No numbers are shown, so none are marked stale")
        }

        suite.check("An absent Grok Bot reading shows that there is none, with no numbers") {
            let row = GrokUsageReader.row(try reading(grokUsageBlob(kind: "absent", readAt: now, reset: now, percent: 0)), now: now)
            try expect(row.windows.isEmpty && row.checked == nil && row.error == nil, "Absent has no numbers or age")
            try expectEqual(row.note, "No usage reading in Grok Bot")
        }

        suite.check("A Grok Bot plan with no included limit shows no weekly percent") {
            let blob = grokUsageBlob(readAt: now - hour, reset: now + 24 * hour, percent: 0, included: false)
            let row = GrokUsageReader.row(try reading(blob), now: now)
            try expect(row.windows.isEmpty, "No included limit means no weekly window")
            try expectEqual(row.note, "No included weekly usage on this plan · Checked 1h ago in Grok Bot")
        }

        suite.check("Grok Bot on-demand spend is a window of its limit, and a zero limit shows none") {
            let spending = GrokUsageReader.row(try reading(grokUsageBlob(readAt: now - hour, reset: now + 24 * hour, percent: 0, onDemand: (500, 2000))), now: now)
            try expectEqual(spending.windows.map(\.title), ["Weekly", "On-demand"])
            try expectEqual(spending.windows.map(\.used), [0, 25])
            let zeroLimit = GrokUsageReader.row(try reading(grokUsageBlob(readAt: now - hour, reset: now + 24 * hour, percent: 10, onDemand: (500, 0))), now: now)
            try expectEqual(zeroLimit.windows.map(\.title), ["Weekly"])
        }

        suite.check("A Grok Bot usage blob with another schema version is ignored") {
            try expect(GrokUsageReader.parse(grokUsageBlob(schema: 3, readAt: now, reset: now + hour, percent: 5)) == nil, "Schema 3 must not parse")
            let folder = try grokUsageFolder()
            try grokUsageBlob(schema: 1, readAt: now, reset: now + hour, percent: 5).write(to: folder.appendingPathComponent(GrokRosterReader.blobFileName(forKey: "sand.client.slice.account.demo-1.weekly-usage.cache")))
            try expect(GrokUsageReader.read(persistenceFolder: folder, now: now) == nil, "An unsupported blob shows no row")
        }

        suite.check("Grok Bot usage is read from the account blob with the newest reading, and no folder means no row") {
            let folder = try grokUsageFolder()
            func write(_ account: String, _ blob: Data) throws {
                try blob.write(to: folder.appendingPathComponent(GrokRosterReader.blobFileName(forKey: "sand.client.slice.account.\(account).weekly-usage.cache")))
            }
            try write("demo-old", grokUsageBlob(readAt: now - 10 * hour, reset: now + 24 * hour, percent: 70))
            try write("demo-new", grokUsageBlob(readAt: now - hour, reset: now + 24 * hour, percent: 12))
            try write("demo-absent", grokUsageBlob(kind: "absent", readAt: now, reset: now, percent: 0))
            try Data("not this blob".utf8).write(to: folder.appendingPathComponent(GrokRosterReader.blobFileName(forKey: "sand.client.slice.account.demo-new.roster.last-roster")))
            let row = GrokUsageReader.read(persistenceFolder: folder, now: now)
            try expectEqual(row?.windows.map(\.used), [12])
            try expect(GrokUsageReader.read(persistenceFolder: folder.appendingPathComponent("missing"), now: now) == nil, "A missing folder shows no row")
        }
    }
}

private func grokUsageFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("grok-usage-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

private func grokUsageBlob(
    schema: Int = 2, kind: String = "present", readAt: Date, reset: Date, percent: Double,
    included: Bool = true, trial: Bool = false, onDemand: (used: Int, limit: Int)? = nil
) -> Data {
    let ms = { (date: Date) in Int(date.timeIntervalSince1970 * 1000) }
    let usage: [String: Any] = [
        "percentUsed": percent, "nextResetMs": ms(reset), "isSandTrial": trial, "hasNonZeroIncludedLimit": included,
        "isTeamSeat": false, "grokPlanLabel": "Demo Plan",
        "onDemand": onDemand.map { ["usedCents": $0.used, "limitCents": $0.limit] as Any } ?? NSNull()
    ]
    let value: [String: Any] = kind == "present"
        ? ["kind": kind, "selectedTeamId": NSNull(), "expiresAtMs": ms(readAt) + 24 * 3_600_000, "reading": ["readAtMs": ms(readAt), "usage": usage]]
        : ["kind": kind, "selectedTeamId": NSNull()]
    return try! JSONSerialization.data(withJSONObject: ["schemaVersion": schema, "value": value])
}
