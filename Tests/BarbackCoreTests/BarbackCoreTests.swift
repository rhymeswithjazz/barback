import CoreGraphics
import XCTest
@testable import BarbackCore

final class AllowListTests: XCTestCase {
    private func key(_ id: String) -> [String: Any] { ["bundle": ["_0": id]] }

    private func list() -> [Any] {
        [
            key("com.example.a"),
            ["isAllowed": true, "location": key("com.example.a"), "menuItemLocations": [key("com.example.a")]],
            key("com.example.b"),
            ["isAllowed": false, "location": key("com.example.b"),
             "menuItemLocations": [["adhocBinary": ["_0": ["relative": "file:///tmp/B.app/Contents/MacOS/B"]]]]],
        ]
    }

    func testReadsEntries() {
        XCTAssertEqual(AllowList.entries(in: list()), [
            .init(bundleID: "com.example.a", isAllowed: true),
            .init(bundleID: "com.example.b", isAllowed: false),
        ])
    }

    func testSwitchesOnlyIsAllowedAndKeepsEveryOtherField() {
        let result = AllowList.setting(false, for: ["com.example.a"], in: list())
        XCTAssertTrue(result.changed)
        XCTAssertTrue(result.missing.isEmpty)
        let entry = result.list[1] as? [String: Any]
        XCTAssertEqual(entry?["isAllowed"] as? Bool, false)
        XCTAssertNotNil(entry?["location"])
        XCTAssertNotNil(entry?["menuItemLocations"])
        // The other app is untouched, its unusual location included.
        let other = result.list[3] as? [String: Any]
        let locations = other?["menuItemLocations"] as? [[String: Any]]
        XCTAssertNotNil(locations?.first?["adhocBinary"])
    }

    func testNoChangeWhenAlreadySet() {
        let result = AllowList.setting(false, for: ["com.example.b"], in: list())
        XCTAssertFalse(result.changed)
    }

    func testReportsAppsWithoutEntryAndNeverAddsOne() {
        let result = AllowList.setting(false, for: ["com.example.a", "com.example.new"], in: list())
        XCTAssertEqual(result.missing, ["com.example.new"])
        XCTAssertEqual(result.list.count, 4)
    }
}

final class MenuBarGeometryTests: XCTestCase {
    // A 1470 × 878 display with a 24-point menu bar, Cocoa coordinates.
    private let bar = CGRect(x: 0, y: 854, width: 1470, height: 24)
    private let dot = CGRect(x: 1200, y: 854, width: 32, height: 24)

    func testInsertionIndexFollowsItemCentres() {
        let frames = [CGRect(x: 1000, y: 854, width: 38, height: 24), CGRect(x: 1038, y: 854, width: 38, height: 24)]
        XCTAssertEqual(MenuBarGeometry.insertionIndex(at: 990, among: frames), 0)
        XCTAssertEqual(MenuBarGeometry.insertionIndex(at: 1030, among: frames), 1)
        XCTAssertEqual(MenuBarGeometry.insertionIndex(at: 1060, among: frames), 2)
        XCTAssertEqual(MenuBarGeometry.insertionIndex(at: 500, among: []), 0)
    }

    func testMenusHangingFromTheMenuBar() {
        let statusMenu = CGRect(x: 1150, y: 760, width: 160, height: 92)
        let contextMenu = CGRect(x: 400, y: 300, width: 160, height: 120)
        XCTAssertEqual(MenuBarGeometry.menuBarMenus([statusMenu, contextMenu], menuBars: [bar]), [statusMenu])
    }

    func testOutsideClicks() {
        let menu = CGRect(x: 1150, y: 760, width: 160, height: 92)
        let drawer = CGRect(x: 1100, y: 810, width: 200, height: 38)
        XCTAssertFalse(MenuBarGeometry.isOutside(CGPoint(x: 700, y: 866), menuBars: [bar], menus: []))
        XCTAssertFalse(MenuBarGeometry.isOutside(CGPoint(x: 1200, y: 800), menuBars: [bar], menus: [menu]))
        XCTAssertFalse(MenuBarGeometry.isOutside(CGPoint(x: 1150, y: 820), menuBars: [bar], menus: [], keep: [drawer]))
        XCTAssertTrue(MenuBarGeometry.isOutside(CGPoint(x: 700, y: 400), menuBars: [bar], menus: [menu], keep: [drawer]))
    }

