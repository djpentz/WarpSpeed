import SwiftUI
import AppKit
import CoreGraphics

@main
struct WarpSpeedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No-op Scene — settings window is managed manually via SettingsWindowController.
        // SwiftUI's Settings scene + LSUIElement is unreliable on recent macOS.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let displayManager = DisplayManager()
    private(set) var warper: Warper!
    private var shortcutManager: ShortcutManager!
    private var statusItemController: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Zero the event suppression interval so physical mouse movement is
        // responsive immediately after a programmatic warp — otherwise the
        // default ~250ms lockout feels like the warp broke the mouse.
        if let source = CGEventSource(stateID: .combinedSessionState) {
            source.localEventsSuppressionInterval = 0
        }

        warper = Warper(displayManager: displayManager)
        shortcutManager = ShortcutManager(displayManager: displayManager, warper: warper)
        statusItemController = StatusItemController(displayManager: displayManager, warper: warper)
        SettingsWindowController.shared.configure(displayManager: displayManager, warper: warper)

        let key = "warpspeed.hasLaunchedBefore"
        if !UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.set(true, forKey: key)
            DispatchQueue.main.async {
                SettingsWindowController.shared.show()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }
}
