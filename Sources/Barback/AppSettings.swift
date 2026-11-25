import BarbackCore
import Foundation

/// What the user chose in Settings, kept in user defaults.
///
/// The controller sets the `on…Change` closures to act on a change as it is made.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let icon = "icon"
        static let hotkey = "hotkey"
        static let autoClose = "autoCloseSeconds"
        static let drawerBackground = "drawerBackground"
        static let drawerIconStyle = "drawerIconStyle"
    }

    private let defaults = UserDefaults.standard

    /// The icon in the menu bar.
    @Published var icon: IconChoice {
        didSet {
            guard icon != oldValue else { return }
            defaults.set(icon.storage, forKey: Key.icon)
            onIconChange?()
        }
    }

    /// Counts the images chosen since launch, so views draw a new one under the same choice.
    @Published private(set) var imageRevision = 0

    /// The shortcut that opens and closes Barback; nil for none.
    @Published var hotkey: Hotkey? {
        didSet {
            guard hotkey != oldValue else { return }
            if let hotkey {
                defaults.set(hotkey.storage, forKey: Key.hotkey)
            } else {
                defaults.removeObject(forKey: Key.hotkey)
            }
            onHotkeyChange?()
        }
    }

    /// Seconds an open Barback is left unused before it closes; zero never closes it.
    @Published var autoCloseSeconds: Int {
        didSet {
            guard autoCloseSeconds != oldValue else { return }
            defaults.set(autoCloseSeconds, forKey: Key.autoClose)
            onAutoCloseChange?()
        }
    }

    /// What the drawer is drawn on.
    @Published var drawerBackground: DrawerBackground {
        didSet {
            guard drawerBackground != oldValue else { return }
            defaults.set(drawerBackground.storage, forKey: Key.drawerBackground)
            onDrawerBackgroundChange?()
        }
    }

    /// How the drawer draws its items.
    @Published var drawerIconStyle: DrawerIconStyle {
        didSet {
            guard drawerIconStyle != oldValue else { return }
            defaults.set(drawerIconStyle.storage, forKey: Key.drawerIconStyle)
            onDrawerIconStyleChange?()
        }
    }

    var onIconChange: (() -> Void)?
    var onDrawerIconStyleChange: (() -> Void)?
    var onDrawerBackgroundChange: (() -> Void)?
    var onHotkeyChange: (() -> Void)?
    var onAutoCloseChange: (() -> Void)?

    private init() {
        icon = IconChoice(storage: defaults.string(forKey: Key.icon))
        hotkey = Hotkey(storage: defaults.dictionary(forKey: Key.hotkey))
        autoCloseSeconds = max(0, defaults.integer(forKey: Key.autoClose))
        drawerBackground = DrawerBackground(storage: defaults.string(forKey: Key.drawerBackground))
        drawerIconStyle = DrawerIconStyle(storage: defaults.string(forKey: Key.drawerIconStyle))
    }

    /// A new image was chosen: it becomes the icon.
    func useChosenImage() {
        imageRevision += 1
        if icon == .image {
            onIconChange?()
        } else {
            icon = .image
        }
    }
}
