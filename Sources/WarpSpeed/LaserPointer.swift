import AppKit
import Combine
import QuartzCore
import SwiftUI

// MARK: - Configuration

/// Persisted laser appearance. Colour is stored as sRGB components so it round-trips
/// through UserDefaults (SwiftUI `Color` isn't directly codable to defaults).
/// The *active* state is intentionally NOT persisted — laser starts off each launch.
struct LaserConfig: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var dotSize: Double          // bright core diameter, points
    var trailEnabled: Bool
    var trailDuration: Double    // how long the ghost trail lingers, seconds
    var trailThickness: Double   // trail particle diameter at the head, points

    static let `default` = LaserConfig(
        red: 1.0, green: 0.18, blue: 0.12,   // classic laser red
        dotSize: 20,
        trailEnabled: false,
        trailDuration: 0.45,
        trailThickness: 12
    )

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }

    mutating func setColor(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .red
        red = Double(ns.redComponent)
        green = Double(ns.greenComponent)
        blue = Double(ns.blueComponent)
    }
}

enum LaserSettings {
    private static let d = UserDefaults.standard
    private static let prefix = "warpspeed.laser."

    static func load() -> LaserConfig {
        var c = LaserConfig.default
        if d.object(forKey: prefix + "red") != nil {
            c.red = d.double(forKey: prefix + "red")
            c.green = d.double(forKey: prefix + "green")
            c.blue = d.double(forKey: prefix + "blue")
        }
        if d.object(forKey: prefix + "dotSize") != nil { c.dotSize = d.double(forKey: prefix + "dotSize") }
        if d.object(forKey: prefix + "trailEnabled") != nil { c.trailEnabled = d.bool(forKey: prefix + "trailEnabled") }
        if d.object(forKey: prefix + "trailDuration") != nil { c.trailDuration = d.double(forKey: prefix + "trailDuration") }
        if d.object(forKey: prefix + "trailThickness") != nil { c.trailThickness = d.double(forKey: prefix + "trailThickness") }
        return c
    }

    static func save(_ c: LaserConfig) {
        d.set(c.red, forKey: prefix + "red")
        d.set(c.green, forKey: prefix + "green")
        d.set(c.blue, forKey: prefix + "blue")
        d.set(c.dotSize, forKey: prefix + "dotSize")
        d.set(c.trailEnabled, forKey: prefix + "trailEnabled")
        d.set(c.trailDuration, forKey: prefix + "trailDuration")
        d.set(c.trailThickness, forKey: prefix + "trailThickness")
    }
}

// MARK: - Controller

/// A presenter laser pointer: a persistent, click-through overlay that rides the
/// cursor so it shows up in a screen-share stream (full-display share only — a
/// single-window share captures just that window's pixels, not our overlay).
///
/// One borderless overlay window *per display* (not a single union-spanning window):
/// a window straddling a Retina + non-Retina pair renders at one backing scale, so
/// the dot would be blurry/mis-sized on one screen. Each window matches its screen's
/// scale; a single shared trail buffer (global coords) is sliced per display, and
/// SwiftUI clips each `LaserView` to its own bounds.
@MainActor
final class LaserController: ObservableObject {
    @Published private(set) var isActive = false
    @Published var config: LaserConfig {
        didSet { LaserSettings.save(config) }
    }

    /// Bumped every timer tick to drive the overlay redraw. The trail/point data
    /// itself is read imperatively inside the Canvas closure to avoid pushing a
    /// 120-element array through Combine 120 times a second.
    @Published private(set) var frameTick: UInt64 = 0

    /// Recent cursor samples in global NS coordinates (bottom-left origin), newest last.
    private(set) var trail: [(point: CGPoint, time: CFTimeInterval)] = []
    /// Latest cursor sample in global NS coordinates, or nil before the first tick.
    private(set) var currentPoint: CGPoint?

    private let displayManager: DisplayManager
    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private let frequency = 120.0

