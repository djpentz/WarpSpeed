import AppKit
import SwiftUI

/// Manages the settings window directly instead of relying on SwiftUI's `Settings`
/// scene. The Settings scene's `showSettingsWindow:` action selector is unreliable
/// for `LSUIElement` (menu bar) apps on recent macOS — first-launch works, later
/// invocations silently no-op. Owning an `NSWindow` ourselves sidesteps that.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var displayManager: DisplayManager?
    private var warper: Warper?

    func configure(displayManager: DisplayManager, warper: Warper) {
        self.displayManager = displayManager
        self.warper = warper
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        guard let displayManager, let warper else { return }

        let root = SettingsView()
            .environmentObject(displayManager)
            .environmentObject(warper)
        let hosting = NSHostingController(rootView: root)

        let w = NSWindow(contentViewController: hosting)
        w.title = "WarpSpeed Settings"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.isReleasedWhenClosed = false
        w.setContentSize(NSSize(width: 480, height: 620))
        w.contentMinSize = NSSize(width: 440, height: 420)
        w.setFrameAutosaveName("WarpSpeedSettings")
        w.center()

        window = w
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
    }
}
