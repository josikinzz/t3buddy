import Foundation

/// T3 Code's MCP server over Streamable HTTP: `POST <origin>/mcp` with a bearer token.
/// Keeps one MCP session (`Mcp-Session-Id`) and re-initialises when the server drops it.
public actor T3MCPClient {
    public let origin: URL
    private let session: URLSession
    private var token: String?
    private var sessionId: String?
    private var initialized = false
    private var nextId = 1

    public init(origin: URL, session: URLSession = T3MCPClient.makeSession()) {
        self.origin = origin
        self.session = session
    }

    /// Every request gives up after this long; a T3 that stops answering empties the orbit.
    public static let requestTimeout: TimeInterval = 6

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        configuration.connectionProxyDictionary = [:]
        return URLSession(configuration: configuration)
    }

    public func setToken(_ token: String?) {
        guard token != self.token else { return }
        self.token = token
        sessionId = nil
        initialized = false
    }

    /// Calls a tool and returns its JSON payload.
    public func callTool(_ name: String, arguments: [String: Any] = [:]) async throws -> Data {
        let params: [String: Any] = ["name": name, "arguments": arguments]
        do {
            try await ensureInitialized()
            return try MCPWire.toolPayload(try await request("tools/call", params: params))
        } catch MCPError.sessionExpired {
            sessionId = nil
            initialized = false
            try await ensureInitialized()
            return try MCPWire.toolPayload(try await request("tools/call", params: params))
        }
    }

    private func ensureInitialized() async throws {
        guard !initialized else { return }
        sessionId = nil
        _ = try await request("initialize", params: [
            "protocolVersion": "2025-06-18",
            "capabilities": [String: Any](),
            "clientInfo": ["name": "T3boii desktop widget", "version": "1"]
        ])
        try await notify("notifications/initialized")
        initialized = true
    }

    private func request(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        let id = nextId
        nextId += 1
        let (data, response) = try await post(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        return try MCPWire.response(id: id, body: data, contentType: response.value(forHTTPHeaderField: "Content-Type"))
    }

    private func notify(_ method: String) async throws {
        _ = try await post(["jsonrpc": "2.0", "method": method])
    }

    private func post(_ body: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        guard let token else { throw MCPError.unauthorized }
        var request = URLRequest(url: origin.appendingPathComponent("mcp"), timeoutInterval: Self.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("2025-06-18", forHTTPHeaderField: "MCP-Protocol-Version")
        if let sessionId { request.setValue(sessionId, forHTTPHeaderField: "Mcp-Session-Id") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MCPError.malformed("not HTTP") }
        if let id = http.value(forHTTPHeaderField: "Mcp-Session-Id"), !id.isEmpty { sessionId = id }
        switch http.statusCode {
        case 200..<300: return (data, http)
        case 401, 403: throw MCPError.unauthorized
        case 404 where request.value(forHTTPHeaderField: "Mcp-Session-Id") != nil: throw MCPError.sessionExpired
        default: throw MCPError.http(http.statusCode)
        }
    }
}

/// Gets a read-only MCP token from the local T3 server without a browser.
///
/// T3's MCP authorization server (`/oauth/mcp/*`) is a public OAuth client flow with PKCE.
/// Its approval step accepts either a signed-in browser session or a one-time pairing code,
/// and the `t3` CLI mints pairing codes for the user who owns the server. So: register a
/// loopback client once (its id is kept and reused), mint a 2-minute `orchestration:read`
/// pairing code with `t3 auth pairing create`, approve with it (`POST /oauth/mcp/decision`,
/// access `read-only`), and exchange the code (`POST /oauth/mcp/token`). T3 issues a 30-day
/// token tied to a new auth session; `revokeSession` ends a replaced one with `t3 auth session revoke`.
public struct T3MCPConnector: Sendable {
    public enum ConnectError: Error, Equatable {
        case noCLI
        case pairingFailed(String)
        case cliTimedOut
        case http(String, Int)
    }

    /// Never listened on: the decision endpoint hands back the redirect instead of following it.
    public static let redirectURI = "http://127.0.0.1:47321/t3boii/callback"
    /// How long a `t3` CLI call may take before it is terminated.
    public static let cliTimeout: TimeInterval = 15

    public let origin: URL
    public let t3Home: URL
    private let session: URLSession

    public init(origin: URL, t3Home: URL, session: URLSession = T3MCPClient.makeSession()) {
        self.origin = origin
        self.t3Home = t3Home
        self.session = session
    }

    /// A new token, approved for `clientId` when one is given (registering a client only when
    /// there is none, or T3 no longer knows it). Returns the client id used.
    public func connect(clientId storedClientId: String?, now: Date = Date()) async throws -> (token: T3MCPToken, clientId: String) {
        if let storedClientId {
            do {
                return (try await mint(clientId: storedClientId, now: now), storedClientId)
            } catch let ConnectError.http(path, status) where path == "/oauth/mcp/decision" && (400..<500).contains(status) {
                // T3 forgot the client (for example a reset auth store): register again below.
            }
        }
        let clientId = try await register()
        return (try await mint(clientId: clientId, now: now), clientId)
    }

    /// Ends a replaced token's session. `sessionId` must come from `T3MCPToken.sessionId`.
    public func revokeSession(_ sessionId: String) async throws {
        guard T3CLILocator.isSafeArgument(sessionId) else { return }
        guard let cli = T3CLILocator.activeBinary(t3Home: t3Home) else { throw ConnectError.noCLI }
        _ = try await Self.run(cli, ["auth", "session", "revoke", sessionId], timeout: Self.cliTimeout)
    }

    private func register() async throws -> String {
        let registration = try await postJSON("/oauth/mcp/register", ["client_name": "T3boii desktop widget", "redirect_uris": [Self.redirectURI]])
        guard let clientId = registration["client_id"] as? String else { throw MCPError.malformed("registration has no client_id") }
        return clientId
    }

    private func mint(clientId: String, now: Date) async throws -> T3MCPToken {
        let pkce = T3MCPAuth.pkce(randomBytes: (0..<48).map { _ in UInt8.random(in: .min ... .max) })
        let state = UUID().uuidString
        let resource = origin.appendingPathComponent("mcp").absoluteString
        let authorization = T3MCPAuth.authorizationRequest(clientId: clientId, redirectURI: Self.redirectURI, pkce: pkce, state: state, resource: resource)

        let code = try await pairingCode()
        let decision = try await postJSON("/oauth/mcp/decision", [
            "authorization": authorization,
            "decision": ["_tag": "pairing-code", "access": "read-only", "code": code]
        ])
        guard let redirect = decision["redirectTo"] as? String else { throw MCPError.malformed("decision has no redirect") }
        let authCode = try T3MCPAuth.authorizationCode(fromRedirect: redirect, expectedState: state)

        var request = URLRequest(url: origin.appendingPathComponent("oauth/mcp/token"), timeoutInterval: T3MCPClient.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = T3MCPAuth.formBody([
            ("grant_type", "authorization_code"), ("code", authCode), ("redirect_uri", Self.redirectURI),
            ("client_id", clientId), ("code_verifier", pkce.verifier), ("resource", resource)
        ])
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw ConnectError.http("token", status) }
        return try T3MCPAuth.token(fromResponse: data, now: now)
    }

    private func pairingCode() async throws -> String {
        guard let cli = T3CLILocator.activeBinary(t3Home: t3Home) else { throw ConnectError.noCLI }
        let arguments = ["auth", "pairing", "create", "--scope", "orchestration:read", "--ttl", "2m", "--label", "T3boii desktop widget", "--json"]
        let output = try await Self.run(cli, arguments, timeout: Self.cliTimeout)
        guard let code = T3CLILocator.pairingCode(fromJSON: output) else {
            throw ConnectError.pairingFailed(String(decoding: output.prefix(200), as: UTF8.self))
        }
        return code
    }

    /// Runs the CLI and returns its stdout; a run past `timeout` is terminated and fails.
    static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval) async throws -> Data {
        let finish = CLIFinish()
        return try await withCheckedThrowingContinuation { continuation in
            finish.continuation = continuation
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            process.terminationHandler = { finished in
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                if finished.terminationStatus == 0 {
                    finish.resume(.success(data))
                } else {
                    finish.resume(.failure(ConnectError.pairingFailed("t3 exited \(finished.terminationStatus)")))
                }
            }
            do {
                try process.run()
            } catch {
                finish.resume(.failure(error))
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard finish.resume(.failure(ConnectError.cliTimedOut)) else { return }
                if process.isRunning { process.terminate() }
            }
        }
    }

    /// Resumes a continuation once, whichever of exit and timeout comes first.
    private final class CLIFinish: @unchecked Sendable {
        private let lock = NSLock()
        var continuation: CheckedContinuation<Data, Error>?

        @discardableResult
        func resume(_ result: Result<Data, Error>) -> Bool {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            guard let pending else { return false }
            pending.resume(with: result)
            return true
        }
    }

    private func postJSON(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: origin.appendingPathComponent(String(path.dropFirst())), timeoutInterval: T3MCPClient.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw ConnectError.http(path, status) }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MCPError.malformed("\(path) returned no object") }
        return object
    }
}

