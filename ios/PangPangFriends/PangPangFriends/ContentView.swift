import SpriteKit
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings = AppSettings()
    @StateObject private var camera = VisionCameraManager()

    @State private var screen: AppScreen = .home
    @State private var selectedGame: GameType = .fruit
    @State private var showSettings = false
    @State private var showPause = false

    // Global Single-Hand Air Cursor state (works across Select top bar, Settings, Ready, Clear & Pause!)
    @State private var handTargets: [String: CGRect] = [:]
    @State private var hoveredGlobalTarget: String? = nil
    @State private var globalDwell: CGFloat = 0
    @State private var globalCooldown: CGFloat = 0
    @State private var globalAirTimer: Timer?
    @State private var rootSize: CGSize = CGSize(width: 852, height: 393)

    // Ready & Countdown state
    @State private var readyHold: [CGFloat] = [0, 0]
    @State private var countdownVal = 3
    @State private var countdownToken = 0
    @State private var readyTimer: Timer?

    // In-Game HUD state
    @State private var score = 0
    @State private var progressDone = 0
    @State private var progressTotal = 7
    @State private var calloutText = ""
    @State private var calloutVisible = false
    @State private var calloutWorkItem: DispatchWorkItem?
    @State private var clearSummary = ""

    // SpriteKit scene
    @State private var scene: KidsGameScene = {
        let s = KidsGameScene(size: CGSize(width: 852, height: 393))
        s.scaleMode = .resizeFill
        return s
    }()

    var body: some View {
        ZStack {
            // Single persistent live camera backdrop shared across Select -> Ready -> Countdown -> InGame -> Clear!
            // Eliminates AVCaptureVideoPreviewLayer teardown/recreation & RotationCoordinator main-thread stalls!
            if screen != .home {
                if camera.isUsingCamera && !settings.devMode {
                    CameraPreviewView(manager: camera)
                        .ignoresSafeArea()
                } else if screen != .select {
                    Color(red: 0.97, green: 0.98, blue: 0.99)
                        .ignoresSafeArea()
                }
            }

            if screen == .home {
                HomeScreenView(
                    settings: settings,
                    onStart: {
                        if !settings.devMode {
                            camera.start(expectedPlayers: settings.players, devMode: false)
                        }
                        screen = .select
                    },
                    onOpenSettings: { showSettings = true }
                )
            } else if screen == .select {
                StageSelectView(
                    settings: settings,
                    camera: camera,
                    hoveredGlobalTarget: hoveredGlobalTarget,
                    modalActive: showSettings || showPause,
                    onBack: {
                        camera.stopCamera()
                        screen = .home
                    },
                    onSelectGame: { game in
                        selectedGame = game
                        enterReadyScreen()
                    },
                    onOpenSettings: { showSettings = true }
                )
            } else {
                // SpriteKit + AR/HUD Overlays over the persistent CameraPreviewView
                GeometryReader { geo in
                    ZStack {
                        if screen == .inGame || screen == .clear {
                            SpriteView(scene: scene, options: [.allowsTransparency])
                                .ignoresSafeArea()
                        }

                        if screen == .ready || screen == .countdown {
                            ReadyOverlayView(
                                settings: settings,
                                camera: camera,
                                readyHold: readyHold,
                                isCountdown: screen == .countdown,
                                countdownVal: countdownVal,
                                hoveredGlobalTarget: hoveredGlobalTarget,
                                onBack: {
                                    stopReadyLoop()
                                    if settings.devMode { camera.stopCamera() }
                                    screen = .select
                                },
                                onSkip: { startCountdown() }
                            )
                        }

                        if screen == .inGame {
                            InGameHUDView(
                                gameType: selectedGame,
                                score: score,
                                progressDone: progressDone,
                                progressTotal: progressTotal,
                                calloutText: calloutText,
                                calloutVisible: calloutVisible,
                                onPause: {
                                    scene.setPausedState(true)
                                    showPause = true
                                }
                            )
                        }

                        if screen == .clear {
                            ClearOverlayView(
                                summary: clearSummary,
                                hoveredGlobalTarget: hoveredGlobalTarget,
                                onReplay: { startCountdown() },
                                onOtherGame: {
                                    scene.stopGame()
                                    if settings.devMode { camera.stopCamera() }
                                    screen = .select
                                }
                            )
                        }
                    }
                    .onAppear { camera.updateViewSize(geo.size) }
                    .onChange(of: geo.size) { _, newSize in camera.updateViewSize(newSize) }
                    // Developer touch/drag gesture (works in Simulator & when Dev Mode ON)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                guard !camera.isUsingCamera else { return }
                                let norm = CGPoint(
                                    x: val.location.x / max(1, geo.size.width),
                                    y: val.location.y / max(1, geo.size.height)
                                )
                                camera.setDevPointer(normalized: norm)
                            }
                    )
                }
            }

            if showSettings {
                SettingsModalView(settings: settings, hoveredGlobalTarget: hoveredGlobalTarget, onClose: { showSettings = false })
            }

            if showPause {
                PauseModalView(
                    hoveredGlobalTarget: hoveredGlobalTarget,
                    onResume: {
                        showPause = false
                        scene.setPausedState(false)
                        SoundEngine.shared.resumeBgm()
                    },
                    onQuit: {
                        showPause = false
                        SoundEngine.shared.setBgmAllowed(false)
                        scene.stopGame()
                        if settings.devMode { camera.stopCamera() }
                        screen = .select
                    }
                )
            }

            // Global Single-Hand Air Cursor Ring Overlay (Settings / Pause / Clear / Ready / Select Top Bar)
            if shouldShowGlobalAirCursor {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.22))
                        .overlay(Circle().stroke(Color.white.opacity(0.88), lineWidth: 4))
                        .frame(width: 64, height: 64)
                    Circle()
                        .trim(from: 0, to: globalDwell)
                        .stroke(Color(red: 0.13, green: 1.0, blue: 0.53), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 64, height: 64)
                    Text("✋").font(.system(size: 24))
                }
                .shadow(color: .green.opacity(0.65), radius: 12)
                .position(x: camera.airCursor.x * rootSize.width, y: camera.airCursor.y * rootSize.height)
                .allowsHitTesting(false)
                .zIndex(999)
            }
        }
        .coordinateSpace(name: "appRoot")
        .background(GeometryReader { g in
            Color.clear
                .onAppear { rootSize = g.size }
                .onChange(of: g.size) { _, s in rootSize = s }
        })
        .onPreferenceChange(HandTargetBoundsKey.self) { bounds in
            if bounds != handTargets {
                handTargets = bounds
            }
        }
        .onAppear {
            AppFont.warmUpInBackground()
            BundleImage.warmUpInBackground([
                "logo_pangpang", "momo", "popo", "momo_head", "popo_head",
                "card_fruit", "card_balloon", "card_freeze", "card_animal",
                "card_jungle", "card_mole", "card_balance"
            ])
            SoundEngine.shared.volume = Float(settings.volume)
            wireScene()
            syncCameraPublishMode()
            syncGlobalAirCursorLoop()
        }
        .onDisappear {
            globalAirTimer?.invalidate()
            globalAirTimer = nil
        }
        // 화면이 인게임 밖으로 나가면 어떤 경로든 BGM·게임 타이머 즉시 완전 정지!
        .onChange(of: screen) { _, newScreen in
            globalCooldown = 0.75
            if globalDwell != 0 { globalDwell = 0 }
            if hoveredGlobalTarget != nil { hoveredGlobalTarget = nil }
            syncCameraPublishMode()
            syncGlobalAirCursorLoop()
            let isPlaying = (newScreen == .inGame)
            SoundEngine.shared.setBgmAllowed(isPlaying)
            if !isPlaying && newScreen != .clear {
                scene.stopGame()
            }
        }
        .onChange(of: showSettings) { _, _ in
            globalCooldown = 0.75
            if globalDwell != 0 { globalDwell = 0 }
            if hoveredGlobalTarget != nil { hoveredGlobalTarget = nil }
            syncCameraPublishMode()
            syncGlobalAirCursorLoop()
        }
        .onChange(of: showPause) { _, _ in
            globalCooldown = 0.75
            if globalDwell != 0 { globalDwell = 0 }
            if hoveredGlobalTarget != nil { hoveredGlobalTarget = nil }
            syncCameraPublishMode()
            syncGlobalAirCursorLoop()
        }
        .onChange(of: settings.players) { _, newPlayers in
            camera.setExpectedPlayers(newPlayers)
        }
        // 앱이 백그라운드로 내려가거나 화면 꺼지면 BGM 즉시 일시정지
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                SoundEngine.shared.pauseBgm()
            } else if screen == .inGame && !showPause {
                SoundEngine.shared.resumeBgm()
            }
        }
    }

    private var shouldShowGlobalAirCursor: Bool {
        guard camera.airCursor.active, camera.isUsingCamera, !settings.devMode else { return false }
        if showSettings || showPause || screen == .clear || screen == .ready { return true }
        if screen == .select && hoveredGlobalTarget != nil { return true }
        return false
    }

    private var needsGlobalAirTimer: Bool {
        showSettings || showPause || screen == .select || screen == .ready || screen == .clear
    }

    private func syncGlobalAirCursorLoop() {
        if needsGlobalAirTimer {
            if globalAirTimer == nil {
                startGlobalAirCursorLoop()
            }
        } else {
            globalAirTimer?.invalidate()
            globalAirTimer = nil
            if globalDwell != 0 { globalDwell = 0 }
            if hoveredGlobalTarget != nil { hoveredGlobalTarget = nil }
        }
    }

    private func startGlobalAirCursorLoop() {
        globalAirTimer?.invalidate()
        globalAirTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { _ in
            if globalCooldown > 0 { globalCooldown = max(0, globalCooldown - 0.04) }
            guard camera.airCursor.active, camera.isUsingCamera, !settings.devMode else {
                if globalDwell != 0 { globalDwell = 0 }
                if hoveredGlobalTarget != nil { hoveredGlobalTarget = nil }
                return
            }
            let allowedPrefix: String?
            if showSettings { allowedPrefix = "set_" }
            else if showPause { allowedPrefix = "pause_" }
            else if screen == .clear { allowedPrefix = "clear_" }
            else if screen == .ready { allowedPrefix = "ready_" }
            else if screen == .select { allowedPrefix = "select_" }
            else { allowedPrefix = nil }

            guard let prefix = allowedPrefix else {
                if globalDwell != 0 { globalDwell = 0 }
                if hoveredGlobalTarget != nil { hoveredGlobalTarget = nil }
                return
            }

            let pt = CGPoint(x: camera.airCursor.x * rootSize.width, y: camera.airCursor.y * rootSize.height)
            var hitId: String? = nil
            var bestScore: CGFloat = .infinity
            let pad: CGFloat = 14
            for (id, rect) in handTargets where id.hasPrefix(prefix) {
                guard rect.width >= 4 && rect.height >= 4 else { continue }
                let insideExact = rect.contains(pt)
                let insidePad = rect.insetBy(dx: -pad, dy: -pad).contains(pt)
                guard insidePad else { continue }
                let nearX = max(rect.minX, min(pt.x, rect.maxX))
                let nearY = max(rect.minY, min(pt.y, rect.maxY))
                let edgeDist = hypot(pt.x - nearX, pt.y - nearY)
                let centerDist = hypot(pt.x - rect.midX, pt.y - rect.midY)
                let stickyBonus: CGFloat = (id == hoveredGlobalTarget) ? -10 : 0
                let score = (insideExact ? 0 : 1000) + edgeDist * 10 + centerDist * 0.08 + stickyBonus
                if score < bestScore {
                    bestScore = score
                    hitId = id
                }
            }

            if let id = hitId {
                if hoveredGlobalTarget != id {
                    hoveredGlobalTarget = id
                    globalDwell = 0
                }
                if isAlreadyActiveGlobalTarget(id) {
                    if globalDwell != 0 { globalDwell = 0 }
                } else if globalCooldown <= 0 {
                    let prevHalf = globalDwell >= 0.5
                    let dwellDur: CGFloat = id.hasPrefix("clear_") ? 1.2 : (id.hasPrefix("set_vol") ? 0.85 : 1.05)
                    globalDwell = min(1.0, globalDwell + 0.04 / dwellDur)
                    if !prevHalf && globalDwell >= 0.5 { SoundEngine.shared.playClick() }
                    if globalDwell >= 1.0 {
                        globalDwell = 0
                        globalCooldown = 0.85
                        hoveredGlobalTarget = nil
                        SoundEngine.shared.playReadyOk()
                        triggerGlobalHandAction(id)
                    }
                }
            } else {
                if globalDwell > 0 {
                    globalDwell = max(0, globalDwell - 0.08)
                }
                if globalDwell <= 0 && hoveredGlobalTarget != nil {
                    hoveredGlobalTarget = nil
                }
            }
        }
    }

    private func isAlreadyActiveGlobalTarget(_ id: String) -> Bool {
        switch id {
        case "select_1p", "set_1p": return settings.players == 1
        case "select_2p", "set_2p": return settings.players == 2
        case "set_slow": return settings.speedRaw == PlaySpeed.slow.rawValue
        case "set_normal": return settings.speedRaw == PlaySpeed.normal.rawValue
        case "set_fast": return settings.speedRaw == PlaySpeed.fast.rawValue
        default: return false
        }
    }

    private func triggerGlobalHandAction(_ id: String) {
        switch id {
        case "select_back":
            camera.stopCamera()
            screen = .home
        case "select_1p": settings.players = 1
        case "select_2p": settings.players = 2
        case "select_settings": showSettings = true
        case "set_close": showSettings = false
        case "set_1p": settings.players = 1
        case "set_2p": settings.players = 2
        case "set_quiet": settings.quietMode.toggle()
        case "set_slow": settings.speedRaw = PlaySpeed.slow.rawValue
        case "set_normal": settings.speedRaw = PlaySpeed.normal.rawValue
        case "set_fast": settings.speedRaw = PlaySpeed.fast.rawValue
        case "set_vol_down":
            settings.volume = max(0, settings.volume - 0.2)
            SoundEngine.shared.volume = Float(settings.volume)
        case "set_vol_up":
            settings.volume = min(1, settings.volume + 0.2)
            SoundEngine.shared.volume = Float(settings.volume)
        case "set_dev": settings.devMode.toggle()
        case "ready_back":
            stopReadyLoop()
            if settings.devMode { camera.stopCamera() }
            screen = .select
        case "ready_skip": startCountdown()
        case "clear_replay": startCountdown()
        case "clear_other":
            scene.stopGame()
            if settings.devMode { camera.stopCamera() }
            screen = .select
        case "pause_resume":
            showPause = false
            scene.setPausedState(false)
            SoundEngine.shared.resumeBgm()
        case "pause_quit":
            showPause = false
            SoundEngine.shared.setBgmAllowed(false)
            scene.stopGame()
            if settings.devMode { camera.stopCamera() }
            screen = .select
        default: break
        }
    }

    private func wireScene() {
        scene.cameraManager = camera
        scene.onScore = { val in
            DispatchQueue.main.async {
                if score != val { score = val }
            }
        }
        scene.onProgress = { done, total in
            DispatchQueue.main.async {
                if progressDone != done { progressDone = done }
                if progressTotal != total { progressTotal = total }
            }
        }
        scene.onCallout = { text, duration in
            DispatchQueue.main.async {
                calloutWorkItem?.cancel()
                if text.isEmpty {
                    withAnimation(.easeOut(duration: 0.35)) { calloutVisible = false }
                } else {
                    calloutText = text
                    withAnimation(.easeOut(duration: 0.2)) { calloutVisible = true }
                    if duration > 0 {
                        let work = DispatchWorkItem {
                            withAnimation(.easeOut(duration: 0.45)) { calloutVisible = false }
                        }
                        calloutWorkItem = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
                    }
                }
            }
        }
        scene.onFinish = { summary in
            DispatchQueue.main.async {
                clearSummary = summary
                screen = .clear
            }
        }
    }

    private func syncCameraPublishMode() {
        if showSettings || showPause {
            camera.setUIPublishMode(.cursorOnly)
        } else if screen == .inGame {
            // Zero SwiftUI re-renders during gameplay — GameScene reads lock-protected snapshotPlayers() directly at 60fps!
            camera.setUIPublishMode(.none)
        } else if screen == .ready || screen == .countdown {
            camera.setUIPublishMode(.readyAndCursor)
        } else if screen == .select || screen == .clear {
            camera.setUIPublishMode(.cursorOnly)
        } else {
            camera.setUIPublishMode(.none)
        }
    }

    private func enterReadyScreen() {
        readyHold = [0, 0]
        screen = .ready
        // Pre-decode ONLY the selected game's assets off the main thread during Ready/Countdown (0ms launch!)
        scene.warmUpAssetsInBackground(for: selectedGame)
        if settings.devMode || !camera.isUsingCamera {
            camera.start(expectedPlayers: settings.players, devMode: settings.devMode)
        } else {
            camera.setExpectedPlayers(settings.players)
        }

        stopReadyLoop()
        readyTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            guard screen == .ready else { return }
            camera.tickDevMode()
            let count = settings.players
            let activePlayers = camera.snapshotPlayers()
            var allReady = true
            for i in 0..<count {
                if let p = activePlayers.first(where: { $0.id == i }) ?? (count == 1 ? activePlayers.first : nil) {
                    readyHold[i] = min(1.5, readyHold[i] + (p.handsUp ? 0.11 : 0.035))
                } else {
                    readyHold[i] = max(0, readyHold[i] - 0.05)
                }
                if readyHold[i] < 1.15 { allReady = false }
            }
            if allReady {
                SoundEngine.shared.playReadyOk()
                startCountdown()
            }
        }
    }

    private func stopReadyLoop() {
        readyTimer?.invalidate()
        readyTimer = nil
    }

    private func startCountdown() {
        stopReadyLoop()
        countdownToken += 1
        let token = countdownToken
        screen = .countdown
        countdownVal = 3
        SoundEngine.shared.playCountdown(3)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            guard screen == .countdown, countdownToken == token else { return }
            countdownVal = 2
            SoundEngine.shared.playCountdown(2)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.70) {
            guard screen == .countdown, countdownToken == token else { return }
            countdownVal = 1
            SoundEngine.shared.playCountdown(1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.55) {
            guard screen == .countdown, countdownToken == token else { return }
            SoundEngine.shared.playCountdown(0)
            SoundEngine.shared.setBgmAllowed(true)
            screen = .inGame
            scene.startGame(type: selectedGame, settings: settings)
        }
    }
}

