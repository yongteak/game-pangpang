import SwiftUI
import UIKit
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
    case animal
    case jungle
    case mole
    case balance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fruit: return "과일 팡팡"
        case .balloon: return "풍선 배구"
        case .freeze: return "얼음 땡!"
        case .animal: return "동물 흉내 포즈"
        case .jungle: return "달려라! 정글 모험"
        case .mole: return "두더지 하이파이브"
        case .balance: return "외나무다리 균형"
        }
    }

    var cardImageName: String {
        switch self {
        case .fruit: return "card_fruit"
        case .balloon: return "card_balloon"
        case .freeze: return "card_freeze"
        case .animal: return "card_animal"
        case .jungle: return "card_jungle"
        case .mole: return "card_mole"
        case .balance: return "card_balance"
        }
    }

    func intensityLevel(quietMode: Bool) -> Int {
        switch self {
        case .fruit: return 2
        case .balloon: return 1
        case .freeze: return quietMode ? 1 : 3
        case .animal: return 2
        case .jungle: return 3
        case .mole: return 2
        case .balance: return 2
        }
    }

    func intensityLabel(quietMode: Bool) -> String {
        switch self {
        case .animal: return "전신 포즈"
        case .jungle: return "전신 모험"
        case .mole: return "손·발 터치"
        case .balance: return "전신 균형"
        default:
            switch intensityLevel(quietMode: quietMode) {
            case 1: return "살살"
            case 2: return "보통"
            default: return "힘껏"
            }
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

/// Torso-normalized 14-joint full-body metrics (scale & camera-distance invariant!)
struct FullBodyMetrics {
    var torsoH: CGFloat = 0.22
    var shoulderW: CGFloat = 0.16
    var shoulderY: CGFloat = 0.45
    var hipY: CGFloat = 0.67
    var lElbowAngle: CGFloat = 165
    var rElbowAngle: CGFloat = 165
    var lKneeAngle: CGFloat = 175
    var rKneeAngle: CGFloat = 175
    var wristSpan: CGFloat = 0.18
    var ankleSpan: CGFloat = 0.14
    var footLift: CGFloat = 0.0
    var torsoLean: CGFloat = 0.0
    var torsoLeanSigned: CGFloat = 0.0
    var isSquatting: Bool = false
    var lShoulder: CGPoint = CGPoint(x: 0.44, y: 0.45)
    var rShoulder: CGPoint = CGPoint(x: 0.56, y: 0.45)
    var lElbow: CGPoint = CGPoint(x: 0.42, y: 0.52)
    var rElbow: CGPoint = CGPoint(x: 0.58, y: 0.52)
    var lHip: CGPoint? = nil
    var rHip: CGPoint? = nil
    var lKnee: CGPoint? = nil
    var rKnee: CGPoint? = nil
    var lAnkle: CGPoint? = nil
    var rAnkle: CGPoint? = nil
    var neck: CGPoint? = nil

    // Per-joint smoothed confidence [0..1] (EMA + 0.45s temporal occlusion persistence)
    var headConf: CGFloat = 1.0
    var neckConf: CGFloat = 1.0
    var lShoulderConf: CGFloat = 1.0
    var rShoulderConf: CGFloat = 1.0
    var lElbowConf: CGFloat = 1.0
    var rElbowConf: CGFloat = 1.0
    var lWristConf: CGFloat = 1.0
    var rWristConf: CGFloat = 1.0
    var lHipConf: CGFloat = 0.0
    var rHipConf: CGFloat = 0.0
    var lKneeConf: CGFloat = 0.0
    var rKneeConf: CGFloat = 0.0
    var lAnkleConf: CGFloat = 0.0
    var rAnkleConf: CGFloat = 0.0
}

struct AirCursorState: Equatable {
    var active: Bool = false
    var x: CGFloat = 0.5
    var y: CGFloat = 0.5
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
    var metrics: FullBodyMetrics = FullBodyMetrics()
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

/// Shared Korean game font (Google Fonts Jua, OFL) + sticker-style typography helper
enum AppFont {
    /// Exact PostScript font name verified from Jua-Regular.ttf (CoreText & TrueType nameID 6)
    static let juaPostScriptName: String = "Jua-Regular"

    static func uiFont(size: CGFloat) -> UIFont {
        if let font = UIFont(name: juaPostScriptName, size: size) {
            return font
        }
        if let font = UIFont(name: "Jua", size: size) {
            return font
        }
        let base = UIFont.systemFont(ofSize: size, weight: .heavy)
        if let rounded = base.fontDescriptor.withDesign(.rounded) {
            return UIFont(descriptor: rounded, size: size)
        }
        return base
    }

    static func swiftUIFont(size: CGFloat) -> Font {
        Font.custom(juaPostScriptName, size: size)
    }

    /// PixiJS-parity sticker text for SpriteKit SKLabelNode.attributedText:
    /// Jua font + fill color + thick colored outline (negative strokeWidth renders both fill & stroke)
    /// + soft drop shadow + centered paragraph alignment.
    static func stickerAttributedText(
        _ text: String,
        fontSize: CGFloat,
        strokeColor: UIColor,
        strokeWidth: CGFloat = 7.0,
        fillColor: UIColor = .white,
        shadowAlpha: CGFloat = 0.28
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping

        var attributes: [NSAttributedString.Key: Any] = [
            .font: uiFont(size: fontSize),
            .foregroundColor: fillColor,
            .strokeColor: strokeColor,
            .strokeWidth: -abs(strokeWidth),
            .paragraphStyle: paragraph
        ]

        if shadowAlpha > 0 {
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(shadowAlpha)
            shadow.shadowOffset = CGSize(width: 0, height: max(2.0, fontSize * 0.06))
            shadow.shadowBlurRadius = max(3.0, fontSize * 0.10)
            attributes[.shadow] = shadow
        }

        return NSAttributedString(string: text, attributes: attributes)
    }
}
