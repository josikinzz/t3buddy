import Foundation
import ModelWidgetCore

extension ModelWidgetChecks {
    static func tokenMigrationChecks(_ suite: inout CheckSuite) {
        func scratchFolder() -> URL {
            FileManager.default.temporaryDirectory.appendingPathComponent("t3migrate-\(UUID().uuidString)")
        }
        let legacy = Data(#"{"accessToken":"demo-token","expiresAt":null}"#.utf8)

        suite.check("a legacy Keychain token counts as moved only once the token file holds it") {
            let folder = scratchFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let store = T3TokenFileStore(url: folder.appendingPathComponent("t3-mcp-token.json"))

            try expectEqual(LegacyT3TokenImport.adopt(legacy, into: store), .moved)

            try expectEqual(T3TokenFileStore(url: store.url).load().token?.accessToken, "demo-token")
        }

        suite.check("a legacy token whose expiry has fractional seconds still counts as moved") {
            let folder = scratchFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let store = T3TokenFileStore(url: folder.appendingPathComponent("t3-mcp-token.json"))
            let fractional = try JSONEncoder().encode(T3MCPToken(accessToken: "demo-token", expiresAt: Date(timeIntervalSince1970: 1_800_000_000.125)))

            try expectEqual(LegacyT3TokenImport.adopt(fractional, into: store), .moved)

            try expectEqual(T3TokenFileStore(url: store.url).load().token?.accessToken, "demo-token")
        }

        suite.check("an undecodable legacy payload is not moved and writes no token file") {
            let folder = scratchFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let store = T3TokenFileStore(url: folder.appendingPathComponent("t3-mcp-token.json"))

            try expectEqual(LegacyT3TokenImport.adopt(Data("not json".utf8), into: store), .undecodable)
            try expectEqual(LegacyT3TokenImport.adopt(Data(), into: store), .undecodable)

            try expect(!store.exists, "no token file for a payload that cannot be read")
        }

        suite.check("a token file that cannot be written leaves the legacy token unmoved") {
            let folder = scratchFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let blocker = folder.appendingPathComponent("blocker")
            try Data().write(to: blocker)
            let store = T3TokenFileStore(url: blocker.appendingPathComponent("t3-mcp-token.json"))

            try expectEqual(LegacyT3TokenImport.adopt(legacy, into: store), .notSaved)
            try expectEqual(store.saveVerified(T3MCPCredentials(clientId: "demo-client")), false)
        }
    }
}
