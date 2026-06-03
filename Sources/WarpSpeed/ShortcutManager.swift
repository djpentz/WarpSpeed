import AppKit
import Combine
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let cycleLeft  = KeyboardShortcuts.Name(
        "warpspeed.cycleLeft",
        default: .init(.leftArrow, modifiers: [.control, .option])
    )
    static let cycleRight = KeyboardShortcuts.Name(
        "warpspeed.cycleRight",
        default: .init(.rightArrow, modifiers: [.control, .option])
    )

    static let windowNext = KeyboardShortcuts.Name(
        "warpspeed.windowNext",
        default: .init(.rightBracket, modifiers: [.control, .option])
    )
    static let windowPrevious = KeyboardShortcuts.Name(
        "warpspeed.windowPrevious",
        default: .init(.leftBracket, modifiers: [.control, .option])
    )

    static func warpToDisplay(_ number: Int) -> KeyboardShortcuts.Name {
        let key: KeyboardShortcuts.Key? = {
            switch number {
            case 1: return .one
            case 2: return .two
            case 3: return .three
            case 4: return .four
            case 5: return .five
            case 6: return .six
            case 7: return .seven
            case 8: return .eight
            case 9: return .nine
            default: return nil
            }
        }()
        let shortcut = key.map { KeyboardShortcuts.Shortcut($0, modifiers: [.control, .option]) }
        return KeyboardShortcuts.Name("warpspeed.display.\(number)", default: shortcut)
    }

    static var allWarpToDisplay: [KeyboardShortcuts.Name] {
        (1...9).map { warpToDisplay($0) }
    }
}

@MainActor
final class ShortcutManager {
    private let displayManager: DisplayManager
    private let warper: Warper
    private let windowCycler: WindowCycler
    private var cancellables = Set<AnyCancellable>()

    init(displayManager: DisplayManager, warper: Warper, windowCycler: WindowCycler) {
        self.displayManager = displayManager
        self.warper = warper
        self.windowCycler = windowCycler

        // Register every handler exactly ONCE. `KeyboardShortcuts.onKeyDown`
        // *appends* to an internal handler array — calling it repeatedly (e.g.
        // on every display re-handshake after sleep) accumulates duplicate
        // handlers, so a single keypress eventually fires `warp()` many times,
        // each tearing down the prior overlay animation before it can render.
        // That was the sleep-degradation bug. Activation by display count is
        // handled separately via enable/disable, which only touch hotkey
        // registration — never the handler closures.
        registerHandlers()

        displayManager.$displays
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateActivation(for: $0.count) }
            .store(in: &cancellables)
    }

    private func registerHandlers() {
        for n in 1...maxDisplays {
            let name = KeyboardShortcuts.Name.warpToDisplay(n)
            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
                // No-ops safely if display `n` doesn't currently exist.
                self?.warper.warp(toDisplayNumber: n)
            }
        }
        KeyboardShortcuts.onKeyDown(for: .cycleLeft) { [weak self] in
            self?.warper.cycle(direction: .left)
        }
        KeyboardShortcuts.onKeyDown(for: .cycleRight) { [weak self] in
            self?.warper.cycle(direction: .right)
        }
        // Window focus cycling. Gating on Accessibility happens inside cycle();
        // the first press without permission triggers the prompt + Settings pane.
        KeyboardShortcuts.onKeyDown(for: .windowNext) { [weak self] in
            self?.windowCycler.cycle(.next)
        }
        KeyboardShortcuts.onKeyDown(for: .windowPrevious) { [weak self] in
            self?.windowCycler.cycle(.previous)
        }
    }

    private func updateActivation(for displayCount: Int) {
        for n in 1...maxDisplays {
            let name = KeyboardShortcuts.Name.warpToDisplay(n)
            if n <= displayCount {
                KeyboardShortcuts.enable(name)
            } else {
                KeyboardShortcuts.disable(name)
            }
        }

        if displayCount > 1 {
            KeyboardShortcuts.enable(.cycleLeft, .cycleRight)
        } else {
            KeyboardShortcuts.disable(.cycleLeft, .cycleRight)
        }
    }

    private let maxDisplays = 9
}
