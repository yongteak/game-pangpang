import SpriteKit
import SwiftUI

/// Native SpriteKit 60fps GPU game engine:
/// - 90-second Fruit Ninja Zen Mode + Redi & Ludi 3-Boss Relay (Pineapple -> Melon -> Watermelon King)
/// - 8 distinct 3D clay fruits launched from ALL 5 directions + gravity + wall bounce + fruit-to-fruit elastic collisions
/// - Multi-hit Tough Fruits (HP 2~3) with knockback bounce & HP dots
/// - Implements all 7 Motion Action Mathematical Axioms.
final class KidsGameScene: SKScene {
    weak var cameraManager: VisionCameraManager?
    var settings = AppSettings()
    var gameType: GameType = .fruit

    var onScore: ((Int) -> Void)?
    var onProgress: ((Int, Int) -> Void)?
    var onCallout: ((String, TimeInterval) -> Void)?
    var onFinish: ((String) -> Void)?

    private var lastUpdate: TimeInterval = 0
    private var elapsed: TimeInterval = 0
    private var isFinished = false
    private var isGamePaused = false
    private var score = 0
    private var combo = 0
    private var comboTimer: CGFloat = 0
    private var hitstopTimer: CGFloat = 0
    private var screenShake: CGFloat = 0
    private var emaMotion: CGFloat = 0
    private var feverActive = false

    private var prevHands: [CGPoint?] = [nil, nil, nil, nil]
    private var handEnergy: [CGFloat] = [0, 0, 0, 0]
    private var swooshCooldown: [CGFloat] = [0, 0, 0, 0]
    private var handTrails: [[CGPoint]] = [[], [], [], []]

    private let worldNode = SKNode()
    private let splatLayer = SKNode()
    private let trailLayer = SKNode()
    private let gameLayer = SKNode()
    private let fxLayer = SKNode()
    private let feverBorder = SKShapeNode()
    private let flashNode = SKSpriteNode(color: .white, size: .zero)

    private struct HandHaloRig {
        let container: SKNode
        let outerGlow: SKShapeNode
        let midRing: SKShapeNode
        let innerCore: SKShapeNode
    }
    private struct TrailBand {
        let color: UIColor
        let offsetY: CGFloat
        let baseWidth: CGFloat
        let segments: [SKShapeNode]
    }
    private struct HandTrailRig {
        let container: SKNode
        let bands: [TrailBand]
    }
    private let maxTrailPoints = 13
    private var haloRigs: [HandHaloRig] = []
    private var trailRigs: [HandTrailRig] = []

    // Parabolic VFX Physics Pools (60fps Metal, zero leaks)
    private struct BurstParticle {
        let node: SKShapeNode
        var vx: CGFloat
        var vy: CGFloat
        let vrot: CGFloat
        var life: CGFloat
        let maxLife: CGFloat
        let baseScale: CGFloat
        let isStar: Bool
    }
    private struct ActiveBubble {
        let node: SKShapeNode
        var vx: CGFloat
        var vy: CGFloat
        let seed: CGFloat
        var life: CGFloat
    }
    private struct SlicedHalf {
        let node: SKSpriteNode
        var vx: CGFloat
        var vy: CGFloat
        let vrot: CGFloat
        var life: CGFloat
        let maxLife: CGFloat
    }
    private var burstParticles: [BurstParticle] = []
    private var activeBubbles: [ActiveBubble] = []
    private var slicedHalves: [SlicedHalf] = []
    private lazy var unitStarPath: CGPath = makeStarPath(outerR: 14.5, innerR: 6.0)
    private lazy var unitDropletPath: CGPath = CGPath(ellipseIn: CGRect(x: -10, y: -10, width: 20, height: 20), transform: nil)

    // 90s Zen Fruit state
    private let zenDuration: CGFloat = 90.0
    private var zenElapsed: CGFloat = 0
    private var feverBurstTimer: CGFloat = 0
    private var spawnTimer: CGFloat = 0.25
    private var bossIndex = 0

    private struct BossConfig {
        let triggerTime: CGFloat
        let texKey: String
        let name: String
        let hits2p: Int
        let hits1p: Int
        let bonus: Int
        let color: UIColor
    }
    private let bossSchedule: [BossConfig] = [
        BossConfig(triggerTime: 22, texKey: "fruit_pineapple", name: "거대 파인애플", hits2p: 26, hits1p: 18, bonus: 12, color: .systemYellow),
        BossConfig(triggerTime: 48, texKey: "fruit_melon", name: "거대 황금 멜론", hits2p: 34, hits1p: 24, bonus: 15, color: UIColor(red: 0.32, green: 0.85, blue: 0.65, alpha: 1)),
        BossConfig(triggerTime: 72, texKey: "watermelon", name: "거대 수박 왕", hits2p: 45, hits1p: 32, bonus: 25, color: .systemPink),
    ]

    private struct ActiveFruit {
        let node: SKSpriteNode
        let auraNode: SKShapeNode
        let orbitNode: SKNode?
        let hpDotsNode: SKNode?
        let kind: String
        let special: String // normal | golden | rainbow
        let color: UIColor
        var hp: Int
        let maxHp: Int
        var hitCooldown: CGFloat
        var bouncesLeft: Int
        var vx: CGFloat
        var vy: CGFloat
        var vrot: CGFloat
        var radius: CGFloat
    }
    private var activeFruits: [ActiveFruit] = []

    // Boss state
    private var activeBossConfig: BossConfig?
    private var bossNode: SKSpriteNode?
    private var bossVfxNode: SKNode?
    private var bossAuraNode: SKShapeNode?
    private var bossOrbitStars: [SKShapeNode] = []
    private var bossBarBg: SKShapeNode?
    private var bossBarFill: SKShapeNode?
    private var bossHits = 0
    private var bossMaxHits = 10
    private var bossShake: CGFloat = 0
    private var bossCooldown: CGFloat = 0

    // Balloon state (리얼 공기역학: 공기저항·부력 흔들림·스핀·바닥 그림자·풍선 끈·풍선 간 충돌 · 200점 목표!)
    private struct ActiveBalloon {
        let node: SKSpriteNode
        let shadowNode: SKShapeNode
        let stringNode: SKShapeNode?
        let orbitNode: SKNode?
        let kind: String // balloon_red | balloon_beach | balloon_gold
        var vx: CGFloat
        var vy: CGFloat
        var vrot: CGFloat
        var radius: CGFloat
        var golden: Bool
        var points: Int
        var cooldown: CGFloat
        let driftSeed: CGFloat
    }
    private var balls: [ActiveBalloon] = []
    private var beachBallSpawned = false
    private var goldBallSpawned = false
    private var nextBalloonMilestone = 50
    private var finishWorkItem: DispatchWorkItem?

    // Freeze / Neon Disco Club state (5라운드 약 1분 구성 · 댄스 6.8~9.0초 · 얼음 3.4~4.8초)
    private var freezeRoundsTotal = 5
    private var freezeRound = 0
    private var isFreezePhase = false
    private var freezeTimer: CGFloat = 7.4
    private var freezeDuration: CGFloat = 3.4
    private var freezeElapsed: CGFloat = 0
    private var freezeWiggleTime: CGFloat = 0
    private var freezeSuccessCount = 0
    private var wiggleSfxCooldown: CGFloat = 0
    private var isWiggling = false
    private var danceEnergy: CGFloat = 0.5
    private var dinoNode: SKSpriteNode?
    private var dinoRing: SKShapeNode?
    private var dancerNodes: [String: SKSpriteNode] = [:]
    private var dancerRings: [String: SKShapeNode] = [:]
    private var clubOverlay: SKSpriteNode?
    private var clubBeams: [SKShapeNode] = []
    private var iceSpotlight: SKShapeNode?
    private var discoBallNode: SKNode?
    private var discoString: SKShapeNode?
    private var discoDots: [SKShapeNode] = []
    private var eqBars: [SKShapeNode] = []
    private var clubBorder: SKShapeNode?
    private var freezeProgBg: SKShapeNode?
    private var freezeProgFill: SKShapeNode?
    private var freezeProgLabel: SKLabelNode?
    private var freezeMeterBg: SKShapeNode?
    private var freezeMeterFill: SKShapeNode?

    // Game 4: Animal Pose Imitation state
    private struct AnimalPoseSpec {
        let id: String
        let tex: String
        let name: String
        let cue: String
        let color: UIColor
    }
    private let animalPoses: [AnimalPoseSpec] = [
        AnimalPoseSpec(id: "giraffe",  tex: "animal_giraffe",  name: "기린",     cue: "두 팔을 머리 위로 쭉!",        color: .systemYellow),
        AnimalPoseSpec(id: "eagle",    tex: "animal_eagle",    name: "독수리",   cue: "두 팔을 양옆으로 활짝!",       color: .systemOrange),
        AnimalPoseSpec(id: "crab",     tex: "animal_crab",     name: "꽃게",     cue: "양팔을 꺾어 집게손 쫙!",       color: .systemRed),
        AnimalPoseSpec(id: "flamingo", tex: "animal_flamingo", name: "플라밍고", cue: "한 발 들고 균형 잡기!",        color: .systemPink),
        AnimalPoseSpec(id: "frog",     tex: "animal_frog",     name: "개구리",   cue: "바닥으로 쏙 웅크리기!",        color: .systemGreen),
        AnimalPoseSpec(id: "elephant", tex: "animal_elephant", name: "코끼리",   cue: "몸을 옆으로 기울여 흔들기!",   color: .systemCyan),
        AnimalPoseSpec(id: "starfish", tex: "animal_starfish", name: "불가사리", cue: "팔·다리 모두 크게 X자로 쫙!",  color: .systemPurple),
    ]
    private var animalIndex = 0
    private var animalCleared: [Bool] = []
    private let animalTimeLimit: CGFloat = 10.0
    private var animalTimer: CGFloat = 10.0
    private var animalHold: CGFloat = 0
    private let animalHoldTarget: CGFloat = 1.8
    private var animalPause: CGFloat = 0
    private var animalSuccessCount = 0
    private var animalMatchGrace: CGFloat = 0
    private var animalMatchBlend: CGFloat = 0
    private var animalPieFill: SKShapeNode?
    private var animalPieBg: SKShapeNode?
    private var animalGuideNode: SKSpriteNode?
    private var animalGuideGlow: SKShapeNode?
    private var animalNamePill: SKShapeNode?
    private var animalNameLbl: SKLabelNode?
    private var animalCueBg: SKShapeNode?
    private var animalCueLbl: SKLabelNode?
    private var animalBarBg: SKShapeNode?
    private var animalBarFill: SKShapeNode?
    private var animalBarStar: SKShapeNode?
    private var animalSilhouetteRigs: [OrganicSilhouetteRig] = []
    private var animalPoseBadge: CircularMoveBadge?
    private var animalBadgeRings: [SKShapeNode] = []
    private var animalBadgeSprites: [SKSpriteNode] = []

    // Pooled Organic Nintendo Body Silhouette Rig (Zero Wireframe Box, Zero White Dots, Zero Per-Frame Allocations)
    private struct SilhouetteLimb {
        let glow: SKShapeNode
        let main: SKShapeNode
    }
    private struct OrganicSilhouetteRig {
        let root: SKNode
        let spine: SilhouetteLimb
        let shoulderArc: SilhouetteLimb
        let pelvisArc: SilhouetteLimb
        let lUpperArm: SilhouetteLimb
        let lForearm: SilhouetteLimb
        let rUpperArm: SilhouetteLimb
        let rForearm: SilhouetteLimb
        let lThigh: SilhouetteLimb
        let lShin: SilhouetteLimb
        let rThigh: SilhouetteLimb
        let rShin: SilhouetteLimb
        let headHalo: SilhouetteLimb
    }

    // Reusable Creamy Circular Posture/Move Badge (Game 4 & Game 5)
    private struct CircularMoveBadge {
        let container: SKNode
        let glowCircle: SKShapeNode
        let bgCircle: SKShapeNode
        let trackRing: SKShapeNode
        let progressRing: SKShapeNode
        let iconSprite: SKSpriteNode
        let iconNode: SKShapeNode
        let labelBg: SKShapeNode
        let label: SKLabelNode
        let radius: CGFloat
    }

    // Game 5: Jungle Adventure (60s, 3 Full-Body Phases: Run / Squat / Jump)
    private enum JunglePhase: CaseIterable {
        case run, squat, jump
    }
    private let jungleDuration: CGFloat = 60.0
    private var jungleElapsed: CGFloat = 0
    private var junglePhase: JunglePhase = .run
    private var junglePhaseTimer: CGFloat = 0
    private var junglePhaseProgress: CGFloat = 0
    private var jungleRunCooldown: CGFloat = 0
    private var jungleTrackBg: SKShapeNode?
    private var jungleTrackFill: SKShapeNode?
    private var jungleTrackMomo: SKSpriteNode?
    private var jungleFlagNodes: [SKShapeNode] = []
    private var jungleVineNode: SKSpriteNode?
    private var jungleVineFallback: SKShapeNode?
    private var jungleMomoSquat: SKSpriteNode?
    private var junglePhasePill: SKShapeNode?
    private var junglePhaseLbl: SKLabelNode?
    private var jungleBadges: [JunglePhase: CircularMoveBadge] = [:]
    private struct JungleStar {
        let node: SKSpriteNode
        let baseY: CGFloat
        let radius: CGFloat
        let seed: CGFloat
    }
    private var jungleStars: [JungleStar] = []

    // Game 6: Mole Hand-Foot High-Five (60s, 6 Holes: 3 Upper Hands + 3 Lower Foot/Crouch)
    private enum MoleState {
        case idle, rising, up, falling, bonked
    }
    private struct MoleHole {
        let index: Int
        let isUpper: Bool
        let normPos: CGPoint // top-left normalized
        let container: SKNode
        let rimNode: SKShapeNode
        let moleSprite: SKSpriteNode
        let goldAura: SKShapeNode
        let goldOrbitNode: SKNode
        let goldOrbitStars: [SKShapeNode]
        var state: MoleState
        var popProgress: CGFloat
        var stayTimer: CGFloat
        var isGold: Bool
        var cooldown: CGFloat
    }
    private let moleDuration: CGFloat = 60.0
    private var moleElapsed: CGFloat = 0
    private var moleSpawnTimer: CGFloat = 0.45
    private var moleFeverTriggered = false
    private var moleHoles: [MoleHole] = []
    private var footHaloNodes: [SKShapeNode] = []

    // Game 7: Log Bridge Balance (60s, Wind Gusts + TorsoLean/WideArms + One-Leg Bonus + Stars)
    private let balanceDuration: CGFloat = 60.0
    private var balanceElapsed: CGFloat = 0
    private var bridgeAngle: CGFloat = 0
    private var bridgeAngVel: CGFloat = 0
    private var windForce: CGFloat = 0
    private var windTimer: CGFloat = 0
    private var windNextTimer: CGFloat = 2.6
    private var balancePointTick: CGFloat = 0
    private var balanceWobbleCooldown: CGFloat = 0
    private var oneLegActive = false
    private var oneLegTimer: CGFloat = 0
    private var oneLegHold: CGFloat = 0
    private var oneLegNextTimer: CGFloat = 11.0
    private var balanceStarSpawnTimer: CGFloat = 2.2
    private var balanceRiverNode: SKShapeNode?
    private var balanceBridgeNode: SKNode?
    private var balanceLogSprite: SKSpriteNode?
    private var balanceMomo: SKSpriteNode?
    private var balancePopo: SKSpriteNode?
    private var balanceGaugeBg: SKShapeNode?
    private var balanceGaugeSafe: SKShapeNode?
    private var balanceGaugeNeedle: SKShapeNode?
    private var balanceGaugeStatusBg: SKShapeNode?
    private var balanceGaugeStatusLbl: SKLabelNode?
    private var balanceWindLines: [SKShapeNode] = []
    private var balanceOneLegContainer: SKNode?
    private var balanceOneLegRing: SKShapeNode?
    private var balanceOneLegLbl: SKLabelNode?
    private struct BalanceStar {
        let node: SKSpriteNode
        let vx: CGFloat
        let baseY: CGFloat
        let radius: CGFloat
        let seed: CGFloat
    }
    private var balanceStars: [BalanceStar] = []

    private var textures: [String: SKTexture] = [:]

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        view.allowsTransparency = true
        scaleMode = .resizeFill

