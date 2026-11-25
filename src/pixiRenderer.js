/**
 * PixiJS v8 WebGL GPU Renderer for product-grade 2D/2.5D kids game VFX:
 *  - Additive-blend ("add") glowing neon rainbow hand trails & star sparkles
 *  - Pure 3D clay fruit sprites + spinning diagonal-sliced halves
 *  - Slash flash beams, shockwave rings, juicy droplets, and micro screen-shake
 */

const PIXI_CDN = "https://cdn.jsdelivr.net/npm/pixi.js@8.6.6/dist/pixi.min.mjs";

const ASSET_MAP = {
  strawberry: "./assets/fruit_strawberry.png",
  strawberry_left: "./assets/fruit_strawberry_left.png",
  strawberry_right: "./assets/fruit_strawberry_right.png",
  apple: "./assets/fruit_apple.png",
  apple_left: "./assets/fruit_apple_left.png",
  apple_right: "./assets/fruit_apple_right.png",
  orange: "./assets/fruit_orange.png",
  orange_left: "./assets/fruit_orange_left.png",
  orange_right: "./assets/fruit_orange_right.png",
  banana: "./assets/fruit_banana.png",
  banana_left: "./assets/fruit_banana_left.png",
  banana_right: "./assets/fruit_banana_right.png",
  grape: "./assets/fruit_grape.png",
  grape_left: "./assets/fruit_grape_left.png",
  grape_right: "./assets/fruit_grape_right.png",
  peach: "./assets/fruit_peach.png",
  peach_left: "./assets/fruit_peach_left.png",
  peach_right: "./assets/fruit_peach_right.png",
  pineapple: "./assets/fruit_pineapple.png",
  pineapple_left: "./assets/fruit_pineapple_left.png",
  pineapple_right: "./assets/fruit_pineapple_right.png",
  melon: "./assets/fruit_melon.png",
  melon_left: "./assets/fruit_melon_left.png",
  melon_right: "./assets/fruit_melon_right.png",
  watermelon: "./assets/watermelon.png",
  watermelon_left: "./assets/watermelon_left.png",
  watermelon_right: "./assets/watermelon_right.png",
  balloon_red: "./assets/balloon_red.png",
  balloon_beach: "./assets/balloon_beach.png",
  balloon_gold: "./assets/balloon_gold.png",
  dino: "./assets/dino_sprite.png",
};

export class PixiGameRenderer {
  constructor(mountEl) {
    this.mountEl = mountEl;
    this.PIXI = null;
    this.app = null;
    this.ready = false;
    this.textures = {};
    this.root = null;
    this.trailGfx = null;
    this.fxGfx = null;
    this.spriteLayer = null;
    this.textLayer = null;
    this.spritePool = new Map();
    this.textPool = new Map();
  }

  async init() {
    if (this.ready) return true;
    try {
      const PIXI = await import(/* @vite-ignore */ PIXI_CDN);
      this.PIXI = PIXI;

      const app = new PIXI.Application();
      await app.init({
        resizeTo: this.mountEl,
        backgroundAlpha: 0,
        antialias: true,
        resolution: Math.min(window.devicePixelRatio || 1, 2),
        autoDensity: true,
        powerPreference: "high-performance",
      });
      this.mountEl.innerHTML = "";
      this.mountEl.appendChild(app.canvas);
      this.app = app;

      // Load all 3D clay textures in parallel
      const entries = Object.entries(ASSET_MAP);
      const loaded = await Promise.all(
        entries.map(async ([k, url]) => [k, await PIXI.Assets.load(url)])
      );
      loaded.forEach(([k, tex]) => {
        this.textures[k] = tex;
      });

      this.root = new PIXI.Container();
      this.splatGfx = new PIXI.Graphics();
      this.trailGfx = new PIXI.Graphics();
      this.trailGfx.blendMode = "add";

      this.spriteLayer = new PIXI.Container();

      this.fxGfx = new PIXI.Graphics();
      this.fxGfx.blendMode = "add";

      this.uiGfx = new PIXI.Graphics();
      this.textLayer = new PIXI.Container();

      this.root.addChild(this.splatGfx, this.trailGfx, this.spriteLayer, this.uiGfx, this.fxGfx, this.textLayer);
      app.stage.addChild(this.root);

      this.ready = true;
      return true;
    } catch (err) {
      console.warn("PixiJS v8 unavailable, using Canvas2D fallback:", err);
      this.ready = false;
      return false;
    }
  }