    func testDrawerHangsUnderTheDotInsideTheScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1470, height: 878)
        let origin = MenuBarGeometry.drawerOrigin(size: CGSize(width: 120, height: 38), under: dot, in: screen)
        XCTAssertEqual(origin.x, 1156)
        XCTAssertEqual(origin.y, 854 - 6 - 38)
        // Near the right edge it is pushed back inside.
        let edgeDot = CGRect(x: 1440, y: 854, width: 28, height: 24)
        let pushed = MenuBarGeometry.drawerOrigin(size: CGSize(width: 120, height: 38), under: edgeDot, in: screen)
        XCTAssertEqual(pushed.x, 1470 - 8 - 120)
    }
}

final class PreferredPositionsTests: XCTestCase {
    private let positions: [String: Double] = [
        "module:Clock": 0,
        "status:com.example.app::Item-0": 213,
        "status:com.example.app::Item-1": 251,
        "status:com.example.application::Item-0": 175,
    ]

    func testKeysMatchTheWholeBundleID() {
        XCTAssertEqual(PreferredPositions.keys(of: "com.example.app", in: positions),
                       ["status:com.example.app::Item-0", "status:com.example.app::Item-1"])
        XCTAssertEqual(PreferredPositions.position(of: "com.example.application", in: positions), 175)
        XCTAssertNil(PreferredPositions.position(of: "com.example.other", in: positions))
    }

    func testBetweenNeighbours() {
        XCTAssertEqual(PreferredPositions.between(251, and: 213), 232)
        XCTAssertEqual(PreferredPositions.between(nil, and: 213), 214)
        XCTAssertEqual(PreferredPositions.between(117, and: nil), 116)
        XCTAssertEqual(PreferredPositions.between(1, and: nil), 0.5)
        XCTAssertNil(PreferredPositions.between(nil, and: nil))
    }
}

final class IconTests: XCTestCase {
    func testChoiceRoundTripsThroughStorage() {
        XCTAssertEqual(IconChoice(storage: nil), .standard)
        XCTAssertEqual(IconChoice(storage: "image"), .image)
        XCTAssertEqual(IconChoice(storage: "symbol:star.fill"), .symbol("star.fill"))
        XCTAssertEqual(IconChoice(storage: "symbol:"), .standard)
        XCTAssertEqual(IconChoice(storage: "nonsense"), .standard)
        for choice in [IconChoice.image, .symbol("chevron.left"), .standard] {
            XCTAssertEqual(IconChoice(storage: choice.storage), choice)
        }
    }

    func testOpenCandidates() {
        // The dot opens to a ring.
        XCTAssertEqual(IconCatalog.openCandidates(for: "circle.fill"), ["circle"])
        // A slash is dropped before anything else is tried.
        XCTAssertEqual(IconCatalog.openCandidates(for: "eye.slash.fill").first, "eye.fill")
        // Left points right.
        XCTAssertEqual(IconCatalog.openCandidates(for: "chevron.left").first, "chevron.right")
        XCTAssertEqual(IconCatalog.openCandidates(for: "chevron.left.2").first, "chevron.right.2")
        XCTAssertEqual(IconCatalog.openCandidates(for: "arrowtriangle.left.fill").first, "arrowtriangle.right.fill")
        // An outline fills, at the end or after its first part.
        XCTAssertEqual(IconCatalog.openCandidates(for: "star"), ["star.fill"])
        XCTAssertEqual(IconCatalog.openCandidates(for: "square.on.square"),
                       ["square.on.square.fill", "square.fill.on.square"])
        // Only the last "fill" is dropped.
        XCTAssertEqual(IconCatalog.openCandidates(for: "circle.grid.2x2.fill"), ["circle.grid.2x2"])
    }

    func testNoCandidateIsTheSymbolItself() {
        for entry in IconCatalog.curated {
            XCTAssertFalse(IconCatalog.openCandidates(for: entry.symbol).contains(entry.symbol), entry.symbol)
        }
        XCTAssertEqual(IconCatalog.openCandidates(for: ""), [])
    }

