import AppKit
import BarbackCore
import ScreenCaptureKit

/// The glyphs items draw in the menu bar, for the drawer's single-colour icons.
///
/// Accessibility gives an item's frame but not its image, so the glyph is captured from
/// MenuBarAgent's menu bar window while the item is in it (ScreenCaptureKit, which takes
/// Screen Recording) and kept: an item in the drawer is switched off and cannot be seen.
/// Each is made a template image, black with the glyph's shape in its alpha, and saved under
/// Application Support so it is there after a relaunch. Without Screen Recording nothing is
/// captured and the drawer keeps the app icons.
@MainActor
enum MenuBarGlyphs {
    /// Called when a glyph is captured for the first time, or changed.
    static var onChange: (() -> Void)?

    private static var images: [String: NSImage] = [:]
    /// What each saved glyph's file holds, so an unchanged capture is not written again.
    private static var saved: [String: Data] = [:]
    private static var missing: Set<String> = []
    private static var isCapturing = false

    static var hasAccess: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt the first time; after that, opens System Settings at
    /// Screen Recording, where Barback is then listed.
    static func requestAccess() {
        guard !CGRequestScreenCaptureAccess() else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The item's glyph as last seen, if it was ever seen.
    static func glyph(for bundleID: String) -> NSImage? {
        if let image = images[bundleID] { return image }
        guard !missing.contains(bundleID) else { return nil }
        let url = fileURL(for: bundleID)
        guard let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) else {
            missing.insert(bundleID)
            return nil
        }
        let image = templateImage(rep)
        images[bundleID] = image
        saved[bundleID] = data
        return image
    }

    /// Captures the glyph of every item in the menu bar now, except `skipping` (the dot).
    static func captureShownItems(skipping: Set<String> = []) {
        guard hasAccess, !isCapturing else { return }
        isCapturing = true
        Task {
            defer { isCapturing = false }
            let items = await Task.detached { MenuBarItems.shownItems() }.value
                .filter { $0.canHide && !skipping.contains($0.bundleID) }
            guard !items.isEmpty else { return }
            var changed = false
            for (bundleID, rep) in await capture(items) where store(rep, for: bundleID) {
                changed = true
            }
            if changed { onChange?() }
        }
    }

    // MARK: - Capturing

    /// One capture per menu bar window, cropped to each item. An app with several items keeps
    /// its leftmost one.
    private static func capture(_ items: [MenuBarItems.Item]) async -> [(String, NSBitmapImageRep)] {
        // MenuBarAgent's menu bar windows are listed as off screen (the Window Server shows
        // them through a window of its own), so off-screen windows have to be included.
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else {
            log("couldn’t list windows for glyphs")
            return []
        }
        let windows = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == "com.apple.MenuBarAgent" && $0.frame.width > 0 && $0.frame.height > 0
        }
        var found: [(String, NSBitmapImageRep)] = []
        var seen: Set<String> = []
        for window in windows {
            let inWindow = items.filter { !seen.contains($0.bundleID) && window.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            guard !inWindow.isEmpty else { continue }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = CGFloat(filter.pointPixelScale)
            let configuration = SCStreamConfiguration()
            configuration.width = Int((window.frame.width * scale).rounded())
            configuration.height = Int((window.frame.height * scale).rounded())
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            configuration.captureResolution = .best
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) else {
                log("couldn’t capture menu bar window \(window.windowID)")
                continue
            }
            for item in inWindow where !seen.contains(item.bundleID) {
                guard let crop = GlyphCrop.pixelRect(slot: item.frame, window: window.frame, scale: scale),
                      let slot = image.cropping(to: crop),
                      let rep = glyphRep(slot, scale: scale) else { continue }
                seen.insert(item.bundleID)
                found.append((item.bundleID, rep))
            }
        }
        return found
    }

    /// The glyph in a slot, made a black shape and trimmed to it. Nil for an empty slot.
    private static func glyphRep(_ slot: CGImage, scale: CGFloat) -> NSBitmapImageRep? {
        let width = slot.width, height = slot.height
        guard width > 0, height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        context.cgContext.draw(slot, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.flushGraphics()
        StatusIcon.reshape(rep, alpha: 1, shapeFromLuminance: true)
        guard let data = rep.bitmapData else { return nil }

        // The slot has room around the glyph; keep what is drawn.
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where data[y * rep.bytesPerRow + x * 4 + 3] > 12 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY, let full = rep.cgImage,
              let trimmed = full.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) else { return nil }
        let result = NSBitmapImageRep(cgImage: trimmed)
        result.size = NSSize(width: CGFloat(trimmed.width) / scale, height: CGFloat(trimmed.height) / scale)
        return result
    }

    // MARK: - Keeping them

    /// Keeps a captured glyph. Returns whether it is new or differs from the one kept.
    private static func store(_ rep: NSBitmapImageRep, for bundleID: String) -> Bool {
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        _ = glyph(for: bundleID)
        guard saved[bundleID] != data else { return false }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: fileURL(for: bundleID), options: .atomic)
        } catch {
            log("couldn’t save the glyph of \(bundleID): \(error)")
        }
        saved[bundleID] = data
        images[bundleID] = templateImage(rep)
        missing.remove(bundleID)
        return true
    }

    private static func templateImage(_ rep: NSBitmapImageRep) -> NSImage {
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Barback/Glyphs", isDirectory: true)
    }

    private static func fileURL(for bundleID: String) -> URL {
        let name = bundleID.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: ".-_"))) ?? bundleID
        return folder.appendingPathComponent(name).appendingPathExtension("png")
    }
}
