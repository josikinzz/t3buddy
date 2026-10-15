import AppKit

/// A hit rectangle the pet page reports, in page CSS px with a top-left origin.
/// The page and the layer window share one size, so a CSS px is one point.
public struct PetHitRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func contains(_ point: CGPoint) -> Bool {
        point.x >= x && point.x <= x + width && point.y >= y && point.y <= y + height
    }
}

/// Pure placement and hit-test rules for T3boii's full-screen, click-through layer.
public enum PetLayerGeometry {
    public enum MessageError: Error, Equatable {
        case missingRects
    }

    /// The part of T3boii's stage that is kept on screen; keep in step with `KEEP` in
    /// `Resources/Pet/pet.js`. His position is the stage centre. The canvas itself is larger
    /// (room to swell, float and flail) and may run off the screen edge.
    public static let stageSize = CGSize(width: 640, height: 760)
    public static let positionDefaultsKey = "T3boiiPosition"

    /// One level above the Desktop-mode panels, so he floats over the cards
    /// but stays below every app window.
    public static var windowLevel: NSWindow.Level {
        NSWindow.Level(rawValue: DesktopPanelWindowMode.desktop.windowLevel.rawValue + 1)
    }

    public static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary
    ]

    /// The screen the dashboard lives on: the main screen, else the largest one.
    public static func layerFrame(mainScreen: CGRect?, screens: [CGRect]) -> CGRect? {
        mainScreen ?? screens.max { $0.width * $0.height < $1.width * $1.height }
    }

    /// Converts an AppKit screen point (bottom-left origin, global) to page CSS px.
    public static func pagePoint(screenPoint: CGPoint, layerFrame: CGRect) -> CGPoint {
        CGPoint(x: screenPoint.x - layerFrame.minX, y: layerFrame.maxY - screenPoint.y)
    }

    /// Whether the layer should take the mouse at `screenPoint`; elsewhere it is click-through.
    public static func catchesMouse(at screenPoint: CGPoint, layerFrame: CGRect, rects: [PetHitRect]) -> Bool {
        guard layerFrame.contains(screenPoint) else { return false }
        let point = pagePoint(screenPoint: screenPoint, layerFrame: layerFrame)
        return rects.contains { $0.contains(point) }
    }

    /// Whether the layer takes the mouse after an event. The state only changes
    /// while no button is held, so a drag that starts on T3boii keeps the mouse
    /// even when the cursor outruns him, and a desktop drag passing over him
    /// stays with the desktop.
    public static func catchesMouse(insideHitRegion inside: Bool, buttonDown: Bool, catchingNow: Bool) -> Bool {
        buttonDown ? catchingNow : inside
    }

    /// Decodes a `hitRegions` message body. Rects with a non-numeric or negative field are dropped.
    public static func hitRects(fromMessage body: [String: Any]) throws -> [PetHitRect] {
        guard let rects = body["rects"] as? [Any] else { throw MessageError.missingRects }
        return rects.compactMap { item in
            guard let rect = item as? [String: Any],
                  let x = number(rect["x"]), let y = number(rect["y"]),
                  let width = number(rect["width"]), let height = number(rect["height"]),
                  width >= 0, height >= 0 else { return nil }
            return PetHitRect(x: x, y: y, width: width, height: height)
        }
    }

    public static func defaultPosition(layerSize: CGSize) -> CGPoint {
        clamp(CGPoint(x: (layerSize.width * 0.3).rounded(), y: (layerSize.height * 0.72).rounded()), layerSize: layerSize)
    }

    /// Keeps the whole stage on the layer; a non-finite position falls back to the default.
    public static func clampedPosition(_ position: CGPoint, layerSize: CGSize) -> CGPoint {
        guard position.x.isFinite, position.y.isFinite else { return defaultPosition(layerSize: layerSize) }
        return clamp(position, layerSize: layerSize)
    }

    public static func encodePosition(_ position: CGPoint) -> [String: Double] {
        ["x": Double(position.x), "y": Double(position.y)]
    }

    public static func decodePosition(_ stored: [String: Any]?) -> CGPoint? {
        guard let stored, let x = number(stored["x"]), let y = number(stored["y"]) else { return nil }
        return CGPoint(x: x, y: y)
    }

    /// The position to start at: the stored one pulled onto this layer, else the default.
    public static func restoredPosition(stored: [String: Any]?, layerSize: CGSize) -> CGPoint {
        guard let position = decodePosition(stored) else { return defaultPosition(layerSize: layerSize) }
        return clampedPosition(position, layerSize: layerSize)
    }

    /// Orb links the layer may open: T3's web UI on this machine, over http(s).
    public static func isLocalThreadLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        return ["127.0.0.1", "localhost", "::1"].contains(url.host?.lowercased() ?? "") && url.user == nil
    }

    private static func clamp(_ position: CGPoint, layerSize: CGSize) -> CGPoint {
        let halfWidth = stageSize.width / 2
        let halfHeight = stageSize.height / 2
        return CGPoint(
            x: min(max(position.x, halfWidth), max(halfWidth, layerSize.width - halfWidth)),
            y: min(max(position.y, halfHeight), max(halfHeight, layerSize.height - halfHeight))
        )
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as NSNumber where CFGetTypeID(value) != CFBooleanGetTypeID():
            return value.doubleValue
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        default:
            return nil
        }
    }
}
