import CoreGraphics

/// Keeps the pixelated mosaic of a string so a redraw reuses it instead of rendering again.
///
/// The mosaic is drawn black and shown as a template image, so the view tints it for light or dark appearance;
/// the appearance therefore does not change the bitmap and is not part of the key.
@MainActor
public final class MosaicCache {
    public struct Key: Hashable {
        public let text: String
        public let fontSize: CGFloat
        /// Points per mosaic block; the text is rendered at `1 / block` scale.
        public let block: CGFloat

        public init(text: String, fontSize: CGFloat, block: CGFloat) {
            self.text = text
            self.fontSize = fontSize
            self.block = block
        }
    }

    public static let shared = MosaicCache()

    private var images: [Key: CGImage] = [:]
    private let limit: Int

    public init(limit: Int = 64) {
        self.limit = max(1, limit)
    }

    public var count: Int { images.count }

    /// The cached mosaic for `key`, rendering it with `render` only on a miss. A failed render is not cached.
    public func image(for key: Key, render: () -> CGImage?) -> CGImage? {
        if let image = images[key] { return image }
        guard let image = render() else { return nil }
        if images.count >= limit {
            images.removeAll(keepingCapacity: true)
        }
        images[key] = image
        return image
    }
}
