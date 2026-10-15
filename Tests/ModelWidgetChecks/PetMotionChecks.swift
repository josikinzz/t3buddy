import Foundation

extension ModelWidgetChecks {
    static func petMotionChecks(_ suite: inout CheckSuite) async {
        suite.check("Pet scripts shake through tremble(), never a raw Math.sin faster than its cap") {
            let page = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/Pet").standardizedFileURL
            let motion = try String(contentsOf: page.appendingPathComponent("motion.js"), encoding: .utf8)
            guard let cap = motion.firstMatch(of: try Regex<(Substring, Substring)>(#"TREMBLE_MAX_RATE = (\d+(?:\.\d+)?)"#)).flatMap({ Double($0.1) }) else {
                throw CheckFailure.message("Resources/Pet/motion.js must export TREMBLE_MAX_RATE")
            }
            var buzzes: [String] = []
            let scripts = try FileManager.default.contentsOfDirectory(atPath: page.path).filter { $0.hasSuffix(".js") && $0 != "motion.js" }.sorted()
            for name in scripts {
                let source = try String(contentsOf: page.appendingPathComponent(name), encoding: .utf8)
                for (line, rate) in rawSineRates(in: source) where rate > cap {
                    buzzes.append("Resources/Pet/\(name):\(line) Math.sin at \(rate) rad/s")
                }
            }
            try expect(buzzes.isEmpty, "Faster than \(cap) rad/s reads as a buzz; use tremble(t, rate) from Resources/Pet/motion.js:\n  " + buzzes.joined(separator: "\n  "))
        }
    }

    // A literal on either side of a `*` (a regex literal can't hold `*/`).
    private static let multipliedLiteral = try! Regex<(Substring, Substring?, Substring?)>(#"\*\s*(\d+(?:\.\d+)?)(?![\d.])|(?:^|[^\w.])(\d+(?:\.\d+)?)\s*\*"#)

    /// Every numeric literal that multiplies inside a `Math.sin(...)` argument, with its line.
    static func rawSineRates(in source: String) -> [(line: Int, rate: Double)] {
        var found: [(Int, Double)] = []
        var index = source.startIndex
        while let call = source.range(of: "Math.sin(", range: index..<source.endIndex) {
            var depth = 1
            var end = call.upperBound
            while end < source.endIndex, depth > 0 {
                if source[end] == "(" { depth += 1 } else if source[end] == ")" { depth -= 1 }
                end = source.index(after: end)
            }
            let argument = source[call.upperBound..<end]
            let line = source[..<call.lowerBound].reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
            for match in argument.matches(of: multipliedLiteral) {
                if let rate = Double(match.1 ?? match.2 ?? "") { found.append((line, rate)) }
            }
            index = end
        }
        return found
    }
}
