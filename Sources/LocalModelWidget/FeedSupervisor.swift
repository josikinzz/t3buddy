import Foundation
import LocalAuthentication
import ModelWidgetCore
import Security

/// Keeps the `t3boii-feed` helper running for as long as the app runs.
///
/// The helper ships in `Contents/Helpers/` (next to the executable in a `swift build` tree). It is
/// launched with `--parent-pid`, so it exits with the app. One that exits with status 3 found
/// another feed already running: the app uses that one (`FeedClient` reads `feed.json`) and checks
/// on it now and then. Any other exit is restarted after 1, 2, 4 … 60 s; five minutes up resets that.
@MainActor
final class FeedSupervisor {
    static let restartDelays: [TimeInterval] = [1, 2, 4, 8, 16, 32, 60]
    static let steadyAfter: TimeInterval = 5 * 60
    static let attachedCheck: TimeInterval = 5

    private var process: Process?
    private var restarts = 0
    private var launchedAt: Date?
    private var stopped = false

    func start() {
        stopped = false
        KeychainT3TokenMigration.migrate(into: T3TokenFileStore())
        launch()
    }

    func stop() {
        stopped = true
        process?.terminate()
        process = nil
    }

    static var helperURL: URL? {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/t3boii-feed")
        let beside = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("t3boii-feed")
        return [bundled, beside].compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// The helper is alive but has stopped answering: end it, and the usual restart brings a new one.
    func replaceHung() {
        guard let process, process.isRunning else { return }
        let pid = process.processIdentifier
        NSLog("T3boii: t3boii-feed (pid \(pid)) stopped answering; replacing it")
        process.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }

    private func launch() {
        guard !stopped else { return }
        guard let helper = Self.helperURL else {
            NSLog("T3boii: the t3boii-feed helper is missing; the app polls T3 itself and looks for it again")
            scheduleRestart()
            return
        }
        let process = Process()
        process.executableURL = helper
        process.arguments = ["--parent-pid", String(ProcessInfo.processInfo.processIdentifier)]
        // Feed parts on top of the standard ones (`FeedFlags`), or off with a `-`: `defaults write <app> petFeedFlags -seeds`.
        let flags = FeedFlags.parse(UserDefaults.standard.string(forKey: "petFeedFlags"))
        if !flags.unknown.isEmpty { NSLog("T3boii: petFeedFlags names no feed part (\(flags.unknown.joined(separator: ", "))); ignoring it") }
        if let argument = flags.argument { process.arguments! += ["--flags", argument] }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            Task { @MainActor [weak self] in self?.ended(status: status) }
        }
        do {
            try process.run()
            self.process = process
            launchedAt = Date()
        } catch {
            NSLog("T3boii: could not start t3boii-feed: \(error.localizedDescription)")
            scheduleRestart()
        }
    }

    private func ended(status: Int32) {
        process = nil
        guard !stopped else { return }
        if status == 3 {
            watchAttached()
            return
        }
        NSLog("T3boii: t3boii-feed exited (\(status)); restarting")
        if let launchedAt, Date().timeIntervalSince(launchedAt) > Self.steadyAfter { restarts = 0 }
        scheduleRestart()
    }

    private func scheduleRestart() {
        let delay = Self.restartDelays[min(restarts, Self.restartDelays.count - 1)]
        restarts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.launch() }
        }
    }

    /// Another process's feed is serving; launch our own once it is gone.
    private func watchAttached() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.attachedCheck) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.stopped else { return }
                if FeedDiscovery.load()?.isAlive == true { self.watchAttached() } else { self.launch() }
            }
        }
    }
}

/// Moves the token earlier builds kept in the login Keychain (generic password, service
/// `local.codex.LocalModelWidget.t3mcp`) into the token file, once, and deletes the item only after the file holds the same token.
/// Never prompts: an item this build cannot read without asking is left alone and ignored.
enum KeychainT3TokenMigration {
    static let service = "local.codex.LocalModelWidget.t3mcp"
    static let account = "mcp-access-token"

    static func migrate(into store: T3TokenFileStore) {
        guard !store.exists else { return }
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
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
            switch LegacyT3TokenImport.adopt(result as? Data ?? Data(), into: store) {
            case .moved:
                SecItemDelete(query as CFDictionary)
                NSLog("T3boii: moved the T3 token from the Keychain to the token file")
            case .undecodable:
                NSLog("T3boii: the old Keychain T3 token could not be decoded; keeping it")
            case .notSaved:
                NSLog("T3boii: could not save the T3 token file; keeping the Keychain token")
            }
        case errSecItemNotFound:
            break
        default:
            NSLog("T3boii: the old Keychain T3 token is not readable without a prompt (\(status)); ignoring it")
        }
        if !store.exists { store.save(store.load()) }
    }
}
