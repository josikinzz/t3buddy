import Foundation
import LocalModelWidgetPanel

extension ModelWidgetChecks {
    static func petSettingsChecks(_ suite: inout CheckSuite) async {
        suite.check("Pet kind is T3boii unless the stored kind is one the page knows") {
            try expectEqual(PetKind(stored: nil), .t3boii)
            try expectEqual(PetKind(stored: ""), .t3boii)
            try expectEqual(PetKind(stored: "dragon"), .t3boii)
            try expectEqual(PetKind(stored: "Shoggoth"), .t3boii)
            try expectEqual(PetKind(stored: "shoggoth"), .shoggoth)
            try expectEqual(PetKind(stored: "t3boii"), .t3boii)
            try expectEqual(PetKind.allCases.map(\.displayName), ["T3boii", "Shoggoth"])
        }

        suite.check("Shoggoth tint normalises a valid hex to lower-case #rrggbb") {
            try expectEqual(PetTint(parsing: "#3DDC84").hex, "#3ddc84")
            try expectEqual(PetTint(parsing: "  #A970ff\n").hex, "#a970ff")
            try expectEqual(PetTint(parsing: "#000000").hex, "#000000")
        }

        suite.check("Shoggoth tint falls back to red for anything but #rrggbb") {
            try expectEqual(PetTint.default.hex, "#ff0000")
            for bad in [nil, "", "   ", "#fff", "red", "#gg0000", "3ddc84", "#3ddc845", "##3ddc8", "#ｆｆ0000", "#ff0000');alert(1);('"] as [String?] {
                try expect(PetTint(parsing: bad) == .default, "\(String(describing: bad)) must fall back to the default")
            }
        }

        suite.check("Shoggoth tint presets parse to themselves and start with the default") {
            try expectEqual(PetTint.presets.first?.tint, .default)
            try expectEqual(PetTint.presets.first?.name, "Red")
            try expectEqual(Set(PetTint.presets.map(\.tint)).count, PetTint.presets.count)
            for preset in PetTint.presets {
                try expect(PetTint(parsing: preset.tint.hex) == preset.tint, "\(preset.name) must round-trip")
            }
        }

        suite.check("Shoggoth tint from colour panel components rounds and clamps to #rrggbb") {
            try expectEqual(PetTint(red: 1, green: 0.5, blue: 0).hex, "#ff8000")
            try expectEqual(PetTint(red: 1.2, green: -0.1, blue: .nan).hex, "#ff0000")
            let violet = PetTint(parsing: "#a970ff")
            let rgb = violet.components
            try expectEqual(PetTint(red: rgb.red, green: rgb.green, blue: rgb.blue), violet)
        }

        suite.check("Pet page config carries the parsed pet and tint, never the stored text") {
            let hostileKind = "shoggoth\"};alert(1);//"
            let hostileTint = "#ff0000');alert(1);('"
            let script = PetPageConfig.script(position: ["x": 400, "y": 500], reducedMotion: false, muted: true, pet: PetKind(stored: hostileKind), tint: PetTint(parsing: hostileTint)) ?? ""
            try expect(!script.contains("alert"), "Unvalidated text must never reach the page")
            let config = try pageConfig(script)
            try expectEqual(config["pet"] as? String, "t3boii")
            try expectEqual(config["tint"] as? String, "#ff0000")
            try expectEqual(config["muted"] as? Bool, true)

            let shoggoth = try pageConfig(PetPageConfig.script(position: ["x": 400, "y": 500], reducedMotion: true, muted: false, pet: PetKind(stored: "shoggoth"), tint: PetTint(parsing: " #40C8E0 ")) ?? "")
            try expectEqual(shoggoth["pet"] as? String, "shoggoth")
            try expectEqual(shoggoth["tint"] as? String, "#40c8e0")
            try expectEqual(shoggoth["position"] as? [String: Double], ["x": 400, "y": 500])
        }
    }

    private static func pageConfig(_ script: String) throws -> [String: Any] {
        let prefix = "window.__t3boiiConfig = "
        try expect(script.hasPrefix(prefix) && script.hasSuffix(";"), "Config must be one assignment: \(script)")
        let json = script.dropFirst(prefix.count).dropLast()
        guard let config = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { throw CheckFailure.message("Config must be a JSON object: \(json)") }
        return config
    }
}
