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

    // Ready & Countdown state
    @State private var readyHold: [CGFloat] = [0, 0]
    @State private var countdownVal = 3
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
            if screen == .home {
                HomeScreenView(
                    settings: settings,
                    onStart: { screen = .select },
                    onOpenSettings: { showSettings = true }
                )
            } else if screen == .select {
                StageSelectView(
                    settings: settings,
                    onBack: { screen = .home },
                    onSelectGame: { game in
                        selectedGame = game
                        enterReadyScreen()
                    },
                    onOpenSettings: { showSettings = true }
                )
            } else {
                // Camera / Minimal Dev Backdrop + SpriteKit + AR/HUD Overlays
                GeometryReader { geo in
                    ZStack {
                        if camera.isUsingCamera {
                            CameraPreviewView(manager: camera)
                                .ignoresSafeArea()
                        } else {
                            Color(red: 0.97, green: 0.98, blue: 0.99)
                                .ignoresSafeArea()
                        }

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
                                onBack: {
                                    stopReadyLoop()
                                    camera.stopCamera()
                                    screen = .select
                                },
                                onSkip: { startCountdown() }
                            )
                        }

                        if screen == .inGame {
                            InGameHUDView(
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
                                onReplay: { startCountdown() },
                                onOtherGame: {
                                    scene.stopGame()
                                    camera.stopCamera()
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
                SettingsModalView(settings: settings, onClose: { showSettings = false })
            }

            if showPause {
                PauseModalView(
                    onResume: {
                        showPause = false
                        scene.setPausedState(false)
                        SoundEngine.shared.resumeBgm()
                    },
                    onQuit: {
                        showPause = false
                        SoundEngine.shared.setBgmAllowed(false)
                        scene.stopGame()
                        camera.stopCamera()
                        screen = .select
                    }
                )
            }
        }
        .onAppear {
            SoundEngine.shared.volume = Float(settings.volume)
            wireScene()
        }
        // 화면이 인게임 밖으로 나가면 어떤 경로든 BGM·게임 타이머 즉시 완전 정지!
        .onChange(of: screen) { _, newScreen in
            let isPlaying = (newScreen == .inGame)
            SoundEngine.shared.setBgmAllowed(isPlaying)
            if !isPlaying && newScreen != .clear {
                scene.stopGame()
            }
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

    private func wireScene() {
        scene.cameraManager = camera
        scene.onScore = { val in DispatchQueue.main.async { score = val } }
        scene.onProgress = { done, total in
            DispatchQueue.main.async {
                progressDone = done
                progressTotal = total
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

    private func enterReadyScreen() {
        readyHold = [0, 0]
        screen = .ready
        camera.start(expectedPlayers: settings.players, devMode: settings.devMode)

        stopReadyLoop()
        readyTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            guard screen == .ready else { return }
            camera.tickDevMode()
            let count = settings.players
            var allReady = true
            for i in 0..<count {
                if i < camera.players.count {
                    let p = camera.players[i]
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
        screen = .countdown
        countdownVal = 3
        SoundEngine.shared.playCountdown(3)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            guard screen == .countdown else { return }
            countdownVal = 2
            SoundEngine.shared.playCountdown(2)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.70) {
            guard screen == .countdown else { return }
            countdownVal = 1
            SoundEngine.shared.playCountdown(1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.55) {
            guard screen == .countdown else { return }
            SoundEngine.shared.playCountdown(0)
            SoundEngine.shared.setBgmAllowed(true)
            screen = .inGame
            scene.startGame(type: selectedGame, settings: settings)
        }
    }
}

// MARK: - 3. Ready Check & 3-2-1 Countdown Overlay
struct ReadyOverlayView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var camera: VisionCameraManager
    let readyHold: [CGFloat]
    let isCountdown: Bool
    let countdownVal: Int
    let onBack: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            // Live detected hand tracking rings during Ready Check (즉각적인 인식 피드백!)
            GeometryReader { geo in
                ForEach(camera.players) { p in
                    let col = p.id == 0 ? Color(red: 0.36, green: 0.90, blue: 0.85) : Color(red: 1.0, green: 0.54, blue: 0.58)
                    ForEach(Array([p.leftHand, p.rightHand].enumerated()), id: \.offset) { _, pt in
                        Circle()
                            .fill(col.opacity(0.28))
                            .overlay(Circle().stroke(col, lineWidth: 3.5))
                            .frame(width: 40, height: 40)
                            .position(x: pt.x * geo.size.width, y: pt.y * geo.size.height)
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
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(Color(red: 0.16, green: 0.20, blue: 0.27))
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
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Color(red: 0.16, green: 0.20, blue: 0.27))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.95), in: Capsule())
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)

                Text(isCountdown ? "준비 완료! 곧 시작해요!" : (settings.players == 2 ? "모모·포포 자리에 서서 만세! 해주세요" : "모모 자리에 서서 만세! 해주세요"))
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Color(red: 0.16, green: 0.20, blue: 0.27))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 9)
                    .background(.white.opacity(0.95), in: Capsule())
                    .shadow(color: .black.opacity(0.14), radius: 10, y: 4)

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
                        .fill(Color.yellow.opacity(0.2))
                        .overlay(Circle().stroke(Color(red: 1.0, green: 0.83, blue: 0.23), lineWidth: 10))
                        .frame(width: 120, height: 120)
                        .shadow(color: .yellow.opacity(0.65), radius: 22)
                    Text("\(countdownVal)")
                        .font(.system(size: 66, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 1.0, green: 0.89, blue: 0.36))
                        .shadow(color: .orange.opacity(0.7), radius: 6, y: 3)
                }
            }
        }
    }
}

