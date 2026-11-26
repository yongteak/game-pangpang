/**
 * Multi-track BGM (.m4a seamless loops) + Web Audio API SFX engine.
 * Strict `bgmAllowed` lifecycle gate prevents BGM from EVER leaking into Home/Select/Background!
 */

const BGM_TRACKS = {
  fruit: "./assets/audio/bgm_fruit.m4a",
  balloon: "./assets/audio/bgm_balloon.m4a",
  freeze: "./assets/audio/bgm_freeze.m4a",
  adventure: "./assets/audio/bgm_adventure.m4a",
};

const SFX_FILES = {
  swoosh: "./assets/audio/sfx_swoosh.m4a",
  slice: "./assets/audio/sfx_slice.m4a",
  tough_hit: "./assets/audio/sfx_tough_hit.m4a",
  golden_pop: "./assets/audio/sfx_golden_pop.m4a",
  rainbow_blast: "./assets/audio/sfx_rainbow_blast.m4a",
  boss_appear: "./assets/audio/sfx_boss_appear.m4a",
  boss_hit: "./assets/audio/sfx_boss_hit.m4a",
  boss_smash: "./assets/audio/sfx_boss_smash.m4a",
  balloon_boing: "./assets/audio/sfx_balloon_boing.m4a",
  balloon_beach: "./assets/audio/sfx_balloon_beach.m4a",
  balloon_gold: "./assets/audio/sfx_balloon_gold.m4a",
  balloon_bounce: "./assets/audio/sfx_balloon_bounce.m4a",
  balloon_milestone: "./assets/audio/sfx_balloon_milestone.m4a",
  dj_scratch: "./assets/audio/sfx_dj_scratch.m4a",
  club_airhorn: "./assets/audio/sfx_club_airhorn.m4a",
  disco_clear: "./assets/audio/sfx_disco_clear.m4a",
  mole_bonk: "./assets/audio/sfx_mole_bonk.m4a",
  jump_star: "./assets/audio/sfx_jump_star.m4a",
  wind_whoosh: "./assets/audio/sfx_wind_whoosh.m4a",
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
    this.sfxBuffers = {};
    this.sfxLoading = false;

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
    if (this.ctx && !this.sfxLoading) {
      this.preloadSfxBuffers();
    }
  }

  async preloadSfxBuffers() {
    this.sfxLoading = true;
    await Promise.all(
      Object.entries(SFX_FILES).map(async ([key, url]) => {
        try {
          const res = await fetch(url);
          const arr = await res.arrayBuffer();
          this.sfxBuffers[key] = await this.ctx.decodeAudioData(arr);
        } catch {}
      })
    );
  }

  playBuffer(key, { gain = 0.85, rate = 1.0 } = {}) {
    if (this.volume <= 0.01) return false;
    this.ensureContext();
    const buf = this.sfxBuffers[key];
    if (!this.ctx || !buf) return false;
    const src = this.ctx.createBufferSource();
    const amp = this.ctx.createGain();
    src.buffer = buf;
    src.playbackRate.value = Math.max(0.7, Math.min(1.6, rate));
    amp.gain.value = Math.min(1.2, gain * this.volume);
    src.connect(amp);
    amp.connect(this.ctx.destination);
    src.start(0);
    return true;
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

  playSwoosh() {
    this.playBuffer("swoosh", { gain: 0.09, rate: 0.94 + Math.random() * 0.18 });
  }

  playToughHit(step = 1) {
    if (this.playBuffer("tough_hit", { gain: 0.88, rate: 0.96 + step * 0.12 })) return;
    this.playBossHit(step);
  }

  playBossAppear() {
    if (this.playBuffer("boss_appear", { gain: 0.92, rate: 1.0 })) return;
    this.playFeverStart();
  }

  playPop(combo = 0) {
    const pitch = 0.94 + Math.min(combo, 9) * 0.048 + (Math.random() - 0.5) * 0.04;
    if (this.playBuffer("slice", { gain: 0.88, rate: pitch })) return;
    const scale = [523.25, 587.33, 659.25, 783.99, 880.0, 987.77, 1046.5, 1174.66, 1318.5, 1567.98];
    const f = scale[Math.min(combo, scale.length - 1)];
    this.tone(380 + Math.min(combo, 8) * 35, 0.1, { type: "sine", gain: 0.28, freqEnd: 980 });
    this.tone(f, 0.24, { type: "triangle", gain: 0.25, delay: 0.02 });
  }

  /** Dedicated bouncy rubbery balloon boing + airy chime SFX */
  playBalloonHit(combo = 0, isGolden = false, isBeach = false) {
    const pitch = 0.94 + Math.min(combo, 9) * 0.042 + (Math.random() - 0.5) * 0.04;
    const key = isGolden ? "balloon_gold" : isBeach ? "balloon_beach" : "balloon_boing";
    if (this.playBuffer(key, { gain: isGolden ? 0.94 : 0.88, rate: pitch })) return;
    const scale = [440, 493.88, 523.25, 587.33, 659.25, 783.99, 880, 1046.5, 1174.66];
    const chime = scale[Math.min(combo, scale.length - 1)];
    this.tone(190, 0.14, { type: "sine", gain: 0.34, freqEnd: 460 });
    this.tone(chime, 0.24, { type: "triangle", gain: 0.22, delay: 0.02 });
  }

  playMilestone() {
    if (this.playBuffer("balloon_milestone", { gain: 0.95, rate: 1.0 })) return;
    [523.25, 659.25, 783.99, 1046.5, 1318.5].forEach((n, i) => {
      this.tone(n, 0.3, { type: "triangle", gain: 0.24, delay: i * 0.055 });
    });
  }

  playGoldenPop() {
    if (this.playBuffer("golden_pop", { gain: 0.92, rate: 1.0 })) return;
    [783.99, 1046.5, 1318.5, 1567.98].forEach((n, i) => {
      this.tone(n, 0.3, { type: "triangle", gain: 0.24, delay: i * 0.035 });
    });
  }

  playRainbowBlast() {
    if (this.playBuffer("rainbow_blast", { gain: 0.95, rate: 1.0 })) return;
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
    if (this.playBuffer("balloon_bounce", { gain: 0.72, rate: 0.94 + Math.random() * 0.14 })) return;
    this.tone(240, 0.16, { type: "sine", gain: 0.26, freqEnd: 460 });
  }

  playBossHit(step = 0) {
    if (this.playBuffer("boss_hit", { gain: 0.9, rate: 0.92 + Math.min(step, 12) * 0.035 })) return;
    const base = 300 + step * 55;
    this.tone(base, 0.14, { type: "triangle", gain: 0.28, freqEnd: base * 1.4 });
  }

  playBossSmash() {
    if (this.playBuffer("boss_smash", { gain: 0.98, rate: 1.0 })) return;
    this.tone(180, 0.35, { type: "sawtooth", gain: 0.22, freqEnd: 55 });
    [523.25, 659.25, 783.99, 1046.5, 1318.5].forEach((n, idx) => {
      this.tone(n, 0.35, { type: "triangle", gain: 0.2, delay: idx * 0.045 });
    });
  }

  playFreezeCue() {
    if (this.playBuffer("dj_scratch", { gain: 0.95, rate: 1.0 })) return;
    this.tone(880, 0.1, { type: "square", gain: 0.12 });
    this.tone(440, 0.22, { type: "square", gain: 0.12, delay: 0.1 });
  }

  playClubAirhorn() {
    if (this.playBuffer("club_airhorn", { gain: 0.82, rate: 1.0 })) return;
    this.playFeverStart();
  }

  playDiscoClear() {
    if (this.playBuffer("disco_clear", { gain: 0.92, rate: 1.0 })) return;
    this.playGoldenPop();
  }

  playFreezeWiggle() {
    // Funny cartoon wobble alert when player wiggles during FREEZE!
    this.tone(360, 0.14, { type: "sawtooth", gain: 0.16, freqEnd: 240 });
    this.tone(420, 0.14, { type: "triangle", gain: 0.18, freqEnd: 290, delay: 0.06 });
  }

  playFreezeFail() {
    // Comical "Bzz-bzz!" caught buzzer (playful, not scary for kids)
    this.tone(280, 0.18, { type: "sawtooth", gain: 0.18, freqEnd: 220 });
    this.tone(210, 0.34, { type: "sawtooth", gain: 0.2, freqEnd: 135, delay: 0.16 });
  }

  playMoleBonk(combo = 0) {
    const rate = 0.94 + Math.min(combo, 8) * 0.045 + (Math.random() - 0.5) * 0.04;
    if (this.playBuffer("mole_bonk", { gain: 0.92, rate })) return;
    // Playful wooden pop + rising chime fallback
    this.tone(310, 0.09, { type: "sine", gain: 0.32, freqEnd: 150 });
    this.tone(560 + Math.min(combo, 8) * 45, 0.16, { type: "triangle", gain: 0.25, freqEnd: 920, delay: 0.02 });
  }

  playJumpStar(combo = 0) {
    const rate = 0.96 + Math.min(combo, 6) * 0.05;
    if (this.playBuffer("jump_star", { gain: 0.92, rate })) return;
    // Sparkling ascending star chime fallback
    [587.33, 880, 1174.66, 1567.98].forEach((f, i) => {
      this.tone(f, 0.22, { type: "triangle", gain: 0.22, delay: i * 0.032 });
    });
  }

  playWindWhoosh() {
    if (this.playBuffer("wind_whoosh", { gain: 0.8, rate: 0.94 + Math.random() * 0.12 })) return;
    // Soft sweeping wind gust fallback (bandpass noise + airy whistle)
    if (this.volume <= 0.01) return;
    this.ensureContext();
    if (!this.ctx) return;
    const now = this.ctx.currentTime;
    const dur = 0.65;
    const bufferSize = Math.floor(this.ctx.sampleRate * dur);
    const noiseBuf = this.ctx.createBuffer(1, bufferSize, this.ctx.sampleRate);
    const data = noiseBuf.getChannelData(0);
    for (let i = 0; i < bufferSize; i++) data[i] = Math.random() * 2 - 1;
    const src = this.ctx.createBufferSource();
    src.buffer = noiseBuf;
    const filter = this.ctx.createBiquadFilter();
    filter.type = "bandpass";
    filter.Q.value = 2.4;
    filter.frequency.setValueAtTime(240, now);
    filter.frequency.exponentialRampToValueAtTime(920, now + dur * 0.45);
    filter.frequency.exponentialRampToValueAtTime(300, now + dur);
    const amp = this.ctx.createGain();
    amp.gain.setValueAtTime(0.001, now);
    amp.gain.linearRampToValueAtTime(0.26 * this.volume, now + dur * 0.3);
    amp.gain.exponentialRampToValueAtTime(0.001, now + dur);
    src.connect(filter);
    filter.connect(amp);
    amp.connect(this.ctx.destination);
    src.start(now);
    src.stop(now + dur + 0.02);
    this.tone(240, 0.42, { type: "sine", gain: 0.09, freqEnd: 520 });
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
    if (this.fadeTimer) {
      clearInterval(this.fadeTimer);
      this.fadeTimer = null;
    }
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

  fadeOutBgm(durationMs = 1100) {
    if (!this.bgmAudio) {
      this.stopBgm();
      return;
    }
    if (this.fadeTimer) clearInterval(this.fadeTimer);
    const audio = this.bgmAudio;
    const startVol = audio.volume;
    const steps = 20;
    let step = 0;
    this.fadeTimer = window.setInterval(() => {
      step++;
      const ratio = Math.max(0, 1 - step / steps);
      try {
        audio.volume = startVol * ratio;
      } catch {}
      if (step >= steps || this.bgmAudio !== audio) {
        clearInterval(this.fadeTimer);
        this.fadeTimer = null;
        if (this.bgmAudio === audio) this.stopBgm();
      }
    }, Math.max(20, Math.round(durationMs / steps)));
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
