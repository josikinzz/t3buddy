import CryptoKit
import Foundation

// Pure pieces of the T3 source: MCP Streamable HTTP wire parsing, T3's tool payloads,
// thread status rules, the OAuth (PKCE) helpers, and the thread → orb mapping. The
// network and process side lives in T3ThreadSource.swift.

public enum MCPError: Error, Equatable, Sendable {
    /// 401: no token, or T3 rejected it.
    case unauthorized
    /// 404 on a request that carried `Mcp-Session-Id`: the server forgot the session.
    case sessionExpired
    case http(Int)
    case rpc(code: Int, message: String)
    case toolError(String)
    case malformed(String)
}

/// JSON-RPC over MCP's Streamable HTTP transport: a response body is either JSON
/// (one message or a batch) or a `text/event-stream` whose `data:` events carry messages.
public enum MCPWire {
    public static func messages(body: Data, contentType: String?) throws -> [[String: Any]] {
        let type = contentType?.lowercased() ?? ""
        let text = String(decoding: body, as: UTF8.self)
        if type.contains("text/event-stream") || (!type.contains("json") && text.trimmingCharacters(in: .whitespaces).hasPrefix("event:")) {
            return try sseEvents(text).flatMap(decodeMessages)
        }
        return try decodeMessages(text)
    }

    /// The response to request `id`; a JSON-RPC error becomes `MCPError.rpc`.
    public static func response(id: Int, body: Data, contentType: String?) throws -> [String: Any] {
        let all = try messages(body: body, contentType: contentType)
        guard let message = all.first(where: { idMatches($0["id"], id) }) else {
            throw MCPError.malformed("no response for request \(id)")
        }
        if let error = message["error"] as? [String: Any] {
            throw MCPError.rpc(code: (error["code"] as? NSNumber)?.intValue ?? 0, message: error["message"] as? String ?? "")
        }
        guard let result = message["result"] as? [String: Any] else { throw MCPError.malformed("response \(id) has no result") }
        return result
    }

    /// A `tools/call` result's JSON payload: `structuredContent`, else the first text block.
    /// `isError: true` becomes `MCPError.toolError` with the tool's text.
    public static func toolPayload(_ result: [String: Any]) throws -> Data {
        let text = (result["content"] as? [[String: Any]])?.first { $0["type"] as? String == "text" }?["text"] as? String
        if result["isError"] as? Bool == true { throw MCPError.toolError(text ?? "tool failed") }
        if let structured = result["structuredContent"], JSONSerialization.isValidJSONObject(structured) {
            return try JSONSerialization.data(withJSONObject: structured)
        }
        guard let text else { throw MCPError.malformed("tool result has no content") }
        return Data(text.utf8)
    }

    /// `data:` payloads of each SSE event (multi-line data joined with newlines).
    static func sseEvents(_ text: String) -> [String] {
        var events: [String] = []
        var data: [String] = []
        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if rawLine.isEmpty {
                if !data.isEmpty { events.append(data.joined(separator: "\n")); data = [] }
            } else if rawLine.hasPrefix("data:") {
                var value = rawLine.dropFirst(5)
                if value.first == " " { value = value.dropFirst() }
                data.append(String(value))
            }
        }
        if !data.isEmpty { events.append(data.joined(separator: "\n")) }
        return events
    }

    private static func decodeMessages(_ text: String) throws -> [[String: Any]] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let object = try JSONSerialization.jsonObject(with: Data(trimmed.utf8))
        if let single = object as? [String: Any] { return [single] }
        if let batch = object as? [[String: Any]] { return batch }
        throw MCPError.malformed("not a JSON-RPC message")
    }

    private static func idMatches(_ value: Any?, _ id: Int) -> Bool {
        if let number = value as? NSNumber { return number.intValue == id }
        if let string = value as? String { return string == String(id) }
        return false
    }
}

// MARK: T3 payloads

