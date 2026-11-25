import AppKit
import BarbackCore

/// The images of the Barback icon: one for when Barback is closed and one for when it is open.
///
/// Both are template images, so the menu bar draws them in its own colour. A symbol opens to
/// its counterpart (`IconCatalog.openCandidates`); a symbol without one, and an image the user
/// chose, is dimmed instead.
@MainActor
enum StatusIcon {
    struct Images {
        let closed: NSImage
        let open: NSImage

        /// The widest of the two, in points.
        var width: CGFloat { max(closed.size.width, open.size.width) }
    }

    enum ImportError: LocalizedError {
        case unreadable

        var errorDescription: String? { "Barback couldn’t read that file as an image." }
    }

    /// The height of an image the user chose, in points. Menu bar symbols are about this tall.
    private static let imageHeight: CGFloat = 16
    private static let maxImageWidth: CGFloat = 44
    private static let dimmedAlpha: CGFloat = 0.45
    private static var cache: (choice: IconChoice, revision: Int, images: Images)?

    static func symbolExists(_ name: String) -> Bool {
        !name.isEmpty && NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    /// The images for a choice. A symbol that does not exist, and an image that is gone or
    /// unreadable, fall back to the dot.
    static func images(for choice: IconChoice, revision: Int = 0) -> Images {
        if let cache, cache.choice == choice, cache.revision == revision { return cache.images }
        let images = make(choice) ?? make(.standard) ?? Images(closed: NSImage(), open: NSImage())
        cache = (choice, revision, images)
        return images
    }

    private static func make(_ choice: IconChoice) -> Images? {
        switch choice {
        case .symbol(let name):
            guard let closed = symbol(name) else { return nil }
            if let openName = IconCatalog.openCandidates(for: name).first(where: symbolExists), let open = symbol(openName) {
                closed.accessibilityDescription = "Barback"
                open.accessibilityDescription = "Barback, open"
                return Images(closed: closed, open: open)
            }
            // Both drawn the same way, so the icon does not shift as it dims.
            return pair(from: closed, size: closed.size)
        case .image:
            guard let url = customImageURL, let image = NSImage(contentsOf: url), image.isValid,
                  image.size.width > 0, image.size.height > 0 else { return nil }
            var size = NSSize(width: image.size.width / image.size.height * imageHeight, height: imageHeight)
            if size.width > maxImageWidth {
                size = NSSize(width: maxImageWidth, height: max(1, maxImageWidth / size.width * imageHeight))
            }
            return pair(from: image, size: size, shapeFromLuminance: true)
        }
    }

    private static func symbol(_ name: String) -> NSImage? {
        let metrics = IconCatalog.metrics(for: name)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: metrics.pointSize, weight: metrics.isBold ? .bold : .regular))
        image?.isTemplate = true
        return image
    }

    private static func pair(from image: NSImage, size: NSSize, shapeFromLuminance: Bool = false) -> Images? {
        guard let closed = bitmap(of: image, size: size, alpha: 1, shapeFromLuminance: shapeFromLuminance),
              let open = bitmap(of: image, size: size, alpha: dimmedAlpha, shapeFromLuminance: shapeFromLuminance) else { return nil }
        closed.accessibilityDescription = "Barback"
        open.accessibilityDescription = "Barback, open"
        return Images(closed: closed, open: open)
    }

    /// Draws an image into a bitmap three pixels to the point. MenuBarAgent draws status
    /// items, and a plain bitmap is the image it is surest to draw as given.
    private static func bitmap(of image: NSImage, size: NSSize, alpha: CGFloat, shapeFromLuminance: Bool) -> NSImage? {
        let scale = 3
        let size = NSSize(width: ceil(size.width), height: ceil(size.height))
        guard size.width > 0, size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32) else { return nil }
        // The size comes first: the context takes its scale from the bitmap as it is made.
        rep.size = size
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        reshape(rep, alpha: alpha, shapeFromLuminance: shapeFromLuminance)
        let result = NSImage(size: size)
        result.addRepresentation(rep)
        result.isTemplate = true
        return result
    }

    /// Makes the bitmap a black shape: only its transparency is drawn in the menu bar.
    ///
    /// An image with no transparency at all (a logo on a white background, say) would be a
    /// solid rectangle, so its shape is taken from its brightness instead: whatever differs
    /// from the corners, which are taken to be background.
    static func reshape(_ rep: NSBitmapImageRep, alpha: CGFloat, shapeFromLuminance: Bool) {
        guard let data = rep.bitmapData, rep.bitsPerPixel == 32 else { return }
        let width = rep.pixelsWide, height = rep.pixelsHigh, rowBytes = rep.bytesPerRow
        func offset(_ x: Int, _ y: Int) -> Int { y * rowBytes + x * 4 }
        // Bitmap data is premultiplied; with full alpha it is the colour itself.
        func luminance(_ at: Int) -> CGFloat {
            (0.299 * CGFloat(data[at]) + 0.587 * CGFloat(data[at + 1]) + 0.114 * CGFloat(data[at + 2])) / 255
        }

        var isOpaque = shapeFromLuminance
        if isOpaque {
            scan: for y in 0..<height {
                for x in 0..<width where data[offset(x, y) + 3] < 250 {
                    isOpaque = false
                    break scan
                }
            }
        }
        var isBackgroundLight = true
        if isOpaque {
            let corners = [offset(0, 0), offset(width - 1, 0), offset(0, height - 1), offset(width - 1, height - 1)]
            isBackgroundLight = corners.map(luminance).reduce(0, +) / 4 >= 0.5
        }
        for y in 0..<height {
            for x in 0..<width {
                let at = offset(x, y)
                var coverage = CGFloat(data[at + 3]) / 255
                if isOpaque {
                    coverage = isBackgroundLight ? 1 - luminance(at) : luminance(at)
                }
                data[at] = 0
                data[at + 1] = 0
                data[at + 2] = 0
                data[at + 3] = UInt8((coverage * alpha * 255).rounded().clamped(to: 0...255))
            }
        }
    }

    // MARK: - The image the user chose

    private static var imageFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Barback", isDirectory: true)
    }

    /// Barback's copy of the chosen image, `icon.<extension>`, if there is one.
    static var customImageURL: URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: imageFolder, includingPropertiesForKeys: nil)) ?? []
        return files.first { $0.deletingPathExtension().lastPathComponent == "icon" }
    }

    /// Keeps a copy of an image to use as the icon, in place of any earlier one.
    static func importImage(from source: URL) throws {
        guard let image = NSImage(contentsOf: source), image.isValid, image.size.width > 0, image.size.height > 0 else {
            throw ImportError.unreadable
        }
        let files = FileManager.default
        try files.createDirectory(at: imageFolder, withIntermediateDirectories: true)
        let copy = imageFolder.appendingPathComponent("icon").appendingPathExtension(source.pathExtension.lowercased())
        let staged = imageFolder.appendingPathComponent("incoming-\(UUID().uuidString)")
        try files.copyItem(at: source, to: staged)
        while let old = customImageURL { try files.removeItem(at: old) }
        try files.moveItem(at: staged, to: copy)
        cache = nil
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
