import AppKit

/// The menu bar item is drawn as one template image: the earbuds glyph plus, when a mode is known,
/// a smaller glyph for it. `MenuBarExtra` drops the image of a `Text` that interpolates one,
/// so composing into a single `NSImage` is what makes both show up.
enum MenuBarIcon {
    static let height: CGFloat = 18
    static let spacing: CGFloat = 2

    /// - Parameters:
    ///   - modeSymbol: SF Symbol for the current mode, or nil to show the earbuds alone.
    ///   - dimmed: the earbuds are not reachable.
    ///   - modePending: a change was sent and not confirmed yet.
    static func image(modeSymbol: String?, dimmed: Bool, modePending: Bool, accessibilityLabel: String) -> NSImage {
        let budsConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let modeConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        var parts: [(NSImage, CGFloat)] = []
        if let buds = NSImage(systemSymbolName: "earbuds", accessibilityDescription: nil)?.withSymbolConfiguration(budsConfig) {
            parts.append((buds, dimmed ? 0.4 : 1))
        }
        if let modeSymbol, let glyph = NSImage(systemSymbolName: modeSymbol, accessibilityDescription: nil)?.withSymbolConfiguration(modeConfig) {
            parts.append((glyph, modePending ? 0.45 : 1))
        }
        let width = parts.map(\.0.size.width).reduce(0, +) + spacing * CGFloat(max(parts.count - 1, 0))
        let image = NSImage(size: NSSize(width: ceil(width), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for (part, alpha) in parts {
                let y = (height - part.size.height) / 2
                part.draw(in: NSRect(x: x, y: y, width: part.size.width, height: part.size.height),
                          from: .zero, operation: .sourceOver, fraction: alpha)
                x += part.size.width + spacing
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityLabel
        return image
    }
}
