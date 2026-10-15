import AppKit

/// Locates and opens the bundled model-benchmark comparison document from the
/// widget's settings menu. Prefers the rendered HTML (nice tables in any
/// browser), then falls back to the raw Markdown. Looks inside the packaged
/// app bundle first, then the source-repo `Resources/` folder for dev runs.
enum BenchmarkDoc {
    private static let baseName = "ModelBenchmarks"

    /// Repo fallback so the menu item works when running the binary straight
    /// out of `.build` (not packaged) during development: the checkout's
    /// `Resources/`, three levels above this file (as `PetLayer` finds the pet).
    private static let repoResources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources", isDirectory: true)

    static func open() {
        guard let url = locate() else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static func locate() -> URL? {
        for ext in ["html", "md"] {
            if let bundled = Bundle.main.url(forResource: baseName, withExtension: ext) {
                return bundled
            }
            let repo = repoResources.appendingPathComponent("\(baseName).\(ext)")
            if FileManager.default.fileExists(atPath: repo.path) {
                return repo
            }
        }
        return nil
    }
}
