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
    private var handTrails: [[CGPoint]] = [[], [], [], []]

    private let worldNode = SKNode()
    private let splatLayer = SKNode()
    private let trailLayer = SKNode()
    private let gameLayer = SKNode()
    private let fxLayer = SKNode()
    private let feverBorder = SKShapeNode()
    private let flashNode = SKSpriteNode(color: .white, size: .zero)

    private var haloNodes: [SKShapeNode] = []
    private var trailNodes: [SKShapeNode] = []

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
        BossConfig(triggerTime: 24, texKey: "fruit_pineapple", name: "거대 파인애플", hits2p: 10, hits1p: 7, bonus: 8, color: .systemYellow),
        BossConfig(triggerTime: 52, texKey: "fruit_melon", name: "거대 황금 멜론", hits2p: 12, hits1p: 9, bonus: 10, color: UIColor(red: 0.32, green: 0.85, blue: 0.65, alpha: 1)),
        BossConfig(triggerTime: 76, texKey: "watermelon", name: "거대 수박 왕", hits2p: 16, hits1p: 12, bonus: 15, color: .systemPink),
    ]

    private struct ActiveFruit {
        let node: SKSpriteNode
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

    // Freeze state
    private var freezeRoundsTotal = 6
    private var freezeRound = 0
    private var isFreezePhase = false
    private var freezeTimer: CGFloat = 4.2
    private var dinoNode: SKSpriteNode?
    private var dinoRing: SKShapeNode?

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
                let halo = SKShapeNode(circleOfRadius: 24)
                halo.strokeColor = i < 2 ? UIColor(red: 0.36, green: 0.94, blue: 0.89, alpha: 1) : UIColor(red: 1.0, green: 0.51, blue: 0.55, alpha: 1)
                halo.fillColor = halo.strokeColor.withAlphaComponent(0.2)
                halo.lineWidth = 3.5
                halo.blendMode = .add
                halo.alpha = 0
                fxLayer.addChild(halo)
                haloNodes.append(halo)

                let trail = SKShapeNode()
                trail.strokeColor = halo.strokeColor
                trail.lineWidth = 12
                trail.lineCap = .round
                trail.lineJoin = .round
                trail.blendMode = .add
                trailLayer.addChild(trail)
                trailNodes.append(trail)
            }
        }
        preloadTextures()
    }

    private func preloadTextures() {
        let baseFruits = [
            "fruit_strawberry", "fruit_apple", "fruit_orange", "fruit_banana",
            "fruit_grape", "fruit_peach", "fruit_pineapple", "fruit_melon", "watermelon"
        ]
        var names = ["balloon_red", "balloon_beach", "balloon_gold", "dino_sprite"]
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
        activeFruits.removeAll()
        balls.removeAll()
        bossNode = nil
        bossBarBg = nil
        bossBarFill = nil
        activeBossConfig = nil
        dinoNode = nil
        dinoRing = nil

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
            freezeRoundsTotal = 6
            freezeRound = 0
            isFreezePhase = false
            freezeTimer = 4.2
            setupDino()
            onProgress?(0, freezeRoundsTotal)
            onCallout?("신나게 흔들어 춤춰요!", 2.4)
            SoundEngine.shared.startBgm(track: "bgm_freeze", rate: 1.0)
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

        var hands: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, Bool, CGFloat, CGFloat)] = []
        for (idx, p) in players.prefix(2).enumerated() {
            let pts = [p.leftHand, p.rightHand]
            for (hIdx, norm) in pts.enumerated() {
                let slot = idx * 2 + hIdx
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
                if slashing { e = min(1, e + dt * 7.0) }
                else { e = max(0, e - dt * 2.8) }
                handEnergy[slot] = e
                prevHands[slot] = CGPoint(x: x, y: y)

                if e > 0.06 {
                    handTrails[slot].append(CGPoint(x: x, y: y))
                    if handTrails[slot].count > 12 { handTrails[slot].removeFirst() }
                } else if !handTrails[slot].isEmpty {
                    handTrails[slot].removeFirst()
                }

                let halo = haloNodes[slot]
                halo.position = CGPoint(x: x, y: y)
                halo.setScale(0.62 + 0.52 * e)
                halo.alpha = 0.22 + 0.72 * e

                let trailNode = trailNodes[slot]
                if handTrails[slot].count >= 2 && e > 0.08 {
                    let path = CGMutablePath()
                    path.move(to: handTrails[slot][0])
                    for pt in handTrails[slot].dropFirst() { path.addLine(to: pt) }
                    trailNode.path = path
                    trailNode.lineWidth = 6 + 10 * e
                    trailNode.alpha = 0.78 * e
                } else {
                    trailNode.path = nil
                }

                hands.append((prev.x, prev.y, x, y, vx, vy, slashing, ang, spd))
            }
        }
        for s in (players.count * 2)..<4 {
            haloNodes[s].alpha = 0
            trailNodes[s].path = nil
        }

        guard !isFinished else { return }

        switch gameType {
        case .fruit:
            updateFruitZen(dt: dt, hands: hands.map { ($0.0, $0.1, $0.2, $0.3, $0.4, $0.5, $0.6, $0.7) })
        case .balloon:
            updateBalloon(dt: dt, hands: hands.map { ($0.2, $0.3, $0.4, $0.5, $0.8) })
        case .freeze:
            updateFreeze(dt: dt, players: players)
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
        if zenElapsed >= zenDuration && (bossNode == nil || zenElapsed >= zenDuration + 6) {
            bossNode?.removeFromParent()
            bossBarBg?.removeFromParent()
            bossBarFill?.removeFromParent()
            bossNode = nil
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
        var rainbowTriggered = false
        var survivors: [ActiveFruit] = []

        for var f in activeFruits {
            f.hitCooldown = max(0, f.hitCooldown - dt)
            f.node.position.x += f.vx * dt
            f.node.position.y += f.vy * dt
            f.vy -= gravity * dt
            f.vx *= (1.0 - 0.08 * dt)
            f.node.zRotation += f.vrot * dt

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
                            SoundEngine.shared.playBossHit(f.maxHp - f.hp)
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
            let swayX = sin(CGFloat(elapsed) * 2.0) * (size.width * 0.04)
            let targetY = size.height * 0.52
            boss.position.x = size.width * 0.5 + swayX + (bossShake > 0 ? CGFloat.random(in: -14...14) * bossShake : 0)
            boss.position.y += (targetY - boss.position.y) * min(1, dt * 5.5)
            bossShake = max(0, bossShake - dt * 4.0)
            bossCooldown = max(0, bossCooldown - dt)

            let rage = CGFloat(bossHits) / CGFloat(max(1, bossMaxHits))
            let radius = min(size.width, size.height) * (0.20 + rage * 0.05)
            boss.size = CGSize(width: radius * 2.1, height: radius * 2.1)
            updateBossBar(remaining: max(0, 1.0 - rage))

            if bossCooldown <= 0 {
                for (px, py, hx, hy, vx, vy, isSlashing, ang) in hands {
                    guard isSlashing else { continue }
                    let d = distPointToSegment(cx: boss.position.x, cy: boss.position.y, x0: px, y0: py, x1: hx, y1: hy)
                    if d < radius * 1.4 * hMult {
                        bossHits += 1
                        bossShake = 1.15
                        bossCooldown = 0.16
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
                            bossBarBg?.removeFromParent()
                            bossBarFill?.removeFromParent()
                            bossNode = nil
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
        if special == "golden" {
            node.color = .systemYellow
            node.colorBlendFactor = 0.35
            let ring = SKShapeNode(circleOfRadius: radius * 1.15)
            ring.strokeColor = .systemYellow
            ring.lineWidth = 5
            ring.blendMode = .add
            node.addChild(ring)
        } else if special == "rainbow" {
            let ring = SKShapeNode(circleOfRadius: radius * 1.2)
            ring.strokeColor = .systemPurple
            ring.lineWidth = 6
            ring.blendMode = .add
            node.addChild(ring)
        } else if hp > 1 {
            let ring = SKShapeNode(circleOfRadius: radius * 1.08)
            ring.strokeColor = .white.withAlphaComponent(0.85)
            ring.lineWidth = 3.5
            node.addChild(ring)

            let dots = SKNode()
            dots.position = CGPoint(x: 0, y: radius + 12)
            node.addChild(dots)
            hpDotsNode = dots
            updateHpDots(node: dots, hp: hp, maxHp: hp)
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
            hpDotsNode: hpDotsNode,
            kind: pick.0,
            special: special,
            color: special == "golden" ? .systemYellow : special == "rainbow" ? .systemPurple : pick.1,
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
        SoundEngine.shared.setBgmRate(1.14)

        let radius = min(size.width, size.height) * 0.20
        let boss = SKSpriteNode(texture: textures[config.texKey])
        boss.size = CGSize(width: radius * 2.1, height: radius * 2.1)
        boss.position = CGPoint(x: size.width * 0.5, y: size.height + 150)
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

        if golden {
            let glow = SKShapeNode(circleOfRadius: r * 1.25)
            glow.fillColor = UIColor.systemYellow.withAlphaComponent(0.24)
            glow.strokeColor = .clear
            glow.blendMode = .add
            glow.zPosition = -1
            node.addChild(glow)
        }

        gameLayer.addChild(node)
        balls.append(ActiveBalloon(
            node: node,
            shadowNode: shadow,
            stringNode: strNode,
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
        // 2) 위로 둥실 떠오르는 무지개 비눗방울 파티클!
        let bCols: [UIColor] = [.systemCyan, .systemPink, .systemYellow, .systemPurple, color]
        let count = power >= 2 ? 12 : 8
        for i in 0..<count {
            let r = CGFloat.random(in: 7...15)
            let bubble = SKShapeNode(circleOfRadius: r)
            bubble.fillColor = bCols[i % bCols.count].withAlphaComponent(0.26)
            bubble.strokeColor = UIColor.white.withAlphaComponent(0.88)
            bubble.lineWidth = 2
            bubble.position = CGPoint(x: pos.x + CGFloat.random(in: -20...20), y: pos.y + CGFloat.random(in: -20...20))
            fxLayer.addChild(bubble)
            let dur = TimeInterval.random(in: 0.75...1.25)
            bubble.run(.sequence([
                .group([
                    .moveBy(x: CGFloat.random(in: -85...85), y: CGFloat.random(in: 90...210), duration: dur),
                    .fadeOut(withDuration: dur),
                ]),
                .removeFromParent(),
            ]))
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
                        SoundEngine.shared.playBalloonHit(combo: combo, isGolden: balls[i].golden)
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

    // MARK: - Game 3: 6-Round Escalating Freeze Dance
    private func setupDino() {
        let r = min(size.width, size.height) * 0.17
        let dino = SKSpriteNode(texture: textures["dino_sprite"])
        dino.size = CGSize(width: r * 2.05, height: r * 2.05)
        dino.position = CGPoint(x: size.width * 0.5, y: size.height * 0.54)
        gameLayer.addChild(dino)
        dinoNode = dino

        let ring = SKShapeNode(circleOfRadius: r * 1.12)
        ring.strokeColor = .systemGreen
        ring.lineWidth = 8
        ring.position = dino.position
        gameLayer.addChild(ring)
        dinoRing = ring
    }

    private func updateFreeze(dt: CGFloat, players: [PlayerPose]) {
        let rawMotion = players.reduce(CGFloat(0)) { $0 + $1.motion }
        emaMotion = 0.25 * rawMotion + 0.75 * emaMotion
        freezeTimer -= dt

        dinoNode?.position = CGPoint(x: size.width * 0.5, y: size.height * 0.54)
        dinoRing?.position = dinoNode?.position ?? .zero
        dinoNode?.zRotation = isFreezePhase ? 0 : sin(CGFloat(elapsed) * 8) * 0.09

        if !isFreezePhase {
            if freezeTimer <= 0 {
                isFreezePhase = true
                freezeTimer = 2.8
                dinoRing?.strokeColor = .systemBlue
                SoundEngine.shared.stopBgm()
                SoundEngine.shared.playFreezeCue()
                let isLast = freezeRound == freezeRoundsTotal - 1
                onCallout?(isLast ? "마지막! 만세하고 얼음!!" : "얼음!! 움직이지 마세요!", 2.5)
            }
        } else {
            if freezeTimer <= 0 {
                freezeRound += 1
                score += 5
                onScore?(score)
                onProgress?(freezeRound, freezeRoundsTotal)
                SoundEngine.shared.playGoldenPop()
                spawnBurst(at: CGPoint(x: size.width * 0.5, y: size.height * 0.54), color: .systemTeal, text: "완벽 성공! +5", power: 2, angle: 0)

                if freezeRound >= freezeRoundsTotal {
                    spawnConfetti()
                    finishGame("공룡 눈을 피해 6라운드 얼음 땡 대성공!")
                } else {
                    isFreezePhase = false
                    freezeTimer = max(3.0, 4.2 - CGFloat(freezeRound) * 0.2)
                    dinoRing?.strokeColor = .systemGreen
                    onCallout?("땡! 더 신나게 흔들어요!", 2.2)
                    SoundEngine.shared.startBgm(track: "bgm_freeze", rate: min(1.22, 1.0 + Float(freezeRound) * 0.045))
                }
            }
        }
    }

    // MARK: - Dopamine VFX Helpers
    private func registerCombo(at pos: CGPoint) {
        combo += 1
        comboTimer = 1.6
        if combo >= 3 && combo % 2 == 1 {
            let label = combo >= 11 ? "\(combo) GODLIKE!!!" : combo >= 7 ? "\(combo) FEVER!!!" : combo >= 5 ? "\(combo) SUPER!!" : "\(combo) COMBO!"
            spawnFloatingText(label, at: CGPoint(x: pos.x, y: min(size.height - 80, pos.y + 52)), color: .systemOrange, big: true)
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
        let pieces: [(String, CGFloat)] = [("\(kind)_left", -1), ("\(kind)_right", 1)]
        for (texKey, dir) in pieces {
            guard let tex = textures[texKey] else { continue }
            let sp = SKSpriteNode(texture: tex)
            sp.size = CGSize(width: radius * 2.15, height: radius * 2.15)
            sp.position = CGPoint(x: pos.x + dir * nx * radius * 0.2, y: pos.y + dir * ny * radius * 0.2)
            gameLayer.addChild(sp)
            let dx = dir * nx * 165 + slashVx * 0.08
            let dy = dir * ny * 120 + 90
            sp.run(.sequence([
                .group([
                    .moveBy(x: dx, y: dy - 260, duration: 0.78),
                    .rotate(byAngle: dir * 3.8, duration: 0.78),
                    .fadeOut(withDuration: 0.78),
                ]),
                .removeFromParent(),
            ]))
        }
    }

    private func spawnBurst(at pos: CGPoint, color: UIColor, text: String, power: Int, angle: CGFloat) {
        let len: CGFloat = power == 3 ? 250 : power == 2 ? 165 : 115
        let beam = SKShapeNode(rectOf: CGSize(width: len * 2, height: power == 3 ? 16 : 10), cornerRadius: 6)
        beam.fillColor = .white
        beam.strokeColor = color
        beam.lineWidth = 3
        beam.blendMode = .add
        beam.position = pos
        beam.zRotation = angle
        fxLayer.addChild(beam)
        beam.run(.sequence([.group([.scaleX(to: 1.4, y: 0.2, duration: 0.24), .fadeOut(withDuration: 0.24)]), .removeFromParent()]))

        let ring = SKShapeNode(circleOfRadius: 24)
        ring.strokeColor = color
        ring.lineWidth = 6
        ring.blendMode = .add
        ring.position = pos
        fxLayer.addChild(ring)
        ring.run(.sequence([.group([.scale(to: power == 3 ? 7.5 : 4.2, duration: 0.32), .fadeOut(withDuration: 0.32)]), .removeFromParent()]))

        let count = power == 3 ? 30 : power == 2 ? 20 : 12
        for i in 0..<count {
            let a = (CGFloat.pi * 2 * CGFloat(i)) / CGFloat(count) + CGFloat.random(in: -0.2...0.2)
            let dist = CGFloat.random(in: 80...(power == 3 ? 280 : 185))
            let dot = SKShapeNode(circleOfRadius: CGFloat.random(in: 5...11))
            dot.fillColor = i % 2 == 0 ? .systemYellow : color
            dot.strokeColor = .clear
            dot.blendMode = .add
            dot.position = pos
            fxLayer.addChild(dot)
            dot.run(.sequence([
                .group([
                    .moveBy(x: cos(a) * dist, y: sin(a) * dist - 40, duration: 0.58),
                    .scale(to: 0.1, duration: 0.58),
                    .fadeOut(withDuration: 0.58),
                ]),
                .removeFromParent(),
            ]))
        }

        spawnFloatingText(text, at: CGPoint(x: pos.x, y: pos.y + 18), color: color, big: power >= 2)
        screenShake = max(screenShake, power == 3 ? 1.35 : power == 2 ? 0.72 : 0.42)

        if power >= 2 {
            flashNode.size = size
            flashNode.color = power == 3 ? .white : .systemYellow
            flashNode.alpha = power == 3 ? 0.55 : 0.26
            flashNode.removeAllActions()
            flashNode.run(.fadeOut(withDuration: 0.32))
        }
    }

    private func spawnFloatingText(_ text: String, at pos: CGPoint, color: UIColor, big: Bool) {
        let lbl = SKLabelNode(text: text)
        lbl.fontName = "AppleSDGothicNeo-Heavy"
        lbl.fontSize = big ? 40 : 28
        lbl.fontColor = .white
        lbl.position = pos
        lbl.zPosition = 50
        fxLayer.addChild(lbl)
        lbl.run(.sequence([
            .group([
                .moveBy(x: 0, y: 65, duration: 0.72),
                .scale(to: big ? 1.25 : 1.08, duration: 0.22),
                .fadeOut(withDuration: 0.72),
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

    private func finishGame(_ summary: String) {
        guard !isFinished else { return }
        isFinished = true
        feverActive = false
        SoundEngine.shared.stopBgm()
        onCallout?("", 0)
        finishWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isFinished else { return }
            SoundEngine.shared.playFanfare()
            self.onFinish?(summary)
        }
        finishWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: work)
    }
}