// MARK: - Reusable Web-Parity Stroked Jua Typography
struct StrokedJuaText: View {
    let text: String
    let size: CGFloat
    var fillColor: Color = Color(red: 1.0, green: 0.894, blue: 0.369)    // #FFE45E
    var strokeColor: Color = Color(red: 0.851, green: 0.525, blue: 0.0)  // #D98600
    var strokeWidth: CGFloat = 3.0
    var shadowColor: Color = Color(red: 0.627, green: 0.345, blue: 0.0).opacity(0.55)
    var shadowRadius: CGFloat = 10
    var shadowY: CGFloat = 5

    private static let strokeDirections: [(CGFloat, CGFloat)] = (0..<8).map { i in
        let angle = CGFloat(i) * (.pi * 2.0 / 8.0)
        return (cos(angle), sin(angle))
    }

    var body: some View {
        ZStack {
            ZStack {
                ForEach(0..<Self.strokeDirections.count, id: \.self) { idx in
                    let dir = Self.strokeDirections[idx]
                    Text(text)
                        .font(AppFont.swiftUIFont(size: size))
                        .foregroundStyle(strokeColor)
                        .offset(x: dir.0 * strokeWidth, y: dir.1 * strokeWidth)
                }
            }
            .compositingGroup()
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)

            Text(text)
                .font(AppFont.swiftUIFont(size: size))
                .foregroundStyle(fillColor)
        }
        .accessibilityLabel(text)
    }
}

