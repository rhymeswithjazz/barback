/// What the drawer under the dot is drawn on.
public enum DrawerBackground: String, CaseIterable, Sendable {
    /// The translucent menu material, as a menu is drawn: the original look.
    case menu
    /// Liquid Glass, as the menu bar and Control Center are drawn on macOS 27.
    case glass
    /// Liquid Glass's clear style: more of what is behind shows through.
    case clearGlass
    /// The window background color, with nothing showing through.
    case solid

    public static let `default` = DrawerBackground.menu

    /// Reads the stored value; anything missing or unknown is the default.
    public init(storage: String?) {
        self = storage.flatMap(DrawerBackground.init(rawValue:)) ?? .default
    }

    public var storage: String { rawValue }

    public var title: String {
        switch self {
        case .menu: "Menu"
        case .glass: "Liquid Glass"
        case .clearGlass: "Clear Glass"
        case .solid: "Solid"
        }
    }
}
