import SwiftUI

// MARK: - Shared helpers

/// Deterministic per-index jitter so each play of an effect is consistent.
private func pseudoRandom(seed: Int) -> Double {
    let x = sin(Double(seed) * 12.9898 + 4.1414) * 43758.5453
    return x - x.rounded(.down)
}

private func easeOutCubic(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
private func easeOutQuad(_ t: Double)  -> Double { 1 - pow(1 - t, 2) }

/// Captures the *first* frame's timestamp instead of the struct-init time, so
/// effects always play their full duration even when the rendering pipeline is
/// cold (e.g. immediately after the display wakes from sleep). Class so the
/// mutation inside the render closure doesn't invalidate the view.
final class EffectClock {
    var start: Date?
}

// MARK: - 1. Warp Streaks (existing)

struct WarpStreaksEffect: View {
    let token: UUID
    @State private var clock = EffectClock()
    private let duration: Double = WarpEffect.streaks.duration
    private let streakCount: Int = 36

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { ctx in
            Canvas { context, size in
                let start = clock.start ?? { clock.start = ctx.date; return ctx.date }()
                let elapsed = ctx.date.timeIntervalSince(start)
                let progress = min(max(elapsed / duration, 0), 1)
                if progress >= 1 { return }

                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxRadius = max(size.width, size.height) * 0.55
                let eased = easeOutCubic(progress)
                let alpha = progress < 0.4 ? 1.0 : max(0, 1 - (progress - 0.4) / 0.6)

                for i in 0..<streakCount {
                    let angle = Double(i) / Double(streakCount) * 2 * .pi
                    let jitter = pseudoRandom(seed: i)
                    let startRadius = maxRadius * (0.65 + 0.35 * jitter)
                    let speedBias  = 0.85 + 0.3 * jitter

                    let headRadius = max(0, startRadius * (1 - eased * speedBias))
                    let tailRadius = max(headRadius, startRadius * (1 - max(eased * speedBias - 0.18, 0)))

                    let head = CGPoint(x: center.x + cos(angle) * headRadius,
                                       y: center.y + sin(angle) * headRadius)
                    let tail = CGPoint(x: center.x + cos(angle) * tailRadius,
                                       y: center.y + sin(angle) * tailRadius)

                    var path = Path()
                    path.move(to: tail)
                    path.addLine(to: head)
                    context.stroke(
                        path,
                        with: .color(.white.opacity(alpha * 0.85)),
                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                    )
                }

                let glowAlpha = max(0, (1 - eased) * 0.35)
                if glowAlpha > 0.01 {
                    let glowR: CGFloat = 60
                    let glowRect = CGRect(x: center.x - glowR, y: center.y - glowR,
                                          width: glowR * 2, height: glowR * 2)
                    context.fill(
                        Path(ellipseIn: glowRect),
                        with: .radialGradient(
                            Gradient(colors: [.white.opacity(glowAlpha), .clear]),
                            center: center, startRadius: 0, endRadius: glowR
                        )
                    )
                }
            }
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - 2. Sonar Ping

struct SonarPingEffect: View {
    let token: UUID
    @State private var clock = EffectClock()
    private let duration: Double = WarpEffect.sonar.duration
    private let ringCount: Int = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { ctx in
            Canvas { context, size in
                let start = clock.start ?? { clock.start = ctx.date; return ctx.date }()
                let elapsed = ctx.date.timeIntervalSince(start)
                let progress = min(max(elapsed / duration, 0), 1)
                if progress >= 1 { return }

                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxRadius = min(size.width, size.height) * 0.42
                let ringColor = Color(red: 0.35, green: 0.85, blue: 1.0)

                for i in 0..<ringCount {
                    let offset = Double(i) * 0.13
                    let ringProgress = max(0, progress - offset)
                    if ringProgress <= 0 || offset >= 1 { continue }
                    let normalized = min(ringProgress / (1 - offset), 1)
                    let eased = easeOutQuad(normalized)

                    let radius = maxRadius * eased
                    let alpha = (1 - normalized) * 0.85

                    let rect = CGRect(x: center.x - radius, y: center.y - radius,
                                      width: radius * 2, height: radius * 2)
                    context.stroke(
                        Path(ellipseIn: rect),
                        with: .color(ringColor.opacity(alpha)),
                        style: StrokeStyle(lineWidth: 2.5)
                    )
                }

                // Bright origin dot, fades fastest.
                let dotAlpha = max(0, 1 - progress * 1.6)
                if dotAlpha > 0 {
                    let r: CGFloat = 7
                    let glowR: CGFloat = 28
                    context.fill(
                        Path(ellipseIn: CGRect(x: center.x - glowR, y: center.y - glowR,
                                               width: glowR * 2, height: glowR * 2)),
                        with: .radialGradient(
                            Gradient(colors: [ringColor.opacity(dotAlpha * 0.5), .clear]),
                            center: center, startRadius: 0, endRadius: glowR
                        )
                    )
                    context.fill(
                        Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r,
                                               width: r * 2, height: r * 2)),
                        with: .color(ringColor.opacity(dotAlpha))
                    )
                }
            }
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - 3. Black Hole

struct BlackHoleEffect: View {
    let token: UUID
    @State private var clock = EffectClock()
    private let duration: Double = WarpEffect.blackHole.duration
    private let particleCount: Int = 56

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { ctx in
            Canvas { context, size in
                let start = clock.start ?? { clock.start = ctx.date; return ctx.date }()
                let elapsed = ctx.date.timeIntervalSince(start)
                let progress = min(max(elapsed / duration, 0), 1)
                if progress >= 1 { return }

                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxRadius = min(size.width, size.height) * 0.42
                let eased = easeOutQuad(progress)

                for i in 0..<particleCount {
                    let seed   = pseudoRandom(seed: i)
                    let seed2  = pseudoRandom(seed: i + 137)
                    let seed3  = pseudoRandom(seed: i + 271)

                    let initialAngle = seed * 2 * .pi
                    let startRadius  = maxRadius * (0.45 + 0.55 * seed2)
                    let spinSpeed    = 3.8 + 2.6 * seed3

                    let currentRadius = max(0, startRadius * (1 - eased))
                    let angle         = initialAngle + eased * spinSpeed

                    // Short trailing arc behind the particle, against its direction of travel.
                    let trailDelta: Double = 0.45
                    let trailRadius = max(currentRadius, startRadius * (1 - max(eased - 0.12, 0)))
                    let head = CGPoint(x: center.x + cos(angle) * currentRadius,
                                       y: center.y + sin(angle) * currentRadius)
                    let tail = CGPoint(x: center.x + cos(angle - trailDelta) * trailRadius,
                                       y: center.y + sin(angle - trailDelta) * trailRadius)

                    var path = Path()
                    path.move(to: tail)
                    path.addLine(to: head)

                    let alpha = progress < 0.75 ? 1.0 : max(0, 1 - (progress - 0.75) / 0.25)
                    // Magenta → cyan-violet streaks depending on seed.
                    let hue = 0.72 + 0.13 * seed
                    let color = Color(hue: hue, saturation: 0.9, brightness: 1.0)

                    context.stroke(
                        path,
                        with: .color(color.opacity(alpha * 0.9)),
                        style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                    )
                }

                // Collapsing event-horizon disc.
                let coreR: CGFloat = max(4, 70 * (1 - eased))
                let haloR: CGFloat = coreR * 2.2
                let coreAlpha = max(0, 1 - progress * 0.6)
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - haloR, y: center.y - haloR,
                                           width: haloR * 2, height: haloR * 2)),
                    with: .radialGradient(
                        Gradient(colors: [
                            Color(hue: 0.78, saturation: 0.6, brightness: 0.4).opacity(coreAlpha),
                            .black.opacity(coreAlpha * 0.85),
                            .clear
                        ]),
                        center: center, startRadius: 0, endRadius: haloR
                    )
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - coreR, y: center.y - coreR,
                                           width: coreR * 2, height: coreR * 2)),
                    with: .color(.black.opacity(coreAlpha))
                )
            }
            .blendMode(.screen)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - 4. Comic Pop!