public struct T3Project: Equatable, Sendable {
    public var id: String
    public var title: String
    public var workspaceRoot: String
    public var faviconPath: String?
    public var projectIcon: ProjectIconOverride?

    public init(id: String, title: String, workspaceRoot: String, faviconPath: String? = nil, projectIcon: ProjectIconOverride? = nil) {
        self.id = id
        self.title = title
        self.workspaceRoot = workspaceRoot
        self.faviconPath = faviconPath
        self.projectIcon = projectIcon
    }
}

/// T3's durable run status. Unknown values (a newer T3) are kept and count as not active.
public struct T3ThreadStatus: RawRepresentable, Hashable, Sendable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Statuses that mean the thread is doing or about to do work. T3 stores a finished
    /// turn as `waiting` while it holds the run open for background work or children.
    public static let activeStatuses = ["preparing", "queued", "starting", "running", "waiting"]
    public static let failedStatus = "failed"

    public var isActive: Bool { Self.activeStatuses.contains(rawValue) }
    public var isFailed: Bool { rawValue == Self.failedStatus }

    /// The orb state for a thread with this status and this many pending runtime requests
    /// (questions and approvals: the thread needs its owner). nil keeps it out of the orbit;
    /// `completed`, `interrupted`, `cancelled`, `rolled_back` and `idle` are reabsorbed.
    /// `failed` maps to `.failed`; the source decides how long a failed orb stays.
    public func orbState(pendingRequests: Int = 0) -> Orb.State? {
        if isActive { return pendingRequests > 0 ? .waiting : .active }
        if isFailed { return .failed }
        return nil
    }
}

public struct T3Thread: Equatable, Sendable {
    public var threadId: String
    public var title: String
    public var status: T3ThreadStatus
    /// T3 provider instance id (usually the driver id, for example `claudeAgent`).
    public var providerInstanceId: String?
    public var parentThreadId: String?
    public var relationshipToParent: String?
    /// `web`, `mcp` (a delegated task), `provider` (a provider's own subagent), ...
    public var creationSource: String?
    public var itemCount: Int?
    public var updatedAt: Date?

    public init(threadId: String, title: String, status: T3ThreadStatus, providerInstanceId: String? = nil, parentThreadId: String? = nil, relationshipToParent: String? = nil, creationSource: String? = nil, itemCount: Int? = nil, updatedAt: Date? = nil) {
        self.threadId = threadId
        self.title = title
        self.status = status
        self.providerInstanceId = providerInstanceId
        self.parentThreadId = parentThreadId
        self.relationshipToParent = relationshipToParent
        self.creationSource = creationSource
        self.itemCount = itemCount
        self.updatedAt = updatedAt
    }

    /// A subagent the provider spawned itself (Claude's Agent tool, Codex or Cursor subagents).
    /// T3 lists its thread as `idle` whatever it is doing; its live state is the parent's
    /// `subagent` activity item instead.
    public var isProviderNativeSubagent: Bool {
        relationshipToParent == "subagent" && creationSource == "provider"
    }
}

/// One row of `t3_thread_read`'s activity timeline, with the start of its text.
public struct T3TimelineItem: Equatable, Sendable {
    public var position: Int
    public var itemId: String
    /// Set on `subagent` items: the provider-native subagent or workflow agent node.
    public var subagentId: String?
    public var runId: String?
    public var type: String
    /// `pending`, `running`, `waiting`, `completed`, `failed`, `cancelled`, `interrupted`.
    public var status: String
    public var title: String?
    /// The first `maxCharsPerItem` characters of the item's text, as read.
    public var text: String?
    public var updatedAt: Date?

    public init(position: Int, itemId: String, subagentId: String? = nil, runId: String? = nil, type: String, status: String, title: String? = nil, text: String? = nil, updatedAt: Date? = nil) {
        self.position = position
        self.itemId = itemId
        self.subagentId = subagentId
        self.runId = runId
        self.type = type
        self.status = status
        self.title = title
        self.text = text
        self.updatedAt = updatedAt
    }

