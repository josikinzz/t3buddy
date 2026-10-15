import AppKit
import ModelWidgetCore
import SwiftUI

/// One colour per provider, shared by every card that draws a provider (subscription bars, token graph).
/// Claude takes T3's tint `#d97757`, the colour of its mark on the orbit badges.
public enum ProviderPalette {
    public enum Swatch: Equatable {
        /// A fixed brand tint, `0xRRGGBB`.
        case rgb(UInt32)
        /// A system colour, so the provider follows light and dark appearance.
        case system(SystemColor)
    }

    public enum SystemColor: Equatable {
        case blue
        case teal
        case gray
    }

    public static let claudeTint: UInt32 = 0xD9_77_57

    /// Keyed by display name, the provider string `SubscriptionUsage` and `TokenProvider.displayName` share.
    public static func swatch(forProvider name: String) -> Swatch {
        switch name.lowercased() {
        case "claude": return .rgb(claudeTint)
        case "codex": return .system(.blue)
        case "kimi": return .system(.teal)
        default: return .system(.gray)
        }
    }

    public static func swatch(for provider: TokenProvider) -> Swatch {
        swatch(forProvider: provider.displayName)
    }

    public static func color(forProvider name: String) -> Color {
        color(swatch(forProvider: name))
    }

    public static func color(for provider: TokenProvider) -> Color {
        color(swatch(for: provider))
    }

    public static func color(_ swatch: Swatch) -> Color {
        switch swatch {
        case let .rgb(value):
            return Color(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
        case .system(.blue): return Color(nsColor: .systemBlue)
        case .system(.teal): return Color(nsColor: .systemTeal)
        case .system(.gray): return Color(nsColor: .systemGray)
        }
    }
}
