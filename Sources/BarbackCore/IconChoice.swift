import Foundation

/// What Barback shows in the menu bar: an SF Symbol by name, or an image the user picked.
public enum IconChoice: Equatable, Sendable {
    case symbol(String)
    /// The image Barback keeps a copy of (see `StatusIcon` in the app).
    case image

    /// The dot Barback starts with.
    public static let standard = IconChoice.symbol("circle.fill")

    // In user defaults: "image", or "symbol:<name>".
    public init(storage: String?) {
        guard let storage else {
            self = .standard
            return
        }
        if storage == "image" {
            self = .image
        } else if storage.hasPrefix("symbol:"), storage.count > 7 {
            self = .symbol(String(storage.dropFirst(7)))
        } else {
            self = .standard
        }
    }

    public var storage: String {
        switch self {
        case .symbol(let name): "symbol:\(name)"
        case .image: "image"
        }
    }
}

/// The symbols offered in Settings, and how symbols are drawn in the menu bar.
public enum IconCatalog {
    public struct Entry: Equatable, Sendable {
        public let symbol: String
        public let title: String
    }

    public static let curated: [Entry] = [
        Entry(symbol: "circle.fill", title: "Dot"),
        Entry(symbol: "ellipsis", title: "Ellipsis"),
        Entry(symbol: "chevron.left", title: "Chevron"),
        Entry(symbol: "chevron.left.2", title: "Double Chevron"),
        Entry(symbol: "chevron.compact.left", title: "Thin Chevron"),
        Entry(symbol: "arrowtriangle.left.fill", title: "Triangle"),
        Entry(symbol: "line.3.horizontal", title: "Lines"),
        Entry(symbol: "circle.grid.2x2.fill", title: "Grid"),
        Entry(symbol: "square.grid.2x2.fill", title: "Squares"),
        Entry(symbol: "archivebox.fill", title: "Box"),
        Entry(symbol: "tray.fill", title: "Tray"),
        Entry(symbol: "shippingbox.fill", title: "Crate"),
        Entry(symbol: "wineglass.fill", title: "Glass"),
        Entry(symbol: "mug.fill", title: "Mug"),
        Entry(symbol: "eye.slash.fill", title: "Eye"),
        Entry(symbol: "sidebar.left", title: "Sidebar"),
        Entry(symbol: "menubar.rectangle", title: "Menu Bar"),
        Entry(symbol: "star.fill", title: "Star"),
        Entry(symbol: "heart.fill", title: "Heart"),
        Entry(symbol: "bolt.fill", title: "Bolt"),
        Entry(symbol: "moon.fill", title: "Moon"),
        Entry(symbol: "sparkle", title: "Sparkle"),
        Entry(symbol: "diamond.fill", title: "Diamond"),
        Entry(symbol: "hexagon.fill", title: "Hexagon"),
    ]

    /// The size and weight a symbol is drawn at. The dot and ring stay as small as a menu bar
    /// indicator; every other symbol is the size of the items around it. The ellipsis and the
    /// lines are too faint at the regular weight, so they are bold too.
    public static func metrics(for symbol: String) -> (pointSize: Double, isBold: Bool) {
        if ["circle.fill", "circle"].contains(symbol) { return (7, true) }
        return (14, ["ellipsis", "line.3.horizontal"].contains(symbol))
    }

    /// Names to try for a symbol's open state, best first; the first that exists is used, and
    /// a symbol with none is dimmed instead.
    ///
    /// - A crossed-out symbol loses its slash: `eye.slash.fill` opens to `eye.fill`.
    /// - A symbol that points left points right: `chevron.left` opens to `chevron.right`.
    /// - A filled symbol opens to its outline and an outline to its fill: `circle.fill` to
    ///   `circle`, `star` to `star.fill`.
    public static func openCandidates(for symbol: String) -> [String] {
        let parts = symbol.split(separator: ".").map(String.init)
        var candidates: [String] = []
        if parts.contains("slash") {
            candidates.append(parts.filter { $0 != "slash" }.joined(separator: "."))
        }
        let swaps = ["left": "right", "right": "left", "backward": "forward", "forward": "backward"]
        if parts.contains(where: { swaps[$0] != nil }) {
            candidates.append(parts.map { swaps[$0] ?? $0 }.joined(separator: "."))
        }
        if let index = parts.lastIndex(of: "fill") {
            var outline = parts
            outline.remove(at: index)
            candidates.append(outline.joined(separator: "."))
        } else if let first = parts.first {
            candidates.append(symbol + ".fill")
            // `square.on.square` fills as `square.fill.on.square`.
            if parts.count > 1 {
                candidates.append(([first, "fill"] + parts.dropFirst()).joined(separator: "."))
            }
        }
        return candidates.filter { !$0.isEmpty && $0 != symbol }
    }
}
