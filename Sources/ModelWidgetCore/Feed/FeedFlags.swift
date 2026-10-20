import Foundation

/// The parts of the feed that are switched by name: `queue` (queued messages) and `seeds`
/// (scheduled tasks). The helper's `--flags` and the app's `petFeedFlags` default both read
/// through `parse`, so the helper and the app's own fallback polling always agree.
public struct FeedFlags: Equatable, Sendable {
    public static let standard: Set<String> = ["queue", "seeds"]
    /// The parts something reads. Any other name, `pr` included until pull requests are read, is
    /// reported in `unknown` and changes nothing.
    public static let known: Set<String> = standard

    public private(set) var on: Set<String>
    /// The names, as written (`-` kept), that switch no part.
    public private(set) var unknown: [String]

    /// The standard parts, plus each name in `text` (comma separated) and less each `-name`:
    /// `-seeds` turns seeds off.
    public static func parse(_ text: String?) -> FeedFlags {
        var flags = FeedFlags(on: standard, unknown: [])
        for part in (text ?? "").split(separator: ",") {
            let written = part.trimmingCharacters(in: .whitespaces)
            let off = written.hasPrefix("-")
            let name = off ? String(written.dropFirst()) : written
            guard !name.isEmpty else { continue }
            guard known.contains(name) else { flags.unknown.append(written); continue }
            if off { flags.on.remove(name) } else { flags.on.insert(name) }
        }
        return flags
    }

    public func contains(_ name: String) -> Bool { on.contains(name) }

    /// `on` as `--flags` text, or nil when it is the standard set: what the app hands its helper,
    /// so a misspelt default never stops the helper from starting.
    public var argument: String? {
        let names = on.subtracting(Self.standard).sorted() + Self.standard.subtracting(on).sorted().map { "-" + $0 }
        return names.isEmpty ? nil : names.joined(separator: ",")
    }
}
