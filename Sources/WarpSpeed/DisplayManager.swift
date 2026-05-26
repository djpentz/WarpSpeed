import AppKit
import Combine
import CoreGraphics

final class DisplayManager: ObservableObject {
    struct Display: Identifiable, Hashable {
        let id: CGDirectDisplayID
        let frame: CGRect           // NSScreen.frame (bottom-left origin)
        let index: Int              // 0 = leftmost
        let name: String
        var displayNumber: Int { index + 1 }   // user-facing label
    }

    @Published private(set) var displays: [Display] = []

    init() {
        refresh()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func screenParametersChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.refresh()
        }
    }

    private func refresh() {
        // Order screens left-to-right, then top-to-bottom for vertically stacked rigs.
        // NSScreen.screens[0] is the primary (menu bar) screen — NOT necessarily leftmost.
        let sorted = NSScreen.screens.sorted { lhs, rhs in
            if lhs.frame.minX != rhs.frame.minX {
                return lhs.frame.minX < rhs.frame.minX
            }
            return lhs.frame.minY > rhs.frame.minY
        }

        displays = sorted.enumerated().map { idx, screen in
            Display(
                id: screen.displayID,
                frame: screen.frame,
                index: idx,
                name: screen.localizedName
            )
        }
    }

    func display(containing nsPoint: CGPoint) -> Display? {
        displays.first { $0.frame.contains(nsPoint) }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }
}
