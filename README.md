# WarpSpeed

A tiny macOS menu bar utility that warps your mouse cursor to any display, instantly.

If you run two or three displays and spend half your day jiggling the mouse to find the pointer, this is for you. Press a hotkey, your cursor lands in the middle of the target screen — accompanied by a brief streak effect so you know exactly where it went.

## Download

Grab the latest build from the [**Releases** page](https://github.com/djpentz/WarpSpeed/releases/latest). Unzip `WarpSpeed.app.zip` and drag `WarpSpeed.app` into `/Applications`.

The binary is **ad-hoc signed, not notarized**, so Gatekeeper will block it on first launch. Clear the quarantine flag once and you're done:

```bash
xattr -dr com.apple.quarantine /Applications/WarpSpeed.app
```

Alternatively, right-click the app in Finder and choose **Open** the first time — macOS will then let you confirm and launch it.

> Proper Developer ID signing + notarization (so no workaround is needed) is future work.

## Features

- **Direct jump:** `⌃⌥1` / `⌃⌥2` / `⌃⌥3` — warp to display 1, 2, or 3 (left-to-right).
- **Cycle:** `⌃⌥←` / `⌃⌥→` — step through displays. Wraps around: past the rightmost lands you on the leftmost.
- **Auto-detect:** plug or unplug a screen, the menu and shortcuts update on the fly.
- **Customisable:** rebind any shortcut in Settings.
- **Delight:** a brief warp-streaks animation converges on the landing point so the jump feels intentional, not random.
- **Tiny:** menu bar only — no Dock icon, no background CPU, no Electron.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+ (ships with Xcode Command Line Tools — `xcode-select --install` if you don't have them)

No Xcode installation required.

## Build

```bash
./scripts/build.sh
open build/WarpSpeed.app
```

That's it. First launch opens Settings so you can confirm the displays and shortcuts.

## Install for everyday use

```bash
./scripts/build.sh
cp -R build/WarpSpeed.app /Applications/
open /Applications/WarpSpeed.app
```

Then enable **Launch at Login** from the menu bar icon.

## Architecture

A small SwiftUI + AppKit menu bar app. Six Swift files:

| File | Purpose |
|------|---------|
| `WarpSpeedApp.swift` | App entry, `LSUIElement` agent setup, first-run flow. |
| `DisplayManager.swift` | Enumerates `NSScreen.screens`, sorts left-to-right, reacts to hot-plug. |
| `Warper.swift` | Coordinate conversion (NS → CG) and `CGWarpMouseCursorPosition`. |
| `WarpOverlay.swift` | Per-display borderless overlay that draws the convergent streaks. |
| `ShortcutManager.swift` | Registers customisable global hotkeys via [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts). |
| `StatusItemController.swift` | Menu bar icon + menu. |
| `SettingsView.swift` | SwiftUI settings window. |
| `LaunchAtLoginManager.swift` | `SMAppService` wrapper. |

### Coordinate systems

`NSScreen.frame` uses a bottom-left origin anchored at the primary (menu bar) screen. `CGWarpMouseCursorPosition` takes top-left coordinates. The conversion is in `Warper.convertToCG(nsPoint:)`. The primary screen height is the only reference needed — the formula works for displays positioned to the left of, above, or below the primary.

### Why `CGEventSourceSetLocalEventsSuppressionInterval(_, 0)`?

By default, after a programmatic cursor warp, macOS ignores physical mouse input for ~250ms. That feels broken right after a warp. Setting the suppression interval to zero at launch makes the mouse responsive immediately after every warp.

## Future work

- **Activate frontmost window** on the target display (requires Accessibility permission).
- **App icon** — currently runs without one; the menu bar icon is the SF Symbol `sparkles.rectangle.stack.fill`.
- **Notarization** for distribution outside personal use.
- **Sparkle** for auto-updates.
