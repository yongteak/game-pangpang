/**
 * Wii-style cheerful Web Audio API synthesizer (zero external audio files needed).
 */
export class SoundEngine {
  constructor() {
    this.ctx = null;
    this.volume = 0.8;
    this.bgmTimer = null;
    this.bgmStep = 0;
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
    amp.gain.linearRampToValueAtTime(peak, now + 0.015);
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
    const scale = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1174.66];
    const f = scale[combo % scale.length];
    this.tone(360, 0.1, { type: "sine", gain: 0.26, freqEnd: 920 });
    this.tone(f, 0.22, { type: "triangle", gain: 0.22, delay: 0.02 });
  }

  playBounce() {
    this.tone(280, 0.18, { type: "sine", gain: 0.28, freqEnd: 560 });
  }

  playBossHit(step = 0) {
    const base = 300 + step * 70;
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

  startBgm(tempoMs = 360) {
    this.stopBgm();
    const melody = [523.25, 659.25, 783.99, 659.25, 587.33, 659.25, 783.99, 1046.5];
    this.bgmStep = 0;
    this.bgmTimer = window.setInterval(() => {
      const f = melody[this.bgmStep % melody.length];
      this.tone(f, 0.22, { type: "triangle", gain: 0.075 });
      if (this.bgmStep % 2 === 0) {
        this.tone(f / 2, 0.28, { type: "sine", gain: 0.055 });
      }
      this.bgmStep++;
    }, tempoMs);
  }

  stopBgm() {
    if (this.bgmTimer) {
      clearInterval(this.bgmTimer);
      this.bgmTimer = null;
    }
  }
}
