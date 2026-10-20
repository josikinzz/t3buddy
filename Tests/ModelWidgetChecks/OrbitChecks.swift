import Foundation
import LocalModelWidgetPanel
import ModelWidgetCore

extension ModelWidgetChecks {
    static func orbitChecks(_ suite: inout CheckSuite) async {
        // MARK: ProjectIconResolver

        suite.check("Project icon resolver finds public/favicon.webp in a fixture folder") {
            try withProject("game-engine", files: ["public/favicon.webp": Data([0x52, 0x49, 0x46, 0x46, 0x01])]) { root in
                let resolver = ProjectIconResolver()
                try expectEqual(resolver.iconPath(workspaceRoot: root), root + "/public/favicon.webp")
                let icon = resolver.resolve(workspaceRoot: root)
                try expectEqual(icon.kind, .image)
                try expect(icon.src?.hasPrefix("data:image/webp;base64,") == true, "webp must be a webp data URL, got \(icon.src ?? "nil")")
            }
        }

        suite.check("Project icon resolver gives a folder with no icon a two-letter monogram") {
            try withProject("data-pipeline", files: ["README.md": Data("hi".utf8)]) { root in
                let icon = ProjectIconResolver().resolve(workspaceRoot: root)
                try expectEqual(icon.kind, .monogram)
                try expectEqual(icon.text, "DP")
                // T3's colour hash over the name; the same name always gets the same colour.
                try expectEqual(icon.color, ProjectMonogram.hex(forColorName: ProjectMonogram.colorName(for: "data-pipeline")))
                try expectEqual(ProjectIconResolver().resolve(workspaceRoot: root).color, icon.color)
            }
        }

        suite.check("Project monogram follows T3's letter rules") {
            try expectEqual(ProjectMonogram.text(for: "data-pipeline"), "DP")
            try expectEqual(ProjectMonogram.text(for: "widgets"), "WS")
            try expectEqual(ProjectMonogram.text(for: "demo-app"), "DA")
            try expectEqual(ProjectMonogram.text(for: "web3 tools"), "W3")
            try expectEqual(ProjectMonogram.text(for: "  "), "PR")
        }

        suite.check("Project icon resolver lets the manual favicon and icon win") {
            try withProject("docs-site", files: [
                "public/favicon.svg": Data("<svg xmlns='http://www.w3.org/2000/svg'/>".utf8),
                "brand/mark.png": Data([0x89, 0x50, 0x4E, 0x47])
            ]) { root in
                let resolver = ProjectIconResolver()
                try expectEqual(resolver.iconPath(workspaceRoot: root), root + "/public/favicon.svg")
                try expectEqual(resolver.iconPath(workspaceRoot: root, faviconOverride: root + "/brand/mark.png"), root + "/brand/mark.png")
                let png = resolver.resolve(workspaceRoot: root, faviconOverride: root + "/brand/mark.png")
                try expect(png.src?.hasPrefix("data:image/png;base64,") == true, "faviconPath override must win")
                let manual = resolver.resolve(workspaceRoot: root, faviconOverride: root + "/brand/mark.png", iconOverride: .monogram(text: "DW", color: "violet"))
                try expectEqual(manual, .monogram("DW", color: "#8b5cf6"))
                // A missing override file falls through to the candidates.
                try expectEqual(resolver.iconPath(workspaceRoot: root, faviconOverride: root + "/gone.png"), root + "/public/favicon.svg")
            }
        }

        suite.check("Project icon resolver resolves index.html rel=icon against public/") {
            let html = #"<html><head><link rel="stylesheet" href="/a.css"><link href="/brand/icon.png?v=2" rel="icon" type="image/png"></head></html>"#
            try withProject("demo-app", files: ["index.html": Data(html.utf8), "public/brand/icon.png": Data([0x89, 0x50])]) { root in
                try expectEqual(ProjectIconResolver().iconPath(workspaceRoot: root), root + "/public/brand/icon.png")
            }
            let route = #"head: () => ({ links: [{ rel: "stylesheet", href: appCss }, { rel: 'icon', href: '/logo.svg' }] })"#
            try expectEqual(ProjectIconResolver.extractIconHref(route), "/logo.svg")
            try expectEqual(ProjectIconResolver.extractIconHref("<link rel='apple-touch-icon' href='/x.png'>"), nil)
        }

        suite.check("Project icon resolver follows t3.json iconPath and refuses paths outside the root") {
            try withProject("some-wiki", files: [
                "t3.json": Data(#"{"iconPath":"art/logo.svg"}"#.utf8),
                "art/logo.svg": Data("<svg/>".utf8),
                "favicon.ico": Data([0, 0, 1, 0])
            ]) { root in
                try expectEqual(ProjectIconResolver().iconPath(workspaceRoot: root), root + "/art/logo.svg")
            }
            try withProject("escape", files: ["t3.json": Data(#"{"iconPath":"../outside.svg"}"#.utf8)]) { root in
                try expectEqual(ProjectIconResolver().iconPath(workspaceRoot: root), nil)
            }
        }

        suite.check("Project icon resolver skips oversized icons and revalidates its cache") {
            let now = Date(timeIntervalSince1970: 1_000_000)
            try withProject("big", files: ["favicon.png": Data(count: ProjectIconResolver.maxImageBytes + 1)]) { root in
                let resolver = ProjectIconResolver()
                try expectEqual(resolver.resolve(workspaceRoot: root, now: now).kind, .monogram)
                // A found file is revalidated by its mtime: the replacement shows at once.
                let file = URL(fileURLWithPath: root + "/favicon.png")
                try Data([0x89, 0x50]).write(to: file)
                try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(5)], ofItemAtPath: file.path)
                try expectEqual(resolver.resolve(workspaceRoot: root, now: now.addingTimeInterval(10)).kind, .image)
            }
            try withProject("bare", files: ["README.md": Data()]) { root in
                let resolver = ProjectIconResolver()
                try expectEqual(resolver.resolve(workspaceRoot: root, now: now).kind, .monogram)
                // No icon is cached for a minute, as T3 does; a new favicon shows after that.
                try Data("<svg/>".utf8).write(to: URL(fileURLWithPath: root + "/favicon.svg"))
                try expectEqual(resolver.resolve(workspaceRoot: root, now: now.addingTimeInterval(10)).kind, .monogram)
                try expectEqual(resolver.resolve(workspaceRoot: root, now: now.addingTimeInterval(120)).kind, .image)
            }
        }

        suite.check("Project icon override decodes T3's projectIcon shapes") {
            try expectEqual(ProjectIconOverride(json: ["kind": "lucide", "name": "message-square-dashed", "color": "gray"]), .lucide(name: "message-square-dashed", color: "gray"))
            try expectEqual(ProjectIconOverride(json: ["kind": "emoji", "emoji": "🌿"]), .emoji("🌿"))
            try expectEqual(ProjectIconOverride(json: NSNull()), nil)
            let lucide = ProjectIconResolver().resolve(workspaceRoot: "/nonexistent", iconOverride: .lucide(name: "x", color: "teal"), title: "No project")
            try expectEqual(lucide, .monogram("NP", color: "#14b8a6"))
        }

        // MARK: MCP wire

        suite.check("MCP wire reads a tools/call result from a JSON response") {
            let result = try MCPWire.response(id: 4, body: Data(threadListJSONResponse.utf8), contentType: "application/json")
            let page = try T3Payload.threads(try MCPWire.toolPayload(result))
            try expectEqual(page.items.map(\.threadId), ["af2196b9", "sub-1", "done-1"])
            try expectEqual(page.items.map(\.status.rawValue), ["running", "waiting", "completed"])
            try expectEqual(page.items[1].parentThreadId, "af2196b9")
            try expectEqual(page.nextCursor, nil)
        }

        suite.check("MCP wire reads a tools/call result from an SSE response") {
            let sse = "event: message\r\nid: 1\r\ndata: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/message\",\"params\":{}}\r\n\r\n"
                + "event: message\ndata: " + threadListJSONResponse + "\n\n"
            let result = try MCPWire.response(id: 4, body: Data(sse.utf8), contentType: "text/event-stream; charset=utf-8")
            let page = try T3Payload.threads(try MCPWire.toolPayload(result))
            try expectEqual(page.items.map(\.status.isActive), [true, true, false])
        }

        suite.check("MCP wire surfaces JSON-RPC and tool errors") {
            let rpc = #"{"jsonrpc":"2.0","id":2,"error":{"code":-32602,"message":"Unknown tool"}}"#
            do {
                _ = try MCPWire.response(id: 2, body: Data(rpc.utf8), contentType: "application/json")
                throw CheckFailure.message("an RPC error must throw")
            } catch let error as MCPError {
                try expectEqual(error, .rpc(code: -32602, message: "Unknown tool"))
            }
            let toolError: [String: Any] = ["isError": true, "content": [["type": "text", "text": "projectId is required"]]]
            do {
                _ = try MCPWire.toolPayload(toolError)
                throw CheckFailure.message("a tool error must throw")
            } catch let error as MCPError {
                try expectEqual(error, .toolError("projectId is required"))
            }
        }

        suite.check("T3 payload decodes projects with favicon and icon overrides") {
            let page = try T3Payload.projects(Data(projectListPayload.utf8))
            try expectEqual(page.items.map(\.title), ["docs-site", "No project"])
            try expectEqual(page.items[0].faviconPath, "/Users/tester/Projects/docs-site/public/favicon.svg")
            try expectEqual(page.items[1].projectIcon, .lucide(name: "message-square-dashed", color: "gray"))
            try expectEqual(try T3Payload.driverKinds(Data(#"{"providers":[{"providerInstanceId":"codex-work","driverKind":"codex"}]}"#.utf8)), ["codex-work": "codex"])
        }

        // MARK: Status → orb

        suite.check("T3 thread status maps active statuses to active orbs and keeps the parent") {
            for status in ["preparing", "queued", "starting", "running", "waiting"] {
                try expectEqual(T3ThreadStatus(rawValue: status).orbState(), .active)
            }
            for status in ["idle", "completed", "interrupted", "cancelled", "rolled_back", "someday"] {
                try expectEqual(T3ThreadStatus(rawValue: status).orbState(), nil)
            }
            let threads = try T3Payload.threads(try MCPWire.toolPayload(try MCPWire.response(id: 4, body: Data(threadListJSONResponse.utf8), contentType: "application/json"))).items
            let project = T3Project(id: "p", title: "docs-site", workspaceRoot: "/tmp")
            let origin = URL(string: "http://127.0.0.1:3773")!
            let orbs = T3OrbMapper.orbs(project: project, threads: threads, icon: .monogram("DA", color: "#000000"), driverKinds: ["codex-work": "codex"]) {
                T3OrbMapper.threadURL(origin: origin, environmentId: "env", threadId: $0)
            }
            try expectEqual(orbs.map(\.id), ["t3:af2196b9", "t3:sub-1"])
            try expectEqual(orbs.map(\.parentId), [nil, "t3:af2196b9"])
            try expectEqual(orbs.map(\.provider), ["claudeAgent", "codex"])
            try expectEqual(orbs.map(\.state), [.active, .active])
            try expectEqual(orbs[0].label, "docs-site · slop unit tests")
            try expectEqual(orbs[0].link, "http://127.0.0.1:3773/env/af2196b9")
            try expectEqual(T3OrbMapper.threadURL(origin: origin, environmentId: "env", threadId: "thread:a%3Ab/c"), "http://127.0.0.1:3773/env/thread:a%253Ab%2Fc")
        }

        // MARK: OAuth helpers

        suite.check("T3 MCP auth builds PKCE S256 and reads the approval redirect") {
            // Challenge cross-checked with Python's hashlib (base64url of SHA-256 over the verifier).
            let rfc = "dBjftJeZ4CVP-mJ92K27uhbUJU1p1r_wW1gFWFOEjXk"
            let pkce = T3MCPAuth.pkce(randomBytes: Array(T3MCPAuthChecks.base64URLDecode(rfc)))
            try expectEqual(pkce.verifier, rfc)
            try expectEqual(pkce.challenge, "ngF5GsXcbwljx6u133FFr3Xht9xooA_DuaX_3QwODtc")
            let code = try T3MCPAuth.authorizationCode(fromRedirect: "http://127.0.0.1:47321/t3boii/callback?code=abc&state=s1&iss=http%3A%2F%2F127.0.0.1%3A3773", expectedState: "s1")
            try expectEqual(code, "abc")
            do {
                _ = try T3MCPAuth.authorizationCode(fromRedirect: "http://127.0.0.1/cb?error=access_denied&state=s1", expectedState: "s1")
                throw CheckFailure.message("a denial must throw")
            } catch let error as T3MCPAuth.RedirectError {
                try expectEqual(error, .denied("access_denied"))
            }
            let now = Date(timeIntervalSince1970: 1_000)
            let token = try T3MCPAuth.token(fromResponse: Data(#"{"access_token":"eyJ.x","token_type":"Bearer","expires_in":2592000,"scope":"orchestration:read"}"#.utf8), now: now)
            try expectEqual(token, T3MCPToken(accessToken: "eyJ.x", expiresAt: now.addingTimeInterval(2_592_000)))
            try expect(token.isUsable(now: now), "fresh token is usable")
            try expect(!token.isUsable(now: now.addingTimeInterval(2_592_000 - 60)), "token about to expire is not usable")
            try expectEqual(String(decoding: T3MCPAuth.formBody([("redirect_uri", "http://a/b?c"), ("code", "x+y")]), as: UTF8.self), "redirect_uri=http%3A%2F%2Fa%2Fb%3Fc&code=x%2By")
        }

        suite.check("T3 CLI locator picks the service's active version") {
            let home = FileManager.default.temporaryDirectory.appendingPathComponent("t3home-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: home) }
            for version in ["0.0.46-nightly.20261014.3093", "0.0.46-nightly.20261014.3118"] {
                let dir = home.appendingPathComponent("runtime/versions/\(version)")
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: dir.appendingPathComponent("t3").path, contents: Data(), attributes: [.posixPermissions: 0o755])
            }
            try expectEqual(T3CLILocator.activeBinary(t3Home: home)?.pathComponents.suffix(2), ["0.0.46-nightly.20261014.3118", "t3"])
            try Data(#"{"activeVersion":"0.0.46-nightly.20261014.3093"}"#.utf8).write(to: home.appendingPathComponent("runtime/service-state.json"))
            try expectEqual(T3CLILocator.activeBinary(t3Home: home)?.pathComponents.suffix(2), ["0.0.46-nightly.20261014.3093", "t3"])
            try expectEqual(T3CLILocator.pairingCode(fromJSON: Data(#"{"id":"1","credential":"PAIR-123","scopes":["orchestration:read"]}"#.utf8)), "PAIR-123")
        }

        // MARK: Snapshot and diff

        suite.check("Feed state JSON round-trips with the optional link") {
            let snapshot = FeedState(orbs: [Orb(id: "t3:a", source: .t3, projectIcon: .image(dataURL: "data:image/png;base64,AA=="), provider: "codex", label: "x", link: "http://127.0.0.1:3773/e/a")])
            let decoded = try JSONDecoder().decode(FeedState.self, from: Data(FeedJSON.encode(snapshot).utf8))
            try expectEqual(decoded, snapshot)
            try expect(FeedJSON.encode(snapshot).contains(#""src":"data:image/png;base64,AA==""#), "data URLs keep their slashes unescaped")
        }

        suite.check("A satellite's activity reaches the pet page with its parent id") {
            let satellite = Orb(id: "t3:node:provider:claudeAgent:native-item:task%3Aa5b0", parentId: "t3:6d82", source: .t3, projectIcon: .monogram("WS", color: "#000000"), provider: "claudeAgent", activity: "running swift build")
            let json = FeedJSON.encode(FeedState(orbs: [satellite]))
            try expect(json.contains(#""activity":"running swift build""#) && json.contains(#""parentId":"t3:6d82""#), "satellite JSON: \(json)")
        }

        suite.check("Pet layer only opens orb links to T3's local web UI") {
            try expect(PetLayerGeometry.isLocalThreadLink(URL(string: "http://127.0.0.1:3773/env/thread")!), "local T3 opens")
            try expect(!PetLayerGeometry.isLocalThreadLink(URL(string: "https://example.com/env/thread")!), "remote host is refused")
            try expect(!PetLayerGeometry.isLocalThreadLink(URL(string: "file:///etc/passwd")!), "file URL is refused")
        }
    }
}

// MARK: Fixtures

/// Trimmed from a real `t3_thread_list` response (T3 Code 0.0.46-nightly.20261014.3118).
private let threadListJSONResponse = #"{"jsonrpc":"2.0","id":4,"result":{"content":[{"type":"text","text":"{\"projectId\":\"p\",\"currentThreadId\":null,\"threads\":[{\"threadId\":\"af2196b9\",\"title\":\"slop unit tests\",\"status\":\"running\",\"providerInstanceId\":\"claudeAgent\",\"model\":\"claude-opus-5-5\",\"parentThreadId\":null,\"relationshipToParent\":null},{\"threadId\":\"sub-1\",\"title\":\"\",\"status\":\"waiting\",\"providerInstanceId\":\"codex-work\",\"parentThreadId\":\"af2196b9\",\"relationshipToParent\":\"subagent\"},{\"threadId\":\"done-1\",\"title\":\"old\",\"status\":\"completed\",\"providerInstanceId\":\"codex\",\"parentThreadId\":null}],\"nextCursor\":null,\"total\":3}"}],"isError":false}}"#

private let projectListPayload = #"{"projects":[{"id":"2720da92","title":"docs-site","workspaceRoot":"/Users/tester/Projects/docs-site","faviconPath":"/Users/tester/Projects/docs-site/public/favicon.svg","projectIcon":null,"deletedAt":null},{"id":"bec5b46b","title":"No project","workspaceRoot":"/Users/tester/.t3/scratch","faviconPath":null,"projectIcon":{"kind":"lucide","name":"message-square-dashed","color":"gray"}},{"id":"gone","title":"Gone","workspaceRoot":"/x","deletedAt":"2026-01-01T00:00:00Z"}],"nextCursor":null}"#

private func orb(_ id: String, source: Orb.Source = .t3) -> Orb {
    Orb(id: id, source: source, projectIcon: .monogram("AB", color: "#123456"), provider: "codex")
}

/// Makes `<tmp>/<uuid>/<name>` holding `files`, runs `body` with its path, then removes it.
private func withProject(_ name: String, files: [String: Data], _ body: (String) throws -> Void) throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-\(UUID().uuidString)", isDirectory: true)
    let root = base.appendingPathComponent(name, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: base) }
    for (relative, data) in files {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try body(root.standardizedFileURL.path)
}

private func expectNotNilValue<T>(_ value: T?) throws -> T {
    guard let value else { throw CheckFailure.message("expected a value, got nil") }
    return value
}

private enum T3MCPAuthChecks {
    static func base64URLDecode(_ text: String) -> Data {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        return Data(base64Encoded: base64) ?? Data()
    }
}
