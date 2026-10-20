import Foundation

public struct Orb: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        case t3
        case grok
    }

    public enum State: String, Codable, Sendable {
        case active
        case waiting
        case failed
    }

    /// What a waiting orb waits on: the owner's answer to a question (it shows a "?"), or their
    /// approval of something it wants to do (a "!").
    public enum WaitingFor: String, Codable, Sendable {
        case input
        case approval
    }

    /// A linked pull request's checks, for the ring on its orb.
    public enum PullRequestState: String, Codable, Sendable {
        case pending
        case pass
        case fail
    }

    /// Stable across snapshots; the scene diffs ids to spawn and reabsorb.
    public var id: String
    /// Set for a subagent; the orb orbits its parent's orb.
    public var parentId: String?
    public var source: Source
    public var projectIcon: OrbIcon
    /// T3 driver id (`codex`, `claudeAgent`, `grok`, ...) for the badge.
    public var provider: String
    public var state: State
    /// Set only when `state` is `.waiting`, and only when the source can tell.
    public var waitingFor: WaitingFor?
    /// Short human label, for example the thread or agent title.
    public var label: String?
    /// Where clicking the orb goes, for example the thread in T3's web UI.
    public var link: String?
    /// A few words on what it is doing right now, for T3boii's speech bubble ("running swift build").
    public var activity: String?
    /// When it last did anything, in seconds since 1970, so the page can tell a busy orb from a stuck one.
    public var activeAt: Double?
    /// Its provider refused it for a rate or usage limit: the orb dies (dissolves under the provider's
    /// logo) instead of cracking. nil, not false, otherwise, so the JSON only says so when it is.
    public var limited: Bool?
    /// The provider that refused it, for that logo; usually `provider`.
    public var limitProvider: String?
    /// The model the thread runs on (`claude-opus-5-5`), when the source says.
    public var model: String?
    /// How busy it is, 0 (idle) to 1 (30 or more timeline items a minute), in steps of 0.05.
    /// Set by `FeedWorld` from the thread's item count; nil when the source cannot count.
    public var level: Double?
    /// The thread is snoozed in T3 until this time (seconds since 1970): it waits as an egg at his feet.
    public var snoozedUntil: Double?
    /// Messages queued for the thread's next turn.
    public var queue: Int?
    public var pr: PullRequestState?

    public init(id: String, parentId: String? = nil, source: Source, projectIcon: OrbIcon, provider: String, state: State = .active, waitingFor: WaitingFor? = nil, label: String? = nil, link: String? = nil, activity: String? = nil, activeAt: Double? = nil, limited: Bool? = nil, limitProvider: String? = nil, model: String? = nil, level: Double? = nil, snoozedUntil: Double? = nil, queue: Int? = nil, pr: PullRequestState? = nil) {
        self.id = id
        self.parentId = parentId
        self.source = source
        self.projectIcon = projectIcon
        self.provider = provider
        self.state = state
        self.waitingFor = waitingFor
        self.label = label
        self.link = link
        self.activity = activity
        self.activeAt = activeAt
        self.limited = limited
        self.limitProvider = limitProvider
        self.model = model
        self.level = level
        self.snoozedUntil = snoozedUntil
        self.queue = queue
        self.pr = pr
    }
}

/// The face of an orb: an image (as a `data:` URL, since the page may only load local and data URLs) or a coloured monogram.
public struct OrbIcon: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case image
        case monogram
    }

    public var kind: Kind
    /// The image when `kind == .image`: a `data:` URL, or a path relative to the pet page (`Resources/Pet`).
    public var src: String?
    /// One or two letters when `kind == .monogram`.
    public var text: String?
    /// `#rrggbb`: the monogram fill, or a ring colour around an image (Grok avatars).
    public var color: String?

    public init(kind: Kind, src: String? = nil, text: String? = nil, color: String? = nil) {
        self.kind = kind
        self.src = src
        self.text = text
        self.color = color
    }

    public static func image(dataURL: String, ring: String? = nil) -> OrbIcon {
        OrbIcon(kind: .image, src: dataURL, color: ring)
    }

    /// An image shipped with the pet page, e.g. `./badges/grokBot.png`; no ring.
    public static func bundled(_ path: String) -> OrbIcon {
        OrbIcon(kind: .image, src: path)
    }

    public static func monogram(_ text: String, color: String) -> OrbIcon {
        OrbIcon(kind: .monogram, text: text, color: color)
    }
}
