# WarpSpeed

macOS menu-bar utility: warp the cursor between displays via global hotkeys (with visual effects) and cycle window focus across displays. Native Swift, SPM-only (no Xcode project), macOS 14+. Personal project.

## 🔑 Read first: `.claude/HANDOFF.md`

**If `.claude/HANDOFF.md` exists, read it before doing any work.** It's only present when a previous session left a handoff — when it is, it has the current release state, the cross-machine patch workflow, build/run steps, architecture, and the hard-won gotchas. The essentials below apply either way, so they're never missed:

- **Release state:** **v0.1.4** is merged to `origin/main` and tagged. **v0.1.5** (presenter laser pointer) is prepared as a patch from the work laptop, pending `git am` + PR on personal.
- **Cross-machine:** personal laptop (`djpentz` / `djpentz@gmail.com`) is canonical origin; the work laptop contributes via `git format-patch` → `git am`. Use a repo-local personal git identity on the work laptop; don't push the personal repo from there.
- **Sleep-degradation bug is SOLVED** — cause was duplicate `KeyboardShortcuts` handlers accumulating on each display re-handshake (handlers are registered once now). **Do NOT re-chase the old "cold-pipeline / `EffectClock` timing" theory — it was a misdiagnosis.**
- **Verify timing/effect fixes against a real `pmset sleepnow`, never a rebuild** — a rebuild clears the degraded state and false-confirms.
- **Accessibility needs stable signing:** run `scripts/setup-signing.sh` once per dev machine, or a lapsed TCC grant will look exactly like a broken feature.

## Taste
Keep it small (no over-architecting). **Delight is a first-class requirement** — propose playful touches, don't bury them. The owner delegates design calls but wants the reasoning and pushes back well; engage.
