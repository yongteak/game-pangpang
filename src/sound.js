/**
 * Multi-track BGM (.m4a seamless loops) + Web Audio API SFX engine.
 * Strict `bgmAllowed` lifecycle gate prevents BGM from EVER leaking into Home/Select/Background!
 */

const BGM_TRACKS = {
  fruit: "./assets/audio/bgm_fruit.m4a",
  balloon: "./assets/audio/bgm_balloon.m4a",
  freeze: "./assets/audio/bgm_freeze.m4a",
};

export class SoundEngine {
  constructor() {
    this.ctx = null;
    this.volume = 0.8;
    this.bgmAllowed = false;
    this.bgmAudio = null;
    this.currentTrack = null;
    this.bgmPaused = false;
    this.fallbackTimer = null;
    this.fallbackStep = 0;

    // Immediately pause BGM if browser tab goes hidden or device sleeps
    document.addEventListener("visibilitychange", () => {
      if (document.hidden) {
        this.pauseBgm();
      } else if (this.bgmAllowed && !this.bgmPaused) {
        this.resumeBgm();
      }
    });
  }

  ensureContext() {
    if (!this.ctx) {
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (AudioCtx) this.ctx = new AudioCtx();
    }
    if (this.ctx && this.ctx.state === "suspended") {
      this.ctx.resume().catch(() => {});
    }
  }

  setVolume(v01) {
    this.volume = Math.max(0, Math.min(1, v01));
    if (this.bgmAudio) {
      this.bgmAudio.volume = Math.min(1, this.volume * 0.52);
    }
  }

  /** Central lifecycle gate — call with `false` whenever leaving In-Game! */
  setBgmAllowed(allowed) {
    this.bgmAllowed = Boolean(allowed);
    if (!this.bgmAllowed) {
      this.stopBgm();
    }
  }

  tone(freq, dur = 0.16, { type = "sine", gain = 0.25, freqEnd = null, delay = 0 } = {}) {
    if (this.volume <= 0.01) return;
    this.ensureContext();
    if (!this.ctx) return;

    const now = this.ctx.currentTime + delay;
    const osc = this.ctx.createOscillator();
    const amp = this.ctx.createGain();
    osc.type = type;
    osc.frequency.setValueAtTime(freq, now);
    if (freqEnd) {
      osc.frequency.exponentialRampToValueAtTime(Math.max(40, freqEnd), now + dur);
    }

    const peak = gain * this.volume;
    amp.gain.setValueAtTime(0.0001, now);
    amp.gain.linearRampToValueAtTime(peak, now + 0.014);
    amp.gain.exponentialRampToValueAtTime(0.0001, now + dur);

    osc.connect(amp);
    amp.connect(this.ctx.destination);
    osc.start(now);
    osc.stop(now + dur + 0.02);
  }

  playClick() {
    this.tone(620, 0.09, { type: "triangle", gain: 0.2, freqEnd: 880 });
  }

  playReadyOk() {
    this.tone(587.33, 0.14, { type: "triangle", gain: 0.24 });
    this.tone(880, 0.2, { type: "triangle", gain: 0.24, delay: 0.08 });
  }

  playCountdown(num) {
    if (num > 0) {
      this.tone(523.25, 0.16, { type: "triangle", gain: 0.26 });
    } else {
      this.tone(783.99, 0.14, { type: "triangle", gain: 0.26 });
      this.tone(1046.5, 0.34, { type: "triangle", gain: 0.28, delay: 0.08 });
    }
  }

  playPop(combo = 0) {
    const scale = [523.25, 587.33, 659.25, 783.99, 880.0, 987.77, 1046.5, 1174.66, 1318.5, 1567.98];
    const f = scale[Math.min(combo, scale.length - 1)];
    this.tone(380 + Math.min(combo, 8) * 35, 0.1, { type: "sine", gain: 0.28, freqEnd: 980 });
    this.tone(f, 0.24, { type: "triangle", gain: 0.25, delay: 0.02 });
    if (combo >= 3) {
      this.tone(f * 1.5, 0.26, { type: "sine", gain: 0.16, delay: 0.04 });
    }
  }

  /** Dedicated bouncy rubbery balloon boing + airy chime SFX */
  playBalloonHit(combo = 0, isGolden = false) {
    const scale = [440, 493.88, 523.25, 587.33, 659.25, 783.99, 880, 1046.5, 1174.66];
    const chime = scale[Math.min(combo, scale.length - 1)];
    // Rubbery elastic boing!
    this.tone(190, 0.14, { type: "sine", gain: 0.34, freqEnd: 460 });
    this.tone(440, 0.12, { type: "sine", gain: 0.18, freqEnd: 310, delay: 0.06 });
    // Sparkling bell chime
    this.tone(chime, 0.24, { type: "triangle", gain: 0.22, delay: 0.02 });
    if (isGolden) {
      this.tone(chime * 1.25, 0.28, { type: "triangle", gain: 0.22, delay: 0.05 });
      this.tone(chime * 1.5, 0.32, { type: "sine", gain: 0.2, delay: 0.09 });
    }
  }

  playMilestone() {
    [523.25, 659.25, 783.99, 1046.5, 1318.5].forEach((n, i) => {
      this.tone(n, 0.3, { type: "triangle", gain: 0.24, delay: i * 0.055 });
    });
  }

