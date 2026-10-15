import AppKit
import Foundation
import LocalAuthentication
import ModelWidgetCore
import Security

/// Polls every orbit source at once, merges their orbs, and hands the pet page a snapshot only when it changed.
///
/// Each source gets `sourceDeadline` per poll. A source that misses it (or is still busy with an
/// earlier poll) contributes its last good orbs for at most one interval, then nothing, and never
/// holds up the other sources. An orb leaves only once it has been missing from two polls in a
/// row (`OrbitRemovalHold`), so a gap between a thread's turns or one bad poll is not a respawn.
/// The T3 source also says which providers are at a rate or usage limit (`limits`).
@MainActor
final class OrbitRuntime {
    static let pollInterval: TimeInterval = 5
    static let sourceDeadline: TimeInterval = 4.5
    /// Posted by the gear menu's "Connect T3" item.
    static let connectT3Notification = Notification.Name("T3boiiConnectT3")

    private let sources: [OrbitSource]
    private let t3: T3ThreadSource
    private let icons: ProjectIconResolver
    private let deliver: (String) -> Void
    private var gate = OrbitChangeGate()
    private var hold = OrbitRemovalHold()
    private var fallback = OrbitSourceFallback(maxAge: OrbitRuntime.pollInterval + 1)
    private var busy: Set<Int> = []
    private var timer: Timer?
    private var polling = false
    private var observer: NSObjectProtocol?

    /// `deliver` receives snapshot JSON for `window.t3boii.update`.
    init(deliver: @escaping (String) -> Void) {
        let store = T3TokenFileStore()
        KeychainT3TokenMigration.migrate(into: store)
        let icons = ProjectIconResolver(transcodeToPNG: Self.pngFromImageFile)
        let t3 = T3ThreadSource(tokenStore: store, icons: icons)
        self.t3 = t3
        self.icons = icons
        self.sources = [t3, GrokOrbitSource()]
        self.deliver = deliver
    }

    func start() {
        guard timer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: Self.connectT3Notification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.connectT3() }
        }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    private func poll() {
        guard !polling else { return }
        polling = true
        let now = Date()
        // A source still busy with an earlier poll is not asked again until it answers.
        let jobs = sources.enumerated().filter { !busy.contains($0.offset) }
        for job in jobs { busy.insert(job.offset) }
        let skipped = Set(sources.indices).subtracting(jobs.map(\.offset))
        Task { [weak self] in
            let results = await withTaskGroup(of: (Int, [Orb]?).self) { group in
                for (index, source) in jobs {
                    group.addTask {
                        let orbs = await OrbitPolling.withDeadline(Self.sourceDeadline) {
                            let orbs = await source.orbs(now: now)
                            await MainActor.run { _ = self?.busy.remove(index) }
                            return orbs
                        }
                        return (index, orbs)
                    }
                }
                var results: [Int: [Orb]?] = [:]
                for await (index, orbs) in group { results[index] = orbs }
                return results
            }
            guard let self else { return }
            var lists: [[Orb]] = []
            for index in self.sources.indices {
                let result = skipped.contains(index) ? nil : results[index] ?? nil
                if result == nil { NSLog("T3boii: orbit source \(index) did not answer within \(Self.sourceDeadline) s") }
                lists.append(self.fallback.resolve(source: index, result: result, now: now))
            }
            self.polling = false
            var snapshot = self.hold.apply(OrbitSnapshot.merged(lists))
            // Providers at a rate or usage limit: T3boii cries once per new one.
            snapshot.limits = await self.t3.limits(now: now)
            if let json = self.gate.jsonIfChanged(snapshot) { self.deliver(json) }
        }
    }

    /// The owner's real projects for the demo (`window.t3boii.demo`), faces resolved as for live threads.
    func demoPayload() async -> String? {
        let projects = await t3.knownProjects
        let icons = icons
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Projects", isDirectory: true)
        return await Task.detached {
            DemoProjects.payloadJSON(DemoProjects.entries(t3Projects: projects, projectsFolder: folder, icons: icons))
        }.value
    }

    private func connectT3() {
        let t3 = t3
        Task { [weak self] in
            let connected = await t3.connectNow()
            NSLog("T3boii: Connect T3 \(connected ? "succeeded" : "failed")")
            self?.poll()
        }
    }

    /// `.icns` (T3's last candidates) as PNG, since WebKit cannot show it.
    nonisolated private static func pngFromImageFile(_ url: URL) -> Data? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        var rect = NSRect(x: 0, y: 0, width: 64, height: 64)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }
}

/// Moves the token earlier builds kept in the login Keychain (generic password, service
/// `local.codex.LocalModelWidget.t3mcp`) into the token file, once, and deletes the item.
/// Never prompts: an item this build cannot read without asking is left alone and ignored.
enum KeychainT3TokenMigration {
    static let service = "local.codex.LocalModelWidget.t3mcp"
    static let account = "mcp-access-token"

    static func migrate(into store: T3TokenFileStore) {
        guard !store.exists else { return }
        let context = LAContext()
        context.interactionNotAllowed = true
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseAuthenticationContext as String: context
        ]
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            if let data = result as? Data, let token = try? JSONDecoder().decode(T3MCPToken.self, from: data) {
                store.save(T3MCPCredentials(token: token))
                NSLog("T3boii: moved the T3 token from the Keychain to the token file")
            }
            query[kSecUseAuthenticationContext as String] = context
            SecItemDelete(query as CFDictionary)
        case errSecItemNotFound:
            break
        default:
            NSLog("T3boii: the old Keychain T3 token is not readable without a prompt (\(status)); ignoring it")
        }
        if !store.exists { store.save(store.load()) }
    }
}
