import Foundation
import Network

/// The feed over loopback HTTP, for the app (and anything else holding the token).
///
/// `GET /v1/health`, `GET /v1/state`, `GET /v1/events`, `GET /v1/demo` (the owner's projects for
/// the demo) and `POST /v1/connect` (fetch a new T3 token now).
///
/// `/v1/events` is server-sent events. Each change is its events (`id: <seq>`, the event as JSON)
/// then `event: state` with the state they lead to. `Last-Event-ID` or `?after=` replays what was
/// missed, then the current state; otherwise, or when the buffer no longer reaches back, `event: reset` with the state comes first. Every request needs the bearer token, a `Host`
/// of exactly `127.0.0.1:<port>`, and no `Origin`: no web page can reach it, even one that
/// rebinds a name to 127.0.0.1.
public final class FeedServer: @unchecked Sendable {
    public static let pingInterval: TimeInterval = 10
    static let maxHeaderBytes = 16 * 1024

    private let engine: FeedEngine
    private let token: String
    private let connect: @Sendable () async -> Bool
    private let demo: @Sendable () async -> String?
    private let queue = DispatchQueue(label: "t3boii.feed.server")
    private var listener: NWListener?
    public private(set) var port: UInt16 = 0

    public init(engine: FeedEngine, token: String, connect: @escaping @Sendable () async -> Bool = { false }, demo: @escaping @Sendable () async -> String? = { nil }) {
        self.engine = engine
        self.token = token
        self.connect = connect
        self.demo = demo
    }

    /// Starts listening on 127.0.0.1 (`port` 0 picks a free one) and returns the port.
    public func start(port requested: UInt16 = 0) async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: requested) ?? .any)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        return try await withCheckedThrowingContinuation { continuation in
            let once = Once()
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    let port = listener.port?.rawValue ?? 0
                    self?.port = port
                    once.run { continuation.resume(returning: port) }
                case let .failed(error):
                    once.run { continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        readHead(connection, buffer: Data())
    }

    private func readHead(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                Task { await self.respond(to: FeedRequest(head: head), on: connection) }
            } else if error != nil || complete || buffer.count > Self.maxHeaderBytes {
                connection.cancel()
            } else {
                self.readHead(connection, buffer: buffer)
            }
        }
    }

    private func respond(to request: FeedRequest?, on connection: NWConnection) async {
        guard let request else { return send(connection, status: 400, body: #"{"error":"bad request"}"#) }
        if let refusal = refusal(of: request) { return send(connection, status: refusal.status, body: #"{"error":"\#(refusal.reason)"}"#) }
        switch (request.method, request.path) {
        case ("GET", "/v1/health"):
            let state = await engine.state
            send(connection, status: 200, body: #"{"ok":true,"seq":\#(state.seq),"source":"\#(state.source.rawValue)","v":\#(FeedState.version)}"#)
        case ("GET", "/v1/state"):
            send(connection, status: 200, body: FeedJSON.encode(await engine.state))
        case ("GET", "/v1/events"):
            await stream(to: connection, after: request.lastEventId)
        case ("GET", "/v1/demo"):
            send(connection, status: 200, body: await demo() ?? "null")
        case ("POST", "/v1/connect"):
            let connected = await connect()
            await engine.pollNow()
            send(connection, status: 200, body: #"{"connected":\#(connected)}"#)
        default:
            send(connection, status: 404, body: #"{"error":"not found"}"#)
        }
    }

    /// Why a request is refused, if it is.
    func refusal(of request: FeedRequest) -> (status: Int, reason: String)? {
        if request.headers["origin"] != nil { return (403, "origin") }
        if request.headers["host"] != "127.0.0.1:\(port)" { return (403, "host") }
        guard let auth = request.headers["authorization"], auth.hasPrefix("Bearer "),
              Self.constantTimeEqual(String(auth.dropFirst("Bearer ".count)), token) else { return (401, "token") }
        return nil
    }

    private func stream(to connection: NWConnection, after: Int?) async {
        let (id, batches) = await engine.subscribe()
        let (state, missed) = await engine.resume(after: after)
        var head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-store\r\nConnection: keep-alive\r\n\r\n"
        var sent = state.seq
        if let missed {
            // Even with nothing missed: seeds, activity and a resync change the state without an event.
            for event in missed { head += Self.frame(event) }
            head += Self.frame(state)
        } else {
            head += "event: reset\nid: \(state.seq)\ndata: \(FeedJSON.encode(state))\n\n"
        }
        let open = OpenFlag()
        let engine = self.engine
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled:
                open.close()
                Task { await engine.unsubscribe(id) }
            default:
                break
            }
        }
        write(connection, head, open: open)

        let pings = Task {
            while !Task.isCancelled, open.isOpen {
                try? await Task.sleep(nanoseconds: UInt64(Self.pingInterval * 1_000_000_000))
                write(connection, ": ping\n\n", open: open)
            }
        }
        for await batch in batches {
            guard open.isOpen else { break }
            let fresh = batch.events.filter { $0.seq > sent }
            guard batch.state.seq > sent || batch.events.isEmpty else { continue }
            sent = max(sent, batch.state.seq)
            write(connection, fresh.map(Self.frame).joined() + Self.frame(batch.state), open: open)
        }
        pings.cancel()
        await engine.unsubscribe(id)
        connection.cancel()
    }

    private func write(_ connection: NWConnection, _ text: String, open: OpenFlag) {
        guard open.isOpen else { return }
        connection.send(content: Data(text.utf8), completion: .contentProcessed { error in
            if error != nil { open.close() }
        })
    }

    static func frame(_ event: FeedEvent) -> String {
        "id: \(event.seq)\ndata: \(FeedJSON.encode(event))\n\n"
    }

    static func frame(_ state: FeedState) -> String {
        "event: state\nid: \(state.seq)\ndata: \(FeedJSON.encode(state))\n\n"
    }

    private func send(_ connection: NWConnection, status: Int, body: String) {
        let reason = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found"][status] ?? "Error"
        let bytes = Data(body.utf8)
        let response = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nContent-Length: \(bytes.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8) + bytes, completion: .contentProcessed { _ in connection.cancel() })
    }

    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        return zip(x, y).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func run(_ body: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            body()
        }
    }

    final class OpenFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var open = true
        var isOpen: Bool { lock.lock(); defer { lock.unlock() }; return open }
        func close() { lock.lock(); open = false; lock.unlock() }
    }
}

/// The parts of an HTTP request head the feed looks at.
struct FeedRequest {
    var method: String
    var path: String
    var query: [String: String]
    /// Lowercased names.
    var headers: [String: String]

    init?(head: String) {
        var lines = head.components(separatedBy: "\r\n")
        let parts = lines.removeFirst().split(separator: " ")
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1.") else { return nil }
        method = String(parts[0])
        let target = URLComponents(string: String(parts[1]))
        path = target?.path ?? ""
        query = Dictionary((target?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return nil }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        self.headers = headers
    }

    var lastEventId: Int? {
        (headers["last-event-id"]).flatMap(Int.init) ?? query["after"].flatMap(Int.init)
    }
}
