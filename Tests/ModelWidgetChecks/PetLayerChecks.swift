import AppKit
import Foundation
import LocalModelWidgetPanel

extension ModelWidgetChecks {
    static func petLayerChecks(_ suite: inout CheckSuite) async {
        suite.check("Pet layer maps AppKit screen points to page CSS px with a top-left origin") {
            // A portrait screen that does not start at the global origin.
            let layer = CGRect(x: 1920, y: -400, width: 1080, height: 1920)
            let topLeft = PetLayerGeometry.pagePoint(screenPoint: CGPoint(x: 1920, y: 1520), layerFrame: layer)
            try expectEqual(topLeft, CGPoint(x: 0, y: 0))
            let inside = PetLayerGeometry.pagePoint(screenPoint: CGPoint(x: 2020, y: 1320), layerFrame: layer)
            try expectEqual(inside, CGPoint(x: 100, y: 200))
            let bottomRight = PetLayerGeometry.pagePoint(screenPoint: CGPoint(x: 3000, y: -400), layerFrame: layer)
            try expectEqual(bottomRight, CGPoint(x: 1080, y: 1920))
        }

        suite.check("Pet layer catches clicks only inside T3boii's hit rects") {
            let layer = CGRect(x: 0, y: 0, width: 1080, height: 1920)
            let rects = [
                PetHitRect(x: 300, y: 1000, width: 200, height: 40),
                PetHitRect(x: 340, y: 1040, width: 120, height: 40)
            ]
            // Page (400, 1020) is AppKit (400, 900).
            try expect(PetLayerGeometry.catchesMouse(at: CGPoint(x: 400, y: 900), layerFrame: layer, rects: rects), "Point on his head must be caught")
            // Page (310, 1060) sits beside the narrower lower band.
            try expect(!PetLayerGeometry.catchesMouse(at: CGPoint(x: 310, y: 860), layerFrame: layer, rects: rects), "Point beside him must pass through")
            try expect(!PetLayerGeometry.catchesMouse(at: CGPoint(x: 900, y: 100), layerFrame: layer, rects: rects), "Far point must pass through")
            try expect(!PetLayerGeometry.catchesMouse(at: CGPoint(x: 400, y: 900), layerFrame: layer, rects: []), "No rects means fully click-through")
            // Outside the layer never catches, even if a rect strays past its edge.
            let stray = [PetHitRect(x: -50, y: -50, width: 2000, height: 2000)]
            try expect(!PetLayerGeometry.catchesMouse(at: CGPoint(x: -10, y: 900), layerFrame: layer, rects: stray), "Point off the layer must pass through")
        }

        suite.check("Pet layer keeps the mouse through a drag and only switches with the button up") {
            try expect(PetLayerGeometry.catchesMouse(insideHitRegion: true, buttonDown: false, catchingNow: false), "Hovering him takes the mouse")
            try expect(!PetLayerGeometry.catchesMouse(insideHitRegion: false, buttonDown: false, catchingNow: true), "Leaving him releases the mouse")
            try expect(PetLayerGeometry.catchesMouse(insideHitRegion: false, buttonDown: true, catchingNow: true), "A drag that outruns him keeps the mouse")
            try expect(!PetLayerGeometry.catchesMouse(insideHitRegion: true, buttonDown: true, catchingNow: false), "A desktop drag over him stays with the desktop")
        }

        suite.check("Pet layer decodes the page's hit-region message and drops bad rects") {
            let body: [String: Any] = [
                "type": "hitRegions",
                "rects": [
                    ["x": 10, "y": 20.5, "width": 30, "height": 40],
                    ["x": 1, "y": 2, "width": -3, "height": 4],
                    ["x": "nope", "y": 2, "width": 3, "height": 4],
                    ["x": 5, "y": 6, "width": 7, "height": 8.25]
                ],
                "viewport": ["width": 1080, "height": 1920]
            ]
            let rects = try PetLayerGeometry.hitRects(fromMessage: body)
            try expectEqual(rects, [
                PetHitRect(x: 10, y: 20.5, width: 30, height: 40),
                PetHitRect(x: 5, y: 6, width: 7, height: 8.25)
            ])
            try expect((try? PetLayerGeometry.hitRects(fromMessage: ["type": "hitRegions"])) == nil, "Missing rects must throw")
        }

        suite.check("Pet position persists as x/y and clamps so the whole stage stays on screen") {
            let layer = CGSize(width: 1080, height: 1920)
            let stage = PetLayerGeometry.stageSize
            let stored = PetLayerGeometry.encodePosition(CGPoint(x: 512.4, y: 300))
            try expectEqual(stored["x"], 512.4)
            try expectEqual(stored["y"], 300)
            try expectEqual(PetLayerGeometry.decodePosition(stored), CGPoint(x: 512.4, y: 300))
            try expect(PetLayerGeometry.decodePosition(["x": 1]) == nil, "A half-stored position must be ignored")
            try expect(PetLayerGeometry.decodePosition(nil) == nil, "No stored position yields nil")

            let inside = PetLayerGeometry.clampedPosition(CGPoint(x: 512, y: 600), layerSize: layer)
            try expectEqual(inside, CGPoint(x: 512, y: 600))
            let offTopLeft = PetLayerGeometry.clampedPosition(CGPoint(x: -400, y: 2), layerSize: layer)
            try expectEqual(offTopLeft, CGPoint(x: stage.width / 2, y: stage.height / 2))
            // A position saved on a larger screen is pulled back onto a smaller one.
            let offBottomRight = PetLayerGeometry.clampedPosition(CGPoint(x: 3000, y: 5000), layerSize: layer)
            try expectEqual(offBottomRight, CGPoint(x: 1080 - stage.width / 2, y: 1920 - stage.height / 2))
            let nonFinite = PetLayerGeometry.clampedPosition(CGPoint(x: CGFloat.nan, y: 300), layerSize: layer)
            try expectEqual(nonFinite, PetLayerGeometry.defaultPosition(layerSize: layer))
        }

        suite.check("Pet restore uses the default spot when nothing is stored") {
            let layer = CGSize(width: 1080, height: 1920)
            let restored = PetLayerGeometry.restoredPosition(stored: nil, layerSize: layer)
            try expectEqual(restored, PetLayerGeometry.defaultPosition(layerSize: layer))
            let fromDefaults = PetLayerGeometry.restoredPosition(stored: ["x": 5000, "y": 800], layerSize: layer)
            try expectEqual(fromDefaults, CGPoint(x: 1080 - PetLayerGeometry.stageSize.width / 2, y: 800))
        }

        suite.check("Pet layer covers the main screen, or the largest when there is none") {
            let portrait = CGRect(x: 0, y: 0, width: 1080, height: 1920)
            let small = CGRect(x: 1080, y: 0, width: 800, height: 600)
            try expectEqual(PetLayerGeometry.layerFrame(mainScreen: small, screens: [portrait, small]), small)
            try expectEqual(PetLayerGeometry.layerFrame(mainScreen: nil, screens: [small, portrait]), portrait)
            try expectEqual(PetLayerGeometry.layerFrame(mainScreen: nil, screens: []), nil)
        }

        suite.check("Pet layer sits just above the desktop panels and joins every space") {
            try expectEqual(PetLayerGeometry.windowLevel.rawValue, DesktopPanelWindowMode.desktop.windowLevel.rawValue + 1)
            try expect(PetLayerGeometry.windowLevel.rawValue < NSWindow.Level.normal.rawValue, "Pet must stay below app windows")
            try expect(PetLayerGeometry.collectionBehavior.contains(.canJoinAllSpaces), "Pet must join all spaces")
            try expect(PetLayerGeometry.collectionBehavior.contains(.stationary), "Pet must not slide with space switches")
        }
    }
}