// MARK: - 3. Ready Check & 3-2-1 Countdown Overlay
struct ReadyOverlayView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var camera: VisionCameraManager
    let readyHold: [CGFloat]
    let isCountdown: Bool
    let countdownVal: Int
    var hoveredGlobalTarget: String? = nil
    let onBack: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            // Live detected hand tracking rings during Ready Check (only genuinely tracked hands!)
            GeometryReader { geo in
                ForEach(camera.players) { p in
                    let col = p.id == 0 ? Color(red: 0.36, green: 0.90, blue: 0.85) : Color(red: 1.0, green: 0.54, blue: 0.58)
                    let handList: [(CGPoint, CGFloat)] = [
                        (p.leftHand, p.metrics.lWristConf),
                        (p.rightHand, p.metrics.rWristConf)
                    ]
                    ForEach(Array(handList.enumerated()), id: \.offset) { _, pair in
                        if pair.1 >= 0.22 {
                            Circle()
                                .fill(col.opacity(0.28))
                                .overlay(Circle().stroke(col, lineWidth: 3.5))
                                .frame(width: 40, height: 40)
                                .position(x: pair.0.x * geo.size.width, y: pair.0.y * geo.size.height)
                        }
                    }
                }
            }
            .allowsHitTesting(false)

            // AR Capsules for 1P or 2P
            HStack(spacing: 70) {
                ForEach(0..<settings.players, id: \.self) { idx in
                    let isOk = readyHold[idx] >= 1.0
                    let col = idx == 0 ? Color(red: 0.36, green: 0.90, blue: 0.85) : Color(red: 1.0, green: 0.54, blue: 0.58)
                    ZStack {
                        Capsule()
                            .fill(isOk ? col.opacity(0.16) : Color.white.opacity(0.08))
                            .overlay(
                                Capsule()
                                    .stroke(col, style: StrokeStyle(lineWidth: isOk ? 6 : 3.5, dash: isOk ? [] : [10, 8]))
                            )
                            .frame(width: 170, height: 245)

                        VStack {
                            Text(isOk ? "✓ P\(idx + 1) OK!" : (idx == 0 ? "P1 · 모모" : "P2 · 포포"))
                                .font(AppFont.swiftUIFont(size: 16))
                                .foregroundStyle(Color(red: 0.153, green: 0.196, blue: 0.267))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(isOk ? col.opacity(0.35) : .white.opacity(0.92), in: Capsule())
                                .offset(y: -14)
                            Spacer()
                            BundleImage.swiftUIImage(named: idx == 0 ? "momo_head" : "popo_head")
                                .resizable().scaledToFit().frame(width: 48, height: 48)
                                .offset(y: 12)
                        }
                        .frame(height: 245)
                    }
                }
            }
            .offset(y: 26)

            // Top bar + Banner
            VStack {
                HStack {
                    Button(action: { SoundEngine.shared.playClick(); onBack() }) {
                        Text("✕")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.black.opacity(0.55), in: Circle())
                    }
                    .handTarget("ready_back", hovered: hoveredGlobalTarget)
                    HStack(spacing: 6) {
                        Circle().fill(.red).frame(width: 8, height: 8)
                        Text(camera.isUsingCamera ? "LIVE · \(settings.players)P" : "🛠️ DEV · \(settings.players)P")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.62), in: Capsule())

                    Spacer()

                    Button(action: { SoundEngine.shared.playClick(); onSkip() }) {
                        Text("바로 시작 ▶")
                            .font(AppFont.swiftUIFont(size: 15))
                            .foregroundStyle(Color(red: 0.153, green: 0.196, blue: 0.267))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.95), in: Capsule())
                            .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
                    }
                    .handTarget("ready_skip", hovered: hoveredGlobalTarget)
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)

                Text(isCountdown ? "준비 완료! 곧 시작해요!" : (settings.players == 2 ? "모모·포포 자리에 서서 만세! 해주세요" : "모모 자리에 서서 만세! 해주세요"))
                    .font(AppFont.swiftUIFont(size: 20))
                    .foregroundStyle(Color(red: 0.153, green: 0.196, blue: 0.267))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.96), in: Capsule())
                    .shadow(color: Color(red: 0.10, green: 0.15, blue: 0.24).opacity(0.18), radius: 12, y: 5)

                Spacer()

                Text(camera.statusText)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .padding(.bottom, 8)
            }

            if isCountdown {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.91, blue: 0.47).opacity(0.26),
                                    Color(red: 1.0, green: 0.77, blue: 0.0).opacity(0.08),
                                ],
                                center: .center,
                                startRadius: 6,
                                endRadius: 68
                            )
                        )
                        .overlay(
                            Circle()
                                .stroke(Color(red: 1.0, green: 0.831, blue: 0.231), lineWidth: 10)
                        )
                        .overlay(
                            Circle()
                                .inset(by: 6)
                                .stroke(Color.white.opacity(0.45), lineWidth: 2)
                        )
                        .frame(width: 136, height: 136)
                        .shadow(color: Color(red: 1.0, green: 0.831, blue: 0.231).opacity(0.75), radius: 24)

                    StrokedJuaText(
                        text: "\(countdownVal)",
                        size: 74,
                        fillColor: Color(red: 1.0, green: 0.894, blue: 0.369),
                        strokeColor: Color(red: 0.851, green: 0.525, blue: 0.0),
                        strokeWidth: 3.2,
                        shadowColor: Color(red: 0.627, green: 0.345, blue: 0.0).opacity(0.55),
                        shadowRadius: 10,
                        shadowY: 5
                    )
                }
            }
        }
    }
}

