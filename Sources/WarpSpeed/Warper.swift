import AppKit
import CoreGraphics

@MainActor
final class Warper: ObservableObject {
    enum Direction { case left, right }

    private let displayManager: DisplayManager
    private var overlay = WarpOverlayController()

    init(displayManager: DisplayManager) {
        self.displayManager = displayManager
    }

    func warp(toDisplayNumber number: Int) {
        guard let display = displayManager.displays.first(where: { $0.displayNumber == number }) else { return }
        warp(to: display)
    }

    func cycle(direction: Direction) {
        let displays = displayManager.displays
        guard displays.count > 1 else { return }

        let mouseNS = NSEvent.mouseLocation
        let currentIdx = displays.firstIndex { $0.frame.contains(mouseNS) } ?? 0
        let n = displays.count
        // Use (idx - 1 + n) % n for left wrap — Swift's % returns negatives for negatives.
        let nextIdx: Int = {
            switch direction {
            case .right: return (currentIdx + 1) % n
            case .left:  return (currentIdx - 1 + n) % n
            }
        }()
        warp(to: displays[nextIdx])
    }

    private func warp(to display: DisplayManager.Display) {
        let nsCenter = CGPoint(x: display.frame.midX, y: display.frame.midY)
        let cgPoint = Self.convertToCG(nsPoint: nsCenter)

        // Warp first so arrival is instant; play the effect afterwards as confirmation.
        CGWarpMouseCursorPosition(cgPoint)
        overlay.flash(on: display)
    }

    /// Plays an effect at the centre of the given display without moving the cursor.
    /// Used by the Settings UI so the user can sample effects in place.
    func preview(effect: WarpEffect, on display: DisplayManager.Display) {
        overlay.flash(on: display, effectOverride: effect)
    }

    /// NSScreen uses bottom-left origin anchored at the primary (menu bar) screen.
    /// CGDirectDisplay uses top-left origin anchored at the same primary.
    /// X axes match; Y axis is flipped about the primary's height.
    static func convertToCG(nsPoint: CGPoint) -> CGPoint {
        guard let primary = NSScreen.screens.first else { return nsPoint }
        return CGPoint(x: nsPoint.x, y: primary.frame.height - nsPoint.y)
    }
}
