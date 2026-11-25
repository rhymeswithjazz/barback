import AppKit
import BarbackCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// The Settings window: the menu bar icon, the drawer's background and icons, the shortcut, and when
/// Barback closes on its own.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let updater: Updater
    private let onPermissions: () -> Void

    init(updater: Updater, onPermissions: @escaping () -> Void) {
        self.updater = updater
        self.onPermissions = onPermissions
    }

    func show() {
        if window == nil {
            let view = SettingsView(settings: .shared, updater: updater, onPermissions: onPermissions)
            let hosting = NSHostingController(rootView: view)
            // The window follows the content, which grows by a line when there is a message.
            hosting.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: hosting)
            window.title = "Barback Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setContentSize(hosting.view.fittingSize)
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        // As for the welcome window: activation may be declined, the window shows either way.
        window?.orderFrontRegardless()
    }
}

private struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let updater: Updater
    let onPermissions: () -> Void

    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    @State private var checksForUpdates = false
    @State private var canCapture = MenuBarGlyphs.hasAccess

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "Menu Bar Icon") {
                IconPicker(settings: settings)
            }
            Divider()
            SettingsSection(title: "Drawer") {
                Picker("Background", selection: $settings.drawerBackground) {
                    ForEach(DrawerBackground.allCases, id: \.self) { background in
                        Text(background.title).tag(background)
                    }
                }
                .fixedSize()
                Picker("Icons", selection: $settings.drawerIconStyle) {
                    ForEach(DrawerIconStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                .fixedSize()
                .onChange(of: settings.drawerIconStyle) { _, style in
                    if style == .singleColor, !MenuBarGlyphs.hasAccess { MenuBarGlyphs.requestAccess() }
                    canCapture = MenuBarGlyphs.hasAccess
                }
                if settings.drawerIconStyle == .singleColor {
                    Text(canCapture
                         ? "Each item shows the icon it draws in the menu bar, as Barback last saw it there. An item not seen yet shows its app icon."
                         : "Single-color icons are read from the menu bar, which takes Screen Recording. Until it is allowed, items show their app icons. macOS may ask to reopen Barback.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !canCapture {
                        Button("Allow Screen Recording…") { MenuBarGlyphs.requestAccess() }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                canCapture = MenuBarGlyphs.hasAccess
            }
            Divider()
            SettingsSection(title: "Shortcut") {
                ShortcutRecorder(settings: settings)
            }
            Divider()
            SettingsSection(title: "Behavior") {
                Picker("Close when left unused", selection: $settings.autoCloseSeconds) {
                    ForEach(AutoClose.choices, id: \.self) { seconds in
                        Text(AutoClose.title(for: seconds)).tag(seconds)
                    }
                }
                .fixedSize()
                Text("Barback stays open while the pointer is in the menu bar or the drawer, and while a menu is open.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // A build run outside an app bundle (`swift run`) has nothing to open at login.
                if Bundle.main.bundleURL.pathExtension == "app" {
                    Toggle("Open at login", isOn: $opensAtLogin)
                        .onChange(of: opensAtLogin) { _, isOn in
                            let service = SMAppService.mainApp
                            guard (service.status == .enabled) != isOn else { return }
                            do {
                                try isOn ? service.register() : service.unregister()
                            } catch {
                                log("open at login: \(error.localizedDescription)")
                            }
                            opensAtLogin = service.status == .enabled
                        }
                }
                if updater.isAvailable {
                    HStack {
                        Toggle("Check for updates automatically", isOn: $checksForUpdates)
                            .onChange(of: checksForUpdates) { _, isOn in updater.checksAutomatically = isOn }
                        Spacer()
                        Button("Check Now") { updater.checkForUpdates() }
                    }
                }
            }
            Divider()
            HStack {
                Text("Barback \(Self.version)").foregroundStyle(.secondary)
                Spacer()
                Button("Permissions…", action: onPermissions)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            opensAtLogin = SMAppService.mainApp.status == .enabled
            checksForUpdates = updater.checksAutomatically
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content
        }
    }
}

// MARK: - Icon

private struct IconPicker: View {
    @ObservedObject var settings: AppSettings
    @State private var symbolName = ""
    @State private var importError: String?

    private let columns = Array(repeating: GridItem(.fixed(44), spacing: 8), count: 8)

    private var typedName: String { symbolName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(IconCatalog.curated, id: \.symbol) { entry in
                    IconCell(isSelected: settings.icon == .symbol(entry.symbol), title: entry.title) {
                        settings.icon = .symbol(entry.symbol)
                        symbolName = ""
                    } label: {
                        // The weight the menu bar draws it at, so the grid shows what you get.
                        Image(systemName: entry.symbol)
                            .font(.system(size: 15, weight: IconCatalog.metrics(for: entry.symbol).isBold ? .bold : .regular))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    TextField("Any SF Symbol name, such as bell.fill", text: $symbolName)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .onChange(of: symbolName) { _, _ in
                            if StatusIcon.symbolExists(typedName) { settings.icon = .symbol(typedName) }
                        }
                    if StatusIcon.symbolExists(typedName) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
                if !typedName.isEmpty && !StatusIcon.symbolExists(typedName) {
                    Text("No symbol has that name. Apple’s SF Symbols app lists them all.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if let url = StatusIcon.customImageURL, let image = NSImage(contentsOf: url) {
                        IconCell(isSelected: settings.icon == .image, title: "Your image") {
                            settings.icon = .image
                            symbolName = ""
                        } label: {
                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: 32, maxHeight: 20)
                        }
                        // A new image under the same choice is a new cell.
                        .id(settings.imageRevision)
                    }
                    Button("Choose Image…", action: chooseImage)
                }
                Text(importError ?? "A PNG, PDF or SVG. Barback draws its shape in the menu bar’s own color, so an image with a transparent background works best.")
                    .font(.callout)
                    .foregroundStyle(importError == nil ? Color.secondary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            IconPreview(images: StatusIcon.images(for: settings.icon, revision: settings.imageRevision))
        }
        .onAppear {
            if case .symbol(let name) = settings.icon, !IconCatalog.curated.contains(where: { $0.symbol == name }) {
                symbolName = name
            }
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an image for the Barback icon"
        panel.prompt = "Use Image"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try StatusIcon.importImage(from: url)
            importError = nil
            symbolName = ""
            settings.useChosenImage()
        } catch {
            importError = error.localizedDescription
        }
    }
}

private struct IconCell<Label: View>: View {
    let isSelected: Bool
    let title: String
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            label
                .frame(width: 44, height: 34)
                .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.22)) : AnyShapeStyle(.quaternary.opacity(0.6)),
                            in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: isSelected ? 1.5 : 0)
                }
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The icon as the menu bar shows it, closed and open.
private struct IconPreview: View {
    let images: StatusIcon.Images

    var body: some View {
        HStack(spacing: 14) {
            state("Closed", images.closed)
            state("Open", images.open)
            Spacer()
        }
        .padding(.top, 2)
    }

    private func state(_ title: String, _ image: NSImage) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Image(nsImage: image)
                .renderingMode(.template)
                .foregroundStyle(.primary)
                .frame(minWidth: 30, minHeight: 24)
                .padding(.horizontal, 4)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: - Shortcut

private struct ShortcutRecorder: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var recorder = Recorder()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Open and close Barback")
                Spacer()
                Button {
                    recorder.isRecording ? recorder.stop() : recorder.start(for: settings)
                } label: {
                    Text(recorder.isRecording ? "Type a shortcut…" : settings.hotkey?.displayName ?? "Record Shortcut")
                        .frame(minWidth: 120)
                }
                if settings.hotkey != nil && !recorder.isRecording {
                    Button {
                        settings.hotkey = nil
                        recorder.message = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Remove the shortcut")
                    .accessibilityLabel("Remove the shortcut")
                }
            }
            if let message = recorder.message ?? (recorder.isRecording ? "Press Esc to cancel, or Delete to remove the shortcut." : nil) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { recorder.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in recorder.stop() }
    }
}

