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
    this.cameraInitPromise = null;
    this.paused = false;
    this.lastTime = performance.now();

    // Horizontal stage-select carousel state (7 games, 4 visible at once -> offsets 0..3)
    this.carouselIndex = 0;
    this.carouselVisible = 4;
    this.carouselMax = 3;
    this.arrowDwellDir = 0;
    this.arrowDwellProgress = 0;
    this.arrowCooldown = 0;
    this._swipeSuppressedClick = false;

    this.readyHold = [0, 0];
    this.countdownVal = 3;
    this.countdownTimer = 0;

    // 3D clay mascot head badges for Ready Check AR capsules (시안 3번 1:1)
    this.mascotHeads = [
      loadImg("./assets/momo_head.png"),
      loadImg("./assets/popo_head.png"),
    ];

    // Phase 4: In-memory Polaroid Photo Album buffer (privacy-first: cleared on replay/exit!)
    this.polaroidCuts = [];
    this.polaroidCanvas = document.createElement("canvas");
    this.polaroidCanvas.width = 480;
    this.polaroidCanvas.height = 480;
    this.polaroidCtx = this.polaroidCanvas.getContext("2d");
    this.polaroidStickerCache = {};

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
      carouselViewport: document.getElementById("carousel-viewport"),
      carouselTrack: document.getElementById("carousel-track"),
      carouselPrev: document.getElementById("btn-carousel-prev"),
      carouselNext: document.getElementById("btn-carousel-next"),
      carouselDots: document.getElementById("carousel-dots"),
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
      polaroidAlbum: document.getElementById("polaroid-album"),
      polaroidGrid: document.getElementById("polaroid-grid"),
      albumSummary: document.getElementById("album-summary"),
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
        const hideDots = this.selectedGame === "animal" || this.selectedGame === "jungle";
        this.el.progressDots.classList.toggle("hidden", hideDots);
        this.el.progressDots.innerHTML = "";
        if (hideDots) return;
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
      onCapturePolaroid: (payload) => {
        this.capturePolaroidSnapshot(payload);
      },
      onFinish: (summary) => {
        this.el.clearSummary.textContent = summary;
        if (this.selectedGame === "animal") {
          this.renderPolaroidClearAlbum(summary);
        } else {
          this.el.screens.clear.classList.remove("has-polaroids");
          this.el.polaroidAlbum?.classList.add("hidden");
        }
        this.showScreen("clear");
      },
    });

    this.bindEvents();
    this.initCarousel();
    this.syncSettingsUI();
    this.resizeCanvas();
    window.addEventListener("resize", () => this.resizeCanvas());
    window.__pangpang = this;
    requestAnimationFrame((t) => this.loop(t));
  }

  initCarousel() {
    const cards = Array.from(document.querySelectorAll(".game-card"));
    this.carouselMax = Math.max(0, cards.length - this.carouselVisible);
    if (this.el.carouselDots) {
      this.el.carouselDots.innerHTML = "";
      for (let i = 0; i <= this.carouselMax; i++) {
        const dot = document.createElement("button");
        dot.className = "carousel-dot" + (i === 0 ? " active" : "");
        dot.setAttribute("aria-label", `${i + 1}번째 구간`);
        dot.addEventListener("click", () => {
          this.sound.playClick();
          this.setCarouselIndex(i);
        });
        this.el.carouselDots.appendChild(dot);
      }
    }

    this.el.carouselPrev?.addEventListener("click", () => {
      if (this.carouselIndex > 0) {
        this.sound.playClick();
        this.setCarouselIndex(this.carouselIndex - 1);
      }
    });
    this.el.carouselNext?.addEventListener("click", () => {
      if (this.carouselIndex < this.carouselMax) {
        this.sound.playClick();
        this.setCarouselIndex(this.carouselIndex + 1);
      }
    });

    // Direct touch/pointer horizontal swipe on carousel viewport
    let dragStartX = null;
    let dragStartY = null;
    this.el.carouselViewport?.addEventListener("pointerdown", (e) => {
      dragStartX = e.clientX;
      dragStartY = e.clientY;
      this._swipeSuppressedClick = false;
    });
    window.addEventListener("pointerup", (e) => {
      if (dragStartX === null) return;
      const dx = e.clientX - dragStartX;
      const dy = e.clientY - dragStartY;
      dragStartX = null;
      dragStartY = null;
      if (this.screen === "select" && Math.abs(dx) > 42 && Math.abs(dx) > Math.abs(dy) * 1.2) {
        this._swipeSuppressedClick = true;
        setTimeout(() => (this._swipeSuppressedClick = false), 120);
        if (dx < 0 && this.carouselIndex < this.carouselMax) {
          this.sound.playClick();
          this.setCarouselIndex(this.carouselIndex + 1);
        } else if (dx > 0 && this.carouselIndex > 0) {
          this.sound.playClick();
          this.setCarouselIndex(this.carouselIndex - 1);
        }
      }
    });

    // Optional wheel slide for desktop trackpad convenience
    let wheelLock = 0;
    this.el.carouselViewport?.addEventListener(
      "wheel",
      (e) => {
        if (this.screen !== "select") return;
        const delta = Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY;
        if (Math.abs(delta) < 18) return;
        const now = performance.now();
        if (now - wheelLock < 280) return;
        wheelLock = now;
        if (delta > 0 && this.carouselIndex < this.carouselMax) {
          this.sound.playClick();
          this.setCarouselIndex(this.carouselIndex + 1);
        } else if (delta < 0 && this.carouselIndex > 0) {
          this.sound.playClick();
          this.setCarouselIndex(this.carouselIndex - 1);
        }
      },
      { passive: true }
    );

    this.setCarouselIndex(0);
  }

  setCarouselIndex(idx) {
    this.carouselIndex = Math.max(0, Math.min(this.carouselMax, idx));
    if (this.el.carouselTrack) {
      this.el.carouselTrack.style.setProperty("--carousel-idx", String(this.carouselIndex));
    }
    if (this.el.carouselPrev) {
      this.el.carouselPrev.disabled = this.carouselIndex <= 0;
    }
    if (this.el.carouselNext) {
      this.el.carouselNext.disabled = this.carouselIndex >= this.carouselMax;
    }
    if (this.el.carouselDots) {
      Array.from(this.el.carouselDots.children).forEach((dot, i) => {
        dot.classList.toggle("active", i === this.carouselIndex);
      });
    }
  }

  ensureCameraReady() {
    if (this.cameraReady) return Promise.resolve();
    if (this.cameraInitPromise) return this.cameraInitPromise;
    this.cameraInitPromise = this.tracker
      .init(this.settings.players, { forcePointer: Boolean(this.settings.devMode) })
      .then(() => {
        this.cameraReady = true;
        this.cameraInitPromise = null;
      })
      .catch(() => {
        this.cameraInitPromise = null;
      });
    return this.cameraInitPromise;
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
        if (this._swipeSuppressedClick) return;
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
    const bumpVol = (delta) => {
      this.settings.volume = Math.max(0, Math.min(100, (this.settings.volume ?? 80) + delta));
      this.el.setVolume.value = String(this.settings.volume);
      this.sound.setVolume(this.settings.volume / 100);
      this.sound.playClick();
      saveSettings(this.settings);
    };
    document.getElementById("btn-vol-down")?.addEventListener("click", () => bumpVol(-20));
    document.getElementById("btn-vol-up")?.addEventListener("click", () => bumpVol(20));
    this.el.setDevMode.addEventListener("change", () => {
      this.sound.playClick();
      this.settings.devMode = this.el.setDevMode.checked;
      saveSettings(this.settings);
      // 모드 전환 시 카메라/마우스 트래커 즉시 재초기화
      if (this.settings.devMode) {
        this.tracker.stop();
        this.tracker.mode = "pointer";
      }
      this.cameraReady = false;
      this.cameraInitPromise = null;
      this.syncSettingsUI();
      if (this.screen === "select") {
        this.el.screens.select.classList.toggle("live-camera", !this.settings.devMode);
        if (!this.settings.devMode) {
          this.ensureCameraReady();
        }
      }
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
    this.el.noiseBanner.classList.remove("hidden");
    this.el.noiseBanner.textContent = this.settings.quietMode
      ? "✋ 한 손을 카드에 1.5초 올리거나 화살표·터치로 골라요! · 🪶 층간소음 모드 ON"
      : "✋ 한 손을 카드에 1.5초 올리거나 화살표·터치로 골라요!";
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
      this.polaroidCuts = [];
      this.el.screens.clear?.classList.remove("has-polaroids");
      this.el.polaroidAlbum?.classList.add("hidden");
    }

    Object.entries(this.el.screens).forEach(([k, node]) => {
      node.classList.toggle("active", k === name || (name === "countdown" && k === "ready"));
    });

    const usesCamera = ["select", "ready", "countdown", "ingame", "clear"].includes(name);
    this.el.viewport.classList.toggle("hidden", !usesCamera);
    this.pixi.setVisible(["ingame", "clear"].includes(name));
    this.el.screens.select.classList.toggle("live-camera", name === "select" && !this.settings.devMode);

    // Reset air-cursor dwell state & add 0.75s entry grace cooldown whenever changing screen
    this.dwellCard = null;
    this.dwellProgress = 0;
    this.dwellTickStep = 0;
    this.arrowDwellDir = 0;
    this.arrowDwellProgress = 0;
    this.arrowCooldown = 0.65;
    this.handClickCooldown = 0.75;
    this.resetHandBtnVisuals();
    const acEl = document.getElementById("air-cursor");
    if (acEl) acEl.classList.add("hidden");
    document.querySelectorAll(".game-card").forEach((c) => {
      c.classList.remove("air-hover");
      const bar = c.querySelector(".card-dwell-bar span");
      if (bar) bar.style.width = "0%";
    });
    [this.el.carouselPrev, this.el.carouselNext].forEach((btn) => {
      if (!btn) return;
      btn.classList.remove("air-hover");
      const r = btn.querySelector(".arrow-dwell-ring");
      if (r) r.style.strokeDashoffset = "176";
    });

    // Enable live front camera IMMEDIATELY on Stage Select (when clicking "시작")!
    if (name === "select" && !this.settings.devMode) {
      this.ctx.clearRect(0, 0, window.innerWidth, window.innerHeight);
      this.ensureCameraReady();
    }
  }

  resetArrowDwellVisuals() {
    [this.el.carouselPrev, this.el.carouselNext].forEach((btn) => {
      if (!btn) return;
      btn.classList.remove("air-hover");
      const r = btn.querySelector(".arrow-dwell-ring");
      if (r) r.style.strokeDashoffset = "176";
    });
  }

  resetHandBtnVisuals() {
    if (this.dwellBtn) {
      this.dwellBtn.classList.remove("hand-hover");
      this.dwellBtn = null;
    }
    this.dwellBtnProgress = 0;
  }

  /**
   * Nearest-target hit-test with exact-containment priority & sticky hysteresis:
   * Fixes overlapping padded hitboxes where an earlier DOM sibling (e.g. `1인` or left card)
   * stole hits from adjacent buttons (`2인` or right card)!
   */
  findBestHandTarget(cx, cy, elements, padPx = 14, currentTarget = null, clipRect = null) {
    let bestEl = null;
    let bestScore = Infinity;

    for (const el of elements) {
      if (!el || el.disabled || el.offsetParent === null) continue;
      const rect = el.getBoundingClientRect();
      if (rect.width < 4 || rect.height < 4) continue;
      if (clipRect) {
        const midX = rect.left + rect.width * 0.5;
        if (midX < clipRect.left + 8 || midX > clipRect.right - 8) continue;
      }

      const insideExact = cx >= rect.left && cx <= rect.right && cy >= rect.top && cy <= rect.bottom;
      const insidePad =
        cx >= rect.left - padPx &&
        cx <= rect.right + padPx &&
        cy >= rect.top - padPx &&
        cy <= rect.bottom + padPx;
      if (!insidePad) continue;

      // Distance from cursor to nearest point on the element's true border (0 if strictly inside)
      const nearX = Math.max(rect.left, Math.min(cx, rect.right));
      const nearY = Math.max(rect.top, Math.min(cy, rect.bottom));
      const edgeDist = Math.hypot(cx - nearX, cy - nearY);
      const centerDist = Math.hypot(cx - (rect.left + rect.width * 0.5), cy - (rect.top + rect.height * 0.5));
      const stickyBonus = el === currentTarget ? -10 : 0;
      const score = (insideExact ? 0 : 1000) + edgeDist * 10 + centerDist * 0.08 + stickyBonus;
      if (score < bestScore) {
        bestScore = score;
        bestEl = el;
      }
    }
    return bestEl;
  }

  isAlreadyActiveOption(el) {
    if (!el) return false;
    return (
      el.classList.contains("active") &&
      (el.classList.contains("mini-opt") || Boolean(el.closest(".seg-control")))
    );
  }

  /**
   * Unified Global Single-Hand Air Cursor across ALL screens & modals:
   * - Modal priority: Settings Modal > Pause Modal > Active Screen (Select / Ready / Clear)
   * - 0.75s entry grace period on any screen/modal switch prevents accidental triggers
   * - Exact-containment + nearest-target matching prevents adjacent buttons/cards stealing hits!
   */
  updateGlobalAirCursor(dt, w, h) {
    const acEl = document.getElementById("air-cursor");
    const ringEl = document.getElementById("air-cursor-ring");
    if (!acEl || !ringEl) return;

    this.arrowCooldown = Math.max(0, (this.arrowCooldown || 0) - dt);
    this.handClickCooldown = Math.max(0, (this.handClickCooldown || 0) - dt);

    const settingsOpen = !this.el.modalSettings.classList.contains("hidden");
    const pauseOpen = !this.el.modalPause.classList.contains("hidden");
    const contextKey = `${this.screen}:${settingsOpen ? 1 : 0}:${pauseOpen ? 1 : 0}`;
    if (this._lastAirContextKey !== contextKey) {
      this._lastAirContextKey = contextKey;
      this.handClickCooldown = Math.max(this.handClickCooldown || 0, 0.75);
      this.arrowCooldown = Math.max(this.arrowCooldown || 0, 0.55);
      this.resetHandBtnVisuals();
      if (this.dwellCard) {
        this.dwellCard.classList.remove("air-hover");
        const b = this.dwellCard.querySelector(".card-dwell-bar span");
        if (b) b.style.width = "0%";
        this.dwellCard = null;
      }
      this.dwellProgress = 0;
      this.dwellTickStep = 0;
      this.arrowDwellDir = 0;
      this.arrowDwellProgress = 0;
      this.resetArrowDwellVisuals();
    }

    const activeUiAllowed = settingsOpen || pauseOpen || ["select", "ready", "clear"].includes(this.screen);
    const ac = this.tracker.airCursor;

    if (!activeUiAllowed || !ac || !ac.active || this.settings.devMode) {
      acEl.classList.add("hidden");
      if (this.dwellCard) {
        this.dwellCard.classList.remove("air-hover");
        const b = this.dwellCard.querySelector(".card-dwell-bar span");
        if (b) b.style.width = "0%";
        this.dwellCard = null;
      }
      this.dwellProgress = 0;
      this.arrowDwellDir = 0;
      this.arrowDwellProgress = 0;
      this.resetArrowDwellVisuals();
      this.resetHandBtnVisuals();
      return;
    }

    // If a modal is open OR we're on Ready/Clear (not Select), use nearest [data-hand-target] inside topmost container!
    const modalRoot = settingsOpen ? this.el.modalSettings : pauseOpen ? this.el.modalPause : null;
    let cx = ac.x * w;
    let cy = ac.y * h;

    if (modalRoot || this.screen !== "select") {
      if (this.dwellCard) {
        this.dwellCard.classList.remove("air-hover");
        const b = this.dwellCard.querySelector(".card-dwell-bar span");
        if (b) b.style.width = "0%";
        this.dwellCard = null;
      }
      this.dwellProgress = 0;
      this.resetArrowDwellVisuals();

      const scope = modalRoot || this.el.screens[this.screen];
      const targets = scope ? Array.from(scope.querySelectorAll("[data-hand-target]")) : [];
      const hitBtn = this.findBestHandTarget(cx, cy, targets, 14, this.dwellBtn);
      if (hitBtn) {
        const rect = hitBtn.getBoundingClientRect();
        cx = cx + (rect.left + rect.width * 0.5 - cx) * 0.14;
        cy = cy + (rect.top + rect.height * 0.5 - cy) * 0.14;
      }

      acEl.classList.remove("hidden");
      acEl.style.left = `${cx}px`;
      acEl.style.top = `${cy}px`;

      if (hitBtn) {
        if (this.dwellBtn && this.dwellBtn !== hitBtn) {
          this.dwellBtn.classList.remove("hand-hover");
          this.dwellBtnProgress = 0;
        }
        this.dwellBtn = hitBtn;
        hitBtn.classList.add("hand-hover");
        if (this.isAlreadyActiveOption(hitBtn)) {
          this.dwellBtnProgress = 0;
        } else if (this.handClickCooldown <= 0) {
          const dwellSec = Math.max(0.6, Number(hitBtn.dataset.handDwell || 1.1));
          const prevHalf = (this.dwellBtnProgress || 0) >= 0.5;
          this.dwellBtnProgress = Math.min(1, (this.dwellBtnProgress || 0) + dt / dwellSec);
          if (!prevHalf && this.dwellBtnProgress >= 0.5) this.sound.playClick();
          if (this.dwellBtnProgress >= 1) {
            this.dwellBtnProgress = 0;
            this.handClickCooldown = 0.85;
            hitBtn.classList.remove("hand-hover");
            this.dwellBtn = null;
            this.sound.playReadyOk();
            hitBtn.click();
          }
        }
      } else {
        this.dwellBtnProgress = Math.max(0, (this.dwellBtnProgress || 0) - dt * 1.6);
        if (this.dwellBtnProgress <= 0 && this.dwellBtn) {
          this.dwellBtn.classList.remove("hand-hover");
          this.dwellBtn = null;
        }
      }
      ringEl.style.strokeDashoffset = String(163.4 * (1 - (this.dwellBtnProgress || 0)));
      return;
    }

    // Stage Select screen (no modal open): check top bar buttons FIRST, then carousel arrows, then visible cards!
    const topTargets = Array.from(this.el.screens.select.querySelectorAll("header [data-hand-target]"));
    const hitTopBtn = this.findBestHandTarget(cx, cy, topTargets, 12, this.dwellBtn);
    if (hitTopBtn) {
      const rect = hitTopBtn.getBoundingClientRect();
      cx = cx + (rect.left + rect.width * 0.5 - cx) * 0.14;
      cy = cy + (rect.top + rect.height * 0.5 - cy) * 0.14;

      if (this.dwellCard) {
        this.dwellCard.classList.remove("air-hover");
        const b = this.dwellCard.querySelector(".card-dwell-bar span");
        if (b) b.style.width = "0%";
        this.dwellCard = null;
      }
      this.dwellProgress = 0;
      this.resetArrowDwellVisuals();

      acEl.classList.remove("hidden");
      acEl.style.left = `${cx}px`;
      acEl.style.top = `${cy}px`;

      if (this.dwellBtn && this.dwellBtn !== hitTopBtn) {
        this.dwellBtn.classList.remove("hand-hover");
        this.dwellBtnProgress = 0;
      }
      this.dwellBtn = hitTopBtn;
      hitTopBtn.classList.add("hand-hover");
      if (this.isAlreadyActiveOption(hitTopBtn)) {
        this.dwellBtnProgress = 0;
      } else if (this.handClickCooldown <= 0) {
        const dwellSec = Math.max(0.7, Number(hitTopBtn.dataset.handDwell || 1.0));
        const prevHalf = (this.dwellBtnProgress || 0) >= 0.5;
        this.dwellBtnProgress = Math.min(1, (this.dwellBtnProgress || 0) + dt / dwellSec);
        if (!prevHalf && this.dwellBtnProgress >= 0.5) this.sound.playClick();
        if (this.dwellBtnProgress >= 1) {
          this.dwellBtnProgress = 0;
          this.handClickCooldown = 0.85;
          hitTopBtn.classList.remove("hand-hover");
          this.dwellBtn = null;
          this.sound.playReadyOk();
          hitTopBtn.click();
        }
      }
      ringEl.style.strokeDashoffset = String(163.4 * (1 - (this.dwellBtnProgress || 0)));
      return;
    } else if (this.dwellBtn) {
      // Smooth decay instead of instant wipe on 1 missed frame!
      this.dwellBtnProgress = Math.max(0, (this.dwellBtnProgress || 0) - dt * 1.8);
      if (this.dwellBtnProgress <= 0) {
        this.resetHandBtnVisuals();
      }
    }

    this.updateSelectAirCursor(dt, w, h);
  }

  updateSelectAirCursor(dt, w, h) {
    const acEl = document.getElementById("air-cursor");
    const ringEl = document.getElementById("air-cursor-ring");
    if (!acEl || !ringEl) return;

    const ac = this.tracker.airCursor;
    if (!ac || !ac.active || this.settings.devMode) {
      acEl.classList.add("hidden");
      if (this.dwellCard) {
        this.dwellCard.classList.remove("air-hover");
        const b = this.dwellCard.querySelector(".card-dwell-bar span");
        if (b) b.style.width = "0%";
        this.dwellCard = null;
      }
      this.dwellProgress = 0;
      this.arrowDwellDir = 0;
      this.arrowDwellProgress = 0;
      this.resetArrowDwellVisuals();
      return;
    }

    let cx = ac.x * w;
    let cy = ac.y * h;
    let hitArrowBtn = null;
    let hitArrowDir = 0;

    // 1) Check chunky left/right carousel arrows first (nearest match, 0.8s dwell with cooldown!)
    const arrowBtns = [this.el.carouselPrev, this.el.carouselNext].filter(Boolean);
    const currentArrowBtn =
      this.arrowDwellDir === -1 ? this.el.carouselPrev : this.arrowDwellDir === 1 ? this.el.carouselNext : null;
    hitArrowBtn = this.findBestHandTarget(cx, cy, arrowBtns, 20, currentArrowBtn);
    if (hitArrowBtn) {
      hitArrowDir = hitArrowBtn === this.el.carouselPrev ? -1 : 1;
      const rect = hitArrowBtn.getBoundingClientRect();
      cx = cx + (rect.left + rect.width * 0.5 - cx) * 0.14;
      cy = cy + (rect.top + rect.height * 0.5 - cy) * 0.14;
    }

    // 2) Check ONLY currently visible cards inside carousel-viewport (nearest match, 1.5s dwell!)
    let hitCard = null;
    if (!hitArrowBtn) {
      const vpRect = this.el.carouselViewport?.getBoundingClientRect();
      const cards = Array.from(document.querySelectorAll(".game-card"));
      hitCard = this.findBestHandTarget(cx, cy, cards, 10, this.dwellCard, vpRect);
      if (hitCard) {
        const rect = hitCard.getBoundingClientRect();
        cx = cx + (rect.left + rect.width * 0.5 - cx) * 0.12;
        cy = cy + (rect.top + rect.height * 0.5 - cy) * 0.12;
      }
    }

    acEl.classList.remove("hidden");
    acEl.style.left = `${cx}px`;
    acEl.style.top = `${cy}px`;

    let ringProgress = 0;

    if (hitArrowBtn) {
      if (this.dwellCard) {
        this.dwellCard.classList.remove("air-hover");
        const oldBar = this.dwellCard.querySelector(".card-dwell-bar span");
        if (oldBar) oldBar.style.width = "0%";
        this.dwellCard = null;
      }
      this.dwellProgress = 0;
      this.dwellTickStep = 0;

      if (this.arrowDwellDir !== hitArrowDir) {
        this.resetArrowDwellVisuals();
        this.arrowDwellDir = hitArrowDir;
        this.arrowDwellProgress = 0;
      }
      hitArrowBtn.classList.add("air-hover");
      if (this.arrowCooldown <= 0 && this.handClickCooldown <= 0) {
        this.arrowDwellProgress = Math.min(1, (this.arrowDwellProgress || 0) + dt / 0.8); // 0.8s dwell!
      }
      ringProgress = this.arrowDwellProgress;
      const arrowRing = hitArrowBtn.querySelector(".arrow-dwell-ring");
      if (arrowRing) {
        arrowRing.style.strokeDashoffset = String(176 * (1 - ringProgress));
      }
      if (this.arrowDwellProgress >= 1) {
        this.arrowDwellProgress = 0;
        this.arrowCooldown = 0.72; // Smooth one-step-at-a-time cooldown!
        if (arrowRing) arrowRing.style.strokeDashoffset = "176";
        this.sound.playClick();
        this.setCarouselIndex(this.carouselIndex + hitArrowDir);
      }
    } else {
      if (this.arrowDwellDir !== 0) {
        this.arrowDwellProgress = Math.max(0, (this.arrowDwellProgress || 0) - dt * 2.0);
        if (this.arrowDwellProgress <= 0) {
          this.arrowDwellDir = 0;
          this.resetArrowDwellVisuals();
        }
      }

      if (hitCard) {
        if (this.dwellCard && this.dwellCard !== hitCard) {
          this.dwellCard.classList.remove("air-hover");
          const oldBar = this.dwellCard.querySelector(".card-dwell-bar span");
          if (oldBar) oldBar.style.width = "0%";
          this.dwellProgress = 0;
          this.dwellTickStep = 0;
        }
        this.dwellCard = hitCard;
        hitCard.classList.add("air-hover");
        if (this.handClickCooldown <= 0) {
          this.dwellProgress = Math.min(1, (this.dwellProgress || 0) + dt / 1.5); // 1.5s dwell!
        }
        ringProgress = this.dwellProgress;
        const step = Math.floor(this.dwellProgress * 3);
        if (step > (this.dwellTickStep || 0) && step < 3) {
          this.dwellTickStep = step;
          this.sound.playClick();
        }
        const bar = hitCard.querySelector(".card-dwell-bar span");
        if (bar) bar.style.width = `${Math.round(this.dwellProgress * 100)}%`;

        if (this.dwellProgress >= 1) {
          const game = hitCard.dataset.game;
          this.dwellProgress = 0;
          this.dwellTickStep = 0;
          this.sound.playReadyOk();
          this.selectedGame = game;
          this.enterReadyScreen();
          return;
        }
      } else {
        this.dwellProgress = Math.max(0, (this.dwellProgress || 0) - dt * 1.4);
        ringProgress = this.dwellProgress;
        if (this.dwellProgress <= 0 && this.dwellCard) {
          this.dwellCard.classList.remove("air-hover");
          const oldBar = this.dwellCard.querySelector(".card-dwell-bar span");
          if (oldBar) oldBar.style.width = "0%";
          this.dwellCard = null;
          this.dwellTickStep = 0;
        }
      }
    }

    const circ = 163.4;
    ringEl.style.strokeDashoffset = String(circ * (1 - ringProgress));
  }

  async enterReadyScreen() {
    this.readyHold = [0, 0];
    this.el.countdownRing.classList.add("hidden");
    this.el.readyBanner.innerHTML =
      this.settings.players === 2
        ? "모모·포포 자리에 서서 <strong>만세!</strong> 해주세요"
        : "모모 자리에 서서 <strong>만세!</strong> 해주세요";
    this.showScreen("ready");

    await this.ensureCameraReady();
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
    this.polaroidCuts = [];
    this.el.screens.clear.classList.remove("has-polaroids");
    this.el.polaroidAlbum?.classList.add("hidden");
    this.showScreen("ingame");
    const hideDots = this.selectedGame === "animal" || this.selectedGame === "jungle";
    this.el.progressDots.classList.toggle("hidden", hideDots);
    this.engine.reset(this.selectedGame, this.settings);
  }

  /** Helper: load pose sticker image synchronously from Pixi textures or Image cache */
  getStickerImageSource(texKey) {
    if (!texKey) return null;
    const tex = this.pixi?.textures?.[texKey];
    const res = tex?.source?.resource;
    if (res && (res instanceof HTMLImageElement || res instanceof ImageBitmap || res instanceof HTMLCanvasElement)) {
      return res;
    }
    if (!this.polaroidStickerCache[texKey]) {
      this.polaroidStickerCache[texKey] = loadImg(`./assets/${texKey}.png`);
    }
    const im = this.polaroidStickerCache[texKey];
    return im && im.complete && im.naturalWidth > 0 ? im : null;
  }

  /**
   * Phase 4: Peak-Expression Smart-Cropped 1:1 480x480 Polaroid Snapshot!
   * - Live camera: smart-crops 1:1 mirrored square centered on player's bbox.
   * - Dev / no-camera mode: renders a bright pastel sunlit living-room portrait with 3D clay mascot!
   */
  buildStylizedPolaroidDataUrl(pose) {
    const ctx = this.polaroidCtx;
    const S = 480;
    ctx.save();
    // Soft warm sunlit living-room gradient backdrop
    const bg = ctx.createLinearGradient(0, 0, S, S);
    bg.addColorStop(0, "#FFF8EA");
    bg.addColorStop(0.55, "#FDEEE2");
    bg.addColorStop(1, "#DFF3FF");
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, S, S);

    // Subtle pastel playmat & window sunlight rays
    ctx.fillStyle = "rgba(255, 255, 255, 0.55)";
    ctx.beginPath();
    ctx.arc(S * 0.22, S * 0.18, 170, 0, Math.PI * 2);
    ctx.fill();

    // Pastel floor mat at bottom
    const matCols = ["#F9D5D3", "#FFF3C4", "#D4F5E9", "#DBEAFE"];
    for (let i = 0; i < 4; i++) {
      ctx.fillStyle = matCols[i];
      ctx.fillRect(i * (S / 4), S * 0.78, S / 4 + 1, S * 0.22);
    }

    // Glowing halo behind character
    const halo = ctx.createRadialGradient(S * 0.5, S * 0.48, 24, S * 0.5, S * 0.48, 185);
    halo.addColorStop(0, (pose.color || "#FFD43B") + "44");
    halo.addColorStop(1, "rgba(255,255,255,0)");
    ctx.fillStyle = halo;
    ctx.fillRect(0, 0, S, S);

    // Sparkle stars
    const drawSparkle = (cx, cy, r, col) => {
      ctx.fillStyle = col;
      ctx.beginPath();
      for (let i = 0; i < 8; i++) {
        const rad = i % 2 === 0 ? r : r * 0.35;
        const a = (i * Math.PI) / 4;
        if (i === 0) ctx.moveTo(cx + Math.cos(a) * rad, cy + Math.sin(a) * rad);
        else ctx.lineTo(cx + Math.cos(a) * rad, cy + Math.sin(a) * rad);
      }
      ctx.closePath();
      ctx.fill();
    };
    drawSparkle(96, 98, 16, "#FFD43B");
    drawSparkle(386, 112, 14, "#FF7D89");
    drawSparkle(364, 332, 12, "#4AD3C8");
    drawSparkle(112, 326, 11, "#C084FC");

    if (pose.isCoop) {
      const mImg = this.getStickerImageSource("momo_dance1") || this.mascotHeads[0];
      const pImg = this.getStickerImageSource("popo_dance1") || this.mascotHeads[1];
      const hImg = this.getStickerImageSource("fx_coop_heart");
      if (mImg) ctx.drawImage(mImg, 44, 146, 200, 220);
      if (pImg) ctx.drawImage(pImg, 236, 146, 200, 220);
      if (hImg) ctx.drawImage(hImg, 165, 92, 150, 150);
    } else {
      const mainImg = this.getStickerImageSource(pose.tex) || this.getStickerImageSource(`pose_${pose.id}`) || this.mascotHeads[0];
      if (mainImg) {
        const aspect = (mainImg.naturalWidth || mainImg.width || 1) / Math.max(1, mainImg.naturalHeight || mainImg.height || 1);
        const targetH = 316;
        const targetW = targetH * aspect;
        ctx.drawImage(mainImg, (S - targetW) * 0.5, S * 0.52 - targetH * 0.5, targetW, targetH);
      }
    }
    ctx.restore();
    return this.polaroidCanvas.toDataURL("image/jpeg", 0.86);
  }

  capturePolaroidSnapshot({ pose, players, isBest = false, combo = 0, roundIndex = 0 }) {
    if (!pose) return;
    const vid = this.el.video;
    const ctx = this.polaroidCtx;
    const S = 480;
    let dataUrl = null;

    if (vid && vid.videoWidth > 64 && vid.videoHeight > 64 && !this.settings.devMode && this.tracker.mode === "mediapipe") {
      try {
        const vw = vid.videoWidth;
        const vh = vid.videoHeight;

        // Compute normalized center of player(s) bbox in mirrored viewport coordinates
        let sumX = 0;
        let sumY = 0;
        let count = 0;
        (players || []).forEach((p) => {
          [p.head, p.shoulders?.[0], p.shoulders?.[1], p.hips?.[0], p.hips?.[1]].forEach((pt) => {
            if (pt && (pt.smoothConf ?? pt.v ?? 1) > 0.2) {
              sumX += pt.x;
              sumY += pt.y;
              count++;
            }
          });
        });
        const normCx = count > 0 ? Math.max(0.22, Math.min(0.78, sumX / count)) : 0.5;
        const normCy = count > 0 ? Math.max(0.24, Math.min(0.72, sumY / count)) : 0.48;

        // Convert mirrored normCx back to raw video X (unmirrored)
        const rawCx = (1 - normCx) * vw;
        const rawCy = normCy * vh;
        const cropSize = Math.min(vw, vh) * 0.92;
        const sx = Math.max(0, Math.min(vw - cropSize, rawCx - cropSize * 0.5));
        const sy = Math.max(0, Math.min(vh - cropSize, rawCy - cropSize * 0.5));

        ctx.save();
        ctx.clearRect(0, 0, S, S);
        // Mirror horizontally to match selfie AR view!
        ctx.translate(S, 0);
        ctx.scale(-1, 1);
        ctx.drawImage(vid, sx, sy, cropSize, cropSize, 0, 0, S, S);
        ctx.restore();
        dataUrl = this.polaroidCanvas.toDataURL("image/jpeg", 0.82);
      } catch {
        dataUrl = null;
      }
    }

    if (!dataUrl) {
      dataUrl = this.buildStylizedPolaroidDataUrl(pose);
    }

    const cut = {
      dataUrl,
      poseId: pose.id,
      stickerTex: pose.stickerTex || pose.tex || "animal_giraffe",
      caption: pose.caption || pose.title || `${pose.name} 완벽!`,
      isBest: Boolean(isBest),
      combo,
      roundIndex,
    };

    if (this.polaroidCuts.length < 3) {
      this.polaroidCuts.push(cut);
    } else if (cut.isBest) {
      // Always preserve Best Cut in slot 3 (rightmost tilted card with golden crown!)
      this.polaroidCuts[2] = cut;
    } else {
      this.polaroidCuts[1] = cut;
    }
  }

  renderPolaroidClearAlbum(summary) {
    if (!this.el.polaroidAlbum || !this.el.polaroidGrid) return;
    const cuts = [...this.polaroidCuts];

    // If player cleared fewer than 3 poses, gracefully fill remaining Polaroids from played deck so album is always lush!
    const deck = this.engine.animalList || [];
    for (let i = 0; cuts.length < 3 && i < deck.length; i++) {
      const p = deck[i];
      if (cuts.some((c) => c.poseId === p.id)) continue;
      cuts.push({
        dataUrl: this.buildStylizedPolaroidDataUrl(p),
        poseId: p.id,
        stickerTex: p.stickerTex || p.tex || "animal_giraffe",
        caption: cuts.length === 2 ? "베스트 컷!" : p.caption || `${p.name} 완벽!`,
        isBest: cuts.length === 2,
        combo: 0,
        roundIndex: i,
      });
    }

    // Ensure exactly one Best Cut gets the golden crown (prefer Boss / Co-op / last slot)
    let bestIdx = cuts.findIndex((c) => c.isBest);
    if (bestIdx < 0) bestIdx = cuts.length - 1;
    // Move Best Cut to rightmost slot (index 2) to match Mockup 4 composition!
    if (cuts.length === 3 && bestIdx !== 2) {
      const [best] = cuts.splice(bestIdx, 1);
      cuts.push(best);
      bestIdx = 2;
    }

    this.el.polaroidGrid.innerHTML = "";
    cuts.slice(0, 3).forEach((cut, idx) => {
      const card = document.createElement("div");
      card.className = `polaroid-card tilt-${idx}`;

      const tape = document.createElement("div");
      tape.className = `washi-tape tape-${idx}`;
      card.appendChild(tape);

      const photoWrap = document.createElement("div");
      photoWrap.className = "polaroid-photo-wrap";
      const img = document.createElement("img");
      img.className = "polaroid-photo";
      img.src = cut.dataUrl;
      img.alt = cut.caption;
      img.draggable = false;
      photoWrap.appendChild(img);
      card.appendChild(photoWrap);

      // 3D Clay Pose Sticker overlapping bottom-left corner
      const sticker = document.createElement("img");
      sticker.className = "polaroid-sticker";
      sticker.src = `./assets/${cut.stickerTex}.png`;
      sticker.alt = "";
      sticker.draggable = false;
      sticker.onerror = () => {
        sticker.src = `./assets/images/${cut.stickerTex}.png`;
        sticker.onerror = () => (sticker.style.display = "none");
      };
      card.appendChild(sticker);

      // Golden 3D Crown on Best Cut!
      if (idx === bestIdx) {
        const crown = document.createElement("img");
        crown.className = "polaroid-crown";
        crown.src = "./assets/fx_crown_gold.png";
        crown.alt = "베스트 컷 왕관";
        crown.draggable = false;
        crown.onerror = () => {
          crown.src = "./assets/images/fx_crown_gold.png";
          crown.onerror = () => (crown.style.display = "none");
        };
        card.appendChild(crown);
      }

      const cap = document.createElement("div");
      cap.className = "polaroid-caption";
      cap.textContent = idx === bestIdx ? (cut.caption || "베스트 컷!") : cut.caption;
      card.appendChild(cap);

      this.el.polaroidGrid.appendChild(card);
    });

    if (this.el.albumSummary) {
      this.el.albumSummary.textContent = summary;
    }
    this.el.screens.clear.classList.add("has-polaroids");
    this.el.polaroidAlbum.classList.remove("hidden");
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
      const p = players.find((pl) => pl.id === z.idx) || (count === 1 ? players[0] : null);
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

    // Double glowing hand tracking halos (only for genuinely tracked on-screen hands!)
    players.forEach((p, idx) => {
      const pid = p.id ?? idx;
      const col = pid === 0 ? "#5CE5D8" : "#FF8A94";
      [p.leftHand, p.rightHand].forEach((pt) => {
        if (!pt || (pt.smoothConf ?? pt.v ?? 1) < 0.22) return;
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

    if (this.screen === "select") {
      if (!this.settings.devMode && this.cameraReady) {
        this.tracker.update(this.settings.players);
        this.updateGlobalAirCursor(dt, w, h);
      }
    } else if (["ready", "countdown", "ingame", "clear"].includes(this.screen)) {
      this.ctx.clearRect(0, 0, w, h);
      if (this.tracker.mode === "pointer") {
        this.drawFallbackBackdrop(w, h);
      }

      const players = this.tracker.update(this.settings.players);

      if (this.screen === "ready" || this.screen === "countdown") {
        this.drawReadyZones(players, w, h, dt);
        if (this.screen === "ready") {
          this.updateGlobalAirCursor(dt, w, h);
        }
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
        this.updateGlobalAirCursor(dt, w, h);
      }
    }

    requestAnimationFrame((t) => this.loop(t));
  }
}

window.addEventListener("DOMContentLoaded", () => {
  new PangPangApp();
});