    func testCuratedSymbolsAreDistinct() {
        XCTAssertEqual(Set(IconCatalog.curated.map(\.symbol)).count, IconCatalog.curated.count)
        XCTAssertEqual(IconCatalog.curated.first?.symbol, "circle.fill")
    }

    func testOnlyTheDotIsSmall() {
        XCTAssertEqual(IconCatalog.metrics(for: "circle.fill").pointSize, 7)
        XCTAssertTrue(IconCatalog.metrics(for: "circle").isBold)
        XCTAssertEqual(IconCatalog.metrics(for: "star.fill").pointSize, 14)
        XCTAssertFalse(IconCatalog.metrics(for: "star.fill").isBold)
        XCTAssertEqual(IconCatalog.metrics(for: "ellipsis").pointSize, 14)
        XCTAssertTrue(IconCatalog.metrics(for: "ellipsis").isBold)
        XCTAssertTrue(IconCatalog.metrics(for: "line.3.horizontal").isBold)
    }
}

final class HotkeyTests: XCTestCase {
    // NSEvent.ModifierFlags raw values.
    private let shift: UInt = 1 << 17, control: UInt = 1 << 18, option: UInt = 1 << 19, command: UInt = 1 << 20

    func testModifiersFromCocoaFlags() {
        XCTAssertEqual(Hotkey.Modifiers(cocoaFlags: control | option), [.control, .option])
        XCTAssertEqual(Hotkey.Modifiers(cocoaFlags: command | shift), [.command, .shift])
        // Caps Lock, the function flag and device bits are ignored.
        XCTAssertEqual(Hotkey.Modifiers(cocoaFlags: (1 << 16) | (1 << 23) | 0x108), [])
    }

    func testCarbonFlags() {
        XCTAssertEqual(Hotkey.Modifiers.command.carbonFlags, 0x0100)
        XCTAssertEqual(Hotkey.Modifiers.shift.carbonFlags, 0x0200)
        XCTAssertEqual(Hotkey.Modifiers.option.carbonFlags, 0x0800)
        XCTAssertEqual(Hotkey.Modifiers.control.carbonFlags, 0x1000)
        XCTAssertEqual(Hotkey.Modifiers([.control, .option, .command]).carbonFlags, 0x1900)
    }

    func testDisplayName() {
        let all = Hotkey(keyCode: 11, modifiers: [.command, .shift, .option, .control], keyLabel: "B")
        XCTAssertEqual(all.displayName, "⌃⌥⇧⌘B")
        XCTAssertEqual(Hotkey(keyCode: 49, modifiers: [.control, .option], keyLabel: "Space").displayName, "⌃⌥Space")
    }

    func testLabels() {
        XCTAssertEqual(Hotkey.label(keyCode: 49, characters: " "), "Space")
        XCTAssertEqual(Hotkey.label(keyCode: 96, characters: "\u{F708}"), "F5")
        XCTAssertEqual(Hotkey.label(keyCode: 123, characters: nil), "←")
        XCTAssertEqual(Hotkey.label(keyCode: 11, characters: "b"), "B")
        XCTAssertEqual(Hotkey.label(keyCode: 200, characters: ""), "Key 200")
    }

    func testUsable() {
        XCTAssertFalse(Hotkey(keyCode: 11, modifiers: [], keyLabel: "B").isUsable)
        XCTAssertFalse(Hotkey(keyCode: 11, modifiers: [.shift], keyLabel: "B").isUsable)
        XCTAssertTrue(Hotkey(keyCode: 11, modifiers: [.control], keyLabel: "B").isUsable)
        XCTAssertTrue(Hotkey(keyCode: 11, modifiers: [.option, .shift], keyLabel: "B").isUsable)
        XCTAssertTrue(Hotkey(keyCode: 96, modifiers: [], keyLabel: "F5").isUsable)
    }

