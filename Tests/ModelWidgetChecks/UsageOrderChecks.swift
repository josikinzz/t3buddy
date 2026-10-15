import Foundation
import ModelWidgetCore

extension ModelWidgetChecks {
    static func usageOrderChecks(_ suite: inout CheckSuite) async {
        func row(_ provider: String, _ email: String, used: [Double], error: String? = nil) throws -> SubscriptionUsage {
            let windows: [[String: Any]] = used.enumerated().map { ["id": "w\($0.offset)", "title": "Weekly", "used": $0.element] }
            let object: [String: Any] = ["id": provider + ":" + email, "provider": provider, "email": email, "plan": "", "windows": windows, "error": error ?? NSNull()]
            return try JSONDecoder().decode(SubscriptionUsage.self, from: JSONSerialization.data(withJSONObject: object))
        }

        suite.check("usage order puts a row at 100% weekly below a row at 40%") {
            let exhausted = try row("Claude", "a@x.com", used: [12, 100])
            let usable = try row("Claude", "b@x.com", used: [5, 40])
            let rows = SubscriptionUsageReader.usableFirst([exhausted, usable])
            try expectEqual(rows.map(\.email), ["b@x.com", "a@x.com"])
        }

        suite.check("usage order puts an errored row below a usable row") {
            let failing = try row("Claude", "a@x.com", used: [10], error: "Usage unavailable (HTTP 500)")
            let usable = try row("Codex", "z@x.com", used: [99.4])
            let rows = SubscriptionUsageReader.usableFirst([failing, usable])
            try expectEqual(rows.map(\.email), ["z@x.com", "a@x.com"])
        }

        suite.check("usage order keeps provider-then-email order inside each group") {
            let input = [
                try row("Claude", "a@x.com", used: [100]),
                try row("Claude", "b@x.com", used: [20]),
                try row("Claude", "c@x.com", used: [100]),
                try row("Codex", "d@x.com", used: [30]),
                try row("Codex", "e@x.com", used: [10], error: "Usage check failed"),
                try row("Kimi", "f@x.com", used: [0]),
            ]
            let rows = SubscriptionUsageReader.usableFirst(input)
            try expectEqual(rows.map(\.email), ["b@x.com", "d@x.com", "f@x.com", "a@x.com", "c@x.com", "e@x.com"])
            try expectEqual(SubscriptionUsageReader.usableFirst(rows).map(\.email), rows.map(\.email))
        }

        suite.check("usage cache encoding carries no reveal or pixelation state") {
            let data = try JSONEncoder().encode([try row("Claude", "a@x.com", used: [40])])
            let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
            let keys = Set(objects.first?.keys.map { $0 } ?? [])
            try expectEqual(keys, ["id", "provider", "email", "plan", "windows"])
            let text = String(decoding: data, as: UTF8.self).lowercased()
            try expect(!text.contains("reveal") && !text.contains("pixel"), "Cache must not hold reveal state")
        }
    }
}
