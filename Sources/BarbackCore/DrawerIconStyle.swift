import CoreGraphics


/// How the drawer draws each item.
public enum DrawerIconStyle: String, CaseIterable, Sendable {
    /// The app's own full-colour icon: the original look.
    case fullColor
    /// The item's glyph as it was last seen in the menu bar, in the label colour. Seeing it
    /// takes Screen Recording; an item not seen yet keeps its app icon.
    case singleColor

    public static let `default` = DrawerIconStyle.fullColor

    /// Reads the stored value; anything missing or unknown is the default.
    public init(storage: String?) {
        self = storage.flatMap(DrawerIconStyle.init(rawValue:)) ?? .default
    }

    public var storage: String { rawValue }

    public var title: String {
        switch self {
        case .fullColor: "Full Color"
        case .singleColor: "Single Color"
        }
    }
}

/// Where a menu bar item is in a capture of the menu bar window that draws it.
public enum GlyphCrop {
    /// The item's slot in pixels of the window's capture, top-left origin, or nil when the
    /// slot is not inside the window. Frames are in points, top-left origin, as Accessibility
    /// and ScreenCaptureKit give them.
    public static func pixelRect(slot: CGRect, window: CGRect, scale: CGFloat) -> CGRect? {
        guard scale > 0, slot.width > 0, slot.height > 0 else { return nil }
        let inside = slot.intersection(window)
        guard !inside.isNull, inside.width >= slot.width / 2 else { return nil }
        return CGRect(x: (inside.minX - window.minX) * scale, y: (inside.minY - window.minY) * scale,
                      width: inside.width * scale, height: inside.height * scale).integral
    }
}
