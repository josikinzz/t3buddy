import Foundation
import LocalModelWidgetPanel
import ModelWidgetCore

extension ModelWidgetChecks {
    static func localModelCardChecks(_ suite: inout CheckSuite) async {
        suite.check("local model card with no model says No model loaded and offers no Unload") {
            let card = LocalModelCardPresentation.make(activeModel: nil, isBusy: false)

            try expectEqual(card.line, "No model loaded")
            try expectEqual(card.loaded, nil)
            try expectEqual(card.unloadButton, nil)
        }

        suite.check("local model card with a loaded model shows its name, host and Unload") {
            let card = LocalModelCardPresentation.make(
                activeModel: LocalModelIdentity(providerID: "ollama", name: "qwen3:8b"),
                isBusy: false
            )

            try expectEqual(card.line, "qwen3:8b · Ollama")
            try expectEqual(card.loaded, .init(name: "qwen3:8b", hostName: "Ollama"))
            try expectEqual(card.unloadButton?.title, "Unload")
            try expectEqual(card.unloadButton?.isEnabled, true)
            try expectEqual(card.unloadButton?.accessibilityLabel, "Unload qwen3:8b from Ollama")
        }

        suite.check("local model card names every host") {
            let hosts = ["bonsai", "magnitude", "ollama", "someday"].map { providerID in
                LocalModelCardPresentation.make(
                    activeModel: LocalModelIdentity(providerID: providerID, name: "m"),
                    isBusy: false
                ).loaded?.hostName
            }

            try expectEqual(hosts, ["Bonsai", "Magnitude", "Ollama", "someday"])
        }

        suite.check("local model card keeps Unload visible but disabled while busy") {
            let card = LocalModelCardPresentation.make(
                activeModel: LocalModelIdentity(providerID: "bonsai", name: "bonsai-8b"),
                isBusy: true
            )

            try expectEqual(card.line, "bonsai-8b · Bonsai")
            try expectEqual(card.unloadButton?.isEnabled, false)
        }

        await suite.check("local model card empties after Unload within one refresh, on the loaded host only") { @MainActor in
            let ollama = MockModelProvider(id: "ollama", installed: [model("alpha")], loaded: [])
            let bonsai = MockModelProvider(
                id: "bonsai",
                installed: [model("bonsai-8b", providerID: "bonsai")],
                loaded: [loaded("bonsai-8b", providerID: "bonsai")]
            )
            let viewModel = WidgetViewModel(providers: [ollama, bonsai])
            await viewModel.refresh()

            let before = DesktopPanelPresentation.make(from: viewModel).card
            try expectEqual(before.line, "bonsai-8b · Bonsai")
            try expect(before.unloadButton != nil, "Expected Unload while a model is loaded")

            await viewModel.unloadActiveModel()

            let after = DesktopPanelPresentation.make(from: viewModel).card
            try expectEqual(after.line, "No model loaded")
            try expectEqual(after.unloadButton, nil)
            try expectEqual(bonsai.events, [.unload("bonsai-8b")])
            try expectEqual(ollama.events, [])
        }

        await suite.check("local model panel never shows memory byte text") { @MainActor in
            let provider = MockModelProvider(installed: [model("alpha")], loaded: [loaded("alpha")])
            let viewModel = WidgetViewModel(providers: [provider])

            let beforeRefresh = DesktopPanelPresentation.make(from: viewModel)
            await viewModel.refresh()
            let afterRefresh = DesktopPanelPresentation.make(from: viewModel)

            for presentation in [beforeRefresh, afterRefresh] {
                for text in allStrings(in: presentation) {
                    for forbidden in ["Zero KB", "byte", "0%"] {
                        try expect(
                            text.contains(forbidden) == false,
                            "Local model panel produced \(text.debugDescription)"
                        )
                    }
                }
            }
        }

        await suite.check("process panel shows no memory byte text before its first sample") { @MainActor in
            await Task.yield()
            let viewModel = ProcessHUDViewModel(
                processSampler: FixedProcessSampler(processes: []),
                memorySampler: FixedMemorySampler(snapshot: .init(totalBytes: 100, usedBytes: 42)),
                terminator: MockProcessTerminator(),
                currentProcessID: 999
            )

            let presentation = ProcessPanelPresentation.make(from: viewModel)

            try expectEqual(presentation.memory.summary, "")
            for text in allStrings(in: presentation) {
                try expect(text.contains("Zero KB") == false, "Process panel produced \(text.debugDescription)")
            }
        }
    }

    /// Every string reachable from a value, so a check can prove a text is never produced.
    private static func allStrings(in value: Any) -> [String] {
        if let string = value as? String {
            return [string]
        }
        return Mirror(reflecting: value).children.flatMap { allStrings(in: $0.value) }
    }
}
