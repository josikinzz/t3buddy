import AppKit
import Foundation
import ModelWidgetCore

/// t3boii-feed: reads T3 Code and Grok Bot, and serves what T3boii should show on 127.0.0.1.
///
///     t3boii-feed --parent-pid <pid>   the app's helper: exits when the app does
///     t3boii-feed --standalone         runs until stopped
///     t3boii-feed --tap                prints the state, then each event, as JSON lines; serves nothing
///     --flags -queue,-seeds            turns parts off; both are on as standard (`FeedFlags`)
///     --t3-home <dir> --token-file <f> another T3 home and token file, for drills against a fake T3
///                                      (`scripts/t3_restart_drill.py`); never the real token
///
/// Anything else on the command line, or a flag name that switches no part, is refused (status 2)
/// before T3 is touched. Only one serving sidecar runs per user (`feed.lock`); a second exits with status 3.
let version = "1"
let usage = "usage: t3boii-feed --parent-pid <pid> | --standalone | --tap  [--flags <names>] [--t3-home <dir>] [--token-file <file>]\n"

func refuse(_ problem: String) -> Never {
    FileHandle.standardError.write(Data("t3boii-feed: \(problem)\n\(usage)".utf8))
    exit(2)
}

var options: [String: String] = [:]
var switches: Set<String> = []
var unread = CommandLine.arguments.dropFirst()
while let argument = unread.popFirst() {
    switch argument {
    case "--standalone", "--tap":
        switches.insert(argument)
    case "--parent-pid", "--flags", "--t3-home", "--token-file":
        guard let value = unread.popFirst() else { refuse("\(argument) needs a value") }
        options[argument] = value
    default:
        refuse("unknown option \(argument)")
    }
}
let tap = switches.contains("--tap")
let parentPid = options["--parent-pid"].flatMap { Int32($0) }
if options["--parent-pid"] != nil, parentPid == nil { refuse("--parent-pid needs a process id") }
guard tap || parentPid != nil || switches.contains("--standalone") else { refuse("say how to run: --parent-pid, --standalone or --tap") }
let flags = FeedFlags.parse(options["--flags"])
guard flags.unknown.isEmpty else {
    refuse("unknown feed flag \(flags.unknown.joined(separator: ", ")) (parts: \(FeedFlags.known.sorted().joined(separator: ", ")))")
}

func log(_ line: String) {
    FileHandle.standardError.write(Data("\(ISO8601DateFormatter().string(from: Date())) \(line)\n".utf8))
}

let t3Home = options["--t3-home"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".t3", isDirectory: true)
let tokenStore = options["--token-file"].map { T3TokenFileStore(url: URL(fileURLWithPath: $0)) } ?? T3TokenFileStore()
let t3 = T3ThreadSource(t3Home: t3Home, tokenStore: tokenStore, icons: ProjectIconResolver(transcodeToPNG: ProjectIconResolver.pngFromImageFile), readsQueues: flags.contains("queue"), readsSeeds: flags.contains("seeds"), log: log)
let engine = FeedEngine(sources: [t3, GrokOrbitSource()], log: log)
let pid = getpid()

/// One line every 10 s: T3 tool calls so far, in all and by tool, for measuring the call rate.
func logCalls() async {
    while true {
        try? await Task.sleep(nanoseconds: 10_000_000_000)
        let byTool = await t3.toolCallsByTool.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        log("t3boii-feed: \(await t3.toolCalls) T3 tool calls so far (\(byTool))")
    }
}

func shutdown(_ status: Int32) -> Never {
    if !tap { FeedDiscovery.remove(pid: pid) }
    exit(status)
}

var watchers: [DispatchSourceProtocol] = []
for signal in [SIGTERM, SIGINT, SIGHUP] {
    Foundation.signal(signal, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signal, queue: .main)
    source.setEventHandler { shutdown(0) }
    source.resume()
    watchers.append(source)
}

if tap {
    Task {
        let (_, batches) = await engine.subscribe()
        await engine.poll()
        print(FeedJSON.encode(await engine.state))
        fflush(stdout)
        Task { await engine.run() }
        Task { await logCalls() }
        for await batch in batches {
            for event in batch.events { print(FeedJSON.encode(event)) }
            fflush(stdout)
        }
    }
} else {
    try? FileManager.default.createDirectory(at: FeedDiscovery.folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let lock = open(FeedDiscovery.lockURL.path, O_CREAT | O_RDWR, 0o600)
    guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else {
        log("t3boii-feed: another feed is running")
        exit(3)
    }
    if let parentPid {
        let parent = DispatchSource.makeProcessSource(identifier: parentPid, eventMask: .exit, queue: .main)
        parent.setEventHandler { shutdown(0) }
        parent.resume()
        watchers.append(parent)
        if kill(parentPid, 0) != 0 { shutdown(0) }
    }
    let token = FeedDiscovery.newToken()
    let icons = ProjectIconResolver(transcodeToPNG: ProjectIconResolver.pngFromImageFile)
    let projectsFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Projects", isDirectory: true)
    let server = FeedServer(engine: engine, token: token, connect: { await t3.connectNow() }, demo: {
        DemoProjects.payloadJSON(DemoProjects.entries(t3Projects: await t3.knownProjects, projectsFolder: projectsFolder, icons: icons))
    })
    Task {
        do {
            let port = try await server.start()
            try FeedDiscovery(pid: pid, port: port, token: token, startedAt: Date(), version: version).save()
            log("t3boii-feed: serving on 127.0.0.1:\(port)")
            Task { await logCalls() }
            await engine.run()
        } catch {
            log("t3boii-feed: could not serve (\(error))")
            shutdown(1)
        }
    }
}

dispatchMain()
