# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Barback is a macOS 27 (Apple silicon) menu bar manager, forked from [Chest](https://github.com/boringbar/chest). It hides menu bar items by flipping macOS's own "Allow in the Menu Bar" switches and Menu Bar Controls preferences, not with assessment mode or a wide divider item. `docs/APPROACH.md` is the design doc: it records how each mechanism works, what was measured on macOS 27, and what was ruled out. Read the relevant section before changing hiding, placing, reading/opening items or drag and drop, and update it when behaviour changes.

## Commands

SwiftPM only; there is no Xcode project.

```sh
swift build
swift test                                                  # BarbackCore tests (XCTest)
swift test --filter BarbackCoreTests.AllowListTests         # one test class
swift test --filter BarbackCoreTests.HotkeyTests/testCarbonFlags   # one test
swift run                       # runs the app; Ctrl-C quits cleanly and restores hidden items
scripts/release.sh --adhoc      # dist/Barback.app + DMG, ad hoc signed, for this Mac
scripts/release.sh              # Developer ID sign, notarize, DMG, GitHub release, Sparkle appcast into updates/
swift scripts/make-icon.swift   # Resources/AppIcon.svg -> Resources/AppIcon.icns
```

- `swift run` works because `Package.swift` embeds `Resources/Info.plist` into the binary (`-sectcreate __TEXT __info_plist`), giving it a bundle ID and agent (LSUIElement) behaviour. Permissions (Accessibility, the protected files) then belong to the terminal app, not Barback.
- `log(...)` (in `MenuBarSwitches.swift`) writes `[Barback] …` to stderr in DEBUG builds only.
- Builds without a feed URL and public key in Info.plist (`swift run`, `--adhoc`) have no updater and make no network connections; `release.sh` injects them from `scripts/release.conf`.
- Releasing: bump `CFBundleShortVersionString` and `CFBundleVersion` (integer, must increase) in `Resources/Info.plist`; optional notes in `release-notes/<version>.md`. `dist/` and `updates/` are git-ignored; `updates/` must be kept because the appcast is regenerated from the DMGs in it. With `GITHUB_REPO` set, the commit must be pushed first; the script tags it, publishes the GitHub release with the DMG and points the appcast's enclosure URLs at the release assets; only `appcast.xml` is uploaded to the site.

## Architecture

Two targets:

- **`BarbackCore`**: pure, UI-free logic, the only tested code. Allow-list plist format (`AllowList`: only flips `isAllowed` on existing entries, never creates entries), position math for `TrailingItemPreferredPositions` (`PreferredPositions`, incl. `dotPlacement`), menu bar geometry, system item → preference key mapping (`SystemItems`), `MoveBudget`, `IconChoice`/`IconCatalog`, `DrawerBackground`, `DrawerIconStyle`/`GlyphCrop`, `Hotkey`, `IdleClock`. Put new decision logic here so it can be tested.
- **`Barback`** (executable, AppKit + SwiftUI, `@MainActor`): `main.swift` sets up an accessory app; `BarbackController` is the hub (status item, ⌘-drag tracking, drop box, drawer, open/close state, idle auto-close, keeping the icon leftmost of shown items). It delegates to:
  - `MenuBarSwitches`: hiding. Writes Control Center's `trackedApplications` allow list and the per-item Menu Bar Controls keys via CFPreferences with the file's absolute path (not `UserDefaults(suiteName:)`), synchronizing before each read because `MenuBarAgent` writes concurrently.
  - `MenuBarPositions`: writes `com.apple.MenuBar` preferred positions so an item switched back on lands where it was dropped.
  - `MenuBarItems`: Accessibility reading of `MenuBarAgent`'s menu bar windows, and pressing items / their menus while switched off.
  - `MenuBarGlyphs`: captures items' menu bar glyphs with ScreenCaptureKit (Screen Recording, opt-in) for the drawer's single-color icons, cached as PNGs under Application Support.
  - `MenuBarLayoutObserver`: watches `MenuBarAgent`'s `AXLayoutChanged` and re-attaches when the process restarts.
  - `FileAccess`: Open-panel grants + security-scoped bookmarks for the two protected group-container plists (`FileAccess.restore()` must run before anything reads them).
  - `BarbackStore`: persisted state of which apps are in the drawer vs hidden left of the icon.
  - UI: `DrawerPanel` (also `DropPanel`, `InsertionMarker`), `NoticePanel`, `SettingsWindow`, `WelcomeWindow`, `StatusIcon`, `HotkeyCenter` (Carbon hot key), `Updater` (Sparkle).

Conventions and invariants:

- The code calls Barback's menu bar icon "the dot" and keeps Chest's names elsewhere too, so changes from upstream Chest merge easily. Don't rename for style.
- Quitting must restore every hidden item (`applicationWillTerminate` → `restoreAll`; SIGINT/SIGTERM are routed to `NSApp.terminate`). Keep that path intact.
- Grants follow the code signature's designated requirement; `release.sh --adhoc` sets `designated => identifier "com.rhymeswithjazz.barback"` so permissions survive rebuilds.

## Manual testing gotchas (from docs/APPROACH.md)

- Synthetic clicks on menu bar items need a HID-sourced event with a click state, or `MenuBarAgent` ignores them.
- A synthetic ⌘-drag must be followed by a Command key-up, or Command stays held.
- Never send Escape while a terminal running an agent is frontmost; bring another app forward and verify first.
- A synthetic drag that starts on nothing can grab a window title bar and, dragged to the top of the screen, open Mission Control. Check the drawer is open first.
- Quit other menu bar managers (Chest, Thaw, Ice, Bartender) first; they fight over the same switches.
