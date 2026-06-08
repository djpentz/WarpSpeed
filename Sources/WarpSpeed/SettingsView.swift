import SwiftUI
import AppKit
import Combine
import KeyboardShortcuts

struct SettingsView: View {
    @EnvironmentObject private var displayManager: DisplayManager
    @EnvironmentObject private var warper: Warper
    @EnvironmentObject private var laser: LaserController
    @State private var launchAtLogin: Bool = LaunchAtLoginManager.isEnabled
    @State private var selectedEffect: WarpEffect = WarpSettings.currentEffect
    @State private var accessibilityTrusted: Bool = WindowCycler.isTrusted
    @State private var visibleWindowsOnly: Bool = WarpSettings.cycleVisibleWindowsOnly

    // Accessibility can be granted/revoked in System Settings while this window
    // is open; poll so the status row reflects it live.
    private let trustTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                if displayManager.displays.isEmpty {
                    Text("No displays detected.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(displayManager.displays) { display in
                        KeyboardShortcuts.Recorder(for: .warpToDisplay(display.displayNumber)) {
                            HStack(spacing: 8) {
                                Image(systemName: "display")
                                    .foregroundStyle(.secondary)
                                Text("Display \(display.displayNumber)")
                                Text("· \(display.name)")
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                            }
                        }
                    }
                }
            } header: {
                Text("Warp to display")
            } footer: {
                Text("Displays are numbered left-to-right. WarpSpeed re-detects them automatically when you plug or unplug a screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if displayManager.displays.count > 1 {
                Section {
                    KeyboardShortcuts.Recorder("Previous display", name: .cycleLeft)
                    KeyboardShortcuts.Recorder("Next display", name: .cycleRight)
                } header: {
                    Text("Cycle between displays")
                } footer: {
                    Text("Cycles wrap around — past the rightmost screen you'll land on the leftmost, and vice versa.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                KeyboardShortcuts.Recorder("Focus next window", name: .windowNext)
                KeyboardShortcuts.Recorder("Focus previous window", name: .windowPrevious)

                Toggle("Only cycle visible windows", isOn: $visibleWindowsOnly)
                    .onChange(of: visibleWindowsOnly) { _, newValue in
                        WarpSettings.cycleVisibleWindowsOnly = newValue
                    }

                HStack(spacing: 8) {
                    Image(systemName: accessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .foregroundStyle(accessibilityTrusted ? .green : .orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(accessibilityTrusted ? "Accessibility access granted" : "Accessibility access needed")
                            .font(.callout)
                        if !accessibilityTrusted {
                            Text("Required to move focus between windows.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !accessibilityTrusted {
                        Button("Grant…") { WindowCycler.requestAccessibility() }
                    }
                }
            } header: {
                Text("Cycle windows")
            } footer: {
                Text("Steps focus through windows left-to-right across your displays, wrapping around, with the cursor following. \"Only cycle visible windows\" skips any window hidden behind another.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                KeyboardShortcuts.Recorder("Toggle laser pointer", name: .laserToggle)

                Toggle("Laser pointer on", isOn: Binding(
                    get: { laser.isActive },
                    set: { laser.setActive($0) }
                ))

                ColorPicker("Colour", selection: Binding(
                    get: { laser.config.color },
                    set: { laser.config.setColor($0) }
                ), supportsOpacity: false)

                HStack {
                    Text("Dot size")
                    Slider(value: $laser.config.dotSize, in: 10...44)
                    Text("\(Int(laser.config.dotSize))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 24, alignment: .trailing)
                }

                Toggle("Motion trail", isOn: $laser.config.trailEnabled)

                if laser.config.trailEnabled {
                    HStack {
                        Text("Trail length")
                        Slider(value: $laser.config.trailDuration, in: 0.1...1.0)
                        Text(String(format: "%.2fs", laser.config.trailDuration))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                    HStack {
                        Text("Trail thickness")
                        Slider(value: $laser.config.trailThickness, in: 2...24)
                        Text("\(Int(laser.config.trailThickness))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 24, alignment: .trailing)
                    }
                }
            } header: {
                Text("Laser pointer")
            } footer: {
                Text("Turns your cursor into a presenter's laser for screen sharing. It appears in the stream only when you share your **whole screen** — sharing a single window (or a PowerPoint slideshow) captures just that window, not the overlay. Toggle it any time with the hotkey.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                VStack(spacing: 6) {
                    ForEach(WarpEffect.allCases) { effect in
                        EffectRow(
                            effect: effect,
                            isSelected: effect == selectedEffect
                        ) {
                            selectedEffect = effect
                        }
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text("Warp effect")
            } footer: {
                Text("Pick one — tapping a card plays it on whichever screen your cursor is on, so you can sample before committing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LaunchAtLoginManager.setEnabled(newValue)
                        launchAtLogin = LaunchAtLoginManager.isEnabled
                    }
            }

            Section {
                HStack {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("WarpSpeed")
                            .font(.headline)
                        Text("Instantly warp your cursor across displays.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, idealWidth: 480)
        .onChange(of: selectedEffect) { _, newValue in
            WarpSettings.currentEffect = newValue
            previewSelection(newValue)
        }
        .onReceive(trustTimer) { _ in
            accessibilityTrusted = WindowCycler.isTrusted
        }
    }

    private func previewSelection(_ effect: WarpEffect) {
        let mouse = NSEvent.mouseLocation
        let display = displayManager.display(containing: mouse)
            ?? displayManager.displays.first
        guard let display else { return }
        warper.preview(effect: effect, on: display)
    }
}

private struct EffectRow: View {
    let effect: WarpEffect
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected
                              ? Color.accentColor
                              : Color.accentColor.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: effect.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(effect.displayName)
                        .font(.headline)
                    Text(effect.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected
                          ? Color.accentColor.opacity(0.08)
                          : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected
                                  ? Color.accentColor.opacity(0.5)
                                  : Color.secondary.opacity(0.18),
                                  lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