    init(displayManager: DisplayManager) {
        self.displayManager = displayManager
        self.config = LaserSettings.load()

        // Rebuild overlays when displays are plugged/unplugged mid-session.
        displayManager.$displays
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isActive else { return }
                self.rebuildWindows()
            }
            .store(in: &cancellables)
    }

    func toggle() { setActive(!isActive) }

    func setActive(_ on: Bool) {
        guard on != isActive else { return }
        isActive = on
        if on {
            trail.removeAll(keepingCapacity: true)
            currentPoint = nil
            rebuildWindows()
            startTimer()
        } else {
            stopTimer()
            tearDownWindows()
            trail.removeAll(keepingCapacity: true)
            currentPoint = nil
        }
    }

    // MARK: Timer

    private func startTimer() {
        stopTimer()
        // .common mode so the trail keeps moving during menu tracking / window drags.
        let t = Timer(timeInterval: 1.0 / frequency, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let p = NSEvent.mouseLocation   // global NS coords, bottom-left origin
        currentPoint = p
        trail.append((p, now))

        // Trim by age. When the trail is off we keep only the head so the buffer
        // can't grow, while staying ready to draw instantly if it's toggled on.
        let cutoff = now - (config.trailEnabled ? config.trailDuration : 0)
        if let firstFresh = trail.firstIndex(where: { $0.time >= cutoff }), firstFresh > 0 {
            trail.removeFirst(firstFresh)
        }

        frameTick &+= 1
    }

    // MARK: Windows

    private func rebuildWindows() {
        let wanted = Set(displayManager.displays.map(\.id))

        // Drop windows for displays that went away.
        for (id, window) in windows where !wanted.contains(id) {
            window.orderOut(nil)
            windows.removeValue(forKey: id)
        }

        for display in displayManager.displays {
            let window = windows[display.id] ?? makeWindow()
            windows[display.id] = window
            window.setFrame(display.frame, display: false)
            window.contentView = NSHostingView(
                rootView: LaserView(display: display).environmentObject(self)
            )
            window.orderFrontRegardless()
        }
    }

    private func tearDownWindows() {
        for window in windows.values {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows.removeAll()
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(
            contentRect: .zero,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // Above the menu bar and fullscreen presentation content so the presenter
        // sees the laser locally; the share compositor captures it regardless of level.
        w.level = .screenSaver
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true          // click-through — never steals clicks
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        // Leave sharingType at its default (.readOnly) so the overlay is captured.
        return w
    }
}

// MARK: - View

/// Draws the laser for one display. Reads the controller's global-coordinate trail
/// imperatively each redraw and converts into this display's local (top-left) space.
private struct LaserView: View {
    let display: DisplayManager.Display
    @EnvironmentObject private var controller: LaserController

    var body: some View {
        Canvas { ctx, _ in
            _ = controller.frameTick   // re-evaluate body each tick
            let cfg = controller.config

            if cfg.trailEnabled, controller.trail.count > 1 {
                drawTrail(ctx, cfg: cfg)
            }
            if let p = controller.currentPoint {
                drawDot(ctx, at: local(p), cfg: cfg)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Global NS (bottom-left) → this display's local SwiftUI (top-left) coordinates.
    private func local(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x - display.frame.minX, y: display.frame.maxY - p.y)
    }

    private func drawTrail(_ ctx: GraphicsContext, cfg: LaserConfig) {
        guard let newest = controller.trail.last?.time else { return }
        let base = cfg.color
        for sample in controller.trail {
            let age = newest - sample.time
            let progress = max(0, 1 - age / cfg.trailDuration)   // 1 at head → 0 at tail
            guard progress > 0 else { continue }
            let r = (cfg.trailThickness / 2) * progress
            let pt = local(sample.point)
            let rect = CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(base.opacity(0.55 * progress)))
        }
    }

    private func drawDot(_ ctx: GraphicsContext, at pt: CGPoint, cfg: LaserConfig) {
        let core = cfg.dotSize
        let halo = core * 2.4

        // Soft outer glow.
        let haloRect = CGRect(x: pt.x - halo / 2, y: pt.y - halo / 2, width: halo, height: halo)
        ctx.fill(
            Path(ellipseIn: haloRect),
            with: .radialGradient(
                Gradient(colors: [cfg.color.opacity(0.45), cfg.color.opacity(0)]),
                center: pt, startRadius: 0, endRadius: halo / 2
            )
        )

        // Bright core.
        let coreRect = CGRect(x: pt.x - core / 2, y: pt.y - core / 2, width: core, height: core)
        ctx.fill(Path(ellipseIn: coreRect), with: .color(cfg.color.opacity(0.95)))

        // White-hot centre for that "lit" laser sparkle.
        let hot = core * 0.42
        let hotRect = CGRect(x: pt.x - hot / 2, y: pt.y - hot / 2, width: hot, height: hot)
        ctx.fill(Path(ellipseIn: hotRect), with: .color(.white.opacity(0.85)))
    }
}