// MARK: - 4. In-Game Minimal HUD
struct InGameHUDView: View {
    let gameType: GameType
    let score: Int
    let progressDone: Int
    let progressTotal: Int
    let calloutText: String
    let calloutVisible: Bool
    let onPause: () -> Void

    var body: some View {
        VStack {
            HStack {
                // 즉시 탭으로 바로 일시정지!
                Button(action: {
                    SoundEngine.shared.playClick()
                    onPause()
                }) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(red: 0.2, green: 0.25, blue: 0.35))
                        .frame(width: 46, height: 46)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.75), lineWidth: 2))
                }

                Spacer()

                // Hide redundant top-center progress dots in games with dedicated visual progress UI (.animal & .jungle)
                if gameType != .animal && gameType != .jungle {
                    HStack(spacing: 8) {
                        ForEach(0..<max(1, progressTotal), id: \.self) { i in
                            Circle()
                                .fill(i < progressDone ? Color.white : Color.white.opacity(0.36))
                                .frame(width: 10, height: 10)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.35), in: Capsule())
                }

                Spacer()

                HStack(spacing: 7) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(Color(red: 1.0, green: 0.831, blue: 0.231))
                        .font(.system(size: 19))
                        .shadow(color: Color.orange.opacity(0.35), radius: 2, y: 1)
                    Text("\(score)")
                        .font(AppFont.swiftUIFont(size: 25))
                        .foregroundStyle(Color(red: 0.118, green: 0.227, blue: 0.373))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 7)
                .background(Color(red: 1.0, green: 0.992, blue: 0.961).opacity(0.96), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.95), lineWidth: 2.5))
                .shadow(color: Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.20), radius: 10, y: 4)
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)

            if calloutVisible && !calloutText.isEmpty {
                Text(calloutText)
                    .font(AppFont.swiftUIFont(size: 21))
                    .foregroundStyle(.white)
                    .shadow(color: Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.28), radius: 3, y: 2)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 9)
                    .background(Color(red: 1.0, green: 0.376, blue: 0.416).opacity(0.94), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.94), lineWidth: 3))
                    .shadow(color: Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.24), radius: 12, y: 5)
                    .transition(.opacity)
            }

            Spacer()
        }
    }
}

