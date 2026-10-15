import Foundation

/// How a card hides an account email: a pixelated mosaic until clicked, revealed for `revealSeconds`.
/// Where a mosaic cannot be drawn (a menu item, a failed render) the email reads as bullets instead.
public enum EmailMask {
    public static let revealSeconds: Double = 10

    /// One bullet per character, capped at 18 so a long address does not widen its row.
    public static func bullets(for email: String) -> String {
        String(repeating: "•", count: min(email.count, 18))
    }
}