/// T3 threads as orbs, read through T3's MCP server.
///
/// Each poll lists projects, then each project's active threads (subagents included) and its
/// most recently updated other threads (for failures). Active threads are read
/// (`t3_thread_read`, activity view) for their pending requests, which make an orb wait on the
/// owner, and for the provider-native subagents running inside them, which become satellites.
/// A provider-native subagent can outlive its parent's turn: the parent is then `completed`
/// but its `updatedAt` follows the subagent's progress, so recently updated threads are read
/// too, and a thread stays followed while it has a subagent running. Reads are capped per poll
/// and rotate between threads; a thread not read this poll keeps what its last read found.
/// Orbs are never capped.
///
/// Without a usable token it connects headlessly, at most once per `reconnectInterval` unless
/// asked to. Any failure yields `[]` and one log line per new kind of problem; nothing reaches the UI.
public actor T3ThreadSource: OrbitSource {
    public static let defaultOrigin = URL(string: "http://127.0.0.1:3773")!
    /// `t3_thread_read` calls per poll, across all threads.
    public static let maxReadsPerPoll = 24
    /// Most recently updated non-active threads looked at per project and poll.
    static let recentPageSize = 15
    /// A non-active thread updated this recently may have a subagent still running.
    static let recentWindow: TimeInterval = 120

    private let client: T3MCPClient
    private let connector: T3MCPConnector
    private let tokenStore: T3TokenStoring
    private let icons: ProjectIconResolver
    private let log: @Sendable (String) -> Void
    private let reconnectInterval: TimeInterval
    private var lastConnectAttempt: Date?
    private var driverKinds: [String: String]?
    private var environmentId: String?
    private var metadataFetchedAt: Date?
    private var lastProblem: String?

    private var trackers: [String: T3ActivityTracker] = [:]
    private var pendingRequests: [String: Int] = [:]
    private var lastReadAt: [String: Date] = [:]
    /// Threads being followed for their subagents, with their project.
    private var followed: [String: (project: T3Project, thread: T3Thread)] = [:]
    /// Every thread seen listed lately, kept while it is listed or is a parent in orbit, so a
    /// parent whose own turn ended can hold its satellites (`T3OrbMapper.holdingParents`).
    private var knownThreads: [String: (project: T3Project, thread: T3Thread)] = [:]
    private var retention = FailedOrbRetention()
    /// The projects the last poll listed, for the demo (`DemoProjects`).
    public private(set) var knownProjects: [T3Project] = []

    public init(
        origin: URL = T3ThreadSource.defaultOrigin,
        t3Home: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".t3", isDirectory: true),
        tokenStore: T3TokenStoring,
        icons: ProjectIconResolver = ProjectIconResolver(),
        reconnectInterval: TimeInterval = 15 * 60,
        log: @escaping @Sendable (String) -> Void = { NSLog("%@", $0) }
    ) {
        self.client = T3MCPClient(origin: origin)
        self.connector = T3MCPConnector(origin: origin, t3Home: t3Home)
        self.tokenStore = tokenStore
        self.icons = icons
        self.reconnectInterval = reconnectInterval
        self.log = log
    }

    public func orbs(now: Date) async -> [Orb] {
        guard let token = await usableToken(now: now, force: false) else { return [] }
        await client.setToken(token.accessToken)
        do {
            let orbs = try await readOrbs(now: now)
            report(nil)
            return orbs
        } catch MCPError.unauthorized {
            // Revoked or expired early: retire it so the next poll reconnects and revokes it.
            var credentials = tokenStore.load()
            credentials.retireToken()
            tokenStore.save(credentials)
            await client.setToken(nil)
            report("T3 rejected the MCP token; reconnecting on a later poll")
            return []
        } catch {
            report("T3 not reachable (\(Self.describe(error))); orbit empty")
            return []
        }
    }

    /// The "Connect T3" action: get a fresh token now, whatever the last attempt was.
    @discardableResult
    public func connectNow() async -> Bool {
        var credentials = tokenStore.load()
        credentials.retireToken()
        tokenStore.save(credentials)
        return await usableToken(now: Date(), force: true) != nil
    }

    private func usableToken(now: Date, force: Bool) async -> T3MCPToken? {
        var credentials = tokenStore.load()
        if let token = credentials.token, token.isUsable(now: now) { return token }
        if !force, let last = lastConnectAttempt, now.timeIntervalSince(last) < reconnectInterval {
            return nil
        }
        lastConnectAttempt = now
        do {
            let minted = try await connector.connect(clientId: credentials.clientId, now: now)
            credentials.retireToken()
            let stale = credentials.staleSessionIds.filter { $0 != minted.token.sessionId }
            credentials = T3MCPCredentials(token: minted.token, clientId: minted.clientId, staleSessionIds: stale)
            tokenStore.save(credentials)
            log("T3boii: connected to T3's MCP server (read-only token, expires \(minted.token.expiresAt.map { "\($0)" } ?? "never"))")
            await revokeStaleSessions()
            return minted.token
        } catch let error as URLError {
            // T3 is not running: try again on the next poll rather than waiting out the interval.
            lastConnectAttempt = nil
            report("T3 not reachable (\(Self.describe(error))); orbit empty")
            return nil
        } catch {
            report("T3 MCP connect failed (\(Self.describe(error))); orbit empty")
            return nil
        }
    }

    /// Revokes the sessions of replaced tokens. One that T3 already ended fails to revoke and is dropped too.
    private func revokeStaleSessions() async {
        let stale = tokenStore.load().staleSessionIds
        guard !stale.isEmpty else { return }
        for sid in stale {
            do {
                try await connector.revokeSession(sid)
                log("T3boii: revoked the replaced T3 session \(sid.prefix(8))")
            } catch {
                log("T3boii: could not revoke the replaced T3 session \(sid.prefix(8)) (\(Self.describe(error)))")
            }
        }
        var credentials = tokenStore.load()
        credentials.staleSessionIds.removeAll { stale.contains($0) }
        tokenStore.save(credentials)
    }

    private func readOrbs(now: Date) async throws -> [Orb] {
        if metadataFetchedAt.map({ now.timeIntervalSince($0) > 10 * 60 }) ?? true {
            driverKinds = (try? T3Payload.driverKinds(try await client.callTool("orchestrator_capabilities"))) ?? driverKinds
            environmentId = (try? T3Payload.environmentId(try await client.callTool("t3_environment_read"))) ?? environmentId
            metadataFetchedAt = now
        }

        // Active threads and the most recently updated others, per project.
        var groups: [(project: T3Project, active: [T3Thread], recent: [T3Thread])] = []
        let projects = try await pages(of: T3Payload.projects) { cursor in
            try await self.client.callTool("t3_project_list", arguments: Self.paged(["limit": 100], cursor))
        }
        knownProjects = projects
        let otherStatuses = ["idle", "completed", "interrupted", T3ThreadStatus.failedStatus, "cancelled", "rolled_back"]
        for project in projects {
            let active = try await pages(of: T3Payload.threads) { cursor in
                try await self.client.callTool("t3_thread_list", arguments: Self.paged([
                    "projectId": project.id, "statuses": T3ThreadStatus.activeStatuses, "includeSubagents": true, "limit": 100
                ], cursor))
            }
            let recent = try T3Payload.threads(try await client.callTool("t3_thread_list", arguments: [
                "projectId": project.id, "statuses": otherStatuses, "includeSubagents": true, "limit": Self.recentPageSize
            ])).items
            if !active.isEmpty || !recent.isEmpty { groups.append((project, active, recent)) }
        }

        // Threads to read: active ones that do their own work (provider-native subagent threads are
        // only shells), recently updated ones, and ones with a subagent still running.
        var reads: [String: (project: T3Project, thread: T3Thread)] = [:]
        for group in groups {
            for thread in group.active where !thread.isProviderNativeSubagent {
                reads[thread.threadId] = (group.project, thread)
            }
            for thread in group.recent where !thread.isProviderNativeSubagent && !thread.status.isFailed {
                if let updated = thread.updatedAt, now.timeIntervalSince(updated) < Self.recentWindow {
                    reads[thread.threadId] = (group.project, thread)
                }
            }
        }
        for (id, entry) in followed where reads[id] == nil && trackers[id]?.currentSubagents.contains(where: \.isWorkActive) == true {
            reads[id] = entry
        }
        await readActivity(of: reads.values.map(\.thread), now: now)
        followed = reads.filter { trackers[$0.key]?.currentSubagents.contains(where: \.isWorkActive) == true }

        // Which failures still show.
        let activeThreads = groups.flatMap(\.active).filter { !$0.isProviderNativeSubagent }
        var activeIds = Set(activeThreads.map { T3OrbMapper.orbId($0.threadId) })
        var failed: [FailedOrbRetention.Candidate] = groups.flatMap(\.recent).filter { $0.status.isFailed && !$0.isProviderNativeSubagent }.map {
            .init(id: T3OrbMapper.orbId($0.threadId), updatedAt: $0.updatedAt)
        }
        for tracker in trackers.values {
            for item in tracker.currentSubagents {
                if item.isWorkActive { activeIds.insert(T3OrbMapper.orbId(item.orbKey)) }
                if item.isFailed { failed.append(.init(id: T3OrbMapper.orbId(item.orbKey), updatedAt: item.updatedAt)) }
            }
        }
        let failedShown = retention.update(activeIds: activeIds, failed: failed, now: now)

        let kinds = driverKinds ?? [:]
        let origin = client.origin
        let environment = environmentId
        let url: (String) -> String? = { threadId in
            environment.flatMap { T3OrbMapper.threadURL(origin: origin, environmentId: $0, threadId: threadId) }
        }
        var projectIcons: [String: OrbIcon] = [:]
        let iconFor = { (project: T3Project) -> OrbIcon in
            if let icon = projectIcons[project.id] { return icon }
            let icon = self.icons.resolve(workspaceRoot: project.workspaceRoot, faviconOverride: project.faviconPath, iconOverride: project.projectIcon, title: project.title, now: now)
            projectIcons[project.id] = icon
            return icon
        }
        var orbs: [Orb] = []
        for group in groups {
            let threads = group.active + group.recent.filter(\.status.isFailed)
            guard !threads.isEmpty else { continue }
            let activity = trackers.compactMapValues { $0.latestPhrase }
            orbs += T3OrbMapper.orbs(project: group.project, threads: threads, icon: iconFor(group.project), driverKinds: kinds, pendingRequests: pendingRequests, failedShown: failedShown, activity: activity, threadURL: url)
        }
        // Satellites carry their parent thread's orb id.
        for (id, entry) in reads.sorted(by: { $0.key < $1.key }) {
            guard let tracker = trackers[id] else { continue }
            orbs += T3OrbMapper.subagentOrbs(parent: entry.thread, project: entry.project, items: tracker.currentSubagents, icon: iconFor(entry.project), driverKinds: kinds, failedShown: failedShown, threadURL: url)
        }

        // A parent whose turn ended while its satellites work on stays in orbit to hold them;
        // one T3 no longer lists at all leaves them circling T3boii.
        var listed: Set<String> = []
        for group in groups {
            for thread in group.active + group.recent {
                knownThreads[thread.threadId] = (group.project, thread)
                listed.insert(thread.threadId)
            }
        }
        for (id, entry) in reads {
            knownThreads[id] = entry
            listed.insert(id)
        }
        let activity = trackers.compactMapValues { $0.latestPhrase }
        orbs = T3OrbMapper.holdingParents(orbs) { orbId in
            guard orbId.hasPrefix(T3OrbMapper.idPrefix),
                  let entry = self.knownThreads[String(orbId.dropFirst(T3OrbMapper.idPrefix.count))] else { return nil }
            return T3OrbMapper.threadOrb(project: entry.project, thread: entry.thread, state: entry.thread.status.isFailed ? .failed : .active, icon: iconFor(entry.project), driverKinds: kinds, activity: activity[entry.thread.threadId], threadURL: url)
        }
        let inOrbit = Set(orbs.map(\.id))
        knownThreads = knownThreads.filter { listed.contains($0.key) || inOrbit.contains(T3OrbMapper.orbId($0.key)) }
        return orbs
    }

    /// Reads threads' timelines within the per-poll budget, least recently read first. A read that
    /// fails leaves that thread as its last read found it, rather than emptying the whole orbit.
    private func readActivity(of threads: [T3Thread], now: Date) async {
        let live = Set(threads.map(\.threadId))
        trackers = trackers.filter { live.contains($0.key) }
        pendingRequests = pendingRequests.filter { live.contains($0.key) }
        lastReadAt = lastReadAt.filter { live.contains($0.key) }

        let ordered = threads.sorted {
            (lastReadAt[$0.threadId] ?? .distantPast, $0.threadId) < (lastReadAt[$1.threadId] ?? .distantPast, $1.threadId)
        }
        var budget = Self.maxReadsPerPoll
        for thread in ordered where budget > 0 {
            var tracker = trackers[thread.threadId] ?? T3ActivityTracker()
            tracker.pruneFinished()
            for read in tracker.plannedReads(itemCount: thread.itemCount).prefix(budget) {
                budget -= 1
                var arguments: [String: Any] = ["threadId": thread.threadId, "view": "activity", "limit": read.limit, "maxCharsPerItem": T3ActivityPhrase.readChars, "runLimit": 1]
                if let after = read.afterPosition { arguments["afterPosition"] = after }
                guard let activity = try? T3Payload.threadActivity(try await client.callTool("t3_thread_read", arguments: arguments)) else { break }
                pendingRequests[thread.threadId] = activity.pendingRequestCount
                tracker.absorb(activity, read: read)
            }
            trackers[thread.threadId] = tracker
            lastReadAt[thread.threadId] = now
        }
    }

    /// Every page of a cursor-paged list, at most 20 pages.
    private func pages<Item>(of decode: (Data) throws -> T3Page<Item>, _ call: (Int?) async throws -> Data) async throws -> [Item] {
        var items: [Item] = []
        var cursor: Int?
        for _ in 0..<20 {
            let page = try decode(try await call(cursor))
            items += page.items
            guard let next = page.nextCursor, !page.items.isEmpty else { break }
            cursor = next
        }
        return items
    }

    private static func paged(_ arguments: [String: Any], _ cursor: Int?) -> [String: Any] {
        var arguments = arguments
        if let cursor { arguments["cursor"] = cursor }
        return arguments
    }

    private func report(_ problem: String?) {
        guard problem != lastProblem else { return }
        lastProblem = problem
        if let problem { log("T3boii: \(problem)") }
    }

    private static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError { return "URLError \(urlError.code.rawValue)" }
        return String(describing: error)
    }
}