// MARK: - Clear & Pause Overlays (Open Live-Camera Celebration + Hand & Touch Support!)
struct ClearOverlayView: View {
    let summary: String
    var hoveredGlobalTarget: String? = nil
    let onReplay: () -> Void
    let onOtherGame: () -> Void

    @State private var appeared = false
    @State private var starShow: [Bool] = [false, false, false]
    @State private var mascotBounce = false

    var body: some View {
        VStack {
            // Top floating translucent victory ribbon (leaves center camera 100% open!)
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    BundleImage.swiftUIImage(named: "momo_head").resizable().scaledToFit().frame(width: 54)
                        .offset(y: mascotBounce ? -6 : 0)
                    BundleImage.swiftUIImage(named: "popo_head").resizable().scaledToFit().frame(width: 54)
                        .offset(y: mascotBounce ? 0 : -6)
                }
                .offset(y: -30)
                .padding(.bottom, -30)
                .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: mascotBounce)

                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { idx in
                        Image(systemName: "star.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.yellow)
                            .shadow(color: .orange.opacity(0.45), radius: 5, y: 2)
                            .scaleEffect(starShow[idx] ? 1.0 : 0.15)
                            .opacity(starShow[idx] ? 1.0 : 0.0)
                            .animation(.spring(response: 0.42, dampingFraction: 0.58), value: starShow[idx])
                    }
                }
                Text("최고야! 짝짝짝!")
                    .font(AppFont.swiftUIFont(size: 32))
                    .foregroundStyle(Color(red: 0.153, green: 0.196, blue: 0.267))
                Text(summary)
                    .font(AppFont.swiftUIFont(size: 16))
                    .foregroundStyle(Color(red: 0.392, green: 0.443, blue: 0.533))
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .background(Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(Color(red: 1.0, green: 0.839, blue: 0.267), lineWidth: 4))
            .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
            .padding(.top, 26)
            .scaleEffect(appeared ? 1.0 : 0.82)
            .offset(y: appeared ? 0 : -26)
            .opacity(appeared ? 1.0 : 0.0)
            .animation(.spring(response: 0.55, dampingFraction: 0.72), value: appeared)

