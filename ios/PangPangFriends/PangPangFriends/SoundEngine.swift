import AVFoundation
import Foundation

/// Dual-pipeline audio engine:
/// - Dedicated `AVAudioPlayer` for rich bundled multi-instrument `.m4a` looping BGM tracks
/// - Dedicated `AVAudioEngine` synth for zero-latency Wii/Balloon SFX
/// - Strict `bgmAllowed` main-thread lifecycle gate guarantees ZERO BGM leaks when leaving games!
final class SoundEngine {
    static let shared = SoundEngine()

    private let engine = AVAudioEngine()
    private let sfxPlayer = AVAudioPlayerNode()
    private let sampleRate: Double = 44100
    private var format: AVAudioFormat

    private var bgmPlayer: AVAudioPlayer?
    private var currentTrack: String?
    private var bgmAllowed: Bool = false

    var volume: Float = 0.8 {
        didSet {
            DispatchQueue.main.async {
                self.bgmPlayer?.volume = min(1.0, self.volume * 0.55)
            }
        }
    }

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(sfxPlayer)
        engine.connect(sfxPlayer, to: engine.mainMixerNode, format: format)
        configureAudioSession()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            try engine.start()
            sfxPlayer.play()
        } catch {
            // Simulator or background audio fallback
        }
    }

    private func ensureRunning() {
        if !engine.isRunning { try? engine.start() }
        if !sfxPlayer.isPlaying { sfxPlayer.play() }
    }

    /// Central lifecycle gate: set `false` on Home / Select / Ready / Clear / Background!
    func setBgmAllowed(_ allowed: Bool) {
        let work = {
            self.bgmAllowed = allowed
            if !allowed {
                self.stopBgmImmediate()
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    func startBgm(track: String, rate: Float = 1.0) {
        let work = {
            guard self.bgmAllowed else { return }
            let clampedRate = max(0.85, min(1.3, rate))

            // Smoothly update rate if same track is already playing
            if let bp = self.bgmPlayer, self.currentTrack == track, bp.isPlaying {
                bp.rate = clampedRate
                bp.volume = min(1.0, self.volume * 0.55)
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
                player.volume = min(1.0, self.volume * 0.55)
                player.prepareToPlay()
                player.play()
                self.bgmPlayer = player
                self.currentTrack = track
            } catch {
                // Ignore audio load errors gracefully
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    func setBgmRate(_ rate: Float) {
        DispatchQueue.main.async {
            self.bgmPlayer?.rate = max(0.85, min(1.3, rate))
        }
    }

    func pauseBgm() {
        DispatchQueue.main.async {
            self.bgmPlayer?.pause()
        }
    }

    func resumeBgm() {
        DispatchQueue.main.async {
            guard self.bgmAllowed else { return }
            self.bgmPlayer?.volume = min(1.0, self.volume * 0.55)
            self.bgmPlayer?.play()
        }
    }

    func stopBgm() {
        if Thread.isMainThread {
            stopBgmImmediate()
        } else {
            DispatchQueue.main.async { self.stopBgmImmediate() }
        }
    }

    private func stopBgmImmediate() {
        bgmPlayer?.stop()
        bgmPlayer = nil
        currentTrack = nil
    }

    // MARK: - Low-latency Synthesized SFX
    func playTone(freq: Double, duration: Double, gain: Float = 0.25, freqEnd: Double? = nil) {
        guard volume > 0.01 else { return }
        ensureRunning()

        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        guard let data = buffer.floatChannelData?[0] else { return }

        let amp = gain * volume
        let endF = freqEnd ?? freq
        for i in 0..<Int(frameCount) {
            let p = Double(i) / Double(max(1, frameCount))
            let t = Double(i) / sampleRate
            let f = freq + (endF - freq) * p
            let env = Float(min(1.0, p / 0.03) * exp(-4.8 * p))
            let wave = sin(2.0 * .pi * f * t) + 0.22 * sin(2.0 * .pi * f * 2.0 * t) * exp(-8.0 * p)
            data[i] = Float(wave) * amp * env
        }
        sfxPlayer.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    func playClick() {
        playTone(freq: 620, duration: 0.08, gain: 0.2, freqEnd: 880)
    }

    func playReadyOk() {
        playTone(freq: 587.33, duration: 0.14, gain: 0.24)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.playTone(freq: 880, duration: 0.2, gain: 0.24)
        }
    }

    func playCountdown(_ num: Int) {
        if num > 0 {
            playTone(freq: 523.25, duration: 0.16, gain: 0.25)
        } else {
            playTone(freq: 783.99, duration: 0.14, gain: 0.26)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                self.playTone(freq: 1046.5, duration: 0.32, gain: 0.28)
            }
        }
    }

    func playPop(combo: Int = 0) {
        let scale: [Double] = [523.25, 587.33, 659.25, 783.99, 880.0, 987.77, 1046.5, 1174.66, 1318.5, 1567.98]
        let f = scale[min(combo, scale.count - 1)]
        playTone(freq: 380 + Double(min(combo, 8)) * 35, duration: 0.1, gain: 0.26, freqEnd: 980)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            self.playTone(freq: f, duration: 0.22, gain: 0.24)
        }
    }

    /// Dedicated rubbery bouncy balloon boing + bell chime SFX
    func playBalloonHit(combo: Int = 0, isGolden: Bool = false) {
        let scale: [Double] = [440, 493.88, 523.25, 587.33, 659.25, 783.99, 880, 1046.5, 1174.66]
        let chime = scale[min(combo, scale.count - 1)]
        playTone(freq: 190, duration: 0.14, gain: 0.32, freqEnd: 460)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.playTone(freq: 430, duration: 0.11, gain: 0.16, freqEnd: 300)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            self.playTone(freq: chime, duration: 0.24, gain: 0.22)
        }
        if isGolden {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                self.playTone(freq: chime * 1.25, duration: 0.26, gain: 0.22)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                self.playTone(freq: chime * 1.5, duration: 0.30, gain: 0.20)
            }
        }
    }

    func playMilestone() {
        let notes = [523.25, 659.25, 783.99, 1046.5, 1318.5]
        for (idx, n) in notes.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(idx) * 0.055) {
                self.playTone(freq: n, duration: 0.28, gain: 0.22)
            }
        }
    }

    func playGoldenPop() {
        let notes = [783.99, 1046.5, 1318.5, 1567.98]
        for (idx, n) in notes.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(idx) * 0.04) {
                self.playTone(freq: n, duration: 0.28, gain: 0.22)
            }
        }
    }

    func playRainbowBlast() {
        playTone(freq: 220, duration: 0.34, gain: 0.24, freqEnd: 880)
        let notes = [523.25, 659.25, 783.99, 1046.5, 1318.5, 1567.98]
        for (idx, n) in notes.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(idx) * 0.035) {
                self.playTone(freq: n, duration: 0.34, gain: 0.2)
            }
        }
    }

    func playFeverStart() {
        let notes = [523.25, 659.25, 783.99, 1046.5]
        for (idx, n) in notes.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(idx) * 0.07) {
                self.playTone(freq: n, duration: 0.22, gain: 0.24)
            }
        }
    }

    func playBounce() {
        playTone(freq: 240, duration: 0.16, gain: 0.25, freqEnd: 460)
    }

    func playBossHit(_ step: Int) {
        let base = 300.0 + Double(step) * 55.0
        playTone(freq: base, duration: 0.14, gain: 0.28, freqEnd: base * 1.35)
    }

    func playBossSmash() {
        playTone(freq: 180, duration: 0.36, gain: 0.32, freqEnd: 55)
        playRainbowBlast()
    }

    func playFreezeCue() {
        playTone(freq: 880, duration: 0.1, gain: 0.16)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.playTone(freq: 440, duration: 0.22, gain: 0.16)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.playTone(freq: f, duration: d, gain: 0.22)
            }
        }
    }
}