        if worldNode.parent == nil {
            addChild(worldNode)
            worldNode.addChild(splatLayer)
            worldNode.addChild(trailLayer)
            worldNode.addChild(gameLayer)
            worldNode.addChild(fxLayer)

            feverBorder.fillColor = .clear
            feverBorder.lineWidth = 14
            feverBorder.blendMode = .add
            feverBorder.alpha = 0
            fxLayer.addChild(feverBorder)

            flashNode.anchorPoint = .zero
            flashNode.alpha = 0
            flashNode.blendMode = .add
            flashNode.zPosition = 200
            addChild(flashNode)

            for i in 0..<4 {
                let isP1 = (i < 2)
                let haloCol = isP1
                    ? UIColor(red: 0x5C / 255.0, green: 0xEF / 255.0, blue: 0xE2 / 255.0, alpha: 1.0) // #5CEFE2
                    : UIColor(red: 0xFF / 255.0, green: 0x82 / 255.0, blue: 0x8B / 255.0, alpha: 1.0) // #FF828B

                // 3-Layer Additive Glowing Hand Halo (matching PixiJS L565-L576)
                let haloContainer = SKNode()
                haloContainer.isHidden = true
                haloContainer.zPosition = 42

                let outerGlow = SKShapeNode(circleOfRadius: 28)
                outerGlow.fillColor = haloCol
                outerGlow.strokeColor = .clear
                outerGlow.blendMode = .add
                outerGlow.alpha = 0
                haloContainer.addChild(outerGlow)

                let midRing = SKShapeNode(circleOfRadius: 22)
                midRing.fillColor = .clear
                midRing.strokeColor = haloCol
                midRing.lineWidth = 2.5
                midRing.blendMode = .add
                midRing.alpha = 0
                haloContainer.addChild(midRing)

                let innerCore = SKShapeNode(circleOfRadius: 5)
                innerCore.fillColor = .white
                innerCore.strokeColor = .clear
                innerCore.blendMode = .add
                innerCore.alpha = 0
                haloContainer.addChild(innerCore)

                fxLayer.addChild(haloContainer)
                haloRigs.append(HandHaloRig(container: haloContainer, outerGlow: outerGlow, midRing: midRing, innerCore: innerCore))

                // 3-Band Rainbow Tapered Neon Hand Trail (matching PixiJS L536-L561)
                let bandSpecs: [(UIColor, CGFloat, CGFloat)] = isP1
                    ? [
                        (UIColor(red: 0x5C / 255.0, green: 0xEF / 255.0, blue: 0xE2 / 255.0, alpha: 1.0), -7, 14), // #5CEFE2
                        (UIColor(red: 0xFF / 255.0, green: 0xF3 / 255.0, blue: 0x80 / 255.0, alpha: 1.0),  0, 10), // #FFF380
                        (UIColor(red: 0xA7 / 255.0, green: 0x8B / 255.0, blue: 0xFA / 255.0, alpha: 1.0),  7,  9), // #A78BFA
                    ]
                    : [
                        (UIColor(red: 0xFF / 255.0, green: 0x7D / 255.0, blue: 0x89 / 255.0, alpha: 1.0), -7, 14), // #FF7D89
                        (UIColor(red: 0xFF / 255.0, green: 0xE0 / 255.0, blue: 0x66 / 255.0, alpha: 1.0),  0, 10), // #FFE066
                        (UIColor(red: 0xFF / 255.0, green: 0x9F / 255.0, blue: 0x5A / 255.0, alpha: 1.0),  7,  9), // #FF9F5A
                    ]

                let trailContainer = SKNode()
                trailLayer.addChild(trailContainer)
                var bands: [TrailBand] = []
                for (bCol, bOffset, bWidth) in bandSpecs {
                    var segs: [SKShapeNode] = []
                    segs.reserveCapacity(maxTrailPoints - 1)
                    for _ in 0..<(maxTrailPoints - 1) {
                        let seg = SKShapeNode()
                        seg.strokeColor = bCol
                        seg.fillColor = .clear
                        seg.lineCap = .round
                        seg.lineJoin = .round
                        seg.blendMode = .add
                        seg.isHidden = true
                        seg.alpha = 0
                        trailContainer.addChild(seg)
                        segs.append(seg)
                    }
                    bands.append(TrailBand(color: bCol, offsetY: bOffset, baseWidth: bWidth, segments: segs))
                }
                trailRigs.append(HandTrailRig(container: trailContainer, bands: bands))
            }
        }
        preloadTextures()
    }

    private func preloadTextures() {
        let baseFruits = [
            "fruit_strawberry", "fruit_apple", "fruit_orange", "fruit_banana",
            "fruit_grape", "fruit_peach", "fruit_pineapple", "fruit_melon", "watermelon"
        ]
        var names = [
            "balloon_red", "balloon_beach", "balloon_gold", "dino_sprite",
            "dino_dance1", "dino_dance2", "dino_freeze",
            "momo_dance1", "momo_dance2", "momo_freeze",
            "popo_dance1", "popo_dance2", "popo_freeze",
            "animal_giraffe", "animal_eagle", "animal_crab",
            "animal_flamingo", "animal_frog", "animal_elephant", "animal_starfish",
            "pose_giraffe", "pose_eagle", "pose_crab",
            "pose_flamingo", "pose_frog", "pose_elephant", "pose_starfish",
            "pose_run", "pose_squat", "pose_jump",
            "jungle_vine", "momo_squat", "star_3d",
            "mole_cute", "mole_gold", "log_bridge", "momo", "popo"
        ]
        for k in baseFruits {
            names.append(contentsOf: [k, "\(k)_left", "\(k)_right"])
        }
        for n in names where textures[n] == nil {
            if let ui = BundleImage.uiImage(named: n) {
                textures[n] = SKTexture(image: ui)
            }
        }
    }

    func setPausedState(_ paused: Bool) {
        isGamePaused = paused
        if paused { SoundEngine.shared.pauseBgm() }
    }

    func startGame(type: GameType, settings: AppSettings) {
        finishWorkItem?.cancel()
        finishWorkItem = nil
        self.gameType = type
        self.settings = settings
        preloadTextures()

        gameLayer.removeAllChildren()
        splatLayer.removeAllChildren()
        for pt in burstParticles { pt.node.removeFromParent() }
        burstParticles.removeAll()
        for bb in activeBubbles { bb.node.removeFromParent() }
        activeBubbles.removeAll()
        for hf in slicedHalves { hf.node.removeFromParent() }
        slicedHalves.removeAll()
        activeFruits.removeAll()
        balls.removeAll()
        bossNode = nil
        bossVfxNode = nil
        bossAuraNode = nil
        bossOrbitStars.removeAll()
        bossBarBg = nil
        bossBarFill = nil
        activeBossConfig = nil
        dinoNode = nil
        dinoRing = nil
        dancerNodes.removeAll()
        dancerRings.removeAll()
        clubOverlay = nil
        clubBeams.removeAll()
        iceSpotlight = nil
        discoBallNode = nil
        discoString = nil
        discoDots.removeAll()
        eqBars.removeAll()
        clubBorder = nil
        freezeProgBg = nil
        freezeProgFill = nil
        freezeProgLabel = nil
        freezeMeterBg = nil
        freezeMeterFill = nil
        animalPieBg = nil
        animalPieFill = nil
        animalGuideNode = nil
        animalGuideGlow = nil
        animalNamePill = nil
        animalNameLbl = nil
        animalCueBg = nil
        animalCueLbl = nil
        animalBarBg = nil
        animalBarFill = nil
        animalBarStar = nil
        animalSilhouetteRigs.removeAll()
        animalPoseBadge = nil
        animalMatchGrace = 0
        animalMatchBlend = 0
        animalBadgeRings.removeAll()
        animalBadgeSprites.removeAll()

        // Reset Game 5 (Jungle)
        jungleTrackBg = nil
        jungleTrackFill = nil
        jungleTrackMomo = nil
        jungleFlagNodes.removeAll()
        jungleVineNode = nil
        jungleVineFallback = nil
        jungleMomoSquat = nil
        junglePhasePill = nil
        junglePhaseLbl = nil
        jungleBadges.removeAll()
        jungleStars.removeAll()

        // Reset Game 6 (Mole)
        moleHoles.removeAll()
        for fh in footHaloNodes { fh.removeFromParent() }
        footHaloNodes.removeAll()

        // Reset Game 7 (Balance)
        balanceRiverNode = nil
        balanceBridgeNode = nil
        balanceLogSprite = nil
        balanceMomo = nil
        balancePopo = nil
        balanceGaugeBg = nil
        balanceGaugeSafe = nil
        balanceGaugeNeedle = nil
        balanceGaugeStatusBg = nil
        balanceGaugeStatusLbl = nil
        balanceWindLines.removeAll()
        balanceOneLegContainer = nil
        balanceOneLegRing = nil
        balanceOneLegLbl = nil
        balanceStars.removeAll()

        lastUpdate = 0
        elapsed = 0
        isFinished = false
        isGamePaused = false
        score = 0
        combo = 0
        comboTimer = 0
        hitstopTimer = 0
        screenShake = 0
        emaMotion = 0
        feverActive = false
        prevHands = [nil, nil, nil, nil]
        handEnergy = [0, 0, 0, 0]
        handTrails = [[], [], [], []]
        for s in 0..<4 { hideHandVfx(slot: s) }

        onScore?(0)

        switch type {
        case .fruit:
            zenElapsed = 0
            feverBurstTimer = 0
            spawnTimer = 0.25
            bossIndex = 0
            bossHits = 0
            bossCooldown = 0
            onProgress?(0, 9)
            onCallout?("90초 과일 팡팡! 사방에서 날아와요!", 2.6)
            SoundEngine.shared.startBgm(track: "bgm_fruit", rate: 1.0)

        case .balloon:
            beachBallSpawned = false
            goldBallSpawned = false
            nextBalloonMilestone = 50
            spawnBalloon(kind: "balloon_red", atX: 0.5, golden: false, points: 1)
            onProgress?(0, 10)
            onCallout?("풍선을 200점까지 신나게 띄워요!", 2.8)
            SoundEngine.shared.startBgm(track: "bgm_balloon", rate: 1.0)

        case .freeze:
            freezeRoundsTotal = 5
            freezeRound = 0
            isFreezePhase = false
            freezeTimer = 7.4
            freezeDuration = 3.4
            freezeElapsed = 0
            freezeWiggleTime = 0
            freezeSuccessCount = 0
            wiggleSfxCooldown = 0
            isWiggling = false
            danceEnergy = 0.55
            setupDino()
            onProgress?(0, freezeRoundsTotal)
            onCallout?("네온 클럽 오픈! 신나게 흔들어 춤춰요!!", 2.5)
            SoundEngine.shared.startBgm(track: "bgm_freeze", rate: 1.0)

        case .animal:
            animalIndex = 0
            animalCleared = Array(repeating: false, count: animalPoses.count)
            animalTimer = animalTimeLimit
            animalHold = 0
            animalPause = 0
            animalSuccessCount = 0
            setupAnimalPoseUI()
            onProgress?(0, animalPoses.count)
            onCallout?("🦒 \(animalPoses[0].name)! \(animalPoses[0].cue)", 2.8)
            SoundEngine.shared.startBgm(track: "bgm_balloon", rate: 1.0)

        case .jungle:
            jungleElapsed = 0
            junglePhase = .run
            junglePhaseTimer = 6.2
            junglePhaseProgress = 0
            jungleRunCooldown = 0
            setupJungleGame()
            onProgress?(0, 5)
            onCallout?("🌿 달려라 정글 모험! 제자리 달리기 시작!!", 2.8)
            SoundEngine.shared.startBgm(track: "bgm_adventure", rate: 1.0)

        case .mole:
            moleElapsed = 0
            moleSpawnTimer = 0.45
            moleFeverTriggered = false
            setupMoleGame()
            onProgress?(0, 10)
            onCallout?("🐹 위엔 손 하이파이브! 아래엔 발 톡톡!", 2.8)
            SoundEngine.shared.startBgm(track: "bgm_adventure", rate: 1.0)

        case .balance:
            balanceElapsed = 0
            bridgeAngle = 0
            bridgeAngVel = 0
            windForce = 0
            windTimer = 0
            windNextTimer = 2.6
            balancePointTick = 0
            balanceWobbleCooldown = 0
            oneLegActive = false
            oneLegTimer = 0
            oneLegHold = 0
            oneLegNextTimer = 11.0
            balanceStarSpawnTimer = 2.2
            setupBalanceGame()
            onProgress?(0, 10)
            onCallout?("🪵 팔을 활짝 벌려 외나무다리 균형을 잡아요!", 2.8)
            SoundEngine.shared.startBgm(track: "bgm_adventure", rate: 1.0)
        }
    }

    func stopGame() {
        isFinished = true
        isGamePaused = true
        feverActive = false
        finishWorkItem?.cancel()
        finishWorkItem = nil
        SoundEngine.shared.stopBgm()
    }

    override func update(_ currentTime: TimeInterval) {
        guard !isGamePaused else { lastUpdate = currentTime; return }
        if lastUpdate == 0 { lastUpdate = currentTime; return }
        var dt = CGFloat(min(0.05, currentTime - lastUpdate))
        lastUpdate = currentTime

        cameraManager?.tickDevMode()

        if hitstopTimer > 0 {
            hitstopTimer -= dt
            dt *= 0.22
        }

        elapsed += TimeInterval(dt)
        if comboTimer > 0 {
            comboTimer -= dt
            if comboTimer <= 0 { combo = 0 }
        }

        if screenShake > 0.01 {
            screenShake = max(0, screenShake - dt * 3.6)
            worldNode.position = CGPoint(
                x: CGFloat.random(in: -14...14) * screenShake,
                y: CGFloat.random(in: -10...10) * screenShake
            )
        } else {
            worldNode.position = .zero
        }

        if feverActive {
            feverBorder.path = CGPath(rect: CGRect(x: 8, y: 8, width: max(10, size.width - 16), height: max(10, size.height - 16)), transform: nil)
            let cols: [UIColor] = [.systemPink, .systemYellow, .systemTeal, .systemPurple]
            feverBorder.strokeColor = cols[Int(elapsed * 3) % cols.count]
            feverBorder.alpha = 0.4 + 0.3 * sin(CGFloat(elapsed) * 7)
        } else {
            feverBorder.alpha = 0
        }

        let players = cameraManager?.players ?? []
        let minVel = settings.speed.minSlashVelocity
        // Render glowing hand halos & swipe trails ONLY in hand-action games (.fruit, .balloon, .mole)
        let showHandEffects = (gameType == .fruit || gameType == .balloon || gameType == .mole)

        var hands: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, Bool, CGFloat, CGFloat)] = []
        var activeSlots: Set<Int> = []
        for p in players.prefix(2) {
            let pid = max(0, min(1, p.id))
            let pts: [(CGPoint, CGFloat)] = [
                (p.leftHand, p.metrics.lWristConf),
                (p.rightHand, p.metrics.rWristConf)
            ]
            for (hIdx, pair) in pts.enumerated() {
                let norm = pair.0
                let conf = pair.1
                let slot = pid * 2 + hIdx
                guard conf >= 0.20, norm.x >= -0.05, norm.x <= 1.05, norm.y >= -0.05, norm.y <= 1.05 else {
                    continue
                }
                activeSlots.insert(slot)
                let x = norm.x * size.width
                let y = (1.0 - norm.y) * size.height
                let prev = prevHands[slot] ?? CGPoint(x: x, y: y)
                let dx = x - prev.x
                let dy = y - prev.y
                let vx = dt > 0.0001 ? dx / dt : 0
                let vy = dt > 0.0001 ? dy / dt : 0
                let spd = hypot(vx, vy)
                let slashing = spd >= minVel
                let ang = atan2(dy, dx)

                var e = handEnergy[slot]
                if showHandEffects {
                    if slashing { e = min(1, e + dt * 7.0) }
                    else { e = max(0, e - dt * 2.8) }
                } else {
                    e = 0
                }
                handEnergy[slot] = e
                prevHands[slot] = CGPoint(x: x, y: y)

                swooshCooldown[slot] = max(0, swooshCooldown[slot] - dt)
                if gameType == .fruit && !isFinished && spd >= minVel * 2.8 && swooshCooldown[slot] <= 0 {
                    SoundEngine.shared.playSwoosh()
                    swooshCooldown[slot] = 0.72
                }

                if showHandEffects {
                    if e > 0.06 {
                        handTrails[slot].append(CGPoint(x: x, y: y))
                        if handTrails[slot].count > maxTrailPoints { handTrails[slot].removeFirst() }
                    } else if !handTrails[slot].isEmpty {
                        handTrails[slot].removeFirst()
                    }

                    let confFade = smoothstep(edge0: 0.18, edge1: 0.45, x: conf)
                    if slot < haloRigs.count {
                        let haloRig = haloRigs[slot]
                        if confFade >= 0.02 {
                            let rScale = 0.62 + 0.52 * e
                            haloRig.container.isHidden = false
                            haloRig.container.position = CGPoint(x: x, y: y)
                            haloRig.outerGlow.setScale(rScale)
                            haloRig.outerGlow.alpha = (0.06 + 0.22 * e) * confFade
                            haloRig.midRing.setScale(rScale)
                            haloRig.midRing.lineWidth = (2.5 + 2.0 * e) / max(0.2, rScale)
                            haloRig.midRing.alpha = (0.22 + 0.72 * e) * confFade
                            haloRig.innerCore.setScale((5.0 + 4.0 * e) / 5.0)
                            haloRig.innerCore.alpha = (0.35 + 0.60 * e) * confFade
                        } else {
                            haloRig.container.isHidden = true
                        }
                    }

                    if slot < trailRigs.count {
                        let tr = handTrails[slot]
                        if tr.count >= 2 && e > 0.08 && confFade >= 0.02 {
                            let rig = trailRigs[slot]
                            let segCount = tr.count - 1
                            for band in rig.bands {
                                for segIdx in 0..<band.segments.count {
                                    let seg = band.segments[segIdx]
                                    if segIdx < segCount {
                                        let i = segIdx + 1
                                        let ratio = CGFloat(i) / CGFloat(tr.count)
                                        let p = CGMutablePath()
                                        p.move(to: CGPoint(x: tr[i - 1].x, y: tr[i - 1].y + band.offsetY))
                                        p.addLine(to: CGPoint(x: tr[i].x, y: tr[i].y + band.offsetY))
                                        seg.path = p
                                        seg.lineWidth = max(2.0, band.baseWidth * ratio * (0.5 + 0.6 * e))
                                        seg.alpha = ratio * 0.78 * e * confFade
                                        seg.isHidden = false
                                    } else if !seg.isHidden {
                                        seg.isHidden = true
                                        seg.path = nil
                                    }
                                }
                            }
                        } else {
                            hideTrailRig(slot: slot)
                        }
                    }
                } else {
                    if !handTrails[slot].isEmpty { handTrails[slot].removeAll() }
                    hideHandVfx(slot: slot)
                }

                hands.append((prev.x, prev.y, x, y, vx, vy, slashing, ang, spd))
            }
        }
        for s in 0..<4 where !activeSlots.contains(s) {
            prevHands[s] = nil
            handEnergy[s] = 0
            if !handTrails[s].isEmpty { handTrails[s].removeAll() }
            hideHandVfx(slot: s)
        }

        // Update parabolic burst particles, swaying soap bubbles, and sliced fruit halves every frame
        updateVfxPhysics(dt: dt)

        if isFinished {
            // 피날레 아웃트로: 종료 후에도 풍선은 둥실 떠오르고, 3번 클럽 댄서들은 끝까지 승리 댄스!
            if gameType == .balloon {
                for i in balls.indices {
                    balls[i].node.position.y += size.height * 0.14 * dt
                    balls[i].node.position.x += sin(CGFloat(elapsed) * 3.0 + balls[i].driftSeed) * 28 * dt
                    balls[i].node.zRotation += 0.85 * dt
                }
            } else if gameType == .freeze {
                animateClubOutro(dt: dt)
            }
            return
        }

        switch gameType {
        case .fruit:
            updateFruitZen(dt: dt, hands: hands.map { ($0.0, $0.1, $0.2, $0.3, $0.4, $0.5, $0.6, $0.7) })
        case .balloon:
            updateBalloon(dt: dt, hands: hands.map { ($0.2, $0.3, $0.4, $0.5, $0.8) })
        case .freeze:
            updateFreeze(dt: dt, players: players)
        case .animal:
            updateAnimalPose(dt: dt, players: players)
        case .jungle:
            updateJungleGame(dt: dt, players: players)
        case .mole:
            updateMoleGame(dt: dt, players: players)
        case .balance:
            updateBalanceGame(dt: dt, players: players)
        }
    }

    private func distPointToSegment(cx: CGFloat, cy: CGFloat, x0: CGFloat, y0: CGFloat, x1: CGFloat, y1: CGFloat) -> CGFloat {
        let vx = x1 - x0
        let vy = y1 - y0
        let lenSq = vx * vx + vy * vy
        if lenSq < 1e-4 { return hypot(cx - x0, cy - y0) }
        let s = max(0, min(1, ((cx - x0) * vx + (cy - y0) * vy) / lenSq))
        return hypot(cx - (x0 + s * vx), cy - (y0 + s * vy))
    }

    // MARK: - Game 1: 90s Zen Fruit + Multi-Direction Physics + Multi-Hit + 3 Bosses
    private func updateFruitZen(dt: CGFloat, hands: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, Bool, CGFloat)]) {
        let spd = settings.speed.speedMult
        let hMult = settings.speed.hitboxMult

        zenElapsed += dt
        onProgress?(min(9, Int((zenElapsed / zenDuration) * 9.0)), 9)

        if feverBurstTimer > 0 {
            feverBurstTimer -= dt
            feverActive = true
            if feverBurstTimer <= 0 && bossNode == nil {
                feverActive = false
                SoundEngine.shared.setBgmRate(1.0)
            }
        }

        // 90s finish check (grace period if mid-boss)
        if zenElapsed >= zenDuration && (bossNode == nil || zenElapsed >= zenDuration + 12) {
            bossNode?.removeFromParent()
            bossVfxNode?.removeFromParent()
            bossBarBg?.removeFromParent()
            bossBarFill?.removeFromParent()
            bossNode = nil
            bossVfxNode = nil
            bossAuraNode = nil
            bossOrbitStars.removeAll()
            activeBossConfig = nil
            feverActive = false
            spawnConfetti()
            finishGame("90초 동안 사방에서 쏟아진 과일 ⭐ \(score)점 대성공!")
            return
        }

        // 3-Boss Relay Trigger (24s Pineapple -> 52s Melon -> 76s Watermelon King)
        if bossNode == nil && bossIndex < bossSchedule.count {
            let nextBoss = bossSchedule[bossIndex]
            if zenElapsed >= nextBoss.triggerTime {
                spawnBoss(config: nextBoss)
                bossIndex += 1
            }
        }

        // Frequent multi-direction spawning
        spawnTimer -= dt
        let isFever = feverActive || zenElapsed > 65
        let maxOnScreen = bossNode != nil ? 3 : (isFever ? 9 : 6)
        if spawnTimer <= 0 && activeFruits.count < maxOnScreen {
            if bossNode != nil {
                spawnDirectionalFruit(spd: spd, allowSpecial: false, forcedZone: Bool.random() ? "left" : "right")
                spawnTimer = 1.65 / spd
            } else {
                let batch = isFever ? (CGFloat.random(in: 0...1) < 0.6 ? 3 : 2) : (CGFloat.random(in: 0...1) < 0.45 ? 2 : 1)
                for _ in 0..<batch {
                    spawnDirectionalFruit(spd: spd * (isFever ? 1.08 : 1.0), allowSpecial: true)
                }
                spawnTimer = (isFever ? 0.52 : 0.72) / spd
            }
        }

        // Physics update (gravity + air drag + wall bounce + top-drop floor bounce + multi-hit)
        let gravity = size.height * 0.46 * spd
        let t = CGFloat(elapsed)
        let rainbowAuraCols: [UIColor] = [
            UIColor(red: 1.0, green: 0.42, blue: 0.51, alpha: 1.0), // #FF6B81
            UIColor(red: 1.0, green: 0.83, blue: 0.23, alpha: 1.0), // #FFD43B
            UIColor(red: 0.36, green: 0.94, blue: 0.89, alpha: 1.0), // #5CEFE2
            UIColor(red: 0.75, green: 0.52, blue: 0.99, alpha: 1.0), // #C084FC
        ]
        var rainbowTriggered = false
        var survivors: [ActiveFruit] = []

        for var f in activeFruits {
            f.hitCooldown = max(0, f.hitCooldown - dt)
            f.node.position.x += f.vx * dt
            f.node.position.y += f.vy * dt
            f.vy -= gravity * dt
            f.vx *= (1.0 - 0.08 * dt)
            f.node.zRotation += f.vrot * dt

            // Pulsing aura + continuous orbiting stars for Golden & Rainbow fruits (matching PixiJS L588-L615)
            if f.special == "golden" {
                let popScale = 1.0 + 0.08 * sin(t * 10.0)
                f.node.setScale(popScale)
                f.auraNode.alpha = 0.28 + 0.10 * sin(t * 9.0)
                f.orbitNode?.zRotation = t * 3.0 - f.node.zRotation
            } else if f.special == "rainbow" {
                let popScale = 1.0 + 0.08 * sin(t * 10.0)
                f.node.setScale(popScale)
                f.auraNode.fillColor = rainbowAuraCols[Int(t * 8.0) % rainbowAuraCols.count].withAlphaComponent(0.34)
                f.orbitNode?.zRotation = -t * 4.0 - f.node.zRotation
            }

            // Elastic side wall bounce (keeps fruits inside play zone!)
            if f.node.position.x < f.radius * 0.8 && f.vx < 0 {
                f.node.position.x = f.radius * 0.8
                f.vx = abs(f.vx) * 0.8
                f.vrot *= -0.9
            } else if f.node.position.x > size.width - f.radius * 0.8 && f.vx > 0 {
                f.node.position.x = size.width - f.radius * 0.8
                f.vx = -abs(f.vx) * 0.8
                f.vrot *= -0.9
            }

            // One-time bottom trampoline bounce for top-dropped fruits
            if f.bouncesLeft > 0 && f.node.position.y < f.radius * 0.9 && f.vy < 0 {
                f.node.position.y = f.radius * 0.9
                f.vy = size.height * 0.52 * spd
                f.bouncesLeft -= 1
                f.node.run(.sequence([.scaleX(to: 1.2, y: 0.82, duration: 0.07), .scale(to: 1.0, duration: 0.1)]))
            }

            var destroyed = false
            if f.hitCooldown <= 0 {
                for (px, py, hx, hy, vx, vy, isSlashing, ang) in hands {
                    guard isSlashing else { continue }
                    let d = distPointToSegment(cx: f.node.position.x, cy: f.node.position.y, x0: px, y0: py, x1: hx, y1: hy)
                    if d < f.radius * 1.42 * hMult {
                        f.hp -= 1
                        let pos = f.node.position

                        if f.hp > 0 {
                            // Multi-hit tough fruit knockback & squash!
                            f.hitCooldown = 0.18
                            f.vy = max(size.height * 0.34, abs(f.vy) * 0.65)
                            f.vx += max(-240, min(240, vx * 0.25))
                            f.vrot += (vx >= 0 ? 1 : -1) * 4.5
                            f.node.run(.sequence([.scaleX(to: 1.24, y: 0.78, duration: 0.07), .scale(to: 1.0, duration: 0.12)]))
                            updateHpDots(node: f.hpDotsNode, hp: f.hp, maxHp: f.maxHp)
                            SoundEngine.shared.playToughHit(f.maxHp - f.hp)
                            spawnBurst(at: pos, color: .systemYellow, text: f.hp == 1 ? "한 번 더!!" : "통!", power: 1, angle: ang)
                            break
                        }

                        // HP == 0 -> Slice in half!
                        destroyed = true
                        f.node.removeFromParent()
                        registerCombo(at: pos)
                        spawnSplatter(at: pos, color: f.color, scale: (f.maxHp > 1 || f.special != "normal") ? 1.45 : 1.0)
                        spawnSlicedHalves(kind: f.kind, at: pos, radius: f.radius, angle: ang, slashVx: vx, slashVy: vy)

                        if f.special == "rainbow" {
                            score += 3
                            SoundEngine.shared.playRainbowBlast()
                            spawnBurst(at: pos, color: .systemPurple, text: "무지개 대폭발!!", power: 3, angle: ang)
                            hitstopTimer = 0.14
                            rainbowTriggered = true
                        } else if f.special == "golden" {
                            score += 3
                            SoundEngine.shared.playGoldenPop()
                            spawnBurst(at: pos, color: .systemYellow, text: "황금 팡!! +3", power: 2, angle: ang)
                        } else if f.maxHp > 1 {
                            score += f.maxHp
                            SoundEngine.shared.playGoldenPop()
                            spawnBurst(at: pos, color: f.color, text: "대박 팡!! +\(f.maxHp)", power: 2, angle: ang)
                        } else {
                            score += 1
                            SoundEngine.shared.playPop(combo: combo)
                            spawnBurst(at: pos, color: f.color, text: "팡! +1", power: 1, angle: ang)
                        }
                        onScore?(score)
                        break
                    }
                }
            }

            if !destroyed && f.node.position.y > -f.radius * 2.5 && f.node.position.x > -f.radius * 3 && f.node.position.x < size.width + f.radius * 3 {
                survivors.append(f)
            } else if !destroyed {
                f.node.removeFromParent()
            }
        }
        activeFruits = survivors

        // Elastic fruit-to-fruit collisions!
        resolveFruitCollisions()

        if rainbowTriggered && !activeFruits.isEmpty {
            for other in activeFruits {
                score += max(1, other.maxHp)
                let pos = other.node.position
                other.node.removeFromParent()
                spawnSplatter(at: pos, color: other.color, scale: 1.15)
                spawnSlicedHalves(kind: other.kind, at: pos, radius: other.radius, angle: -0.4, slashVx: 0, slashVy: 0)
                spawnBurst(at: pos, color: other.color, text: "연쇄 팡!", power: 1, angle: -0.4)
            }
            activeFruits.removeAll()
            onScore?(score)
        }

        // Active Boss update (Pineapple -> Melon -> Watermelon King)
        if let boss = bossNode, let cfg = activeBossConfig {
            let swayX = sin(t * 2.0) * (size.width * 0.04)
            let targetY = size.height * 0.52
            boss.position.x = size.width * 0.5 + swayX + (bossShake > 0 ? CGFloat.random(in: -14...14) * bossShake : 0)
            boss.position.y += (targetY - boss.position.y) * min(1, dt * 5.5)
            bossShake = max(0, bossShake - dt * 4.0)
            bossCooldown = max(0, bossCooldown - dt)

            let rage = CGFloat(bossHits) / CGFloat(max(1, bossMaxHits))
            let baseRadius = min(size.width, size.height) * 0.20
            let radius = min(size.width, size.height) * (0.20 + rage * 0.05)
            let br = radius * (1.0 + 0.09 * bossShake)
            boss.size = CGSize(width: br * 2.15, height: br * 2.15)
            boss.zRotation = sin(t * 2.5) * 0.06
            boss.color = UIColor(red: 1.0, green: 0.94, blue: 0.70, alpha: 1.0)
            boss.colorBlendFactor = bossShake > 0.35 ? 0.35 : 0.0
            updateBossBar(remaining: max(0, 1.0 - rage))

            // Pulsing boss aura + 8 orbiting golden 5-pointed stars (matching PixiJS L642-L649)
            if let vfx = bossVfxNode {
                vfx.position = boss.position
                let auraScale = (br / max(1.0, baseRadius)) * (1.0 + 0.06 * sin(t * 6.0))
                bossAuraNode?.setScale(auraScale)
                for (i, star) in bossOrbitStars.enumerated() {
                    let ang = t * 1.5 + (CGFloat(i) * .pi * 2.0) / 8.0
                    star.position = CGPoint(x: cos(ang) * br * 1.24, y: sin(ang) * br * 1.12)
                    star.zRotation = -ang
                }
            }

            if bossCooldown <= 0 {
                for (px, py, hx, hy, vx, vy, isSlashing, ang) in hands {
                    guard isSlashing else { continue }
                    let d = distPointToSegment(cx: boss.position.x, cy: boss.position.y, x0: px, y0: py, x1: hx, y1: hy)
                    if d < radius * 1.4 * hMult {
                        bossHits += 1
                        bossShake = 1.15
                        bossCooldown = 0.19
                        SoundEngine.shared.playBossHit(bossHits)
                        let words = ["퍽!", "쾅!", "짜릿!", "우지끈!", "파워 업!"]
                        spawnSplatter(at: CGPoint(x: hx, y: hy), color: cfg.color, scale: 0.95)
                        spawnBurst(at: CGPoint(x: hx, y: hy), color: cfg.color, text: words[bossHits % words.count], power: bossHits % 4 == 0 ? 2 : 1, angle: ang)

                        if bossHits >= bossMaxHits {
                            score += cfg.bonus
                            onScore?(score)
                            SoundEngine.shared.playBossSmash()
                            hitstopTimer = 0.2
                            let pos = boss.position
                            boss.removeFromParent()
                            bossVfxNode?.removeFromParent()
                            bossBarBg?.removeFromParent()
                            bossBarFill?.removeFromParent()
                            bossNode = nil
                            bossVfxNode = nil
                            bossAuraNode = nil
                            bossOrbitStars.removeAll()
                            activeBossConfig = nil
                            spawnSplatter(at: pos, color: cfg.color, scale: 2.3)
                            spawnSlicedHalves(kind: cfg.texKey, at: pos, radius: radius, angle: ang, slashVx: vx, slashVy: vy)
                            spawnBurst(at: pos, color: cfg.color, text: "\(cfg.name) 격파!! +\(cfg.bonus)", power: 3, angle: ang)

                            feverBurstTimer = 9.0
                            feverActive = true
                            SoundEngine.shared.playFeverStart()
                            SoundEngine.shared.setBgmRate(1.12)
                            if bossIndex >= bossSchedule.count {
                                spawnConfetti()
                                onCallout?("피날레 피버! 마지막까지 팡팡!!", 3.2)
                            } else {
                                onCallout?("보스 클리어! 과일 소나기 피버!!", 3.0)
                            }
                        }
                        break
                    }
                }
            }
        }
    }

    private func resolveFruitCollisions() {
        guard activeFruits.count >= 2 else { return }
        for i in 0..<activeFruits.count {
            for j in (i + 1)..<activeFruits.count {
                let pa = activeFruits[i].node.position
                let pb = activeFruits[j].node.position
                let dx = pb.x - pa.x
                let dy = pb.y - pa.y
                let dist = hypot(dx, dy)
                let minDist = (activeFruits[i].radius + activeFruits[j].radius) * 0.92
                if dist > 0.01 && dist < minDist {
                    let nx = dx / dist
                    let ny = dy / dist
                    let overlap = (minDist - dist) * 0.5
                    activeFruits[i].node.position.x -= nx * overlap
                    activeFruits[i].node.position.y -= ny * overlap
                    activeFruits[j].node.position.x += nx * overlap
                    activeFruits[j].node.position.y += ny * overlap

                    let rvx = activeFruits[j].vx - activeFruits[i].vx
                    let rvy = activeFruits[j].vy - activeFruits[i].vy
                    let velAlongNormal = rvx * nx + rvy * ny
                    if velAlongNormal < 0 {
                        let impulse = -(1.0 + 0.82) * velAlongNormal * 0.5
                        activeFruits[i].vx -= impulse * nx
                        activeFruits[i].vy -= impulse * ny
                        activeFruits[j].vx += impulse * nx
                        activeFruits[j].vy += impulse * ny
                    }
                }
            }
        }
    }

    private func spawnDirectionalFruit(spd: CGFloat, allowSpecial: Bool, forcedZone: String? = nil) {
        let regularPool: [(String, UIColor, Int)] = [
            ("fruit_strawberry", UIColor(red: 1.0, green: 0.30, blue: 0.43, alpha: 1), 1),
            ("fruit_apple",      UIColor(red: 0.94, green: 0.28, blue: 0.44, alpha: 1), 1),
            ("fruit_orange",     UIColor(red: 1.0, green: 0.62, blue: 0.11, alpha: 1), 1),
            ("fruit_banana",     UIColor(red: 1.0, green: 0.82, blue: 0.40, alpha: 1), 1),
            ("fruit_grape",      UIColor(red: 0.61, green: 0.36, blue: 0.90, alpha: 1), 1),
            ("fruit_peach",      UIColor(red: 1.0, green: 0.56, blue: 0.64, alpha: 1), 1),
        ]
        let toughPool: [(String, UIColor, Int)] = [
            ("fruit_pineapple", UIColor(red: 1.0, green: 0.72, blue: 0.01, alpha: 1), 3),
            ("fruit_melon",     UIColor(red: 0.32, green: 0.82, blue: 0.63, alpha: 1), 2),
            ("fruit_grape",     UIColor(red: 0.61, green: 0.36, blue: 0.90, alpha: 1), 2),
            ("fruit_peach",     UIColor(red: 1.0, green: 0.56, blue: 0.64, alpha: 1), 2),
        ]

        let isTough = CGFloat.random(in: 0...1) < 0.28
        let pick = (isTough ? toughPool : regularPool).randomElement()!

        var special = "normal"
        if allowSpecial && !isTough {
            let r = CGFloat.random(in: 0...1)
            if r < 0.08 { special = "rainbow" }
            else if r < 0.22 { special = "golden" }
        }

        let hp = special != "normal" ? 1 : pick.2
        let radius = min(size.width, size.height) * (isTough ? 0.098 : special != "normal" ? 0.094 : 0.082)
        let node = SKSpriteNode(texture: textures[pick.0])
        node.size = CGSize(width: radius * 2.2, height: radius * 2.2)

        var hpDotsNode: SKNode?
        let auraNode: SKShapeNode
        var orbitNode: SKNode?

        if special == "golden" {
            node.color = UIColor(red: 1.0, green: 0.91, blue: 0.46, alpha: 1.0) // #FFE875
            node.colorBlendFactor = 0.28

            let aura = SKShapeNode(circleOfRadius: radius * 1.45)
            aura.fillColor = UIColor(red: 1.0, green: 0.83, blue: 0.23, alpha: 0.32) // #FFD43B
            aura.strokeColor = .clear
            aura.blendMode = .add
            aura.zPosition = -2
            node.addChild(aura)
            auraNode = aura

            let ring = SKShapeNode(circleOfRadius: radius * 1.25)
            ring.fillColor = .clear
            ring.strokeColor = UIColor(red: 1.0, green: 0.95, blue: 0.63, alpha: 0.90) // #FFF3A1
            ring.lineWidth = 5
            ring.blendMode = .add
            ring.zPosition = -1
            node.addChild(ring)

            let orbit = SKNode()
            orbit.zPosition = 2
            let starPath = makeStarPath(outerR: 11, innerR: 5)
            let goldStarCol = UIColor(red: 1.0, green: 0.91, blue: 0.40, alpha: 0.95) // #FFE866
            for k in 0..<4 {
                let a = CGFloat(k) * (.pi * 0.5)
                let star = SKShapeNode(path: starPath)
                star.fillColor = goldStarCol
                star.strokeColor = .clear
                star.blendMode = .add
                star.position = CGPoint(x: cos(a) * radius * 1.15, y: sin(a) * radius * 1.15)
                orbit.addChild(star)
            }
            node.addChild(orbit)
            orbitNode = orbit
        } else if special == "rainbow" {
            let rCols: [UIColor] = [
                UIColor(red: 1.0, green: 0.42, blue: 0.51, alpha: 1.0), // #FF6B81
                UIColor(red: 1.0, green: 0.83, blue: 0.23, alpha: 1.0), // #FFD43B
                UIColor(red: 0.36, green: 0.94, blue: 0.89, alpha: 1.0), // #5CEFE2
                UIColor(red: 0.75, green: 0.52, blue: 0.99, alpha: 1.0), // #C084FC
            ]
            let aura = SKShapeNode(circleOfRadius: radius * 1.55)
            aura.fillColor = rCols[0].withAlphaComponent(0.34)
            aura.strokeColor = .clear
            aura.blendMode = .add
            aura.zPosition = -2
            node.addChild(aura)
            auraNode = aura

            let ring = SKShapeNode(circleOfRadius: radius * 1.35)
            ring.fillColor = .clear
            ring.strokeColor = UIColor.white.withAlphaComponent(0.92)
            ring.lineWidth = 6
            ring.blendMode = .add
            ring.zPosition = -1
            node.addChild(ring)

            let orbit = SKNode()
            orbit.zPosition = 2
            let starPath = makeStarPath(outerR: 12, innerR: 5)
            for k in 0..<5 {
                let a = (CGFloat(k) * .pi * 2.0) / 5.0
                let star = SKShapeNode(path: starPath)
                star.fillColor = rCols[k % 4].withAlphaComponent(0.95)
                star.strokeColor = .clear
                star.blendMode = .add
                star.position = CGPoint(x: cos(a) * radius * 1.22, y: sin(a) * radius * 1.22)
                orbit.addChild(star)
            }
            node.addChild(orbit)
            orbitNode = orbit
        } else {
            let aura = SKShapeNode(circleOfRadius: radius * 1.15)
            aura.fillColor = pick.1.withAlphaComponent(hp > 1 ? 0.24 : 0.14)
            aura.strokeColor = .clear
            aura.blendMode = .add
            aura.zPosition = -2
            node.addChild(aura)
            auraNode = aura

            if hp > 1 {
                let ring = SKShapeNode(circleOfRadius: radius * 1.08)
                ring.fillColor = .clear
                ring.strokeColor = .white.withAlphaComponent(0.85)
                ring.lineWidth = 3.5
                node.addChild(ring)

                let dots = SKNode()
                dots.position = CGPoint(x: 0, y: radius + 12)
                node.addChild(dots)
                hpDotsNode = dots
                updateHpDots(node: dots, hp: hp, maxHp: hp)
            }
        }

        let zones = ["bottom", "bottom", "left", "right", "top"]
        let zone = forcedZone ?? zones.randomElement()!
        var x: CGFloat, y: CGFloat, vx: CGFloat, vy: CGFloat
        var bouncesLeft = 0

        switch zone {
        case "left":
            x = -radius
            y = size.height * CGFloat.random(in: 0.28...0.72)
            vx = size.width * CGFloat.random(in: 0.28...0.44) * spd
            vy = size.height * CGFloat.random(in: 0.24...0.40) * spd
        case "right":
            x = size.width + radius
            y = size.height * CGFloat.random(in: 0.28...0.72)
            vx = -size.width * CGFloat.random(in: 0.28...0.44) * spd
            vy = size.height * CGFloat.random(in: 0.24...0.40) * spd
        case "top":
            x = size.width * CGFloat.random(in: 0.16...0.84)
            y = size.height + radius
            vx = CGFloat.random(in: -0.11...0.11) * size.width * spd
            vy = -size.height * CGFloat.random(in: 0.08...0.16) * spd
            bouncesLeft = 1
        default: // bottom arc
            x = size.width * CGFloat.random(in: 0.14...0.86)
            y = -radius
            let toCenter = (size.width * 0.5 - x) * CGFloat.random(in: 0.35...0.70)
            vx = (toCenter + CGFloat.random(in: -45...45)) * spd
            vy = size.height * CGFloat.random(in: 0.56...0.72) * spd
        }

        node.position = CGPoint(x: x, y: y)
        gameLayer.addChild(node)
        activeFruits.append(ActiveFruit(
            node: node,
            auraNode: auraNode,
            orbitNode: orbitNode,
            hpDotsNode: hpDotsNode,
            kind: pick.0,
            special: special,
            color: special == "golden" ? UIColor(red: 1.0, green: 0.72, blue: 0.01, alpha: 1) : special == "rainbow" ? UIColor(red: 0.66, green: 0.33, blue: 0.97, alpha: 1) : pick.1,
            hp: hp,
            maxHp: hp,
            hitCooldown: 0,
            bouncesLeft: bouncesLeft,
            vx: vx,
            vy: vy,
            vrot: CGFloat.random(in: -2.2...2.2),
            radius: radius
        ))
    }

    private func updateHpDots(node: SKNode?, hp: Int, maxHp: Int) {
        guard let node else { return }
        node.removeAllChildren()
        let gap: CGFloat = 13
        let startX = -CGFloat(maxHp - 1) * gap * 0.5
        for i in 0..<maxHp {
            let dot = SKShapeNode(circleOfRadius: 4.5)
            dot.fillColor = i < hp ? .systemYellow : UIColor.black.withAlphaComponent(0.4)
            dot.strokeColor = .white
            dot.lineWidth = 1.5
            dot.position = CGPoint(x: startX + CGFloat(i) * gap, y: 0)
            node.addChild(dot)
        }
    }

    private func spawnBoss(config: BossConfig) {
        activeBossConfig = config
        bossHits = 0
        bossMaxHits = settings.players == 2 ? config.hits2p : config.hits1p
        bossCooldown = 0.2
        SoundEngine.shared.playBossAppear()
        SoundEngine.shared.setBgmRate(1.14)

        let radius = min(size.width, size.height) * 0.20
        bossVfxNode?.removeFromParent()
        bossOrbitStars.removeAll()

        let vfx = SKNode()
        vfx.position = CGPoint(x: size.width * 0.5, y: size.height + 150)
        vfx.zPosition = 0
        let aura = SKShapeNode(circleOfRadius: radius * 1.22)
        aura.fillColor = config.color.withAlphaComponent(0.25)
        aura.strokeColor = .clear
        aura.blendMode = .add
        aura.zPosition = -2
        vfx.addChild(aura)
        bossAuraNode = aura

        let starPath = makeStarPath(outerR: 13, innerR: 5.5)
        let starCol = UIColor(red: 1.0, green: 0.863, blue: 0.302, alpha: 0.95) // #FFDC4D
        for i in 0..<8 {
            let ang = (CGFloat(i) * .pi * 2.0) / 8.0
            let star = SKShapeNode(path: starPath)
            star.fillColor = starCol
            star.strokeColor = .clear
            star.blendMode = .add
            star.zPosition = 5
            star.position = CGPoint(x: cos(ang) * radius * 1.24, y: sin(ang) * radius * 1.12)
            vfx.addChild(star)
            bossOrbitStars.append(star)
        }
        gameLayer.addChild(vfx)
        bossVfxNode = vfx

        let boss = SKSpriteNode(texture: textures[config.texKey])
        boss.size = CGSize(width: radius * 2.15, height: radius * 2.15)
        boss.position = CGPoint(x: size.width * 0.5, y: size.height + 150)
        boss.zPosition = 1
        gameLayer.addChild(boss)
        bossNode = boss

        let barW = min(340, size.width * 0.36)
        let barH: CGFloat = 24
        let bg = SKShapeNode(rectOf: CGSize(width: barW, height: barH), cornerRadius: 12)
        bg.fillColor = UIColor.black.withAlphaComponent(0.32)
        bg.strokeColor = .white
        bg.lineWidth = 4
        bg.position = CGPoint(x: size.width * 0.5, y: size.height * 0.16)
        gameLayer.addChild(bg)
        bossBarBg = bg

        let fill = SKShapeNode()
        fill.fillColor = config.color
        fill.strokeColor = .clear
        fill.position = bg.position
        gameLayer.addChild(fill)
        bossBarFill = fill
        updateBossBar(remaining: 1.0)

        let msg = settings.players == 2
            ? "\(config.name) 등장! 둘이 함께 흔들어 깨기!"
            : "\(config.name) 등장! 힘껏 흔들어 깨기!"
        onCallout?(msg, 3.4)
    }

    private func updateBossBar(remaining: CGFloat) {
        guard let bg = bossBarBg, let fill = bossBarFill else { return }
        let barW = min(340, size.width * 0.36) - 8
        let fillW = max(0, barW * remaining)
        fill.path = fillW > 4
            ? CGPath(roundedRect: CGRect(x: -barW / 2, y: -8, width: fillW, height: 16), cornerWidth: 8, cornerHeight: 8, transform: nil)
            : nil
        fill.fillColor = remaining > 0.4 ? UIColor(red: 0.38, green: 0.95, blue: 0.78, alpha: 1) : .systemYellow
        fill.position = bg.position
    }

    // MARK: - Game 2: Realistic Aerodynamic Balloon Volley (200-Point Family Rally + Bubble VFX!)
    private func spawnBalloon(kind: String, atX normX: CGFloat, golden: Bool, points: Int) {
        let isBeach = (kind == "balloon_beach")
        let r = min(size.width, size.height) * (isBeach ? 0.10 : 0.108)
        let tex = textures[kind]
        let node = SKSpriteNode(texture: tex)
        if let tex {
            let aspect = tex.size().width / max(1, tex.size().height)
            let hDim = r * (isBeach ? 2.12 : 2.38)
            node.size = CGSize(width: hDim * aspect, height: hDim)
        } else {
            node.size = CGSize(width: r * 2.1, height: r * 2.3)
        }
        node.position = CGPoint(x: size.width * normX, y: size.height * 0.76)

        let shadow = SKShapeNode(ellipseOf: CGSize(width: r * 1.4, height: r * 0.35))
        shadow.fillColor = UIColor.black.withAlphaComponent(0.16)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: node.position.x, y: size.height * 0.06)
        splatLayer.addChild(shadow)

        var strNode: SKShapeNode?
        if !isBeach {
            let s = SKShapeNode()
            s.strokeColor = golden ? UIColor(red: 1.0, green: 0.90, blue: 0.52, alpha: 0.9) : UIColor.white.withAlphaComponent(0.88)
            s.lineWidth = 3
            s.lineCap = .round
            gameLayer.addChild(s)
            strNode = s
        }

        let auraCol: UIColor = golden
            ? UIColor(red: 1.0, green: 0.83, blue: 0.23, alpha: 0.28) // #FFD43B
            : (isBeach
                ? UIColor(red: 0.38, green: 0.84, blue: 1.0, alpha: 0.14) // #60D5FF
                : UIColor(red: 1.0, green: 0.42, blue: 0.51, alpha: 0.14)) // #FF6B81
        let glow = SKShapeNode(circleOfRadius: r * (golden ? 1.32 : 1.15))
        glow.fillColor = auraCol
        glow.strokeColor = .clear
        glow.blendMode = .add
        glow.zPosition = -1
        node.addChild(glow)

        var orbitNode: SKNode?
        if golden {
            let orbit = SKNode()
            orbit.zPosition = 2
            let starPath = makeStarPath(outerR: 10, innerR: 4.5)
            let goldStarCol = UIColor(red: 1.0, green: 0.91, blue: 0.40, alpha: 0.92) // #FFE866
            for k in 0..<4 {
                let a = CGFloat(k) * (.pi * 0.5)
                let star = SKShapeNode(path: starPath)
                star.fillColor = goldStarCol
                star.strokeColor = .clear
                star.blendMode = .add
                star.position = CGPoint(x: cos(a) * r * 1.18, y: sin(a) * r * 1.18)
                orbit.addChild(star)
            }
            node.addChild(orbit)
            orbitNode = orbit
        }

        gameLayer.addChild(node)
        balls.append(ActiveBalloon(
            node: node,
            shadowNode: shadow,
            stringNode: strNode,
            orbitNode: orbitNode,
            kind: kind,
            vx: (golden ? -115 : 115) * settings.speed.speedMult,
            vy: -20,
            vrot: isBeach ? 2.0 : 0,
            radius: r,
            golden: golden,
            points: points,
            cooldown: 0.25,
            driftSeed: CGFloat.random(in: 0...6.28)
        ))
    }

    private func spawnBalloonVfx(at pos: CGPoint, color: UIColor, text: String, power: Int) {
        // 1) 이중 공기 파동 링
        for (idx, mult) in [CGFloat(power >= 2 ? 6.2 : 4.6), CGFloat(power >= 2 ? 4.4 : 3.2)].enumerated() {
            let ring = SKShapeNode(circleOfRadius: 20)
            ring.strokeColor = idx == 0 ? color : .white
            ring.lineWidth = idx == 0 ? 6 : 3.5
            ring.blendMode = .add
            ring.position = pos
            fxLayer.addChild(ring)
            ring.run(.sequence([.group([.scale(to: mult, duration: 0.36), .fadeOut(withDuration: 0.36)]), .removeFromParent()]))
        }
        // 2) 위로 둥실 떠오르는 무지개 비눗방울 파티클 (상단 좌측 스페큘러 하이라이트 + 사인파 흔들림! matching PixiJS L1606-L1615)
        let bCols: [UIColor] = [
            UIColor(red: 0x67 / 255.0, green: 0xE8 / 255.0, blue: 0xF9 / 255.0, alpha: 1.0), // #67E8F9
            UIColor(red: 0xFD / 255.0, green: 0xA4 / 255.0, blue: 0xAF / 255.0, alpha: 1.0), // #FDA4AF
            UIColor(red: 0xFD / 255.0, green: 0xE0 / 255.0, blue: 0x47 / 255.0, alpha: 1.0), // #FDE047
            UIColor(red: 0xC4 / 255.0, green: 0xB5 / 255.0, blue: 0xFD / 255.0, alpha: 1.0), // #C4B5FD
            color,
        ]
        let count = power >= 2 ? 14 : 9
        for i in 0..<count {
            let r = CGFloat.random(in: 7...18)
            let ang = CGFloat.random(in: 0...(CGFloat.pi * 2))
            let sp = CGFloat.random(in: 55...200)
            let bubble = SKShapeNode(circleOfRadius: r)
            bubble.fillColor = bCols[i % bCols.count].withAlphaComponent(0.25)
            bubble.strokeColor = UIColor.white.withAlphaComponent(0.85)
            bubble.lineWidth = 2
            bubble.position = CGPoint(x: pos.x + cos(ang) * 18, y: pos.y + sin(ang) * 18)
            bubble.zPosition = 44

            // Crisp white top-left specular highlight dot (Y-up: -x, +y)
            let highlight = SKShapeNode(circleOfRadius: max(1.5, r * 0.24))
            highlight.fillColor = UIColor.white.withAlphaComponent(0.90)
            highlight.strokeColor = .clear
            highlight.position = CGPoint(x: -r * 0.32, y: r * 0.32)
            bubble.addChild(highlight)

            fxLayer.addChild(bubble)
            if activeBubbles.count >= 80, let oldest = activeBubbles.first {
                oldest.node.removeFromParent()
                activeBubbles.removeFirst()
            }
            activeBubbles.append(ActiveBubble(
                node: bubble,
                vx: cos(ang) * sp,
                vy: CGFloat.random(in: 90...220),
                seed: CGFloat.random(in: 0...6.28),
                life: CGFloat.random(in: 0.95...1.50)
            ))
        }
        spawnBurst(at: pos, color: color, text: text, power: power, angle: -0.3)
    }

    private func updateBalloon(dt: CGFloat, hands: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)]) {
        let spd = settings.speed.speedMult
        let hMult = settings.speed.hitboxMult
        let minVel = settings.speed.minSlashVelocity * 0.48

        for i in balls.indices {
            let isBeach = balls[i].kind == "balloon_beach"
            let r = balls[i].radius
            balls[i].cooldown = max(0, balls[i].cooldown - dt)

            // 1) 리얼 풍선 공기역학: 부드러운 중력 + 공기 저항(체공감!) + 공기 흐름 흔들림
            let gravity = size.height * (isBeach ? 0.34 : 0.22) * spd
            let drag: CGFloat = isBeach ? 0.85 : 1.45
            let airDrift: CGFloat = size.width * (isBeach ? 0.04 : 0.11)

            balls[i].vy -= gravity * dt
            balls[i].vx -= balls[i].vx * drag * dt
            balls[i].vy -= balls[i].vy * (drag * 0.72) * dt
            balls[i].vx += sin(CGFloat(elapsed) * 2.4 + balls[i].driftSeed) * airDrift * dt

            balls[i].node.position.x += balls[i].vx * dt
            balls[i].node.position.y += balls[i].vy * dt

            if isBeach {
                balls[i].node.zRotation += balls[i].vrot * dt
                balls[i].vrot *= (1.0 - 0.55 * dt)
            } else {
                let targetTilt = max(-0.32, min(0.32, -balls[i].vx * 0.0012 + sin(CGFloat(elapsed) * 3.0 + balls[i].driftSeed) * 0.07))
                balls[i].node.zRotation += (targetTilt - balls[i].node.zRotation) * min(1, dt * 6.5)
            }
            if let orbit = balls[i].orbitNode {
                orbit.zRotation = CGFloat(elapsed) * 2.6 - balls[i].node.zRotation
            }

            // 2) 벽 & 바닥 안전 탄성
            if balls[i].node.position.x < r + 16 {
                balls[i].node.position.x = r + 16
                balls[i].vx = abs(balls[i].vx) * 0.82
                balls[i].vrot *= -0.8
            }
            if balls[i].node.position.x > size.width - r - 16 {
                balls[i].node.position.x = size.width - r - 16
                balls[i].vx = -abs(balls[i].vx) * 0.82
                balls[i].vrot *= -0.8
            }
            if balls[i].node.position.y > size.height - r - 16 {
                balls[i].node.position.y = size.height - r - 16
                balls[i].vy = -abs(balls[i].vy) * 0.55
            }
            if balls[i].node.position.y < r + 26 {
                balls[i].node.position.y = r + 26
                balls[i].vy = size.height * (isBeach ? 0.42 : 0.34) * spd
                balls[i].node.run(.sequence([.scaleX(to: 1.2, y: 0.82, duration: 0.08), .scale(to: 1.0, duration: 0.12)]))
                SoundEngine.shared.playBounce()
            }

            // 바닥 동적 그림자 & 흔들리는 풍선 끈 업데이트
            let pos = balls[i].node.position
            let nearFloor = max(0.15, min(1.0, 1.0 - (pos.y / max(1, size.height))))
            balls[i].shadowNode.position = CGPoint(x: pos.x, y: size.height * 0.05)
            balls[i].shadowNode.setScale(0.55 + 0.65 * nearFloor)
            balls[i].shadowNode.alpha = 0.08 + 0.2 * nearFloor

            if let sNode = balls[i].stringNode {
                let knotY = pos.y - r * 1.05
                let sway = sin(CGFloat(elapsed) * 4.5 + balls[i].driftSeed) * 14 - balls[i].vx * 0.08
                let p = CGMutablePath()
                p.move(to: CGPoint(x: pos.x, y: knotY))
                p.addCurve(
                    to: CGPoint(x: pos.x + sway * 0.8, y: knotY - r * 1.25),
                    control1: CGPoint(x: pos.x + sway * 0.4, y: knotY - r * 0.45),
                    control2: CGPoint(x: pos.x - sway * 0.5, y: knotY - r * 0.85)
                )
                sNode.path = p
            }

            // 3) 손 타격 판정 + 오프센터 스핀!
            if balls[i].cooldown <= 0 {
                for (hx, hy, hvx, hvy, hspd) in hands where hspd >= minVel {
                    if hypot(hx - pos.x, hy - pos.y) < r * 1.45 * hMult {
                        let offsetX = (pos.x - hx) / max(36, r)
                        balls[i].vy = size.height * (isBeach ? 0.62 : 0.54) * spd + max(0, hvy * 0.2)
                        balls[i].vx = offsetX * 260 + hvx * 0.22
                        balls[i].vx = max(-420, min(420, balls[i].vx))
                        balls[i].vrot = -offsetX * 5.2 - hvx * 0.004
                        balls[i].cooldown = 0.24
                        balls[i].node.run(.sequence([.scaleX(to: 1.24, y: 0.78, duration: 0.08), .scale(to: 1.0, duration: 0.14)]))

                        let comboBonus = combo >= 5 ? 1 : 0
                        let gained = balls[i].points + comboBonus
                        score += gained
                        registerCombo(at: pos)
                        onScore?(score)
                        onProgress?(min(10, (score * 10) / 200), 10)

                        let fxCol: UIColor = balls[i].golden ? .systemYellow : (isBeach ? .systemTeal : .systemPink)
                        SoundEngine.shared.playBalloonHit(combo: combo, isGolden: balls[i].golden, isBeach: isBeach)
                        let hitText = balls[i].golden ? "황금 통! +\(gained)" : (isBeach ? "스핀 통! +\(gained)" : "통! +\(gained)")
                        spawnBalloonVfx(at: pos, color: fxCol, text: hitText, power: balls[i].golden ? 2 : 1)

                        if !beachBallSpawned && score >= 25 {
                            beachBallSpawned = true
                            SoundEngine.shared.playFeverStart()
                            spawnBalloon(kind: "balloon_beach", atX: 0.28, golden: false, points: 2)
                            onCallout?("웃는 비치볼 등장! (+2점!)", 3.2)
                        }
                        if !goldBallSpawned && score >= 60 {
                            goldBallSpawned = true
                            feverActive = true
                            SoundEngine.shared.playFeverStart()
                            SoundEngine.shared.setBgmRate(1.06)
                            spawnBalloon(kind: "balloon_gold", atX: 0.72, golden: true, points: 3)
                            onCallout?("황금 왕관 풍선 추가! 3개 풍선 대파티!", 3.4)
                        }
                        if nextBalloonMilestone < 200 && score >= nextBalloonMilestone {
                            let ms = nextBalloonMilestone
                            nextBalloonMilestone += 50
                            SoundEngine.shared.playMilestone()
                            spawnConfetti()
                            SoundEngine.shared.setBgmRate(ms >= 150 ? 1.15 : (ms >= 100 ? 1.10 : 1.05))
                            let msMsg = ms == 150 ? "150점 돌파! 200점까지 조금만 더!!" : "\(ms)점 돌파! 슈퍼 피버!!"
                            onCallout?(msMsg, 3.0)
                        }
                        if score >= 200 {
                            feverActive = false
                            spawnConfetti()
                            finishGame("풍선 3종으로 무려 ⭐ \(score)점 200점 대성공!")
                        }
                        break
                    }
                }
            }
        }

        // 4) 풍선끼리 탄성 충돌!
        guard balls.count >= 2 else { return }
        for i in 0..<balls.count {
            for j in (i + 1)..<balls.count {
                let pa = balls[i].node.position
                let pb = balls[j].node.position
                let dx = pb.x - pa.x
                let dy = pb.y - pa.y
                let dist = hypot(dx, dy)
                let minDist = (balls[i].radius + balls[j].radius) * 0.95
                if dist > 0.01 && dist < minDist {
                    let nx = dx / dist
                    let ny = dy / dist
                    let overlap = (minDist - dist) * 0.5
                    balls[i].node.position.x -= nx * overlap
                    balls[i].node.position.y -= ny * overlap
                    balls[j].node.position.x += nx * overlap
                    balls[j].node.position.y += ny * overlap
                    let vn = (balls[j].vx - balls[i].vx) * nx + (balls[j].vy - balls[i].vy) * ny
                    if vn < 0 {
                        let imp = -(1.0 + 0.88) * vn * 0.5
                        balls[i].vx -= imp * nx; balls[i].vy -= imp * ny
                        balls[j].vx += imp * nx; balls[j].vy += imp * ny
                        SoundEngine.shared.playBounce()
                    }
                }
            }
        }
    }

    // MARK: - Game 3: Neon Nightclub / Kids Disco Freeze Dance
    private func setupDino() {
        // 1) 어두운 네온 클럽 배경 필터 (카메라 인물 선명 + 네온 조명 폭발!)
        let overlay = SKSpriteNode(color: UIColor(red: 0.06, green: 0.02, blue: 0.14, alpha: 1), size: size)
        overlay.anchorPoint = .zero
        overlay.alpha = 0.30
        overlay.zPosition = -20
        splatLayer.addChild(overlay)
        clubOverlay = overlay

        // 2) 회전하는 네온 레이저 / 스포트라이트 빔 6개
        let beamColors: [UIColor] = [
            UIColor(red: 1.0, green: 0.18, blue: 0.58, alpha: 1),  // Hot Pink
            UIColor(red: 0.0, green: 0.96, blue: 1.0, alpha: 1),   // Electric Cyan
            UIColor(red: 1.0, green: 0.90, blue: 0.0, alpha: 1),   // Neon Yellow
            UIColor(red: 0.72, green: 0.30, blue: 1.0, alpha: 1),  // Neon Purple
            UIColor(red: 0.13, green: 1.0, blue: 0.53, alpha: 1),  // Neon Mint
            UIColor(red: 1.0, green: 0.42, blue: 0.21, alpha: 1),  // Club Orange
        ]
        let beamLen = hypot(size.width, size.height) * 1.15
        for c in beamColors {
            let p = CGMutablePath()
            p.move(to: .zero)
            p.addLine(to: CGPoint(x: -beamLen * 0.11, y: -beamLen))
            p.addLine(to: CGPoint(x: beamLen * 0.11, y: -beamLen))
            p.closeSubpath()
            let beam = SKShapeNode(path: p)
            beam.fillColor = c.withAlphaComponent(0.20)
            beam.strokeColor = .clear
            beam.blendMode = .add
            beam.zPosition = -10
            splatLayer.addChild(beam)
            clubBeams.append(beam)
        }

        // 얼음! 순간 차가운 아이스 스포트라이트 1개
        let iceP = CGMutablePath()
        iceP.move(to: CGPoint(x: size.width * 0.5, y: size.height + 10))
        iceP.addLine(to: CGPoint(x: size.width * 0.16, y: -20))
        iceP.addLine(to: CGPoint(x: size.width * 0.84, y: -20))
        iceP.closeSubpath()
        let iceSpot = SKShapeNode(path: iceP)
        iceSpot.fillColor = UIColor.systemCyan.withAlphaComponent(0.24)
        iceSpot.strokeColor = .clear
        iceSpot.blendMode = .add
        iceSpot.alpha = 0
        iceSpot.zPosition = -9
        splatLayer.addChild(iceSpot)
        iceSpotlight = iceSpot

        // 3) 상단 회전 미러볼 (Disco Mirror Ball) + 사방에 흩어지는 반짝이 빛방울
        let ballR = min(size.width, size.height) * 0.068
        let str = SKShapeNode()
        str.strokeColor = UIColor.white.withAlphaComponent(0.85)
        str.lineWidth = 3.5
        gameLayer.addChild(str)
        discoString = str

        let ballContainer = SKNode()
        let glow = SKShapeNode(circleOfRadius: ballR * 1.55)
        glow.fillColor = UIColor(red: 0.91, green: 0.47, blue: 0.98, alpha: 0.34)
        glow.strokeColor = .clear
        glow.blendMode = .add
        ballContainer.addChild(glow)

        let sphere = SKShapeNode(circleOfRadius: ballR)
        sphere.fillColor = UIColor(white: 0.92, alpha: 0.96)
        sphere.strokeColor = .white
        sphere.lineWidth = 2.5
        ballContainer.addChild(sphere)

        for row in -2...2 {
            for col in -2...2 {
                let fx = CGFloat(col) * ballR * 0.32
                let fy = CGFloat(row) * ballR * 0.32
                if hypot(fx, fy) < ballR * 0.78 {
                    let tile = SKShapeNode(rectOf: CGSize(width: 7, height: 6), cornerRadius: 1)
                    tile.fillColor = beamColors[abs(row * 5 + col) % beamColors.count].withAlphaComponent(0.75)
                    tile.strokeColor = .clear
                    tile.position = CGPoint(x: fx, y: fy)
                    ballContainer.addChild(tile)
                }
            }
        }
        gameLayer.addChild(ballContainer)
        discoBallNode = ballContainer

        for k in 0..<14 {
            let dot = SKShapeNode(circleOfRadius: 5 + CGFloat(k % 3) * 2.5)
            dot.fillColor = beamColors[k % beamColors.count].withAlphaComponent(0.68)
            dot.strokeColor = .clear
            dot.blendMode = .add
            dot.zPosition = -5
            splatLayer.addChild(dot)
            discoDots.append(dot)
        }

        // 4) 하단 네온 이퀄라이저 스펙트럼 바 20개
        let barCount = 20
        let eqColors: [UIColor] = [
            UIColor(red: 1.0, green: 0.18, blue: 0.58, alpha: 1),
            UIColor(red: 0.75, green: 0.52, blue: 0.99, alpha: 1),
            UIColor(red: 0.0, green: 0.96, blue: 1.0, alpha: 1),
            UIColor(red: 0.13, green: 1.0, blue: 0.53, alpha: 1),
            UIColor(red: 1.0, green: 0.90, blue: 0.0, alpha: 1),
        ]
        for i in 0..<barCount {
            let bar = SKShapeNode(rectOf: CGSize(width: 14, height: 100), cornerRadius: 4)
            bar.fillColor = eqColors[i % eqColors.count].withAlphaComponent(0.75)
            bar.strokeColor = .clear
            bar.blendMode = .add
            bar.zPosition = -4
            splatLayer.addChild(bar)
            eqBars.append(bar)
        }

        // 5) 비트에 번쩍이는 네온 클럽 프레임 + 얼음 남은 시간 프로그레스 바 + 움직임 감지 게이지
        let border = SKShapeNode()
        border.fillColor = .clear
        border.blendMode = .add
        border.zPosition = 30
        gameLayer.addChild(border)
        clubBorder = border

        let pBg = SKShapeNode(rectOf: CGSize(width: 340, height: 26), cornerRadius: 13)
        pBg.fillColor = UIColor.black.withAlphaComponent(0.62)
        pBg.strokeColor = UIColor(red: 0.73, green: 0.90, blue: 0.99, alpha: 1)
        pBg.lineWidth = 3.5
        pBg.isHidden = true
        pBg.zPosition = 32
        gameLayer.addChild(pBg)
        freezeProgBg = pBg

        let pFill = SKShapeNode()
        pFill.strokeColor = .clear
        pFill.isHidden = true
        pFill.zPosition = 33
        gameLayer.addChild(pFill)
        freezeProgFill = pFill

        let pLbl = SKLabelNode()
        pLbl.verticalAlignmentMode = .center
        pLbl.horizontalAlignmentMode = .center
        setStickerLabel(pLbl, text: "❄️ 얼음 버티기", fontSize: 25, strokeColor: UIColor(red: 0.01, green: 0.52, blue: 0.78, alpha: 1), strokeWidth: 6.5)
        pLbl.isHidden = true
        pLbl.zPosition = 34
        gameLayer.addChild(pLbl)
        freezeProgLabel = pLbl

        let mBg = SKShapeNode(rectOf: CGSize(width: 230, height: 12), cornerRadius: 6)
        mBg.fillColor = UIColor.black.withAlphaComponent(0.55)
        mBg.strokeColor = .systemCyan
        mBg.lineWidth = 2
        mBg.isHidden = true
        mBg.zPosition = 32
        gameLayer.addChild(mBg)
        freezeMeterBg = mBg

        let mFill = SKShapeNode()
        mFill.strokeColor = .clear
        mFill.isHidden = true
        mFill.zPosition = 33
        gameLayer.addChild(mFill)
        freezeMeterFill = mFill

        // 6) 라운드 합류형 클럽 댄서 3마리 (디노 · 모모 · 포포)
        let r = min(size.width, size.height) * 0.165
        let dancerSpecs: [(String, UIColor)] = [
            ("dino", UIColor(red: 1.0, green: 0.18, blue: 0.58, alpha: 1)),
            ("momo", UIColor(red: 0.0, green: 0.96, blue: 1.0, alpha: 1)),
            ("popo", UIColor(red: 1.0, green: 0.90, blue: 0.0, alpha: 1)),
        ]
        for (id, col) in dancerSpecs {
            let ring = SKShapeNode(circleOfRadius: r * 1.04)
            ring.strokeColor = col
            ring.fillColor = col.withAlphaComponent(0.24)
            ring.lineWidth = 6
            ring.blendMode = .add
            ring.isHidden = (id != "dino")
            gameLayer.addChild(ring)
            dancerRings[id] = ring

            let sp = SKSpriteNode(texture: textures["\(id)_dance1"] ?? textures["dino_sprite"])
            sp.size = CGSize(width: r * 2.25, height: r * 2.25)
            sp.isHidden = (id != "dino")
            gameLayer.addChild(sp)
            dancerNodes[id] = sp
        }
        dinoNode = dancerNodes["dino"]
        dinoRing = dancerRings["dino"]
    }

    private func updateFreeze(dt: CGFloat, players: [PlayerPose]) {
        let rawMotion = players.reduce(CGFloat(0)) { $0 + $1.motion }
        let avgMotion = rawMotion / CGFloat(max(1, players.count))
        emaMotion = 0.3 * avgMotion + 0.7 * emaMotion
        freezeTimer -= dt

        let t = CGFloat(elapsed)
        let rate = min(1.22, 1.0 + CGFloat(freezeRound) * 0.045)
        let beatHz = (128.0 / 60.0) * rate
        let beatPulse: CGFloat = isFreezePhase ? 0 : pow(max(0, cos(t * .pi * beatHz)), 4)

        if !isFreezePhase {
            isWiggling = false
            if emaMotion > 0.015 {
                danceEnergy = min(1.0, danceEnergy + dt * 1.15)
            } else {
                danceEnergy = max(0.30, danceEnergy - dt * 0.45)
            }
        } else {
            freezeElapsed += dt
            wiggleSfxCooldown = max(0, wiggleSfxCooldown - dt)
            let threshold: CGFloat = settings.speed == .slow ? 0.055 : (settings.speed == .fast ? 0.028 : 0.038)
            if freezeElapsed > 0.55 {
                if emaMotion > threshold {
                    isWiggling = true
                    freezeWiggleTime += dt
                    screenShake = max(screenShake, 0.32)
                    if wiggleSfxCooldown <= 0 {
                        wiggleSfxCooldown = 0.48
                        SoundEngine.shared.playFreezeWiggle()
                        spawnBurst(at: CGPoint(x: size.width * 0.5, y: size.height * 0.66), color: .systemRed, text: "움찔!! 멈춰요!!", power: 1, angle: 0)
                    }
                } else {
                    isWiggling = false
                }
            } else {
                isWiggling = false
            }
        }

        // 1) 어두운 클럽 오버레이 & 아이스 스포트라이트
        clubOverlay?.size = size
        clubOverlay?.color = isFreezePhase
            ? UIColor(red: 0.02, green: 0.11, blue: 0.21, alpha: 1)
            : UIColor(red: 0.06, green: 0.02, blue: 0.14, alpha: 1)
        clubOverlay?.alpha = isFreezePhase ? 0.36 : (0.30 - beatPulse * 0.06)
        iceSpotlight?.alpha = isFreezePhase ? 1.0 : 0.0

        // 2) 회전하는 6개 네온 레이저 빔
        let anchorX: [CGFloat] = [0.06, 0.22, 0.50, 0.50, 0.78, 0.94]
        let baseAng: [CGFloat] = [-0.52, -0.25, 0.0, 0.0, 0.25, 0.52]
        let amp: [CGFloat] = [0.46, 0.40, 0.52, -0.52, 0.40, 0.46]
        let spds: [CGFloat] = [1.7, 2.1, 1.5, 1.9, 2.2, 1.6]
        for (i, bm) in clubBeams.enumerated() {
            bm.position = CGPoint(x: size.width * anchorX[i], y: size.height + 10)
            bm.alpha = isFreezePhase ? 0.0 : (0.65 + beatPulse * 0.35)
            if !isFreezePhase {
                bm.zRotation = baseAng[i] + sin(t * spds[i] + CGFloat(i) * 1.1) * amp[i]
                bm.xScale = 1.0 + beatPulse * 0.35
            }
        }

        // 3) 회전 미러볼 & 반짝이 빛방울
        let ballR = min(size.width, size.height) * 0.068
        let ballPos = CGPoint(x: size.width * 0.5, y: size.height - min(80, size.height * 0.13))
        discoBallNode?.position = ballPos
        discoBallNode?.setScale(1.0 + beatPulse * 0.10)
        if !isFreezePhase {
            discoBallNode?.zRotation = t * 1.15
        }
        let spath = CGMutablePath()
        spath.move(to: CGPoint(x: ballPos.x, y: size.height))
        spath.addLine(to: CGPoint(x: ballPos.x, y: ballPos.y + ballR))
        discoString?.path = spath

        for (k, dot) in discoDots.enumerated() {
            let ang = (isFreezePhase ? 0 : t * (0.45 + CGFloat(k % 3) * 0.18)) + CGFloat(k) * 0.95
            let dist = (0.24 + CGFloat((k * 37) % 100) / 140.0) * min(size.width, size.height)
            dot.position = CGPoint(
                x: size.width * 0.5 + cos(ang) * dist * 1.4,
                y: size.height * 0.52 + sin(ang * 1.1) * dist * 0.85
            )
            dot.setScale(isFreezePhase ? 0.8 : (0.9 + beatPulse * 0.45))
            dot.alpha = isFreezePhase ? 0.3 : 0.78
        }

        // 4) 하단 네온 이퀄라이저 스펙트럼 바 20개
        let barCount = max(1, eqBars.count)
        let barGap: CGFloat = 5
        let barW = (size.width - 48 - barGap * CGFloat(barCount - 1)) / CGFloat(barCount)
        for (i, bar) in eqBars.enumerated() {
            let wave: CGFloat = isFreezePhase
                ? 0.08
                : (0.22 + 0.48 * abs(sin(t * 7.5 + CGFloat(i) * 0.55)) + 0.35 * beatPulse * abs(cos(CGFloat(i) * 0.4 + t * 3)))
            let bh = max(8, wave * size.height * 0.20 * (0.65 + danceEnergy * 0.65))
            bar.xScale = max(0.3, barW / 14.0)
            bar.yScale = bh / 100.0
            bar.position = CGPoint(x: 24 + CGFloat(i) * (barW + barGap) + barW * 0.5, y: bh * 0.5 + 8)
            bar.alpha = isFreezePhase ? 0.32 : 0.85
        }

        // 5) 비트에 번쩍이는 네온 프레임 (얼음 중 움직이면 빨간 경고 테두리 + 위험 게이지!)
        let clubCols: [UIColor] = [.systemPink, .systemCyan, .systemYellow, .systemPurple, .systemGreen]
        let frameCol = (isFreezePhase && isWiggling) ? UIColor.systemRed : (isFreezePhase ? UIColor.systemCyan : clubCols[Int(t * beatHz) % clubCols.count])
        clubBorder?.path = CGPath(rect: CGRect(x: 6, y: 6, width: max(1, size.width - 12), height: max(1, size.height - 12)), transform: nil)
        clubBorder?.strokeColor = frameCol
        clubBorder?.lineWidth = (isFreezePhase && isWiggling) ? 22 : (isFreezePhase ? 14 : (8 + beatPulse * 12))
        clubBorder?.alpha = (isFreezePhase && isWiggling) ? 0.94 : (isFreezePhase ? 0.78 : (0.35 + beatPulse * 0.55))

        freezeProgBg?.isHidden = !isFreezePhase
        freezeProgFill?.isHidden = !isFreezePhase
        freezeProgLabel?.isHidden = !isFreezePhase
        freezeMeterBg?.isHidden = !isFreezePhase
        freezeMeterFill?.isHidden = !isFreezePhase
        if isFreezePhase {
            let dur = max(0.1, freezeDuration)
            let remRatio = max(0.0, min(1.0, freezeTimer / dur))
            let remSec = String(format: "%.1f", max(0.0, Double(freezeTimer)))

            let progPos = CGPoint(x: size.width * 0.5, y: size.height * 0.19)
            freezeProgBg?.position = progPos
            freezeProgFill?.position = progPos
            let pFillW = max(0, 332 * remRatio)
            freezeProgFill?.path = pFillW > 4
                ? CGPath(roundedRect: CGRect(x: -166, y: -9, width: pFillW, height: 18), cornerWidth: 9, cornerHeight: 9, transform: nil)
                : nil
            freezeProgFill?.fillColor = remRatio < 0.25 ? UIColor(red: 0.13, green: 1.0, blue: 0.53, alpha: 1) : .systemCyan
            let progText = remRatio < 0.25 ? "⚡ 곧 땡!! \(remSec)초" : "❄️ 얼음 버티기 \(remSec)초"
            let progStroke = remRatio < 0.25
                ? UIColor(red: 0.08, green: 0.50, blue: 0.24, alpha: 1)
                : UIColor(red: 0.01, green: 0.52, blue: 0.78, alpha: 1)
            setStickerLabel(freezeProgLabel, text: progText, fontSize: 25, strokeColor: progStroke, strokeWidth: 6.5, cacheKey: "\(progText)|\(remRatio < 0.25)")
            freezeProgLabel?.position = CGPoint(x: size.width * 0.5, y: progPos.y + 28)

            let meterPos = CGPoint(x: size.width * 0.5, y: progPos.y - 24)
            freezeMeterBg?.position = meterPos
            freezeMeterBg?.strokeColor = isWiggling ? .systemRed : .systemCyan
            let danger = min(1.0, freezeWiggleTime / 0.48)
            let fillW = max(0, 224 * danger)
            freezeMeterFill?.position = meterPos
            freezeMeterFill?.path = fillW > 2
                ? CGPath(roundedRect: CGRect(x: -112, y: -4, width: fillW, height: 8), cornerWidth: 4, cornerHeight: 4, transform: nil)
                : nil
            freezeMeterFill?.fillColor = danger >= 0.85 ? .systemRed : (danger >= 0.3 ? .systemYellow : .systemCyan)
        }

        // 6) 라운드 합류형 클럽 댄서 128 BPM 리듬 댄스 & 얼음 포즈! (1R 디노 -> 2~3R 모모 -> 4~5R 포포 3마리!)
        let lineup: [(String, CGFloat, CGFloat, CGFloat, Int, UIColor)]
        if freezeRound >= 3 {
            lineup = [
                ("momo", 0.24, 0.45, 0.92, 1, .systemCyan),
                ("dino", 0.50, 0.49, 1.00, 0, .systemPink),
                ("popo", 0.76, 0.45, 0.92, 1, .systemYellow),
            ]
        } else if freezeRound >= 1 {
            lineup = [
                ("momo", 0.34, 0.47, 0.96, 1, .systemCyan),
                ("dino", 0.66, 0.47, 1.00, 0, .systemPink),
            ]
        } else {
            lineup = [
                ("dino", 0.50, 0.49, 1.12, 0, .systemPink),
            ]
        }

        let activeIds = Set(lineup.map { $0.0 })
        for (id, sp) in dancerNodes {
            let show = activeIds.contains(id)
            sp.isHidden = !show
            dancerRings[id]?.isHidden = !show
        }

        let beatIdx = Int(t * beatHz)
        let baseR = min(size.width, size.height) * 0.165
        for (id, nx, ny, scaleMul, ph, col) in lineup {
            guard let sp = dancerNodes[id], let ring = dancerRings[id] else { continue }
            let cx = size.width * nx
            let cy = size.height * ny
            let r = baseR * scaleMul
            let poseKey = isFreezePhase ? "\(id)_freeze" : ((beatIdx + ph) % 2 == 0 ? "\(id)_dance1" : "\(id)_dance2")
            if let tex = textures[poseKey] {
                sp.texture = tex
            }
            sp.size = CGSize(width: r * 2.25, height: r * 2.25)
            sp.position = CGPoint(x: cx, y: cy + (isFreezePhase ? 0 : beatPulse * 18))
            sp.xScale = isFreezePhase ? 1.0 : (1.0 + 0.07 * beatPulse)
            sp.yScale = isFreezePhase ? 1.0 : (1.0 - 0.05 * beatPulse + 0.06 * (1.0 - beatPulse))
            sp.zRotation = isFreezePhase ? 0 : sin(t * beatHz * .pi + CGFloat(ph) * 1.5) * 0.11
            sp.colorBlendFactor = 0

            ring.position = CGPoint(x: cx, y: cy)
            ring.strokeColor = isFreezePhase ? .systemCyan : col
            ring.fillColor = (isFreezePhase ? UIColor.systemCyan : col).withAlphaComponent(isFreezePhase ? 0.24 : 0.28)
            ring.setScale(scaleMul * (1.0 + (isFreezePhase ? 0 : beatPulse * 0.12)))
        }

        if !isFreezePhase {
            if freezeTimer <= 0 {
                let freezeDurs: [CGFloat] = [3.4, 3.8, 4.2, 4.6, 4.8]
                freezeDuration = freezeDurs[min(freezeRound, freezeDurs.count - 1)]
                isFreezePhase = true
                freezeTimer = freezeDuration
                freezeElapsed = 0
                freezeWiggleTime = 0
                wiggleSfxCooldown = 0
                isWiggling = false
                screenShake = 0.55
                flashNode.size = size
                flashNode.color = .systemCyan
                flashNode.alpha = 0.42
                flashNode.removeAllActions()
                flashNode.run(.fadeOut(withDuration: 0.32))
                SoundEngine.shared.pauseBgm()
                SoundEngine.shared.playFreezeCue()
                let isLast = freezeRound == freezeRoundsTotal - 1
                onCallout?(isLast ? "마지막! 만세하고 얼음!!" : "얼음!! 조명 정지! 움직이지 마세요!", 2.6)
            }
        } else {
            if freezeTimer <= 0 {
                freezeRound += 1
                let wiggle = freezeWiggleTime
                if wiggle >= 0.48 {
                    SoundEngine.shared.playFreezeFail()
                    screenShake = 0.7
                    flashNode.size = size
                    flashNode.color = .systemRed
                    flashNode.alpha = 0.42
                    flashNode.removeAllActions()
                    flashNode.run(.fadeOut(withDuration: 0.35))
                    spawnBurst(at: CGPoint(x: size.width * 0.5, y: size.height * 0.50), color: .systemRed, text: "움직여서 들켰어요! +0", power: 2, angle: 0)
                } else if wiggle >= 0.14 {
                    freezeSuccessCount += 1
                    score += 2
                    SoundEngine.shared.playBounce()
                    spawnBurst(at: CGPoint(x: size.width * 0.5, y: size.height * 0.50), color: .systemYellow, text: "아슬아슬 세이프! +2", power: 2, angle: 0)
                } else {
                    freezeSuccessCount += 1
                    score += 5
                    SoundEngine.shared.playDiscoClear()
                    spawnBurst(at: CGPoint(x: size.width * 0.5, y: size.height * 0.50), color: .systemPink, text: "완벽 얼음!! +5", power: 2, angle: 0)
                }
                onScore?(score)
                onProgress?(freezeRound, freezeRoundsTotal)
                isWiggling = false

                if freezeRound >= freezeRoundsTotal {
                    SoundEngine.shared.playClubAirhorn()
                    spawnConfetti()
                    finishGame("네온 클럽 5라운드 중 \(freezeSuccessCount)번 얼음 성공! ⭐ \(score)점!")
                } else {
                    isFreezePhase = false
                    freezeTimer = CGFloat.random(in: 6.8...9.0)
                    danceEnergy = 0.55
                    flashNode.size = size
                    flashNode.color = .systemPink
                    flashNode.alpha = 0.36
                    flashNode.removeAllActions()
                    flashNode.run(.fadeOut(withDuration: 0.30))
                    SoundEngine.shared.playClubAirhorn()
                    let joinMsg = freezeRound == 1
                        ? "디스코 모모 합류!! 둘이 함께 신나게 춤춰요!!"
                        : (freezeRound == 3
                           ? "디스코 포포 합류!! 3마리 완전체 클럽 떼춤!!"
                           : (wiggle >= 0.48 ? "다음엔 꽁꽁! 땡!! 다시 신나게 흔들어요!!" : "땡!! 디스코 타임! 신나게 흔들어요!!"))
                    onCallout?(joinMsg, 2.6)
                    SoundEngine.shared.setBgmRate(min(1.18, 1.0 + Float(freezeRound) * 0.04))
                    SoundEngine.shared.resumeBgm()
                }
            }
        }
    }

    // MARK: - Game 4: Animal Pose Imitation (14-Joint Full-Body Engine + 7-Animal Relay)
    private func setupAnimalPoseUI() {
        // 1) Top-left pie timer
        let pieBg = SKShapeNode(circleOfRadius: 34)
        pieBg.fillColor = .white.withAlphaComponent(0.95)
        pieBg.strokeColor = UIColor(red: 0.12, green: 0.23, blue: 0.37, alpha: 1)
        pieBg.lineWidth = 4.5
        gameLayer.addChild(pieBg)
        animalPieBg = pieBg

        let pieFill = SKShapeNode()
        pieFill.fillColor = .systemYellow
        pieFill.strokeColor = .clear
        gameLayer.addChild(pieFill)
        animalPieFill = pieFill

        // 2) Top 7 animal badges
        for spec in animalPoses {
            let ring = SKShapeNode(circleOfRadius: 19)
            ring.fillColor = .white.withAlphaComponent(0.94)
            ring.strokeColor = UIColor(red: 0.12, green: 0.23, blue: 0.37, alpha: 1)
            ring.lineWidth = 3
            gameLayer.addChild(ring)
            animalBadgeRings.append(ring)

            let sp = SKSpriteNode(texture: textures[spec.tex])
            sp.size = CGSize(width: 30, height: 30)
            gameLayer.addChild(sp)
            animalBadgeSprites.append(sp)
        }

        // 3) Right-upper Name Pill + Cue + Hold Progress Bar
        let pill = SKShapeNode(rectOf: CGSize(width: 156, height: 46), cornerRadius: 23)
        pill.fillColor = .systemYellow
        pill.strokeColor = UIColor(red: 0.12, green: 0.23, blue: 0.37, alpha: 1)
        pill.lineWidth = 4
        gameLayer.addChild(pill)
        animalNamePill = pill

        let nLbl = SKLabelNode()
        nLbl.verticalAlignmentMode = .center
        nLbl.horizontalAlignmentMode = .center
        setStickerLabel(nLbl, text: animalPoses[0].name, fontSize: 27, strokeColor: UIColor(red: 0.12, green: 0.23, blue: 0.37, alpha: 1), strokeWidth: 6.5)
        gameLayer.addChild(nLbl)
        animalNameLbl = nLbl

        let cBg = SKShapeNode(rectOf: CGSize(width: 266, height: 34), cornerRadius: 17)
        cBg.fillColor = UIColor(red: 0.08, green: 0.14, blue: 0.24, alpha: 0.72)
        cBg.strokeColor = UIColor.white.withAlphaComponent(0.42)
        cBg.lineWidth = 1.8
        cBg.zPosition = 8
        gameLayer.addChild(cBg)
        animalCueBg = cBg

        let cLbl = SKLabelNode()
        cLbl.verticalAlignmentMode = .center
        cLbl.horizontalAlignmentMode = .center
        setStickerLabel(cLbl, text: animalPoses[0].cue, fontSize: 17.5, strokeColor: UIColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1), strokeWidth: 5.5)
        cLbl.zPosition = 9
        gameLayer.addChild(cLbl)
        animalCueLbl = cLbl

        let bBg = SKShapeNode(rectOf: CGSize(width: 210, height: 22), cornerRadius: 11)
        bBg.fillColor = UIColor.black.withAlphaComponent(0.55)
        bBg.strokeColor = UIColor(red: 0.12, green: 0.23, blue: 0.37, alpha: 1)
        bBg.lineWidth = 3.5
        gameLayer.addChild(bBg)
        animalBarBg = bBg

        let bFill = SKShapeNode()
        bFill.strokeColor = .clear
        gameLayer.addChild(bFill)
        animalBarFill = bFill

        // Crisp navy-outlined golden 3D star at right end of progress bar!
        let star = SKShapeNode(path: makeStarPath(points: 5, outerRadius: 21, innerRadius: 10))
        star.fillColor = UIColor(red: 1.0, green: 0.83, blue: 0.23, alpha: 1) // #FFD43B
        star.strokeColor = UIColor(red: 0.12, green: 0.23, blue: 0.37, alpha: 1) // #1E3A5F
        star.lineWidth = 3.5
        star.lineJoin = .round
        star.zPosition = 12
        let starHighlight = SKShapeNode(path: makeStarPath(points: 5, outerRadius: 10, innerRadius: 5))
        starHighlight.fillColor = UIColor(red: 1.0, green: 0.96, blue: 0.72, alpha: 0.88)
        starHighlight.strokeColor = .clear
        starHighlight.position = CGPoint(x: -2, y: 2)
        star.addChild(starHighlight)
        gameLayer.addChild(star)
        animalBarStar = star

        // 4) Right-lower 3D Clay Animal Guide
        let glow = SKShapeNode(circleOfRadius: 90)
        glow.fillColor = UIColor.systemGreen.withAlphaComponent(0.32)
        glow.strokeColor = .clear
        glow.blendMode = .add
        glow.alpha = 0
        gameLayer.addChild(glow)
        animalGuideGlow = glow

        let guide = SKSpriteNode(texture: textures[animalPoses[0].tex])
        guide.size = CGSize(width: 170, height: 170)
        gameLayer.addChild(guide)
        animalGuideNode = guide

        // 5) Pooled Organic Nintendo-Style Body Silhouette Rigs (Up to 2 Players — Zero Wireframe Box, Zero Blinking!)
        animalSilhouetteRigs.removeAll()
        for _ in 0..<2 {
            let rig = makeOrganicSilhouetteRig()
            gameLayer.addChild(rig.root)
            animalSilhouetteRigs.append(rig)
        }

        // Bottom-left warm cream circular posture icon badge (3/4-angled pose_<animal>.png + glowing green progress ring)
        let poseBadge = makeCircularMoveBadge(iconId: animalPoses[0].id, title: animalPoses[0].name, radius: 42)
        gameLayer.addChild(poseBadge.container)
        animalPoseBadge = poseBadge
    }

    private func smoothstep(edge0: CGFloat, edge1: CGFloat, x: CGFloat) -> CGFloat {
        let t = max(0, min(1, (x - edge0) / max(1e-5, edge1 - edge0)))
        return t * t * (3.0 - 2.0 * t)
    }

    private func lerpColor(_ a: UIColor, _ b: UIColor, t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 1
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 1
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let u = max(0, min(1, t))
        return UIColor(
            red: r1 + (r2 - r1) * u,
            green: g1 + (g2 - g1) * u,
            blue: b1 + (b2 - b1) * u,
            alpha: a1 + (a2 - a1) * u
        )
    }

    private func makeSilhouetteLimb(lineWidth: CGFloat, parent: SKNode) -> SilhouetteLimb {
        let glow = SKShapeNode()
        glow.fillColor = .clear
        glow.lineWidth = lineWidth + 8.0
        glow.lineCap = .round
        glow.lineJoin = .round
        glow.blendMode = .alpha
        glow.alpha = 0
        glow.zPosition = 0
        parent.addChild(glow)

        let main = SKShapeNode()
        main.fillColor = .clear
        main.lineWidth = lineWidth
        main.lineCap = .round
        main.lineJoin = .round
        main.blendMode = .alpha
        main.alpha = 0
        main.zPosition = 1
        parent.addChild(main)

        return SilhouetteLimb(glow: glow, main: main)
    }

    private func makeOrganicSilhouetteRig() -> OrganicSilhouetteRig {
        let root = SKNode()
        root.zPosition = 20
        root.isHidden = true
        return OrganicSilhouetteRig(
            root: root,
            spine: makeSilhouetteLimb(lineWidth: 11.0, parent: root),
            shoulderArc: makeSilhouetteLimb(lineWidth: 9.0, parent: root),
            pelvisArc: makeSilhouetteLimb(lineWidth: 8.0, parent: root),
            lUpperArm: makeSilhouetteLimb(lineWidth: 9.0, parent: root),
            lForearm: makeSilhouetteLimb(lineWidth: 6.5, parent: root),
            rUpperArm: makeSilhouetteLimb(lineWidth: 9.0, parent: root),
            rForearm: makeSilhouetteLimb(lineWidth: 6.5, parent: root),
            lThigh: makeSilhouetteLimb(lineWidth: 9.0, parent: root),
            lShin: makeSilhouetteLimb(lineWidth: 6.5, parent: root),
            rThigh: makeSilhouetteLimb(lineWidth: 9.0, parent: root),
            rShin: makeSilhouetteLimb(lineWidth: 6.5, parent: root),
            headHalo: makeSilhouetteLimb(lineWidth: 3.5, parent: root)
        )
    }

    private func updateOrganicSilhouetteRig(_ rig: OrganicSilhouetteRig, player p: PlayerPose, matchBlend: CGFloat) {
        rig.root.isHidden = false
        let m = p.metrics

        let idleColor = p.id == 0
            ? UIColor(red: 0.404, green: 0.910, blue: 0.976, alpha: 1.0) // P1 calm sky #67E8F9
            : UIColor(red: 0.992, green: 0.643, blue: 0.686, alpha: 1.0) // P2 calm coral #FDA4AF
        let matchColor = UIColor(red: 0.133, green: 1.0, blue: 0.533, alpha: 1.0) // Nintendo mint #22FF88
        let strokeCol = lerpColor(idleColor, matchColor, t: matchBlend)
        let baseAlpha = 0.40 + 0.36 * matchBlend
        let glowAlphaBase = 0.20 * matchBlend

        func toSK(_ pt: CGPoint) -> CGPoint {
            CGPoint(x: pt.x * size.width, y: (1.0 - pt.y) * size.height)
        }

        func applySegment(_ limb: SilhouetteLimb, from a: CGPoint?, to b: CGPoint?, confA: CGFloat, confB: CGFloat) {
            let vis = smoothstep(edge0: 0.12, edge1: 0.48, x: min(confA, confB))
            guard let a, let b, vis >= 0.02 else {
                limb.main.alpha = 0
                limb.glow.alpha = 0
                return
            }
            let path = CGMutablePath()
            path.move(to: toSK(a))
            path.addLine(to: toSK(b))
            limb.main.path = path
            limb.main.strokeColor = strokeCol
            limb.main.alpha = baseAlpha * vis
            if glowAlphaBase > 0.01 {
                limb.glow.path = path
                limb.glow.strokeColor = matchColor
                limb.glow.alpha = glowAlphaBase * vis
            } else {
                limb.glow.alpha = 0
            }
        }

        func applyQuad(_ limb: SilhouetteLimb, from a: CGPoint?, ctrl c: CGPoint?, to b: CGPoint?, conf: CGFloat) {
            let vis = smoothstep(edge0: 0.12, edge1: 0.48, x: conf)
            guard let a, let c, let b, vis >= 0.02 else {
                limb.main.alpha = 0
                limb.glow.alpha = 0
                return
            }
            let path = CGMutablePath()
            path.move(to: toSK(a))
            path.addQuadCurve(to: toSK(b), control: toSK(c))
            limb.main.path = path
            limb.main.strokeColor = strokeCol
            limb.main.alpha = baseAlpha * vis
            if glowAlphaBase > 0.01 {
                limb.glow.path = path
                limb.glow.strokeColor = matchColor
                limb.glow.alpha = glowAlphaBase * vis
            } else {
                limb.glow.alpha = 0
            }
        }

        let shMid = CGPoint(x: (m.lShoulder.x + m.rShoulder.x) * 0.5, y: (m.lShoulder.y + m.rShoulder.y) * 0.5)
        let neckPt = m.neck ?? CGPoint(x: shMid.x, y: shMid.y - m.torsoH * 0.05)
        let shConf = min(m.lShoulderConf, m.rShoulderConf)
        let hipConf = min(m.lHipConf, m.rHipConf)
        let hipMid: CGPoint? = (m.lHip != nil && m.rHip != nil)
            ? CGPoint(x: (m.lHip!.x + m.rHip!.x) * 0.5, y: (m.lHip!.y + m.rHip!.y) * 0.5)
            : CGPoint(x: shMid.x, y: min(0.95, shMid.y + m.torsoH))
        let spineBottomConf = (m.lHip != nil && m.rHip != nil) ? max(hipConf, shConf * 0.72) : shConf * 0.65

        // 1) Central rounded spine (neckMid -> hipMid)
        applySegment(rig.spine, from: neckPt, to: hipMid, confA: max(m.neckConf, shConf), confB: spineBottomConf)

        // 2) Soft curved shoulder arc (shL -> raised neckCtrl -> shR) & subtle pelvis arc (hipL -> hipMid -> hipR)
        let shCtrl = CGPoint(x: shMid.x, y: shMid.y - m.torsoH * 0.09)
        applyQuad(rig.shoulderArc, from: m.lShoulder, ctrl: shCtrl, to: m.rShoulder, conf: shConf)

        if let lh = m.lHip, let rh = m.rHip, let hm = hipMid {
            let pelvCtrl = CGPoint(x: hm.x, y: hm.y + m.torsoH * 0.06)
            applyQuad(rig.pelvisArc, from: lh, ctrl: pelvCtrl, to: rh, conf: hipConf)
        } else {
            rig.pelvisArc.main.alpha = 0
            rig.pelvisArc.glow.alpha = 0
        }

        // 3) Tapered rounded limbs (upper 9pt -> lower 6.5pt, smooth confidence-driven alpha, ZERO joint dots!)
        applySegment(rig.lUpperArm, from: m.lShoulder, to: m.lElbow, confA: m.lShoulderConf, confB: m.lElbowConf)
        applySegment(rig.lForearm,  from: m.lElbow,    to: p.leftHand, confA: m.lElbowConf, confB: m.lWristConf)
        applySegment(rig.rUpperArm, from: m.rShoulder, to: m.rElbow, confA: m.rShoulderConf, confB: m.rElbowConf)
        applySegment(rig.rForearm,  from: m.rElbow,    to: p.rightHand, confA: m.rElbowConf, confB: m.rWristConf)

        applySegment(rig.lThigh, from: m.lHip,  to: m.lKnee,  confA: m.lHipConf,  confB: m.lKneeConf)
        applySegment(rig.lShin,  from: m.lKnee, to: m.lAnkle, confA: m.lKneeConf, confB: m.lAnkleConf)
        applySegment(rig.rThigh, from: m.rHip,  to: m.rKnee,  confA: m.rHipConf,  confB: m.rKneeConf)
        applySegment(rig.rShin,  from: m.rKnee, to: m.rAnkle, confA: m.rKneeConf, confB: m.rAnkleConf)

        // 4) Calm open head halo
        let headVis = smoothstep(edge0: 0.12, edge1: 0.48, x: m.headConf)
        if headVis >= 0.02 {
            let hc = toSK(p.head)
            let hr: CGFloat = 16.0
            let hp = CGPath(ellipseIn: CGRect(x: hc.x - hr, y: hc.y - hr, width: hr * 2, height: hr * 2), transform: nil)
            rig.headHalo.main.path = hp
            rig.headHalo.main.strokeColor = strokeCol
            rig.headHalo.main.alpha = baseAlpha * headVis
            if glowAlphaBase > 0.01 {
                rig.headHalo.glow.path = hp
                rig.headHalo.glow.strokeColor = matchColor
                rig.headHalo.glow.alpha = glowAlphaBase * headVis
            } else {
                rig.headHalo.glow.alpha = 0
            }
        } else {
            rig.headHalo.main.alpha = 0
            rig.headHalo.glow.alpha = 0
        }
    }

    private func checkPlayerAnimalPose(_ p: PlayerPose, id: String) -> Bool {
        let m = p.metrics
        let bothUp = p.leftHand.y < p.head.y + m.torsoH * 0.08 && p.rightHand.y < p.head.y + m.torsoH * 0.08
        let bothAboveSh = p.leftHand.y < m.shoulderY - m.torsoH * 0.05 && p.rightHand.y < m.shoulderY - m.torsoH * 0.05
        switch id {
        case "giraffe":
            return bothUp && max(m.lElbowAngle, m.rElbowAngle) > 115
        case "eagle":
            return m.wristSpan > m.shoulderW * 1.75
                && abs(p.leftHand.y - m.shoulderY) < m.torsoH * 0.55
                && abs(p.rightHand.y - m.shoulderY) < m.torsoH * 0.55
        case "crab":
            let handsAboveElbows = p.leftHand.y < m.lElbow.y && p.rightHand.y < m.rElbow.y
            return handsAboveElbows && m.lElbowAngle < 135 && m.rElbowAngle < 135 && m.wristSpan > m.shoulderW * 1.15
        case "flamingo":
            return m.footLift > m.torsoH * 0.22 || (m.wristSpan > m.shoulderW * 1.65 && m.torsoLean > 0.12)
        case "frog":
            return m.isSquatting || (p.leftHand.y > m.hipY - m.torsoH * 0.1 && p.rightHand.y > m.hipY - m.torsoH * 0.1 && p.head.y > 0.52)
        case "elephant":
            let sameSide = (p.leftHand.x < p.centerX - m.shoulderW * 0.2 && p.rightHand.x < p.centerX + m.shoulderW * 0.3)
                || (p.leftHand.x > p.centerX - m.shoulderW * 0.3 && p.rightHand.x > p.centerX + m.shoulderW * 0.2)
            return m.torsoLean > 0.14 || sameSide
        case "starfish":
            return (bothAboveSh || m.wristSpan > m.shoulderW * 1.7) && (m.ankleSpan > m.shoulderW * 1.15 || bothUp)
        default:
            return bothUp
        }
    }

    private func updateAnimalPose(dt: CGFloat, players: [PlayerPose]) {
        guard animalIndex < animalPoses.count else { return }
        let cur = animalPoses[animalIndex]
        let t = CGFloat(elapsed)

        if animalPause > 0 {
            animalPause -= dt
            animalMatchBlend = max(0, animalMatchBlend - dt * 4.0)
            for (rigIdx, rig) in animalSilhouetteRigs.enumerated() {
                if rigIdx < players.count {
                    updateOrganicSilhouetteRig(rig, player: players[rigIdx], matchBlend: animalMatchBlend)
                } else {
                    rig.root.isHidden = true
                }
            }
        } else {
            animalTimer = max(0, animalTimer - dt)
            var matchCount = 0
            for p in players {
                if checkPlayerAnimalPose(p, id: cur.id) { matchCount += 1 }
            }
            let matched = matchCount > 0
            if matched {
                animalMatchGrace = 0.15
                let boost: CGFloat = matchCount >= 2 ? 1.35 : 1.0
                let prevStep = Int((animalHold / animalHoldTarget) * 3)
                animalHold = min(animalHoldTarget, animalHold + dt * boost)
                let nextStep = Int((animalHold / animalHoldTarget) * 3)
                if nextStep > prevStep && nextStep < 3 { SoundEngine.shared.playClick() }
            } else if animalMatchGrace > 0 {
                // Kid-friendly 0.15s match-loss grace so micro-wobbles don't penalize 4-6yo kids
                animalMatchGrace = max(0, animalMatchGrace - dt)
            } else {
                animalHold = max(0, animalHold - dt * 0.45)
            }
            let effectiveMatched = matched || animalMatchGrace > 0
            animalMatchBlend += ((effectiveMatched ? 1.0 : 0.0) - animalMatchBlend) * min(1.0, dt * 8.0)

            // Layout & update HUD
            let piePos = CGPoint(x: 68, y: size.height - 96)
            animalPieBg?.position = piePos
            let timeRatio = max(0, min(1, animalTimer / animalTimeLimit))
            let piePath = CGMutablePath()
            if timeRatio > 0.01 {
                piePath.move(to: .zero)
                piePath.addArc(center: .zero, radius: 30, startAngle: .pi / 2, endAngle: .pi / 2 - (.pi * 2 * timeRatio), clockwise: true)
                piePath.closeSubpath()
            }
            animalPieFill?.position = piePos
            animalPieFill?.path = piePath
            animalPieFill?.fillColor = timeRatio < 0.25 ? .systemRed : .systemYellow

            for i in animalPoses.indices {
                let bx = 136 + CGFloat(i) * 44
                let by = piePos.y
                let isCur = i == animalIndex
                let isDone = animalCleared[i]
                animalBadgeRings[i].position = CGPoint(x: bx, y: by)
                animalBadgeRings[i].fillColor = isDone ? UIColor(red: 1.0, green: 0.95, blue: 0.69, alpha: 0.95) : .white.withAlphaComponent(0.94)
                animalBadgeRings[i].strokeColor = isCur ? .systemYellow : (isDone ? .systemGreen : UIColor(red: 0.12, green: 0.23, blue: 0.37, alpha: 1))
                animalBadgeRings[i].lineWidth = isCur ? 4.5 : 2.5
                animalBadgeRings[i].setScale(isCur ? 1.15 : 1.0)
                animalBadgeSprites[i].position = CGPoint(x: bx, y: by)
                animalBadgeSprites[i].alpha = isDone ? 0.55 : 1.0
            }

            let panelX = size.width * 0.80
            let pillY = size.height * 0.78
            animalNamePill?.position = CGPoint(x: panelX, y: pillY)
            animalNamePill?.fillColor = cur.color
            setStickerLabel(animalNameLbl, text: cur.name, fontSize: 27, strokeColor: UIColor(red: 0.12, green: 0.23, blue: 0.37, alpha: 1), strokeWidth: 6.5)
            animalNameLbl?.position = CGPoint(x: panelX, y: pillY)
            animalCueBg?.position = CGPoint(x: panelX, y: pillY - 40)
            animalCueBg?.strokeColor = effectiveMatched ? UIColor(red: 0.13, green: 1.0, blue: 0.53, alpha: 0.90) : UIColor.white.withAlphaComponent(0.45)
            setStickerLabel(animalCueLbl, text: cur.cue, fontSize: 17.5, strokeColor: UIColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1), strokeWidth: 5.5)
            animalCueLbl?.position = CGPoint(x: panelX, y: pillY - 40)

            let barPos = CGPoint(x: panelX, y: pillY - 72)
            animalBarBg?.position = barPos
            animalBarFill?.position = barPos
            let holdRatio = max(0, min(1, animalHold / animalHoldTarget))
            let fillW = max(0, 202 * holdRatio)
            animalBarFill?.path = fillW > 3
                ? CGPath(roundedRect: CGRect(x: -101, y: -7, width: fillW, height: 14), cornerWidth: 7, cornerHeight: 7, transform: nil)
                : nil
            animalBarFill?.fillColor = effectiveMatched ? UIColor(red: 0.22, green: 0.94, blue: 0.49, alpha: 1) : .systemCyan

            // Crisp navy-outlined golden 3D star at the right end of the hold bar
            animalBarStar?.position = CGPoint(x: barPos.x + 108, y: barPos.y)
            animalBarStar?.setScale(effectiveMatched ? (1.08 + 0.10 * sin(t * 10)) : 1.0)
            animalBarStar?.zRotation = effectiveMatched ? sin(t * 7) * 0.14 : 0

            let guideDim = min(size.width, size.height) * 0.40
            let guidePos = CGPoint(x: size.width * 0.84, y: size.height * 0.30 + sin(t * (effectiveMatched ? 8 : 3)) * (effectiveMatched ? 8 : 4))
            animalGuideNode?.texture = textures[cur.tex]
            animalGuideNode?.size = CGSize(width: guideDim, height: guideDim)
            animalGuideNode?.position = guidePos
            animalGuideNode?.setScale(1.0 + 0.06 * animalMatchBlend)
            animalGuideGlow?.position = guidePos
            animalGuideGlow?.alpha = 0.85 * animalMatchBlend

            // Calm, organic, rounded glowing Nintendo-style body silhouette (ZERO wireframe box, ZERO white dots, ZERO blinking!)
            for (rigIdx, rig) in animalSilhouetteRigs.enumerated() {
                if rigIdx < players.count {
                    updateOrganicSilhouetteRig(rig, player: players[rigIdx], matchBlend: animalMatchBlend)
                } else {
                    rig.root.isHidden = true
                }
            }

            // Bottom-left warm cream circular posture icon badge (cute 3/4 pose_<animal>.png + glowing green progress ring!)
            if let badge = animalPoseBadge {
                badge.container.position = CGPoint(x: 80, y: 82)
                updateCircularMoveBadge(
                    badge,
                    iconId: cur.id,
                    title: "\(cur.name) 포즈",
                    progress: holdRatio,
                    active: true,
                    pulse: 1.0 + (0.04 + 0.04 * sin(t * 9)) * animalMatchBlend
                )
            }

            if animalHold >= animalHoldTarget || animalTimer <= 0 {
                let cleared = animalHold >= animalHoldTarget
                if cleared {
                    animalCleared[animalIndex] = true
                    animalSuccessCount += 1
                    score += 10
                    SoundEngine.shared.playGoldenPop()
                    spawnBurst(at: CGPoint(x: size.width * 0.5, y: size.height * 0.52), color: cur.color, text: "\(cur.name) 완벽 변신! +10", power: 2, angle: 0)
                } else {
                    score += 2
                    SoundEngine.shared.playBounce()
                    spawnBurst(at: CGPoint(x: size.width * 0.5, y: size.height * 0.52), color: .lightGray, text: "아쉬워요! 다음 도전! +2", power: 1, angle: 0)
                }
                onScore?(score)
                animalIndex += 1
                onProgress?(animalIndex, animalPoses.count)

                if animalIndex >= animalPoses.count {
                    spawnConfetti()
                    finishGame("동물 7종 중 \(animalSuccessCount)마리 완벽 변신! ⭐ \(score)점!")
                } else {
                    let next = animalPoses[animalIndex]
                    animalTimer = animalTimeLimit
                    animalHold = 0
                    animalMatchGrace = 0
                    animalMatchBlend = 0
                    animalPause = 0.85
                    onCallout?("\(next.name)! \(next.cue)", 2.8)
                }
            }
        }
    }

    private func makeStickFigurePath(id: String, scale s: CGFloat) -> CGPath {
        // Y-up coordinates for SpriteKit!
        let p = CGMutablePath()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: -y * s - 4) }
        func ln(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat)) {
            p.move(to: pt(a.0, a.1)); p.addLine(to: pt(b.0, b.1))
        }
        let hd, nk, hp, lE, lH, rE, rH, lK, lF, rK, rF: (CGFloat, CGFloat)
        switch id {
        case "eagle":
            (hd,nk,hp) = ((0,-0.95),(0,-0.55),(0,0.20))
            (lE,lH,rE,rH) = ((-0.75,-0.55),(-1.35,-0.62),(0.75,-0.55),(1.35,-0.62))
            (lK,lF,rK,rF) = ((-0.28,0.70),(-0.28,1.15),(0.28,0.70),(0.28,1.15))
        case "crab":
            (hd,nk,hp) = ((0,-0.75),(0,-0.38),(0,0.32))
            (lE,lH,rE,rH) = ((-0.72,-0.35),(-0.76,-0.95),(0.72,-0.35),(0.76,-0.95))
            (lK,lF,rK,rF) = ((-0.62,0.65),(-0.52,1.15),(0.62,0.65),(0.52,1.15))
        case "flamingo":
            (hd,nk,hp) = ((0,-0.95),(0,-0.55),(0,0.20))
            (lE,lH,rE,rH) = ((-0.68,-0.48),(-1.22,-0.45),(0.68,-0.48),(1.22,-0.45))
            (lK,lF,rK,rF) = ((-0.18,0.70),(-0.18,1.18),(0.52,0.48),(0.16,0.76))
        case "frog":
            (hd,nk,hp) = ((0,-0.35),(0,0.02),(0,0.62))
            (lE,lH,rE,rH) = ((-0.45,0.45),(-0.24,1.02),(0.45,0.45),(0.24,1.02))
            (lK,lF,rK,rF) = ((-0.78,0.48),(-0.58,1.08),(0.78,0.48),(0.58,1.08))
        case "elephant":
            (hd,nk,hp) = ((0.38,-0.88),(0.24,-0.52),(0,0.20))
            (lE,lH,rE,rH) = ((0.55,-0.22),(1.05,-0.08),(0.62,-0.36),(1.05,-0.20))
            (lK,lF,rK,rF) = ((-0.25,0.70),(-0.25,1.15),(0.25,0.70),(0.25,1.15))
        case "starfish":
            (hd,nk,hp) = ((0,-0.95),(0,-0.55),(0,0.18))
            (lE,lH,rE,rH) = ((-0.68,-0.88),(-1.18,-1.32),(0.68,-0.88),(1.18,-1.32))
            (lK,lF,rK,rF) = ((-0.50,0.68),(-0.95,1.18),(0.50,0.68),(0.95,1.18))
        case "run":
            (hd,nk,hp) = ((0.10,-0.95),(0.05,-0.55),(-0.05,0.15))
            (lE,lH,rE,rH) = ((-0.52,-0.25),(-0.78,-0.55),(0.58,-0.32),(0.88,-0.72))
            (lK,lF,rK,rF) = ((-0.52,0.52),(-0.88,1.05),(0.52,0.42),(0.24,0.92))
        case "squat":
            (hd,nk,hp) = ((0,-0.45),(0,-0.08),(0,0.52))
            (lE,lH,rE,rH) = ((-0.55,0.02),(-0.82,-0.12),(0.55,0.02),(0.82,-0.12))
            (lK,lF,rK,rF) = ((-0.68,0.50),(-0.54,1.08),(0.68,0.50),(0.54,1.08))
        case "jump":
            (hd,nk,hp) = ((0,-1.08),(0,-0.68),(0,0.08))
            (lE,lH,rE,rH) = ((-0.55,-1.02),(-0.82,-1.52),(0.55,-1.02),(0.82,-1.52))
            (lK,lF,rK,rF) = ((-0.42,0.58),(-0.62,1.06),(0.42,0.58),(0.62,1.06))
        default: // giraffe
            (hd,nk,hp) = ((0,-1.05),(0,-0.65),(0,0.15))
            (lE,lH,rE,rH) = ((-0.42,-0.95),(-0.38,-1.55),(0.42,-0.95),(0.38,-1.55))
            (lK,lF,rK,rF) = ((-0.25,0.65),(-0.25,1.15),(0.25,0.65),(0.25,1.15))
        }
        ln(nk, hp); ln(nk, lE); ln(lE, lH); ln(nk, rE); ln(rE, rH)
        ln(hp, lK); ln(lK, lF); ln(hp, rK); ln(rK, rF)
        let hc = pt(hd.0, hd.1)
        let hr = max(4.5, s * 0.24)
        p.addEllipse(in: CGRect(x: hc.x - hr, y: hc.y - hr, width: hr * 2, height: hr * 2))
        return p
    }

    private func makeStarPath(outerR: CGFloat, innerR: CGFloat) -> CGPath {
        makeStarPath(points: 5, outerRadius: outerR, innerRadius: innerR)
    }

    private func makeStarPath(points: Int, outerRadius: CGFloat, innerRadius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let step = CGFloat.pi / CGFloat(points)
        for i in 0..<(points * 2) {
            let r = (i % 2 == 0) ? outerRadius : innerRadius
            let ang = CGFloat.pi / 2 + CGFloat(i) * step
            let pt = CGPoint(x: cos(ang) * r, y: sin(ang) * r)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }

    private func makeCircularMoveBadge(iconId: String, title: String, radius: CGFloat) -> CircularMoveBadge {
        let container = SKNode()
        container.zPosition = 28

        let glow = SKShapeNode(circleOfRadius: radius + 12)
        glow.fillColor = UIColor(red: 0.13, green: 1.0, blue: 0.53, alpha: 0.26)
        glow.strokeColor = .clear
        glow.blendMode = .add
        glow.alpha = 0
        container.addChild(glow)

        let bg = SKShapeNode(circleOfRadius: radius)
        bg.fillColor = UIColor(red: 1.0, green: 0.99, blue: 0.96, alpha: 0.96) // Warm cream #FFFDF5
        bg.strokeColor = UIColor(red: 0.12, green: 0.23, blue: 0.37, alpha: 0.85)
        bg.lineWidth = 3.0
        container.addChild(bg)

        let track = SKShapeNode(circleOfRadius: radius + 4.5)
        track.fillColor = .clear
        track.strokeColor = UIColor.black.withAlphaComponent(0.18)
        track.lineWidth = 6.5
        container.addChild(track)

        let prog = SKShapeNode()
        prog.fillColor = .clear
        prog.strokeColor = UIColor(red: 0.13, green: 1.0, blue: 0.53, alpha: 1.0) // Glowing neon green #22FF88
        prog.lineWidth = 7.0
        prog.lineCap = .round
        container.addChild(prog)

        // Cute 3/4-angled pose_<id>.png sprite (78% of circle diameter -> radius * 1.56, clean circular-safe framing!)
        let poseTex = textures["pose_\(iconId)"]
        let spriteDim = radius * 1.56
        let iconSprite = SKSpriteNode(texture: poseTex)
        iconSprite.size = CGSize(width: spriteDim, height: spriteDim)
        iconSprite.isHidden = (poseTex == nil)
        iconSprite.zPosition = 2
        container.addChild(iconSprite)

        // Fallback vector stickman ONLY if pose texture is missing
        let icon = SKShapeNode(path: makeStickFigurePath(id: iconId, scale: radius * 0.44))
        icon.strokeColor = UIColor(red: 0.11, green: 0.36, blue: 0.23, alpha: 1.0)
        icon.fillColor = .clear
        icon.lineWidth = 3.8
        icon.lineCap = .round
        icon.lineJoin = .round
        icon.isHidden = (poseTex != nil)
        icon.zPosition = 2
        container.addChild(icon)

        let lblBg = SKShapeNode(rectOf: CGSize(width: max(98, radius * 2.55), height: 25), cornerRadius: 12.5)
        lblBg.fillColor = UIColor(red: 0.09, green: 0.32, blue: 0.18, alpha: 0.92)
        lblBg.strokeColor = UIColor(red: 1.0, green: 0.99, blue: 0.96, alpha: 0.92)
        lblBg.lineWidth = 1.8
        lblBg.position = CGPoint(x: 0, y: -(radius + 18))
        container.addChild(lblBg)

        let lbl = SKLabelNode()
        lbl.verticalAlignmentMode = .center
        lbl.horizontalAlignmentMode = .center
        setStickerLabel(lbl, text: title, fontSize: 14, strokeColor: UIColor(red: 0.08, green: 0.33, blue: 0.18, alpha: 1), strokeWidth: 5.0, cacheKey: "\(title)|true")
        lbl.position = lblBg.position
        container.addChild(lbl)

        return CircularMoveBadge(
            container: container,
            glowCircle: glow,
            bgCircle: bg,
            trackRing: track,
            progressRing: prog,
            iconSprite: iconSprite,
            iconNode: icon,
            labelBg: lblBg,
            label: lbl,
            radius: radius
        )
    }

    private func updateCircularMoveBadge(_ badge: CircularMoveBadge, iconId: String? = nil, title: String? = nil, progress: CGFloat, active: Bool, pulse: CGFloat = 1.0) {
        if let iconId {
            if let poseTex = textures["pose_\(iconId)"] {
                badge.iconSprite.texture = poseTex
                badge.iconSprite.isHidden = false
                badge.iconNode.isHidden = true
            } else {
                badge.iconSprite.isHidden = true
                badge.iconNode.isHidden = false
                badge.iconNode.path = makeStickFigurePath(id: iconId, scale: badge.radius * 0.44)
            }
        }
        let displayTitle = title ?? badge.label.attributedText?.string ?? ""
        if !displayTitle.isEmpty {
            let strokeCol = active
                ? UIColor(red: 0.08, green: 0.33, blue: 0.18, alpha: 1) // #14532D
                : UIColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1) // #0F172A
            setStickerLabel(badge.label, text: displayTitle, fontSize: 14, strokeColor: strokeCol, strokeWidth: 5.0, cacheKey: "\(displayTitle)|\(active)")
        }
        badge.labelBg.fillColor = active
            ? UIColor(red: 0.09, green: 0.40, blue: 0.20, alpha: 0.94)
            : UIColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 0.76)
        badge.labelBg.strokeColor = active
            ? UIColor(red: 0.13, green: 1.0, blue: 0.53, alpha: 0.95)
            : UIColor.white.withAlphaComponent(0.75)
        let clamped = max(0, min(1, progress))
        if clamped > 0.01 {
            let arc = CGMutablePath()
            arc.addArc(
                center: .zero,
                radius: badge.radius + 4.5,
                startAngle: .pi / 2,
                endAngle: .pi / 2 - (.pi * 2 * clamped),
                clockwise: true
            )
            badge.progressRing.path = arc
            badge.progressRing.alpha = 1.0
        } else {
            badge.progressRing.path = nil
            badge.progressRing.alpha = 0
        }
        badge.container.alpha = active ? 1.0 : 0.68
        badge.container.setScale(active ? pulse : 0.90)
        badge.glowCircle.alpha = active ? (0.45 + 0.35 * clamped) : 0
        badge.bgCircle.strokeColor = active
            ? UIColor(red: 0.13, green: 0.85, blue: 0.45, alpha: 1.0)
            : UIColor(red: 0.12, green: 0.23, blue: 0.37, alpha: 0.65)
    }

    // MARK: - Game 5: Jungle Adventure (60s, Run / Squat under Vine / Jump Star Smash!)
    private func setupJungleGame() {
        // 1) Top 5-flag jungle progress track
        let trackW = min(380, size.width * 0.44)
        let trackBg = SKShapeNode(rectOf: CGSize(width: trackW, height: 14), cornerRadius: 7)
        trackBg.fillColor = UIColor(red: 0.14, green: 0.26, blue: 0.16, alpha: 0.78)
        trackBg.strokeColor = UIColor(red: 1.0, green: 0.96, blue: 0.80, alpha: 0.92)
        trackBg.lineWidth = 2.5
        trackBg.zPosition = 24
        gameLayer.addChild(trackBg)
        jungleTrackBg = trackBg

        let trackFill = SKShapeNode()
        trackFill.fillColor = UIColor(red: 0.22, green: 0.94, blue: 0.49, alpha: 1)
        trackFill.strokeColor = .clear
        trackFill.zPosition = 25
        gameLayer.addChild(trackFill)
        jungleTrackFill = trackFill

        for _ in 0..<5 {
            let fl = SKShapeNode(circleOfRadius: 7)
            fl.fillColor = .white
            fl.strokeColor = UIColor(red: 0.12, green: 0.28, blue: 0.18, alpha: 1)
            fl.lineWidth = 2
            fl.zPosition = 26
            gameLayer.addChild(fl)
            jungleFlagNodes.append(fl)
        }

        let tMomo = SKSpriteNode(texture: textures["momo"])
        tMomo.size = CGSize(width: 34, height: 34)
        tMomo.zPosition = 27
        gameLayer.addChild(tMomo)
        jungleTrackMomo = tMomo

        // 2) Phase Banner Pill
        let pPill = SKShapeNode(rectOf: CGSize(width: 268, height: 44), cornerRadius: 22)
        pPill.fillColor = UIColor(red: 0.11, green: 0.65, blue: 0.36, alpha: 0.92)
        pPill.strokeColor = .white
        pPill.lineWidth = 3
        pPill.zPosition = 26
        gameLayer.addChild(pPill)
        junglePhasePill = pPill

        let pLbl = SKLabelNode()
        pLbl.verticalAlignmentMode = .center
        pLbl.horizontalAlignmentMode = .center
        setStickerLabel(pLbl, text: "🏃 제자리 달리기!", fontSize: 21, strokeColor: UIColor(red: 0.08, green: 0.33, blue: 0.18, alpha: 1), strokeWidth: 6.0)
        pLbl.zPosition = 27
        gameLayer.addChild(pLbl)
        junglePhaseLbl = pLbl

        // 3) Descending 3D Clay Jungle Vine + Momo Squat Guide
        if let vTex = textures["jungle_vine"] {
            let vine = SKSpriteNode(texture: vTex)
            let vw = size.width * 0.94
            let aspect = vTex.size().height / max(1, vTex.size().width)
            vine.size = CGSize(width: vw, height: max(92, vw * aspect))
            vine.position = CGPoint(x: size.width * 0.5, y: size.height + 140)
            vine.zPosition = 18
            vine.isHidden = true
            gameLayer.addChild(vine)
            jungleVineNode = vine
        } else {
            let fb = SKShapeNode(rectOf: CGSize(width: size.width * 0.92, height: 54), cornerRadius: 27)
            fb.fillColor = UIColor(red: 0.20, green: 0.72, blue: 0.28, alpha: 0.94)
            fb.strokeColor = .systemYellow
            fb.lineWidth = 4
            fb.position = CGPoint(x: size.width * 0.5, y: size.height + 120)
            fb.zPosition = 18
            fb.isHidden = true
            gameLayer.addChild(fb)
            jungleVineFallback = fb
        }

        let mSquat = SKSpriteNode(texture: textures["momo_squat"] ?? textures["momo"])
        mSquat.size = CGSize(width: 136, height: 136)
        mSquat.zPosition = 19
        mSquat.isHidden = true
        gameLayer.addChild(mSquat)
        jungleMomoSquat = mSquat

        // 4) Bottom 3 Creamy Circular Move Badges:
        // Bottom-left 2 badges (제자리 달리기, 웅크리기) + Bottom-right 1 badge (점프 만세!)
        let runBadge = makeCircularMoveBadge(iconId: "run", title: "제자리 달리기", radius: 36)
        let squatBadge = makeCircularMoveBadge(iconId: "squat", title: "웅크리기", radius: 36)
        let jumpBadge = makeCircularMoveBadge(iconId: "jump", title: "점프 만세!", radius: 36)
        gameLayer.addChild(runBadge.container)
        gameLayer.addChild(squatBadge.container)
        gameLayer.addChild(jumpBadge.container)
        jungleBadges = [.run: runBadge, .squat: squatBadge, .jump: jumpBadge]

        enterJunglePhase(.run, announce: false)
    }

    private func clearJungleStars() {
        for s in jungleStars { s.node.removeFromParent() }
        jungleStars.removeAll()
    }

    private func enterJunglePhase(_ next: JunglePhase, announce: Bool = true) {
        junglePhase = next
        junglePhaseProgress = 0
        clearJungleStars()

        switch next {
        case .run:
            junglePhaseTimer = 6.2
            jungleVineNode?.isHidden = true
            jungleVineFallback?.isHidden = true
            jungleMomoSquat?.isHidden = true
            junglePhasePill?.fillColor = UIColor(red: 0.14, green: 0.72, blue: 0.42, alpha: 0.94)
            setStickerLabel(junglePhaseLbl, text: "🏃 제자리 달리기!", fontSize: 21, strokeColor: UIColor(red: 0.08, green: 0.33, blue: 0.18, alpha: 1), strokeWidth: 6.0)
            if announce { onCallout?("🏃 신나게 제자리 달리기!!", 2.2) }

        case .squat:
            junglePhaseTimer = 6.8
            jungleVineNode?.isHidden = false
            jungleVineNode?.position = CGPoint(x: size.width * 0.5, y: size.height + 90)
            jungleVineFallback?.isHidden = false
            jungleVineFallback?.position = CGPoint(x: size.width * 0.5, y: size.height + 90)
            jungleMomoSquat?.isHidden = false
            junglePhasePill?.fillColor = UIColor(red: 0.96, green: 0.56, blue: 0.12, alpha: 0.94)
            setStickerLabel(junglePhaseLbl, text: "🌿 숙여요! 웅크리기!", fontSize: 21, strokeColor: UIColor(red: 0.49, green: 0.18, blue: 0.07, alpha: 1), strokeWidth: 6.0)
            if announce { onCallout?("🌿 덩굴이 내려와요! 쏙 웅크리기!!", 2.4) }

        case .jump:
            junglePhaseTimer = 6.8
            jungleVineNode?.isHidden = true
            jungleVineFallback?.isHidden = true
            jungleMomoSquat?.isHidden = true
            junglePhasePill?.fillColor = UIColor(red: 0.95, green: 0.72, blue: 0.08, alpha: 0.95)
            setStickerLabel(junglePhaseLbl, text: "⭐ 점프 만세! 별 터치!", fontSize: 21, strokeColor: UIColor(red: 0.47, green: 0.21, blue: 0.06, alpha: 1), strokeWidth: 6.0)
            spawnJungleStars()
            if announce { onCallout?("⭐ 점프 만세! 하늘의 별을 팡팡 터치!!", 2.4) }
        }
    }

    private func spawnJungleStars() {
        clearJungleStars()
        let count = settings.players == 2 ? 5 : 4
        let r = min(size.width, size.height) * 0.082
        for i in 0..<count {
            let frac = count > 1 ? (0.18 + 0.64 * CGFloat(i) / CGFloat(count - 1)) : 0.5
            let baseY = size.height * (0.72 + (i % 2 == 0 ? 0.08 : 0.02))
            let node: SKSpriteNode
            if let tex = textures["star_3d"] {
                node = SKSpriteNode(texture: tex)
                node.size = CGSize(width: r * 2.1, height: r * 2.1)
            } else {
                node = SKSpriteNode(color: .clear, size: CGSize(width: r * 2, height: r * 2))
                let shape = SKShapeNode(path: makeStarPath(points: 5, outerRadius: r, innerRadius: r * 0.48))
                shape.fillColor = .systemYellow
                shape.strokeColor = UIColor(red: 0.12, green: 0.23, blue: 0.37, alpha: 1)
                shape.lineWidth = 3.5
                node.addChild(shape)
            }
            node.position = CGPoint(x: size.width * frac, y: baseY)
            node.zPosition = 20
            node.setScale(0.1)
            node.run(.scale(to: 1.0, duration: 0.28))
            gameLayer.addChild(node)
            jungleStars.append(JungleStar(node: node, baseY: baseY, radius: r, seed: CGFloat(i) * 1.3))
        }
    }

    private func updateJungleGame(dt: CGFloat, players: [PlayerPose]) {
        let t = CGFloat(elapsed)
        jungleElapsed += dt
        junglePhaseTimer -= dt
        jungleRunCooldown = max(0, jungleRunCooldown - dt)

        let totalRatio = max(0, min(1, jungleElapsed / jungleDuration))
        let checkpoints = min(5, Int(totalRatio * 5.0))
        onProgress?(checkpoints, 5)

        if jungleElapsed >= jungleDuration {
            clearJungleStars()
            spawnConfetti()
            finishGame("정글 모험 60초 완주! ⭐ \(score)점 대성공!")
            return
        }

        // Layout top 5-flag jungle track & phase pill (lifted into clean top-center HUD space!)
        let trackW = min(380, size.width * 0.44)
        let trackPos = CGPoint(x: size.width * 0.5, y: size.height - 54)
        jungleTrackBg?.position = trackPos
        jungleTrackFill?.position = trackPos
        let fillW = max(0, (trackW - 6) * totalRatio)
        jungleTrackFill?.path = fillW > 3
            ? CGPath(roundedRect: CGRect(x: -(trackW - 6) * 0.5, y: -4.5, width: fillW, height: 9), cornerWidth: 4.5, cornerHeight: 4.5, transform: nil)
            : nil
        for (i, fl) in jungleFlagNodes.enumerated() {
            let fx = trackPos.x - (trackW * 0.46) + (trackW * 0.92) * (CGFloat(i) / 4.0)
            fl.position = CGPoint(x: fx, y: trackPos.y)
            fl.fillColor = i < checkpoints ? .systemYellow : .white
        }
        jungleTrackMomo?.position = CGPoint(
            x: trackPos.x - (trackW * 0.46) + (trackW * 0.92) * totalRatio,
            y: trackPos.y + 18 + abs(sin(t * 9)) * 6
        )

        junglePhasePill?.position = CGPoint(x: size.width * 0.5, y: size.height - 96)
        junglePhaseLbl?.position = CGPoint(x: size.width * 0.5, y: size.height - 96)

        // Phase logic
        let hMult = settings.speed.hitboxMult
        switch junglePhase {
        case .run:
            var runningNow = false
            for p in players {
                let m = p.metrics
                if p.motion > 0.022 || m.footLift > m.torsoH * 0.14 {
                    runningNow = true
                }
            }
            if runningNow {
                junglePhaseProgress = min(1.0, junglePhaseProgress + dt * 0.34)
                if jungleRunCooldown <= 0 {
                    jungleRunCooldown = 0.58
                    score += 1
                    onScore?(score)
                    SoundEngine.shared.playClick()
                    spawnFloatingText("다다닥! +1", at: CGPoint(x: size.width * CGFloat.random(in: 0.32...0.68), y: size.height * 0.36), color: .systemGreen, big: false)
                }
            }
            if junglePhaseProgress >= 1.0 || junglePhaseTimer <= 0 {
                if junglePhaseProgress >= 1.0 {
                    score += 6
                    onScore?(score)
                    SoundEngine.shared.playGoldenPop()
                    spawnBurst(at: CGPoint(x: size.width * 0.5, y: size.height * 0.48), color: .systemGreen, text: "정글 질주 성공!! +6", power: 2, angle: 0)
                }
                enterJunglePhase(.squat)
            }

        case .squat:
            // Descend vine smoothly to upper-mid screen height (y ~ 0.64)
            let targetVineY = size.height * 0.64 + sin(t * 2.5) * 6
            if let v = jungleVineNode {
                v.position.x = size.width * 0.5 + sin(t * 1.8) * 10
                v.position.y += (targetVineY - v.position.y) * min(1, dt * 3.5)
            }
            if let fb = jungleVineFallback {
                fb.position.y += (targetVineY - fb.position.y) * min(1, dt * 3.5)
            }
            jungleMomoSquat?.position = CGPoint(x: size.width * 0.18, y: size.height * 0.34 + sin(t * 5) * 5)

            var squatting = false
            for p in players {
                if p.metrics.isSquatting || p.head.y > 0.55 {
                    squatting = true
                }
            }
            if squatting {
                junglePhaseProgress = min(1.0, junglePhaseProgress + dt * 0.85)
            } else {
                junglePhaseProgress = max(0, junglePhaseProgress - dt * 0.25)
            }

            if junglePhaseProgress >= 1.0 || junglePhaseTimer <= 0 {
                if junglePhaseProgress >= 1.0 {
                    score += 8
                    onScore?(score)
                    SoundEngine.shared.playGoldenPop()
                    spawnBurst(at: CGPoint(x: size.width * 0.5, y: size.height * 0.45), color: .systemYellow, text: "덩굴 쏙 통과!! +8", power: 2, angle: 0)
                } else {
                    score += 2
                    onScore?(score)
                    SoundEngine.shared.playBounce()
                    spawnFloatingText("다음엔 쏙 숙여요! +2", at: CGPoint(x: size.width * 0.5, y: size.height * 0.48), color: .systemOrange, big: false)
                }
                enterJunglePhase(.jump)
            }

        case .jump:
            var remaining: [JungleStar] = []
            let totalStars = max(1, settings.players == 2 ? 5 : 4)
            for st in jungleStars {
                st.node.position.y = st.baseY + sin(t * 4.2 + st.seed) * 10
                st.node.zRotation = sin(t * 2.8 + st.seed) * 0.16

                var hit = false
                for p in players {
                    let pts = [p.leftHand, p.rightHand, p.head]
                    for pt in pts {
                        let sx = pt.x * size.width
                        let sy = (1.0 - pt.y) * size.height
                        if hypot(sx - st.node.position.x, sy - st.node.position.y) < st.radius * 1.55 * hMult {
                            hit = true
                            break
                        }
                    }
                    if hit { break }
                }

                if hit {
                    let pos = st.node.position
                    st.node.removeFromParent()
                    score += 5
                    onScore?(score)
                    SoundEngine.shared.playJumpStar()
                    spawnBurst(at: pos, color: .systemYellow, text: "점프 별 팡!! +5", power: 2, angle: -0.3)
                } else {
                    remaining.append(st)
                }
            }
            jungleStars = remaining
            let collected = totalStars - jungleStars.count
            junglePhaseProgress = CGFloat(collected) / CGFloat(totalStars)

            if jungleStars.isEmpty || junglePhaseTimer <= 0 {
                if jungleStars.isEmpty {
                    score += 5
                    onScore?(score)
                    SoundEngine.shared.playMilestone()
                    spawnBurst(at: CGPoint(x: size.width * 0.5, y: size.height * 0.60), color: .systemYellow, text: "별 올클리어!! +5", power: 2, angle: 0)
                }
                enterJunglePhase(.run)
            }
        }

        // Layout & update Bottom 3 Creamy Circular Move Badges (pose_run, pose_squat, pose_jump sprites!):
        // Bottom-left 2 badges (run & squat) + Bottom-right 1 badge (jump)
        let activePulse = 1.06 + 0.03 * sin(t * 8)
        if let bRun = jungleBadges[.run] {
            bRun.container.position = CGPoint(x: 64, y: 72)
            updateCircularMoveBadge(bRun, progress: junglePhase == .run ? junglePhaseProgress : 0, active: junglePhase == .run, pulse: activePulse)
        }
        if let bSquat = jungleBadges[.squat] {
            bSquat.container.position = CGPoint(x: 158, y: 72)
            updateCircularMoveBadge(bSquat, progress: junglePhase == .squat ? junglePhaseProgress : 0, active: junglePhase == .squat, pulse: activePulse)
        }
        if let bJump = jungleBadges[.jump] {
            bJump.container.position = CGPoint(x: size.width - 70, y: 72)
            updateCircularMoveBadge(bJump, progress: junglePhase == .jump ? junglePhaseProgress : 0, active: junglePhase == .jump, pulse: activePulse)
        }
    }

    // MARK: - Game 6: Mole Hand-Foot High-Five (60s, 3 Upper Hand Holes + 3 Lower Foot/Crouch Holes)
    private func setupMoleGame() {
        let coords: [(Bool, CGPoint)] = [
            (true,  CGPoint(x: 0.22, y: 0.29)),
            (true,  CGPoint(x: 0.50, y: 0.27)),
            (true,  CGPoint(x: 0.78, y: 0.29)),
            (false, CGPoint(x: 0.22, y: 0.80)),
            (false, CGPoint(x: 0.50, y: 0.82)),
            (false, CGPoint(x: 0.78, y: 0.80)),
        ]
        let holeW: CGFloat = min(140, size.width * 0.165)
        let holeH: CGFloat = holeW * 0.38

        for (idx, (isUpper, norm)) in coords.enumerated() {
            let container = SKNode()
            container.zPosition = isUpper ? 14 : 18

            // Back burrow shadow
            let holeBack = SKShapeNode(ellipseOf: CGSize(width: holeW, height: holeH))
            holeBack.fillColor = isUpper
                ? UIColor(red: 0.25, green: 0.55, blue: 0.82, alpha: 0.58)
                : UIColor(red: 0.26, green: 0.18, blue: 0.10, alpha: 0.76)
            holeBack.strokeColor = isUpper
                ? UIColor.white.withAlphaComponent(0.92)
                : UIColor(red: 0.36, green: 0.78, blue: 0.38, alpha: 0.94)
            holeBack.lineWidth = 4
            container.addChild(holeBack)

            // Golden aura + 4 orbiting golden 5-pointed stars for golden mole (matching PixiJS L1345-L1350)
            let aura = SKShapeNode(circleOfRadius: holeW * 0.56)
            aura.fillColor = UIColor(red: 1.0, green: 0.83, blue: 0.23, alpha: 0.34) // #FFD43B
            aura.strokeColor = .clear
            aura.blendMode = .add
            aura.alpha = 0
            aura.position = CGPoint(x: 0, y: holeH * 0.8)
            container.addChild(aura)

            let goldOrbitNode = SKNode()
            goldOrbitNode.alpha = 0
            goldOrbitNode.zPosition = 4
            var goldOrbitStars: [SKShapeNode] = []
            let moleStarPath = makeStarPath(outerR: 10, innerR: 4.5)
            let moleStarCol = UIColor(red: 1.0, green: 0.91, blue: 0.40, alpha: 1.0) // #FFE866
            for k in 0..<4 {
                let a = CGFloat(k) * (.pi * 0.5)
                let star = SKShapeNode(path: moleStarPath)
                star.fillColor = moleStarCol
                star.strokeColor = .clear
                star.blendMode = .add
                star.position = CGPoint(x: cos(a) * holeW * 0.56, y: sin(a) * holeW * 0.49)
                goldOrbitNode.addChild(star)
                goldOrbitStars.append(star)
            }
            container.addChild(goldOrbitNode)

            // Cute mole sprite
            let mole = SKSpriteNode(texture: textures["mole_cute"])
            let mDim = holeW * 0.86
            mole.size = CGSize(width: mDim, height: mDim)
            mole.position = CGPoint(x: 0, y: -6)
            mole.alpha = 0
            mole.setScale(0.1)
            container.addChild(mole)

            // Front rim lip + hint icon (✋ upper, 👟 lower)
            let rim = SKShapeNode(ellipseOf: CGSize(width: holeW * 1.06, height: holeH * 0.56))
            rim.fillColor = isUpper
                ? UIColor(red: 0.88, green: 0.97, blue: 1.0, alpha: 0.90)
                : UIColor(red: 0.42, green: 0.82, blue: 0.40, alpha: 0.92)
            rim.strokeColor = .white
            rim.lineWidth = 2.5
            rim.position = CGPoint(x: 0, y: -holeH * 0.34)
            rim.zPosition = 5
            container.addChild(rim)

            let hint = SKLabelNode()
            hint.verticalAlignmentMode = .center
            hint.horizontalAlignmentMode = .center
            setStickerLabel(
                hint,
                text: isUpper ? "✋ 손!" : "👟 발·손!",
                fontSize: 13.5,
                strokeColor: isUpper ? UIColor(red: 0.01, green: 0.52, blue: 0.78, alpha: 1) : UIColor(red: 0.08, green: 0.45, blue: 0.22, alpha: 1),
                strokeWidth: 5.0
            )
            hint.position = rim.position
            hint.zPosition = 6
            container.addChild(hint)

            gameLayer.addChild(container)
            moleHoles.append(MoleHole(
                index: idx,
                isUpper: isUpper,
                normPos: norm,
                container: container,
                rimNode: rim,
                moleSprite: mole,
                goldAura: aura,
                goldOrbitNode: goldOrbitNode,
                goldOrbitStars: goldOrbitStars,
                state: .idle,
                popProgress: 0,
                stayTimer: 0,
                isGold: false,
                cooldown: 0.2
            ))
        }

        // Subtle glowing foot halos so players see foot kicks on lower mole holes!
        for i in 0..<4 {
            let fh = SKShapeNode(circleOfRadius: 20)
            fh.strokeColor = i < 2 ? UIColor(red: 0.36, green: 0.94, blue: 0.89, alpha: 0.9) : UIColor(red: 1.0, green: 0.58, blue: 0.42, alpha: 0.9)
            fh.fillColor = fh.strokeColor.withAlphaComponent(0.20)
            fh.lineWidth = 3.5
            fh.blendMode = .add
            fh.alpha = 0
            fxLayer.addChild(fh)
            footHaloNodes.append(fh)
        }
    }

    private func updateMoleGame(dt: CGFloat, players: [PlayerPose]) {
        let t = CGFloat(elapsed)
        let spd = settings.speed.speedMult
        let hMult = settings.speed.hitboxMult

        moleElapsed += dt
        onProgress?(min(10, Int((moleElapsed / moleDuration) * 10.0)), 10)

        if moleElapsed >= moleDuration {
            feverActive = false
            spawnConfetti()
            finishGame("두더지 하이파이브 60초 완료! ⭐ \(score)점 대성공!")
            return
        }

        // Fever wave at 40s!
        if !moleFeverTriggered && moleElapsed >= 40.0 {
            moleFeverTriggered = true
            feverActive = true
            SoundEngine.shared.playFeverStart()
            SoundEngine.shared.setBgmRate(1.14)
            onCallout?("🔥 두더지 피버 타임!! 모두 하이파이브!!", 3.0)
        }

        // Collect all hand points & foot/knee points in SpriteKit coords
        var handPts: [CGPoint] = []
        var lowerPts: [CGPoint] = []
        var footHaloIdx = 0
        for p in players.prefix(2) {
            let lh = CGPoint(x: p.leftHand.x * size.width, y: (1.0 - p.leftHand.y) * size.height)
            let rh = CGPoint(x: p.rightHand.x * size.width, y: (1.0 - p.rightHand.y) * size.height)
            handPts.append(lh)
            handPts.append(rh)
            lowerPts.append(lh)
            lowerPts.append(rh)

            let m = p.metrics
            let footPairs: [(CGPoint?, CGFloat)] = [(m.lAnkle, m.lAnkleConf), (m.rAnkle, m.rAnkleConf)]
            for (footOpt, fConf) in footPairs {
                let vis = smoothstep(edge0: 0.12, edge1: 0.48, x: fConf)
                if let fpt = footOpt, vis >= 0.02 {
                    let sk = CGPoint(x: fpt.x * size.width, y: (1.0 - fpt.y) * size.height)
                    if fConf >= 0.14 { lowerPts.append(sk) }
                    if footHaloIdx < footHaloNodes.count {
                        footHaloNodes[footHaloIdx].position = sk
                        footHaloNodes[footHaloIdx].alpha = 0.72 * vis
                        footHaloIdx += 1
                    }
                }
            }
            for (kneeOpt, kConf) in [(m.lKnee, m.lKneeConf), (m.rKnee, m.rKneeConf)] {
                if let kpt = kneeOpt, kConf >= 0.14 {
                    lowerPts.append(CGPoint(x: kpt.x * size.width, y: (1.0 - kpt.y) * size.height))
                }
            }
        }
        while footHaloIdx < footHaloNodes.count {
            footHaloNodes[footHaloIdx].alpha = 0
            footHaloIdx += 1
        }

        // Spawn moles smoothly
        moleSpawnTimer -= dt
        let activeCount = moleHoles.filter { $0.state != .idle }.count
        let maxActive = feverActive ? 4 : (settings.players == 2 ? 3 : 2)
        if moleSpawnTimer <= 0 && activeCount < maxActive {
            let idleIndices = moleHoles.indices.filter { moleHoles[$0].state == .idle && moleHoles[$0].cooldown <= 0 }
            if let pickIdx = idleIndices.randomElement() {
                let isGold = CGFloat.random(in: 0...1) < (feverActive ? 0.36 : 0.22)
                moleHoles[pickIdx].isGold = isGold
                moleHoles[pickIdx].state = .rising
                moleHoles[pickIdx].popProgress = 0
                moleHoles[pickIdx].stayTimer = (feverActive ? 1.85 : 2.55) / spd
                moleHoles[pickIdx].moleSprite.texture = textures[isGold ? "mole_gold" : "mole_cute"]
                moleHoles[pickIdx].moleSprite.colorBlendFactor = 0
                moleHoles[pickIdx].moleSprite.zRotation = 0
            }
            moleSpawnTimer = (feverActive ? 0.42 : 0.78) / spd
        }

        // Update each hole & detect hand/foot high-fives
        let hitRadius = min(size.width, size.height) * 0.115 * hMult
        for i in moleHoles.indices {
            let hx = moleHoles[i].normPos.x * size.width
            let hy = (1.0 - moleHoles[i].normPos.y) * size.height
            moleHoles[i].container.position = CGPoint(x: hx, y: hy)
            moleHoles[i].cooldown = max(0, moleHoles[i].cooldown - dt)

            switch moleHoles[i].state {
            case .idle:
                moleHoles[i].moleSprite.alpha = 0
                moleHoles[i].goldAura.alpha = 0
                moleHoles[i].goldOrbitNode.alpha = 0

            case .rising:
                moleHoles[i].popProgress = min(1.0, moleHoles[i].popProgress + dt * 5.2)
                if moleHoles[i].popProgress >= 1.0 {
                    moleHoles[i].state = .up
                }

            case .up:
                moleHoles[i].stayTimer -= dt
                if moleHoles[i].stayTimer <= 0 {
                    moleHoles[i].state = .falling
                }

            case .falling:
                moleHoles[i].popProgress = max(0, moleHoles[i].popProgress - dt * 4.0)
                if moleHoles[i].popProgress <= 0 {
                    moleHoles[i].state = .idle
                    moleHoles[i].cooldown = 0.55
                }

            case .bonked:
                moleHoles[i].popProgress = max(0, moleHoles[i].popProgress - dt * 6.5)
                if moleHoles[i].popProgress <= 0 {
                    moleHoles[i].state = .idle
                    moleHoles[i].cooldown = 0.45
                }
            }

            let p = moleHoles[i].popProgress
            if moleHoles[i].state != .idle {
                let bounce = sin(t * 7 + CGFloat(i)) * 4 * p
                let molePos = CGPoint(x: 0, y: -10 + p * 44 + bounce)
                moleHoles[i].moleSprite.alpha = min(1.0, p * 1.6)
                moleHoles[i].moleSprite.position = molePos
                if moleHoles[i].state == .bonked {
                    moleHoles[i].moleSprite.xScale = 1.28 * p
                    moleHoles[i].moleSprite.yScale = 0.62 * p
                } else {
                    moleHoles[i].moleSprite.xScale = 0.35 + 0.65 * p
                    moleHoles[i].moleSprite.yScale = 0.35 + 0.65 * p
                    moleHoles[i].moleSprite.zRotation = sin(t * 5 + CGFloat(i)) * 0.08
                }
                if moleHoles[i].isGold {
                    moleHoles[i].goldAura.position = molePos
                    moleHoles[i].goldAura.alpha = 0.90 * p
                    moleHoles[i].goldAura.setScale(0.90 + 0.16 * sin(t * 8))

                    moleHoles[i].goldOrbitNode.position = molePos
                    moleHoles[i].goldOrbitNode.alpha = 0.92 * p
                    let rx = moleHoles[i].moleSprite.size.width * 0.65
                    let ry = rx * 0.88
                    for (k, star) in moleHoles[i].goldOrbitStars.enumerated() {
                        let a = t * 3.4 + CGFloat(k) * (.pi * 0.5)
                        star.position = CGPoint(x: cos(a) * rx, y: sin(a) * ry)
                        star.zRotation = -a
                    }
                } else {
                    moleHoles[i].goldAura.alpha = 0
                    moleHoles[i].goldOrbitNode.alpha = 0
                }
            }

            // Check hits while rising or up!
            if (moleHoles[i].state == .rising || moleHoles[i].state == .up) && p > 0.35 {
                let targetPos = CGPoint(x: hx, y: hy + 34)
                let testers = moleHoles[i].isUpper ? handPts : lowerPts
                var hit = false
                for pt in testers {
                    if hypot(pt.x - targetPos.x, pt.y - targetPos.y) < hitRadius {
                        hit = true
                        break
                    }
                }
                if hit {
                    moleHoles[i].state = .bonked
                    registerCombo(at: targetPos)
                    let basePts = moleHoles[i].isGold ? 5 : 2
                    let comboBonus = combo >= 4 ? 1 : 0
                    let gained = basePts + comboBonus
                    score += gained
                    onScore?(score)
                    SoundEngine.shared.playMoleBonk(combo: combo, isGold: moleHoles[i].isGold)
                    let col: UIColor = moleHoles[i].isGold ? .systemYellow : (moleHoles[i].isUpper ? .systemCyan : .systemGreen)
                    let txt = moleHoles[i].isGold ? "황금 하이파이브!! +\(gained)" : (moleHoles[i].isUpper ? "짝! 하이파이브! +\(gained)" : "톡! 발 터치! +\(gained)")
                    spawnBurst(at: targetPos, color: col, text: txt, power: moleHoles[i].isGold ? 2 : 1, angle: 0)
                }
            }
        }
    }

    // MARK: - Game 7: Log Bridge Balance (60s, Wind Gusts + TorsoLean/WideArms + One-Leg Bonus + Stars)
    private func setupBalanceGame() {
        // 1) Sparkling semi-transparent blue stream along bottom
        let river = SKShapeNode(rectOf: CGSize(width: size.width + 40, height: size.height * 0.16))
        river.fillColor = UIColor(red: 0.20, green: 0.72, blue: 0.98, alpha: 0.34)
        river.strokeColor = UIColor.white.withAlphaComponent(0.65)
        river.lineWidth = 3
        river.zPosition = 2
        gameLayer.addChild(river)
        balanceRiverNode = river

        // 2) Tilting Log Bridge + Momo (& Popo in 2P) standing on top!
        let bridgeContainer = SKNode()
        bridgeContainer.zPosition = 16
        gameLayer.addChild(bridgeContainer)
        balanceBridgeNode = bridgeContainer

        let logW = min(560, size.width * 0.64)
        let logSprite: SKSpriteNode
        if let tex = textures["log_bridge"] {
            logSprite = SKSpriteNode(texture: tex)
            let aspect = tex.size().height / max(1, tex.size().width)
            logSprite.size = CGSize(width: logW, height: max(54, logW * aspect))
        } else {
            logSprite = SKSpriteNode(color: .clear, size: CGSize(width: logW, height: 54))
            let fb = SKShapeNode(rectOf: CGSize(width: logW, height: 42), cornerRadius: 21)
            fb.fillColor = UIColor(red: 0.62, green: 0.39, blue: 0.20, alpha: 0.96)
            fb.strokeColor = UIColor(red: 0.35, green: 0.20, blue: 0.08, alpha: 1)
            fb.lineWidth = 4
            logSprite.addChild(fb)
        }
        bridgeContainer.addChild(logSprite)
        balanceLogSprite = logSprite

        let charDim = min(size.width, size.height) * 0.28
        let momo = SKSpriteNode(texture: textures["momo"])
        momo.size = CGSize(width: charDim, height: charDim)
        momo.position = CGPoint(x: settings.players == 2 ? -charDim * 0.44 : 0, y: charDim * 0.48)
        momo.zPosition = 4
        bridgeContainer.addChild(momo)
        balanceMomo = momo

        if settings.players == 2 {
            let popo = SKSpriteNode(texture: textures["popo"])
            popo.size = CGSize(width: charDim * 0.95, height: charDim * 0.95)
            popo.position = CGPoint(x: charDim * 0.44, y: charDim * 0.48)
            popo.zPosition = 4
            bridgeContainer.addChild(popo)
            balancePopo = popo
        }

        // 3) Live Green/Red Balance Gauge
        let gaugeW: CGFloat = min(300, size.width * 0.38)
        let gBg = SKShapeNode(rectOf: CGSize(width: gaugeW, height: 22), cornerRadius: 11)
        gBg.fillColor = UIColor(red: 0.94, green: 0.26, blue: 0.30, alpha: 0.85) // Red danger outer edges
        gBg.strokeColor = .white
        gBg.lineWidth = 3.5
        gBg.zPosition = 26
        gameLayer.addChild(gBg)
        balanceGaugeBg = gBg

        let gSafe = SKShapeNode(rectOf: CGSize(width: gaugeW * 0.52, height: 16), cornerRadius: 8)
        gSafe.fillColor = UIColor(red: 0.16, green: 0.90, blue: 0.48, alpha: 0.95) // Green safe center zone!
        gSafe.strokeColor = .clear
        gSafe.zPosition = 27
        gameLayer.addChild(gSafe)
        balanceGaugeSafe = gSafe

        let needle = SKShapeNode(circleOfRadius: 13)
        needle.fillColor = .systemYellow
        needle.strokeColor = UIColor(red: 0.12, green: 0.23, blue: 0.37, alpha: 1)
        needle.lineWidth = 3.5
        needle.zPosition = 28
        gameLayer.addChild(needle)
        balanceGaugeNeedle = needle

        let stBg = SKShapeNode(rectOf: CGSize(width: 294, height: 32), cornerRadius: 16)
        stBg.fillColor = UIColor(red: 0.08, green: 0.14, blue: 0.24, alpha: 0.72)
        stBg.strokeColor = UIColor.white.withAlphaComponent(0.38)
        stBg.lineWidth = 1.8
        stBg.zPosition = 27
        gameLayer.addChild(stBg)
        balanceGaugeStatusBg = stBg

        let stLbl = SKLabelNode()
        stLbl.verticalAlignmentMode = .center
        stLbl.horizontalAlignmentMode = .center
        setStickerLabel(stLbl, text: "⚖️ 중심 완벽! 팔을 활짝!", fontSize: 16, strokeColor: UIColor(red: 0.08, green: 0.33, blue: 0.18, alpha: 1), strokeWidth: 5.0)
        stLbl.zPosition = 28
        gameLayer.addChild(stLbl)
        balanceGaugeStatusLbl = stLbl

        // 4) Cartoon Wind Gust Lines
        for _ in 0..<7 {
            let wl = SKShapeNode(rectOf: CGSize(width: 72, height: 5), cornerRadius: 2.5)
            wl.fillColor = UIColor.white.withAlphaComponent(0.75)
            wl.strokeColor = .clear
            wl.alpha = 0
            wl.zPosition = 22
            gameLayer.addChild(wl)
            balanceWindLines.append(wl)
        }

        // 5) One-Leg Balance Bonus Pill
        let olBox = SKNode()
        olBox.zPosition = 28
        olBox.isHidden = true
        let olPill = SKShapeNode(rectOf: CGSize(width: 216, height: 44), cornerRadius: 22)
        olPill.fillColor = UIColor(red: 0.96, green: 0.35, blue: 0.62, alpha: 0.94)
        olPill.strokeColor = .white
        olPill.lineWidth = 3
        olBox.addChild(olPill)

        let olRing = SKShapeNode()
        olRing.strokeColor = .systemYellow
        olRing.lineWidth = 5
        olRing.lineCap = .round
        olRing.position = CGPoint(x: -82, y: 0)
        olBox.addChild(olRing)
        balanceOneLegRing = olRing

        let olLbl = SKLabelNode()
        olLbl.verticalAlignmentMode = .center
        olLbl.horizontalAlignmentMode = .center
        setStickerLabel(olLbl, text: "🦩 한 발 균형! +10", fontSize: 17.5, strokeColor: UIColor(red: 0.51, green: 0.09, blue: 0.26, alpha: 1), strokeWidth: 5.5)
        olLbl.position = CGPoint(x: 12, y: 0)
        olBox.addChild(olLbl)
        balanceOneLegLbl = olLbl

        gameLayer.addChild(olBox)
        balanceOneLegContainer = olBox
    }

    private func spawnBalanceStar() {
        let fromLeft = Bool.random()
        let r = min(size.width, size.height) * 0.068
        let node: SKSpriteNode
        if let tex = textures["star_3d"] {
            node = SKSpriteNode(texture: tex)
            node.size = CGSize(width: r * 2.1, height: r * 2.1)
        } else {
            node = SKSpriteNode(color: .clear, size: CGSize(width: r * 2, height: r * 2))
            let sh = SKShapeNode(path: makeStarPath(points: 5, outerRadius: r, innerRadius: r * 0.48))
            sh.fillColor = .systemYellow
            sh.strokeColor = UIColor(red: 0.12, green: 0.23, blue: 0.37, alpha: 1)
            sh.lineWidth = 3
            node.addChild(sh)
        }
        let baseY = size.height * CGFloat.random(in: 0.46...0.74)
        node.position = CGPoint(x: fromLeft ? -r : size.width + r, y: baseY)
        node.zPosition = 20
        gameLayer.addChild(node)
        let speed = size.width * CGFloat.random(in: 0.13...0.19) * settings.speed.speedMult
        balanceStars.append(BalanceStar(
            node: node,
            vx: fromLeft ? speed : -speed,
            baseY: baseY,
            radius: r,
            seed: CGFloat.random(in: 0...6.28)
        ))
    }

    private func updateBalanceGame(dt: CGFloat, players: [PlayerPose]) {
        let t = CGFloat(elapsed)
        let hMult = settings.speed.hitboxMult

        balanceElapsed += dt
        onProgress?(min(10, Int((balanceElapsed / balanceDuration) * 10.0)), 10)

        if balanceElapsed >= balanceDuration {
            for st in balanceStars { st.node.removeFromParent() }
            balanceStars.removeAll()
            spawnConfetti()
            finishGame("외나무다리 균형잡기 60초 완주! ⭐ \(score)점 대성공!")
            return
        }

        // 1) Periodic Wind Gusts
        if windTimer > 0 {
            windTimer -= dt
            if windTimer <= 0 {
                windForce = 0
                windNextTimer = CGFloat.random(in: 3.0...4.8)
            }
        } else {
            windNextTimer -= dt
            if windNextTimer <= 0 {
                let dir: CGFloat = Bool.random() ? 1.0 : -1.0
                windForce = dir * (0.48 + min(0.24, balanceElapsed * 0.004))
                windTimer = CGFloat.random(in: 3.4...4.6)
                SoundEngine.shared.playWindWhoosh()
                let msg = dir > 0
                    ? "🌬️ 왼쪽 바람! 왼쪽으로 몸을 기울여 균형!"
                    : "🌬️ 오른쪽 바람! 오른쪽으로 몸을 기울여 균형!"
                onCallout?(msg, 2.6)
            }
        }

        // 2) Player Torso Lean + Wide Arms Stabilization
        var leanSum: CGFloat = 0
        var wideArmsCount = 0
        var oneLegDetected = false
        for p in players {
            let m = p.metrics
            let shTilt = (m.rShoulder.y - m.lShoulder.y) * 1.8
            leanSum += (m.torsoLeanSigned * 1.4 + shTilt)
            if m.wristSpan > m.shoulderW * 1.4 {
                wideArmsCount += 1
            }
            if m.footLift > m.torsoH * 0.16 {
                oneLegDetected = true
            }
        }
        let avgLean = players.isEmpty ? 0 : (leanSum / CGFloat(players.count))
        let hasWideArms = wideArmsCount > 0

        // Bridge physics: gentle wave + wind torque + player counter-lean + strong spring damping when arms wide!
        let gentleSway = sin(t * 1.7) * 0.14
        let counterTorque = avgLean * 1.25
        let damping: CGFloat = hasWideArms ? 3.8 : 2.1
        let selfCenter: CGFloat = hasWideArms ? 1.85 : 0.95
        let accel = (windForce + gentleSway + counterTorque) - bridgeAngle * selfCenter - bridgeAngVel * damping
        bridgeAngVel += accel * dt
        bridgeAngle = max(-0.38, min(0.38, bridgeAngle + bridgeAngVel * dt))

        // Render river & tilting bridge + Momo/Popo
        balanceRiverNode?.position = CGPoint(x: size.width * 0.5, y: size.height * 0.07 + sin(t * 2.5) * 3)
        balanceBridgeNode?.position = CGPoint(x: size.width * 0.5, y: size.height * 0.25)
        // SpriteKit zRotation: negative tilts right side down, positive tilts left side down
        balanceBridgeNode?.zRotation = -bridgeAngle
        let slideX = bridgeAngle * 110
        let charDim = min(size.width, size.height) * 0.28
        if settings.players == 2 {
            balanceMomo?.position = CGPoint(x: -charDim * 0.44 + slideX, y: charDim * 0.48 + abs(sin(t * 4.5)) * 5)
            balancePopo?.position = CGPoint(x: charDim * 0.44 + slideX, y: charDim * 0.48 + abs(cos(t * 4.5)) * 5)
        } else {
            balanceMomo?.position = CGPoint(x: slideX, y: charDim * 0.48 + abs(sin(t * 4.5)) * 5)
        }

        // Animated wind lines
        for (idx, wl) in balanceWindLines.enumerated() {
            if abs(windForce) > 0.05 {
                wl.alpha = 0.65
                let speed: CGFloat = (windForce > 0 ? 1 : -1) * (420 + CGFloat(idx % 3) * 90)
                if wl.position.x == 0 && wl.position.y == 0 {
                    wl.position = CGPoint(x: CGFloat.random(in: 0...size.width), y: size.height * (0.28 + CGFloat(idx) * 0.08))
                }
                wl.position.x += speed * dt
                if wl.position.x > size.width + 60 { wl.position.x = -60 }
                if wl.position.x < -60 { wl.position.x = size.width + 60 }
            } else {
                wl.alpha = max(0, wl.alpha - dt * 3.0)
            }
        }

        // 3) Live Green/Red Balance Gauge
        let gaugeW: CGFloat = min(300, size.width * 0.38)
        let gaugePos = CGPoint(x: size.width * 0.5, y: size.height - 86)
        balanceGaugeBg?.position = gaugePos
        balanceGaugeSafe?.position = gaugePos
        let normTilt = max(-1.0, min(1.0, bridgeAngle / 0.36))
        balanceGaugeNeedle?.position = CGPoint(x: gaugePos.x + normTilt * (gaugeW * 0.46), y: gaugePos.y)
        let isSafe = abs(bridgeAngle) < 0.20
        balanceGaugeNeedle?.fillColor = isSafe ? UIColor(red: 0.16, green: 0.96, blue: 0.52, alpha: 1) : .systemYellow
        balanceGaugeStatusBg?.position = CGPoint(x: gaugePos.x, y: gaugePos.y - 30)
        balanceGaugeStatusLbl?.position = CGPoint(x: gaugePos.x, y: gaugePos.y - 30)
        let statusText = isSafe
            ? (hasWideArms ? "✨ 비행기 팔 최고! 완벽 균형!" : "⚖️ 중심 완벽! 계속 유지해요!")
            : "⚡ 흔들흔들! 반대쪽으로 기울여요!"
        let statusStroke = isSafe
            ? UIColor(red: 0.08, green: 0.33, blue: 0.18, alpha: 1)
            : UIColor(red: 0.60, green: 0.20, blue: 0.04, alpha: 1)
        setStickerLabel(balanceGaugeStatusLbl, text: statusText, fontSize: 16, strokeColor: statusStroke, strokeWidth: 5.0, cacheKey: "\(statusText)|\(isSafe)")

        // Continuous safe-zone scoring & gentle wobble feedback
        balanceWobbleCooldown = max(0, balanceWobbleCooldown - dt)
        if isSafe {
            balancePointTick += dt * (hasWideArms ? 1.35 : 1.0)
            if balancePointTick >= 0.85 {
                balancePointTick = 0
                score += 1
                onScore?(score)
                spawnFloatingText("균형 +1", at: CGPoint(x: size.width * 0.5 + slideX, y: size.height * 0.46), color: .systemGreen, big: false)
            }
        } else if abs(bridgeAngle) >= 0.34 && balanceWobbleCooldown <= 0 {
            balanceWobbleCooldown = 1.6
            SoundEngine.shared.playBounce()
            bridgeAngVel *= -0.35
            bridgeAngle *= 0.65
            spawnFloatingText("앗! 흔들흔들!", at: CGPoint(x: size.width * 0.5, y: size.height * 0.45), color: .systemOrange, big: false)
        }

        // 4) Periodic One-Leg Balance Bonus Challenge ("🦩 한 발 들고 균형!")
        if !oneLegActive {
            oneLegNextTimer -= dt
            if oneLegNextTimer <= 0 && balanceElapsed < balanceDuration - 7 {
                oneLegActive = true
                oneLegTimer = 6.0
                oneLegHold = 0
                balanceOneLegContainer?.isHidden = false
                onCallout?("🦩 보너스! 한 발 들고 1.5초 균형 잡기!!", 2.6)
            }
        } else {
            oneLegTimer -= dt
            balanceOneLegContainer?.position = CGPoint(x: size.width * 0.5, y: size.height - 144)
            let canCredit = oneLegDetected || (!(cameraManager?.isUsingCamera ?? false) && isSafe)
            if canCredit && isSafe {
                oneLegHold = min(1.5, oneLegHold + dt)
            } else {
                oneLegHold = max(0, oneLegHold - dt * 0.4)
            }
            let rRatio = oneLegHold / 1.5
            let arc = CGMutablePath()
            if rRatio > 0.02 {
                arc.addArc(center: .zero, radius: 13, startAngle: .pi / 2, endAngle: .pi / 2 - (.pi * 2 * rRatio), clockwise: true)
            }
            balanceOneLegRing?.path = arc

            if oneLegHold >= 1.5 {
                oneLegActive = false
                oneLegNextTimer = 14.0
                balanceOneLegContainer?.isHidden = true
                score += 10
                onScore?(score)
                SoundEngine.shared.playGoldenPop()
                spawnBurst(at: CGPoint(x: size.width * 0.5, y: size.height * 0.54), color: .systemPink, text: "🦩 한 발 균형 성공!! +10", power: 2, angle: 0)
            } else if oneLegTimer <= 0 {
                oneLegActive = false
                oneLegNextTimer = 13.0
                balanceOneLegContainer?.isHidden = true
            }
        }

        // 5) Floating Collectible 3D Stars
        balanceStarSpawnTimer -= dt
        if balanceStarSpawnTimer <= 0 && balanceStars.count < 3 {
            spawnBalanceStar()
            balanceStarSpawnTimer = CGFloat.random(in: 2.2...3.4)
        }
        var keptStars: [BalanceStar] = []
        for st in balanceStars {
            st.node.position.x += st.vx * dt
            st.node.position.y = st.baseY + sin(t * 3.5 + st.seed) * 14
            st.node.zRotation += 1.4 * dt

            var caught = false
            for p in players {
                for pt in [p.leftHand, p.rightHand] {
                    let sx = pt.x * size.width
                    let sy = (1.0 - pt.y) * size.height
                    if hypot(sx - st.node.position.x, sy - st.node.position.y) < st.radius * 1.55 * hMult {
                        caught = true
                        break
                    }
                }
                if caught { break }
            }
            if caught {
                let pos = st.node.position
                st.node.removeFromParent()
                score += 5
                onScore?(score)
                SoundEngine.shared.playJumpStar()
                spawnBurst(at: pos, color: .systemYellow, text: "균형 별 캐치!! +5", power: 2, angle: 0)
            } else if st.node.position.x > -st.radius * 2.5 && st.node.position.x < size.width + st.radius * 2.5 {
                keptStars.append(st)
            } else {
                st.node.removeFromParent()
            }
        }
        balanceStars = keptStars
    }

    // MARK: - Dopamine VFX & Jua Sticker Typography Helpers
    private func setStickerLabel(
        _ label: SKLabelNode?,
        text: String,
        fontSize: CGFloat,
        strokeColor: UIColor,
        strokeWidth: CGFloat = 6.5,
        fillColor: UIColor = .white,
        shadowAlpha: CGFloat = 0.28,
        cacheKey: String? = nil
    ) {
        guard let label else { return }
        let key = cacheKey ?? "\(text)|\(Int(fontSize * 10))"
        if label.name == key { return }
        label.name = key
        label.attributedText = AppFont.stickerAttributedText(
            text,
            fontSize: fontSize,
            strokeColor: strokeColor,
            strokeWidth: strokeWidth,
            fillColor: fillColor,
            shadowAlpha: shadowAlpha
        )
    }

    private func hideTrailRig(slot: Int) {
        guard slot >= 0 && slot < trailRigs.count else { return }
        for band in trailRigs[slot].bands {
            for seg in band.segments where !seg.isHidden {
                seg.isHidden = true
                seg.path = nil
                seg.alpha = 0
            }
        }
    }

    private func hideHandVfx(slot: Int) {
        if slot >= 0 && slot < haloRigs.count {
            let rig = haloRigs[slot]
            rig.container.isHidden = true
            rig.outerGlow.alpha = 0
            rig.midRing.alpha = 0
            rig.innerCore.alpha = 0
        }
        hideTrailRig(slot: slot)
    }

    private func updateVfxPhysics(dt: CGFloat) {
        let t = CGFloat(elapsed)

        // 1) Parabolic 5-Pointed Star & Juicy Droplet Burst Particles (gravity 320 pt/s², matching games.js L594-L600)
        if !burstParticles.isEmpty {
            var keptParticles: [BurstParticle] = []
            keptParticles.reserveCapacity(burstParticles.count)
            for var pt in burstParticles {
                pt.life -= dt
                if pt.life <= 0 {
                    pt.node.removeFromParent()
                    continue
                }
                pt.node.position.x += pt.vx * dt
                pt.node.position.y += pt.vy * dt
                pt.vy -= 320.0 * dt
                if pt.isStar {
                    pt.node.zRotation += pt.vrot * dt
                }
                let a = max(0, pt.life / pt.maxLife)
                pt.node.setScale(max(0.05, pt.baseScale * a))
                pt.node.alpha = pt.isStar ? a : (a * 0.90)
                keptParticles.append(pt)
            }
            burstParticles = keptParticles
        }

        // 2) Balloon Soap Bubbles with Sinusoidal Horizontal Drift (matching games.js L577-L583)
        if !activeBubbles.isEmpty {
            var keptBubbles: [ActiveBubble] = []
            keptBubbles.reserveCapacity(activeBubbles.count)
            for var bb in activeBubbles {
                bb.life -= dt
                if bb.life <= 0 {
                    bb.node.removeFromParent()
                    continue
                }
                bb.node.position.x += (bb.vx + sin(t * 6.0 + bb.seed) * 28.0) * dt
                bb.node.position.y += bb.vy * dt
                bb.vx *= max(0, 1.0 - 1.8 * dt)
                bb.node.alpha = max(0, min(1, bb.life / 0.6))
                keptBubbles.append(bb)
            }
            activeBubbles = keptBubbles
        }

        // 3) Sliced 3D Fruit Halves True Parabolic Gravity Arc (gravity 600 pt/s², matching games.js L585-L592)
        if !slicedHalves.isEmpty {
            var keptHalves: [SlicedHalf] = []
            keptHalves.reserveCapacity(slicedHalves.count)
            for var hf in slicedHalves {
                hf.life -= dt
                if hf.life <= 0 {
                    hf.node.removeFromParent()
                    continue
                }
                hf.node.position.x += hf.vx * dt
                hf.node.position.y += hf.vy * dt
                hf.vy -= 600.0 * dt
                hf.node.zRotation += hf.vrot * dt
                hf.node.alpha = max(0, min(1, hf.life / hf.maxLife))
                keptHalves.append(hf)
            }
            slicedHalves = keptHalves
        }
    }

    private func registerCombo(at pos: CGPoint) {
        combo += 1
        comboTimer = 1.6
        if combo >= 3 && combo % 2 == 1 {
            let label = combo >= 11 ? "\(combo) GODLIKE!!!" : combo >= 7 ? "\(combo) FEVER!!!" : combo >= 5 ? "\(combo) SUPER!!" : "\(combo) COMBO!"
            let comboColor = UIColor(red: 1.0, green: 0.42, blue: 0.0, alpha: 1.0) // #FF6B00
            spawnFloatingText(label, at: CGPoint(x: pos.x, y: min(size.height - 80, pos.y + 56)), color: comboColor, big: true)
        }
    }

    private func spawnSplatter(at pos: CGPoint, color: UIColor, scale: CGFloat) {
        let group = SKNode()
        group.position = pos
        for _ in 0..<7 {
            let r = CGFloat.random(in: 7...19) * scale
            let blob = SKShapeNode(circleOfRadius: r)
            blob.fillColor = color.withAlphaComponent(0.38)
            blob.strokeColor = .clear
            blob.position = CGPoint(x: CGFloat.random(in: -44...44) * scale, y: CGFloat.random(in: -44...44) * scale)
            group.addChild(blob)
        }
        splatLayer.addChild(group)
        group.run(.sequence([.group([.moveBy(x: 0, y: -22, duration: 1.5), .fadeOut(withDuration: 1.5)]), .removeFromParent()]))
    }

    private func spawnSlicedHalves(kind: String, at pos: CGPoint, radius: CGFloat, angle: CGFloat, slashVx: CGFloat, slashVy: CGFloat) {
        let nx = -sin(angle)
        let ny = cos(angle)
        let splitSpd = 215.0 + CGFloat.random(in: 0...75)
        let pieces: [(String, CGFloat, CGFloat, CGFloat)] = [
            ("\(kind)_left",  -1, 185, -5.4),
            ("\(kind)_right",  1, 175,  5.6),
        ]
        for (texKey, dir, upKick, vrot) in pieces {
            guard let tex = textures[texKey] else { continue }
            let sp = SKSpriteNode(texture: tex)
            sp.size = CGSize(width: radius * 2.2, height: radius * 2.2)
            sp.position = CGPoint(x: pos.x + dir * nx * radius * 0.22, y: pos.y + dir * ny * radius * 0.22)
            sp.zRotation = angle * 0.35
            sp.zPosition = 25
            gameLayer.addChild(sp)

            if slicedHalves.count >= 40, let oldest = slicedHalves.first {
                oldest.node.removeFromParent()
                slicedHalves.removeFirst()
            }
            let vx = dir * nx * splitSpd + slashVx * 0.14
            let vy = dir * ny * splitSpd * 0.55 + upKick + slashVy * 0.08
            slicedHalves.append(SlicedHalf(
                node: sp,
                vx: vx,
                vy: vy,
                vrot: vrot,
                life: 0.92,
                maxLife: 0.92
            ))
        }
    }

    private func spawnBurst(at pos: CGPoint, color: UIColor, text: String, power: Int, angle: CGFloat) {
        let maxR: CGFloat = power == 3 ? 280 : (power == 2 ? 175 : 125)
        let flashDur: TimeInterval = 0.26 + TimeInterval(power) * 0.08

        // 1) Crisp white diagonal slash flash beam (matching PixiJS L1588-L1594)
        let beam = SKShapeNode(rectOf: CGSize(width: maxR * 1.6, height: 14), cornerRadius: 7)
        beam.fillColor = .white
        beam.strokeColor = .clear
        beam.blendMode = .add
        beam.position = pos
        beam.zRotation = angle
        beam.zPosition = 46
        fxLayer.addChild(beam)
        beam.run(.sequence([
            .group([
                .scaleX(to: 1.62, y: 0.15, duration: flashDur),
                .fadeOut(withDuration: flashDur),
            ]),
            .removeFromParent(),
        ]))

        // 2) Expanding colored shockwave ring (matching PixiJS L1586)
        let ring = SKShapeNode(circleOfRadius: 24)
        ring.fillColor = .clear
        ring.strokeColor = color
        ring.lineWidth = 8
        ring.blendMode = .add
        ring.position = pos
        ring.zPosition = 45
        fxLayer.addChild(ring)
        ring.run(.sequence([
            .group([
                .scale(to: (24.0 + maxR) / 24.0, duration: flashDur),
                .fadeOut(withDuration: flashDur),
            ]),
            .removeFromParent(),
        ]))

        // 3) 18 / 28 / 42 Mixed Golden 5-Pointed Stars & Colored Juicy Droplets with Real Parabolic Gravity!
        let count = power == 3 ? 42 : (power == 2 ? 28 : 18)
        let goldStarColor = UIColor(red: 1.0, green: 0.863, blue: 0.302, alpha: 1.0) // #FFDC4D
        let maxLife: CGFloat = 0.72 + CGFloat(power) * 0.16
        for i in 0..<count {
            let isStar = (i % 2 == 0)
            let a = (CGFloat.pi * 2.0 * CGFloat(i)) / CGFloat(count) + CGFloat.random(in: 0...0.25)
            let spd = (140.0 + CGFloat(power) * 65.0) + CGFloat.random(in: 0...(200.0 + CGFloat(power) * 70.0))
            let pSize = (8.0 + CGFloat(power) * 3.0) + CGFloat.random(in: 0...8.0)
            let baseScale = pSize / 10.0

            let pNode = SKShapeNode(path: isStar ? unitStarPath : unitDropletPath)
            pNode.fillColor = isStar ? goldStarColor : color
            pNode.strokeColor = .clear
            pNode.blendMode = .add
            pNode.position = pos
            pNode.setScale(baseScale)
            pNode.zPosition = 45
            fxLayer.addChild(pNode)

            if burstParticles.count >= 200, let oldest = burstParticles.first {
                oldest.node.removeFromParent()
                burstParticles.removeFirst()
            }
            burstParticles.append(BurstParticle(
                node: pNode,
                vx: cos(a) * spd,
                vy: sin(a) * spd + 65.0,
                vrot: isStar ? CGFloat.random(in: -6.0...6.0) : 0,
                life: maxLife,
                maxLife: maxLife,
                baseScale: baseScale,
                isStar: isStar
            ))
        }

        spawnFloatingText(text, at: CGPoint(x: pos.x, y: pos.y + 18), color: color, big: power >= 2)
        screenShake = max(screenShake, power == 3 ? 1.35 : power == 2 ? 0.75 : 0.45)

        if power >= 2 {
            flashNode.size = size
            flashNode.color = power == 3 ? .white : UIColor(red: 1.0, green: 0.91, blue: 0.46, alpha: 1.0)
            flashNode.alpha = power == 3 ? 0.55 : 0.28
            flashNode.removeAllActions()
            flashNode.run(.fadeOut(withDuration: 0.32))
        }
    }

    private func spawnFloatingText(_ text: String, at pos: CGPoint, color: UIColor, big: Bool) {
        guard !text.isEmpty else { return }
        let lbl = SKLabelNode()
        lbl.verticalAlignmentMode = .center
        lbl.horizontalAlignmentMode = .center
        lbl.attributedText = AppFont.stickerAttributedText(
            text,
            fontSize: big ? 42 : 30,
            strokeColor: color,
            strokeWidth: big ? 8.0 : 7.0,
            fillColor: .white,
            shadowAlpha: 0.28
        )
        lbl.position = pos
        lbl.zPosition = 50
        lbl.setScale(0.86)
        fxLayer.addChild(lbl)
        lbl.run(.sequence([
            .group([
                .moveBy(x: 0, y: 74, duration: 0.85),
                .scale(to: big ? 1.24 : 1.12, duration: 0.24),
                .fadeOut(withDuration: 0.85),
            ]),
            .removeFromParent(),
        ]))
    }

    private func spawnConfetti() {
        let cols: [UIColor] = [.systemPink, .systemYellow, .systemTeal, .systemBlue, .systemPurple]
        for i in 0..<100 {
            let c = SKShapeNode(rectOf: CGSize(width: 12, height: 8), cornerRadius: 2)
            c.fillColor = cols[i % cols.count]
            c.strokeColor = .clear
            c.position = CGPoint(x: CGFloat.random(in: 20...(size.width - 20)), y: size.height + CGFloat.random(in: 10...260))
            fxLayer.addChild(c)
            let dur = TimeInterval.random(in: 1.4...2.4)
            c.run(.sequence([
                .group([
                    .moveBy(x: CGFloat.random(in: -90...90), y: -(size.height + 260), duration: dur),
                    .rotate(byAngle: CGFloat.random(in: -6...6), duration: dur),
                ]),
                .removeFromParent(),
            ]))
        }
    }

    private func animateClubOutro(dt: CGFloat) {
        let t = CGFloat(elapsed)
        let beatHz: CGFloat = 128.0 / 60.0
        let beatPulse: CGFloat = pow(max(0, cos(t * .pi * beatHz)), 4)
        let beatIdx = Int(t * beatHz)
        let baseR = min(size.width, size.height) * 0.165
        let lineup: [(String, CGFloat, CGFloat, CGFloat, Int, UIColor)] = [
            ("momo", 0.24, 0.45, 0.92, 1, .systemCyan),
            ("dino", 0.50, 0.49, 1.00, 0, .systemPink),
            ("popo", 0.76, 0.45, 0.92, 1, .systemYellow),
        ]
        for (id, nx, ny, scaleMul, ph, col) in lineup {
            guard let sp = dancerNodes[id], let ring = dancerRings[id] else { continue }
            sp.isHidden = false
            ring.isHidden = false
            let cx = size.width * nx
            let cy = size.height * ny
            let r = baseR * scaleMul
            let poseKey = (beatIdx + ph) % 2 == 0 ? "\(id)_dance1" : "\(id)_dance2"
            if let tex = textures[poseKey] { sp.texture = tex }
            sp.size = CGSize(width: r * 2.25, height: r * 2.25)
            sp.position = CGPoint(x: cx, y: cy + beatPulse * 18)
            sp.zRotation = sin(t * beatHz * .pi + CGFloat(ph) * 1.5) * 0.11
            ring.position = CGPoint(x: cx, y: cy)
            ring.strokeColor = col
            ring.setScale(scaleMul * (1.0 + beatPulse * 0.12))
        }
        discoBallNode?.zRotation = t * 1.15
    }

    private func finishGame(_ summary: String) {
        guard !isFinished else { return }
        isFinished = true
        feverActive = false

        // 1) 부드러운 BGM 페이드아웃 + 황금 피날레 플래시 + 축하 콜아웃!
        SoundEngine.shared.fadeOutBgm(duration: 1.1)
        SoundEngine.shared.playMilestone()
        flashNode.size = size
        flashNode.color = .systemYellow
        flashNode.alpha = 0.48
        flashNode.removeAllActions()
        flashNode.run(.fadeOut(withDuration: 0.45))
        onCallout?("🎉 피니시!! 대성공!! 🎉", 2.0)

        // 2) 게임별 피날레 마무리 모션!
        if gameType == .fruit && !activeFruits.isEmpty {
            for f in activeFruits {
                let pos = f.node.position
                f.node.removeFromParent()
                spawnSplatter(at: pos, color: f.color, scale: 1.15)
                spawnSlicedHalves(kind: f.kind, at: pos, radius: f.radius, angle: -0.4, slashVx: 0, slashVy: 0)
                spawnBurst(at: pos, color: .systemYellow, text: "팡!", power: 1, angle: -0.4)
            }
            activeFruits.removeAll()
        } else if gameType == .freeze {
            isFreezePhase = false
            isWiggling = false
            freezeProgBg?.isHidden = true
            freezeProgFill?.isHidden = true
            freezeProgLabel?.isHidden = true
            freezeMeterBg?.isHidden = true
            freezeMeterFill?.isHidden = true
            iceSpotlight?.alpha = 0
        }

        // 3) 1.85초간 생생한 피날레 축하 모션 후 통합 결과 팝업 부드럽게 등장!
        finishWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isFinished else { return }
            SoundEngine.shared.playFanfare()
            self.onFinish?(summary)
        }
        finishWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.85, execute: work)
    }
}