struct ComicPopEffect: View {
    let token: UUID
    @State private var clock = EffectClock()
    @State private var word: String = ComicPopEffect.popWords.randomElement() ?? "POP!"
    private let duration: Double = WarpEffect.comicPop.duration

    private static let popWords = [
        "WARP!", "POP!", "ZOOM!", "ZAP!", "BAM!",
        "WHAM!", "BOOM!", "POW!", "ZIP!", "BLAM!",
        "WHOOSH!", "KAPOW!", "SNAP!", "ZWOOSH!", "PING!"
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { ctx in
            let start = clock.start ?? { clock.start = ctx.date; return ctx.date }()
            let elapsed = ctx.date.timeIntervalSince(start)
            let progress = min(max(elapsed / duration, 0), 1)

            ZStack {
                if progress < 1 {
                    let popEased = 1 - pow(1 - min(progress * 2.2, 1), 3)
                    let scale    = 0.35 + 0.75 * popEased
                    let wiggle   = sin(progress * 14) * 4
                    let alpha: Double = progress < 0.65 ? 1.0 : max(0, 1 - (progress - 0.65) / 0.35)

                    // Yellow starburst behind the text, drawn with a comic-book ink outline.
                    Canvas { context, size in
                        let center = CGPoint(x: size.width / 2, y: size.height / 2)
                        let burstR: CGFloat = 150 * scale
                        let spikes = 14
                        var path = Path()
                        for i in 0..<spikes {
                            let a = Double(i) / Double(spikes) * 2 * .pi
                            let outerWobble = 1.0 + 0.12 * sin(Double(i) * 1.7)
                            let r1 = burstR * outerWobble
                            let r2 = burstR * 0.55
                            let p1 = CGPoint(x: center.x + cos(a) * r1,
                                             y: center.y + sin(a) * r1)
                            let mid = a + .pi / Double(spikes)
                            let p2 = CGPoint(x: center.x + cos(mid) * r2,
                                             y: center.y + sin(mid) * r2)
                            if i == 0 { path.move(to: p1) } else { path.addLine(to: p1) }
                            path.addLine(to: p2)
                        }
                        path.closeSubpath()
                        context.fill(path, with: .color(Color(red: 1.0, green: 0.86, blue: 0.15).opacity(alpha)))
                        context.stroke(path, with: .color(.black.opacity(alpha)), lineWidth: 4.0)
                    }

                    Text(word)
                        .font(.system(size: 96, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.94, green: 0.18, blue: 0.18))
                        .shadow(color: .black, radius: 0, x: 3, y: 3)
                        .shadow(color: .black, radius: 0, x: -3, y: -3)
                        .shadow(color: .black, radius: 0, x: 3, y: -3)
                        .shadow(color: .black, radius: 0, x: -3, y: 3)
                        .scaleEffect(scale)
                        .rotationEffect(.degrees(-6 + wiggle))
                        .opacity(alpha)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 5. Spotlight

struct SpotlightEffect: View {
    let token: UUID
    @State private var clock = EffectClock()
    private let duration: Double = WarpEffect.spotlight.duration

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { ctx in
            Canvas { context, size in
                let start = clock.start ?? { clock.start = ctx.date; return ctx.date }()
                let elapsed = ctx.date.timeIntervalSince(start)
                let progress = min(max(elapsed / duration, 0), 1)
                if progress >= 1 { return }

                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let spotRadius: CGFloat = 110 + 25 * sin(progress * .pi)

                // Phase-based alphas: dim peaks early, glow peaks middle, both fade out.
                let dimAlpha: Double = {
                    let rampUp = min(progress / 0.18, 1.0)
                    let rampDown = max(0, 1 - (progress - 0.35) / 0.65)
                    return rampUp * rampDown * 0.55
                }()
                let glowAlpha: Double = {
                    let rampUp = min(progress / 0.12, 1.0)
                    let rampDown = max(0, 1 - (progress - 0.3) / 0.7)
                    return rampUp * rampDown
                }()

                // Dim the whole screen with a circular cutout at the cursor.
                if dimAlpha > 0.005 {
                    var mask = Path(CGRect(origin: .zero, size: size))
                    mask.addPath(Path(ellipseIn: CGRect(
                        x: center.x - spotRadius, y: center.y - spotRadius,
                        width: spotRadius * 2, height: spotRadius * 2
                    )))
                    context.fill(mask, with: .color(.black.opacity(dimAlpha)), style: FillStyle(eoFill: true))
                }

                // Warm spotlight wash over the cursor.
                let glowR: CGFloat = spotRadius * 1.3
                let glowRect = CGRect(x: center.x - glowR, y: center.y - glowR,
                                      width: glowR * 2, height: glowR * 2)
                context.fill(
                    Path(ellipseIn: glowRect),
                    with: .radialGradient(
                        Gradient(colors: [
                            Color(red: 1.0, green: 0.93, blue: 0.7).opacity(glowAlpha * 0.55),
                            Color(red: 1.0, green: 0.85, blue: 0.5).opacity(glowAlpha * 0.22),
                            .clear
                        ]),
                        center: center, startRadius: 0, endRadius: glowR
                    )
                )

                // Crisp pinpoint at the exact landing.
                let pinR: CGFloat = 5
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - pinR, y: center.y - pinR,
                                           width: pinR * 2, height: pinR * 2)),
                    with: .color(.white.opacity(glowAlpha * 0.9))
                )
            }
            .allowsHitTesting(false)
        }
    }
}
