import Foundation
import ModelWidgetCore

extension ModelWidgetChecks {
    static func feedFlagsChecks(_ suite: inout CheckSuite) async {
        suite.check("Feed flags: queue and seeds are on unless dropped with -queue or -seeds") {
            try expectEqual(FeedFlags.parse(nil).on, ["queue", "seeds"])
            try expectEqual(FeedFlags.parse("").on, ["queue", "seeds"])
            try expectEqual(FeedFlags.parse("-seeds").on, ["queue"])
            try expectEqual(FeedFlags.parse("-queue").on, ["seeds"])
            try expectEqual(FeedFlags.parse("-queue, -seeds").on, [])
            try expectEqual(FeedFlags.parse("-seeds,seeds").on, ["queue", "seeds"])
            try expectEqual(FeedFlags.parse("-queue, -seeds").unknown, [])
        }

        suite.check("Feed flags: a name that switches no part is reported and changes nothing, so a typo cannot pass for a setting") {
            let typo = FeedFlags.parse("-seed, sedes, pr, -queue")
            try expectEqual(typo.unknown, ["-seed", "sedes", "pr"])
            try expectEqual(typo.on, ["seeds"])
        }

        suite.check("Feed flags: the helper is handed only the known parts, and nothing when they are the standard ones") {
            try expectEqual(FeedFlags.parse(nil).argument, nil)
            try expectEqual(FeedFlags.parse("queue, typo").argument, nil)
            try expectEqual(FeedFlags.parse("-seeds, typo").argument, "-seeds")
            try expectEqual(FeedFlags.parse(FeedFlags.parse("-queue,-seeds").argument).on, [])
        }
    }
}
