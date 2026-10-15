import CoreGraphics
import Foundation
import LocalModelWidgetPanel
import ModelWidgetCore

extension ModelWidgetChecks {
    static func reviewFixChecks(_ suite: inout CheckSuite) async {
        let keys = ["model", "usage", "process", "tokens"]
        let launch = Date(timeIntervalSince1970: 1_000_000)

        suite.check("Masonry repacks once placeholder cards report their settled heights") {
            var columns = MasonryColumns()
            // At launch the usage card has its cached rows; process and tokens show placeholders.
            let placeholder: [CGFloat] = [70, 400, 80, 120]
            let first = columns.assignment(keys: keys, heights: placeholder, ready: [true, true, false, false], columns: 2, gap: 16, now: launch)
            try expectEqual(first, [0, 1, 0, 0])
            try expect(columns.settled == false, "Placeholder heights must not freeze the columns")

            // The real heights arrive; the grid packs them as a fresh layout would instead of keeping the lopsided columns.
            let settledHeights: [CGFloat] = [70, 400, 470, 300]
            let settled = columns.assignment(keys: keys, heights: settledHeights, ready: [true, true, true, true], columns: 2, gap: 16, now: launch.addingTimeInterval(2))
            try expectEqual(settled, MasonryPlacement.assign(heights: settledHeights, columns: 2, gap: 16))
            try expectEqual(settled, [0, 1, 0, 1])
            try expect(columns.settled, "Every card ready settles the grid")
            let points = MasonryPlacement.stack(heights: settledHeights, assignment: settled, gap: 16)
            let left = MasonryPlacement.contentHeight(heights: zip(settledHeights, settled).filter { $0.1 == 0 }.map(\.0), points: zip(points, settled).filter { $0.1 == 0 }.map(\.0))
            let right = MasonryPlacement.contentHeight(heights: zip(settledHeights, settled).filter { $0.1 == 1 }.map(\.0), points: zip(points, settled).filter { $0.1 == 1 }.map(\.0))
            try expect(abs(left - right) < 200, "Settled columns must be balanced, got \(left) vs \(right)")
        }

        suite.check("Masonry keeps columns sticky after settling and still repacks on an order change") {
            var columns = MasonryColumns()
            let heights: [CGFloat] = [70, 400, 470, 300]
            _ = columns.assignment(keys: keys, heights: heights, ready: Array(repeating: true, count: 4), columns: 2, gap: 16, now: launch)
            // The usage card grows a lot; a fresh pack would move cards, the settled grid only pushes its own column down.
            let grown: [CGFloat] = [70, 900, 470, 300]
            try expect(MasonryPlacement.assign(heights: grown, columns: 2, gap: 16) != [0, 1, 0, 1], "The fixture must differ from a fresh pack")
            try expectEqual(columns.assignment(keys: keys, heights: grown, ready: Array(repeating: true, count: 4), columns: 2, gap: 16, now: launch.addingTimeInterval(60)), [0, 1, 0, 1])

            let reordered = ["tokens", "model", "usage", "process"]
            let reorderedHeights: [CGFloat] = [300, 70, 900, 470]
            try expectEqual(
                columns.assignment(keys: reordered, heights: reorderedHeights, ready: Array(repeating: true, count: 4), columns: 2, gap: 16, now: launch.addingTimeInterval(61)),
                MasonryPlacement.assign(heights: reorderedHeights, columns: 2, gap: 16)
            )
        }

        suite.check("Masonry stops waiting for a card that never leaves its placeholder") {
            var columns = MasonryColumns(settleInterval: 10)
            let ready = [true, true, true, false]
            _ = columns.assignment(keys: keys, heights: [70, 400, 470, 120], ready: ready, columns: 2, gap: 16, now: launch)
            try expect(columns.settled == false, "A loading card keeps the grid repacking at first")
            let late = columns.assignment(keys: keys, heights: [70, 400, 470, 120], ready: ready, columns: 2, gap: 16, now: launch.addingTimeInterval(10))
            try expect(columns.settled, "The settle deadline ends the warm-up")
            // From here a height change keeps the columns.
            try expectEqual(columns.assignment(keys: keys, heights: [70, 400, 470, 900], ready: ready, columns: 2, gap: 16, now: launch.addingTimeInterval(11)), late)
        }

        // 2026-10-14T15:30:00Z; fixture lines fall in the 15:00 UTC hour.
        let now = Date(timeIntervalSince1970: 1_791_991_800)
        let hour = Date(timeIntervalSince1970: 1_791_990_000)
        func claudeLine(id: String, input: Int, output: Int) -> String {
            #"{"type":"assistant","timestamp":"2026-10-14T15:12:05Z","message":{"id":"\#(id)","model":"claude-opus-5-5","usage":{"input_tokens":\#(input),"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":\#(output)}}}"#
        }
        func claudeRoot() throws -> (base: URL, file: URL) {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent("review-fix-checks-\(UUID().uuidString)")
            let dir = base.appendingPathComponent("projects/-Users-x-proj")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return (base, dir.appendingPathComponent("s.jsonl"))
        }
        func append(_ text: String, to url: URL) throws {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
        }
        func claudeBucket(_ snapshot: TokenUsageSnapshot) -> TokenCounts? {
            snapshot.buckets.first { $0.provider == .claude && $0.hour == hour }?.counts
        }

        await suite.check("token reader skips a line longer than its cap and still parses the lines after it") {
            let root = try claudeRoot()
            defer { try? FileManager.default.removeItem(at: root.base) }
            // 200 KiB of usage-looking text with no newline, against a 64 KiB cap.
            let giant = #"{"usage":{"# + String(repeating: "x", count: 200 << 10)
            let text = claudeLine(id: "msg_1", input: 10, output: 20) + "\n" + giant + "\n" + claudeLine(id: "msg_2", input: 1, output: 2) + "\n"
            try text.write(to: root.file, atomically: false, encoding: .utf8)
            let reader = TokenUsageReader(sources: [TokenLogSource(format: .claudeCode, root: root.base.appendingPathComponent("projects"))], maxLineBytes: 64 << 10)
            let snapshot = await reader.refresh(now: now)
            try expectEqual(claudeBucket(snapshot), TokenCounts(input: 11, output: 22))
            try expectEqual(snapshot.stats.linesSkipped, 1)
            try expectEqual(snapshot.stats.bytesRead, Int64(text.utf8.count))
        }

        await suite.check("token reader keeps skipping an over-long line across refreshes until its newline") {
            let root = try claudeRoot()
            defer { try? FileManager.default.removeItem(at: root.base) }
            // The giant line is still being written: no newline yet when the first refresh runs.
            try (claudeLine(id: "msg_1", input: 10, output: 20) + "\n" + #"{"usage":{"# + String(repeating: "y", count: 150 << 10))
                .write(to: root.file, atomically: false, encoding: .utf8)
            let reader = TokenUsageReader(sources: [TokenLogSource(format: .claudeCode, root: root.base.appendingPathComponent("projects"))], maxLineBytes: 64 << 10)
            let first = await reader.refresh(now: now)
            try expectEqual(claudeBucket(first), TokenCounts(input: 10, output: 20))
            try expectEqual(first.stats.linesSkipped, 0)

            // The giant line ends with a valid usage line; it would count if the reader forgot it was mid-line.
            try append(claudeLine(id: "msg_tail", input: 1_000, output: 1_000) + "\n" + claudeLine(id: "msg_2", input: 1, output: 2) + "\n", to: root.file)
            let second = await reader.refresh(now: now)
            try expectEqual(claudeBucket(second), TokenCounts(input: 11, output: 22))
            try expectEqual(second.stats.linesSkipped, 1)
        }

        await suite.check("token reader serves overlapping refreshes from one scan without doubling") {
            let root = try claudeRoot()
            defer { try? FileManager.default.removeItem(at: root.base) }
            try (claudeLine(id: "msg_1", input: 10, output: 20) + "\n").write(to: root.file, atomically: false, encoding: .utf8)
            let reader = TokenUsageReader(sources: [TokenLogSource(format: .claudeCode, root: root.base.appendingPathComponent("projects"))])
            async let a = reader.refresh(now: now)
            async let b = reader.refresh(now: now)
            let (first, second) = await (a, b)
            try expectEqual(claudeBucket(first), TokenCounts(input: 10, output: 20))
            try expectEqual(claudeBucket(second), TokenCounts(input: 10, output: 20))
            try expectEqual(TokenBucket(provider: .claude, hour: hour, counts: TokenCounts(input: 10, output: 20, cacheRead: 99)).fresh, 30)
        }

        suite.check("Claude is #d97757 on every card that draws a provider") {
            try expectEqual(ProviderPalette.swatch(forProvider: "Claude"), .rgb(0xD97757))
            try expectEqual(ProviderPalette.swatch(for: .claude), .rgb(0xD97757))
            for provider in TokenProvider.allCases {
                // The subscription card keys by display name, the token card by provider; both must agree.
                try expectEqual(ProviderPalette.swatch(for: provider), ProviderPalette.swatch(forProvider: provider.displayName))
            }
            let swatches = TokenProvider.allCases.map(ProviderPalette.swatch(for:))
            try expectEqual(Set(swatches.map { "\($0)" }).count, swatches.count)
        }

        await suite.check("Pixelated email mosaics render once per text and are reused on redraw") { @MainActor in
            let cache = MosaicCache(limit: 4)
            var renders = 0
            func render() -> CGImage? {
                renders += 1
                let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
                return context?.makeImage()
            }
            let key = MosaicCache.Key(text: "a@b.c", fontSize: 10, block: 3)
            let first = cache.image(for: key, render: render)
            let again = cache.image(for: key, render: render)
            try expect(first != nil && first === again, "A redraw must reuse the cached mosaic")
            try expectEqual(renders, 1)
            _ = cache.image(for: MosaicCache.Key(text: "d@e.f", fontSize: 10, block: 3), render: render)
            try expectEqual(renders, 2)
            _ = cache.image(for: MosaicCache.Key(text: "x@y.z", fontSize: 10, block: 3)) { nil }
            try expectEqual(cache.count, 2)
        }
    }
}
