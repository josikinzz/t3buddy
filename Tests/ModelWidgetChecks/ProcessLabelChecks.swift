import Foundation
import LocalModelWidgetPanel
import ModelWidgetCore

extension ModelWidgetChecks {
    static func processLabelChecks(_ suite: inout CheckSuite) async {
        let home = "/Users/tester"

        await suite.check("process label names a generic node process by its project folder") {
            try expectEqual(
                ProcessLabel.label(name: "node", cwd: "/Users/tester/Projects/docs-site", homeDirectory: home),
                "node · docs-site"
            )
            try expectEqual(
                ProcessLabel.label(name: "node", cwd: "/Users/tester/Projects/docs-site/", homeDirectory: home),
                "node · docs-site"
            )
        }

        await suite.check("process label covers interpreters and agent CLIs, including versioned names") {
            let cwd = "/Users/tester/Projects/widgets"
            for name in ["bun", "deno", "python", "python3", "python3.12", "Python", "ruby", "java", "go", "codex", "claude", "npm", "uv"] {
                try expectEqual(ProcessLabel.label(name: name, cwd: cwd, homeDirectory: home), "\(name) · widgets")
            }
        }

        await suite.check("process label keeps the bare name when the working directory is missing or unhelpful") {
            try expectEqual(ProcessLabel.label(name: "node", cwd: nil, homeDirectory: home), "node")
            try expectEqual(ProcessLabel.label(name: "node", cwd: "", homeDirectory: home), "node")
            try expectEqual(ProcessLabel.label(name: "codex", cwd: "/", homeDirectory: home), "codex")
            try expectEqual(ProcessLabel.label(name: "codex", cwd: home, homeDirectory: home), "codex")
            try expectEqual(ProcessLabel.label(name: "codex", cwd: home + "/", homeDirectory: home), "codex")
        }

        await suite.check("process label keeps a named app's own name") {
            try expectEqual(
                ProcessLabel.label(name: "Google Chrome", cwd: "/Users/tester/Projects/widgets", homeDirectory: home),
                "Google Chrome"
            )
            try expectEqual(ProcessLabel.label(name: "Xcode", cwd: "/", homeDirectory: home), "Xcode")
            try expectEqual(ProcessLabel.label(name: "nodemon-ui", cwd: "/Users/tester/Projects/widgets", homeDirectory: home), "nodemon-ui")
        }

        await suite.check("process name resolves a version-named agent binary to its tool name") {
            try expectEqual(
                ProcessLabel.processName(name: "2.1.296", executablePath: "/Users/tester/.local/share/claude/versions/2.1.296"),
                "claude"
            )
            try expectEqual(ProcessLabel.processName(name: "node", executablePath: "/opt/homebrew/bin/node"), "node")
            try expectEqual(ProcessLabel.processName(name: "Safari", executablePath: nil), "Safari")
        }

        await suite.check("process panel rows show generic processes by project and keep app names") { @MainActor in
            let viewModel = ProcessHUDViewModel(
                processSampler: FixedProcessSampler(processes: [
                    RunningProcess(processID: 12, name: "node", workingDirectory: "/Users/tester/Projects/docs-site", residentMemoryBytes: 300_000_000),
                    RunningProcess(processID: 34, name: "Google Chrome", workingDirectory: "/Users/tester/Projects/widgets", residentMemoryBytes: 200_000_000),
                    RunningProcess(processID: 56, name: "codex", residentMemoryBytes: 100_000_000)
                ]),
                memorySampler: FixedMemorySampler(snapshot: .init(totalBytes: 1_000_000_000, usedBytes: 700_000_000)),
                terminator: MockProcessTerminator(),
                currentProcessID: 999
            )
            await viewModel.refresh()

            let presentation = ProcessPanelPresentation.make(from: viewModel)

            try expectEqual(presentation.processRows.map(\.title), ["node · docs-site", "Google Chrome", "codex"])
            try expectEqual(presentation.proportionSegments.first?.title, "node · docs-site")
            try expectEqual(presentation.processRows[0].accessibilityLabel, "node · docs-site, 30% of unified memory")
            try expectEqual(presentation.processRows[0].forceQuitButton.title, "Force Quit")
            try expectEqual(presentation.processRows[0].forceQuitButton.isEnabled, true)
        }
    }
}
