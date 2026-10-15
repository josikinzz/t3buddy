import LocalModelWidgetPanel
import ModelWidgetCore
import SwiftUI

/// Draws text as a mosaic: rendered at 1/block scale, then scaled back up without smoothing.
/// A hidden copy of the text sets the layout size, so revealing the text does not move the row.
/// The mosaic is rendered once per text, size and block and reused from `MosaicCache` on every redraw.
struct PixelatedText: View {
    var text: String
    var fontSize: CGFloat
    var block: CGFloat = 3
    var body: some View {
        let font = Font.system(size: fontSize)
        return Text(text).font(font).lineLimit(1).hidden().overlay(alignment: .leading) {
            if let image = Self.mosaic(text, fontSize: fontSize, block: block) {
                image
            } else {
                Text(EmailMask.bullets(for: text)).font(font)
            }
        }
    }

    /// The mosaic as an `Image`, so it can also sit inline in a `Text`. Nil when the render fails.
    @MainActor
    static func mosaic(_ text: String, fontSize: CGFloat, block: CGFloat = 3) -> Image? {
        let cgImage = MosaicCache.shared.image(for: MosaicCache.Key(text: text, fontSize: fontSize, block: block)) {
            let renderer = ImageRenderer(content: Text(text).font(.system(size: fontSize)).foregroundStyle(.black).fixedSize())
            renderer.scale = 1 / block
            return renderer.cgImage
        }
        return cgImage.map { Image(decorative: $0, scale: 1 / block).renderingMode(.template).interpolation(.none) }
    }
}
