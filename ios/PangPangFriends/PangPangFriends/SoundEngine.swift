import AVFoundation
import Foundation

/// Dual-pipeline audio engine:
/// - Dedicated `AVAudioPlayer` for rich bundled multi-instrument `.m4a` looping BGM tracks
/// - Dedicated `AVAudioEngine` synth for zero-latency Wii/Balloon SFX
/// - Strict `bgmAllowed` main-thread lifecycle gate guarantees ZERO BGM leaks when leaving games!
final class SoundEngine {
    static let shared = SoundEngine()

    private let audioQueue = DispatchQueue(label: "pp.audio.queue", qos: .userInitiated)
    private let engine = AVAudioEngine()
    private let sfxPlayer = AVAudioPlayerNode()
    private let sampleRate: Double = 44100
    private var format: AVAudioFormat

    private var bgmPlayer: AVAudioPlayer?
    private var currentTrack: String?
    private var bgmAllowed: Bool = false

    // Preloaded in-memory SFX data + reusable polyphonic player pool on dedicated audioQueue (0ms main-thread impact!)
    private var sfxDataCache: [String: Data] = [:]
    private var sfxPlayerPool: [String: [AVAudioPlayer]] = [:]

    var volume: Float = 0.8 {
        didSet {
            let vol = volume
            audioQueue.async {
                self.bgmPlayer?.volume = min(1.0, vol * 0.55)
            }
        }
    }

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(sfxPlayer)
        engine.connect(sfxPlayer, to: engine.mainMixerNode, format: format)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigChange),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        audioQueue.async {
            self.configureAudioSession()
            self.preloadSfxFiles()
        }
    }

    @objc private func handleEngineConfigChange() {
        audioQueue.async {
            self.recoverAudioEngine()
        }
    }

    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeVal = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeVal) else { return }
        audioQueue.async {
            if type == .began {
                self.bgmPlayer?.pause()
                self.sfxPlayer.stop()
                if self.engine.isRunning { self.engine.pause() }
            } else if type == .ended {
                self.recoverAudioEngine()
                if self.bgmAllowed {
                    self.bgmPlayer?.play()
                }
            }
        }
    }

    private func recoverAudioEngine() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            sfxPlayer.stop()
            if engine.isRunning { engine.stop() }
            engine.prepare()
            try engine.start()
            sfxPlayer.play()
        } catch {
            // Graceful fallback on simulator or transient route change
        }
    }

    private func preloadSfxFiles() {
        let keys = [
            "sfx_swoosh", "sfx_slice", "sfx_tough_hit", "sfx_golden_pop",
            "sfx_rainbow_blast", "sfx_boss_appear", "sfx_boss_hit", "sfx_boss_smash",
            "sfx_balloon_boing", "sfx_balloon_beach", "sfx_balloon_gold",
            "sfx_balloon_bounce", "sfx_balloon_milestone",
            "sfx_dj_scratch", "sfx_club_airhorn", "sfx_disco_clear",
            "sfx_mole_bonk", "sfx_jump_star", "sfx_wind_whoosh"
        ]
        for k in keys {
            if let url = Bundle.main.url(forResource: k, withExtension: "m4a"),
               let data = try? Data(contentsOf: url) {
                sfxDataCache[k] = data
            }
        }
    }

    @discardableResult
    private func playSfxFile(_ key: String, gain: Float = 0.9, rate: Float = 1.0) -> Bool {
        let vol = volume
        guard vol > 0.01 else { return true }
        audioQueue.async {
            guard let data = self.sfxDataCache[key] else { return }
            var pool = self.sfxPlayerPool[key] ?? []
            let player: AVAudioPlayer
            if let idle = pool.first(where: { !$0.isPlaying }) {
                player = idle
                player.currentTime = 0
            } else if pool.count < 4, let created = try? AVAudioPlayer(data: data) {
                created.enableRate = true
                created.prepareToPlay()
                pool.append(created)
                self.sfxPlayerPool[key] = pool
                player = created
            } else if let oldest = pool.first {
                oldest.stop()
                oldest.currentTime = 0
                player = oldest
            } else {
                return
            }
            player.rate = max(0.7, min(1.6, rate))
            player.volume = min(1.0, gain * vol)
            player.play()
        }
        return true
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            engine.prepare()
            try engine.start()
            sfxPlayer.play()
        } catch {
            // Simulator or background audio fallback
        }
    }

    private func ensureRunning() {
        if !engine.isRunning {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? session.setActive(true)
            engine.prepare()
            try? engine.start()
        }
        if !sfxPlayer.isPlaying { sfxPlayer.play() }
    }

    /// Central lifecycle gate: set `false` on Home / Select / Ready / Clear / Background!
    func setBgmAllowed(_ allowed: Bool) {
        audioQueue.async {
            self.bgmAllowed = allowed
            if !allowed {
                self.stopBgmImmediate()
            }
        }
    }

    func startBgm(track: String, rate: Float = 1.0) {
        let vol = volume
        audioQueue.async {
            guard self.bgmAllowed else { return }
            let clampedRate = max(0.85, min(1.3, rate))

            // Smoothly update rate if same track is already playing
            if let bp = self.bgmPlayer, self.currentTrack == track, bp.isPlaying {
                bp.rate = clampedRate
                bp.volume = min(1.0, vol * 0.55)
                return
            }

            self.stopBgmImmediate()
            guard self.bgmAllowed else { return }

            guard let url = Bundle.main.url(forResource: track, withExtension: "m4a") else { return }
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = -1
                player.enableRate = true
                player.rate = clampedRate
                player.volume = min(1.0, vol * 0.55)
                player.prepareToPlay()
                player.play()
                self.bgmPlayer = player
                self.currentTrack = track
            } catch {
                // Ignore audio load errors gracefully
            }
        }
    }

    func setBgmRate(_ rate: Float) {
        audioQueue.async {
            self.bgmPlayer?.rate = max(0.85, min(1.3, rate))
        }
    }

    func pauseBgm() {
        audioQueue.async {
            self.bgmPlayer?.pause()
        }
    }

    func resumeBgm() {
        let vol = volume
        audioQueue.async {
            guard self.bgmAllowed else { return }
            self.bgmPlayer?.volume = min(1.0, vol * 0.55)
            self.bgmPlayer?.play()
        }
    }

    func stopBgm() {
        audioQueue.async {
            self.stopBgmImmediate()
        }
    }

    func fadeOutBgm(duration: TimeInterval = 1.1) {
        audioQueue.async {
            guard let player = self.bgmPlayer else { return }
            player.setVolume(0, fadeDuration: duration)
            self.audioQueue.asyncAfter(deadline: .now() + duration + 0.05) {
                if self.bgmPlayer === player {
                    self.stopBgmImmediate()
                }
            }
        }
    }

    private func stopBgmImmediate() {
        bgmPlayer?.stop()
        bgmPlayer = nil
        currentTrack = nil
    }

    // MARK: - Low-latency Synthesized SFX (offloaded to audioQueue so main thread never blocks)
    func playTone(freq: Double, duration: Double, gain: Float = 0.25, freqEnd: Double? = nil) {
        let vol = volume
        guard vol > 0.01 else { return }
        audioQueue.async {
            self.ensureRunning()

            let frameCount = AVAudioFrameCount(self.sampleRate * duration)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: self.format, frameCapacity: frameCount) else { return }
            buffer.frameLength = frameCount
            guard let data = buffer.floatChannelData?[0] else { return }

            let amp = gain * vol
            let endF = freqEnd ?? freq
            let n = Int(frameCount)
            for i in 0..<n {
                let p = Double(i) / Double(max(1, n))
                let t = Double(i) / self.sampleRate
                let f = freq + (endF - freq) * p
                let tailFade: Double = p > 0.92 ? max(0.0, (1.0 - p) / 0.08) : 1.0
                let env = Float(min(1.0, p / 0.03) * exp(-4.8 * p) * tailFade)
                let wave = sin(2.0 * .pi * f * t) + 0.22 * sin(2.0 * .pi * f * 2.0 * t) * exp(-8.0 * p)
                data[i] = Float(wave) * amp * env
            }
            self.sfxPlayer.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        }
    }

    func playClick() {
        playTone(freq: 620, duration: 0.08, gain: 0.2, freqEnd: 880)
    }

    func playReadyOk() {
        playTone(freq: 587.33, duration: 0.14, gain: 0.24)
        audioQueue.asyncAfter(deadline: .now() + 0.08) {
            self.playTone(freq: 880, duration: 0.2, gain: 0.24)
        }
    }

    func playCountdown(_ num: Int) {
        if num > 0 {
            playTone(freq: 523.25, duration: 0.16, gain: 0.25)
        } else {
            playTone(freq: 783.99, duration: 0.14, gain: 0.26)
            audioQueue.asyncAfter(deadline: .now() + 0.08) {
                self.playTone(freq: 1046.5, duration: 0.32, gain: 0.28)
            }
        }
    }

    func playSwoosh() {
        playSfxFile("sfx_swoosh", gain: 0.09, rate: Float.random(in: 0.94...1.12))
    }

    func playToughHit(_ step: Int = 1) {
        if playSfxFile("sfx_tough_hit", gain: 0.9, rate: 0.96 + Float(step) * 0.12) { return }
        playBossHit(step)
    }

    func playBossAppear() {
        if playSfxFile("sfx_boss_appear", gain: 0.95, rate: 1.0) { return }
        playFeverStart()
    }

    func playPop(combo: Int = 0) {
        let pitch = 0.94 + Float(min(combo, 9)) * 0.048 + Float.random(in: -0.02...0.02)
        if playSfxFile("sfx_slice", gain: 0.9, rate: pitch) { return }
        let scale: [Double] = [523.25, 587.33, 659.25, 783.99, 880.0, 987.77, 1046.5, 1174.66, 1318.5, 1567.98]
        let f = scale[min(combo, scale.count - 1)]
        playTone(freq: 380 + Double(min(combo, 8)) * 35, duration: 0.1, gain: 0.26, freqEnd: 980)
        audioQueue.asyncAfter(deadline: .now() + 0.02) {
            self.playTone(freq: f, duration: 0.22, gain: 0.24)
        }
    }

    /// Dedicated rubbery bouncy balloon boing + bell chime SFX
    func playBalloonHit(combo: Int = 0, isGolden: Bool = false, isBeach: Bool = false) {
        let pitch = 0.94 + Float(min(combo, 9)) * 0.042 + Float.random(in: -0.02...0.02)
        let key = isGolden ? "sfx_balloon_gold" : (isBeach ? "sfx_balloon_beach" : "sfx_balloon_boing")
        if playSfxFile(key, gain: isGolden ? 0.95 : 0.9, rate: pitch) { return }
        let scale: [Double] = [440, 493.88, 523.25, 587.33, 659.25, 783.99, 880, 1046.5, 1174.66]
        let chime = scale[min(combo, scale.count - 1)]
        playTone(freq: 190, duration: 0.14, gain: 0.32, freqEnd: 460)
        audioQueue.asyncAfter(deadline: .now() + 0.02) {
            self.playTone(freq: chime, duration: 0.24, gain: 0.22)
        }
    }

    func playMilestone() {
        if playSfxFile("sfx_balloon_milestone", gain: 0.96, rate: 1.0) { return }
        let notes = [523.25, 659.25, 783.99, 1046.5, 1318.5]
        for (idx, n) in notes.enumerated() {
            audioQueue.asyncAfter(deadline: .now() + Double(idx) * 0.055) {
                self.playTone(freq: n, duration: 0.28, gain: 0.22)
            }
        }
    }

    func playGoldenPop() {
        if playSfxFile("sfx_golden_pop", gain: 0.94, rate: 1.0) { return }
        let notes = [783.99, 1046.5, 1318.5, 1567.98]
        for (idx, n) in notes.enumerated() {
            audioQueue.asyncAfter(deadline: .now() + Double(idx) * 0.04) {
                self.playTone(freq: n, duration: 0.28, gain: 0.22)
            }
        }
    }

    func playRainbowBlast() {
        if playSfxFile("sfx_rainbow_blast", gain: 0.96, rate: 1.0) { return }
        playTone(freq: 220, duration: 0.34, gain: 0.24, freqEnd: 880)
        let notes = [523.25, 659.25, 783.99, 1046.5, 1318.5, 1567.98]
        for (idx, n) in notes.enumerated() {
            audioQueue.asyncAfter(deadline: .now() + Double(idx) * 0.035) {
                self.playTone(freq: n, duration: 0.34, gain: 0.2)
            }
        }
    }

    func playFeverStart() {
        let notes = [523.25, 659.25, 783.99, 1046.5]
        for (idx, n) in notes.enumerated() {
            audioQueue.asyncAfter(deadline: .now() + Double(idx) * 0.07) {
                self.playTone(freq: n, duration: 0.22, gain: 0.24)
            }
        }
    }

    func playBounce() {
        if playSfxFile("sfx_balloon_bounce", gain: 0.74, rate: Float.random(in: 0.94...1.08)) { return }
        playTone(freq: 240, duration: 0.16, gain: 0.25, freqEnd: 460)
    }

    func playBossHit(_ step: Int) {
        if playSfxFile("sfx_boss_hit", gain: 0.92, rate: 0.92 + Float(min(step, 12)) * 0.035) { return }
        let base = 300.0 + Double(step) * 55.0
        playTone(freq: base, duration: 0.14, gain: 0.28, freqEnd: base * 1.35)
    }

    func playBossSmash() {
        if playSfxFile("sfx_boss_smash", gain: 1.0, rate: 1.0) { return }
        playTone(freq: 180, duration: 0.36, gain: 0.32, freqEnd: 55)
        playRainbowBlast()
    }

    func playFreezeCue() {
        if playSfxFile("sfx_dj_scratch", gain: 0.96, rate: 1.0) { return }
        playTone(freq: 880, duration: 0.1, gain: 0.16)
        audioQueue.asyncAfter(deadline: .now() + 0.1) {
            self.playTone(freq: 440, duration: 0.22, gain: 0.16)
        }
    }

    func playClubAirhorn() {
        if playSfxFile("sfx_club_airhorn", gain: 0.84, rate: 1.0) { return }
        playFeverStart()
    }

    func playDiscoClear() {
        if playSfxFile("sfx_disco_clear", gain: 0.94, rate: 1.0) { return }
        playGoldenPop()
    }

    func playFreezeWiggle() {
        playTone(freq: 360, duration: 0.14, gain: 0.2, freqEnd: 240)
        audioQueue.asyncAfter(deadline: .now() + 0.06) {
            self.playTone(freq: 420, duration: 0.14, gain: 0.22, freqEnd: 290)
        }
    }

    func playFreezeFail() {
        playTone(freq: 280, duration: 0.18, gain: 0.24, freqEnd: 220)
        audioQueue.asyncAfter(deadline: .now() + 0.16) {
            self.playTone(freq: 210, duration: 0.34, gain: 0.26, freqEnd: 135)
        }
    }

    func playMoleBonk(combo: Int = 0, isGold: Bool = false) {
        let rate = (isGold ? 1.12 : 0.96) + Float(min(combo, 8)) * 0.035
        if playSfxFile("sfx_mole_bonk", gain: isGold ? 0.96 : 0.90, rate: rate) { return }
        playTone(freq: isGold ? 420 : 280, duration: 0.11, gain: 0.30, freqEnd: isGold ? 960 : 620)
        audioQueue.asyncAfter(deadline: .now() + 0.03) {
            self.playTone(freq: isGold ? 1174.66 : 783.99, duration: 0.20, gain: 0.24)
        }
    }

    func playJumpStar() {
        if playSfxFile("sfx_jump_star", gain: 0.94, rate: Float.random(in: 0.96...1.08)) { return }
        playTone(freq: 360, duration: 0.16, gain: 0.26, freqEnd: 880)
        audioQueue.asyncAfter(deadline: .now() + 0.07) {
            self.playTone(freq: 1046.5, duration: 0.22, gain: 0.24, freqEnd: 1318.5)
        }
    }

    func playWindWhoosh() {
        if playSfxFile("sfx_wind_whoosh", gain: 0.85, rate: Float.random(in: 0.92...1.08)) { return }
        playTone(freq: 210, duration: 0.26, gain: 0.18, freqEnd: 460)
        audioQueue.asyncAfter(deadline: .now() + 0.18) {
            self.playTone(freq: 440, duration: 0.28, gain: 0.15, freqEnd: 190)
        }
    }

    func playFanfare() {
        let seq: [(Double, Double, Double)] = [
            (523.25, 0.18, 0.0),
            (659.25, 0.18, 0.14),
            (783.99, 0.18, 0.28),
            (1046.5, 0.65, 0.42),
        ]
        for (f, d, delay) in seq {
            audioQueue.asyncAfter(deadline: .now() + delay) {
                self.playTone(freq: f, duration: d, gain: 0.22)
            }
        }
    }

    /// Crisp camera shutter ("찰칵!") synthesized on audioQueue for Polaroid snapshot capture.
    func playShutter() {
        let vol = volume
        guard vol > 0.01 else { return }
        audioQueue.async {
            self.ensureRunning()
            let duration = 0.12
            let frameCount = AVAudioFrameCount(self.sampleRate * duration)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: self.format, frameCapacity: frameCount) else { return }
            buffer.frameLength = frameCount
            guard let data = buffer.floatChannelData?[0] else { return }

            let n = Int(frameCount)
            var seed: UInt32 = 0x51A7_7E21
            for i in 0..<n {
                let t = Double(i) / self.sampleRate
                // Fast deterministic LCG white noise for mechanical shutter click
                seed = seed &* 1664525 &+ 1013904223
                let noise = (Double(seed & 0xFFFF) / 32768.0) - 1.0
                // Dual click envelope: initial leaf open (0..0.025s) + second crisp snap (0.045..0.09s)
                let env1 = t < 0.032 ? exp(-t * 140.0) : 0.0
                let dt2 = t - 0.048
                let env2 = dt2 >= 0 ? exp(-dt2 * 110.0) : 0.0
                let clickTone = sin(2.0 * .pi * 2400.0 * t) * 0.35 + sin(2.0 * .pi * 4100.0 * t) * 0.25
                let sample = (noise * 0.72 + clickTone * 0.28) * (env1 * 0.85 + env2 * 1.0)
                let tailFade = i > n - 120 ? Double(n - i) / 120.0 : 1.0
                data[i] = Float(sample * tailFade) * 0.34 * vol
            }
            self.sfxPlayer.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        }
    }

    func playCoopFanfare() {
        let notes: [(Double, Double, Double)] = [
            (659.25, 0.14, 0.0),
            (783.99, 0.14, 0.07),
            (1046.5, 0.18, 0.14),
            (1318.5, 0.34, 0.22),
        ]
        for (f, d, delay) in notes {
            audioQueue.asyncAfter(deadline: .now() + delay) {
                self.playTone(freq: f, duration: d, gain: 0.24)
            }
        }
    }

    func playWallPass() {
        playTone(freq: 440, duration: 0.12, gain: 0.24, freqEnd: 1174.66)
        audioQueue.asyncAfter(deadline: .now() + 0.08) {
            self.playTone(freq: 1046.5, duration: 0.26, gain: 0.25, freqEnd: 1567.98)
        }
    }
}