/// Takes the next key press in Barback's windows as the new shortcut.
@MainActor
private final class Recorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published var message: String?
    private var monitor: Any?
    private weak var settings: AppSettings?

    func start(for settings: AppSettings) {
        guard !isRecording else { return }
        self.settings = settings
        isRecording = true
        message = nil
        HotkeyCenter.shared.isPaused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = Int(event.keyCode)
            let flags = event.modifierFlags.rawValue
            let characters = event.characters(byApplyingModifiers: [])
            MainActor.assumeIsolated { self?.pressed(keyCode: keyCode, flags: flags, characters: characters) }
            return nil
        }
    }

    func stop() {
        guard isRecording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        HotkeyCenter.shared.isPaused = false
    }

    private func pressed(keyCode: Int, flags: UInt, characters: String?) {
        let modifiers = Hotkey.Modifiers(cocoaFlags: flags)
        if modifiers.isEmpty, keyCode == 53 {
            stop()
            return
        }
        if modifiers.isEmpty, keyCode == 51 || keyCode == 117 {
            stop()
            settings?.hotkey = nil
            return
        }
        let hotkey = Hotkey(keyCode: keyCode, modifiers: modifiers, keyLabel: Hotkey.label(keyCode: keyCode, characters: characters))
        guard hotkey.isUsable else {
            message = "Hold ⌘, ⌃ or ⌥ with the key, or use a function key."
            return
        }
        stop()
        settings?.hotkey = hotkey
        // The controller registers it as the setting changes.
        message = HotkeyCenter.shared.registered == hotkey
            ? nil
            : "macOS didn’t accept \(hotkey.displayName); another app may be using it. Try another shortcut."
    }
}
