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

        suite.check("The motion rules read every body module as well as the page's scripts") {
            let scripts = try petScripts()
            try expect(scripts.contains("bodies/t3boii.js") && scripts.contains("pet.js"), "petScripts() lists bodies/*.js beside the page's scripts: \(scripts)")
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

        suite.check("Pet laps and breaths whose rate is a variable advance a Phase, never the clock times that rate") {
            for bad in ["const goal = spec.speed * t * motion + slot;", "x * t * motion", "Math.sin(t * rate + 1)", "Math.sin(t * period)", "Math.cos(t * rate)", "Math.cos( t * speed.x)"] {
                try expect(bad.contains(clockTimesVariable), "the rule catches \(bad)")
            }
            for fine in ["Math.sin(t * 0.9 + k)", "Math.sin(t * TAU / WAIT_S)", "Math.sin(t * BOB_RATE)", "Math.cos(t * 7.5)", "Math.cos(t * TAU / WAIT_S)", "Math.cos(dt * rate)", "ring.phase.advance(dt, speed * motion)", "speed * this.t"] {
                try expect(!fine.contains(clockTimesVariable), "the rule passes \(fine)")
            }
            var sweeps: [String] = []
            for name in try petScripts() {
                let source = try String(contentsOf: petPage.appendingPathComponent(name), encoding: .utf8)
                for match in source.matches(of: clockTimesVariable) {
                    let line = source[..<match.range.lowerBound].reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
                    sweeps.append("Resources/Pet/\(name):\(line) \(match.output.trimmingCharacters(in: .whitespaces))")
                }
            }
            try expect(sweeps.isEmpty, "A rate that changes sweeps every slot round at once when it multiplies the clock; keep a Phase (motion.js) and advance it by dt:\n  " + sweeps.joined(separator: "\n  "))
        }

        suite.check("Orb breaths come from orbit.js (--pulse), not CSS keyframes that restart when the pace changes") {
            let page = try String(contentsOf: petPage.appendingPathComponent("index.html"), encoding: .utf8)
            for rule in page.matches(of: try Regex<Substring>(#"[^{}]*\{[^{}]*\}"#)) {
                let text = rule.output
                if text.contains("[data-pace"), text.contains("animation:") { throw CheckFailure.message("index.html animates a [data-pace] rule: \(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))") }
            }
            try expect(!page.contains("@keyframes breathe"), "the old breathe keyframes are gone")
        }

        suite.check("Every tremble() rate is a literal within the cap") {
            let motion = try String(contentsOf: petPage.appendingPathComponent("motion.js"), encoding: .utf8)
            let cap = motion.firstMatch(of: try Regex<(Substring, Substring)>(#"TREMBLE_MAX_RATE = (\d+(?:\.\d+)?)"#)).flatMap { Double($0.1) } ?? 0
            var bad: [String] = []
            for name in try petScripts() {
                let source = try String(contentsOf: petPage.appendingPathComponent(name), encoding: .utf8)
                for (line, argument) in trigArguments(of: try Regex<Substring>(#"(?:^|[^\w.])tremble\("#), in: source) {
                    let parts = argument.dropLast().split(separator: ",", maxSplits: 2)
                    let rate = parts.count > 1 ? Double(parts[1].trimmingCharacters(in: .whitespaces)) : nil
                    if rate.map({ $0 > cap }) ?? true { bad.append("Resources/Pet/\(name):\(line) tremble(\(argument)") }
                }
            }
            try expect(bad.isEmpty, "A tremble's rate must be a literal no faster than \(cap) rad/s:\n  " + bad.joined(separator: "\n  "))
        }
    }

    private static let petPage = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/Pet").standardizedFileURL

    /// The pet scripts that animate, body modules included, sorted; motion.js owns the shake and is exempt.
    private static func petScripts() throws -> [String] {
        let files = FileManager.default
        let page = try files.contentsOfDirectory(atPath: petPage.path).filter { $0.hasSuffix(".js") && $0 != "motion.js" }
        let bodies = try files.contentsOfDirectory(atPath: petPage.appendingPathComponent("bodies").path).filter { $0.hasSuffix(".js") }.map { "bodies/" + $0 }
        return (page + bodies).sorted()
    }

    private static let sineCall = try! Regex<Substring>(#"Math\.sin\("#)
    // `speed * t`, `rate * t`, `… * t * motion`, or `sin(t * someVariable` (or `cos`): a clock multiplied by a
    // rate that can change. SCREAMING_CASE names and TAU are constants and pass.
    private static let clockTimesVariable = try! Regex<Substring>(#"(?:(?:^|[^\w])(?:speed|rate)\s*\*\s*t(?![\w.])|\*\s*t\s*\*\s*motion(?!\w)|(?:^|[^\w])(?:sin|cos)\(\s*t\s*\*\s*(?!TAU(?!\w))[a-z_][\w.]*)"#)
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
