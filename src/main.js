import { SoundEngine } from "./sound.js";
import { PoseTracker } from "./tracker.js";
import { MiniGameEngine } from "./games.js";
import { PixiGameRenderer } from "./pixiRenderer.js";

const STORAGE_KEY = "pangpang_friends_settings_v1";

const DEFAULT_SETTINGS = {
  players: 2,
  quietMode: true,
  speed: "normal",
  volume: 80,
  devMode: false,
};

function loadSettings() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? { ...DEFAULT_SETTINGS, ...JSON.parse(raw) } : { ...DEFAULT_SETTINGS };
  } catch {
    return { ...DEFAULT_SETTINGS };
  }
}

function saveSettings(s) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(s));
  } catch {}
}

function loadImg(src) {
  const im = new Image();
  im.src = src;
  return im;
}

class PangPangApp {
  constructor() {
    this.settings = loadSettings();
    this.sound = new SoundEngine();
    this.sound.setVolume(this.settings.volume / 100);

    this.screen = "home";
    this.selectedGame = "fruit";
    this.cameraReady = false;
    this.paused = false;
    this.lastTime = performance.now();

    this.readyHold = [0, 0];
    this.countdownVal = 3;
    this.countdownTimer = 0;

    // 3D clay mascot head badges for Ready Check AR capsules (시안 3번 1:1)
    this.mascotHeads = [
      loadImg("./assets/momo_head.png"),
      loadImg("./assets/popo_head.png"),
    ];

    this.el = {
      viewport: document.getElementById("stage-viewport"),
      video: document.getElementById("camera-video"),
      canvas: document.getElementById("game-canvas"),
      pixiLayer: document.getElementById("pixi-layer"),
      screens: {
        home: document.getElementById("screen-home"),
        select: document.getElementById("screen-select"),
        ready: document.getElementById("screen-ready"),
        ingame: document.getElementById("screen-ingame"),
        clear: document.getElementById("screen-clear"),
      },
      homeMascots: document.getElementById("home-mascots"),
      mascotMomo: document.getElementById("mascot-momo"),
      mascotPopo: document.getElementById("mascot-popo"),
      homeToggle1p: document.getElementById("home-toggle-1p"),
      homeToggle2p: document.getElementById("home-toggle-2p"),
      selectToggle1p: document.getElementById("select-toggle-1p"),
      selectToggle2p: document.getElementById("select-toggle-2p"),
      noiseBanner: document.getElementById("noise-mode-banner"),
      freezeMeta: document.getElementById("freeze-meta"),
      readyLiveLabel: document.getElementById("ready-live-label"),
      readyBanner: document.getElementById("ready-banner"),
      countdownRing: document.getElementById("countdown-ring"),
      countdownNum: document.getElementById("countdown-num"),
      cameraStatusPill: document.getElementById("camera-status-pill"),
      progressDots: document.getElementById("progress-dots"),
      scorePill: document.getElementById("score-pill"),
      scoreValue: document.getElementById("score-value"),
      ingameCallout: document.getElementById("ingame-callout"),
      clearSummary: document.getElementById("clear-summary"),
      modalSettings: document.getElementById("modal-settings"),
      modalPause: document.getElementById("modal-pause"),
      setPlayers: document.getElementById("set-players"),
      setQuiet: document.getElementById("set-quiet"),
      setSpeed: document.getElementById("set-speed"),
      setVolume: document.getElementById("set-volume"),
      setDevMode: document.getElementById("set-dev-mode"),
      tvGuideTip: document.getElementById("tv-guide-tip"),
      pauseBtn: document.getElementById("btn-pause"),
    };

    this.ctx = this.el.canvas.getContext("2d");
    this.pixi = new PixiGameRenderer(this.el.pixiLayer);
    this.pixi.init();

    this.tracker = new PoseTracker(this.el.video, (msg) => {
      this.el.cameraStatusPill.textContent = msg;
    });

    this.engine = new MiniGameEngine(this.sound, {
      onScore: (val) => {
        this.el.scoreValue.textContent = String(val);
        this.el.scorePill.classList.remove("bump");
        void this.el.scorePill.offsetWidth;
        this.el.scorePill.classList.add("bump");
      },
      onProgress: (done, total) => {
        this.el.progressDots.innerHTML = "";
        for (let i = 0; i < total; i++) {
          const d = document.createElement("span");
          d.className = "pdot" + (i < done ? " done" : "");
          this.el.progressDots.appendChild(d);
        }
      },
      onCallout: (text, autoHideMs = 0) => {
        clearTimeout(this.calloutHideTimer);
        clearTimeout(this.calloutFadeTimer);
        if (!text) {
          this.el.ingameCallout.classList.add("hidden");
          this.el.ingameCallout.classList.remove("fade-out");
        } else {
          this.el.ingameCallout.textContent = text;
          this.el.ingameCallout.classList.remove("hidden", "fade-out");
          if (autoHideMs > 0) {
            this.calloutFadeTimer = setTimeout(() => {
              this.el.ingameCallout.classList.add("fade-out");
            }, autoHideMs);
            this.calloutHideTimer = setTimeout(() => {
              this.el.ingameCallout.classList.add("hidden");
              this.el.ingameCallout.classList.remove("fade-out");
            }, autoHideMs + 480);
          }
        }
      },
      onFinish: (summary) => {
        this.el.clearSummary.textContent = summary;
        this.showScreen("clear");
      },
    });

    this.bindEvents();
    this.syncSettingsUI();
    this.resizeCanvas();
    window.addEventListener("resize", () => this.resizeCanvas());
    requestAnimationFrame((t) => this.loop(t));
  }

