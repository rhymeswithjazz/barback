import Foundation

/// A keyboard shortcut that opens and closes Barback from anywhere.
public struct Hotkey: Equatable, Sendable {
    public struct Modifiers: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// From `NSEvent.ModifierFlags.rawValue`.
        public init(cocoaFlags: UInt) {
            var modifiers: Modifiers = []
            if cocoaFlags & (1 << 18) != 0 { modifiers.insert(.control) }
            if cocoaFlags & (1 << 19) != 0 { modifiers.insert(.option) }
            if cocoaFlags & (1 << 17) != 0 { modifiers.insert(.shift) }
            if cocoaFlags & (1 << 20) != 0 { modifiers.insert(.command) }
            self = modifiers
        }

        /// For Carbon's `RegisterEventHotKey`: `cmdKey`, `shiftKey`, `optionKey`, `controlKey`.
        public var carbonFlags: UInt32 {
            var flags: UInt32 = 0
            if contains(.command) { flags |= 0x0100 }
            if contains(.shift) { flags |= 0x0200 }
            if contains(.option) { flags |= 0x0800 }
            if contains(.control) { flags |= 0x1000 }
            return flags
        }

        /// In the order macOS writes them: ⌃⌥⇧⌘.
        public var symbols: String {
            var text = ""
            if contains(.control) { text += "⌃" }
            if contains(.option) { text += "⌥" }
            if contains(.shift) { text += "⇧" }
            if contains(.command) { text += "⌘" }
            return text
        }
    }

    /// The virtual key code, which names a place on the keyboard rather than a character.
    public let keyCode: Int
    public let modifiers: Modifiers
    /// What the key types, as it was when the shortcut was recorded: "B", "Space", "F5".
    public let keyLabel: String

    public init(keyCode: Int, modifiers: Modifiers, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// As menus write it: "⌃⌥B".
    public var displayName: String { modifiers.symbols + keyLabel }

    /// Whether the keys can be a global shortcut: a function key alone, or any other key with
    /// ⌘, ⌃ or ⌥. A letter alone or with only Shift would take that key away from typing.
    public var isUsable: Bool {
        Self.functionKeys[keyCode] != nil || !modifiers.isDisjoint(with: [.command, .control, .option])
    }

    /// The label of a key: its fixed name if it has one (Space, F5, an arrow), else what it
    /// types without modifiers, in capitals.
    public static func label(keyCode: Int, characters: String?) -> String {
        if let name = namedKeys[keyCode] ?? functionKeys[keyCode] { return name }
        let typed = (characters ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return typed.isEmpty ? "Key \(keyCode)" : typed
    }

    // MARK: - User defaults

    public init?(storage: [String: Any]?) {
        guard let storage,
              let keyCode = storage["keyCode"] as? Int,
              let modifiers = storage["modifiers"] as? Int,
              let keyLabel = storage["keyLabel"] as? String else { return nil }
        self.init(keyCode: keyCode, modifiers: Modifiers(rawValue: modifiers), keyLabel: keyLabel)
    }

    public var storage: [String: Any] {
        ["keyCode": keyCode, "modifiers": modifiers.rawValue, "keyLabel": keyLabel]
    }

    // MARK: - Key names

    private static let namedKeys: [Int: String] = [
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc", 76: "Enter",
        115: "Home", 116: "Page Up", 117: "Forward Delete", 119: "End", 121: "Page Down",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    private static let functionKeys: [Int: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]
}
