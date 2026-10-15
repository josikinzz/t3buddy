import AppKit
import Foundation
import LocalModelWidgetPanel
import ModelWidgetCore

@main
struct ModelWidgetChecks {
    static func main() async {
        var suite = CheckSuite()
        await suite.check("Kimi ratios convert to percentages and preserve weekly reset") {
            let data = Data(#"{"usages":{"limit_5h":{"used_ratio":0,"reset_time":"2026-10-13T22:38:57Z"},"limit_7d":{"used_ratio":0.2236,"reset_time":"2026-10-17T00:38:57Z"}}}"#.utf8)
            let parsed = try SubscriptionUsageReader.parse(data, provider: "Kimi")
            try expectEqual(parsed.windows.count, 2)
            try expect(abs(parsed.windows[1].used - 22.36) < 0.001, "Kimi ratio must become percent")
            try expect(parsed.windows[1].reset != nil, "Kimi reset must parse")
        }

        await suite.check("Kimi signed in through CLI Proxy and the Kimi CLI shows one working row") {
            func row(_ id: String, _ email: String, _ error: String?) throws -> SubscriptionUsage {
                let object: [String: Any] = ["id": id, "provider": "Kimi", "email": email, "plan": "", "windows": [Any](), "error": error ?? NSNull()]
                return try JSONDecoder().decode(SubscriptionUsage.self, from: JSONSerialization.data(withJSONObject: object))
            }
            let proxy = try row("Kimi:kimi-ai-1.json", "a@b.c", nil)
            let staleNamed = try row("Kimi:cli-named.json", "a@b.c", "Sign-in needs refresh (HTTP 401)")
            let staleAnonymous = try row("Kimi:cli.json", "Signed-in Kimi account", "Sign-in needs refresh (HTTP 401)")
            let rows = SubscriptionUsageReader.dedupe([staleNamed, staleAnonymous, proxy])
            try expectEqual(rows.count, 1)
            try expectEqual(rows[0].id, "Kimi:kimi-ai-1.json")
        }

        await suite.check("Idle hide fires once per idle stretch and respects video") {
            var policy = IdleHidePolicy(minutes: 10)
            try expectEqual(policy.evaluate(idleSeconds: 599, displayHeldBy: []), .wait)
            try expectEqual(policy.evaluate(idleSeconds: 610, displayHeldBy: ["zoom.us"]), .skip("zoom.us is keeping the display awake"))
            try expectEqual(policy.evaluate(idleSeconds: 620, displayHeldBy: ["caffeinate", "powerd"]), .hide)
            try expectEqual(policy.evaluate(idleSeconds: 900, displayHeldBy: []), .wait)
            try expectEqual(policy.evaluate(idleSeconds: 2, displayHeldBy: []), .wait)
            try expectEqual(policy.evaluate(idleSeconds: 600, displayHeldBy: []), .hide)
            var off = IdleHidePolicy(minutes: 0)
            try expectEqual(off.evaluate(idleSeconds: 100_000, displayHeldBy: []), .wait)
        }

        await suite.check("Codex labels weekly primary windows by duration and preserves reset epochs") {
            let data = Data(#"{"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":84,"limit_window_seconds":604800,"reset_at":1792472291},"secondary_window":null}}"#.utf8)
            let parsed = try SubscriptionUsageReader.parse(data, provider: "Codex")
            try expectEqual(parsed.windows.count, 1)
            try expectEqual(parsed.windows[0].title, "Weekly")
            try expectEqual(parsed.windows[0].used, 84)
            try expectEqual(parsed.windows[0].reset?.timeIntervalSince1970, 1792472291)
        }
        await suite.check("Claude preserves inactive short limits and fractional weekly reset dates") {
            let data = Data(#"{"five_hour":{"utilization":0,"resets_at":null},"seven_day":{"utilization":100,"resets_at":"2026-10-15T18:00:00.296927Z"},"seven_day_sonnet":null}"#.utf8)
            let parsed = try SubscriptionUsageReader.parse(data, provider: "Claude")
            try expectEqual(parsed.windows.count, 2)
            try expect(parsed.windows[0].reset == nil, "Inactive limit must not invent a reset")
            try expect(parsed.windows[1].reset != nil, "Fractional reset must parse")
        }


        await suite.check("session activate unloads loaded models across hosts before loading target") { @MainActor in
            let ollama = MockModelProvider(
                id: "ollama",
                installed: [
                    model("alpha"),
                    model("beta")
                ],
                loaded: [
                    loaded("alpha")
                ]
            )
            let lmStudio = MockModelProvider(
                id: "lmstudio",
                installed: [
                    model("beta", providerID: "lmstudio")
                ],
                loaded: [
                    loaded("gamma", providerID: "lmstudio")
                ]
            )
            let session = LocalModelSession(providers: [ollama, lmStudio])

            let result = try await session.activateModel(
                with: LocalModelIdentity(providerID: "lmstudio", name: "beta")
            )

            try expect(result.didRun, "Expected session activation to run")
            try expectEqual(ollama.events, [
                .unload("alpha")
            ])
            try expectEqual(lmStudio.events, [
                .unload("gamma"),
                .load("beta")
            ])
            try expectEqual(result.state.activeModelID, LocalModelIdentity(providerID: "lmstudio", name: "beta"))
        }

        await suite.check("session refresh collapses external multi-load to newest expiry") { @MainActor in
            let old = Date(timeIntervalSince1970: 100)
            let newest = Date(timeIntervalSince1970: 200)
            let ollama = MockModelProvider(
                id: "ollama",
                installed: [
                    model("alpha")
                ],
                loaded: [
                    loaded("alpha", expiresAt: old)
                ]
            )
            let lmStudio = MockModelProvider(
                id: "lmstudio",
                installed: [
                    model("beta", providerID: "lmstudio"),
                    model("gamma", providerID: "lmstudio")
                ],
                loaded: [
                    loaded("beta", providerID: "lmstudio", expiresAt: newest),
                    loaded("gamma", providerID: "lmstudio", expiresAt: nil)
                ]
            )
            let session = LocalModelSession(providers: [ollama, lmStudio])

            let state = try await session.refresh()

            try expectEqual(state.activeModelID, LocalModelIdentity(providerID: "lmstudio", name: "beta"))
            try expectEqual(state.activeLoadedModel?.name, "beta")
            try expectEqual(state.models.map(\.identity), [
                LocalModelIdentity(providerID: "lmstudio", name: "beta"),
                LocalModelIdentity(providerID: "ollama", name: "alpha"),
                LocalModelIdentity(providerID: "lmstudio", name: "gamma")
            ])
            try expectEqual(ollama.events, [
                .unload("alpha")
            ])
            try expectEqual(lmStudio.events, [
                .unload("gamma")
            ])
        }

        await suite.check("session uses provider id when returned model identity disagrees") { @MainActor in
            let provider = MockModelProvider(
                id: "ollama",
                installed: [
                    model("alpha", providerID: "wrong")
                ],
                loaded: [
                    loaded("alpha", providerID: "wrong", sizeBytes: 987)
                ]
            )
            let session = LocalModelSession(providers: [provider])

            let state = try await session.refresh()

            try expectEqual(state.activeModelID, LocalModelIdentity(providerID: "ollama", name: "alpha"))
            try expectEqual(state.models.first?.providerID, "ollama")
            try expectEqual(state.models.first?.isLoaded, true)
            try expectEqual(state.models.first?.loadedSizeBytes, 987)
        }

        await suite.check("refresh marks externally loaded Ollama model active and first") { @MainActor in
            let provider = MockModelProvider(
                installed: [
                    model("alpha"),
                    model("beta")
                ],
                loaded: [
                    loaded("beta", sizeBytes: 987)
                ]
            )
            let viewModel = WidgetViewModel(
                providers: [provider],
                memorySampler: FixedMemorySampler(snapshot: .init(totalBytes: 100, usedBytes: 42))
            )

            await viewModel.refresh()

            try expectEqual(viewModel.activeModelID, LocalModelIdentity(providerID: "ollama", name: "beta"))
            try expectEqual(viewModel.models.map(\.name), ["beta", "alpha"])
            try expectEqual(viewModel.models.map(\.isLoaded), [true, false])
            try expectClose(viewModel.memory.usedFraction, 0.42)
        }

        await suite.check("refresh preserves installed order when no model is active") { @MainActor in
            let provider = MockModelProvider(
                installed: [
                    model("alpha"),
                    model("beta"),
                    model("gamma")
                ],
                loaded: []
            )
            let viewModel = WidgetViewModel(
                providers: [provider],
                memorySampler: FixedMemorySampler(snapshot: .init(totalBytes: 100, usedBytes: 42))
            )

            await viewModel.refresh()

            try expectEqual(viewModel.activeModelID, nil)
            try expectEqual(viewModel.models.map(\.name), ["alpha", "beta", "gamma"])
        }

        await suite.check("activate uses local model session and refreshes state") { @MainActor in
            let provider = MockModelProvider(
                installed: [
                    model("alpha"),
                    model("beta")
                ],
                loaded: [
                    loaded("alpha")
                ]
            )
            let viewModel = WidgetViewModel(
                providers: [provider],
                memorySampler: FixedMemorySampler(snapshot: .init(totalBytes: 10, usedBytes: 5))
            )

            await viewModel.activate(model("beta"))

            try expectEqual(provider.events, [
                .unload("alpha"),
                .load("beta")
            ])
            try expect(viewModel.isBusy == false, "Expected activate to finish with isBusy false")
            try expectEqual(viewModel.pendingModelID, Optional<LocalModelIdentity>.none)
            try expectEqual(viewModel.statusText, "Loaded beta")
        }

        await suite.check("activate ignores already loaded model") { @MainActor in
            let provider = MockModelProvider(
                installed: [
                    model("alpha")
                ],
                loaded: [
                    loaded("alpha")
                ]
            )
            let viewModel = WidgetViewModel(
                providers: [provider],
                memorySampler: FixedMemorySampler(snapshot: .init(totalBytes: 10, usedBytes: 5))
            )
            await viewModel.refresh()

            await viewModel.activate(model("alpha"))

            try expectEqual(provider.events, [])
            try expectEqual(viewModel.statusText, "Loaded alpha")
        }

        await suite.check("busy view model ignores overlapping activation") { @MainActor in
            let provider = BlockingMockModelProvider(
                installed: [
                    model("alpha"),
                    model("beta")
                ],
                loaded: []
            )
            let viewModel = WidgetViewModel(
                providers: [provider],
                memorySampler: FixedMemorySampler(snapshot: .init(totalBytes: 10, usedBytes: 5))
            )

            let firstActivation = Task { await viewModel.activate(model("alpha")) }
            await provider.waitUntilLoadAttempted()
            try expectEqual(viewModel.pendingModelID, LocalModelIdentity(providerID: "ollama", name: "alpha"))
            await viewModel.activate(model("beta"))
            provider.finishLoad()
            await firstActivation.value

            try expectEqual(provider.events, [
                .load("alpha")
            ])
            try expect(viewModel.isBusy == false, "Expected first activation to reset busy flag")
        }

        suite.check("desktop panel layout owns the card width and leaves height to each card") {
            try expectEqual(DesktopPanelLayout.panelWidth, 332)
            try expectEqual(DesktopPanelLayout.panelWidth, DashboardLayout.columnWidth)
        }

        suite.check("desktop panel window modes map to AppKit policy") {
            try expectEqual(DesktopPanelWindowMode.desktop.title, "Desktop")
            try expectEqual(DesktopPanelWindowMode.floating.title, "Float")
            try expect(DesktopPanelWindowMode.desktop.collectionBehavior.contains(.stationary), "Expected desktop mode to be stationary")
            try expect(DesktopPanelWindowMode.floating.collectionBehavior.contains(.stationary) == false, "Expected floating mode to move with windows")
            try expectEqual(DesktopPanelWindowMode.floating.windowLevel, .floating)
        }

        await suite.check("desktop panel presentation maps initial state") { @MainActor in
            await Task.yield()
            let viewModel = WidgetViewModel(
                providers: [
                    MockModelProvider(installed: [], loaded: [])
                ],
                memorySampler: FixedMemorySampler(snapshot: .init(totalBytes: 100, usedBytes: 42))
            )

            let presentation = DesktopPanelPresentation.make(from: viewModel)

            try expectEqual(presentation.title, "Local Models")
            try expectEqual(presentation.card.line, "No model loaded")
            try expectEqual(presentation.card.unloadButton, nil)
            try expectEqual(presentation.statusText, "Idle")
            try expectEqual(presentation.quitButton.isEnabled, true)
        }

        await suite.check("desktop panel presentation offers no Unload while a model is loading") { @MainActor in
            let provider = BlockingMockModelProvider(
                installed: [
                    model("alpha"),
                    model("beta", sizeBytes: 2_000_000)
                ],
                loaded: []
            )
            let viewModel = WidgetViewModel(
                providers: [provider],
                memorySampler: FixedMemorySampler(snapshot: .init(totalBytes: 10, usedBytes: 5))
            )
            await viewModel.refresh()

            let firstActivation = Task { await viewModel.activate(model("alpha")) }
            await provider.waitUntilLoadAttempted()

            let presentation = DesktopPanelPresentation.make(from: viewModel)

            try expectEqual(presentation.card.line, "No model loaded")
            try expectEqual(presentation.card.unloadButton, nil)

            provider.finishLoad()
            await firstActivation.value
        }

        await suite.check("process panel presentation ranks memory consumers and maps color segments") { @MainActor in
            let viewModel = ProcessHUDViewModel(
                processSampler: FixedProcessSampler(processes: [
                    process(pid: 12, name: "Safari", residentMemoryBytes: 200_000_000),
                    process(pid: 34, name: "Xcode", residentMemoryBytes: 300_000_000),
                    process(pid: 56, name: "Finder", residentMemoryBytes: 25_000_000)
                ]),
                memorySampler: FixedMemorySampler(snapshot: .init(totalBytes: 1_000_000_000, usedBytes: 700_000_000)),
                terminator: MockProcessTerminator(),
                currentProcessID: 999
            )
            await viewModel.refresh()

            let presentation = ProcessPanelPresentation.make(from: viewModel)

            try expectEqual(presentation.title, "Process Memory")
            try expectEqual(presentation.processRows.map(\.title), ["Xcode", "Safari", "Finder"])
            try expectEqual(presentation.processRows.map(\.colorIndex), [0, 1, 2])
            try expectEqual(presentation.proportionSegments.map(\.title), ["Xcode", "Safari", "Finder", "Other used"])
            try expectEqual(presentation.proportionSegments.map(\.colorIndex), [0, 1, 2, nil])
            try expectClose(presentation.proportionSegments[0].fraction, 0.30)
            try expectClose(presentation.proportionSegments[1].fraction, 0.20)
            try expectClose(presentation.proportionSegments[2].fraction, 0.025)
            try expectClose(presentation.proportionSegments[3].fraction, 0.175)
            try expectEqual(presentation.processRows[0].forceQuitButton.title, "Force Quit")
            try expectEqual(presentation.processRows[0].accessibilityLabel, "Xcode, 30% of unified memory")
        }

        await suite.check("process hud force quit calls terminator and protects its own process") { @MainActor in
            let terminator = MockProcessTerminator()
            let viewModel = ProcessHUDViewModel(
                processSampler: FixedProcessSampler(processes: [
                    process(pid: 34, name: "Xcode", residentMemoryBytes: 300_000_000),
                    process(pid: 999, name: "Local Model Widget", residentMemoryBytes: 50_000_000)
                ]),
                memorySampler: FixedMemorySampler(snapshot: .init(totalBytes: 1_000_000_000, usedBytes: 700_000_000)),
                terminator: terminator,
                currentProcessID: 999
            )
            await viewModel.refresh()

            await viewModel.forceQuit(processID: 34)
            try expectEqual(terminator.terminatedProcessIDs, [34])
            try expectEqual(viewModel.statusText, "Force quit requested for Xcode")

            await viewModel.forceQuit(processID: 999)
            try expectEqual(terminator.terminatedProcessIDs, [34])
            try expectEqual(viewModel.statusText, "The widget cannot force quit itself.")
        }

        await suite.check("installedModels fetches and maps Ollama tags through provider interface") {
            let client = makeOllamaClient(stubs: [
                "/api/tags": .json("""
            {
              "models": [
                {
                  "name": "qwen3-coder:30b",
                  "model": "qwen3-coder:30b",
                  "size": 18556700761,
                  "details": {
                    "family": "qwen3moe",
                    "parameter_size": "30.5B",
                    "quantization_level": "Q4_K_M"
                  }
                }
              ]
            }
            """)
            ])

            let models = try await client.installedModels()

            try expectEqual(models, [
                LocalModel(
                    providerID: "ollama",
                    name: "qwen3-coder:30b",
                    sizeBytes: 18_556_700_761,
                    family: "qwen3moe",
                    parameterSize: "30.5B",
                    quantization: "Q4_K_M"
                )
            ])
            try expectEqual(OllamaURLProtocol.capturedRequests.map(\.path), ["/api/tags"])
        }

        await suite.check("loadedModels fetches and maps Ollama ps response through provider interface") {
            let client = makeOllamaClient(stubs: [
                "/api/ps": .json("""
            {
              "models": [
                {
                  "name": "gemma4:latest",
                  "model": "gemma4:latest",
                  "size": 9608350718,
                  "size_vram": 7453659136,
                  "processor": "100% GPU",
                  "expires_at": "2026-06-28T03:08:00.000000000Z"
                }
              ]
            }
            """)
            ])

            let models = try await client.loadedModels()

            try expectEqual(models.count, 1)
            try expectEqual(models[0].name, "gemma4:latest")
            try expectEqual(models[0].sizeBytes, 7_453_659_136)
            try expectEqual(models[0].processor, "100% GPU")
            try expect(models[0].expiresAt != nil, "Expected Ollama date to decode")
            try expectEqual(OllamaURLProtocol.capturedRequests.map(\.path), ["/api/ps"])
        }

        await suite.check("load and unload post Ollama generate keep_alive contract through provider interface") {
            let client = makeOllamaClient(stubs: [
                "/api/generate": .json("{}")
            ])

            try await client.loadModel(named: "gemma4:latest")
            try await client.unloadModel(named: "gemma4:latest")

            try expectEqual(OllamaURLProtocol.capturedRequests.map(\.method), ["POST", "POST"])
            try expectEqual(OllamaURLProtocol.capturedRequests.map(\.path), ["/api/generate", "/api/generate"])
            let bodies = try OllamaURLProtocol.capturedRequests.map { try jsonDictionary($0.body) }

            try expectEqual(bodies[0]["model"] as? String, "gemma4:latest")
            try expectEqual(bodies[0]["prompt"] as? String, "")
            try expectEqual(bodies[0]["stream"] as? Bool, false)
            try expectEqual(bodies[0]["keep_alive"] as? String, "1h")
            try expectEqual(bodies[1]["keep_alive"] as? String, "0")
        }

        await suite.check("Ollama provider methods throw http status errors") {
            let client = makeOllamaClient(stubs: [
                "/api/tags": .json("{}", statusCode: 503)
            ])

            do {
                _ = try await client.installedModels()
                throw CheckFailure.message("Expected HTTP status error")
            } catch let error as OllamaError {
                try expectEqual(error, .httpStatus(503))
            }
        }

        suite.check("system memory excludes reclaimable cache from used memory") {
            let gib: UInt64 = 1024 * 1024 * 1024
            let usedBytes = SystemMemorySampler.activityMonitorUsedBytes(
                totalBytes: 64 * gib,
                pageSize: 16 * 1024,
                internalPages: 500_000,
                wiredPages: 2_000_000,
                compressorPages: 45_000
            )

            try expectEqual(usedBytes, 41_697_280_000)
            try expectClose(Double(usedBytes) / Double(64 * gib), 0.6068, accuracy: 0.0001)
        }

        suite.check("system memory used bytes are clamped to physical memory") {
            let usedBytes = SystemMemorySampler.activityMonitorUsedBytes(
                totalBytes: 100,
                pageSize: 10,
                internalPages: 8,
                wiredPages: 8,
                compressorPages: 8
            )

            try expectEqual(usedBytes, 100)
        }

        suite.check("memory progress is clamped") {
            try expectClose(MemorySnapshot(totalBytes: 100, usedBytes: 42).usedFraction, 0.42)
            try expectEqual(MemorySnapshot(totalBytes: 0, usedBytes: 42).usedFraction, 0)
            try expectEqual(MemorySnapshot(totalBytes: 100, usedBytes: 120).usedFraction, 1)
        }

        suite.check("system process sampler includes the current process") {
            let processes = try SystemProcessSampler().sample()
            let currentProcessID = ProcessInfo.processInfo.processIdentifier
            guard let currentProcess = processes.first(where: { $0.processID == currentProcessID }) else {
                throw CheckFailure.message("Expected sampler to include PID \(currentProcessID)")
            }

            try expect(currentProcess.name.isEmpty == false, "Expected current process to have a name")
            try expect(currentProcess.residentMemoryBytes > 0, "Expected current process to report resident memory")
        }

        suite.check("magnitude status table parses rows by header columns") {
            let rows = MagnitudeStatusTable.parse("""
            Local models

            MODEL             MEMORY   CONTEXT  STATUS     MODEL ID
            Qwen3.8 27B (Q8)  36.9 GB  100K     Ready      qwen3.8-27b:gguf:q8
            Gemma 4 E2B (Q4)  4.7 GB   64K      Installed  gemma-4-e2b-it-qat:gguf:q4

            """)

            try expectEqual(rows, [
                MagnitudeStatusRow(modelID: "qwen3.8-27b:gguf:q8", memoryBytes: 36_900_000_000, quantization: "Q8", isReady: true),
                MagnitudeStatusRow(modelID: "gemma-4-e2b-it-qat:gguf:q4", memoryBytes: 4_700_000_000, quantization: "Q4", isReady: false)
            ])
            try expectEqual(MagnitudeStatusTable.parse("Local models\n\nNo models installed.\n"), [])
        }

        await suite.check("session treats an unreachable host as having no models") { @MainActor in
            let offline = UnreachableModelProvider(id: "ollama")
            let online = MockModelProvider(
                id: "bonsai",
                installed: [model("alpha", providerID: "bonsai")],
                loaded: [loaded("alpha", providerID: "bonsai")]
            )
            let session = LocalModelSession(providers: [offline, online])

            let state = try await session.refresh()

            try expectEqual(state.models.map(\.name), ["alpha"])
            try expectEqual(state.activeModelID, LocalModelIdentity(providerID: "bonsai", name: "alpha"))
        }

        await processLabelChecks(&suite)
        await idleHideEvidenceChecks(&suite)
        await usageOrderChecks(&suite)
        await localModelCardChecks(&suite)
        await masonryChecks(&suite)
        await tokenUsageChecks(&suite)
        await petLayerChecks(&suite)
        await orbitChecks(&suite)
        await grokRosterChecks(&suite)
        await reviewFixChecks(&suite)
        await orbitStateChecks(&suite)
        await providerLimitChecks(&suite)
        await petMotionChecks(&suite)
        suite.finish()
    }
}

struct CheckSuite {
    private(set) var failures = 0

    mutating func check(_ name: String, _ body: () throws -> Void) {
        do {
            try body()
            print("PASS \(name)")
        } catch {
            failures += 1
            print("FAIL \(name): \(error)")
        }
    }

    mutating func check(_ name: String, _ body: () async throws -> Void) async {
        do {
            try await body()
            print("PASS \(name)")
        } catch {
            failures += 1
            print("FAIL \(name): \(error)")
        }
    }

    func finish() -> Never {
        if failures == 0 {
            print("All checks passed.")
            exit(0)
        } else {
            print("\(failures) check(s) failed.")
            exit(1)
        }
    }
}

enum CheckFailure: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case let .message(message):
            return message
        }
    }
}

