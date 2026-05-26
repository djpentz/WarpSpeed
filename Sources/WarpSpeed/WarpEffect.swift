import Foundation
import SwiftUI

enum WarpEffect: String, CaseIterable, Identifiable {
    case streaks    = "streaks"
    case sonar      = "sonar"
    case blackHole  = "blackHole"
    case comicPop   = "comicPop"
    case spotlight  = "spotlight"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .streaks:   return "Warp Streaks"
        case .sonar:     return "Sonar Ping"
        case .blackHole: return "Black Hole"
        case .comicPop:  return "Comic Pop!"
        case .spotlight: return "Spotlight"
        }
    }

    var subtitle: String {
        switch self {
        case .streaks:   return "Stars rush inward to your cursor. Pure hyperdrive."
        case .sonar:     return "A calm radar ping radiates out from the landing point."
        case .blackHole: return "Reality folds in on itself. Drama."
        case .comicPop:  return "Big yellow starburst, comic-book swagger. Different word each time."
        case .spotlight: return "Stage lights find your cursor while everything else fades."
        }
    }

    var symbol: String {
        switch self {
        case .streaks:   return "sparkles"
        case .sonar:     return "dot.radiowaves.up.forward"
        case .blackHole: return "tornado"
        case .comicPop:  return "burst.fill"
        case .spotlight: return "flashlight.on.fill"
        }
    }

    var duration: Double {
        switch self {
        case .streaks:   return 0.35
        case .sonar:     return 0.65
        case .blackHole: return 0.55
        case .comicPop:  return 0.60
        case .spotlight: return 0.65
        }
    }
}

enum WarpSettings {
    private static let effectKey = "warpspeed.effect"

    static var currentEffect: WarpEffect {
        get {
            let raw = UserDefaults.standard.string(forKey: effectKey) ?? WarpEffect.streaks.rawValue
            return WarpEffect(rawValue: raw) ?? .streaks
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: effectKey)
        }
    }
}

struct WarpEffectHost: View {
    let effect: WarpEffect
    let token: UUID

    var body: some View {
        Group {
            switch effect {
            case .streaks:   WarpStreaksEffect(token: token)
            case .sonar:     SonarPingEffect(token: token)
            case .blackHole: BlackHoleEffect(token: token)
            case .comicPop:  ComicPopEffect(token: token)
            case .spotlight: SpotlightEffect(token: token)
            }
        }
        .id(token)
        .ignoresSafeArea()
    }
}
