import Foundation

/// A project's manual icon from T3 (`projectIcon` on `t3_project_list` / `t3_project_read`).
/// T3 Code's sidebar shows it ahead of any favicon.
public enum ProjectIconOverride: Equatable, Sendable {
    /// `color` is a T3 palette name, for example `blue`.
    case monogram(text: String, color: String)
    case emoji(String)
    /// A lucide glyph; the orb cannot draw lucide, so it shows the title monogram in `color`.
    case lucide(name: String, color: String)

    /// Decodes T3's `{ kind, ... }` object; anything else is no override.
    public init?(json: Any?) {
        guard let object = json as? [String: Any], let kind = object["kind"] as? String else { return nil }
        switch kind {
        case "monogram":
            guard let text = object["text"] as? String, !text.isEmpty else { return nil }
            self = .monogram(text: text, color: object["color"] as? String ?? "blue")
        case "emoji":
            guard let emoji = object["emoji"] as? String, !emoji.isEmpty else { return nil }
            self = .emoji(emoji)
        case "lucide":
            guard let name = object["name"] as? String else { return nil }
            self = .lucide(name: name, color: object["color"] as? String ?? "gray")
        default:
            return nil
        }
    }
}

/// T3 Code's project monogram: two letters and a palette colour derived from the project name
/// (client `ProjectMonogram`, 0.0.46).
public enum ProjectMonogram {
    /// T3's palette, in its order (the hash indexes it), with Tailwind's 500 swatch.
    public static let palette: [(name: String, hex: String)] = [
        ("gray", "#6b7280"), ("red", "#ef4444"), ("orange", "#f97316"), ("amber", "#f59e0b"),
        ("yellow", "#eab308"), ("lime", "#84cc16"), ("green", "#22c55e"), ("emerald", "#10b981"),
        ("teal", "#14b8a6"), ("cyan", "#06b6d4"), ("sky", "#0ea5e9"), ("blue", "#3b82f6"),
        ("indigo", "#6366f1"), ("violet", "#8b5cf6"), ("purple", "#a855f7"), ("fuchsia", "#d946ef"),
        ("pink", "#ec4899"), ("rose", "#f43f5e")
    ]

    /// First letter of the first word, then the first digit after it, else the first letter
    /// of the last word, else the first word's last letter. `semantic-space` → `SS`.
    public static func text(for name: String) -> String {
        let words = wordRuns(normalized(name))
        guard let first = words.first, let lead = first.first else { return "PR" }
        let rest = first.dropFirst()
        let second = rest.first(where: { $0.isNumber })
            ?? (words.count > 1 ? words.last?.first : first.last)
            ?? lead
        return String(String([lead, second]).uppercased().prefix(2))
    }

    public static func colorName(for name: String) -> String {
        var key = normalized(name).lowercased()
        if key.isEmpty { key = "project" }
        var hash = 0
        for scalar in key.unicodeScalars {
            hash = (hash * 31 + Int(scalar.value)) % palette.count
        }
        return palette[hash].name
    }

    public static func hex(forColorName name: String) -> String {
        palette.first { $0.name == name }?.hex ?? "#3b82f6"
    }

    public static func icon(for name: String) -> OrbIcon {
        .monogram(text(for: name), color: hex(forColorName: colorName(for: name)))
    }

