import AppKit
import SwiftUI

@MainActor
final class WarpOverlayController {
    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var hideTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]

    func flash(on display: DisplayManager.Display, effectOverride: WarpEffect? = nil) {
        let effect = effectOverride ?? WarpSettings.currentEffect
        let window = windows[display.id] ?? makeWindow()
        windows[display.id] = window

        window.setFrame(display.frame, display: false)
        window.contentView = NSHostingView(rootView: WarpEffectHost(effect: effect, token: UUID()))
        window.orderFrontRegardless()

        hideTasks[display.id]?.cancel()
        let lingerNs = UInt64((effect.duration + 0.1) * 1_000_000_000)
        hideTasks[display.id] = Task { [weak self, weak window] in
            try? await Task.sleep(nanoseconds: lingerNs)
            await MainActor.run {
                guard let self else { return }
                window?.orderOut(nil)
                window?.contentView = nil
                self.hideTasks[display.id] = nil
            }
        }
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        w.level = .statusBar
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        return w
    }
}
