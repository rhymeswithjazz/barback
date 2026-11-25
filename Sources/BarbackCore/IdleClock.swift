import Foundation

/// Decides when an open Barback has been left alone long enough to close on its own.
///
/// It is asked every so often whether Barback is in use: the pointer is in the menu bar or
/// the drawer, a menu is open, an item is being dragged. Any use starts the wait again, so
/// Barback never closes under the pointer or over an open menu.
public struct IdleClock: Sendable {
    /// How long Barback stays open unused, in seconds. Zero or less never closes it.
    public let delay: TimeInterval
    private var lastUse: TimeInterval

    public init(delay: TimeInterval, now: TimeInterval) {
        self.delay = delay
        lastUse = now
    }

    /// Whether to close now.
    public mutating func shouldClose(now: TimeInterval, isInUse: Bool) -> Bool {
        guard delay > 0 else { return false }
        if isInUse {
            lastUse = now
            return false
        }
        return now - lastUse >= delay
    }
}

/// The choices Settings offers for closing on its own, in seconds; zero is never.
public enum AutoClose {
    public static let choices = [0, 5, 10, 15, 30, 60]

    public static func title(for seconds: Int) -> String {
        switch seconds {
        case ...0: "Never"
        case 60: "After 1 minute"
        default: "After \(seconds) seconds"
        }
    }
}
