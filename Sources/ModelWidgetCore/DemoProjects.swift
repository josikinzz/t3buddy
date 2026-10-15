import Foundation

/// The owner's real projects for T3boii's demo (`Resources/Pet/demo.js`): T3's registered
/// projects, then the git folders in `~/Projects`, each face resolved exactly as for a live
/// thread (`ProjectIconResolver`). Image faces come first so the orbit looks varied; projects
/// sharing a face (worktree copies of one repo) count once.
public enum DemoProjects {
    /// `notifyutil -p local.codex.LocalModelWidget.demo` (scripts/demo.sh) starts the demo.
    public static let notificationName = "local.codex.LocalModelWidget.demo"
    /// `scripts/demo.sh limit [provider]`: a made-up rate limit for one provider on the real orbit
    /// (`window.t3boii.debug.limit`). A Darwin notification carries no payload, so each provider has
    /// its own name, `<notificationName>.limit.<provider>`; the bare `.limit` lets the page pick.
    public static let limitNotificationName = notificationName + ".limit"
    public static let limitProviders = ["codex", "claudeAgent", "cursor", "grok", "grokBot", "kimi", "opencode", "pi", "antigravity"]
    public static let maxProjects = 12

    public struct Entry: Encodable, Equatable, Sendable {
        public var title: String
        public var icon: OrbIcon
    }

    struct Payload: Encodable {
        var projects: [Entry]
        var grok: OrbIcon
    }

    public static func entries(t3Projects: [T3Project], projectsFolder: URL?, icons: ProjectIconResolver, fileManager: FileManager = .default) -> [Entry] {
        var candidates = t3Projects.map { (title: $0.title, root: $0.workspaceRoot, favicon: $0.faviconPath, override: $0.projectIcon) }
        if let folder = projectsFolder, let names = try? fileManager.contentsOfDirectory(atPath: folder.path) {
            for name in names.sorted() where !name.hasPrefix(".") {
                let root = folder.appendingPathComponent(name).path
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue,
                      fileManager.fileExists(atPath: root + "/.git") else { continue }
                candidates.append((title: name, root: root, favicon: nil, override: nil))
            }
        }
        var images: [Entry] = [], monograms: [Entry] = []
        // Not projects: the home folder, the projects folder itself, and T3's scratch space.
        let home = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path
        var seenRoots: Set<String> = [home, projectsFolder?.standardizedFileURL.path ?? home]
        var seenTitles = Set<String>(), seenFaces = Set<String>()
        for candidate in candidates {
            let root = URL(fileURLWithPath: candidate.root).standardizedFileURL.path
            guard !root.hasPrefix(home + "/.t3/"), seenRoots.insert(root).inserted, seenTitles.insert(candidate.title.lowercased()).inserted else { continue }
            let icon = icons.resolve(workspaceRoot: root, faviconOverride: candidate.favicon, iconOverride: candidate.override, title: candidate.title)
            let face = icon.kind == .image ? (icon.src ?? "") : "\(icon.text ?? "")|\(icon.color ?? "")"
            guard seenFaces.insert(face).inserted else { continue }
            let entry = Entry(title: candidate.title, icon: icon)
            if icon.kind == .image { images.append(entry) } else { monograms.append(entry) }
        }
        return Array((images + monograms).prefix(maxProjects))
    }

    /// The JSON `window.t3boii.demo(payload)` takes: `{ projects: [{ title, icon }], grok }`.
    public static func payloadJSON(_ entries: [Entry]) -> String? {
        let payload = Payload(projects: entries, grok: GrokRosterReader.inflightOrb.projectIcon)
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
