import Foundation

/// Which pet the page shows. Raw values are the page's kind strings (`window.__t3boiiConfig.pet`).
public enum PetKind: String, CaseIterable, Sendable {
    case t3boii
    case shoggoth

    public static let defaultsKey = "petKind"

    /// A missing or unknown stored kind is T3boii.
    public init(stored: String?) {
        self = stored.flatMap(PetKind.init(rawValue:)) ?? .t3boii
    }

    public var displayName: String {
        switch self {
        case .t3boii: "T3boii"
        case .shoggoth: "Shoggoth"
        }
    }
}

/// The shoggoth's eye tint, always a lower-case `#rrggbb`, so it is safe to put into page script.
public struct PetTint: Hashable, Sendable {
    public static let defaultsKey = "shoggothTint"
    public static let `default` = PetTint(validated: "#ff0000")

    public struct Preset: Hashable, Sendable {
        public let name: String
        public let tint: PetTint
    }

    /// The gear menu's choices; the first is the default.
    public static let presets: [Preset] = [
        Preset(name: "Red", tint: .default),
        Preset(name: "Amber", tint: PetTint(validated: "#ffb020")),
        Preset(name: "Green", tint: PetTint(validated: "#3ddc84")),
        Preset(name: "Cyan", tint: PetTint(validated: "#40c8e0")),
        Preset(name: "Violet", tint: PetTint(validated: "#a970ff")),
        Preset(name: "White", tint: PetTint(validated: "#f5f5f7"))
    ]

    public let hex: String

    private init(validated hex: String) {
        self.hex = hex
    }

    /// Accepts `#rrggbb` in any case with surrounding whitespace; anything else is the default.
    public init(parsing text: String?) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        // Character.isHexDigit also passes fullwidth digits, so check the ASCII bytes.
        let digits = trimmed.utf8.dropFirst()
        let valid = trimmed.hasPrefix("#") && digits.count == 6 && digits.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
        self = valid ? PetTint(validated: trimmed) : .default
    }

    /// sRGB components in 0...1, as a colour picker reports them; out-of-range values are clamped.
    public init(red: Double, green: Double, blue: Double) {
        let byte = { (component: Double) in Int((min(1, max(0, component.isFinite ? component : 0)) * 255).rounded()) }
        self.init(validated: String(format: "#%02x%02x%02x", byte(red), byte(green), byte(blue)))
    }

    public var components: (red: Double, green: Double, blue: Double) {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        return (Double(value >> 16 & 0xff) / 255, Double(value >> 8 & 0xff) / 255, Double(value & 0xff) / 255)
    }
}

/// The `window.__t3boiiConfig` the page reads before any of its scripts run.
public enum PetPageConfig {
    public static func script(position: [String: Double], reducedMotion: Bool, muted: Bool, pet: PetKind, tint: PetTint) -> String? {
        let config: [String: Any] = ["position": position, "reducedMotion": reducedMotion, "muted": muted, "pet": pet.rawValue, "tint": tint.hex]
        guard let data = try? JSONSerialization.data(withJSONObject: config, options: [.sortedKeys]), let json = String(data: data, encoding: .utf8) else { return nil }
        return "window.__t3boiiConfig = \(json);"
    }
}