  resizeCanvas() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.el.canvas.width = Math.floor(window.innerWidth * dpr);
    this.el.canvas.height = Math.floor(window.innerHeight * dpr);
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    if (this.pixi) this.pixi.resize(window.innerWidth, window.innerHeight);
  }

  bindEvents() {
    [this.el.homeToggle1p, this.el.homeToggle2p].forEach((btn) => {
      btn.addEventListener("click", () => {
        this.sound.playClick();
        this.settings.players = Number(btn.dataset.players);
        saveSettings(this.settings);
        this.syncSettingsUI();
      });
    });

    // 홈 캐릭터를 톡톡 건드리면 점프 + 귀여운 효과음!
    [this.el.mascotMomo, this.el.mascotPopo].forEach((m, idx) => {
      m.addEventListener("click", () => {
        this.sound.playPop(idx * 2 + 1);
        this.triggerMascotHop(m);
      });
    });

    document.getElementById("btn-start").addEventListener("click", () => {
      this.sound.playClick();
      this.showScreen("select");
    });

    document.getElementById("btn-fullscreen").addEventListener("click", () => {
      this.sound.playClick();
      if (!document.fullscreenElement) {
        document.documentElement.requestFullscreen?.().catch(() => {});
      } else {
        document.exitFullscreen?.().catch(() => {});
      }
    });

    document.getElementById("btn-back-home").addEventListener("click", () => {
      this.sound.playClick();
      this.showScreen("home");
    });

    // Select screen 1P / 2P segmented toggle
    [this.el.selectToggle1p, this.el.selectToggle2p].forEach((btn) => {
      btn.addEventListener("click", () => {
        this.sound.playClick();
        this.settings.players = Number(btn.dataset.players);
        saveSettings(this.settings);
        this.syncSettingsUI();
      });
    });

    document.querySelectorAll(".game-card").forEach((card) => {
      card.addEventListener("pointerenter", () => {
        document.querySelectorAll(".game-card").forEach((c) => c.classList.remove("featured"));
        card.classList.add("featured");
      });
      card.addEventListener("click", () => {
        this.sound.playClick();
        this.selectedGame = card.dataset.game;
        this.enterReadyScreen();
      });
    });

    document.getElementById("btn-ready-back").addEventListener("click", () => {
      this.sound.playClick();
      this.showScreen("select");
    });
    document.getElementById("btn-ready-skip").addEventListener("click", () => {
      this.sound.playClick();
      this.startCountdown();
    });

    ["btn-open-settings-home", "btn-open-settings-select"].forEach((id) => {
      document.getElementById(id).addEventListener("click", () => {
        this.sound.playClick();
        this.el.modalSettings.classList.remove("hidden");
      });
    });
    document.getElementById("btn-close-settings").addEventListener("click", () => {
      this.sound.playClick();
      this.el.modalSettings.classList.add("hidden");
    });
    this.el.modalSettings.addEventListener("click", (e) => {
      if (e.target === this.el.modalSettings) this.el.modalSettings.classList.add("hidden");
    });

    this.el.setPlayers.querySelectorAll("button").forEach((b) => {
      b.addEventListener("click", () => {
        this.sound.playClick();
        this.settings.players = Number(b.dataset.val);
        saveSettings(this.settings);
        this.syncSettingsUI();
      });
    });
    this.el.setQuiet.addEventListener("change", () => {
      this.sound.playClick();
      this.settings.quietMode = this.el.setQuiet.checked;
      saveSettings(this.settings);
      this.syncSettingsUI();
    });
    this.el.setSpeed.querySelectorAll("button").forEach((b) => {
      b.addEventListener("click", () => {
        this.sound.playClick();
        this.settings.speed = b.dataset.val;
        saveSettings(this.settings);
        this.syncSettingsUI();
      });
    });
    this.el.setVolume.addEventListener("input", () => {
      this.settings.volume = Number(this.el.setVolume.value);
      this.sound.setVolume(this.settings.volume / 100);
      saveSettings(this.settings);
    });
    this.el.setDevMode.addEventListener("change", () => {
      this.sound.playClick();
      this.settings.devMode = this.el.setDevMode.checked;
      saveSettings(this.settings);
      // 모드 전환 시 다음 게임 진입 때 카메라/마우스 트래커 재초기화
      if (this.settings.devMode) {
        this.tracker.stop();
        this.tracker.mode = "pointer";
      }
      this.cameraReady = false;
      this.syncSettingsUI();
    });
    document.getElementById("btn-tv-guide").addEventListener("click", () => {
      this.sound.playClick();
      this.el.tvGuideTip.classList.toggle("hidden");
    });

    // 즉시 클릭으로 바로 일시정지!
    this.el.pauseBtn.addEventListener("click", () => {
      this.sound.playClick();
      this.paused = true;
      this.sound.pauseBgm();
      this.el.modalPause.classList.remove("hidden");
    });

    document.getElementById("btn-resume").addEventListener("click", () => {
      this.sound.playClick();
      this.paused = false;
      this.el.modalPause.classList.add("hidden");
      this.sound.resumeBgm();
    });
    document.getElementById("btn-quit-to-select").addEventListener("click", () => {
      this.sound.playClick();
      this.paused = false;
      this.sound.setBgmAllowed(false);
      this.engine.stop();
      this.el.modalPause.classList.add("hidden");
      this.showScreen("select");
    });

    document.getElementById("btn-replay").addEventListener("click", () => {
      this.sound.playClick();
      this.startCountdown();
    });
    document.getElementById("btn-other-game").addEventListener("click", () => {
      this.sound.playClick();
      this.engine.stop();
      this.showScreen("select");
    });

    const updatePointer = (clientX, clientY) => {
      const x = Math.max(0, Math.min(1, clientX / window.innerWidth));
      const y = Math.max(0, Math.min(1, clientY / window.innerHeight));
      this.tracker.setPointer(x, y, true);
    };
    window.addEventListener("pointermove", (e) => updatePointer(e.clientX, e.clientY));
    window.addEventListener("pointerdown", (e) => updatePointer(e.clientX, e.clientY));
  }

  triggerMascotHop(node) {
    if (!node) return;
    node.classList.remove("happy-hop");
    void node.offsetWidth;
    node.classList.add("happy-hop");
    setTimeout(() => node.classList.remove("happy-hop"), 560);
  }

  syncSettingsUI() {
    const p = this.settings.players;
    this.el.homeToggle1p.classList.toggle("active", p === 1);
    this.el.homeToggle2p.classList.toggle("active", p === 2);
    this.el.homeMascots.classList.toggle("single-player", p === 1);
    this.el.mascotPopo.classList.toggle("hidden-p2", p === 1);
    this.el.selectToggle1p.classList.toggle("active", p === 1);
    this.el.selectToggle2p.classList.toggle("active", p === 2);
    this.el.readyLiveLabel.textContent = this.settings.devMode ? `🛠️ DEV · ${p}P` : `LIVE · ${p}P`;

    this.el.setPlayers.querySelectorAll("button").forEach((b) => {
      b.classList.toggle("active", Number(b.dataset.val) === p);
    });
    this.el.setQuiet.checked = this.settings.quietMode;
    this.el.setDevMode.checked = Boolean(this.settings.devMode);
    this.el.noiseBanner.classList.toggle("hidden", !this.settings.quietMode);
    const flameSvg =
      '<svg class="flame-ic" viewBox="0 0 24 24"><path d="M12.7 2.2c.3 2.8-1.4 4.7-2.6 6.2-1.2 1.5-2.1 2.8-2.1 4.9 0 3 2.4 5.5 5.4 5.5 3.1 0 5.6-2.5 5.6-5.7 0-2.8-1.4-5.1-3.3-7.1-.2 1.4-.9 2.3-1.8 2.8.5-2.1-.1-4.8-1.2-6.6z"/></svg>';
    this.el.freezeMeta.innerHTML = this.settings.quietMode
      ? `<span class="intensity-pill level-1" title="운동 강도"><span class="flames">${flameSvg}</span>살살</span>`
      : `<span class="intensity-pill level-3" title="운동 강도"><span class="flames">${flameSvg}${flameSvg}${flameSvg}</span>힘껏</span>`;

    this.el.setSpeed.querySelectorAll("button").forEach((b) => {
      b.classList.toggle("active", b.dataset.val === this.settings.speed);
    });
    this.el.setVolume.value = String(this.settings.volume);
  }

  showScreen(name) {
    this.screen = name;
    // 인게임 화면을 벗어나면 무조건 BGM 및 게임 루프 타이머 완전 차단!
    const isPlaying = name === "ingame";
    this.sound.setBgmAllowed(isPlaying);
    if (!isPlaying && name !== "clear") {
      this.engine.stop();
    }

    Object.entries(this.el.screens).forEach(([k, node]) => {
      node.classList.toggle("active", k === name || (name === "countdown" && k === "ready"));
    });

    const usesCamera = ["ready", "countdown", "ingame", "clear"].includes(name);
    this.el.viewport.classList.toggle("hidden", !usesCamera);
    this.pixi.setVisible(["ingame", "clear"].includes(name));
  }

  async enterReadyScreen() {
    this.readyHold = [0, 0];
    this.el.countdownRing.classList.add("hidden");
    this.el.readyBanner.innerHTML =
      this.settings.players === 2
        ? "모모·포포 자리에 서서 <strong>만세!</strong> 해주세요"
        : "모모 자리에 서서 <strong>만세!</strong> 해주세요";
    this.showScreen("ready");

    if (!this.cameraReady) {
      await this.tracker.init(this.settings.players, { forcePointer: Boolean(this.settings.devMode) });
      this.cameraReady = true;
    }
  }

  startCountdown() {
    this.screen = "countdown";
    this.showScreen("countdown");
    this.countdownVal = 3;
    this.countdownTimer = 0.9;
    this.el.readyBanner.textContent = "준비 완료! 곧 시작해요!";
    this.el.countdownRing.classList.remove("hidden");
    this.el.countdownNum.textContent = "3";
    this.sound.playCountdown(3);
  }

  startInGame() {
    this.paused = false;
    this.showScreen("ingame");
    this.engine.reset(this.selectedGame, this.settings);
  }

  drawCameraBrackets(w, h) {
    const ctx = this.ctx;
    const m = 24;
    const ln = 34;
    ctx.save();
    ctx.strokeStyle = "rgba(255, 255, 255, 0.72)";
    ctx.lineWidth = 4;
    ctx.lineCap = "round";
    [
      [m, m, 1, 1],
      [w - m, m, -1, 1],
      [m, h - m, 1, -1],
      [w - m, h - m, -1, -1],
    ].forEach(([x, y, dx, dy]) => {
      ctx.beginPath();
      ctx.moveTo(x + dx * ln, y);
      ctx.lineTo(x, y);
      ctx.lineTo(x, y + dy * ln);
      ctx.stroke();
    });
    ctx.restore();
  }

  drawReadyZones(players, w, h, dt) {
    this.drawCameraBrackets(w, h);

    const count = this.settings.players;
    const zones =
      count === 1
        ? [{ x: w * 0.5, label: "P1 · 모모", color: "#5CE5D8", pillBg: "#D8FAF6", idx: 0 }]
        : [
            { x: w * 0.3, label: "P1 · 모모", color: "#5CE5D8", pillBg: "#D8FAF6", idx: 0 },
            { x: w * 0.7, label: "P2 · 포포", color: "#FF8A94", pillBg: "#FFE2E5", idx: 1 },
          ];

    const capW = Math.min(220, w * 0.24);
    const capH = Math.min(420, h * 0.65);
    const capY = h * 0.56 - capH / 2;

    let allOk = true;
    zones.forEach((z) => {
      const p = players[z.idx];
      const detected = Boolean(p);
      const isOk = detected && (p.handsUp || this.readyHold[z.idx] > 1.1);

      if (detected) {
        this.readyHold[z.idx] += dt * (p.handsUp ? 2.2 : 0.75);
      } else {
        this.readyHold[z.idx] = Math.max(0, this.readyHold[z.idx] - dt);
      }
      if (!isOk) allOk = false;

      const ctx = this.ctx;
      ctx.save();
      ctx.beginPath();
      ctx.roundRect(z.x - capW / 2, capY, capW, capH, capW / 2);
      ctx.fillStyle = isOk ? z.color + "20" : "rgba(255,255,255,0.08)";
      ctx.fill();
      ctx.lineWidth = isOk ? 7 : 4;
      ctx.setLineDash(isOk ? [] : [12, 10]);
      ctx.strokeStyle = z.color;
      ctx.shadowColor = z.color;
      ctx.shadowBlur = isOk ? 20 : 6;
      ctx.stroke();
      ctx.restore();

      // Top status badge ("✓ P1 OK!")
      ctx.save();
      const badgeW = 136;
      ctx.fillStyle = isOk ? z.pillBg : "rgba(255,255,255,0.92)";
      ctx.shadowColor = "rgba(0,0,0,0.12)";
      ctx.shadowBlur = 10;
      ctx.beginPath();
      ctx.roundRect(z.x - badgeW / 2, capY - 22, badgeW, 38, 19);
      ctx.fill();
      ctx.shadowBlur = 0;

      ctx.font = "900 17px 'Apple SD Gothic Neo', sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      if (isOk) {
        ctx.fillStyle = "#2BB673";
        ctx.beginPath();
        ctx.arc(z.x - 42, capY - 3, 11, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = "#FFFFFF";
        ctx.font = "900 13px sans-serif";
        ctx.fillText("✓", z.x - 42, capY - 2);
        ctx.fillStyle = "#273244";
        ctx.font = "900 16px 'Apple SD Gothic Neo', sans-serif";
        ctx.fillText(`P${z.idx + 1} OK!`, z.x + 12, capY - 2);
      } else {
        ctx.fillStyle = "#273244";
        ctx.fillText(z.label, z.x, capY - 2);
      }

      // Bottom 3D mascot head badge (시안 3번 하단 모모/포포 배지)
      const headImg = this.mascotHeads[z.idx];
      if (headImg && headImg.complete && headImg.naturalWidth > 0) {
        const hs = 62;
        ctx.drawImage(headImg, z.x - hs / 2, capY + capH - hs * 0.72, hs, hs);
      }
      ctx.restore();
    });

    // Double glowing hand tracking halos
    players.forEach((p, idx) => {
      const col = idx === 0 ? "#5CE5D8" : "#FF8A94";
      [p.leftHand, p.rightHand].forEach((pt) => {
        const hx = pt.x * w;
        const hy = pt.y * h;
        this.ctx.save();
        this.ctx.strokeStyle = col;
        this.ctx.shadowColor = col;
        this.ctx.shadowBlur = 14;
        this.ctx.lineWidth = 3.5;
        this.ctx.beginPath();
        this.ctx.arc(hx, hy, 22, 0, Math.PI * 2);
        this.ctx.stroke();
        this.ctx.globalAlpha = 0.5;
        this.ctx.lineWidth = 2;
        this.ctx.beginPath();
        this.ctx.arc(hx, hy, 32, 0, Math.PI * 2);
        this.ctx.stroke();
        this.ctx.restore();
      });
    });

    if (this.screen === "ready" && allOk && this.readyHold.slice(0, count).every((v) => v >= 1.2)) {
      this.sound.playReadyOk();
      this.startCountdown();
    }
  }

  drawFallbackBackdrop(w, h) {
    // 게임에 방해되지 않는 초미니멀 뉴트럴 배경 (개발자/마우스 테스트 모드)
    const ctx = this.ctx;
    ctx.fillStyle = "#F7F9FC";
    ctx.fillRect(0, 0, w, h);
  }

  loop(now) {
    const dt = Math.min(0.05, (now - this.lastTime) / 1000);
    this.lastTime = now;

    const w = window.innerWidth;
    const h = window.innerHeight;

    if (["ready", "countdown", "ingame", "clear"].includes(this.screen)) {
      this.ctx.clearRect(0, 0, w, h);
      if (this.tracker.mode === "pointer") {
        this.drawFallbackBackdrop(w, h);
      }

      const players = this.tracker.update(this.settings.players);

      if (this.screen === "ready" || this.screen === "countdown") {
        this.drawReadyZones(players, w, h, dt);
        if (this.screen === "countdown") {
          this.countdownTimer -= dt;
          if (this.countdownTimer <= 0) {
            this.countdownVal--;
            if (this.countdownVal > 0) {
              this.el.countdownNum.textContent = String(this.countdownVal);
              this.countdownTimer = 0.85;
              this.sound.playCountdown(this.countdownVal);
            } else {
              this.sound.playCountdown(0);
              this.startInGame();
            }
          }
        }
      } else if (this.screen === "ingame" || this.screen === "clear") {
        if (!this.paused) {
          this.engine.update(dt, players, w, h);
        }
        if (this.pixi.ready) {
          this.pixi.renderState(this.engine, players, w, h);
        } else {
          this.engine.renderFallback2D(this.ctx, players, w, h);
        }
      }
    }

    requestAnimationFrame((t) => this.loop(t));
  }
}

window.addEventListener("DOMContentLoaded", () => {
  new PangPangApp();
});