    /// A provider-native subagent or workflow agent. A task delegated through T3 (`delegate_task`)
    /// also shows in its parent's timeline as a `subagent` item, `node:delegated-task:<key>`, but
    /// it is a T3 thread of its own too (`thread:delegated-task:<key>`, listed with its parent), so
    /// only the thread counts: two orbs for one task would read as an extra agent.
    public var isSubagent: Bool { type == "subagent" && !isDelegatedTask }
    public var isDelegatedTask: Bool { subagentId?.hasPrefix(Self.delegatedTaskNodePrefix) == true }
    public static let delegatedTaskNodePrefix = "node:delegated-task:"
    /// T3's own rule for work that is still going.
    public var isWorkActive: Bool { ["pending", "running", "waiting"].contains(status) }
    public var isFailed: Bool { status == "failed" }
    /// The id the subagent's orb carries, stable while the item updates in place.
    public var orbKey: String { subagentId ?? itemId }
}

/// A `t3_thread_read` (activity view) result: the thread's live detail and one page of its timeline.
public struct T3ThreadActivity: Equatable, Sendable {
    public var threadId: String
    public var status: T3ThreadStatus
    public var activeRunId: String?
    /// Pending runtime requests (user questions and approvals): the thread needs its owner.
    public var pendingRequestCount: Int
    public var itemCount: Int
    public var items: [T3TimelineItem]
    /// Position of the last item returned; read on with `afterPosition` = this.
    public var nextPosition: Int?
    public var hasMore: Bool

    public init(threadId: String, status: T3ThreadStatus, activeRunId: String?, pendingRequestCount: Int, itemCount: Int, items: [T3TimelineItem], nextPosition: Int?, hasMore: Bool) {
        self.threadId = threadId
        self.status = status
        self.activeRunId = activeRunId
        self.pendingRequestCount = pendingRequestCount
        self.itemCount = itemCount
        self.items = items
        self.nextPosition = nextPosition
        self.hasMore = hasMore
    }
}

public struct T3Page<Item: Sendable>: Sendable {
    public var items: [Item]
    /// Offset of the next page, or nil on the last page.
    public var nextCursor: Int?
}

public enum T3Payload {
    public static func projects(_ data: Data) throws -> T3Page<T3Project> {
        let object = try jsonObject(data)
        guard let list = object["projects"] as? [[String: Any]] else { throw MCPError.malformed("no projects") }
        let projects = list.compactMap { item -> T3Project? in
            guard let id = item["id"] as? String, let root = item["workspaceRoot"] as? String else { return nil }
            if let deleted = item["deletedAt"], !(deleted is NSNull) { return nil }
            return T3Project(
                id: id,
                title: item["title"] as? String ?? URL(fileURLWithPath: root).lastPathComponent,
                workspaceRoot: root,
                faviconPath: item["faviconPath"] as? String,
                projectIcon: ProjectIconOverride(json: item["projectIcon"])
            )
        }
        return T3Page(items: projects, nextCursor: cursor(object["nextCursor"]))
    }

    public static func threads(_ data: Data) throws -> T3Page<T3Thread> {
        let object = try jsonObject(data)
        guard let list = object["threads"] as? [[String: Any]] else { throw MCPError.malformed("no threads") }
        let threads = list.compactMap { item -> T3Thread? in
            guard let id = item["threadId"] as? String, let status = item["status"] as? String else { return nil }
            return T3Thread(
                threadId: id,
                title: item["title"] as? String ?? "",
                status: T3ThreadStatus(rawValue: status),
                providerInstanceId: item["providerInstanceId"] as? String,
                parentThreadId: item["parentThreadId"] as? String,
                relationshipToParent: item["relationshipToParent"] as? String,
                creationSource: item["creationSource"] as? String,
                itemCount: (item["itemCount"] as? NSNumber)?.intValue,
                updatedAt: date(item["updatedAt"])
            )
        }
        return T3Page(items: threads, nextCursor: cursor(object["nextCursor"]))
    }

