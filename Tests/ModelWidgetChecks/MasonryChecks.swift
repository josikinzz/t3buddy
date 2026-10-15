import AppKit
import Foundation
import LocalModelWidgetPanel

extension ModelWidgetChecks {
    static func masonryChecks(_ suite: inout CheckSuite) async {
        await suite.check("Masonry puts each card in the shortest column and keeps source order inside a column") {
            let points = MasonryPlacement.place(heights: [100, 300, 50, 80, 200], columns: 2, gap: 10)
            try expectEqual(points, [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 342, y: 0),
                CGPoint(x: 0, y: 110),
                CGPoint(x: 0, y: 170),
                CGPoint(x: 0, y: 260)
            ])
            // Equal columns break the tie to the left.
            try expectEqual(MasonryPlacement.place(heights: [50, 50, 50], columns: 2, gap: 10), [
                CGPoint(x: 0, y: 0), CGPoint(x: 342, y: 0), CGPoint(x: 0, y: 60)
            ])
            // Three columns sit one column width plus a gap apart.
            try expectEqual(MasonryPlacement.place(heights: [50, 80, 30, 40], columns: 3, gap: 10), [
                CGPoint(x: 0, y: 0), CGPoint(x: 342, y: 0), CGPoint(x: 684, y: 0), CGPoint(x: 684, y: 40)
            ])
            // Gaps count toward a column's height: two 50s plus a gap is taller than one 105.
            try expectEqual(MasonryPlacement.assign(heights: [50, 105, 50, 10], columns: 2, gap: 10), [0, 1, 0, 1])
            try expectEqual(MasonryPlacement.contentHeight(heights: [100, 300, 50, 80, 200], points: points), 460)
            try expectEqual(MasonryPlacement.place(heights: [], columns: 2, gap: 10), [])
            try expectEqual(MasonryPlacement.place(heights: [40, 40], columns: 0, gap: 10), [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 50)])
        }

        await suite.check("Masonry keeps column assignment when a card grows and repacks when the order changes") {
            var columns = MasonryColumns()
            let keys = ["model", "usage", "process"]
            try expectEqual(columns.assignment(keys: keys, heights: [100, 200, 50], columns: 2, gap: 10), [0, 1, 0])
            let before = MasonryPlacement.stack(heights: [100, 200, 50], assignment: [0, 1, 0], gap: 10)

            // A fresh pack would move "process" to column 1; the grid keeps it under "model".
            try expectEqual(MasonryPlacement.assign(heights: [300, 200, 50], columns: 2, gap: 10), [0, 1, 1])
            let kept = columns.assignment(keys: keys, heights: [300, 200, 50], columns: 2, gap: 10)
            try expectEqual(kept, [0, 1, 0])
            let after = MasonryPlacement.stack(heights: [300, 200, 50], assignment: kept, gap: 10)
            try expectEqual(after[0], before[0])
            try expectEqual(after[1], before[1])
            try expectEqual(after[2], CGPoint(x: before[2].x, y: before[2].y + 200))

            try expectEqual(columns.assignment(keys: ["usage", "model", "process"], heights: [200, 300, 50], columns: 2, gap: 10), [0, 1, 0])
            try expectEqual(columns.assignment(keys: ["usage", "model", "process"], heights: [200, 300, 50], columns: 1, gap: 10), [0, 0, 0])
        }

        await suite.check("Dashboard fits three 332 pt columns on the portrait screen and anchors top right") {
            try expectEqual(DashboardLayout.columnWidth, 332)
            try expectEqual(DashboardLayout.columnCount(screenWidth: 1080), 3)
            try expectEqual(DashboardLayout.columnCount(screenWidth: 2560), 3)
            try expectEqual(DashboardLayout.columnCount(screenWidth: 1000), 2)
            try expectEqual(DashboardLayout.columnCount(screenWidth: 700), 1)
            try expectEqual(DashboardLayout.columnCount(screenWidth: 200), 1)
            try expectEqual(DashboardLayout.gridWidth(columns: 3), 1028)
            try expect(DashboardLayout.gridWidth(columns: 3) <= 1080 - DashboardLayout.screenMargin * 2, "Three columns fit inside the screen margins")

            let visible = NSRect(x: 0, y: 0, width: 1080, height: 1890)
            let frame = DashboardLayout.windowFrame(contentSize: CGSize(width: 1028, height: 1000), visibleFrame: visible)
            let inset = DashboardLayout.shadowInset
            try expectEqual(frame.size, CGSize(width: 1028 + inset * 2, height: 1000 + inset * 2))
            try expectEqual(frame.maxX - inset, visible.maxX - DashboardLayout.screenMargin)
            try expectEqual(frame.maxY - inset, visible.maxY - DashboardLayout.topMargin)
            let tall = DashboardLayout.windowFrame(contentSize: CGSize(width: 1028, height: 5000), visibleFrame: visible)
            try expectEqual(tall.minY, visible.minY)
            try expectEqual(tall.maxY - inset, visible.maxY - DashboardLayout.topMargin)
        }

        await suite.check("Dashboard window grows downward from a fixed top until it fills the visible frame") {
            // The live portrait screen: 1080 x 1920 with a 30 pt menu bar.
            let visible = NSRect(x: 0, y: 0, width: 1080, height: 1890)
            let inset = DashboardLayout.shadowInset
            let short = DashboardLayout.windowFrame(contentSize: CGSize(width: 1028, height: 400), visibleFrame: visible)
            let grown = DashboardLayout.windowFrame(contentSize: CGSize(width: 1028, height: 890), visibleFrame: visible)
            try expectEqual(grown.maxY, short.maxY)
            try expectEqual(grown.maxX, short.maxX)
            try expectEqual(grown.height, 890 + inset * 2)
            try expectEqual(grown.minY, short.minY - 490)
            // The grid's top edge sits 32 pt under the visible frame top, and the window never leaves the screen.
            try expectEqual(grown.maxY - inset, visible.maxY - 32)
            try expect(grown.minY >= visible.minY, "Window must stay on screen")
            let huge = DashboardLayout.windowFrame(contentSize: CGSize(width: 1028, height: 4000), visibleFrame: visible)
            try expectEqual(huge.maxY, short.maxY)
            try expectEqual(huge.minY, visible.minY)
        }

        await suite.check("Dashboard card order drops unknown ids, appends new cards, and survives a relaunch") {
            try expectEqual(DashboardCardOrder.resolve(nil), DashboardCard.allCases)
            try expectEqual(DashboardCardOrder.resolve(["process", "storage", "model", "process"]), [.process, .model, .usage, .tokens])
            try expect(DashboardCard(rawValue: "storage") == nil, "Disk Space must not be a dashboard card")

            let order: [DashboardCard] = [.model, .usage, .process, .tokens]
            try expectEqual(DashboardCardOrder.move(.model, onto: .process, in: order), [.usage, .process, .model, .tokens])
            try expectEqual(DashboardCardOrder.move(.tokens, onto: .usage, in: order), [.model, .tokens, .usage, .process])
            try expectEqual(DashboardCardOrder.move(.usage, onto: .usage, in: order), order)

            let suiteName = "ModelWidgetChecks.dashboard.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defer { defaults.removePersistentDomain(forName: suiteName) }
            try expectEqual(DashboardCardOrder.load(from: defaults), DashboardCard.allCases)
            DashboardCardOrder.save([.process, .usage, .model], to: defaults)
            let relaunched = UserDefaults(suiteName: suiteName)!
            try expectEqual(DashboardCardOrder.load(from: relaunched), [.process, .usage, .model, .tokens])
            try expectEqual(relaunched.stringArray(forKey: DashboardCardOrder.defaultsKey), ["process", "usage", "model"])
        }
    }
}
