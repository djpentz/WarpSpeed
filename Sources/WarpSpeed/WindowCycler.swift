import AppKit
import ApplicationServices

/// Cycles keyboard focus through every on-screen window across all displays,
/// ordered spatially left-to-right (wrapping at the ends), and warps the cursor
/// to follow focus. Window enumeration uses CGWindowList (no permission needed);
/// raising a window uses the Accessibility API (requires Accessibility permission).
@MainActor
final class WindowCycler {
    enum Direction { case next, previous }

    /// The CGWindowID we last raised. Used as the "current" anchor because the
    /// WindowServer's front-to-back order updates asynchronously after a raise —
    /// re-reading "frontmost" too soon would step from a stale window.
    private var lastRaisedWindowID: CGWindowID?

    private struct WinInfo {
        let id: CGWindowID
        let pid: pid_t
        let bounds: CGRect   // global, top-left origin (same space CGWarp wants)
        let owner: String
    }

    func cycle(_ direction: Direction) {
        guard ensureTrusted() else { return }

        let (ordered, frontmost) = snapshot()
        guard ordered.count > 1 else {
            ordered.first.map(focus)   // 0–1 windows: just focus the one, if any
            return
        }

        let current = currentIndex(ordered: ordered, frontmost: frontmost)
        let n = ordered.count
        let target: Int
        switch direction {
        case .next:     target = (current + 1) % n
        case .previous: target = (current - 1 + n) % n
        }
        focus(ordered[target])
    }

    // MARK: - Enumeration

    /// Returns the spatially-ordered window list plus the current frontmost
    /// window id, in a single CGWindowList pass.
    private func snapshot() -> (ordered: [WinInfo], frontmost: CGWindowID?) {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return ([], nil)
        }

        let myPid = ProcessInfo.processInfo.processIdentifier
        var list: [WinInfo] = []   // preserves CGWindowList front-to-back order
        for w in infos {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != myPid,
                  let number = w[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = w[kCGWindowBounds as String],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as! CFDictionary)
            else { continue }

            // Skip tiny helper/utility windows (palettes, tooltips that slip through).
            if rect.width < 80 || rect.height < 80 { continue }

            let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
            list.append(WinInfo(id: number, pid: pid, bounds: rect, owner: owner))
        }

        // Optionally drop windows hidden behind others. `list` is front-to-back,
        // so a window is "exposed" only where it isn't covered by the union of
        // every window in front of it. Slivers (<~8% visible) count as hidden.
        if WarpSettings.cycleVisibleWindowsOnly {
            var fronts: [CGRect] = []
            list = list.filter { win in
                let exposed = fronts.isEmpty || visibleFraction(of: win.bounds, coveredBy: fronts) >= 0.08
                fronts.append(win.bounds)   // every front window occludes, exposed or not
                return exposed
            }
        }

        let frontmost = list.first?.id

        // Spatial order: left-to-right by x (negative on left-of-primary screens),
        // then top-to-bottom. Horizontal display layout means x alone groups by screen.
        let ordered = list.sorted { a, b in
            if abs(a.bounds.minX - b.bounds.minX) > 1 { return a.bounds.minX < b.bounds.minX }
            return a.bounds.minY < b.bounds.minY
        }
        return (ordered, frontmost)
    }

    private func currentIndex(ordered: [WinInfo], frontmost: CGWindowID?) -> Int {
        if let last = lastRaisedWindowID, let idx = ordered.firstIndex(where: { $0.id == last }) {
            return idx
        }
        if let frontmost, let idx = ordered.firstIndex(where: { $0.id == frontmost }) {
            return idx
        }
        return 0
    }

    // MARK: - Focus

    private func focus(_ win: WinInfo) {
        let app = AXUIElementCreateApplication(win.pid)
        AXUIElementSetMessagingTimeout(app, 0.2)   // never beachball the hotkey

        if let axWindow = matchingAXWindow(in: app, bounds: win.bounds) {
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(axWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
        // Raise alone doesn't move keyboard focus — the app must also be activated.
        NSRunningApplication(processIdentifier: win.pid)?.activate()

        lastRaisedWindowID = win.id

        // Delight: the cursor follows focus. CGWindowList bounds are already in
        // global top-left coords, so warp directly — no NSScreen Y-flip here.
        CGWarpMouseCursorPosition(CGPoint(x: win.bounds.midX, y: win.bounds.midY))
    }

    private func matchingAXWindow(in app: AXUIElement, bounds: CGRect) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }

        for window in windows {
            if let frame = axFrame(of: window), framesMatch(frame, bounds) {
                return window
            }
        }
        return windows.first   // fallback: app's frontmost window
    }

    private func axFrame(of window: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let posValue, let sizeValue,
              CFGetTypeID(posValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    private func framesMatch(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 6 && abs(a.minY - b.minY) < 6 &&
        abs(a.width - b.width) < 6 && abs(a.height - b.height) < 6
    }

    /// Fraction of `rect` not covered by any rect in `covers`, estimated on a
    /// grid of sample points. Cheap and good enough to decide "is this window
    /// meaningfully visible, or buried behind others?"
    private func visibleFraction(of rect: CGRect, coveredBy covers: [CGRect]) -> Double {
        let cols = 12, rows = 12
        var visible = 0
        for r in 0..<rows {
            for c in 0..<cols {
                let p = CGPoint(
                    x: rect.minX + (Double(c) + 0.5) / Double(cols) * rect.width,
                    y: rect.minY + (Double(r) + 0.5) / Double(rows) * rect.height
                )
                if !covers.contains(where: { $0.contains(p) }) { visible += 1 }
            }
        }
        return Double(visible) / Double(cols * rows)
    }

    // MARK: - Permission

    /// Returns true if Accessibility is granted. Otherwise triggers the system
    /// prompt and opens the relevant Settings pane, and returns false.
    @discardableResult
    func ensureTrusted() -> Bool {
        if Self.isTrusted { return true }
        Self.requestAccessibility()
        return false
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Triggers the system Accessibility prompt and opens the Settings pane.
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