  setVisible(visible) {
    if (this.mountEl) {
      this.mountEl.style.display = visible ? "block" : "none";
      if (visible && this.ready && this.app) {
        this.resize(window.innerWidth, window.innerHeight);
      }
    }
  }

  resize(w, h) {
    if (this.ready && this.app && w > 0 && h > 0) {
      this.app.renderer.resize(w, h);
    }
  }

  getSprite(id, texKey) {
    let sp = this.spritePool.get(id);
    if (!sp) {
      sp = new this.PIXI.Sprite(this.textures[texKey]);
      sp.anchor.set(0.5);
      this.spriteLayer.addChild(sp);
      this.spritePool.set(id, sp);
    } else if (this.textures[texKey] && sp.texture !== this.textures[texKey]) {
      sp.texture = this.textures[texKey];
    }
    sp.visible = true;
    return sp;
  }

  getText(id, content, color) {
    let tx = this.textPool.get(id);
    if (!tx) {
      tx = new this.PIXI.Text({
        text: content,
        style: {
          fontFamily: "'Jua', 'Apple SD Gothic Neo', sans-serif",
          fontSize: 34,
          fontWeight: "900",
          fill: "#FFFFFF",
          stroke: { color, width: 7, join: "round" },
          dropShadow: { alpha: 0.25, blur: 6, distance: 3, color: "#000000" },
        },
      });
      tx.anchor.set(0.5);
      this.textLayer.addChild(tx);
      this.textPool.set(id, tx);
    }
    tx.visible = true;
    return tx;
  }

  drawStar(gfx, cx, cy, rOuter, rInner, color, alpha = 1) {
    const pts = [];
    for (let i = 0; i < 10; i++) {
      const r = i % 2 === 0 ? rOuter : rInner;
      const a = -Math.PI / 2 + (i * Math.PI) / 5;
      pts.push(cx + Math.cos(a) * r, cy + Math.sin(a) * r);
    }
    gfx.poly(pts).fill({ color, alpha });
  }