    /// `t3_thread_read` with `view: "activity"`.
    public static func threadActivity(_ data: Data) throws -> T3ThreadActivity {
        let object = try jsonObject(data)
        guard let thread = object["thread"] as? [String: Any], let id = thread["threadId"] as? String else {
            throw MCPError.malformed("thread read has no thread")
        }
        let items = (object["items"] as? [[String: Any]] ?? []).compactMap { item -> T3TimelineItem? in
            guard let position = (item["position"] as? NSNumber)?.intValue, let itemId = item["itemId"] as? String else { return nil }
            return T3TimelineItem(
                position: position,
                itemId: itemId,
                subagentId: item["subagentId"] as? String,
                runId: item["runId"] as? String,
                type: item["type"] as? String ?? "",
                status: item["status"] as? String ?? "",
                title: item["title"] as? String,
                text: item["text"] as? String,
                updatedAt: date(item["updatedAt"])
            )
        }
        return T3ThreadActivity(
            threadId: id,
            status: T3ThreadStatus(rawValue: thread["status"] as? String ?? "idle"),
            activeRunId: thread["activeRunId"] as? String,
            pendingRequestCount: (thread["pendingRequestCount"] as? NSNumber)?.intValue ?? 0,
            itemCount: (thread["itemCount"] as? NSNumber)?.intValue ?? 0,
            items: items,
            nextPosition: cursor(object["nextPosition"]),
            hasMore: object["hasMore"] as? Bool ?? false
        )
    }

    /// T3's timestamps: ISO 8601 with milliseconds.
    public static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// Provider instance id → driver kind, from `orchestrator_capabilities`.
    public static func driverKinds(_ data: Data) throws -> [String: String] {
        let object = try jsonObject(data)
        var kinds: [String: String] = [:]
        for provider in object["providers"] as? [[String: Any]] ?? [] {
            if let instance = provider["providerInstanceId"] as? String, let driver = provider["driverKind"] as? String {
                kinds[instance] = driver
            }
        }
        return kinds
    }

    public static func environmentId(_ data: Data) throws -> String? {
        try jsonObject(data)["environmentId"] as? String
    }

    private static func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPError.malformed("tool payload is not an object")
        }
        return object
    }

    private static func cursor(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }
}

// MARK: Mapping

public enum T3OrbMapper {
    public static let idPrefix = "t3:"

    /// One orb per thread whose status puts it in the orbit. Delegated children carry their parent's
    /// orb id. Provider-native subagent threads are skipped: they come from `subagentOrbs`.
    /// `pendingRequests` maps thread id to its pending request count; a failed thread shows
    /// only while its orb id is in `failedShown` (see `FailedOrbRetention`).
    /// `activity` maps thread id to a few words on what it is doing (see `T3ActivityPhrase`).
    public static func orbs(project: T3Project, threads: [T3Thread], icon: OrbIcon, driverKinds: [String: String] = [:], pendingRequests: [String: Int] = [:], failedShown: Set<String> = [], activity: [String: String] = [:], threadURL: (String) -> String? = { _ in nil }) -> [Orb] {
        threads.compactMap { thread in
            guard !thread.isProviderNativeSubagent,
                  let state = thread.status.orbState(pendingRequests: pendingRequests[thread.threadId] ?? 0) else { return nil }
            if state == .failed, !failedShown.contains(orbId(thread.threadId)) { return nil }
            return threadOrb(project: project, thread: thread, state: state, icon: icon, driverKinds: driverKinds, activity: activity[thread.threadId], threadURL: threadURL)
        }
    }