    private static func normalized(_ name: String) -> String {
        name.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs of letters and digits (`[\p{L}\p{N}]+`).
    private static func wordRuns(_ text: String) -> [[Character]] {
        var runs: [[Character]] = []
        var current: [Character] = []
        for character in text {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                runs.append(current)
                current = []
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }
}

/// Finds a project's face the way T3 Code 0.0.46 does (server `ProjectFaviconResolver`,
/// client `ProjectFavicon`), and encodes it for the pet page.
///
/// Order: the manual `projectIcon`; the project's `faviconPath`; `t3.json`'s `iconPath`;
/// the fixed candidate list; the `rel="icon"` link in an HTML or root route file, resolved
/// against `public/`; then the title monogram. Results are cached per workspace root and
/// revalidated by the icon file's modification time.
public final class ProjectIconResolver: @unchecked Sendable {
    /// T3 Code 0.0.46's `FAVICON_CANDIDATES`, plus `public/favicon.webp` (T3 only finds a
    /// webp through a manual `faviconPath`). A T3 update can change this list.
    public static let faviconCandidates = [
        "favicon.svg", "favicon.ico", "favicon.png",
        "public/favicon.svg", "public/favicon.ico", "public/favicon.png", "public/favicon.webp",
        "app/favicon.ico", "app/favicon.png", "app/icon.svg", "app/icon.png", "app/icon.ico",
        "src/favicon.ico", "src/favicon.svg",
        "src/app/favicon.ico", "src/app/icon.svg", "src/app/icon.png",
        "assets/icon.svg", "assets/icon.png", "assets/logo.svg", "assets/logo.png",
        ".idea/icon.svg",
        "Resources/AppIcon.icns", "AppIcon.icns"
    ]

    /// T3 Code 0.0.46's `ICON_SOURCE_FILES`: files whose `rel="icon"` link names the icon.
    public static let iconSourceFiles = [
        "index.html", "public/index.html",
        "app/routes/__root.tsx", "src/routes/__root.tsx",
        "app/root.tsx", "src/root.tsx", "src/index.html"
    ]

    public static let projectFileName = "t3.json"
    /// Bigger files fall back to the monogram rather than bloat every snapshot.
    public static let maxImageBytes = 512 * 1024
    static let positiveTTL: TimeInterval = 10 * 60
    static let negativeTTL: TimeInterval = 60

    /// Turns a file WebKit cannot show (`.icns`) into PNG bytes; nil skips it.
    public typealias Transcoder = @Sendable (URL) -> Data?

    private struct Entry {
        var path: String?
        var modified: Date?
        var icon: OrbIcon
        var resolvedAt: Date
    }

    private let fileManager: FileManager
    private let transcodeToPNG: Transcoder?
    private let lock = NSLock()
    private var cache: [String: Entry] = [:]

    public init(fileManager: FileManager = .default, transcodeToPNG: Transcoder? = nil) {
        self.fileManager = fileManager
        self.transcodeToPNG = transcodeToPNG
    }

    /// The orb face for a project. `title` names the monogram; it defaults to the folder name.
    public func resolve(workspaceRoot: String, faviconOverride: String? = nil, iconOverride: ProjectIconOverride? = nil, title: String? = nil, now: Date = Date()) -> OrbIcon {
        let name = monogramName(title: title, workspaceRoot: workspaceRoot)
        switch iconOverride {
        case let .monogram(text, color)?:
            return .monogram(text, color: ProjectMonogram.hex(forColorName: color))
        case let .emoji(emoji)?:
            return .monogram(emoji, color: "#3f3f46")
        case let .lucide(_, color)?:
            return .monogram(ProjectMonogram.text(for: name), color: ProjectMonogram.hex(forColorName: color))
        case nil:
            break
        }

        let key = "\(faviconOverride ?? "")\u{0}\(workspaceRoot)\u{0}\(name)"
        lock.lock()
        let cached = cache[key]
        lock.unlock()
        if let cached, isFresh(cached, now: now) { return cached.icon }

        let path = iconPath(workspaceRoot: workspaceRoot, faviconOverride: faviconOverride)
        let icon = path.flatMap { imageIcon(path: $0) } ?? ProjectMonogram.icon(for: name)
        let entry = Entry(path: path, modified: path.flatMap(modificationDate), icon: icon, resolvedAt: now)
        lock.lock()
        cache[key] = entry
        lock.unlock()
        return icon
    }

    /// The absolute path of the project's icon file, or nil when T3 would show a monogram.
    public func iconPath(workspaceRoot: String, faviconOverride: String? = nil) -> String? {
        let root = URL(fileURLWithPath: workspaceRoot).standardizedFileURL.path
        guard isDirectory(root) else { return nil }
        if let faviconOverride, !faviconOverride.isEmpty {
            let candidate = faviconOverride.hasPrefix("/") ? faviconOverride : within(root, faviconOverride)
            if let candidate, isFile(candidate) { return candidate }
        }
        if let iconPath = projectFileIconPath(root: root), let candidate = within(root, iconPath), isFile(candidate) {
            return candidate
        }
        for relative in Self.faviconCandidates {
            if let candidate = within(root, relative), isFile(candidate) { return candidate }
        }
        for sourceFile in Self.iconSourceFiles {
            guard let sourcePath = within(root, sourceFile),
                  let source = try? String(contentsOfFile: sourcePath, encoding: .utf8),
                  let href = Self.extractIconHref(source) else { continue }
            let clean = href.hasPrefix("/") ? String(href.dropFirst()) : href
            for relative in ["public/" + clean, clean] {
                if let candidate = within(root, relative), isFile(candidate) { return candidate }
            }
        }
        return nil
    }

    /// The icon href from an HTML `<link rel="icon">`, or from a route file's `{ rel: "icon", href: ... }`.
    public static func extractIconHref(_ source: String) -> String? {
        let range = NSRange(source.startIndex..., in: source)
        if let match = linkIconHTML.firstMatch(in: source, range: range),
           let hrefRange = Range(match.range(at: 1), in: source) {
            return String(source[hrefRange])
        }
        for run in source.components(separatedBy: "}") {
            let runRange = NSRange(run.startIndex..., in: run)
            guard iconRel.firstMatch(in: run, range: runRange) != nil,
                  let match = iconHref.firstMatch(in: run, range: runRange),
                  let hrefRange = Range(match.range(at: 1), in: run) else { continue }
            return String(run[hrefRange])
        }
        return nil
    }

    /// `data:` URL for an icon file; nil for unknown types, unreadable or oversized files.
    public func dataURL(forFile path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        var mime = Self.mimeTypes[ext]
        var data: Data?
        if ext == "icns" {
            data = transcodeToPNG?(url)
            mime = "image/png"
        } else if mime != nil {
            let size = (try? fileManager.attributesOfItem(atPath: path)[.size] as? NSNumber)?.intValue ?? Int.max
            if size <= Self.maxImageBytes { data = fileManager.contents(atPath: path) }
        }
        guard let mime, let data, !data.isEmpty, data.count <= Self.maxImageBytes else { return nil }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    // MARK: Helpers

    private static let mimeTypes = [
        "svg": "image/svg+xml", "ico": "image/x-icon", "png": "image/png", "webp": "image/webp",
        "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif"
    ]

    // T3's LINK_ICON_HTML_RE, ICON_REL_RE and ICON_HREF_RE.
    private static let linkIconHTML = try! NSRegularExpression(
        pattern: #"<link\b(?=[^>]*\brel=["'](?:icon|shortcut icon)["'])(?=[^>]*\bhref=["']([^"'?]+))[^>]*>"#,
        options: [.caseInsensitive])
    private static let iconRel = try! NSRegularExpression(pattern: #"\brel\s*:\s*["'](?:icon|shortcut icon)["']"#, options: [.caseInsensitive])
    private static let iconHref = try! NSRegularExpression(pattern: #"\bhref\s*:\s*["']([^"'?]+)"#, options: [.caseInsensitive])

    private func isFresh(_ entry: Entry, now: Date) -> Bool {
        let age = now.timeIntervalSince(entry.resolvedAt)
        guard let path = entry.path else { return age >= 0 && age < Self.negativeTTL }
        return age >= 0 && age < Self.positiveTTL && modificationDate(path) == entry.modified
    }

    private func imageIcon(path: String) -> OrbIcon? {
        dataURL(forFile: path).map { OrbIcon.image(dataURL: $0) }
    }

    private func monogramName(title: String?, workspaceRoot: String) -> String {
        if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty { return title }
        return URL(fileURLWithPath: workspaceRoot).lastPathComponent
    }

    private func projectFileIconPath(root: String) -> String? {
        guard let data = fileManager.contents(atPath: (root as NSString).appendingPathComponent(Self.projectFileName)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let iconPath = (object["iconPath"] as? String)?.trimmingCharacters(in: .whitespaces),
              !iconPath.isEmpty else { return nil }
        return iconPath
    }

    /// `relative` resolved inside `root`; nil when it is absolute or escapes the root.
    private func within(_ root: String, _ relative: String) -> String? {
        let trimmed = relative.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/") else { return nil }
        let resolved = URL(fileURLWithPath: root).appendingPathComponent(trimmed).standardizedFileURL.path
        guard resolved.hasPrefix(root + "/") else { return nil }
        return resolved
    }

    private func isFile(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &directory) && !directory.boolValue
    }

    private func isDirectory(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
    }

    private func modificationDate(_ path: String) -> Date? {
        (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}
