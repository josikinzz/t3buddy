import Foundation

/// What the widget keeps between launches to talk to T3's MCP server.
public struct T3MCPCredentials: Codable, Equatable, Sendable {
    public var token: T3MCPToken?
    /// The OAuth client registered once and reused for every mint, so re-mints do not pile up clients.
    public var clientId: String?
    /// Sessions of tokens that were replaced or rejected, revoked after the next mint.
    public var staleSessionIds: [String]

    public init(token: T3MCPToken? = nil, clientId: String? = nil, staleSessionIds: [String] = []) {
        self.token = token
        self.clientId = clientId
        self.staleSessionIds = staleSessionIds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try container.decodeIfPresent(T3MCPToken.self, forKey: .token)
        clientId = try container.decodeIfPresent(String.self, forKey: .clientId)
        staleSessionIds = try container.decodeIfPresent([String].self, forKey: .staleSessionIds) ?? []
    }

    /// Drops the token, remembering its session so the next mint revokes it.
    public mutating func retireToken() {
        if let sid = token?.sessionId, !staleSessionIds.contains(sid) { staleSessionIds.append(sid) }
        token = nil
    }
}

/// Where the T3 MCP credentials live.
public protocol T3TokenStoring: Sendable {
    func load() -> T3MCPCredentials
    func save(_ credentials: T3MCPCredentials)
}

/// The credentials as a JSON file only this user can read: the folder is 0700, the file 0600,
/// written atomically. Any process of this user can already run `t3` and mint a token, so this
/// protects the token as well as a Keychain item would, and it survives ad-hoc rebuilds.
public final class T3TokenFileStore: T3TokenStoring, @unchecked Sendable {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LocalModelWidget", isDirectory: true)
            .appendingPathComponent("t3-mcp-token.json")
    }

    public let url: URL
    private let lock = NSLock()
    private var cached: T3MCPCredentials?
    /// The file's modification date when `cached` was read: the helper and the app's fallback
    /// share the file, so one sees a token the other minted.
    private var cachedStamp: Date?

    public init(url: URL = T3TokenFileStore.defaultURL) {
        self.url = url
    }

    /// Whether a credentials file exists yet (the Keychain migration only runs before it does).
    public var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    public func load() -> T3MCPCredentials {
        lock.lock()
        defer { lock.unlock() }
        let stamp = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if let cached, stamp == cachedStamp { return cached }
        let loaded = (try? Data(contentsOf: url)).flatMap { try? Self.decoder.decode(T3MCPCredentials.self, from: $0) } ?? cached ?? T3MCPCredentials()
        cached = loaded
        cachedStamp = stamp
        return loaded
    }

    public func save(_ credentials: T3MCPCredentials) {
        saveVerified(credentials)
    }

    /// Saves, then reads the file back: true only when the file holds exactly the bytes written. Bytes,
    /// not decoded values: the file keeps whole seconds, so a fractional expiry never reads back equal.
    @discardableResult
    public func saveVerified(_ credentials: T3MCPCredentials) -> Bool {
        lock.lock()
        cached = credentials
        lock.unlock()
        let written: Data
        do {
            written = try write(credentials)
        } catch {
            NSLog("T3boii: could not write the T3 token file (\(error.localizedDescription))")
            return false
        }
        return (try? Data(contentsOf: url)) == written
    }

    private func write(_ credentials: T3MCPCredentials) throws -> Data {
        let manager = FileManager.default
        let folder = url.deletingLastPathComponent()
        try manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let data = try Self.encoder.encode(credentials)
        let temporary = folder.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        guard manager.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        if rename(temporary.path, url.path) != 0 {
            let code = errno
            try? manager.removeItem(at: temporary)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        return data
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Adopts the token an earlier build kept in the Keychain. The caller deletes the Keychain item only
/// after `.moved`: a payload that cannot be decoded, or a file that cannot be written, leaves it in place.
public enum LegacyT3TokenImport {
    public enum Outcome: Equatable, Sendable {
        case moved
        case undecodable
        case notSaved
    }

    public static func adopt(_ legacy: Data, into store: T3TokenFileStore) -> Outcome {
        guard let token = try? JSONDecoder().decode(T3MCPToken.self, from: legacy) else { return .undecodable }
        return store.saveVerified(T3MCPCredentials(token: token)) ? .moved : .notSaved
    }
}