    /// The orb for one thread, in `state`. Its id is the thread's own, whatever run or turn it is
    /// on, so a new message or a status change never makes it a different orb.
    public static func threadOrb(project: T3Project, thread: T3Thread, state: Orb.State, icon: OrbIcon, driverKinds: [String: String] = [:], activity: String? = nil, threadURL: (String) -> String? = { _ in nil }) -> Orb {
        Orb(
            id: orbId(thread.threadId),
            parentId: thread.parentThreadId.map(orbId),
            source: .t3,
            projectIcon: icon,
            provider: provider(thread, driverKinds),
            state: state,
            label: thread.title.isEmpty ? project.title : "\(project.title) · \(thread.title)",
            link: threadURL(thread.threadId),
            activity: activity,
            activeAt: thread.updatedAt.map { ($0.timeIntervalSince1970 * 1000).rounded() / 1000 }
        )
    }

    /// `orbs` plus the parents their satellites circle. A thread whose own turn has ended (T3 lists
    /// it `completed` or `idle`, between turns or while its subagents and delegated tasks keep
    /// working) stays in orbit, active, while any orb names it as parent, so its satellites stay
    /// attached instead of falling out onto the halo. `parent(threadOrbId)` gives the parent's
    /// orb whatever its status, or nil when it is not known; then its children circle T3boii.
    public static func holdingParents(_ orbs: [Orb], parent: (String) -> Orb?) -> [Orb] {
        var result = orbs
        var ids = Set(orbs.map(\.id))
        var queue = orbs.compactMap(\.parentId)
        while let id = queue.popLast() {
            guard !ids.contains(id), let held = parent(id), held.id == id else { continue }
            ids.insert(id)
            result.append(held)
            if let grandparent = held.parentId { queue.append(grandparent) }
        }
        return result
    }

    /// Satellites for the provider-native subagents and workflow agents running inside `parent`,
    /// from its activity timeline. Each carries the parent thread's orb id.
    public static func subagentOrbs(parent: T3Thread, project: T3Project, items: [T3TimelineItem], icon: OrbIcon, driverKinds: [String: String] = [:], failedShown: Set<String> = [], threadURL: (String) -> String? = { _ in nil }) -> [Orb] {
        items.compactMap { item in
            guard item.isSubagent else { return nil }
            let id = orbId(item.orbKey)
            let state: Orb.State
            if item.isWorkActive {
                state = .active
            } else if item.isFailed, failedShown.contains(id) {
                state = .failed
            } else {
                return nil
            }
            let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Orb(
                id: id,
                parentId: orbId(parent.threadId),
                source: .t3,
                projectIcon: icon,
                provider: provider(parent, driverKinds),
                state: state,
                label: "\(project.title) · \(title.isEmpty ? "subagent" : title)",
                link: threadURL(parent.threadId),
                activeAt: item.updatedAt.map { ($0.timeIntervalSince1970 * 1000).rounded() / 1000 }
            )
        }
    }

    public static func orbId(_ key: String) -> String { idPrefix + key }

    private static func provider(_ thread: T3Thread, _ driverKinds: [String: String]) -> String {
        let instance = thread.providerInstanceId ?? ""
        return driverKinds[instance] ?? (instance.isEmpty ? "generic" : instance)
    }

    /// T3's web route for a thread: `<origin>/<environmentId>/<threadId>`.
    public static func threadURL(origin: URL, environmentId: String, threadId: String) -> String? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/%")
        guard let env = environmentId.addingPercentEncoding(withAllowedCharacters: allowed),
              let thread = threadId.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return origin.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/\(env)/\(thread)"
    }
}

// MARK: OAuth (T3 MCP: authorization_code + PKCE S256, public client)

public struct T3MCPToken: Codable, Equatable, Sendable {
    public var accessToken: String
    public var expiresAt: Date?

