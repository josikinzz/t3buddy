import Foundation

/// Server-sent events, as `FeedServer` writes them: fields up to a blank line make one frame.
public struct FeedStreamParser: Sendable {
    public struct Frame: Equatable, Sendable {
        /// `message` for an event, `state` or `reset` for a state.
        public var kind: String
        public var id: Int?
        public var data: String

        public init(kind: String, id: Int?, data: String) {
            self.kind = kind
            self.id = id
            self.data = data
        }
    }

    private var kind: String?
    private var id: Int?
    private var data: [String] = []

    public init() {}

    /// Takes one line (without its newline); a blank line ends a frame and returns it.
    public mutating func take(_ line: Substring) -> Frame? {
        if line.isEmpty {
            defer { kind = nil; id = nil; data = [] }
            guard !data.isEmpty else { return nil }
            return Frame(kind: kind ?? "message", id: id, data: data.joined(separator: "\n"))
        }
        guard !line.hasPrefix(":"), let colon = line.firstIndex(of: ":") else { return nil }
        var value = line[line.index(after: colon)...]
        if value.hasPrefix(" ") { value = value.dropFirst() }
        switch line[..<colon] {
        case "event": kind = String(value)
        case "id": id = Int(value)
        case "data": data.append(String(value))
        default: break
        }
        return nil
    }
}

/// What the app hands the page (`window.t3boii.feed`): events since the last call, and the state
/// when it changed. Collects frames between deliveries.
public struct FeedRelay: Sendable {
    public private(set) var lastSeq: Int?
    private var events: [String] = []
    private var state: String?
    private var delivered: String?

    public init() {}

    public mutating func take(_ frame: FeedStreamParser.Frame) {
        if let id = frame.id { lastSeq = id }
        switch frame.kind {
        case "state", "reset": state = frame.data
        default: events.append(frame.data)
        }
    }

    /// The argument for `window.t3boii.feed`, or nil when there is nothing new.
    public mutating func flush() -> String? {
        let changed = state.flatMap { $0 == delivered ? nil : $0 }
        guard !events.isEmpty || changed != nil else { return nil }
        defer { events = []; if let changed { delivered = changed } }
        var parts: [String] = []
        if !events.isEmpty { parts.append(#""events":[\#(events.joined(separator: ","))]"#) }
        if let changed { parts.append(#""state":\#(changed)"#) }
        return "{\(parts.joined(separator: ","))}"
    }

    /// The state as last delivered, for a page that reloads.
    public var currentState: String? { delivered }

    /// The last state with its source marked stale, for when the feed itself has gone quiet.
    public mutating func markStale() -> String? {
        guard let json = delivered ?? state, var current = try? JSONDecoder().decode(FeedState.self, from: Data(json.utf8)), current.source != .stale else { return nil }
        current.source = .stale
        state = FeedJSON.encode(current)
        return flush()
    }
}

extension FeedDiscovery {
    /// A request to this feed, authorised.
    public func request(_ method: String, _ path: String, timeout: TimeInterval = 5) -> URLRequest {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Whether the process that wrote this is still running.
    public var isAlive: Bool { kill(pid, 0) == 0 }
}
