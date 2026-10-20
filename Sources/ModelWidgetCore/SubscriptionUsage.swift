import Foundation

public struct UsageWindow: Identifiable, Codable, Sendable {
    public var id: String
    public var title: String
    public var used: Double
    public var reset: Date?
}

public struct SubscriptionUsage: Identifiable, Codable, Sendable {
    public var id: String
    public var provider: String
    public var email: String
    public var plan: String
    public var windows: [UsageWindow]
    public var error: String?
    public var checked: Date?
    /// A plain fact about the reading, such as where and when another app took it.
    public var note: String?

    /// Still has quota: no error and every reported window under 100%.
    public var isUsable: Bool { error == nil && windows.allSatisfy { $0.used < 100 } }
}

public enum SubscriptionUsageReader {
    private struct Account: Sendable {
        var id: String
        var provider: String
        var email: String
        var plan: String
        var token: String
        var accountID: String
        var baseURL = "https://api.kimi.com/coding"
    }

    public static func read(home: URL = FileManager.default.homeDirectoryForCurrentUser) async -> [SubscriptionUsage] {
        var accounts: [String: Account] = [:]
        let proxy = home.appendingPathComponent(".cli-proxy-api")
        let codexHomes = ((try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? []).filter { $0.lastPathComponent == ".codex" || $0.lastPathComponent.hasPrefix(".codex-") }
        let files = ((try? FileManager.default.contentsOfDirectory(at: proxy, includingPropertiesForKeys: nil)) ?? []).filter {
            ($0.lastPathComponent.hasPrefix("claude-") || $0.lastPathComponent.hasPrefix("codex-")) && $0.pathExtension == "json"
        } + codexHomes.map { $0.appendingPathComponent("auth.json") }
        for file in files {
            guard let data = try? Data(contentsOf: file), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let isLocal = file.lastPathComponent == "auth.json"
            let tokens = isLocal ? (json["tokens"] as? [String: Any] ?? [:]) : json
            let provider = isLocal ? "Codex" : (json["type"] as? String == "claude" ? "Claude" : "Codex")
            guard let token = tokens["access_token"] as? String, !token.isEmpty else { continue }
            let claims = jwtClaims(tokens["id_token"] as? String ?? "")
            let email = json["email"] as? String ?? claims["email"] as? String ?? "Signed-in account"
            let accountID = tokens["account_id"] as? String ?? ""
            let id = provider + ":" + email
            guard accounts[id] == nil else { continue }
            accounts[id] = Account(id: id, provider: provider, email: email, plan: json["plan_type"] as? String ?? "", token: token, accountID: accountID)
        }
        // CLI Proxy keeps its Kimi logins refreshed; the Kimi CLI's own token goes stale between sessions.
        let proxyKimi = ((try? FileManager.default.contentsOfDirectory(at: proxy, includingPropertiesForKeys: nil)) ?? []).filter { $0.lastPathComponent.hasPrefix("kimi") && $0.pathExtension == "json" }
        let cliKimi = ((try? FileManager.default.contentsOfDirectory(at: home.appendingPathComponent(".kimi-code/credentials"), includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "json" }
        for file in proxyKimi + cliKimi {
            guard let data = try? Data(contentsOf: file), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let token = json["access_token"] as? String, !token.isEmpty,
                  json["disabled"] as? Bool != true else { continue }
            let id = "Kimi:" + file.lastPathComponent
            var account = Account(id: id, provider: "Kimi", email: "Signed-in Kimi account", plan: "", token: token, accountID: "")
            if let base = json["base_url"] as? String, base.hasPrefix("https://") { account.baseURL = base.hasSuffix("/") ? String(base.dropLast()) : base }
            accounts[id] = account
        }
        let rows = await withTaskGroup(of: SubscriptionUsage.self) { group in
            for account in accounts.values { group.addTask { await fetch(account) } }
            var rows: [SubscriptionUsage] = []
            for await row in group { rows.append(row) }
            return rows
        }
        return usableFirst(dedupe(rows).sorted { ($0.provider, $0.email) < ($1.provider, $1.email) })
    }

    /// Rows with no error and every window under 100% come first; each group keeps its incoming order.
    public static func usableFirst(_ rows: [SubscriptionUsage]) -> [SubscriptionUsage] {
        let usable = rows.filter(\.isUsable)
        return usable + rows.filter { !$0.isUsable }
    }

    /// The same Kimi account can be signed in through CLI Proxy and the Kimi CLI; keep one row, preferring a working reading.
    public static func dedupe(_ rows: [SubscriptionUsage]) -> [SubscriptionUsage] {
        var kept: [String: SubscriptionUsage] = [:]
        var order: [String] = []
        for row in rows {
            let key = row.provider + ":" + row.email
            if let existing = kept[key] {
                if existing.error != nil && row.error == nil { kept[key] = row }
            } else {
                kept[key] = row
                order.append(key)
            }
        }
        // A stale token can't fetch its email, so drop the anonymous Kimi row once a named Kimi account is present.
        let namedKimi = rows.contains { $0.provider == "Kimi" && $0.email != "Signed-in Kimi account" }
        return order.compactMap { kept[$0] }.filter { !(namedKimi && $0.provider == "Kimi" && $0.email == "Signed-in Kimi account") }
    }

    private static func jwtClaims(_ token: String) -> [String: Any] {
        let parts = token.split(separator: ".")
        guard parts.count > 1 else { return [:] }
        var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func fetch(_ account: Account) async -> SubscriptionUsage {
        var row = SubscriptionUsage(id: account.id, provider: account.provider, email: account.email, plan: account.plan, windows: [], checked: nil)
        let url = account.provider == "Kimi" ? account.baseURL + "/v1/usages" : account.provider == "Claude" ? "https://api.anthropic.com/api/oauth/usage" : "https://chatgpt.com/backend-api/wham/usage"
        var request = URLRequest(url: URL(string: url)!)
        request.timeoutInterval = 20
        request.setValue("Bearer " + account.token, forHTTPHeaderField: "Authorization")
        if account.provider == "Claude" {
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("claude-cli/2.1.280 (external, cli)", forHTTPHeaderField: "User-Agent")
        } else if account.provider == "Codex" {
            request.setValue(account.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
            request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                row.error = status == 401 || status == 403 ? "Sign-in needs refresh (HTTP \(status))" : "Usage unavailable (HTTP \(status))"
                return row
            }
            let parsed = try parse(data, provider: account.provider)
            row.windows = parsed.windows
            if !parsed.plan.isEmpty { row.plan = parsed.plan }
            if account.provider == "Kimi" {
                var profileRequest = URLRequest(url: URL(string: account.baseURL + "/v1/me")!)
                profileRequest.timeoutInterval = 10
                profileRequest.setValue("Bearer " + account.token, forHTTPHeaderField: "Authorization")
                if let (profileData, response) = try? await URLSession.shared.data(for: profileRequest), (response as? HTTPURLResponse)?.statusCode == 200,
                   let profile = try? JSONSerialization.jsonObject(with: profileData) as? [String: Any] {
                    row.email = profile["email"] as? String ?? profile["nickname"] as? String ?? row.email
                    row.plan = profile["user_level_name"] as? String ?? ""
                }
            }
            row.checked = Date()
            if row.windows.isEmpty { row.error = "No limits reported" }
        } catch { row.error = "Usage check failed" }
        return row
    }

    public static func parse(_ data: Data, provider: String) throws -> (windows: [UsageWindow], plan: String) {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var windows: [UsageWindow] = []
        if provider == "Kimi" {
            let usages = json["usages"] as? [String: Any] ?? [:]
            for (key, title) in [("limit_5h", "5-hour"), ("limit_7d", "Weekly"), ("limit_month_total", "Monthly"), ("limit_month_code", "Code monthly")] {
                guard let entry = usages[key] as? [String: Any] else { continue }
                let ratio = (entry["used_ratio"] as? Double) ?? (entry["used_ratio"] as? String).flatMap(Double.init)
                guard let ratio else { continue }
                let formatter = ISO8601DateFormatter()
                var reset: Date?
                if let raw = entry["reset_time"] as? String {
                    reset = formatter.date(from: raw)
                    if reset == nil { formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; reset = formatter.date(from: raw) }
                }
                windows.append(UsageWindow(id: key, title: title, used: ratio * 100, reset: reset))
            }
        } else if provider == "Claude" {
            let names = ["five_hour": "5-hour", "seven_day": "Weekly", "seven_day_opus": "Opus weekly", "seven_day_sonnet": "Sonnet weekly", "seven_day_cowork": "Cowork weekly", "iguana_necktie": "Fable weekly"]
            for key in ["five_hour", "seven_day", "seven_day_opus", "seven_day_sonnet", "seven_day_cowork", "iguana_necktie"] {
                guard let value = json[key] as? [String: Any], let used = value["utilization"] as? Double else { continue }
                var reset: Date?
                if let date = value["resets_at"] as? String {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    reset = formatter.date(from: date)
                    if reset == nil { formatter.formatOptions = [.withInternetDateTime]; reset = formatter.date(from: date) }
                }
                windows.append(UsageWindow(id: key, title: names[key] ?? key, used: used, reset: reset))
            }
        } else {
            func add(_ limit: [String: Any], prefix: String, label: String) {
                for key in ["primary_window", "secondary_window"] {
                    guard let value = limit[key] as? [String: Any], let used = value["used_percent"] as? Double else { continue }
                    let duration = value["limit_window_seconds"] as? Double ?? 0
                    let title = duration == 604800 ? "Weekly" : duration == 18000 ? "5-hour" : duration > 0 ? "\(Int(duration / 3600))-hour" : "Limit"
                    let reset = (value["reset_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
                    windows.append(UsageWindow(id: prefix + key, title: label + title, used: used, reset: reset))
                }
            }
            if let limit = json["rate_limit"] as? [String: Any] { add(limit, prefix: "", label: "") }
            if let limit = json["code_review_rate_limit"] as? [String: Any] { add(limit, prefix: "review", label: "Review ") }
            if let additional = json["additional_rate_limits"] as? [[String: Any]] {
                for (index, entry) in additional.enumerated() {
                    if let limit = entry["rate_limit"] as? [String: Any] { add(limit, prefix: "extra\(index)", label: (entry["limit_name"] as? String ?? "Extra") + " ") }
                }
            }
        }
        return (windows, json["plan_type"] as? String ?? "")
    }
}
