import Foundation

/// T3 Code's MCP server over Streamable HTTP: `POST <origin>/mcp` with a bearer token.
/// Keeps one MCP session (`Mcp-Session-Id`) and re-initialises when the server drops it.
public actor T3MCPClient {
    public private(set) var origin: URL
    private let session: URLSession
    private var token: String?
    private var sessionId: String?
    private var initialized = false
    private var nextId = 1
    private var bucket: CallBucket
    /// Tool call requests made, a session retry included, in all and by tool, for the feed's own accounting.
    public private(set) var calls = 0
    public private(set) var callsByTool: [String: Int] = [:]
    /// Sessions the server dropped (it answered 404 to one): T3 restarted, as a rule.
    public private(set) var sessionsLost = 0

    public init(origin: URL, session: URLSession = T3MCPClient.makeSession(), bucket: CallBucket = .t3) {
        self.origin = origin
        self.session = session
        self.bucket = bucket
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

    /// T3 moved (a restart on another port): start a new session there.
    public func setOrigin(_ origin: URL) {
        guard origin != self.origin else { return }
        self.origin = origin
        sessionId = nil
        initialized = false
    }

    public func setToken(_ token: String?) {
        guard token != self.token else { return }
        self.token = token
        sessionId = nil
        initialized = false
    }

    /// Once more in a new session when the server dropped this one.
    public func callTool(_ name: String, arguments: [String: Any] = [:]) async throws -> Data {
        let params: [String: Any] = ["name": name, "arguments": arguments]
        do {
            return try await send(name, params)
        } catch MCPError.sessionExpired {
            sessionsLost += 1
            sessionId = nil
            initialized = false
            return try await send(name, params)
        }
    }

    /// One `tools/call` request. It waits its turn in the bucket first, so a poll that wants more
    /// than the cap takes longer, and counts in `calls`.
    private func send(_ name: String, _ params: [String: Any]) async throws -> Data {
        let wait = bucket.take(now: Date())
        if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        calls += 1
        callsByTool[name, default: 0] += 1
        try await ensureInitialized()
        return try MCPWire.toolPayload(try await request("tools/call", params: params))
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
/// Orbs are never capped. A running provider-native subagent's own thread (listed `idle`
/// whatever it does) is read just by its tail, for what its satellite is doing.
///
/// A thread that failed is read once more, just its last few items, to see whether its provider
/// refused it for a rate or usage limit; so are active threads' reads. Limits mark their orbs
/// (`Orb.limited`) and become episodes per provider (`ProviderLimitEpisodes`, `limits(now:)`).
///
/// Without a usable token it connects headlessly, at most once per `reconnectInterval` unless
/// asked to. Any failure yields no reading (nil) and one log line per new kind of problem.
public actor T3ThreadSource {
    public static let defaultOrigin = URL(string: "http://127.0.0.1:3773")!
    /// `t3_thread_read` calls per poll, across all threads. With the lists and tails below, a poll
    /// stays within `CallBucket.t3`'s burst, so the bucket rarely makes a poll wait.
    public static let maxReadsPerPoll = 4
    /// A thread whose item count and status have not moved is read again after this long anyway.
    static let rereadInterval: TimeInterval = 20
    /// Projects with nothing going on are listed a few per poll, in turn; the rest every poll.
    static let coldProjectsPerPoll = 2
    /// Most recently updated non-active threads looked at per project, and how often that list is
    /// read again on its own (hot projects, cold ones), a few projects per poll. It is read at once
    /// when one of the project's active threads leaves the active list, for how that thread ended.
    static let recentPageSize = 15
    static let recentRefresh: TimeInterval = 30
    static let coldRecentRefresh: TimeInterval = 120
    static let recentRefreshesPerPoll = 2
    /// Until it has seen everything once (`FeedReading.warming`), a fresh source reads more a poll.
    static let warmingReadsPerPoll = 8
    static let warmingRefreshesPerPoll = 4
    /// A poll starts no optional read (timelines, tails, recent lists, queues, seeds) after this
    /// long, so however the call bucket paces it, it lands inside `FeedEngine.sourceDeadline`.
    static let pollTimeBudget: TimeInterval = 5
    static let projectInterval: TimeInterval = 120
    /// A non-active thread updated this recently may have a subagent still running.
    static let recentWindow: TimeInterval = 120
    /// Failed threads whose tails are read per poll, for why they failed, and how many items each.
    static let maxFailureReadsPerPoll = 2
    static let failureTailItems = 8
    /// Running provider-native subagents whose own threads' tails are read per poll, and how many items each.
    static let maxSubagentReadsPerPoll = 3
    static let subagentTailItems = 8

    private let client: T3MCPClient
    private var connector: T3MCPConnector
    private let runtimeFile: URL
    private var server: T3ServerIdentity?
    private var tokenInUse: String?
    /// The token in use has been read with. One that worked and is then rejected was revoked or
    /// expired early, so a new one is minted at once; a fresh one rejected waits out `reconnectInterval`.
    private var tokenWorked = false
    private var sessionsLost = 0
    /// Why the next good reading is a resync, while one is owed (`FeedReading.resync`).
    private var resyncReason: String?
    /// Every hot project's recent list and every listed thread have been read once.
    private var warm = false
    private var pollStartedAt = Date()
    private var pollHasTime: Bool { Date().timeIntervalSince(pollStartedAt) < Self.pollTimeBudget }
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
    /// How many of those are questions (`t3_pending_request_list`); the rest are approvals.
    private var pendingQuestions: [String: Int] = [:]
    /// Messages queued behind each running thread's turn, read only when `readsQueues` (flag `queue`).
    private let readsQueues: Bool
    /// Scheduled tasks are read every `seedInterval` only when `readsSeeds` (flag `seeds`).
    private let readsSeeds: Bool
    private var seedsReadAt: Date?
    /// Seeds read while warming, which the world does not take: they go out with the first whole reading.
    private var heldSeeds: [FeedSeed]?
    static let seedInterval: TimeInterval = 60
    private var queued: [String: Int] = [:]
    /// A queue builds when someone writes to a running thread, so a thread with a message in the
    /// last `queueWindow`, or a queue still draining, has its queue read every `queueInterval`;
    /// any other active thread's only every `quietQueueInterval`, to catch a first queued message.
    private var messagedAt: [String: Date] = [:]
    private var queueReadAt: [String: Date] = [:]
    static let queueWindow: TimeInterval = 10 * 60
    static let queueInterval: TimeInterval = 6
    static let quietQueueInterval: TimeInterval = 60
    private var lastReadAt: [String: Date] = [:]
    private var projectsReadAt: Date?
    /// Each project's active thread ids and its other recent threads, as last listed.
    private var activeLists: [String: Set<String>] = [:]
    private var recentLists: [String: (at: Date, threads: [T3Thread])] = [:]
    /// Each thread's item count and status when last read, to skip reads that would find nothing new.
    private var lastReadShape: [String: String] = [:]
    /// Threads whose history was still being read this poll: their subagents were already there.
    private var bootstrapping: Set<String> = []
    /// Projects listed every poll: those with orbs or recent work. nil until the first full sweep.
    private var hotProjects: Set<String>?
    private var coldCursor = 0
    /// Threads being followed for their subagents, with their project.
    private var followed: [String: (project: T3Project, thread: T3Thread)] = [:]
    /// Every thread seen listed lately, kept while it is listed or is a parent in orbit, so a
    /// parent whose own turn ended can hold its satellites (`T3OrbMapper.holdingParents`).
    private var knownThreads: [String: (project: T3Project, thread: T3Thread)] = [:]
    private var retention = FailedOrbRetention()
    /// Failed threads' tails as last read: the limit that ended them, if one did, and the thread's
    /// `updatedAt` then, so each failure is read once.
    private var failureReads: [String: (updatedAt: Date?, providerInstanceId: String?, limit: T3LimitItem?)] = [:]
    /// Running provider-native subagents by satellite orb key: their own threads, what each was
    /// last seen doing there, and when each was last read.
    private var subagentThreads: [String: T3Thread] = [:]
    private var subagentActivity: [String: String] = [:]
    private var subagentReadAt: [String: Date] = [:]
    private var subagentReadCount: [String: Int?] = [:]
    private var episodes = ProviderLimitEpisodes()
    /// The projects the last poll listed, for the demo (`DemoProjects`).
    public private(set) var knownProjects: [T3Project] = []

    public init(
        origin: URL = T3ThreadSource.defaultOrigin,
        t3Home: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".t3", isDirectory: true),
        tokenStore: T3TokenStoring,
        icons: ProjectIconResolver = ProjectIconResolver(),
        reconnectInterval: TimeInterval = 15 * 60,
        readsQueues: Bool = false,
        readsSeeds: Bool = false,
        log: @escaping @Sendable (String) -> Void = { NSLog("%@", $0) }
    ) {
        self.readsQueues = readsQueues
        self.readsSeeds = readsSeeds
        self.client = T3MCPClient(origin: origin)
        self.connector = T3MCPConnector(origin: origin, t3Home: t3Home)
        self.runtimeFile = T3ServerIdentity.file(t3Home: t3Home)
        self.tokenStore = tokenStore
        self.icons = icons
        self.reconnectInterval = reconnectInterval
        self.log = log
    }

    /// One poll of T3, or nil when T3 could not be read.
    public func reading(now: Date) async -> FeedReading? {
        await checkServer()
        guard let token = await usableToken(now: now, force: false) else { return nil }
        if tokenInUse != token.accessToken {
            if tokenInUse != nil { owe("T3's MCP token changed") }
            tokenInUse = token.accessToken
            tokenWorked = false
        }
        await client.setToken(token.accessToken)
        do {
            var reading = try await readThreads(now: now)
            let lost = await client.sessionsLost
            if lost > sessionsLost { owe("T3 dropped the MCP session") }
            sessionsLost = lost
            tokenWorked = true
            // The engine's deadline won and drops this reading: the resync stays owed, or the next
            // reading would swallow what the restart cancelled.
            guard !Task.isCancelled else { return nil }
            if !reading.warming { heldSeeds = nil }
            if let reason = resyncReason {
                reading.resync = true
                resyncReason = nil
                log("T3boii: \(reason); orbit resynced without events")
            }
            report(nil)
            return reading
        } catch MCPError.unauthorized {
            // Revoked or expired early: retire it so the next poll reconnects and revokes it.
            var credentials = tokenStore.load()
            credentials.retireToken()
            tokenStore.save(credentials)
            await client.setToken(nil)
            if tokenWorked { lastConnectAttempt = nil }
            report("T3 rejected the MCP token; reconnecting on a later poll")
            return nil
        } catch {
            // A poll cut short (the app's fallback ending) says nothing about T3.
            if !Task.isCancelled { report("T3 not reachable (\(Self.describe(error))); orbit kept as last seen") }
            return nil
        }
    }

    /// A new `server-runtime.json` pid or start time is a restart; a new origin moves the client there.
    private func checkServer() async {
        guard let current = T3ServerIdentity.read(from: runtimeFile) else { return }
        if let server, !server.isSameServer(as: current) { owe("T3 restarted") }
        server = current
        if current.origin != connector.origin {
            await client.setOrigin(current.origin)
            connector = T3MCPConnector(origin: current.origin, t3Home: connector.t3Home)
        }
    }

    /// Owes a resync: every thread is read afresh and the next good reading is taken without events.
    private func owe(_ reason: String) {
        if resyncReason == nil { resyncReason = reason }
        lastReadShape = [:]
    }

    /// Providers at a rate or usage limit, as of the last poll; one that has lifted since goes now.
    public var toolCalls: Int { get async { await client.calls } }
    public var toolCallsByTool: [String: Int] { get async { await client.callsByTool } }

    public func limits(now: Date) -> [ProviderLimit] {
        episodes.update(sightings: [], progress: [], now: now)
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
            report("T3 not reachable (\(Self.describe(error))); orbit kept as last seen")
            return nil
        } catch {
            report("T3 MCP connect failed (\(Self.describe(error))); orbit kept as last seen")
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

    private func readThreads(now: Date) async throws -> FeedReading {
        pollStartedAt = Date()
        if metadataFetchedAt.map({ now.timeIntervalSince($0) > 10 * 60 }) ?? true {
            driverKinds = (try? T3Payload.driverKinds(try await client.callTool("orchestrator_capabilities"))) ?? driverKinds
            environmentId = (try? T3Payload.environmentId(try await client.callTool("t3_environment_read"))) ?? environmentId
            metadataFetchedAt = now
        }

        var groups: [(project: T3Project, active: [T3Thread], recent: [T3Thread])] = []
        if projectsReadAt.map({ now.timeIntervalSince($0) >= Self.projectInterval }) ?? true {
            knownProjects = try await pages(of: T3Payload.projects) { cursor in
                try await self.client.callTool("t3_project_list", arguments: Self.paged(["limit": 100], cursor))
            }
            projectsReadAt = now
            let ids = Set(knownProjects.map(\.id))
            activeLists = activeLists.filter { ids.contains($0.key) }
            recentLists = recentLists.filter { ids.contains($0.key) }
        }
        let projects = knownProjects
        let otherStatuses = ["idle", "completed", "interrupted", T3ThreadStatus.failedStatus, "cancelled", "rolled_back"]
        var listing = projects
        if let hot = hotProjects {
            let cold = projects.filter { !hot.contains($0.id) }
            let turn = cold.isEmpty ? [] : (0..<min(Self.coldProjectsPerPoll, cold.count)).map { cold[(coldCursor + $0) % cold.count].id }
            coldCursor = cold.isEmpty ? 0 : (coldCursor + turn.count) % cold.count
            listing = projects.filter { hot.contains($0.id) || turn.contains($0.id) }
        }
        var refreshes = warm ? Self.recentRefreshesPerPoll : Self.warmingRefreshesPerPoll
        // Threads first seen in a project's first recent list ended before the feed looked: not news.
        var alreadyOver: Set<String> = []
        for project in listing {
            let active = try await pages(of: T3Payload.threads) { cursor in
                try await self.client.callTool("t3_thread_list", arguments: Self.paged([
                    "projectId": project.id, "statuses": T3ThreadStatus.activeStatuses, "includeSubagents": true, "limit": 100
                ], cursor))
            }
            let before = activeLists[project.id] ?? []
            let listedActive = Set(active.filter { !$0.isProviderNativeSubagent }.map(\.threadId))
            let left = !before.isSubset(of: listedActive)
            activeLists[project.id] = listedActive
            let cached = recentLists[project.id]
            let refresh = (hotProjects?.contains(project.id) ?? true) ? Self.recentRefresh : Self.coldRecentRefresh
            var recent = cached?.threads ?? []
            if left || resyncReason != nil || (refreshes > 0 && pollHasTime && cached.map({ now.timeIntervalSince($0.at) >= refresh }) ?? true) {
                if !left { refreshes -= 1 }
                recent = try T3Payload.threads(try await client.callTool("t3_thread_list", arguments: [
                    "projectId": project.id, "statuses": otherStatuses, "includeSubagents": true, "limit": Self.recentPageSize
                ])).items
                if cached == nil { alreadyOver.formUnion(recent.filter { !before.contains($0.threadId) }.map { T3OrbMapper.orbId($0.threadId) }) }
                recentLists[project.id] = (now, recent)
            }
            if !active.isEmpty || !recent.isEmpty { groups.append((project, active, recent)) }
        }

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
        let readNow = await readActivity(of: reads.values.map(\.thread), budget: warm ? Self.maxReadsPerPoll : Self.warmingReadsPerPoll, now: now)
        followed = reads.filter { trackers[$0.key]?.currentSubagents.contains(where: \.isWorkActive) == true }
        await readSubagentActivity(listed: groups.flatMap { $0.active + $0.recent }, now: now)

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
        let failedThreads = groups.flatMap { group in
            group.recent.filter { $0.status.isFailed && !$0.isProviderNativeSubagent && failedShown.contains(T3OrbMapper.orbId($0.threadId)) }
        }
        await readFailures(failedThreads)

        let kinds = driverKinds ?? [:]
        let origin = await client.origin
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
            orbs += T3OrbMapper.orbs(project: group.project, threads: threads, icon: iconFor(group.project), driverKinds: kinds, pendingRequests: pendingRequests, pendingQuestions: pendingQuestions, failedShown: failedShown, activity: activity, threadURL: url)
        }
        for (id, entry) in reads.sorted(by: { $0.key < $1.key }) {
            guard let tracker = trackers[id] else { continue }
            orbs += T3OrbMapper.subagentOrbs(parent: entry.thread, project: entry.project, items: tracker.currentSubagents, icon: iconFor(entry.project), driverKinds: kinds, failedShown: failedShown, activity: subagentActivity, threadURL: url)
        }

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

        var hits: [String: String] = [:]
        var sightings: [ProviderLimitEpisodes.Sighting] = []
        let sight = { (orbId: String, limit: T3LimitItem, provider: String) in
            guard let at = limit.item.updatedAt, now.timeIntervalSince(at) < ProviderLimitEpisodes.freshness else { return }
            hits[orbId] = provider
            let words = [limit.item.title, limit.item.text].compactMap { $0 }.joined(separator: " ")
            sightings.append(.init(provider: provider, at: at, until: ProviderLimitText.until(in: words, at: at)))
        }
        for (id, read) in failureReads {
            if let limit = read.limit {
                sight(T3OrbMapper.orbId(id), limit, T3OrbMapper.providerId(instance: limit.providerInstanceId ?? read.providerInstanceId, driverKinds: kinds))
            }
        }
        for (id, entry) in reads {
            guard let tracker = trackers[id] else { continue }
            if let limit = tracker.limit {
                sight(T3OrbMapper.orbId(id), limit, T3OrbMapper.providerId(instance: limit.providerInstanceId ?? entry.thread.providerInstanceId, driverKinds: kinds))
            }
            // A subagent's error may be another provider's words; it says whose when it can.
            for item in tracker.currentSubagents where ProviderLimitText.isLimit(item) {
                let provider = ProviderLimitText.providerHint(item.text ?? "") ?? T3OrbMapper.providerId(instance: entry.thread.providerInstanceId, driverKinds: kinds)
                sight(T3OrbMapper.orbId(item.orbKey), T3LimitItem(item: item, providerInstanceId: nil), provider)
            }
        }
        // Proof a provider works again: a running thread of it, not itself at a limit, still updating.
        var progress: [ProviderLimitEpisodes.Progress] = []
        for group in groups {
            for thread in group.active where thread.status.rawValue == "running" && !thread.isProviderNativeSubagent && hits[T3OrbMapper.orbId(thread.threadId)] == nil {
                if let at = thread.updatedAt { progress.append(.init(provider: T3OrbMapper.providerId(instance: thread.providerInstanceId, driverKinds: kinds), at: at)) }
            }
        }
        let limits = episodes.update(sightings: sightings, progress: progress, now: now)
        orbs = ProviderLimitText.mark(orbs, hits: hits)
        if readsQueues {
            let byOrb = Dictionary(uniqueKeysWithValues: queued.map { (T3OrbMapper.orbId($0.key), $0.value) })
            for i in orbs.indices { orbs[i].queue = byOrb[orbs[i].id] }
        }

        hotProjects = Set(groups.filter { group in
            group.active.contains { !$0.isProviderNativeSubagent }
                || group.recent.contains { $0.updatedAt.map { now.timeIntervalSince($0) < Self.recentWindow } ?? false }
                || failedThreads.contains { thread in group.recent.contains { $0.threadId == thread.threadId } }
        }.map(\.project.id))
        warm = warm || (hotProjects?.allSatisfy { recentLists[$0] != nil } == true && reads.keys.allSatisfy { lastReadAt[$0] != nil })
        var seeds: [FeedSeed]?
        if readsSeeds, pollHasTime, seedsReadAt.map({ now.timeIntervalSince($0) >= Self.seedInterval }) ?? true {
            seeds = try? T3Payload.seeds(try await client.callTool("list_scheduled_tasks"), providers: kinds)
            if seeds != nil { seedsReadAt = now }
        }
        if warm { seeds = seeds ?? heldSeeds } else { heldSeeds = seeds ?? heldSeeds }
        return FeedReading(
            orbs: orbs,
            ended: ended(groups: groups),
            itemCounts: itemCounts(active: activeThreads),
            messages: readNow.sorted().flatMap { id in
                (trackers[id]?.arrivals ?? []).map { FeedMessage(orbId: T3OrbMapper.orbId(id), from: $0.createdBy == "user" ? .user : .agent) }
            },
            seen: Set(groups.flatMap(\.recent).filter { $0.status.isFailed && $0.settled }.map { T3OrbMapper.orbId($0.threadId) }),
            limits: limits,
            known: alreadyOver.union(bootstrapping.flatMap { id in (trackers[id]?.currentSubagents ?? []).map { T3OrbMapper.orbId($0.orbKey) } }),
            seeds: seeds,
            warming: !warm
        )
    }

    /// Orbs whose thread or subagent T3 lists as over, with how it ended: the threads among the
    /// most recently updated non-active ones, and the subagent items with an ending status.
    private func ended(groups: [(project: T3Project, active: [T3Thread], recent: [T3Thread])]) -> [String: String] {
        var ended: [String: String] = [:]
        for thread in groups.flatMap(\.recent) where !thread.isProviderNativeSubagent && !thread.status.isFailed {
            ended[T3OrbMapper.orbId(thread.threadId)] = thread.status.rawValue
        }
        ended.merge(T3OrbMapper.endedSubagents(trackers.values.flatMap(\.currentSubagents)), uniquingKeysWith: { _, subagent in subagent })
        return ended
    }

    /// Timeline lengths, for how busy each orb is: listed threads' own, and running subagents' threads'.
    private func itemCounts(active: [T3Thread]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for thread in active { if let count = thread.itemCount { counts[T3OrbMapper.orbId(thread.threadId)] = count } }
        for (key, thread) in subagentThreads { if let count = thread.itemCount { counts[T3OrbMapper.orbId(key)] = count } }
        return counts
    }

    /// Reads the tail of each newly shown failed thread once (within `maxFailureReadsPerPoll`), for
    /// a limit that ended it. A failure no longer shown is forgotten.
    private func readFailures(_ threads: [T3Thread]) async {
        let shown = Set(threads.map(\.threadId))
        failureReads = failureReads.filter { shown.contains($0.key) }
        var budget = Self.maxFailureReadsPerPoll
        for thread in threads where budget > 0 && pollHasTime {
            if let read = failureReads[thread.threadId], read.updatedAt == thread.updatedAt { continue }
            budget -= 1
            guard let activity = try? await readTail(of: thread.threadId, itemCount: thread.itemCount, items: Self.failureTailItems) else { continue }
            failureReads[thread.threadId] = (thread.updatedAt, thread.providerInstanceId, ProviderLimitText.latestLimit(in: activity.items, runProviders: activity.runProviders))
        }
    }

    /// Reads what each running provider-native subagent (Claude's Agent tool, Codex subagents) is
    /// doing from the tail of its own thread, which T3 lists `idle` whatever it does, so the thread
    /// reads above skip it. Within `maxSubagentReadsPerPoll`, least recently read first; one not read
    /// this poll keeps what its last read found, and one no longer running is forgotten.
    private func readSubagentActivity(listed: [T3Thread], now: Date) async {
        let running = trackers.flatMap { parentId, tracker in
            tracker.currentSubagents.filter { $0.isSubagent && $0.isWorkActive }.map { (parentId: parentId, item: $0) }
        }
        let live = Set(running.map(\.item.orbKey))
        subagentThreads = subagentThreads.filter { live.contains($0.key) }
        subagentActivity = subagentActivity.filter { live.contains($0.key) }
        subagentReadAt = subagentReadAt.filter { live.contains($0.key) }
        subagentReadCount = subagentReadCount.filter { live.contains($0.key) }
        for entry in running {
            if let thread = T3OrbMapper.subagentThread(for: entry.item, parentThreadId: entry.parentId, among: listed) {
                subagentThreads[entry.item.orbKey] = thread
            }
        }

        let keys = live.filter { subagentThreads[$0] != nil }.sorted {
            (subagentReadAt[$0] ?? .distantPast, $0) < (subagentReadAt[$1] ?? .distantPast, $1)
        }
        var budget = Self.maxSubagentReadsPerPoll
        for key in keys where budget > 0 && pollHasTime {
            guard var thread = subagentThreads[key] else { continue }
            if let read = subagentReadCount[key], read == thread.itemCount, let at = subagentReadAt[key], now.timeIntervalSince(at) < Self.rereadInterval { continue }
            budget -= 1
            guard var tail = try? await readTail(of: thread.threadId, itemCount: thread.itemCount, items: Self.subagentTailItems) else { continue }
            // The thread grew past the count it was read at: read its real tail once more.
            if tail.itemCount > (tail.nextPosition ?? -1) + 1, budget > 0,
               let newer = try? await readTail(of: thread.threadId, itemCount: tail.itemCount, items: Self.subagentTailItems) {
                budget -= 1
                tail = newer
            }
            thread.itemCount = tail.itemCount
            subagentThreads[key] = thread
            if let phrase = T3ActivityPhrase.latest(in: tail.items) { subagentActivity[key] = phrase }
            subagentReadAt[key] = now
            subagentReadCount[key] = thread.itemCount
        }
    }

    /// The last `items` items of a thread with `itemCount` items (its first items when the count is unknown).
    private func readTail(of threadId: String, itemCount: Int?, items: Int) async throws -> T3ThreadActivity {
        var arguments: [String: Any] = ["threadId": threadId, "view": "activity", "limit": items, "maxCharsPerItem": T3ActivityPhrase.readChars, "runLimit": 1]
        if let count = itemCount, count > items { arguments["afterPosition"] = count - items - 1 }
        return try T3Payload.threadActivity(try await client.callTool("t3_thread_read", arguments: arguments))
    }

    /// Reads threads' timelines within the per-poll budget, least recently read first, skipping
    /// one that cannot have changed (`rereadInterval`). A read that fails leaves that thread as its
    /// last read found it, rather than emptying the whole orbit. Returns the threads read.
    private func readActivity(of threads: [T3Thread], budget: Int, now: Date) async -> Set<String> {
        let live = Set(threads.map(\.threadId))
        trackers = trackers.filter { live.contains($0.key) }
        pendingRequests = pendingRequests.filter { live.contains($0.key) }
        pendingQuestions = pendingQuestions.filter { live.contains($0.key) }
        lastReadAt = lastReadAt.filter { live.contains($0.key) }
        lastReadShape = lastReadShape.filter { live.contains($0.key) }
        messagedAt = messagedAt.filter { live.contains($0.key) }
        queueReadAt = queueReadAt.filter { live.contains($0.key) }
        var read: Set<String> = []

        let ordered = threads.sorted {
            (lastReadAt[$0.threadId] ?? .distantPast, $0.threadId) < (lastReadAt[$1.threadId] ?? .distantPast, $1.threadId)
        }
        var budget = budget
        bootstrapping = []
        for thread in ordered where budget > 0 && pollHasTime {
            let shape = "\(thread.itemCount ?? -1)|\(thread.status.rawValue)"
            if lastReadShape[thread.threadId] == shape, (pendingRequests[thread.threadId] ?? 0) == 0,
               trackers[thread.threadId]?.currentSubagents.contains(where: \.isWorkActive) != true,
               let last = lastReadAt[thread.threadId], now.timeIntervalSince(last) < Self.rereadInterval {
                continue
            }
            var tracker = trackers[thread.threadId] ?? T3ActivityTracker()
            if !tracker.caughtUp { bootstrapping.insert(thread.threadId) }
            tracker.pruneFinished()
            var readAny = false
            for read in tracker.plannedReads(itemCount: thread.itemCount).prefix(budget) {
                budget -= 1
                var arguments: [String: Any] = ["threadId": thread.threadId, "view": "activity", "limit": read.limit, "maxCharsPerItem": T3ActivityPhrase.readChars, "runLimit": 1]
                if let after = read.afterPosition { arguments["afterPosition"] = after }
                guard let activity = try? T3Payload.threadActivity(try await client.callTool("t3_thread_read", arguments: arguments)) else { break }
                pendingRequests[thread.threadId] = activity.pendingRequestCount
                tracker.absorb(activity, read: read)
                readAny = true
            }
            if readAny {
                if !tracker.arrivals.isEmpty { messagedAt[thread.threadId] = now }
                await readPendingQuestions(of: thread.threadId)
                if readsQueues { await readQueue(of: thread, now: now) }
                lastReadShape[thread.threadId] = shape
            }
            trackers[thread.threadId] = tracker
            lastReadAt[thread.threadId] = now
            read.insert(thread.threadId)
        }
        return read
    }

    /// How many of a thread's pending requests are questions for its owner rather than approvals,
    /// asked only while it has any. A failed ask keeps what the last one found.
    private func readPendingQuestions(of threadId: String) async {
        guard (pendingRequests[threadId] ?? 0) > 0 else { pendingQuestions[threadId] = nil; return }
        guard let ids = try? T3Payload.pendingQuestionIds(try await client.callTool("t3_pending_request_list", arguments: ["threadId": threadId])) else { return }
        pendingQuestions[threadId] = ids.count
    }

    /// How many messages wait behind a running thread's turn; a beads string needs four at most.
    private func readQueue(of thread: T3Thread, now: Date) async {
        guard thread.status.isActive else { queued[thread.threadId] = nil; return }
        let lively = queued[thread.threadId] != nil || messagedAt[thread.threadId].map { now.timeIntervalSince($0) < Self.queueWindow } == true
        if let last = queueReadAt[thread.threadId], now.timeIntervalSince(last) < (lively ? Self.queueInterval : Self.quietQueueInterval) { return }
        queueReadAt[thread.threadId] = now
        guard let count = try? T3Payload.queuedCount(try await client.callTool("t3_queue_list", arguments: ["threadId": thread.threadId, "limit": 4])) else { return }
        queued[thread.threadId] = count > 0 ? count : nil
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