    func testRoundTripsThroughStorage() {
        let hotkey = Hotkey(keyCode: 11, modifiers: [.control, .option], keyLabel: "B")
        XCTAssertEqual(Hotkey(storage: hotkey.storage), hotkey)
        XCTAssertNil(Hotkey(storage: nil))
        XCTAssertNil(Hotkey(storage: ["keyCode": 11]))
    }
}

final class IdleClockTests: XCTestCase {
    func testClosesAfterTheDelay() {
        var clock = IdleClock(delay: 10, now: 100)
        XCTAssertFalse(clock.shouldClose(now: 105, isInUse: false))
        XCTAssertFalse(clock.shouldClose(now: 109.5, isInUse: false))
        XCTAssertTrue(clock.shouldClose(now: 110, isInUse: false))
    }

    func testUseStartsTheWaitAgain() {
        var clock = IdleClock(delay: 10, now: 100)
        XCTAssertFalse(clock.shouldClose(now: 108, isInUse: true))
        XCTAssertFalse(clock.shouldClose(now: 115, isInUse: false))
        // Still in use long past the delay: never closes under the pointer.
        XCTAssertFalse(clock.shouldClose(now: 160, isInUse: true))
        XCTAssertFalse(clock.shouldClose(now: 169, isInUse: false))
        XCTAssertTrue(clock.shouldClose(now: 170, isInUse: false))
    }

    func testNeverCloses() {
        var clock = IdleClock(delay: 0, now: 100)
        XCTAssertFalse(clock.shouldClose(now: 100_000, isInUse: false))
    }

    func testChoices() {
        XCTAssertEqual(AutoClose.choices.first, 0)
        XCTAssertEqual(AutoClose.title(for: 0), "Never")
        XCTAssertEqual(AutoClose.title(for: 10), "After 10 seconds")
        XCTAssertEqual(AutoClose.title(for: 60), "After 1 minute")
    }
}

final class DrawerBackgroundTests: XCTestCase {
    func testRoundTripsThroughStorage() {
        for background in DrawerBackground.allCases {
            XCTAssertEqual(DrawerBackground(storage: background.storage), background)
        }
    }

    func testMissingOrUnknownIsTheOriginalLook() {
        XCTAssertEqual(DrawerBackground(storage: nil), .menu)
        XCTAssertEqual(DrawerBackground(storage: "frosted"), .menu)
    }

    func testTitlesAreDistinct() {
        XCTAssertEqual(Set(DrawerBackground.allCases.map(\.title)).count, DrawerBackground.allCases.count)
    }
}

final class DrawerIconStyleTests: XCTestCase {
    func testStorageRoundTrips() {
        for style in DrawerIconStyle.allCases {
            XCTAssertEqual(DrawerIconStyle(storage: style.storage), style)
        }
    }

    func testMissingOrUnknownIsFullColor() {
        XCTAssertEqual(DrawerIconStyle(storage: nil), .fullColor)
        XCTAssertEqual(DrawerIconStyle(storage: "sepia"), .fullColor)
    }
}

final class GlyphCropTests: XCTestCase {
    private let window = CGRect(x: 0, y: 0, width: 1512, height: 33)

    func testSlotScalesToPixels() {
        let rect = GlyphCrop.pixelRect(slot: CGRect(x: 1200, y: 0, width: 30, height: 33), window: window, scale: 2)
        XCTAssertEqual(rect, CGRect(x: 2400, y: 0, width: 60, height: 66))
    }

    func testSlotIsRelativeToWindow() {
        let second = CGRect(x: 1512, y: -200, width: 1920, height: 33)
        let rect = GlyphCrop.pixelRect(slot: CGRect(x: 1612, y: -200, width: 20, height: 33), window: second, scale: 1)
        XCTAssertEqual(rect, CGRect(x: 100, y: 0, width: 20, height: 33))
    }

    func testSlotOutsideWindowIsNil() {
        XCTAssertNil(GlyphCrop.pixelRect(slot: CGRect(x: 1600, y: 0, width: 30, height: 33), window: window, scale: 2))
        XCTAssertNil(GlyphCrop.pixelRect(slot: CGRect(x: 1500, y: 0, width: 30, height: 33), window: window, scale: 2))
        XCTAssertNil(GlyphCrop.pixelRect(slot: .zero, window: window, scale: 2))
    }
}
