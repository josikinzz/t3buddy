import Foundation

extension ModelWidgetChecks {
    static func petMotionChecks(_ suite: inout CheckSuite) async {
        suite.check("Pet scripts shake through tremble(), never a raw Math.sin faster than its cap") {
            let motion = try String(contentsOf: petPage.appendingPathComponent("motion.js"), encoding: .utf8)
            guard let cap = motion.firstMatch(of: try Regex<(Substring, Substring)>(#"TREMBLE_MAX_RATE = (\d+(?:\.\d+)?)"#)).flatMap({ Double($0.1) }) else {
                throw CheckFailure.message("Resources/Pet/motion.js must export TREMBLE_MAX_RATE")
            }
            var buzzes: [String] = []
            for name in try petScripts() {
                let source = try String(contentsOf: petPage.appendingPathComponent(name), encoding: .utf8)
                for (line, rate) in rawSineRates(in: source) where rate > cap {
                    buzzes.append("Resources/Pet/\(name):\(line) Math.sin at \(rate) rad/s")
                }
            }
            try expect(buzzes.isEmpty, "Faster than \(cap) rad/s reads as a buzz; use tremble(t, rate) from Resources/Pet/motion.js:\n  " + buzzes.joined(separator: "\n  "))
        }

        suite.check("Pet sways whose pace changes advance their own phase, never the clock over a runtime period") {
            var sweeps: [String] = []
            for name in try petScripts() {
                let source = try String(contentsOf: petPage.appendingPathComponent(name), encoding: .utf8)
                for (line, argument) in trigArguments(of: sineOrCosineCall, in: source) where argument.contains(clockOverPeriod) {
                    sweeps.append("Resources/Pet/\(name):\(line) Math.sin/cos of t over a parenthesised period")
                }
            }
            try expect(sweeps.isEmpty, "A period that moves with power, sleep or mood sweeps the clock through dozens of cycles, a buzz; keep a phase advanced by dt instead:\n  " + sweeps.joined(separator: "\n  "))
        }
    }

    private static let petPage = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/Pet").standardizedFileURL

    /// The pet scripts that animate, sorted; motion.js owns the shake and is exempt.
    private static func petScripts() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: petPage.path).filter { $0.hasSuffix(".js") && $0 != "motion.js" }.sorted()
    }

    private static let sineCall = try! Regex<Substring>(#"Math\.sin\("#)
    private static let sineOrCosineCall = try! Regex<Substring>(#"Math\.(?:sin|cos)\("#)
    // The bare clock `t` (not `x.t` or `dt`) multiplied, then divided by a parenthesised period.
    private static let clockOverPeriod = try! Regex<Substring>(#"(?:^|[^\w.])t\s*\*[^,]*?/\s*\("#)

    // A literal on either side of a `*` (a regex literal can't hold `*/`).
    private static let multipliedLiteral = try! Regex<(Substring, Substring?, Substring?)>(#"\*\s*(\d+(?:\.\d+)?)(?![\d.])|(?:^|[^\w.])(\d+(?:\.\d+)?)\s*\*"#)

    /// The balanced-paren argument of every call `opener` matches, with the call's line.
    private static func trigArguments(of opener: Regex<Substring>, in source: String) -> [(line: Int, argument: Substring)] {
        var found: [(Int, Substring)] = []
        var index = source.startIndex
        while let call = source[index...].firstMatch(of: opener) {
            var depth = 1
            var end = call.range.upperBound
            while end < source.endIndex, depth > 0 {
                if source[end] == "(" { depth += 1 } else if source[end] == ")" { depth -= 1 }
                end = source.index(after: end)
            }
            let line = source[..<call.range.lowerBound].reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
            found.append((line, source[call.range.upperBound..<end]))
            index = end
        }
        return found
    }

    /// Every numeric literal that multiplies inside a `Math.sin(...)` argument, with its line.
    static func rawSineRates(in source: String) -> [(line: Int, rate: Double)] {
        var found: [(Int, Double)] = []
        for (line, argument) in trigArguments(of: sineCall, in: source) {
            for match in argument.matches(of: multipliedLiteral) {
                if let rate = Double(match.1 ?? match.2 ?? "") { found.append((line, rate)) }
            }
        }
        return found
    }
}