  playGoldenPop() {
    [783.99, 1046.5, 1318.5, 1567.98].forEach((n, i) => {
      this.tone(n, 0.3, { type: "triangle", gain: 0.24, delay: i * 0.035 });
    });
  }

  playRainbowBlast() {
    this.tone(220, 0.35, { type: "sawtooth", gain: 0.2, freqEnd: 880 });
    [523.25, 659.25, 783.99, 1046.5, 1318.5, 1567.98, 2093.0].forEach((n, i) => {
      this.tone(n, 0.38, { type: "triangle", gain: 0.2, delay: i * 0.03 });
    });
  }

  playFeverStart() {
    [523.25, 659.25, 783.99, 1046.5].forEach((n, i) => {
      this.tone(n, 0.22, { type: "triangle", gain: 0.24, delay: i * 0.07 });
    });
  }

  playBounce() {
    this.tone(240, 0.16, { type: "sine", gain: 0.26, freqEnd: 460 });
  }

  playBossHit(step = 0) {
    const base = 300 + step * 55;
    this.tone(base, 0.14, { type: "triangle", gain: 0.28, freqEnd: base * 1.4 });
  }

  playBossSmash() {
    this.tone(180, 0.35, { type: "sawtooth", gain: 0.22, freqEnd: 55 });
    [523.25, 659.25, 783.99, 1046.5, 1318.5].forEach((n, idx) => {
      this.tone(n, 0.35, { type: "triangle", gain: 0.2, delay: idx * 0.045 });
    });
  }

  playFreezeCue() {
    this.tone(880, 0.1, { type: "square", gain: 0.12 });
    this.tone(440, 0.22, { type: "square", gain: 0.12, delay: 0.1 });
  }

  playFanfare() {
    const notes = [
      [523.25, 0.18, 0.0],
      [659.25, 0.18, 0.14],
      [783.99, 0.18, 0.28],
      [1046.5, 0.65, 0.42],
      [783.99, 0.65, 0.42],
      [659.25, 0.65, 0.42],
    ];
    notes.forEach(([f, d, delay]) => {
      this.tone(f, d, { type: "triangle", gain: 0.2, delay });
    });
  }

  startBgm(track = "fruit", rate = 1.0) {
    if (!this.bgmAllowed) return;
    const trackKey = BGM_TRACKS[track] ? track : "fruit";

    // If same track is already playing, just smoothly update playbackRate!
    if (this.bgmAudio && this.currentTrack === trackKey && !this.bgmAudio.paused) {
      this.bgmAudio.playbackRate = Math.max(0.85, Math.min(1.3, rate));
      this.bgmAudio.volume = Math.min(1, this.volume * 0.52);
      return;
    }

    this.stopBgm();
    if (!this.bgmAllowed) return;

    this.currentTrack = trackKey;
    this.bgmPaused = false;
    const audio = new Audio(BGM_TRACKS[trackKey]);
    audio.loop = true;
    audio.volume = Math.min(1, this.volume * 0.52);
    audio.playbackRate = Math.max(0.85, Math.min(1.3, rate));
    this.bgmAudio = audio;

    audio.play().catch(() => {
      // Fallback synth if audio file fails to autoplay
      if (this.bgmAllowed && this.bgmAudio === audio) {
        this.startFallbackSynth(Math.round(350 / rate));
      }
    });
  }

  setBgmRate(rate) {
    if (this.bgmAudio) {
      this.bgmAudio.playbackRate = Math.max(0.85, Math.min(1.3, rate));
    }
  }

  pauseBgm() {
    this.bgmPaused = true;
    if (this.bgmAudio) {
      this.bgmAudio.pause();
    }
    this.stopFallbackSynth();
  }

  resumeBgm() {
    if (!this.bgmAllowed) return;
    this.bgmPaused = false;
    if (this.bgmAudio) {
      this.bgmAudio.volume = Math.min(1, this.volume * 0.52);
      this.bgmAudio.play().catch(() => {});
    }
  }

  stopBgm() {
    this.bgmPaused = false;
    this.currentTrack = null;
    if (this.bgmAudio) {
      try {
        this.bgmAudio.pause();
        this.bgmAudio.currentTime = 0;
        this.bgmAudio.src = "";
      } catch {}
      this.bgmAudio = null;
    }
    this.stopFallbackSynth();
  }

  startFallbackSynth(tempoMs = 340) {
    this.stopFallbackSynth();
    const melody = [523.25, 659.25, 783.99, 659.25, 587.33, 659.25, 783.99, 1046.5];
    this.fallbackStep = 0;
    this.fallbackTimer = window.setInterval(() => {
      if (!this.bgmAllowed || this.bgmPaused) {
        this.stopFallbackSynth();
        return;
      }
      const f = melody[this.fallbackStep % melody.length];
      this.tone(f, 0.2, { type: "triangle", gain: 0.065 });
      this.fallbackStep++;
    }, tempoMs);
  }

  stopFallbackSynth() {
    if (this.fallbackTimer) {
      clearInterval(this.fallbackTimer);
      this.fallbackTimer = null;
    }
  }
}