            Spacer()

            // Bottom floating action dock (hand hover 1.2s OR instant touch!)
            HStack(spacing: 18) {
                Button(action: { SoundEngine.shared.playClick(); onReplay() }) {
                    Text("🔄 다시 하기")
                        .font(AppFont.swiftUIFont(size: 22))
                        .foregroundStyle(.white)
                        .shadow(color: Color(red: 0.725, green: 0.431, blue: 0.0).opacity(0.35), radius: 2, y: 1)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 13)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.886, blue: 0.290),
                                    Color(red: 1.0, green: 0.761, blue: 0.039),
                                    Color(red: 0.961, green: 0.686, blue: 0.0),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(.white.opacity(0.55), lineWidth: 2))
                        .shadow(color: Color(red: 0.949, green: 0.678, blue: 0.0).opacity(0.42), radius: 10, y: 5)
                }
                .handTarget("clear_replay", hovered: hoveredGlobalTarget)

                Button(action: { SoundEngine.shared.playClick(); onOtherGame() }) {
                    Text("🎮 다른 놀이")
                        .font(AppFont.swiftUIFont(size: 22))
                        .foregroundStyle(.white)
                        .shadow(color: Color(red: 0.10, green: 0.45, blue: 0.42).opacity(0.32), radius: 2, y: 1)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 13)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.455, green: 0.918, blue: 0.878),
                                    Color(red: 0.247, green: 0.784, blue: 0.741),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(.white.opacity(0.65), lineWidth: 2.5))
                        .shadow(color: Color(red: 0.247, green: 0.784, blue: 0.741).opacity(0.38), radius: 10, y: 5)
                }
                .handTarget("clear_other", hovered: hoveredGlobalTarget)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 18)
            .offset(y: appeared ? 0 : 40)
            .opacity(appeared ? 1.0 : 0.0)
            .animation(.spring(response: 0.55, dampingFraction: 0.75).delay(0.12), value: appeared)
        }
        .onAppear {
            appeared = true
            mascotBounce = true
            for i in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16 + Double(i) * 0.16) {
                    starShow[i] = true
                }
            }
        }
    }
}

