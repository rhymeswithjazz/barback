import BarbackCore
import Carbon.HIToolbox
import Foundation

/// The global shortcut. Carbon's hot keys are still how macOS lets an app take one key
/// combination from anywhere; they need no permission, and the key press goes to no other app.
@MainActor
final class HotkeyCenter {
    static let shared = HotkeyCenter()

    var onPress: (() -> Void)?

    /// The shortcut macOS accepted; nil when there is none, it is paused, or it was refused.
    private(set) var registered: Hotkey?
    private var wanted: Hotkey?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// Off while Settings records a new shortcut, so pressing the current one records it.
    var isPaused = false {
        didSet {
            if isPaused != oldValue { apply() }
        }
    }

    /// Whether the shortcut is in place (or there is none to put in place).
    @discardableResult
    func set(_ hotkey: Hotkey?) -> Bool {
        wanted = hotkey
        apply()
        return hotkey == nil || isPaused || registered == hotkey
    }

    private func apply() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        registered = nil
        guard let wanted, wanted.isUsable, !isPaused else { return }
        installHandler()
        var reference: EventHotKeyRef?
        // "BRBK"
        let id = EventHotKeyID(signature: 0x4252_424B, id: 1)
        let status = RegisterEventHotKey(UInt32(wanted.keyCode), wanted.modifiers.carbonFlags, id, GetEventDispatcherTarget(), 0, &reference)
        guard status == noErr, let reference else {
            log("shortcut \(wanted.displayName) refused: \(status)")
            return
        }
        hotKey = reference
        registered = wanted
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotkeyCenter.shared.onPress?() }
            }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}