func expect(_ condition: Bool, _ message: String) throws {
    if condition == false {
        throw CheckFailure.message(message)
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T) throws {
    if actual != expected {
        throw CheckFailure.message("Expected \(expected), got \(actual)")
    }
}

func expectClose(_ actual: Double, _ expected: Double, accuracy: Double = 0.001) throws {
    if abs(actual - expected) > accuracy {
        throw CheckFailure.message("Expected \(expected), got \(actual)")
    }
}

struct OllamaStubResponse {
    let statusCode: Int
    let data: Data

    static func json(_ value: String, statusCode: Int = 200) -> OllamaStubResponse {
        OllamaStubResponse(statusCode: statusCode, data: value.data(using: .utf8)!)
    }
}

struct OllamaCapturedRequest {
    let method: String
    let path: String
    let body: Data?
}

final class OllamaURLProtocol: URLProtocol {
    static var stubs: [String: OllamaStubResponse] = [:]
    static var capturedRequests: [OllamaCapturedRequest] = []

    static func reset(stubs: [String: OllamaStubResponse]) {
        self.stubs = stubs
        capturedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.capturedRequests.append(
            OllamaCapturedRequest(
                method: request.httpMethod ?? "GET",
                path: path,
                body: Self.bodyData(for: request)
            )
        )

        guard let url = request.url, let stub = Self.stubs[path] else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func bodyData(for request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}

func makeOllamaClient(stubs: [String: OllamaStubResponse]) -> OllamaClient {
    OllamaURLProtocol.reset(stubs: stubs)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OllamaURLProtocol.self]
    let session = URLSession(configuration: configuration)
    return OllamaClient(baseURL: URL(string: "http://ollama.test")!, session: session)
}

func jsonDictionary(_ data: Data?) throws -> [String: Any] {
    guard let data else {
        throw CheckFailure.message("Expected JSON request body")
    }
    guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw CheckFailure.message("Expected JSON object")
    }
    return dictionary
}

func model(_ name: String, providerID: String = "ollama", sizeBytes: Int64 = 123) -> LocalModel {
    LocalModel(providerID: providerID, name: name, sizeBytes: sizeBytes)
}

func loaded(
    _ name: String,
    providerID: String = "ollama",
    sizeBytes: Int64 = 456,
    expiresAt: Date? = nil
) -> LoadedModel {
    LoadedModel(providerID: providerID, name: name, sizeBytes: sizeBytes, processor: "CPU", expiresAt: expiresAt)
}

func process(
    pid: Int32,
    name: String,
    residentMemoryBytes: UInt64,
    executablePath: String? = nil
) -> RunningProcess {
    RunningProcess(
        processID: pid,
        name: name,
        executablePath: executablePath,
        residentMemoryBytes: residentMemoryBytes
    )
}

struct UnreachableModelProvider: ModelProvider {
    let id: String
    var displayName: String { id }

    func installedModels() async throws -> [LocalModel] { throw URLError(.cannotConnectToHost) }
    func loadedModels() async throws -> [LoadedModel] { throw URLError(.cannotConnectToHost) }
    func loadModel(named name: String) async throws { throw URLError(.cannotConnectToHost) }
    func unloadModel(named name: String) async throws { throw URLError(.cannotConnectToHost) }
}

final class MockModelProvider: ModelProvider {
    enum Event: Equatable, CustomStringConvertible {
        case load(String)
        case unload(String)

        var description: String {
            switch self {
            case let .load(name):
                return "load(\(name))"
            case let .unload(name):
                return "unload(\(name))"
            }
        }
    }

    let id: String
    let displayName = "Ollama"
    var installed: [LocalModel]
    var loaded: [LoadedModel]
    var events: [Event] = []

    init(id: String = "ollama", installed: [LocalModel], loaded: [LoadedModel]) {
        self.id = id
        self.installed = installed
        self.loaded = loaded
    }

    func installedModels() async throws -> [LocalModel] {
        installed
    }

    func loadedModels() async throws -> [LoadedModel] {
        loaded
    }

    func loadModel(named name: String) async throws {
        events.append(.load(name))
        loaded = [LoadedModel(providerID: id, name: name, sizeBytes: 456)]
    }

    func unloadModel(named name: String) async throws {
        events.append(.unload(name))
        loaded.removeAll { $0.name == name }
    }
}

struct FixedMemorySampler: MemorySampling {
    let snapshot: MemorySnapshot

    func sample() throws -> MemorySnapshot {
        snapshot
    }
}

struct FixedProcessSampler: ProcessSampling {
    let processes: [RunningProcess]

    func sample() throws -> [RunningProcess] {
        processes
    }
}

final class MockProcessTerminator: ProcessTerminating {
    private(set) var terminatedProcessIDs: [Int32] = []

    func terminate(processID: Int32) throws {
        terminatedProcessIDs.append(processID)
    }
}

actor LoadGate {
    private var loadAttempted = false
    private var finishRequested = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var finishContinuation: CheckedContinuation<Void, Never>?

    func markLoadAttempted() {
        loadAttempted = true
        let pending = waiters
        waiters = []
        for waiter in pending {
            waiter.resume()
        }
    }

    func waitUntilLoadAttempted() async {
        if loadAttempted { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func waitForFinish() async {
        if finishRequested { return }
        await withCheckedContinuation { continuation in
            finishContinuation = continuation
        }
    }

    func finish() {
        finishRequested = true
        finishContinuation?.resume()
        finishContinuation = nil
    }
}

final class BlockingMockModelProvider: ModelProvider {
    let id = "ollama"
    let displayName = "Ollama"
    let gate = LoadGate()
    var installed: [LocalModel]
    var loaded: [LoadedModel]
    var events: [MockModelProvider.Event] = []

    init(installed: [LocalModel], loaded: [LoadedModel]) {
        self.installed = installed
        self.loaded = loaded
    }

    func installedModels() async throws -> [LocalModel] {
        installed
    }

    func loadedModels() async throws -> [LoadedModel] {
        loaded
    }

    func loadModel(named name: String) async throws {
        events.append(.load(name))
        await gate.markLoadAttempted()
        await gate.waitForFinish()
        loaded = [LoadedModel(providerID: id, name: name, sizeBytes: 456)]
    }

    func unloadModel(named name: String) async throws {
        events.append(.unload(name))
        loaded.removeAll { $0.name == name }
    }

    func waitUntilLoadAttempted() async {
        await gate.waitUntilLoadAttempted()
    }

    func finishLoad() {
        Task { await gate.finish() }
    }
}
