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
    private var cancellables = Set<AnyCancellable>()

    init(displayManager: DisplayManager, warper: Warper) {
        self.displayManager = displayManager
        self.warper = warper

        displayManager.$displays
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.rebind(for: $0.count) }
            .store(in: &cancellables)
    }

    private func rebind(for displayCount: Int) {
        // Tear down all numeric shortcut handlers, then re-register only the active ones.
        for name in KeyboardShortcuts.Name.allWarpToDisplay {
            KeyboardShortcuts.disable(name)
        }

        for n in 1...max(displayCount, 1) {
            let name = KeyboardShortcuts.Name.warpToDisplay(n)
            KeyboardShortcuts.onKeyDown(for: name) { [weak self] in
                self?.warper.warp(toDisplayNumber: n)
            }
        }

        if displayCount > 1 {
            KeyboardShortcuts.onKeyDown(for: .cycleLeft) { [weak self] in
                self?.warper.cycle(direction: .left)
            }
            KeyboardShortcuts.onKeyDown(for: .cycleRight) { [weak self] in
                self?.warper.cycle(direction: .right)
            }
        } else {
            KeyboardShortcuts.disable(.cycleLeft)
            KeyboardShortcuts.disable(.cycleRight)
        }
    }
}
