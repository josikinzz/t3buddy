import Foundation

/// Display names for rows in the process memory card.
public enum ProcessLabel {
    /// Interpreters and agent CLIs whose own name says nothing about the work they do.
    /// Matched case-insensitively after trailing version digits are dropped (`python3.12` → `python`).
    static let genericNames: Set<String> = [
        "node", "nodejs", "bun", "deno", "tsx", "npm", "npx", "pnpm", "yarn",
        "python", "uv", "uvx", "ruby", "perl", "php", "java", "go",
        "bash", "zsh", "sh", "fish",
        "codex", "claude", "gemini", "opencode", "aider", "goose", "amp", "cursor-agent", "grok", "kimi", "qwen"
    ]

    /// `name · project` for a generic process whose working directory names a project, otherwise `name`.
    public static func label(
        name: String,
        cwd: String?,
        homeDirectory: String = NSHomeDirectory()
    ) -> String {
        guard isGeneric(name), let project = projectName(cwd: cwd, homeDirectory: homeDirectory) else {
            return name
        }
        return "\(name) · \(project)"
    }

    /// The name to show for a process before any project is added.
    /// Version-installed binaries such as `~/.local/share/claude/versions/2.1.296`
    /// report the version as their name; the tool folder names them instead.
    public static func processName(name: String, executablePath: String?) -> String {
        guard let executablePath, name.first?.isNumber == true else {
            return name
        }
        let components = URL(fileURLWithPath: executablePath).pathComponents
        guard components.count >= 3,
              components[components.count - 1] == name,
              components[components.count - 2] == "versions"
        else {
            return name
        }
        return components[components.count - 3]
    }

    static func isGeneric(_ name: String) -> Bool {
        var base = name.lowercased()
        while let last = base.last, last.isNumber || last == "." {
            base.removeLast()
        }
        return genericNames.contains(base)
    }

    private static func projectName(cwd: String?, homeDirectory: String) -> String? {
        guard let cwd else { return nil }
        let directory = trimmingTrailingSlashes(cwd)
        guard directory.isEmpty == false,
              directory != trimmingTrailingSlashes(homeDirectory)
        else {
            return nil
        }
        let project = URL(fileURLWithPath: directory).lastPathComponent
        return project.isEmpty || project == "/" ? nil : project
    }

    private static func trimmingTrailingSlashes(_ path: String) -> String {
        var trimmed = path
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }
}