// MARK: - 4. In-Game Minimal HUD
struct InGameHUDView: View {
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

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 18))
                    Text("\(score)")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.42, green: 0.29, blue: 0.21))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .background(.white.opacity(0.95), in: Capsule())
                .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)

            if calloutVisible && !calloutText.isEmpty {
                Text(calloutText)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .background(Color(red: 1.0, green: 0.38, blue: 0.42).opacity(0.92), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.9), lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
                    .transition(.opacity)
            }

            Spacer()
        }
    }
}

// MARK: - Clear & Pause Overlays
struct ClearOverlayView: View {
    let summary: String
    let onReplay: () -> Void
    let onOtherGame: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    BundleImage.swiftUIImage(named: "momo_head").resizable().scaledToFit().frame(width: 56)
                    BundleImage.swiftUIImage(named: "popo_head").resizable().scaledToFit().frame(width: 56)
                }
                .offset(y: -36)
                .padding(.bottom, -36)

                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { _ in
                        Image(systemName: "star.fill").font(.system(size: 36)).foregroundStyle(.yellow)
                    }
                }
                Text("최고야! 짝짝짝!")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                Text(summary)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    Button(action: { SoundEngine.shared.playClick(); onReplay() }) {
                        Text("다시 하기")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .background(Color.orange, in: Capsule())
                    }
                    Button(action: { SoundEngine.shared.playClick(); onOtherGame() }) {
                        Text("다른 놀이")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .background(Color(red: 0.25, green: 0.78, blue: 0.74), in: Capsule())
                    }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 24)
            .background(.white.opacity(0.97), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(Color.yellow, lineWidth: 5))
            .shadow(color: .black.opacity(0.2), radius: 22, y: 10)
        }
    }
}

struct PauseModalView: View {
    let onResume: () -> Void
    let onQuit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.38).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("잠깐 쉬어가기")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                Button(action: { SoundEngine.shared.playClick(); onResume() }) {
                    Text("▶ 계속 놀기")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 210, height: 48)
                        .background(Color.orange, in: Capsule())
                }
                Button(action: { SoundEngine.shared.playClick(); onQuit() }) {
                    Text("다른 놀이")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 210, height: 48)
                        .background(Color(red: 0.25, green: 0.78, blue: 0.74), in: Capsule())
                }
            }
            .padding(28)
            .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        }
    }
}