    public init(accessToken: String, expiresAt: Date?) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }

    /// The T3 auth session this token belongs to: T3's bearer tokens are
    /// `base64url({"v":1,"kind":"session","sid":…}).signature`. nil for any other shape.
    public var sessionId: String? {
        guard let head = accessToken.split(separator: ".").first else { return nil }
        var base64 = head.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["kind"] as? String == "session",
              let sid = object["sid"] as? String, T3CLILocator.isSafeArgument(sid) else { return nil }
        return sid
    }

    /// Usable until five minutes before it expires.
    public func isUsable(now: Date) -> Bool {
        guard !accessToken.isEmpty else { return false }
        guard let expiresAt else { return true }
        return now.addingTimeInterval(5 * 60) < expiresAt
    }
}

public enum T3MCPAuth {
    public struct PKCE: Equatable, Sendable {
        public var verifier: String
        public var challenge: String
    }

    /// A verifier from 48 random bytes (64 base64url characters) and its S256 challenge.
    public static func pkce(randomBytes: [UInt8]) -> PKCE {
        let verifier = base64URL(Data(randomBytes))
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        return PKCE(verifier: verifier, challenge: challenge)
    }

    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// The authorization request T3's `/oauth/mcp/authorize` and `/oauth/mcp/decision` take.
    public static func authorizationRequest(clientId: String, redirectURI: String, pkce: PKCE, state: String, resource: String) -> [String: String] {
        [
            "response_type": "code",
            "client_id": clientId,
            "redirect_uri": redirectURI,
            "code_challenge": pkce.challenge,
            "code_challenge_method": "S256",
            "state": state,
            "resource": resource
        ]
    }

    public enum RedirectError: Error, Equatable {
        case denied(String)
        case stateMismatch
        case missingCode
    }

    /// The `code` from the redirect T3 sends the approval to.
    public static func authorizationCode(fromRedirect redirect: String, expectedState: String) throws -> String {
        let items = URLComponents(string: redirect)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        if let error = value("error") { throw RedirectError.denied(value("error_description") ?? error) }
        guard value("state") == expectedState else { throw RedirectError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw RedirectError.missingCode }
        return code
    }

    public static func token(fromResponse data: Data, now: Date) throws -> T3MCPToken {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = object["access_token"] as? String, !access.isEmpty else {
            throw MCPError.malformed("token response has no access_token")
        }
        let expiresIn = (object["expires_in"] as? NSNumber)?.doubleValue
        return T3MCPToken(accessToken: access, expiresAt: expiresIn.map { now.addingTimeInterval($0) })
    }

    /// `application/x-www-form-urlencoded` body.
    public static func formBody(_ fields: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields.map { name, value in
            "\(name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
        return Data(body.utf8)
    }
}

/// Where the `t3` CLI lives: the version T3's service state names as active.
public enum T3CLILocator {
    public static func activeBinary(t3Home: URL, fileManager: FileManager = .default) -> URL? {
        let versions = t3Home.appendingPathComponent("runtime/versions", isDirectory: true)
        let state = t3Home.appendingPathComponent("runtime/service-state.json")
        if let data = fileManager.contents(atPath: state.path),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let active = object["activeVersion"] as? String, !active.contains("/") {
            let binary = versions.appendingPathComponent(active).appendingPathComponent("t3")
            if fileManager.isExecutableFile(atPath: binary.path) { return binary }
        }
        // No service state: the newest installed version.
        let names = (try? fileManager.contentsOfDirectory(atPath: versions.path)) ?? []
        return names.sorted(by: { $0.compare($1, options: .numeric) == .orderedDescending })
            .map { versions.appendingPathComponent($0).appendingPathComponent("t3") }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    /// Whether `value` can go to the CLI as one argument: letters, digits and dashes, not starting with a dash.
    public static func isSafeArgument(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first, first != "-", value.count <= 128 else { return false }
        return value.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "-" }
    }

    /// The secret from `t3 auth pairing create --json`.
    public static func pairingCode(fromJSON data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["credential"] as? String
    }
}