  renderState(state, players, w, h) {
    if (!this.ready) return;

    // Screen shake offset
    const sh = state.screenShake || 0;
    this.root.x = sh > 0.01 ? (Math.random() - 0.5) * 16 * sh : 0;
    this.root.y = sh > 0.01 ? (Math.random() - 0.5) * 12 * sh : 0;

    // Hide pooled sprites/texts before marking active ones
    const activeSprites = new Set();
    const activeTexts = new Set();
    this.spritePool.forEach((sp) => (sp.visible = false));
    this.textPool.forEach((tx) => (tx.visible = false));

    this.splatGfx.clear();
    this.trailGfx.clear();
    this.fxGfx.clear();
    this.uiGfx.clear();

    // 0) 피버 타임 무지개 화면 테두리 오라 + 과즙 스플래시 얼룩!
    if (state.feverActive) {
      const pulse = 0.55 + 0.35 * Math.sin(state.elapsed * 7);
      const hueCols = [0xff6b81, 0xffd43b, 0x5cefe2, 0xc084fc];
      const col = hueCols[Math.floor(state.elapsed * 3) % hueCols.length];
      this.fxGfx.rect(8, 8, w - 16, h - 16).stroke({ color: col, width: 14, alpha: 0.42 * pulse });
    }

    (state.splatters || []).forEach((sp) => {
      const a = Math.max(0, (sp.life / sp.maxLife) * 0.42);
      sp.blobs.forEach((b) => {
        this.splatGfx.circle(sp.x + b.dx, sp.y + b.dy, b.r).fill({ color: sp.hexColor, alpha: a });
      });
    });

    // 1) Glowing additive neon rainbow swipe trails (공리 3: 활성 스윙 시에만 표시)
    state.trails.forEach((tr, slot) => {
      if (tr.length < 2) return;
      const energy = state.handEnergy?.[slot] ?? 0;
      if (energy < 0.08) return;
      const isP1 = tr[0].player === 0;
      const bands = isP1
        ? [
            { col: 0x5cefe2, offset: -7, w: 14 },
            { col: 0xfff380, offset: 0, w: 10 },
            { col: 0xa78bfa, offset: 7, w: 9 },
          ]
        : [
            { col: 0xff7d89, offset: -7, w: 14 },
            { col: 0xffe066, offset: 0, w: 10 },
            { col: 0xff9f5a, offset: 7, w: 9 },
          ];

      bands.forEach((b) => {
        for (let i = 1; i < tr.length; i++) {
          const ratio = i / tr.length;
          this.trailGfx
            .moveTo(tr[i - 1].x, tr[i - 1].y + b.offset)
            .lineTo(tr[i].x, tr[i].y + b.offset)
            .stroke({
              color: b.col,
              width: Math.max(2, b.w * ratio * (0.5 + 0.6 * energy)),
              alpha: ratio * 0.78 * energy,
              cap: "round",
            });
        }
      });
    });

    // 2) Hand halos with Idle Attenuation (공리 3: 정지 시 작고 흐리게 수축, 휘두르면 점화!)
    state.hands.forEach((hd) => {
      const col = hd.player === 0 ? 0x5cefe2 : 0xff828b;
      const e = hd.energy ?? 0;
      const rScale = 0.62 + 0.52 * e;
      const alphaRing = 0.22 + 0.72 * e;
      const alphaFill = 0.06 + 0.22 * e;
      this.fxGfx.circle(hd.x, hd.y, 28 * rScale).fill({ color: col, alpha: alphaFill });
      this.fxGfx.circle(hd.x, hd.y, 22 * rScale).stroke({ color: col, width: 2.5 + 2 * e, alpha: alphaRing });
      this.fxGfx.circle(hd.x, hd.y, 5 + 4 * e).fill({ color: 0xffffff, alpha: 0.35 + 0.6 * e });
    });

    // 3) 3D Clay Fruits (whole + 다중 타격 HP 도트 + 탄성 찌그러짐 + 황금/무지개 오라!)
    if (state.gameId === "fruit") {
      state.fruits.forEach((f) => {
        const sp = this.getSprite(`f_${f.uid}`, f.kind);
        activeSprites.add(`f_${f.uid}`);
        sp.x = f.x;
        sp.y = f.y;
        sp.rotation = f.rot;
        const popScale = f.special !== "normal" ? 1 + 0.08 * Math.sin(state.elapsed * 10) : 1;
        const sq = f.squash || 0;
        const size = f.r * 2.25 * popScale;
        const baseScale = size / Math.max(sp.texture.width, sp.texture.height);
        sp.scale.set(baseScale * (1 + 0.22 * sq), baseScale * (1 - 0.18 * sq));
        sp.alpha = 1;

        if (f.special === "golden") {
          sp.tint = 0xffe875;
          this.fxGfx.circle(f.x, f.y, f.r * 1.45).fill({ color: 0xffd43b, alpha: 0.32 });
          this.fxGfx.circle(f.x, f.y, f.r * 1.25).stroke({ color: 0xfff3a1, width: 5, alpha: 0.9 });
          for (let k = 0; k < 4; k++) {
            const a = state.elapsed * 3 + (k * Math.PI) / 2;
            this.drawStar(this.fxGfx, f.x + Math.cos(a) * f.r * 1.15, f.y + Math.sin(a) * f.r * 1.15, 11, 5, 0xffe866, 0.95);
          }
        } else if (f.special === "rainbow") {
          const rCols = [0xff6b81, 0xffd43b, 0x5cefe2, 0xc084fc];
          const rc = rCols[Math.floor(state.elapsed * 8) % rCols.length];
          sp.tint = 0xffffff;
          this.fxGfx.circle(f.x, f.y, f.r * 1.55).fill({ color: rc, alpha: 0.34 });
          this.fxGfx.circle(f.x, f.y, f.r * 1.35).stroke({ color: 0xffffff, width: 6, alpha: 0.92 });
          for (let k = 0; k < 5; k++) {
            const a = -state.elapsed * 4 + (k * Math.PI * 2) / 5;
            this.drawStar(this.fxGfx, f.x + Math.cos(a) * f.r * 1.22, f.y + Math.sin(a) * f.r * 1.22, 12, 5, rCols[k % 4], 0.95);
          }
        } else {
          sp.tint = sq > 0.25 ? 0xfff4c2 : 0xffffff;
          this.fxGfx.circle(f.x, f.y, f.r * 1.15).fill({ color: f.hexColor, alpha: f.maxHp > 1 ? 0.24 : 0.14 });
          if (f.maxHp > 1) {
            // 단단한 과일(2~3타) 반짝 테두리 & 상단 HP 도트 표시
            this.uiGfx.circle(f.x, f.y, f.r * 1.08).stroke({ color: 0xffffff, width: 3.5, alpha: 0.8 });
            const dotGap = 14;
            const startX = f.x - ((f.maxHp - 1) * dotGap) / 2;
            const dotY = f.y - f.r - 12;
            for (let d = 0; d < f.maxHp; d++) {
              const filled = d < f.hp;
              this.uiGfx
                .circle(startX + d * dotGap, dotY, 5)
                .fill({ color: filled ? 0xffd43b : 0x222c3c, alpha: filled ? 1 : 0.45 })
                .stroke({ color: 0xffffff, width: 1.8 });
            }
          }
        }
      });

      // Multi-Boss Finale (파인애플 -> 멜론 -> 거대 수박 왕!)
      if (state.boss) {
        const b = state.boss;
        const sx = (Math.random() - 0.5) * 20 * b.shake;
        const sy = (Math.random() - 0.5) * 14 * b.shake;
        const bx = b.x + sx;
        const by = b.y + sy;
        const br = b.r * (1 + 0.09 * b.shake);

        // Orbiting glowing golden stars
        for (let i = 0; i < 8; i++) {
          const ang = state.elapsed * 1.5 + (i * Math.PI * 2) / 8;
          const ox = bx + Math.cos(ang) * (br * 1.24);
          const oy = by + Math.sin(ang) * (br * 1.12);
          this.drawStar(this.fxGfx, ox, oy, 13, 5.5, 0xffdc4d, 0.95);
        }
        this.fxGfx.circle(bx, by, br * 1.22).fill({ color: b.hexColor || 0x7ef58a, alpha: 0.25 });

        const sp = this.getSprite(`boss_${b.kind}`, b.kind);
        activeSprites.add(`boss_${b.kind}`);
        sp.x = bx;
        sp.y = by;
        sp.rotation = Math.sin(state.elapsed * 2.5) * 0.06;
        const scale = (br * 2.15) / Math.max(sp.texture.width, sp.texture.height);
        sp.scale.set(scale);
        sp.alpha = 1;
        sp.tint = b.shake > 0.35 ? 0xfff0b3 : 0xffffff;

        // Chunky Mint-to-Yellow Co-op Energy Bar (시안 4번 정중앙 하단 고정)
        const barW = Math.min(340, w * 0.34);
        const barH = 26;
        const barX = w * 0.5 - barW / 2;
        const barY = Math.min(h - 46, h * 0.84);
        const rem = Math.max(0, 1 - state.bossHits / state.bossMaxHits);

        this.uiGfx.roundRect(barX, barY, barW, barH, 13).fill({ color: 0x202a3c, alpha: 0.34 });
        this.uiGfx.roundRect(barX, barY, barW, barH, 13).stroke({ color: 0xffffff, width: 4.5 });
        if (rem > 0.02) {
          this.uiGfx
            .roundRect(barX + 4, barY + 4, (barW - 8) * rem, barH - 8, 9)
            .fill({ color: rem > 0.4 ? 0x62f2c8 : 0xffe055, alpha: 1 });
        }
      }
    } else if (state.gameId === "balloon") {
      (state.balls || []).forEach((b) => {
        const bx = b.x * w;
        const by = b.y * h;
        const br = Math.min(w, h) * b.r;
        const sq = b.squash || 0;

        // 1) 바닥 동적 그림자 (풍선이 바닥에 가까워질수록 크고 진해져 깊이감 제공!)
        const heightRatio = Math.max(0.15, Math.min(1, b.y / 0.88));
        const shadowW = br * (0.55 + 0.65 * heightRatio);
        const shadowH = br * 0.22 * heightRatio;
        this.splatGfx
          .ellipse(bx, h * 0.94, shadowW, shadowH)
          .fill({ color: 0x1e293b, alpha: 0.08 + 0.16 * heightRatio });

        // 2) 풍선 끈 (루비/황금 헬륨 풍선 아래 자연스럽게 흔들리는 하얀 리본 끈!)
        if (b.kind !== "balloon_beach") {
          const knotY = by + br * 1.05;
          const sway = Math.sin(state.elapsed * 4.5 + b.uid) * 14 - (b.vx || 0) * 65;
          this.uiGfx
            .moveTo(bx, knotY)
            .bezierCurveTo(
              bx + sway * 0.4, knotY + br * 0.45,
              bx - sway * 0.5, knotY + br * 0.85,
              bx + sway * 0.8, knotY + br * 1.25
            )
            .stroke({ color: b.kind === "balloon_gold" ? 0xffe484 : 0xffffff, width: 3, alpha: 0.85, cap: "round" });
        }

        // 3) 고시인성 은은한 후광 (황금 풍선 + 콤보 오라)
        const auraCol = b.kind === "balloon_gold" ? 0xffd43b : b.kind === "balloon_red" ? 0xff6b81 : 0x60d5ff;
        this.fxGfx.circle(bx, by, br * (b.kind === "balloon_gold" ? 1.32 : 1.15)).fill({
          color: auraCol,
          alpha: b.kind === "balloon_gold" ? 0.28 : 0.14 + 0.12 * sq,
        });
        if (b.kind === "balloon_gold") {
          for (let k = 0; k < 4; k++) {
            const a = state.elapsed * 2.6 + (k * Math.PI) / 2;
            this.drawStar(this.fxGfx, bx + Math.cos(a) * br * 1.18, by + Math.sin(a) * br * 1.18, 10, 4.5, 0xffe866, 0.92);
          }
        }

        // 4) 투명 3D 풍선/비치볼 스프라이트 (네모 박스 없음! 방향성 탄성 찌그러짐 & 스핀!)
        const sp = this.getSprite(`balloon_${b.uid}`, b.kind);
        activeSprites.add(`balloon_${b.uid}`);
        sp.x = bx;
        sp.y = by;
        sp.tint = 0xffffff;
        sp.alpha = 1;
        sp.rotation = b.rot || 0;
        const targetDim = br * (b.kind === "balloon_beach" ? 2.12 : 2.38);
        const baseScale = targetDim / Math.max(sp.texture.width, sp.texture.height);
        sp.scale.set(baseScale * (1 + 0.22 * sq), baseScale * (1 - 0.19 * sq));
      });
    } else if (state.gameId === "freeze") {
      const cx = w * 0.5;
      const cy = h * 0.46;
      const r = Math.min(w, h) * 0.17;
      const ringCol = state.phase === "freeze" ? 0x60c5ff : 0x5ce596;
      this.fxGfx.circle(cx, cy, r * 1.3).fill({ color: ringCol, alpha: 0.24 });
      this.uiGfx.circle(cx, cy, r * 1.12).stroke({ color: ringCol, width: 7, alpha: 0.85 });
      const sp = this.getSprite("dino_sp", "dino");
      activeSprites.add("dino_sp");
      sp.x = cx;
      sp.y = cy;
      sp.tint = state.phase === "freeze" ? 0xbbe6ff : 0xffffff;
      sp.rotation = state.phase === "freeze" ? 0 : Math.sin(state.elapsed * 8) * 0.09;
      const scale = (r * 2.05) / Math.max(sp.texture.width, sp.texture.height);
      sp.scale.set(scale);
    }

    // 4) Sliced 3D Fruit Halves spinning apart!
    state.halves.forEach((hf) => {
      const sp = this.getSprite(`h_${hf.uid}`, hf.texKey);
      activeSprites.add(`h_${hf.uid}`);
      sp.x = hf.x;
      sp.y = hf.y;
      sp.rotation = hf.rot;
      const scale = (hf.r * 2.2) / Math.max(sp.texture.width, sp.texture.height);
      sp.scale.set(scale);
      sp.alpha = Math.max(0, Math.min(1, hf.life / hf.maxLife));
    });

    // 5) Shockwave rings & slash flash beams
    state.flashes.forEach((fl) => {
      const p = 1 - fl.life / fl.maxLife;
      const a = Math.max(0, 1 - p);
      // Expanding glowing shockwave
      this.fxGfx.circle(fl.x, fl.y, 24 + fl.maxR * p).stroke({ color: fl.hexColor, width: Math.max(2, 10 * a), alpha: a * 0.85 });
      // Crisp white diagonal slash beam
      const len = fl.maxR * (0.8 + 0.5 * p);
      const dx = Math.cos(fl.angle) * len;
      const dy = Math.sin(fl.angle) * len;
      this.fxGfx
        .moveTo(fl.x - dx, fl.y - dy)
        .lineTo(fl.x + dx, fl.y + dy)
        .stroke({ color: 0xffffff, width: Math.max(2, 14 * a), alpha: a, cap: "round" });
    });

    // 5b) 풍선 전용 이중 공기 파동 링 & 무지개 비눗방울 파티클!
    (state.airRings || []).forEach((ar) => {
      const p = 1 - ar.life / ar.maxLife;
      const a = Math.max(0, 1 - p);
      this.fxGfx
        .circle(ar.x, ar.y, ar.r + ar.maxR * p)
        .stroke({ color: ar.hexColor, width: Math.max(2, 7 * a), alpha: a * 0.85 });
    });

    (state.bubbles || []).forEach((bb) => {
      const a = Math.max(0, Math.min(1, bb.life / 0.6));
      this.uiGfx
        .circle(bb.x, bb.y, bb.r)
        .fill({ color: bb.hexColor, alpha: 0.25 * a })
        .stroke({ color: 0xffffff, width: 2, alpha: 0.85 * a });
      this.uiGfx
        .circle(bb.x - bb.r * 0.32, bb.y - bb.r * 0.32, Math.max(1.5, bb.r * 0.24))
        .fill({ color: 0xffffff, alpha: 0.9 * a });
    });

    // 6) Additive glowing particles (stars + juicy droplets) & Floating Score Text
    state.particles.forEach((pt) => {
      const a = Math.max(0, pt.life / pt.maxLife);
      if (pt.text) {
        const tx = this.getText(`t_${pt.uid}`, pt.text, pt.color);
        activeTexts.add(`t_${pt.uid}`);
        tx.x = pt.x;
        tx.y = pt.y;
        tx.alpha = a;
        const mul = pt.bigText ? 1.38 : 1.0;
        tx.scale.set(mul * (0.9 + 0.3 * (1 - a)));
      } else if (pt.star) {
        this.drawStar(this.fxGfx, pt.x, pt.y, pt.size * 1.45 * a, pt.size * 0.6 * a, 0xffdc4d, a);
      } else {
        this.fxGfx.circle(pt.x, pt.y, pt.size * a).fill({ color: pt.hexColor || 0xffdc4d, alpha: a * 0.9 });
      }
    });

    // 7) Confetti & Full-screen Dopamine Flash
    state.confetti.forEach((c) => {
      this.uiGfx
        .rect(c.x - c.size / 2, c.y - c.size / 3, c.size, c.size * 0.66)
        .fill({ color: c.hexColor, alpha: 0.92 });
    });
    if (state.screenFlash > 0.01) {
      this.fxGfx.rect(0, 0, w, h).fill({ color: state.screenFlashHex || 0xffffff, alpha: state.screenFlash * 0.45 });
    }

    // Cleanup dead pooled sprites/texts
    for (const [k, sp] of this.spritePool.entries()) {
      if (!activeSprites.has(k)) {
        this.spriteLayer.removeChild(sp);
        sp.destroy();
        this.spritePool.delete(k);
      }
    }
    for (const [k, tx] of this.textPool.entries()) {
      if (!activeTexts.has(k)) {
        this.textLayer.removeChild(tx);
        tx.destroy();
        this.textPool.delete(k);
      }
    }
  }
}
