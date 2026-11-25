import SwiftUI
import CoreGraphics

enum AppScreen: Equatable {
    case home
    case select
    case ready
    case countdown
    case inGame
    case clear
}

enum GameType: String, CaseIterable, Identifiable {
    case fruit
    case balloon
    case freeze

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fruit: return "과일 팡팡"
        case .balloon: return "풍선 배구"
        case .freeze: return "얼음 땡!"
        }
    }

    var cardImageName: String {
        switch self {
        case .fruit: return "card_fruit"
        case .balloon: return "card_balloon"
        case .freeze: return "card_freeze"
        }
    }

    func intensityLevel(quietMode: Bool) -> Int {
        switch self {
        case .fruit: return 2
        case .balloon: return 1
        case .freeze: return quietMode ? 1 : 3
        }
    }

    func intensityLabel(quietMode: Bool) -> String {
        switch intensityLevel(quietMode: quietMode) {
        case 1: return "살살"
        case 2: return "보통"
        default: return "힘껏"
        }
    }
}

enum PlaySpeed: String, CaseIterable {
    case slow
    case normal
    case fast

    var label: String {
        switch self {
        case .slow: return "느림(4세)"
        case .normal: return "보통"
        case .fast: return "빠름(6세)"
        }
    }

    var speedMult: CGFloat {
        switch self {
        case .slow: return 0.75
        case .normal: return 1.0
        case .fast: return 1.28
        }
    }

    var hitboxMult: CGFloat {
        switch self {
        case .slow: return 1.35
        case .normal: return 1.16
        case .fast: return 1.0
        }
    }

    /// 공리 1: 속도 기반 베기 임계치 (pt/s — 실카메라 팔 휘두르기에 최적화, 정지 시 절대 불가)
    var minSlashVelocity: CGFloat {
        switch self {
        case .slow: return 130
        case .normal: return 190
        case .fast: return 260
        }
    }
}

final class AppSettings: ObservableObject {
    @AppStorage("pp_players") var players: Int = 2
    @AppStorage("pp_quiet") var quietMode: Bool = true
    @AppStorage("pp_speed") var speedRaw: String = PlaySpeed.normal.rawValue
    @AppStorage("pp_volume") var volume: Double = 0.8
    @AppStorage("pp_devMode") var devMode: Bool = false

    var speed: PlaySpeed {
        get { PlaySpeed(rawValue: speedRaw) ?? .normal }
        set { speedRaw = newValue.rawValue; objectWillChange.send() }
    }
}

/// Normalized [0..1] pose coordinates (top-left origin for SwiftUI, converted for SpriteKit)
struct PlayerPose: Identifiable {
    let id: Int // 0 = P1 (Momo, left), 1 = P2 (Popo, right)
    var centerX: CGFloat
    var centerY: CGFloat
    var head: CGPoint
    var leftHand: CGPoint
    var rightHand: CGPoint
    var handsUp: Bool
    var motion: CGFloat
}

/// Bundle resource image loader (supports PNG & JPG in Resources/)
enum BundleImage {
    static func uiImage(named name: String) -> UIImage? {
        if let path = Bundle.main.path(forResource: name, ofType: "png"),
           let img = UIImage(contentsOfFile: path) {
            return img
        }
        if let path = Bundle.main.path(forResource: name, ofType: "jpg"),
           let img = UIImage(contentsOfFile: path) {
            return img
        }
        return UIImage(named: name)
    }

    static func swiftUIImage(named name: String) -> Image {
        if let ui = uiImage(named: name) {
            return Image(uiImage: ui)
        }
        return Image(systemName: "sparkles")
    }
}