struct PauseModalView: View {
    var hoveredGlobalTarget: String? = nil
    let onResume: () -> Void
    let onQuit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.38).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("잠깐 쉬어가기")
                    .font(AppFont.swiftUIFont(size: 28))
                    .foregroundStyle(Color(red: 0.153, green: 0.196, blue: 0.267))
                Button(action: { SoundEngine.shared.playClick(); onResume() }) {
                    Text("▶ 계속 놀기")
                        .font(AppFont.swiftUIFont(size: 21))
                        .foregroundStyle(.white)
                        .shadow(color: Color(red: 0.725, green: 0.431, blue: 0.0).opacity(0.32), radius: 2, y: 1)
                        .frame(width: 220, height: 50)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.886, blue: 0.290),
                                    Color(red: 1.0, green: 0.761, blue: 0.039),
                                    Color(red: 0.961, green: 0.686, blue: 0.0),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(.white.opacity(0.5), lineWidth: 2))
                        .shadow(color: Color(red: 0.949, green: 0.678, blue: 0.0).opacity(0.36), radius: 10, y: 4)
                }
                .handTarget("pause_resume", hovered: hoveredGlobalTarget)

                Button(action: { SoundEngine.shared.playClick(); onQuit() }) {
                    Text("🎮 다른 놀이")
                        .font(AppFont.swiftUIFont(size: 21))
                        .foregroundStyle(.white)
                        .shadow(color: Color(red: 0.10, green: 0.45, blue: 0.42).opacity(0.30), radius: 2, y: 1)
                        .frame(width: 220, height: 50)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.455, green: 0.918, blue: 0.878),
                                    Color(red: 0.247, green: 0.784, blue: 0.741),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            in: Capsule()
                        )
                        .overlay(Capsule().stroke(.white.opacity(0.65), lineWidth: 2.5))
                        .shadow(color: Color(red: 0.247, green: 0.784, blue: 0.741).opacity(0.34), radius: 10, y: 4)
                }
                .handTarget("pause_quit", hovered: hoveredGlobalTarget)
            }
            .padding(28)
            .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        }
    }
}
