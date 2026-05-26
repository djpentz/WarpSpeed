import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let displayManager: DisplayManager
    private let warper: Warper
    private var cancellables = Set<AnyCancellable>()

    init(displayManager: DisplayManager, warper: Warper) {
        self.displayManager = displayManager
        self.warper = warper
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "sparkles.rectangle.stack.fill",
                accessibilityDescription: "WarpSpeed"
            )
            image?.isTemplate = true
            button.image = image
        }

        rebuildMenu()
        displayManager.$displays
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let header = NSMenuItem()
        header.title = displayManager.displays.count == 1
            ? "1 display detected"
            : "\(displayManager.displays.count) displays detected"
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        for display in displayManager.displays {
            let item = NSMenuItem(
                title: "Warp to display \(display.displayNumber) — \(display.name)",
                action: #selector(warpToDisplay(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = display.displayNumber
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let launchToggle = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchToggle.target = self
        launchToggle.state = LaunchAtLoginManager.isEnabled ? .on : .off
        menu.addItem(launchToggle)

        let about = NSMenuItem(title: "About WarpSpeed", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit WarpSpeed",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
    }

    @objc private func warpToDisplay(_ sender: NSMenuItem) {
        warper.warp(toDisplayNumber: sender.tag)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let next = !LaunchAtLoginManager.isEnabled
        LaunchAtLoginManager.setEnabled(next)
        sender.state = LaunchAtLoginManager.isEnabled ? .on : .off
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}

