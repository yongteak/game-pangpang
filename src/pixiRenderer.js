/**
 * PixiJS v8 WebGL GPU Renderer for product-grade 2D/2.5D kids game VFX:
 *  - Additive-blend ("add") glowing neon rainbow hand trails & star sparkles
 *  - Pure 3D clay fruit sprites + spinning diagonal-sliced halves
 *  - Slash flash beams, shockwave rings, juicy droplets, and micro screen-shake
 */

import { DancePuppetRig, RIG_ASSET_MAP } from "./danceRig.js";

const PIXI_CDN = "https://cdn.jsdelivr.net/npm/pixi.js@8.6.6/dist/pixi.min.mjs";

const ASSET_MAP = {
  ...RIG_ASSET_MAP,
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
  dino_dance1: "./assets/dino_dance1.png",
  dino_dance2: "./assets/dino_dance2.png",
  dino_freeze: "./assets/dino_freeze.png",
  momo_dance1: "./assets/momo_dance1.png",
  momo_dance2: "./assets/momo_dance2.png",
  momo_freeze: "./assets/momo_freeze.png",
  popo_dance1: "./assets/popo_dance1.png",
  popo_dance2: "./assets/popo_dance2.png",
  popo_freeze: "./assets/popo_freeze.png",
  animal_giraffe: "./assets/animal_giraffe.png",
  animal_eagle: "./assets/animal_eagle.png",
  animal_crab: "./assets/animal_crab.png",
  animal_flamingo: "./assets/animal_flamingo.png",
  animal_frog: "./assets/animal_frog.png",
  animal_elephant: "./assets/animal_elephant.png",
  animal_starfish: "./assets/animal_starfish.png",
  momo_head: "./assets/momo_head.png",
  popo_head: "./assets/popo_head.png",
  jungle_vine: "./assets/jungle_vine.png",
  momo_squat: "./assets/momo_squat.png",
  star_3d: "./assets/star_3d.png",
  mole_cute: "./assets/mole_cute.png",
  mole_gold: "./assets/mole_gold.png",
  log_bridge: "./assets/log_bridge.png",
  pose_giraffe: "./assets/pose_giraffe.png",
  pose_eagle: "./assets/pose_eagle.png",
  pose_crab: "./assets/pose_crab.png",
  pose_flamingo: "./assets/pose_flamingo.png",
  pose_frog: "./assets/pose_frog.png",
  pose_elephant: "./assets/pose_elephant.png",
  pose_starfish: "./assets/pose_starfish.png",
  pose_run: "./assets/pose_run.png",
  pose_squat: "./assets/pose_squat.png",
  pose_jump: "./assets/pose_jump.png",
  // Phase 1-4 Pose Game Expansion (15 new 3D clay assets — ./assets/ primary with ./assets/images/ fallback)
  animal_rabbit: ["./assets/animal_rabbit.png", "./assets/images/animal_rabbit.png"],
  animal_trex: ["./assets/animal_trex.png", "./assets/images/animal_trex.png"],
  animal_rocket: ["./assets/animal_rocket.png", "./assets/images/animal_rocket.png"],
  animal_robot: ["./assets/animal_robot.png", "./assets/images/animal_robot.png"],
  animal_heart: ["./assets/animal_heart.png", "./assets/images/animal_heart.png"],
  animal_penguin: ["./assets/animal_penguin.png", "./assets/images/animal_penguin.png"],
  pose_rabbit: ["./assets/pose_rabbit.png", "./assets/images/pose_rabbit.png"],
  pose_trex: ["./assets/pose_trex.png", "./assets/images/pose_trex.png"],
  pose_rocket: ["./assets/pose_rocket.png", "./assets/images/pose_rocket.png"],
  pose_robot: ["./assets/pose_robot.png", "./assets/images/pose_robot.png"],
  pose_heart: ["./assets/pose_heart.png", "./assets/images/pose_heart.png"],
  pose_penguin: ["./assets/pose_penguin.png", "./assets/images/pose_penguin.png"],
  fx_coop_heart: ["./assets/fx_coop_heart.png", "./assets/images/fx_coop_heart.png"],
  fx_wall_frame: ["./assets/fx_wall_frame.png", "./assets/images/fx_wall_frame.png"],
  fx_crown_gold: ["./assets/fx_crown_gold.png", "./assets/images/fx_crown_gold.png"],
};

const HAND_VFX_GAMES = new Set(["fruit", "balloon", "mole"]);

function smoothstep(edge0, edge1, x) {
  const t = Math.max(0, Math.min(1, (x - edge0) / (edge1 - edge0)));
  return t * t * (3 - 2 * t);
}

function lerpHexColor(a, b, t) {
  const k = Math.max(0, Math.min(1, t));
  const ar = (a >> 16) & 0xff, ag = (a >> 8) & 0xff, ab = a & 0xff;
  const br = (b >> 16) & 0xff, bg = (b >> 8) & 0xff, bb = b & 0xff;
  const r = Math.round(ar + (br - ar) * k);
  const g = Math.round(ag + (bg - ag) * k);
  const bl = Math.round(ab + (bb - ab) * k);
  return (r << 16) | (g << 8) | bl;
}

export class PixiGameRenderer {
  constructor(mountEl) {
    this.mountEl = mountEl;
    this.PIXI = null;
    this.app = null;
    this.ready = false;
    this.textures = {};
    this.root = null;
    this.skeletonGfx = null;
    this.trailGfx = null;
    this.fxGfx = null;
    this.spriteLayer = null;
    this.badgeSpriteLayer = null;
    this.textLayer = null;
    this.spritePool = new Map();
    this.rigPool = new Map();
    this.textPool = new Map();
    this.skeletonMatchBlend = 0;
    this.animalGuideMatchBlend = 0;
    this.lastRenderElapsed = 0;
    this.lastRigResetSeq = -1;
    this._rigStateBuf = {
      mode: "dance",
      subAction: "run",
      bpm: 128,
      energy: 0.5,
      tilt: 0,
      frozen: false,
      wiggling: false,
      routineOverride: null,
    };
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

      // Load all 3D clay textures in parallel (gracefully tolerate any not-yet-present textures or multi-path fallbacks!)
      const entries = Object.entries(ASSET_MAP);
      const loaded = await Promise.all(
        entries.map(async ([k, urlOrList]) => {
          const urls = Array.isArray(urlOrList) ? urlOrList : [urlOrList];
          for (const url of urls) {
            try {
              const tex = await PIXI.Assets.load(url);
              if (tex) return [k, tex];
            } catch {
              // try next fallback URL
            }
          }
          return [k, null];
        })
      );
      loaded.forEach(([k, tex]) => {
        if (tex) this.textures[k] = tex;
      });

      this.root = new PIXI.Container();
      this.splatGfx = new PIXI.Graphics();
      this.skeletonGfx = new PIXI.Graphics(); // Normal-blend organic Nintendo body silhouette
      this.trailGfx = new PIXI.Graphics();
      this.trailGfx.blendMode = "add";

      this.spriteLayer = new PIXI.Container();

      this.uiGfx = new PIXI.Graphics();
      this.badgeSpriteLayer = new PIXI.Container(); // Cute 3/4-angled pose icon PNGs on top of cream badge circles

      this.fxGfx = new PIXI.Graphics();
      this.fxGfx.blendMode = "add";

      this.textLayer = new PIXI.Container();

      this.root.addChild(
        this.splatGfx,
        this.skeletonGfx,
        this.trailGfx,
        this.spriteLayer,
        this.uiGfx,
        this.badgeSpriteLayer,
        this.fxGfx,
        this.textLayer
      );
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

  getSprite(id, texKey, targetLayer = null) {
    const tex = this.textures[texKey];
    if (!tex) return null;
    const layer = targetLayer || this.spriteLayer;
    let sp = this.spritePool.get(id);
    if (!sp) {
      sp = new this.PIXI.Sprite(tex);
      sp.anchor.set(0.5);
      layer.addChild(sp);
      this.spritePool.set(id, sp);
    } else {
      if (sp.texture !== tex) sp.texture = tex;
      if (sp.parent !== layer) {
        sp.parent?.removeChild(sp);
        layer.addChild(sp);
      }
    }
    sp.visible = true;
    return sp;
  }

  /**
   * Mounts (once) and updates a pooled 6-part DancePuppetRig with zero per-frame allocations.
   * Falls back cleanly to a single sprite inside DancePuppetRig if any part texture is missing.
   */
  mountOrUpdateRig(id, characterId, baseSize, x, y, dt, rigState, activeRigs, phaseOffset = 0, rootRotation = 0) {
    let rig = this.rigPool.get(id);
    if (!rig) {
      rig = new DancePuppetRig(this.PIXI, this.textures, characterId, baseSize, phaseOffset);
      this.spriteLayer.addChild(rig.root);
      this.rigPool.set(id, rig);
    } else if (rig.characterId !== characterId) {
      rig.destroy();
      rig = new DancePuppetRig(this.PIXI, this.textures, characterId, baseSize, phaseOffset);
      this.spriteLayer.addChild(rig.root);
      this.rigPool.set(id, rig);
    }
    rig.root.visible = true;
    rig.root.x = x;
    rig.root.y = y;
    rig.root.rotation = rootRotation;
    rig.setBaseSize(baseSize);
    rig.update(dt, rigState);
    if (activeRigs) activeRigs.add(id);
    return rig;
  }

  resetAllRigs() {
    this.rigPool.forEach((rig) => rig.resetPhase());
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

  /** Crisp 3D clay golden star with thick navy outline + warm inner highlight */
  drawStar3D(gfx, cx, cy, rOuter, rInner, fillColor = 0xffd43b, strokeColor = 0x1e3a5f, strokeWidth = 4.5) {
    const pts = [];
    const innerPts = [];
    for (let i = 0; i < 10; i++) {
      const r = i % 2 === 0 ? rOuter : rInner;
      const a = -Math.PI / 2 + (i * Math.PI) / 5;
      pts.push(cx + Math.cos(a) * r, cy + Math.sin(a) * r);
      const rh = r * 0.56;
      innerPts.push(cx - rOuter * 0.06 + Math.cos(a) * rh, cy - rOuter * 0.08 + Math.sin(a) * rh);
    }
    gfx.poly(pts).fill({ color: fillColor, alpha: 1 }).stroke({ color: strokeColor, width: strokeWidth, join: "round" });
    gfx.poly(innerPts).fill({ color: 0xfff3a1, alpha: 0.72 });
  }

  /** Draws a smooth circular arc on a Pixi Graphics layer (0..1 progress from 12 o'clock clockwise) */
  drawArcStroke(gfx, cx, cy, r, progress, color, width, alpha = 1) {
    const clamped = Math.max(0, Math.min(1, progress));
    if (clamped <= 0.005) return;
    const steps = Math.max(8, Math.ceil(clamped * 42));
    const startAng = -Math.PI / 2;
    const sweep = Math.PI * 2 * clamped;
    for (let i = 0; i <= steps; i++) {
      const a = startAng + (sweep * i) / steps;
      const x = cx + Math.cos(a) * r;
      const y = cy + Math.sin(a) * r;
      if (i === 0) gfx.moveTo(x, y);
      else gfx.lineTo(x, y);
    }
    gfx.stroke({ color, width, alpha, cap: "round", join: "round" });
  }

  /**
   * Lush Nintendo/Wii circular posture icon badge:
   * - Warm cream circle (#FFFDF5) + soft drop shadow + subtle navy rim
   * - Cute 3/4-angled pose icon PNG (pose_<poseId>.png) centered with circular-safe padding (fallback silhouette if missing)
   * - Smooth glossy green (#22FF88) circular progress ring (0% -> 100%)
   * - Readable pill label underneath
   */
  drawPostureBadge(id, cx, cy, radius, poseId, label, progress, active, activeSprites, activeTexts, opts = {}) {
    const p = Math.max(0, Math.min(1, progress || 0));
    const pulse = opts.pulse || 1.0;
    const inactiveScale = opts.inactiveDim ? 0.90 : 1.0;
    const scaleMul = (active ? 1.06 : inactiveScale) * pulse;
    const r = radius * scaleMul;
    const badgeAlpha = active ? 1.0 : opts.inactiveDim ? 0.68 : 0.86;

    // Soft drop shadow & warm active halo
    this.uiGfx.circle(cx, cy + 5, r + 4).fill({ color: 0x0f172a, alpha: 0.22 * badgeAlpha });
    if (active) {
      this.fxGfx.circle(cx, cy, r + 13).fill({ color: 0x22ff88, alpha: 0.18 + p * 0.14 });
    }

    // Warm cream circular face (#FFFDF5) + crisp subtle rim
    this.uiGfx
      .circle(cx, cy, r)
      .fill({ color: 0xfffdf5, alpha: active ? 0.98 : 0.90 * badgeAlpha })
      .stroke({ color: active ? 0x1e3a5f : 0x64748b, width: active ? 3.5 : 2.8, alpha: active ? 0.90 : 0.62 * badgeAlpha });

    // Background outer progress track
    this.uiGfx.circle(cx, cy, r + 5).stroke({ color: 0xffffff, width: 6, alpha: active ? 0.58 : 0.26 * badgeAlpha });

    // Glossy Nintendo green (#22FF88) circular progress ring (0% -> 100%)
    if (p > 0.01) {
      this.drawArcStroke(this.uiGfx, cx, cy, r + 5, p, 0x22ff88, 7.5, 1);
      this.drawArcStroke(this.fxGfx, cx, cy, r + 5, p, 0x22ff88, 12, 0.36);
    } else if (active) {
      this.uiGfx.circle(cx, cy, r + 5).stroke({ color: 0x22ff88, width: 3.5, alpha: 0.52 });
    }

    // Cute 3/4-angled pose icon PNG sprite (fitted cleanly to radius * 1.56 inside the cream circle!)
    const poseTexKey = `pose_${poseId}`;
    const iconSp = this.getSprite(`badge_ic_${id}`, poseTexKey, this.badgeSpriteLayer);
    if (iconSp) {
      activeSprites.add(`badge_ic_${id}`);
      iconSp.x = cx;
      iconSp.y = cy;
      iconSp.rotation = 0;
      iconSp.tint = 0xffffff;
      iconSp.alpha = badgeAlpha;
      const sc = (r * 1.56) / Math.max(1, iconSp.texture.width, iconSp.texture.height);
      iconSp.scale.set(sc);
    } else {
      // Fallback silhouette only if PNG texture is not yet loaded
      const templates = {
        giraffe:  { hd: [0,-1.02], nk: [0,-0.62], hp: [0,0.18], lE: [-0.42,-0.92], lH: [-0.36,-1.48], rE: [0.42,-0.92], rH: [0.36,-1.48], lK: [-0.24,0.66], lF: [-0.24,1.12], rK: [0.24,0.66], rF: [0.24,1.12] },
        eagle:    { hd: [0,-0.92], nk: [0,-0.52], hp: [0,0.22], lE: [-0.72,-0.52], lH: [-1.28,-0.58], rE: [0.72,-0.52], rH: [1.28,-0.58], lK: [-0.26,0.68], lF: [-0.26,1.12], rK: [0.26,0.68], rF: [0.26,1.12] },
        crab:     { hd: [0,-0.74], nk: [0,-0.38], hp: [0,0.30], lE: [-0.70,-0.34], lH: [-0.74,-0.90], rE: [0.70,-0.34], rH: [0.74,-0.90], lK: [-0.58,0.64], lF: [-0.48,1.10], rK: [0.58,0.64], rF: [0.48,1.10] },
        flamingo: { hd: [0,-0.92], nk: [0,-0.52], hp: [0,0.20], lE: [-0.66,-0.46], lH: [-1.18,-0.44], rE: [0.66,-0.46], rH: [1.18,-0.44], lK: [-0.18,0.68], lF: [-0.18,1.14], rK: [0.50,0.46], rF: [0.16,0.74] },
        frog:     { hd: [0,-0.34], nk: [0,0.02],  hp: [0,0.58], lE: [-0.46,0.42],  lH: [-0.24,0.98],  rE: [0.46,0.42],  rH: [0.24,0.98],  lK: [-0.74,0.46], lF: [-0.56,1.04], rK: [0.74,0.46], rF: [0.56,1.04] },
        elephant: { hd: [0.34,-0.84], nk: [0.22,-0.50], hp: [0,0.20], lE: [0.52,-0.22], lH: [1.02,-0.08], rE: [0.58,-0.36], rH: [1.02,-0.22], lK: [-0.24,0.68], lF: [-0.24,1.12], rK: [0.24,0.68], rF: [0.24,1.12] },
        starfish: { hd: [0,-0.92], nk: [0,-0.52], hp: [0,0.18], lE: [-0.66,-0.84], lH: [-1.14,-1.28], rE: [0.66,-0.84], rH: [1.14,-1.28], lK: [-0.48,0.66], lF: [-0.92,1.14], rK: [0.48,0.66], rF: [0.92,1.14] },
        run:      { hd: [0.10,-0.96], nk: [0.06,-0.56], hp: [-0.04,0.14], lE: [-0.56,-0.26], lH: [-0.28,0.06], rE: [0.52,-0.32], rH: [0.78,-0.68], lK: [-0.48,0.66], lF: [-0.88,1.02], rK: [0.54,0.44], rF: [0.38,0.98] },
        squat:    { hd: [0.06,-0.38], nk: [0.04,-0.02], hp: [-0.14,0.52], lE: [0.46,0.06], lH: [0.92,0.02], rE: [0.40,0.16], rH: [0.84,0.14], lK: [0.46,0.56], lF: [0.24,1.08], rK: [-0.34,0.62], rF: [-0.42,1.08] },
        jump:     { hd: [0,-1.04], nk: [0,-0.64], hp: [0,0.08], lE: [-0.58,-0.96], lH: [-0.86,-1.44], rE: [0.58,-0.96], rH: [0.86,-1.44], lK: [-0.34,0.58], lF: [-0.54,1.04], rK: [0.34,0.58], rF: [0.54,1.04] },
        rabbit:   { hd: [0,-0.88], nk: [0,-0.50], hp: [0,0.22], lE: [-0.44,-0.82], lH: [-0.22,-1.42], rE: [0.44,-0.82], rH: [0.22,-1.42], lK: [-0.22,0.68], lF: [-0.22,1.12], rK: [0.22,0.68], rF: [0.22,1.12] },
        trex:     { hd: [0.12,-0.52], nk: [0.04,-0.16], hp: [-0.08,0.42], lE: [-0.34,0.12], lH: [-0.12,0.22], rE: [0.36,0.06], rH: [0.54,0.18], lK: [-0.36,0.74], lF: [-0.32,1.12], rK: [0.32,0.74], rF: [0.34,1.12] },
        rocket:   { hd: [0,-0.96], nk: [0,-0.56], hp: [0,0.20], lE: [-0.42,-0.24], lH: [-0.46,0.16], rE: [0.36,-0.96], rH: [0.30,-1.52], lK: [-0.22,0.68], lF: [-0.24,1.12], rK: [0.22,0.68], rF: [0.24,1.12] },
        robot:    { hd: [0,-0.92], nk: [0,-0.52], hp: [0,0.22], lE: [-0.62,-0.52], lH: [-0.62,-1.08], rE: [0.62,-0.52], rH: [0.62,0.04], lK: [-0.24,0.68], lF: [-0.24,1.12], rK: [0.24,0.68], rF: [0.24,1.12] },
        heart:    { hd: [0,-0.86], nk: [0,-0.48], hp: [0,0.22], lE: [-0.64,-0.84], lH: [-0.12,-1.32], rE: [0.64,-0.84], rH: [0.12,-1.32], lK: [-0.22,0.68], lF: [-0.22,1.12], rK: [0.22,0.68], rF: [0.22,1.12] },
        penguin:  { hd: [0,-0.90], nk: [0,-0.52], hp: [0,0.22], lE: [-0.52,-0.14], lH: [-0.82,0.26], rE: [0.52,-0.14], rH: [0.82,0.26], lK: [-0.24,0.68], lF: [-0.34,1.12], rK: [0.24,0.68], rF: [0.34,1.12] },
      };
      const tpl = templates[poseId] || templates.squat;
      const s = r * 0.48;
      const oy = cy + r * 0.08;
      const P = (pt) => ({ x: cx + pt[0] * s, y: oy + pt[1] * s });
      const figCol = active ? 0x166534 : 0x334155;
      const lw = Math.max(4, r * 0.115);
      const drawSeg = (a, b) => {
        const pa = P(a), pb = P(b);
        this.uiGfx.moveTo(pa.x, pa.y).lineTo(pb.x, pb.y).stroke({ color: figCol, width: lw, alpha: badgeAlpha, cap: "round" });
      };
      drawSeg(tpl.nk, tpl.hp);
      drawSeg(tpl.nk, tpl.lE); drawSeg(tpl.lE, tpl.lH);
      drawSeg(tpl.nk, tpl.rE); drawSeg(tpl.rE, tpl.rH);
      drawSeg(tpl.hp, tpl.lK); drawSeg(tpl.lK, tpl.lF);
      drawSeg(tpl.hp, tpl.rK); drawSeg(tpl.rK, tpl.rF);
      const hdP = P(tpl.hd);
      this.uiGfx.circle(hdP.x, hdP.y, s * 0.27).fill({ color: figCol, alpha: badgeAlpha });
    }

    // Crisp readable pill label underneath the cream circle
    if (label) {
      const lblY = cy + r + 23;
      const pillW = Math.max(100, label.length * 14 + 28);
      this.uiGfx
        .roundRect(cx - pillW / 2, lblY - 14, pillW, 28, 14)
        .fill({ color: active ? 0x166534 : 0x0f172a, alpha: active ? 0.94 : 0.72 * badgeAlpha })
        .stroke({ color: active ? 0x22ff88 : 0xffffff, width: 2.2, alpha: active ? 0.95 : 0.75 * badgeAlpha });
      const tx = this.getText(`badge_lbl_${id}`, label, active ? "#14532d" : "#0f172a");
      activeTexts.add(`badge_lbl_${id}`);
      tx.text = label;
      tx.x = cx;
      tx.y = lblY;
      tx.alpha = badgeAlpha;
      tx.scale.set(0.46);
    }
  }

  /**
   * Commercial Zero-Flicker Organic Nintendo Body Silhouette (Normal Blend):
   * - Smooth central spine (neckMid -> hipMid) + curved shoulder arc + subtle pelvis arc
   * - Tapered rounded limbs (upper arm/thigh thicker, forearm/shin slimmer)
   * - Calm open head halo (no filled dot over the child's face)
   * - ZERO rectangular torso cage, ZERO harsh white joint dots, ZERO hard blinking cutoffs!
   * - Per-segment smoothstep(0.12, 0.48, smoothConf) alpha + warm radiant mint-green match bloom!
   */
  drawLiveSkeleton(players, w, h, matched, dt = 0.016, calmMode = false, rainbowMode = false, elapsed = 0) {
    const targetBlend = matched ? 1.0 : 0.0;
    this.skeletonMatchBlend += (targetBlend - this.skeletonMatchBlend) * Math.min(1, dt * 8.0);
    const mb = this.skeletonMatchBlend;

    const baseAlpha = calmMode
      ? 0.28 + (0.56 - 0.28) * mb
      : 0.42 + (0.80 - 0.42) * mb;

    const rainbowPalette = [0x22ff88, 0x38bdf8, 0xc084fc, 0xff4d8d, 0xffd43b];
    const rainbowIdx = Math.floor(elapsed * 4.5);
    const rainbowFrac = (elapsed * 4.5) % 1;
    const rainbowCol = lerpHexColor(
      rainbowPalette[rainbowIdx % rainbowPalette.length],
      rainbowPalette[(rainbowIdx + 1) % rainbowPalette.length],
      rainbowFrac
    );

    players.forEach((p, idx) => {
      if (!p.shoulders || !p.elbows || !p.hips) return;
      const pid = p.id ?? idx;
      const idleCol = rainbowMode ? rainbowCol : pid === 0 ? 0x67e8f9 : 0xfda4af;
      const glowCol = rainbowMode ? rainbowCol : 0x22ff88;
      const col = lerpHexColor(idleCol, rainbowMode ? rainbowCol : 0x22ff88, mb);
      const pt = (j) =>
        j
          ? { x: j.x * w, y: j.y * h, c: j.smoothConf ?? j.v ?? 1 }
          : null;

      const head = pt(p.head);
      const shL = pt(p.shoulders[0]), shR = pt(p.shoulders[1]);
      const elL = pt(p.elbows[0]), elR = pt(p.elbows[1]);
      const wrL = pt(p.leftHand), wrR = pt(p.rightHand);
      const hpL = pt(p.hips[0]), hpR = pt(p.hips[1]);
      const knL = pt(p.knees?.[0]), knR = pt(p.knees?.[1]);
      const anL = pt(p.ankles?.[0]), anR = pt(p.ankles?.[1]);

      if (!shL || !shR || !hpL || !hpR) return;

      const neckMid = { x: (shL.x + shR.x) * 0.5, y: (shL.y + shR.y) * 0.5, c: Math.min(shL.c, shR.c) };
      const hipMid = { x: (hpL.x + hpR.x) * 0.5, y: (hpL.y + hpR.y) * 0.5, c: Math.min(hpL.c, hpR.c) };
      const glowStrength = rainbowMode ? Math.max(0.55, mb) : mb;

      const drawOrganicLine = (a, b, width) => {
        if (!a || !b) return;
        const vis = smoothstep(0.12, 0.48, Math.min(a.c, b.c));
        if (vis < 0.02) return;
        if (glowStrength > 0.04) {
          this.skeletonGfx
            .moveTo(a.x, a.y)
            .lineTo(b.x, b.y)
            .stroke({ color: glowCol, width: width + (rainbowMode ? 12 : 8), alpha: 0.24 * glowStrength * vis, cap: "round" });
        }
        this.skeletonGfx
          .moveTo(a.x, a.y)
          .lineTo(b.x, b.y)
          .stroke({ color: col, width, alpha: baseAlpha * vis, cap: "round" });
      };

      const drawOrganicArc = (a, ctrlX, ctrlY, b, width) => {
        if (!a || !b) return;
        const vis = smoothstep(0.12, 0.48, Math.min(a.c, b.c));
        if (vis < 0.02) return;
        if (glowStrength > 0.04) {
          this.skeletonGfx
            .moveTo(a.x, a.y)
            .quadraticCurveTo(ctrlX, ctrlY, b.x, b.y)
            .stroke({ color: glowCol, width: width + (rainbowMode ? 12 : 8), alpha: 0.24 * glowStrength * vis, cap: "round" });
        }
        this.skeletonGfx
          .moveTo(a.x, a.y)
          .quadraticCurveTo(ctrlX, ctrlY, b.x, b.y)
          .stroke({ color: col, width, alpha: baseAlpha * vis, cap: "round" });
      };

      // 1) Smooth central spine (neckMid -> hipMid)
      drawOrganicLine(neckMid, hipMid, 14);

      // 2) Soft curved shoulder arc & subtle pelvis arc (NO boxy torso cage!)
      drawOrganicArc(shL, neckMid.x, neckMid.y - Math.max(8, h * 0.012), shR, 12);
      drawOrganicArc(hpL, hipMid.x, hipMid.y + Math.max(4, h * 0.006), hpR, 10);

      // 3) Tapered rounded arms (upper arm 11px -> forearm 8px)
      drawOrganicLine(shL, elL, 11);
      drawOrganicLine(elL, wrL, 8);
      drawOrganicLine(shR, elR, 11);
      drawOrganicLine(elR, wrR, 8);

      // 4) Tapered rounded legs (thigh 11px -> shin 8px)
      drawOrganicLine(hpL, knL, 11);
      drawOrganicLine(knL, anL, 8);
      drawOrganicLine(hpR, knR, 11);
      drawOrganicLine(knR, anR, 8);

      // 5) Calm open head halo (no filled dot over the child's face!)
      if (head) {
        const hVis = smoothstep(0.12, 0.48, head.c);
        if (hVis >= 0.02) {
          if (glowStrength > 0.04) {
            this.skeletonGfx.circle(head.x, head.y, 20).stroke({ color: glowCol, width: 9, alpha: 0.22 * glowStrength * hVis });
          }
          this.skeletonGfx.circle(head.x, head.y, 18).stroke({ color: col, width: 4, alpha: baseAlpha * hVis });
        }
      }
    });
  }

  renderState(state, players, w, h) {
    if (!this.ready) return;

    // Screen shake offset
    const sh = state.screenShake || 0;
    this.root.x = sh > 0.01 ? (Math.random() - 0.5) * 16 * sh : 0;
    this.root.y = sh > 0.01 ? (Math.random() - 0.5) * 12 * sh : 0;

    // Hide pooled sprites/texts/rigs before marking active ones
    const activeSprites = new Set();
    const activeTexts = new Set();
    const activeRigs = new Set();
    this.spritePool.forEach((sp) => (sp.visible = false));
    this.textPool.forEach((tx) => (tx.visible = false));
    this.rigPool.forEach((rig) => (rig.root.visible = false));

    if (state.rigResetSeq !== undefined && state.rigResetSeq !== this.lastRigResetSeq) {
      this.lastRigResetSeq = state.rigResetSeq;
      this.resetAllRigs();
    }

    const renderDt = Math.max(0.008, Math.min(0.1, (state.elapsed || 0) - (this.lastRenderElapsed || 0)));
    this.lastRenderElapsed = state.elapsed || 0;

    this.splatGfx.clear();
    this.skeletonGfx.clear();
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

    // 1) & 2) Hand swipe trails & glowing hand halos ONLY in hand-action games (fruit, balloon, mole)!
    // Completely hidden in animal, freeze, jungle, and balance for clean Nintendo/Wii visual hierarchy.
    if (HAND_VFX_GAMES.has(state.gameId)) {
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

      state.hands.forEach((hd) => {
        const col = hd.player === 0 ? 0x5cefe2 : 0xff828b;
        const e = hd.energy ?? 0;
        const confFade = smoothstep(0.18, 0.45, hd.conf ?? 1);
        if (confFade < 0.02) return;
        const rScale = 0.62 + 0.52 * e;
        const alphaRing = (0.22 + 0.72 * e) * confFade;
        const alphaFill = (0.06 + 0.22 * e) * confFade;
        this.fxGfx.circle(hd.x, hd.y, 28 * rScale).fill({ color: col, alpha: alphaFill });
        this.fxGfx.circle(hd.x, hd.y, 22 * rScale).stroke({ color: col, width: 2.5 + 2 * e, alpha: alphaRing });
        this.fxGfx.circle(hd.x, hd.y, 5 + 4 * e).fill({ color: 0xffffff, alpha: (0.35 + 0.6 * e) * confFade });
      });
    }

    // 3) 3D Clay Fruits (whole + 다중 타격 HP 도트 + 탄성 찌그러짐 + 황금/무지개 오라!)
    if (state.gameId === "fruit") {
      state.fruits.forEach((f) => {
        const sp = this.getSprite(`f_${f.uid}`, f.kind);
        if (!sp) return;
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
        if (sp) {
          activeSprites.add(`boss_${b.kind}`);
          sp.x = bx;
          sp.y = by;
          sp.rotation = Math.sin(state.elapsed * 2.5) * 0.06;
          const scale = (br * 2.15) / Math.max(sp.texture.width, sp.texture.height);
          sp.scale.set(scale);
          sp.alpha = 1;
          sp.tint = b.shake > 0.35 ? 0xfff0b3 : 0xffffff;
        }

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
        if (sp) {
          activeSprites.add(`balloon_${b.uid}`);
          sp.x = bx;
          sp.y = by;
          sp.tint = 0xffffff;
          sp.alpha = 1;
          sp.rotation = b.rot || 0;
          const targetDim = br * (b.kind === "balloon_beach" ? 2.12 : 2.38);
          const baseScale = targetDim / Math.max(sp.texture.width, sp.texture.height);
          sp.scale.set(baseScale * (1 + 0.22 * sq), baseScale * (1 - 0.19 * sq));
        }
      });
    } else if (state.gameId === "freeze") {
      const isFreeze = state.phase === "freeze";
      const t = state.elapsed;
      const rate = Math.min(1.22, 1.0 + (state.round || 0) * 0.045);
      const beatHz = (128 / 60) * rate;
      const beatPulse = isFreeze ? 0 : Math.pow(Math.max(0, Math.cos(t * Math.PI * beatHz)), 4);
      const energy = isFreeze ? 0 : Math.max(0.35, state.danceEnergy || 0.4);

      // 1) 나이트클럽 네온 어둠 필터 (카메라 인물은 선명하게 보이면서 네온 조명이 확 살아남!)
      this.splatGfx.rect(0, 0, w, h).fill({
        color: isFreeze ? 0x061d36 : 0x0e0524,
        alpha: isFreeze ? 0.36 : 0.30 - beatPulse * 0.06,
      });

      // 2) 회전하는 클럽 레이저 & 스포트라이트 빔!
      if (!isFreeze) {
        const beams = [
          { ox: w * 0.06, oy: -10, col: 0xff2d95, base: 1.05, amp: 0.48, spd: 1.7, ph: 0.0 },
          { ox: w * 0.22, oy: -10, col: 0x00f5ff, base: 1.32, amp: 0.42, spd: 2.1, ph: 1.2 },
          { ox: w * 0.50, oy: -10, col: 0xffe600, base: 1.57, amp: 0.55, spd: 1.5, ph: 2.4 },
          { ox: w * 0.50, oy: -10, col: 0xb84dff, base: 1.57, amp: -0.55, spd: 1.9, ph: 0.6 },
          { ox: w * 0.78, oy: -10, col: 0x22ff88, base: 1.82, amp: 0.42, spd: 2.2, ph: 3.1 },
          { ox: w * 0.94, oy: -10, col: 0xff6b35, base: 2.08, amp: 0.48, spd: 1.6, ph: 4.2 },
        ];
        const len = Math.hypot(w, h) * 1.15;
        beams.forEach((bm) => {
          const ang = bm.base + Math.sin(t * bm.spd + bm.ph) * bm.amp;
          const spread = 0.095 + beatPulse * 0.045;
          const x1 = bm.ox + Math.cos(ang - spread) * len;
          const y1 = bm.oy + Math.sin(ang - spread) * len;
          const x2 = bm.ox + Math.cos(ang + spread) * len;
          const y2 = bm.oy + Math.sin(ang + spread) * len;
          this.fxGfx
            .poly([bm.ox, bm.oy, x1, y1, x2, y2])
            .fill({ color: bm.col, alpha: 0.16 + beatPulse * 0.12 });
        });
      } else {
        // 얼음! 순간: 클럽 조명 뚝 끊기고 중앙 차가운 아이스 스포트라이트 1개만 투사!
        this.fxGfx
          .poly([w * 0.5, -10, w * 0.18, h + 20, w * 0.82, h + 20])
          .fill({ color: 0x38bdf8, alpha: 0.22 });
      }

      // 3) 상단 회전 미러볼 (Disco Mirror Ball) + 사방에 흩어지는 미러볼 반짝이 점!
      const ballX = w * 0.5;
      const ballY = Math.min(82, h * 0.13);
      const ballR = Math.min(w, h) * 0.068;
      this.uiGfx.moveTo(ballX, 0).lineTo(ballX, ballY - ballR).stroke({ color: 0xe2e8f0, width: 3.5, alpha: 0.85 });
      this.fxGfx.circle(ballX, ballY, ballR * (1.45 + beatPulse * 0.35)).fill({
        color: isFreeze ? 0x60c5ff : 0xe879f9,
        alpha: isFreeze ? 0.22 : 0.34,
      });
      this.uiGfx.circle(ballX, ballY, ballR).fill({ color: isFreeze ? 0x93c5fd : 0xe2e8f0, alpha: 0.96 });
      this.uiGfx.circle(ballX, ballY, ballR).stroke({ color: 0xffffff, width: 2.5, alpha: 0.9 });
      // 미러볼 타일 반사 하이라이트
      const tileCols = [0xff2d95, 0x00f5ff, 0xffe600, 0xffffff, 0xb84dff];
      for (let row = -2; row <= 2; row++) {
        for (let col = -3; col <= 3; col++) {
          const shift = isFreeze ? 0 : (t * 2.2) % 1;
          const fx = ballX + ((col + shift - 0.5) / 3.4) * ballR * 0.92;
          const fy = ballY + (row / 2.8) * ballR * 0.85;
          if (Math.hypot(fx - ballX, fy - ballY) < ballR * 0.82) {
            const cIdx = Math.abs(row * 5 + col) % tileCols.length;
            this.uiGfx
              .rect(fx - 3.5, fy - 3, 7, 6)
              .fill({ color: isFreeze ? 0xe0f2fe : tileCols[cIdx], alpha: 0.72 });
          }
        }
      }
      // 벽/화면에 흩어지는 미러볼 반짝이 빛방울 16개
      for (let k = 0; k < 16; k++) {
        const ang = (isFreeze ? 0 : t * (0.45 + (k % 3) * 0.18)) + k * 0.92;
        const dist = (0.24 + ((k * 37) % 100) / 140) * Math.min(w, h);
        const dx = w * 0.5 + Math.cos(ang) * dist * 1.45;
        const dy = h * 0.45 + Math.sin(ang * 1.1) * dist * 0.85;
        const c = isFreeze ? 0xbae6fd : tileCols[k % tileCols.length];
        this.fxGfx.circle(dx, dy, 4.5 + (k % 3) * 2.5 + beatPulse * 4).fill({ color: c, alpha: isFreeze ? 0.35 : 0.65 });
      }

      // 4) 하단 네온 클럽 이퀄라이저 스펙트럼 바 (24개, 비트 & 움직임 에너지에 맞춰 춤춤!)
      const barCount = 24;
      const barGap = 5;
      const barW = (w - 48 - barGap * (barCount - 1)) / barCount;
      const eqCols = [0xff2d95, 0xc084fc, 0x00f5ff, 0x22ff88, 0xffe600];
      for (let i = 0; i < barCount; i++) {
        const wave = isFreeze
          ? 0.08
          : 0.22 + 0.48 * Math.abs(Math.sin(t * 7.5 + i * 0.55)) + 0.35 * beatPulse * Math.abs(Math.cos(i * 0.4 + t * 3));
        const bh = Math.max(8, wave * h * 0.20 * (0.65 + energy * 0.65));
        const bx = 24 + i * (barW + barGap);
        const by = h - bh - 10;
        const col = isFreeze ? 0x38bdf8 : eqCols[i % eqCols.length];
        this.fxGfx.roundRect(bx, by, barW, bh, 5).fill({ color: col, alpha: isFreeze ? 0.35 : 0.72 });
      }

      // 5) 비트에 맞춰 번쩍이는 네온 클럽 테두리 프레임! (얼음 중 움직이면 빨간 경고 테두리!)
      const isWiggling = isFreeze && Boolean(state.isWiggling);
      const borderCol = isWiggling ? 0xff4757 : isFreeze ? 0x38bdf8 : tileCols[Math.floor(t * beatHz) % tileCols.length];
      this.fxGfx.rect(6, 6, w - 12, h - 12).stroke({
        color: borderCol,
        width: isWiggling ? 22 : isFreeze ? 14 : 8 + beatPulse * 12,
        alpha: isWiggling ? 0.92 : isFreeze ? 0.78 : 0.35 + beatPulse * 0.55,
      });

      // 5b) 얼음 남은 시간 예측 프로그레스 바 (3~5초 카운트다운!) + 하단 움직임 감지 위험 게이지
      if (isFreeze) {
        const dur = Math.max(0.1, state.freezeDuration || 3.5);
        const remRatio = Math.max(0, Math.min(1, (state.phaseTimer || 0) / dur));
        const remSec = Math.max(0, state.phaseTimer || 0).toFixed(1);

        const barW = Math.min(360, w * 0.40);
        const barH = 26;
        const barX = w * 0.5 - barW / 2;
        const barY = Math.min(h - 74, h * 0.80);

        // 남은 얼음 시간 프로그레스 바 (눈으로 땡! 타이밍 예측 가능!)
        this.uiGfx.roundRect(barX, barY, barW, barH, 13).fill({ color: 0x0f172a, alpha: 0.65 });
        this.uiGfx.roundRect(barX, barY, barW, barH, 13).stroke({ color: 0xbae6fd, width: 3.5 });
        if (remRatio > 0.015) {
          const fillCol = remRatio < 0.25 ? 0x22ff88 : 0x38bdf8;
          this.uiGfx
            .roundRect(barX + 4, barY + 4, (barW - 8) * remRatio, barH - 8, 9)
            .fill({ color: fillCol, alpha: 0.96 });
        }
        const tx = this.getText("freeze_timer_lbl", `❄️ ${remSec}초`, "#0284c7");
        activeTexts.add("freeze_timer_lbl");
        tx.text = remRatio < 0.25 ? `⚡ 곧 땡!! ${remSec}초` : `❄️ 얼음 버티기 ${remSec}초`;
        tx.x = w * 0.5;
        tx.y = barY - 22;
        tx.alpha = 1;
        tx.scale.set(0.82);

        // 하단 슬림 움직임 감지 위험 게이지
        const dBarW = Math.min(240, w * 0.26);
        const dBarH = 12;
        const dBarX = w * 0.5 - dBarW / 2;
        const dBarY = barY + barH + 10;
        const danger = Math.min(1, (state.freezeWiggleTime || 0) / 0.48);
        this.uiGfx.roundRect(dBarX, dBarY, dBarW, dBarH, 6).fill({ color: 0x0f172a, alpha: 0.55 });
        this.uiGfx.roundRect(dBarX, dBarY, dBarW, dBarH, 6).stroke({ color: isWiggling ? 0xff4757 : 0x7dd3fc, width: 2 });
        if (danger > 0.02) {
          this.uiGfx
            .roundRect(dBarX + 2, dBarY + 2, (dBarW - 4) * danger, dBarH - 4, 4)
            .fill({ color: danger >= 0.85 ? 0xff4757 : danger >= 0.3 ? 0xffd43b : 0x38bdf8, alpha: 1 });
        }
      }

      // 6) 라운드 합류형 클럽 댄서들! (1R 디노 -> 2~3R 모모 합류 -> 4~5R 포포까지 3마리 완전체 6파츠 관절 떼춤!)
      const rnd = state.round || 0;
      const lineup =
        rnd >= 3
          ? [
              { id: "momo", nx: 0.24, ny: 0.56, scaleMul: 0.94, phaseOffset: 0.35, col: 0x00f5ff },
              { id: "dino", nx: 0.50, ny: 0.53, scaleMul: 1.04, phaseOffset: 0.00, col: 0xff2d95 },
              { id: "popo", nx: 0.76, ny: 0.56, scaleMul: 0.94, phaseOffset: -0.35, col: 0xffe600 },
            ]
          : rnd >= 1
          ? [
              { id: "momo", nx: 0.34, ny: 0.55, scaleMul: 0.98, phaseOffset: 0.35, col: 0x00f5ff },
              { id: "dino", nx: 0.66, ny: 0.55, scaleMul: 1.04, phaseOffset: 0.00, col: 0xff2d95 },
            ]
          : [{ id: "dino", nx: 0.50, ny: 0.53, scaleMul: 1.15, phaseOffset: 0.00, col: 0xff2d95 }];

      const baseR = Math.min(w, h) * 0.165;
      const rigBuf = this._rigStateBuf;
      rigBuf.mode = "dance";
      rigBuf.subAction = "run";
      rigBuf.bpm = state.danceBpm || 128 * rate;
      rigBuf.energy = state.danceEnergy !== undefined ? state.danceEnergy : energy;
      rigBuf.tilt = 0;
      rigBuf.frozen = isFreeze;
      rigBuf.wiggling = isWiggling;
      rigBuf.routineOverride = state.freezeRoutineOverride ?? null;

      lineup.forEach((d) => {
        const cx = w * d.nx;
        const cy = h * d.ny;
        const r = baseR * d.scaleMul;
        const ringCol = isFreeze ? 0x60c5ff : d.col;

        // Render dancer glow & neon ring on splatGfx (BEHIND spriteLayer) so rings never slice across dancers' faces!
        this.splatGfx.circle(cx, cy, r * (1.2 + beatPulse * 0.22)).fill({ color: ringCol, alpha: isFreeze ? 0.24 : 0.28 });
        this.splatGfx.circle(cx, cy, r * (1.02 + beatPulse * 0.08)).stroke({ color: ringCol, width: 6, alpha: 0.88 });

        this.mountOrUpdateRig(
          `rig_freeze_${d.id}`,
          d.id,
          r * 2.15,
          cx,
          cy + r * 0.06,
          renderDt,
          rigBuf,
          activeRigs,
          d.phaseOffset,
          0
        );
      });
    } else if (state.gameId === "animal") {
      const list = state.animalList || [];
      const idx = Math.min(list.length - 1, state.animalIndex || 0);
      const cur = list[idx];
      if (cur) {
        const t = state.elapsed;
        const matched = Boolean(state.animalMatch);
        const holdRatio = Math.max(0, Math.min(1, (state.animalHold || 0) / Math.max(0.1, state.animalHoldTarget || 1.8)));
        const timeRatio = Math.max(0, Math.min(1, (state.animalTimer || 0) / Math.max(0.1, state.animalTimeLimit || 10)));
        const combo = state.animalCombo || 0;
        const rainbowMode = Boolean(state.animalRainbowAura);
        const isCompact = h < 500 || w < 960;

        // Smooth AR hologram match blend (0 -> 1) for alpha & golden-mint aura pop
        const targetGuideBlend = matched ? 1.0 : 0.0;
        this.animalGuideMatchBlend += (targetGuideBlend - this.animalGuideMatchBlend) * Math.min(1, renderDt * 8.0);
        const guideMb = this.animalGuideMatchBlend;

        // 4-Layer Glossy Pill Helper (Shadow + Base + Top Specular Highlight + Rim)
        const drawGlossyPill = (x, y, pw, ph, fillHex, strokeHex = 0xffffff, strokeW = 3.5) => {
          const r = ph * 0.5;
          // 1) Soft drop shadow
          this.uiGfx.roundRect(x, y + 4, pw, ph, r).fill({ color: 0x0f172a, alpha: 0.24 });
          // 2) Main glossy body
          this.uiGfx.roundRect(x, y, pw, ph, r).fill({ color: fillHex, alpha: 0.98 });
          // 3) Top glass specular highlight
          this.uiGfx.roundRect(x + 8, y + 3, Math.max(12, pw - 16), ph * 0.36, r * 0.5).fill({ color: 0xffffff, alpha: 0.34 });
          // 4) Crisp outer rim
          this.uiGfx.roundRect(x, y, pw, ph, r).stroke({ color: strokeHex, width: strokeW, alpha: 0.96 });
        };

        // 0) Zero-flicker organic Nintendo body silhouette (calm -> mint-green -> rainbow neon at 3+ COMBO!)
        this.drawLiveSkeleton(players, w, h, matched, renderDt, false, rainbowMode, t);

        // --- PHASE 2: 2P CO-OP COMBINED POSE BONUS ROUND (Round 4 — Clean Top-Center Ribbon Swap!) ---
        if (cur.isCoop) {
          const ribW = isCompact
            ? Math.min(440, Math.max(220, w - 340))
            : Math.min(500, Math.max(260, w - 340));
          const ribH = isCompact ? 40 : 54;
          const ribX = w * 0.5 - ribW * 0.5;
          const ribY = isCompact ? 16 : 22;
          const tailW = isCompact ? 18 : 34;
          // Left & right folded ribbon tails
          this.uiGfx
            .poly([ribX - tailW, ribY + 8, ribX + 10, ribY + 8, ribX + 10, ribY + ribH + 4, ribX - tailW, ribY + ribH + 4, ribX - tailW * 0.55, ribY + ribH * 0.5 + 6])
            .fill({ color: 0xd93870, alpha: 0.96 })
            .stroke({ color: 0xffd43b, width: 3 });
          this.uiGfx
            .poly([ribX + ribW + tailW, ribY + 8, ribX + ribW - 10, ribY + 8, ribX + ribW - 10, ribY + ribH + 4, ribX + ribW + tailW, ribY + ribH + 4, ribX + ribW + tailW * 0.55, ribY + ribH * 0.5 + 6])
            .fill({ color: 0xd93870, alpha: 0.96 })
            .stroke({ color: 0xffd43b, width: 3 });
          // Main pink-gold glossy ribbon
          drawGlossyPill(ribX, ribY, ribW, ribH, 0xff4d8d, 0xffd43b, isCompact ? 3.5 : 4.2);
          const coopTitleTx = this.getText("coop_title", cur.title, "#9d174d");
          activeTexts.add("coop_title");
          coopTitleTx.text = cur.title;
          coopTitleTx.x = w * 0.5;
          coopTitleTx.y = ribY + ribH * 0.5;
          coopTitleTx.alpha = 1;
          coopTitleTx.scale.set(Math.min(isCompact ? 0.58 : 0.74, (ribW - 36) / Math.max(240, cur.title.length * 23)));

          // Centered Pink Percentage Progress Bar underneath ribbon
          const pBarW = Math.min(280, w * 0.30);
          const pBarH = isCompact ? 22 : 26;
          const pBarX = w * 0.5 - pBarW * 0.5;
          const pBarY = ribY + ribH + (isCompact ? 8 : 14);
          this.uiGfx
            .roundRect(pBarX, pBarY, pBarW, pBarH, pBarH * 0.5)
            .fill({ color: 0xfff5eb, alpha: 0.94 })
            .stroke({ color: 0xd4a373, width: 3 });
          if (holdRatio > 0.02) {
            this.uiGfx
              .roundRect(pBarX + 4, pBarY + 4, (pBarW - 8) * holdRatio, pBarH - 8, (pBarH - 8) * 0.5)
              .fill({ color: matched ? 0xff4d8d : 0xfb7185, alpha: 1 });
          }
          const pctTx = this.getText("coop_pct", `${Math.round(holdRatio * 100)}%`, "#9d174d");
          activeTexts.add("coop_pct");
          pctTx.text = `${Math.round(holdRatio * 100)}%`;
          pctTx.x = w * 0.5;
          pctTx.y = pBarY + pBarH * 0.5;
          pctTx.alpha = 1;
          pctTx.scale.set(isCompact ? 0.46 : 0.56);

          // Midpoint Hologram Anchor ((p1Hand + p2Hand)/2) + Dual-Color Giant Heart Arc!
          const mid = state.coopMidpoint || { x: 0.5, y: 0.52 };
          const prox = state.coopProximity || 0;
          const hx = mid.x * w;
          const hy = Math.max(pBarY + pBarH + 56, mid.y * h);
          const heartScale = 0.68 + prox * 0.54 + (matched ? 0.10 * Math.sin(t * 10) : 0);
          const arcR = Math.min(w, h) * 0.25 * (0.85 + prox * 0.2);

          // Dual-color glowing giant heart arc (Mint left for P1 + Coral-Pink right for P2!)
          this.fxGfx
            .moveTo(hx, hy - arcR * 0.45)
            .bezierCurveTo(hx - arcR * 0.95, hy - arcR * 1.15, hx - arcR * 1.35, hy + arcR * 0.25, hx, hy + arcR * 1.05)
            .stroke({ color: 0x5cefe2, width: matched ? 16 : 10, alpha: 0.42 + prox * 0.45, cap: "round" });
          this.fxGfx
            .moveTo(hx, hy - arcR * 0.45)
            .bezierCurveTo(hx + arcR * 0.95, hy - arcR * 1.15, hx + arcR * 1.35, hy + arcR * 0.25, hx, hy + arcR * 1.05)
            .stroke({ color: 0xff7d89, width: matched ? 16 : 10, alpha: 0.42 + prox * 0.45, cap: "round" });

          // Center Hologram Heart sprite (fx_coop_heart.png) + orbiting golden sparkles!
          const heartDim = Math.min(w, h) * 0.22 * heartScale;
          this.fxGfx.circle(hx, hy, heartDim * 0.65).fill({ color: 0xff6b9d, alpha: 0.22 + prox * 0.24 });
          const hsp = this.getSprite("coop_heart_holo", "fx_coop_heart");
          if (hsp) {
            activeSprites.add("coop_heart_holo");
            hsp.x = hx;
            hsp.y = hy + Math.sin(t * 5) * 6;
            hsp.rotation = Math.sin(t * 2.5) * 0.06;
            hsp.tint = 0xffffff;
            hsp.alpha = 0.85 + prox * 0.15;
            const sc = heartDim / Math.max(1, hsp.texture.width, hsp.texture.height);
            hsp.scale.set(sc);
          } else {
            this.uiGfx.circle(hx, hy, heartDim * 0.36).fill({ color: 0xff4d8d, alpha: 0.92 }).stroke({ color: 0xffd43b, width: 4 });
          }

          // Orbiting golden stars around midpoint hologram scaling with proximity
          const starCount = 6;
          for (let k = 0; k < starCount; k++) {
            const ang = t * (1.8 + prox * 1.8) + (k * Math.PI * 2) / starCount;
            const sx = hx + Math.cos(ang) * heartDim * 0.68;
            const sy = hy + Math.sin(ang) * heartDim * 0.58;
            this.drawStar(this.fxGfx, sx, sy, 10 + prox * 6, 4.5 + prox * 2.5, k % 2 === 0 ? 0xffd43b : 0xfff3a1, 0.72 + prox * 0.28);
          }

          // Momo (Bottom-Left) + Popo (Bottom-Right) 3D Clay Corner Mascot Guides!
          const mascotDim = Math.min(w, h) * (isCompact ? 0.26 : 0.30);
          const mSp = this.getSprite("coop_momo", matched ? "momo_dance1" : "momo_dance2");
          if (mSp) {
            activeSprites.add("coop_momo");
            mSp.x = Math.max(76, w * 0.11);
            mSp.y = h - mascotDim * 0.46 + Math.sin(t * 5) * 5;
            mSp.rotation = 0.06;
            mSp.tint = 0xffffff;
            mSp.alpha = 1;
            const sc = mascotDim / Math.max(1, mSp.texture.width, mSp.texture.height);
            mSp.scale.set(sc);
          }
          const pSp = this.getSprite("coop_popo", matched ? "popo_dance1" : "popo_dance2");
          if (pSp) {
            activeSprites.add("coop_popo");
            pSp.x = w - Math.max(76, w * 0.11);
            pSp.y = h - mascotDim * 0.46 + Math.cos(t * 5) * 5;
            pSp.rotation = -0.06;
            pSp.tint = 0xffffff;
            pSp.alpha = 1;
            const sc = mascotDim / Math.max(1, pSp.texture.width, pSp.texture.height);
            pSp.scale.set(sc);
          }
          return;
        }

        // --- PHASE 3: APPROACHING SILHOUETTE WALL BONUS ROUND (Round 5 — Clean Top-Center Banner Swap!) ---
        if (cur.isWall) {
          const wScale = state.wallScale || 0.22;
          const stage = state.wallStage || 1;
          const wallCx = w * 0.5;
          const wallCy = h * 0.55;

          // 1) Glowing perspective floor rails converging toward center
          const railCols = [0xffe066, 0x5cefe2, 0x5cefe2, 0xffe066];
          const railBottomX = [w * 0.14, w * 0.34, w * 0.66, w * 0.86];
          const railTopX = [w * 0.36, w * 0.45, w * 0.55, w * 0.64];
          for (let r = 0; r < 4; r++) {
            this.fxGfx
              .moveTo(railBottomX[r], h + 10)
              .lineTo(railTopX[r], h * 0.66)
              .stroke({ color: matched ? 0x22ff88 : railCols[r], width: r === 1 || r === 2 ? 7 : 5, alpha: 0.62, cap: "round" });
          }

          // 2) Approaching Wall Sprite (fx_wall_frame.png) with perspective scale s(t) = 0.22 + 0.98 * t^2.2
          const wallW = w * 0.86 * wScale;
          const wallH = h * 0.72 * wScale;
          const wsp = this.getSprite("wall_frame_main", "fx_wall_frame");
          if (wsp) {
            activeSprites.add("wall_frame_main");
            wsp.x = wallCx;
            wsp.y = wallCy;
            wsp.rotation = 0;
            wsp.tint = matched ? 0xd9ffe8 : 0xffffff;
            wsp.alpha = Math.min(0.96, 0.45 + wScale * 0.55);
            const sx = wallW / Math.max(1, wsp.texture.width);
            const sy = wallH / Math.max(1, wsp.texture.height);
            wsp.scale.set(sx, sy);
          } else {
            // Graceful puffy pastel rainbow foam wall fallback
            const wx = wallCx - wallW * 0.5;
            const wy = wallCy - wallH * 0.5;
            this.uiGfx
              .roundRect(wx, wy, wallW, wallH, Math.max(16, 44 * wScale))
              .stroke({ color: 0x93c5fd, width: Math.max(10, 34 * wScale), alpha: 0.85 });
            this.uiGfx
              .roundRect(wx + 8 * wScale, wy + 8 * wScale, wallW - 16 * wScale, wallH - 16 * wScale, Math.max(12, 36 * wScale))
              .stroke({ color: 0xf9a8d4, width: Math.max(4, 10 * wScale), alpha: 0.75 });
          }

          // 3) Glowing Neon Cutout Rim + Orbiting Golden Stars
          const cutR = Math.min(wallW, wallH) * 0.36;
          const rimCol = matched ? 0x22ff88 : 0x38bdf8;
          this.fxGfx.circle(wallCx, wallCy, cutR).stroke({ color: rimCol, width: Math.max(6, 18 * wScale), alpha: matched ? 0.85 : 0.48 });
          this.uiGfx.circle(wallCx, wallCy, cutR).stroke({ color: matched ? 0x86efac : 0xbae6fd, width: Math.max(3, 6 * wScale), alpha: 0.92 });

          for (let k = 0; k < 6; k++) {
            const ang = t * 1.4 + (k * Math.PI * 2) / 6;
            const sx = wallCx + Math.cos(ang) * cutR * 1.04;
            const sy = wallCy + Math.sin(ang) * cutR * 0.96;
            this.drawStar3D(this.uiGfx, sx, sy, Math.max(8, 18 * wScale), Math.max(4, 8 * wScale), 0xffd43b, 0x1e3a5f, Math.max(1.5, 3 * wScale));
          }

          // 4) Top-center glossy sky-blue 4-layer pill + 5-Stage Progress Bar!
          const pillW = Math.min(440, Math.max(240, w - (isCompact ? 260 : 320)));
          const pillH = isCompact ? 42 : 52;
          const pillX = w * 0.5 - pillW * 0.5;
          const pillY = isCompact ? 16 : 22;
          drawGlossyPill(pillX, pillY, pillW, pillH, 0x38bdf8, 0xffffff, isCompact ? 3.2 : 4);
          const wTitleTx = this.getText("wall_title", cur.title, "#0369a1");
          activeTexts.add("wall_title");
          wTitleTx.text = cur.title;
          wTitleTx.x = w * 0.5;
          wTitleTx.y = pillY + pillH * 0.5;
          wTitleTx.alpha = 1;
          wTitleTx.scale.set(isCompact ? 0.58 : 0.74);

          // 5-Stage Segmented Progress Bar right under pill
          const segCount = 5;
          const segW = isCompact ? 36 : 46;
          const segH = isCompact ? 14 : 18;
          const segGap = 6;
          const totalSegW = segCount * segW + (segCount - 1) * segGap;
          const segStartX = w * 0.5 - totalSegW * 0.5;
          const segY = pillY + pillH + (isCompact ? 8 : 12);
          this.uiGfx
            .roundRect(segStartX - 8, segY - 4, totalSegW + 16, segH + 8, 12)
            .fill({ color: 0x1e3a5f, alpha: 0.78 })
            .stroke({ color: 0xffffff, width: 2.5 });
          for (let s = 0; s < segCount; s++) {
            const filled = s < stage;
            const sx = segStartX + s * (segW + segGap);
            const segCol = filled ? (s >= 3 ? 0x22ff88 : 0x67e8f9) : 0x334155;
            this.uiGfx.roundRect(sx, segY, segW, segH, 6).fill({ color: segCol, alpha: filled ? 1 : 0.65 });
          }

          // 5) Bottom-Left Warm Cream Circular Pose Badge showing target pose!
          const badgeRad = isCompact ? 30 : Math.min(54, Math.min(w, h) * 0.082);
          this.drawPostureBadge(
            "wall_pose",
            isCompact ? 64 : Math.max(92, w * 0.095),
            isCompact ? h - 78 : h - Math.max(98, h * 0.155),
            badgeRad,
            cur.wallPoseId || cur.id,
            cur.shortCue || cur.name,
            Math.min(1, wScale / 1.1),
            true,
            activeSprites,
            activeTexts,
            { pulse: matched ? 1.0 + 0.05 * Math.sin(t * 10) : 1.0 }
          );
          return;
        }

        // --- PHASE 1: CENTER-HERO ANIMAL POSE LAYOUT (De-Cluttered Right Side + Compact Top-Center Header!) ---
        // 1) Top-Left: Circular Pie Countdown Timer cleanly aligned next to DOM Pause button (x: 28..80)
        const pieR = isCompact ? 15 : 24;
        const pieX = isCompact ? 98 : 114;
        const pieY = isCompact ? 34 : 44;
        this.splatGfx.circle(pieX, pieY, pieR + 3).fill({ color: 0xffffff, alpha: 0.96 });
        this.uiGfx.circle(pieX, pieY, pieR + 3).stroke({ color: 0x1e3a5f, width: isCompact ? 2.8 : 3.8 });
        if (timeRatio > 0.01) {
          const pts = [pieX, pieY];
          const steps = 28;
          const endAng = -Math.PI / 2 + Math.PI * 2 * timeRatio;
          for (let s = 0; s <= steps; s++) {
            const a = -Math.PI / 2 + ((endAng + Math.PI / 2) * s) / steps;
            pts.push(pieX + Math.cos(a) * (pieR - 2), pieY + Math.sin(a) * (pieR - 2));
          }
          this.uiGfx.poly(pts).fill({ color: timeRatio < 0.28 ? 0xff5c5c : 0xffd43b, alpha: 1 });
        }

        // 2) Top-Left: 7-Round Mini Relay Badges right next to pie timer (zero overlap with center or right!)
        const badgeR = isCompact ? 10.5 : Math.min(19, w * 0.018);
        const gap = badgeR * (isCompact ? 2.22 : 2.28);
        const startX = pieX + pieR + (isCompact ? 16 : 28);
        const badgeY = pieY;
        const trackColors = [0x4ade80, 0xf9a8d4, 0x34d399, 0x60a5fa, 0xc084fc, 0xfbbf24, 0xfb7185];
        list.forEach((a, i) => {
          const bx = startX + i * gap;
          const isCur = i === idx;
          const isDone = Boolean(state.animalCleared?.[i]);
          if (isCur) {
            this.fxGfx.circle(bx, badgeY, badgeR + (isCompact ? 6 : 8)).fill({ color: 0x22ff88, alpha: 0.42 + 0.16 * Math.sin(t * 7) });
          }
          this.splatGfx
            .circle(bx, badgeY, badgeR + (isCur ? (isCompact ? 2.5 : 3.5) : 0))
            .fill({ color: isDone ? 0xfff3b0 : trackColors[i % trackColors.length], alpha: 0.96 });
          this.uiGfx
            .circle(bx, badgeY, badgeR + (isCur ? (isCompact ? 2.5 : 3.5) : 0))
            .stroke({ color: isCur ? 0xffffff : isDone ? 0x22c55e : 0xffffff, width: isCur ? (isCompact ? 3 : 3.8) : 2.2 });
          const asp = this.getSprite(`ab_${i}_${a.id}`, a.isCoop ? "fx_coop_heart" : a.tex);
          if (asp) {
            activeSprites.add(`ab_${i}_${a.id}`);
            asp.x = bx;
            asp.y = badgeY;
            asp.rotation = 0;
            asp.tint = 0xffffff;
            asp.alpha = isDone ? 0.78 : 1;
            const asc = (badgeR * 1.62) / Math.max(1, asp.texture.width, asp.texture.height);
            asp.scale.set(asc);
          }
          if (isDone) {
            this.drawStar3D(this.uiGfx, bx + badgeR * 0.65, badgeY + badgeR * 0.65, isCompact ? 6 : 9, isCompact ? 2.8 : 4, 0xffd43b, 0x1e3a5f, 1.6);
          }
        });

        // 3) Top-Right: ONLY ⭐ Score (DOM) + 🔥 N COMBO! when combo >= 2 (ZERO right-side clutter!)
        if (combo >= 2) {
          const comboText = `🔥 ${combo} COMBO!`;
          const cPillW = isCompact ? 126 : 158;
          const cPillH = isCompact ? 30 : 42;
          // On compact mobile landscape (852x393), tuck Combo pill cleanly BELOW the DOM Score pill so they never collide!
          const cPillX = isCompact ? w - cPillW - 22 : w - 332;
          const cPillY = isCompact ? 74 : 23;
          const cPulse = combo >= 3 ? 1 + 0.045 * Math.sin(t * 9) : 1;
          if (combo >= 3) {
            this.fxGfx.roundRect(cPillX - 5, cPillY - 5, cPillW + 10, cPillH + 10, 22).fill({ color: 0xff8c00, alpha: 0.34 });
          }
          drawGlossyPill(cPillX, cPillY, cPillW, cPillH, combo >= 3 ? 0xff6b00 : 0xff8c24, 0xffe875, isCompact ? 2.6 : 3);
          const cTx = this.getText("animal_combo", comboText, "#9a3412");
          activeTexts.add("animal_combo");
          cTx.text = comboText;
          cTx.x = cPillX + cPillW * 0.5;
          cTx.y = cPillY + cPillH * 0.5;
          cTx.alpha = 1;
          cTx.scale.set((isCompact ? 0.48 : 0.62) * cPulse);
        }

        // 4) Clean, Compact TOP-CENTER Header (x = w * 0.50, y ≈ 66..154px):
        //    [Animal Name Pill] + [1-line Cue] + [Hold Progress Bar + 3D Gold Star]
        const headerX = w * 0.5;
        const baseTitle = cur.title || cur.name;
        const titleText = cur.isBoss ? `👑 ${baseTitle} 2배!` : cur.speedUp ? `⚡ ${baseTitle}` : baseTitle;
        const pillFill = cur.isBoss ? 0xf59e0b : cur.hex;
        const pillStroke = cur.isBoss ? 0xfff3a1 : 0xffffff;

        let barY;
        if (isCompact) {
          // Compact mobile landscape (e.g. 852x393): sleek 2-tier top-center header (y = 52..99px) -> ZERO overlap with badges or center-hero!
          const titleW = Math.min(186, Math.max(124, titleText.length * 14 + 30));
          const cueW = Math.min(238, Math.max(144, cur.cue.length * 10.5 + 24));
          const rowGap = 8;
          const totalW = titleW + rowGap + cueW;
          const rowLeft = headerX - totalW * 0.5;
          const rowY = 66;
          const rowH = 28;

          drawGlossyPill(rowLeft, rowY - rowH * 0.5, titleW, rowH, pillFill, pillStroke, 2.6);
          const nameTx = this.getText("animal_name", titleText, cur.isBoss ? "#78350f" : "#7c2d12");
          activeTexts.add("animal_name");
          nameTx.text = titleText;
          nameTx.x = rowLeft + titleW * 0.5;
          nameTx.y = rowY;
          nameTx.alpha = 1;
          nameTx.scale.set(0.52);

          const cueLeft = rowLeft + titleW + rowGap;
          this.uiGfx
            .roundRect(cueLeft, rowY - 12, cueW, 24, 12)
            .fill({ color: 0x0f172a, alpha: 0.72 })
            .stroke({ color: matched ? 0x22ff88 : 0xffffff, width: 1.8, alpha: 0.90 });
          const cueTx = this.getText("animal_cue", cur.cue, "#0f172a");
          activeTexts.add("animal_cue");
          cueTx.text = cur.cue;
          cueTx.x = cueLeft + cueW * 0.5;
          cueTx.y = rowY;
          cueTx.alpha = 1;
          cueTx.scale.set(0.42);

          barY = 86;
        } else {
          // Desktop / Tablet / TV (e.g. 1280x720): crisp 3-tier top-center header (y = 82..154px) -> 36px clean gap above center-hero!
          const titlePillH = 44;
          const titlePillW = Math.min(w * 0.36, Math.max(210, titleText.length * 22 + 52));
          const pillY = 82;
          drawGlossyPill(headerX - titlePillW * 0.5, pillY - titlePillH * 0.5, titlePillW, titlePillH, pillFill, pillStroke, 3.8);
          const nameTx = this.getText("animal_name", titleText, cur.isBoss ? "#78350f" : "#7c2d12");
          activeTexts.add("animal_name");
          nameTx.text = titleText;
          nameTx.x = headerX;
          nameTx.y = pillY;
          nameTx.alpha = 1;
          nameTx.scale.set(0.78);

          const cueY = pillY + 38;
          const cuePillW = Math.min(w * 0.42, Math.max(220, cur.cue.length * 14 + 36));
          this.uiGfx
            .roundRect(headerX - cuePillW * 0.5, cueY - 15, cuePillW, 30, 15)
            .fill({ color: 0x0f172a, alpha: 0.72 })
            .stroke({ color: matched ? 0x22ff88 : 0xffffff, width: 2.2, alpha: 0.90 });
          const cueTx = this.getText("animal_cue", cur.cue, "#0f172a");
          activeTexts.add("animal_cue");
          cueTx.text = cur.cue;
          cueTx.x = headerX;
          cueTx.y = cueY;
          cueTx.alpha = 1;
          cueTx.scale.set(0.54);

          barY = cueY + 21;
        }

        // Glossy Green Hold Progress Bar + 3D Gold Star centered under header
        const barW = isCompact ? Math.min(200, w * 0.26) : Math.min(276, w * 0.25);
        const barH = isCompact ? 13 : 20;
        const barX = headerX - barW * 0.5 - 8;
        this.uiGfx
          .roundRect(barX, barY, barW, barH, barH * 0.5)
          .fill({ color: 0x0f172a, alpha: 0.70 })
          .stroke({ color: 0xffffff, width: isCompact ? 2.2 : 3.2 });
        if (holdRatio > 0.02) {
          this.uiGfx
            .roundRect(barX + 3, barY + 3, (barW - 6) * holdRatio, barH - 6, (barH - 6) * 0.5)
            .fill({ color: cur.isBoss ? 0xffd43b : matched ? 0x22ff88 : 0x34d399, alpha: 1 });
        }
        const starX = barX + barW + (isCompact ? 8 : 10);
        const starY = barY + barH * 0.5;
        if (matched || holdRatio > 0.72) {
          this.fxGfx.circle(starX, starY, isCompact ? 18 : 28).fill({ color: 0xffd43b, alpha: 0.36 + 0.14 * Math.sin(t * 10) });
        }
        const starOutR = isCompact ? (matched ? 14 : 12) : (matched ? 22 : 18);
        this.drawStar3D(this.uiGfx, starX, starY, starOutR, starOutR * 0.46, 0xffd43b, 0x1e3a5f, isCompact ? 2.8 : 4);

        // 5) Bottom-Left: Cute 3/4 Momo Circular Pose Badge (cleanly clear of center-hero and viewport bottom!)
        const badgeRad = isCompact ? 30 : Math.min(54, Math.min(w, h) * 0.082);
        this.drawPostureBadge(
          "animal_cur",
          isCompact ? 64 : Math.max(92, w * 0.095),
          isCompact ? h - 78 : h - Math.max(98, h * 0.155),
          badgeRad,
          cur.id,
          cur.shortCue || cur.name,
          holdRatio,
          true,
          activeSprites,
          activeTexts,
          { pulse: matched ? 1.0 + 0.045 * Math.sin(t * 9) : 1.0 }
        );

        // 6) CENTER-HERO Animal Guide (Nintendo AR Hologram Partner right next to the child!)
        const guideX = w * 0.50;
        const guideY = isCompact ? h * 0.58 : h * 0.52;
        const guideDim = Math.min(w, h) * (isCompact ? 0.45 : 0.50);

        // Soft glowing AR hologram halo behind guide (warm soft glow -> golden-mint aura on match!)
        const haloCol = cur.isBoss
          ? 0xffd43b
          : lerpHexColor(0xfff6d6, 0x22ff88, guideMb);
        const outerHaloAlpha = cur.isBoss
          ? 0.24 + 0.10 * Math.sin(t * 7)
          : 0.14 + 0.20 * guideMb + 0.06 * Math.sin(t * (matched ? 9 : 3.2));
        this.fxGfx.circle(guideX, guideY, guideDim * (0.50 + 0.06 * guideMb)).fill({
          color: haloCol,
          alpha: outerHaloAlpha,
        });
        this.fxGfx.circle(guideX, guideY, guideDim * (0.37 + 0.04 * guideMb)).fill({
          color: cur.isBoss ? 0xfff3a1 : lerpHexColor(0xffffff, 0xffd43b, guideMb * 0.65),
          alpha: 0.12 + 0.14 * guideMb,
        });
        if (guideMb > 0.05) {
          this.fxGfx.circle(guideX, guideY, guideDim * (0.48 + 0.04 * Math.sin(t * 8))).stroke({
            color: rainbowMode ? 0xffd43b : 0x22ff88,
            width: 6,
            alpha: 0.45 * guideMb,
          });
          this.fxGfx.rect(8, 8, w - 16, h - 16).stroke({
            color: rainbowMode ? 0xffd43b : 0x38ef7d,
            width: 10,
            alpha: 0.36 * guideMb,
          });
        }

        const gsp = this.getSprite(`aguide_${cur.id}`, cur.tex);
        if (gsp) {
          activeSprites.add(`aguide_${cur.id}`);
          gsp.x = guideX;
          gsp.y = guideY + Math.sin(t * (matched ? 8 : 3)) * (matched ? 8 : 4);
          gsp.rotation = Math.sin(t * 2.5) * 0.035;
          gsp.tint = 0xffffff;
          // Clean semi-transparent AR hologram presence (0.88 -> 1.00 on match!)
          gsp.alpha = 0.88 + 0.12 * guideMb;
          const gsc = guideDim / Math.max(1, gsp.texture.width, gsp.texture.height);
          gsp.scale.set(gsc * (1.0 + 0.06 * guideMb));
        }

        // Golden Boss Crown floating above Center-Hero guide (clamped cleanly below Hold Bar!)
        if (cur.isBoss) {
          const csp = this.getSprite("boss_pose_crown", "fx_crown_gold");
          if (csp) {
            activeSprites.add("boss_pose_crown");
            const minCrownY = barY + barH + (isCompact ? 18 : 24);
            const idealCrownY = guideY - guideDim * 0.44;
            csp.x = guideX;
            csp.y = Math.max(minCrownY, idealCrownY) + Math.sin(t * 5) * 3;
            csp.rotation = Math.sin(t * 3) * 0.08;
            csp.tint = 0xffffff;
            csp.alpha = 0.92 + 0.08 * guideMb;
            const csc = (guideDim * (isCompact ? 0.24 : 0.28)) / Math.max(1, csp.texture.width, csp.texture.height);
            csp.scale.set(csc);
          }
        }
      }
    } else if (state.gameId === "jungle") {
      const t = state.elapsed;
      const phase = state.junglePhase || "run";
      const trackP = Math.max(0, Math.min(1, state.jungleTrackProgress || 0));
      const remSec = Math.max(0, Math.ceil((state.jungleDuration || 60) - (state.jungleElapsed || 0)));

      // 0) Calm organic Nintendo body silhouette (alpha 0.28 -> 0.56)
      this.drawLiveSkeleton(players, w, h, Boolean(state.jungleActiveDetected), renderDt, true);

      // 1) Top 5-Checkpoint Jungle Progress Track lifted cleanly into freed upper space!
      const trackW = Math.min(540, w * 0.54);
      const trackH = 18;
      const trackX = w * 0.5 - trackW * 0.5;
      const trackY = 64;

      this.uiGfx
        .roundRect(trackX - 8, trackY - 8, trackW + 16, trackH + 16, 17)
        .fill({ color: 0x0f172a, alpha: 0.52 })
        .stroke({ color: 0xfffdf5, width: 3.5, alpha: 0.94 });
      this.uiGfx.roundRect(trackX, trackY, trackW, trackH, 9).fill({ color: 0x1e293b, alpha: 0.68 });
      if (trackP > 0.01) {
        this.uiGfx
          .roundRect(trackX, trackY, trackW * trackP, trackH, 9)
          .fill({ color: 0x22ff88, alpha: 0.98 });
      }
      // 5 Checkpoint Flags
      for (let i = 1; i <= 5; i++) {
        const fx = trackX + (trackW * i) / 5;
        const passed = (state.jungleCheckpoints || 0) >= i;
        this.uiGfx.moveTo(fx, trackY + 2).lineTo(fx, trackY - 22).stroke({ color: 0xfffdf5, width: 3, cap: "round" });
        this.uiGfx
          .poly([fx, trackY - 22, fx + 16, trackY - 15, fx, trackY - 8])
          .fill({ color: passed ? 0xffd43b : 0x94a3b8, alpha: 1 })
          .stroke({ color: 0x1e3a5f, width: 2 });
        if (passed) {
          this.drawStar3D(this.uiGfx, fx + 7, trackY - 15, 7, 3.2, 0xffd43b, 0x1e3a5f, 1.8);
        }
      }
      // Bouncing Momo marker on track
      const momoTrackX = trackX + trackW * trackP;
      const momoTrackY = trackY + trackH * 0.5 - Math.abs(Math.sin(t * 9)) * 7;
      const mHead = this.getSprite("jungle_momo_track", "momo_head");
      if (mHead) {
        activeSprites.add("jungle_momo_track");
        mHead.x = momoTrackX;
        mHead.y = momoTrackY;
        mHead.rotation = Math.sin(t * 9) * 0.1;
        mHead.alpha = 1;
        mHead.tint = 0xffffff;
        const sc = 44 / Math.max(mHead.texture.width, mHead.texture.height);
        mHead.scale.set(sc);
      } else {
        this.uiGfx.circle(momoTrackX, momoTrackY, 15).fill({ color: 0x4ad3c8, alpha: 1 }).stroke({ color: 0x1e3a5f, width: 3 });
      }

      // Countdown pill beside track with readable dark backing
      const timerX = trackX + trackW + 64;
      const timerY = trackY + 9;
      this.uiGfx
        .roundRect(timerX - 46, timerY - 17, 92, 34, 17)
        .fill({ color: 0x0f172a, alpha: 0.68 })
        .stroke({ color: 0xfffdf5, width: 2.2, alpha: 0.85 });
      const timerTx = this.getText("jungle_time", `⏱️ ${remSec}초`, "#0f172a");
      activeTexts.add("jungle_time");
      timerTx.text = `⏱️ ${remSec}초`;
      timerTx.x = timerX;
      timerTx.y = timerY;
      timerTx.alpha = 1;
      timerTx.scale.set(0.56);

      // 2) Phase-specific 3D clay props + Live 6-part DancePuppetRig Momo guide!
      if (phase === "run") {
        if (state.jungleActiveDetected) {
          for (let k = 0; k < 6; k++) {
            const ly = h * (0.18 + k * 0.13);
            const len = 36 + ((t * 280 + k * 53) % 70);
            this.fxGfx.moveTo(16, ly).lineTo(16 + len, ly).stroke({ color: 0x22ff88, width: 5, alpha: 0.55, cap: "round" });
            this.fxGfx.moveTo(w - 16, ly).lineTo(w - 16 - len, ly).stroke({ color: 0xffe875, width: 5, alpha: 0.55, cap: "round" });
          }
        }
      } else if (phase === "squat") {
        const vy = (state.jungleVineY ?? 0.36) * h;
        const vSp = this.getSprite("jungle_vine_prop", "jungle_vine");
        if (vSp) {
          activeSprites.add("jungle_vine_prop");
          vSp.x = w * 0.5;
          vSp.y = vy;
          vSp.rotation = Math.sin(t * 2.4) * 0.018;
          vSp.tint = state.jungleActiveDetected ? 0xd9ffe6 : 0xffffff;
          vSp.alpha = 1;
          const scaleX = (w * 0.96) / Math.max(1, vSp.texture.width);
          const scaleY = Math.min(scaleX, (h * 0.30) / Math.max(1, vSp.texture.height));
          vSp.scale.set(scaleX, Math.max(scaleY, scaleX * 0.72));
        } else {
          this.uiGfx.roundRect(w * 0.04, vy - 26, w * 0.92, 52, 26).fill({ color: 0x16a34a, alpha: 0.94 }).stroke({ color: 0x14532d, width: 5 });
        }
        for (let i = 0; i < 5; i++) {
          const sx = w * (0.16 + i * 0.17);
          const sy = vy + Math.sin(t * 4 + i * 1.3) * 14;
          this.fxGfx.circle(sx, sy, 22).fill({ color: 0xffd43b, alpha: 0.35 });
          this.drawStar3D(this.uiGfx, sx, sy, 15, 7, 0xffd43b, 0x1e3a5f, 3);
        }
        if (state.jungleActiveDetected) {
          this.fxGfx.rect(8, 8, w - 16, h - 16).stroke({ color: 0x22ff88, width: 12, alpha: 0.42 });
        }
      } else if (phase === "jump") {
        (state.jungleStars || []).forEach((st) => {
          if (st.collected) return;
          const sx = st.x * w;
          const sy = st.y * h;
          const sr = Math.min(w, h) * st.r;
          const pulse = 1 + 0.1 * Math.sin(t * 7 + st.seed);
          this.fxGfx.circle(sx, sy, sr * 1.45 * pulse).fill({ color: 0xffd43b, alpha: 0.32 });
          this.fxGfx.circle(sx, sy, sr * 1.15).stroke({ color: 0xfff3a1, width: 4, alpha: 0.85 });

          const sp = this.getSprite(`jstar_${st.uid}`, "star_3d");
          if (sp) {
            activeSprites.add(`jstar_${st.uid}`);
            sp.x = sx;
            sp.y = sy;
            sp.rotation = Math.sin(t * 3 + st.seed) * 0.18;
            sp.tint = 0xffffff;
            sp.alpha = 1;
            const sc = (sr * 2.3 * pulse) / Math.max(sp.texture.width, sp.texture.height);
            sp.scale.set(sc);
          } else {
            this.drawStar3D(this.uiGfx, sx, sy, sr * 1.05 * pulse, sr * 0.48 * pulse, 0xffd43b, 0x1e3a5f, 4.5);
          }
        });
      }

      // Live 6-part Momo puppet smoothly cross-fading between run / squat / jump!
      const jRigBuf = this._rigStateBuf;
      jRigBuf.mode = "jungle";
      jRigBuf.subAction = state.jungleSubAction || phase;
      jRigBuf.bpm = state.jungleActiveDetected ? 142 : 116;
      jRigBuf.energy = state.jungleEnergy !== undefined ? state.jungleEnergy : (state.jungleActiveDetected ? 0.95 : 0.45);
      jRigBuf.tilt = 0;
      jRigBuf.frozen = false;
      jRigBuf.wiggling = false;
      jRigBuf.routineOverride = null;
      this.mountOrUpdateRig(
        "rig_jungle_momo",
        "momo",
        Math.min(w, h) * 0.30,
        w * 0.16,
        h * 0.56,
        renderDt,
        jRigBuf,
        activeRigs,
        0,
        0
      );

      // 3) Bottom 3 circular move badges with cute 3/4-angled pose_run / pose_squat / pose_jump PNGs!
      const bR = Math.min(50, Math.min(w, h) * 0.076);
      const bY = h - Math.max(92, h * 0.148);
      this.drawPostureBadge(
        "jungle_run",
        Math.max(76, w * 0.08),
        bY,
        bR,
        "run",
        "제자리 달리기",
        phase === "run" ? state.junglePhaseProgress : 0,
        phase === "run",
        activeSprites,
        activeTexts,
        { inactiveDim: true }
      );
      this.drawPostureBadge(
        "jungle_squat",
        Math.max(196, w * 0.08 + bR * 2.55),
        bY,
        bR,
        "squat",
        "웅크리기(스쿼트)",
        phase === "squat" ? state.junglePhaseProgress : 0,
        phase === "squat",
        activeSprites,
        activeTexts,
        { inactiveDim: true }
      );
      this.drawPostureBadge(
        "jungle_jump",
        w - Math.max(82, w * 0.085),
        bY,
        bR,
        "jump",
        "점프 만세!",
        phase === "jump" ? state.junglePhaseProgress : 0,
        phase === "jump",
        activeSprites,
        activeTexts,
        { inactiveDim: true }
      );
    } else if (state.gameId === "mole") {
      const t = state.elapsed;
      const holeR = Math.min(w, h) * 0.095;
      const remSec = Math.max(0, Math.ceil((state.moleDuration || 60) - (state.moleElapsed || 0)));

      // Smooth confidence-driven foot rings (ZERO blinking!) so kids see their feet for lower moles
      players.forEach((p, idx) => {
        const col = idx === 0 ? 0x5cefe2 : 0xff828b;
        (p.ankles || []).forEach((a) => {
          if (!a) return;
          const vis = smoothstep(0.12, 0.48, a.smoothConf ?? a.v ?? 1);
          if (vis < 0.02) return;
          const ax = a.x * w, ay = a.y * h;
          this.fxGfx.circle(ax, ay, 24).fill({ color: col, alpha: 0.22 * vis });
          this.fxGfx.circle(ax, ay, 20).stroke({ color: col, width: 3.5, alpha: 0.85 * vis });
        });
      });

      // Top countdown badge + Fever badge
      const mTimerText = state.moleFeverTriggered ? `🔥 피버! ${remSec}초` : `⏱️ ${remSec}초`;
      const mTimerW = state.moleFeverTriggered ? 168 : 108;
      this.uiGfx
        .roundRect(w * 0.5 - mTimerW * 0.5, 84 - 18, mTimerW, 36, 18)
        .fill({ color: 0x0f172a, alpha: 0.66 })
        .stroke({ color: state.moleFeverTriggered ? 0xffd43b : 0xffffff, width: 2.2, alpha: 0.88 });
      const mTimer = this.getText("mole_time", mTimerText, "#0f172a");
      activeTexts.add("mole_time");
      mTimer.text = mTimerText;
      mTimer.x = w * 0.5;
      mTimer.y = 84;
      mTimer.alpha = 1;
      mTimer.scale.set(0.62);

      // Subtle row guidance pills with readable translucent backing
      const topY = h * 0.145;
      this.uiGfx.roundRect(w * 0.5 - 110, topY - 14, 220, 28, 14).fill({ color: 0x0f172a, alpha: 0.56 });
      const topLbl = this.getText("mole_row_top", "✋ 위: 손 하이파이브!", "#0284c7");
      activeTexts.add("mole_row_top");
      topLbl.x = w * 0.5;
      topLbl.y = topY;
      topLbl.alpha = 0.94;
      topLbl.scale.set(0.50);

      const botY = h * 0.935;
      this.uiGfx.roundRect(w * 0.5 - 122, botY - 14, 244, 28, 14).fill({ color: 0x0f172a, alpha: 0.60 });
      const botLbl = this.getText("mole_row_bot", "🦶 아래: 발차기 · 손 터치!", "#15803d");
      activeTexts.add("mole_row_bot");
      botLbl.x = w * 0.5;
      botLbl.y = botY;
      botLbl.alpha = 0.95;
      botLbl.scale.set(0.52);

      // Render all 6 holes (3 upper cloud holes + 3 lower earthy holes) & popping moles!
      (state.moleHoles || []).forEach((hl) => {
        const hx = hl.x * w;
        const hy = hl.y * h;
        const isTop = hl.row === "top";

        // 1) Hole backdrop (drawn on splatGfx = BEHIND sprites)
        if (isTop) {
          // Fluffy sky cloud hole
          this.splatGfx.ellipse(hx, hy + holeR * 0.26, holeR * 1.18, holeR * 0.44).fill({ color: 0xffffff, alpha: 0.88 });
          this.splatGfx.circle(hx - holeR * 0.65, hy + holeR * 0.18, holeR * 0.42).fill({ color: 0xffffff, alpha: 0.86 });
          this.splatGfx.circle(hx + holeR * 0.65, hy + holeR * 0.18, holeR * 0.42).fill({ color: 0xffffff, alpha: 0.86 });
          this.splatGfx.ellipse(hx, hy + holeR * 0.18, holeR * 0.86, holeR * 0.30).fill({ color: 0x0c4a6e, alpha: 0.72 });
        } else {
          // Earthy grass burrow hole
          this.splatGfx.ellipse(hx, hy + holeR * 0.28, holeR * 1.24, holeR * 0.46).fill({ color: 0x4ade80, alpha: 0.9 });
          this.splatGfx.ellipse(hx, hy + holeR * 0.24, holeR * 1.05, holeR * 0.38).fill({ color: 0x92400e, alpha: 0.92 });
          this.splatGfx.ellipse(hx, hy + holeR * 0.18, holeR * 0.84, holeR * 0.28).fill({ color: 0x29150a, alpha: 0.88 });
        }

        // 2) Popping Mole Sprite!
        if (hl.pop > 0.02) {
          // Playful overshoot bounce
          const bounce = hl.state === "bonked" ? 0.82 : 1 + Math.sin(hl.pop * Math.PI) * 0.12;
          const my = hy - holeR * 0.48 * hl.pop + (hl.state === "bonked" ? 14 : 0);

          if (hl.golden) {
            this.fxGfx.circle(hx, my, holeR * 1.22).fill({ color: 0xffd43b, alpha: 0.34 * hl.pop });
            for (let k = 0; k < 4; k++) {
              const a = t * 3.4 + (k * Math.PI) / 2;
              this.drawStar(this.fxGfx, hx + Math.cos(a) * holeR * 1.0, my + Math.sin(a) * holeR * 0.88, 10, 4.5, 0xffe866, 0.92 * hl.pop);
            }
          } else {
            this.fxGfx.circle(hx, my, holeR * 0.95).fill({ color: isTop ? 0x38bdf8 : 0x22ff88, alpha: 0.16 * hl.pop });
          }

          const sp = this.getSprite(`mole_${hl.id}`, hl.kind);
          if (sp) {
            activeSprites.add(`mole_${hl.id}`);
            sp.x = hx;
            sp.y = my;
            sp.rotation = hl.state === "bonked" ? 0.22 : Math.sin(t * 7 + hl.id) * 0.07;
            sp.tint = hl.state === "bonked" ? 0xffe875 : 0xffffff;
            sp.alpha = Math.min(1, hl.pop * 1.4);
            const baseScale = (holeR * 1.95) / Math.max(sp.texture.width, sp.texture.height);
            const sx = hl.state === "bonked" ? 1.24 : bounce;
            const sy = hl.state === "bonked" ? 0.72 : (0.55 + 0.45 * hl.pop) * bounce;
            sp.scale.set(baseScale * sx, baseScale * sy);
          } else {
            // Cute clay vector mole fallback
            const col = hl.golden ? 0xf59e0b : 0xa16207;
            this.uiGfx.circle(hx, my, holeR * 0.65 * hl.pop).fill({ color: col, alpha: 1 }).stroke({ color: 0x1e3a5f, width: 3.5 });
            this.uiGfx.circle(hx, my + 4, holeR * 0.22 * hl.pop).fill({ color: 0xfda4af, alpha: 1 });
          }
        }

        // 3) Front rim lip (drawn on uiGfx = IN FRONT of mole base!)
        this.uiGfx
          .ellipse(hx, hy + holeR * 0.32, holeR * 0.98, holeR * 0.24)
          .fill({ color: isTop ? 0xe0f2fe : 0x22c55e, alpha: 0.9 })
          .stroke({ color: isTop ? 0xffffff : 0x166534, width: 3 });
      });
    } else if (state.gameId === "balance") {
      const t = state.elapsed;
      const angle = state.bridgeAngle || 0;
      const inSafe = Boolean(state.balanceInSafe);
      const remSec = Math.max(0, Math.ceil((state.balanceDuration || 60) - (state.balanceElapsed || 0)));

      // 0) Calm organic Nintendo silhouette + soft golden airplane-arm glow when arms wide!
      this.drawLiveSkeleton(players, w, h, inSafe, renderDt, true);
      if (state.balanceWideArms) {
        players.forEach((p) => {
          if (p.leftHand && p.rightHand) {
            const vis = smoothstep(0.12, 0.48, Math.min(p.leftHand.smoothConf ?? p.leftHand.v ?? 1, p.rightHand.smoothConf ?? p.rightHand.v ?? 1));
            if (vis >= 0.02) {
              this.fxGfx
                .moveTo(p.leftHand.x * w, p.leftHand.y * h)
                .lineTo(p.rightHand.x * w, p.rightHand.y * h)
                .stroke({ color: 0xffd43b, width: 9, alpha: 0.42 * vis, cap: "round" });
            }
          }
        });
      }

      // 1) Animated Wind Gust Streaks + High-Contrast Direction Pill
      const ws = state.windStrength || 0;
      if (ws > 0.05 && state.windDir !== 0) {
        const dir = state.windDir; // +1 = wind blowing from left to right (lean right!)
        for (let i = 0; i < 10; i++) {
          const prog = ((t * 0.95 + i * 0.13) % 1);
          const sx = dir > 0 ? prog * w : (1 - prog) * w;
          const sy = h * (0.20 + (i % 5) * 0.13);
          const len = 75 + (i % 3) * 35;
          this.fxGfx
            .moveTo(sx, sy)
            .bezierCurveTo(sx + dir * len * 0.4, sy - 14, sx + dir * len * 0.7, sy + 14, sx + dir * len, sy)
            .stroke({ color: 0x7dd3fc, width: 5, alpha: 0.65 * ws, cap: "round" });
        }
        const arrowTxt = dir > 0 ? "🌬️ 오른쪽으로 기울여요! ➡" : "⬅ 왼쪽으로 기울여요! 🌬️";
        const windAlpha = Math.min(1, ws * 1.4);
        const windY = h * 0.23;
        this.uiGfx
          .roundRect(w * 0.5 - 178, windY - 22, 356, 44, 22)
          .fill({ color: 0x0f172a, alpha: 0.74 * windAlpha })
          .stroke({ color: 0x7dd3fc, width: 2.5, alpha: 0.92 * windAlpha });
        const windTx = this.getText("balance_wind", arrowTxt, "#0369a1");
        activeTexts.add("balance_wind");
        windTx.text = arrowTxt;
        windTx.x = w * 0.5;
        windTx.y = windY;
        windTx.alpha = windAlpha;
        windTx.scale.set(0.68);
      }

      // 2) Top-Center Glowing Balance Gauge Bar (Green Safe Center Zone!)
      const gaugeW = Math.min(380, w * 0.42);
      const gaugeH = 26;
      const gaugeX = w * 0.5 - gaugeW * 0.5;
      const gaugeY = 86;
      this.uiGfx
        .roundRect(gaugeX, gaugeY, gaugeW, gaugeH, 13)
        .fill({ color: 0x0f172a, alpha: 0.62 })
        .stroke({ color: 0xffffff, width: 3.5 });
      // Safe green center band (|angle| < 0.16 out of 0.42 => ~38% width)
      const safeW = gaugeW * (0.16 / 0.42);
      this.uiGfx
        .roundRect(w * 0.5 - safeW * 0.5, gaugeY + 4, safeW, gaugeH - 8, 9)
        .fill({ color: inSafe ? 0x22ff88 : 0x4ade80, alpha: inSafe ? 0.92 : 0.45 });
      // Indicator star sliding with bridgeAngle
      const normAngle = Math.max(-1, Math.min(1, angle / 0.42));
      const dotX = w * 0.5 + normAngle * (gaugeW * 0.46);
      const dotY = gaugeY + gaugeH * 0.5;
      this.drawStar3D(this.uiGfx, dotX, dotY, 19, 8.5, inSafe ? 0xffd43b : 0xff6b6b, 0x1e3a5f, 3.5);

      const bTimerX = gaugeX + gaugeW + 62;
      const bTimerY = gaugeY + 13;
      this.uiGfx
        .roundRect(bTimerX - 46, bTimerY - 17, 92, 34, 17)
        .fill({ color: 0x0f172a, alpha: 0.68 })
        .stroke({ color: 0xffffff, width: 2.2, alpha: 0.85 });
      const bTimer = this.getText("balance_time", `⏱️ ${remSec}초`, "#0f172a");
      activeTexts.add("balance_time");
      bTimer.text = `⏱️ ${remSec}초`;
      bTimer.x = bTimerX;
      bTimer.y = bTimerY;
      bTimer.alpha = 1;
      bTimer.scale.set(0.56);

      // 3) Floating star_3d stars overhead to catch while balancing!
      (state.balanceStars || []).forEach((st) => {
        const sx = st.x * w;
        const sy = (st.y + Math.sin(t * 3.2 + st.seed) * 0.025) * h;
        const sr = Math.min(w, h) * st.r;
        this.fxGfx.circle(sx, sy, sr * 1.35).fill({ color: 0xffd43b, alpha: 0.3 });
        const sp = this.getSprite(`bstar_${st.uid}`, "star_3d");
        if (sp) {
          activeSprites.add(`bstar_${st.uid}`);
          sp.x = sx;
          sp.y = sy;
          sp.rotation = t * 1.5 + st.seed;
          sp.tint = 0xffffff;
          sp.alpha = 1;
          const sc = (sr * 2.15) / Math.max(sp.texture.width, sp.texture.height);
          sp.scale.set(sc);
        } else {
          this.drawStar3D(this.uiGfx, sx, sy, sr, sr * 0.45, 0xffd43b, 0x1e3a5f, 4);
        }
      });

      // 4) Charming Tilting Log Bridge + Momo (& Popo in 2P) Standing on Top!
      const bridgeCx = w * 0.5;
      const bridgeCy = h * 0.78;
      const bridgeW = Math.min(620, w * 0.62);

      // Wooden fulcrum stump beneath log center
      this.splatGfx
        .poly([bridgeCx - 38, h, bridgeCx - 22, bridgeCy + 14, bridgeCx + 22, bridgeCy + 14, bridgeCx + 38, h])
        .fill({ color: 0x78350f, alpha: 0.92 })
        .stroke({ color: 0x451a03, width: 4 });

      const bSp = this.getSprite("balance_log", "log_bridge");
      if (bSp) {
        activeSprites.add("balance_log");
        bSp.x = bridgeCx;
        bSp.y = bridgeCy;
        bSp.rotation = angle;
        bSp.tint = 0xffffff;
        bSp.alpha = 1;
        const sc = bridgeW / Math.max(1, bSp.texture.width);
        bSp.scale.set(sc);
      } else {
        // Warm 3D wooden log vector fallback
        const dx = Math.cos(angle) * (bridgeW * 0.48);
        const dy = Math.sin(angle) * (bridgeW * 0.48);
        this.uiGfx
          .moveTo(bridgeCx - dx, bridgeCy - dy)
          .lineTo(bridgeCx + dx, bridgeCy + dy)
          .stroke({ color: 0x92400e, width: 42, cap: "round" });
        this.uiGfx
          .moveTo(bridgeCx - dx * 0.92, bridgeCy - dy * 0.92 - 6)
          .lineTo(bridgeCx + dx * 0.92, bridgeCy + dy * 0.92 - 6)
          .stroke({ color: 0xd97706, width: 12, cap: "round", alpha: 0.7 });
      }

      // Mascots standing on top of the tilting log using live 6-part DancePuppetRigs!
      const riders =
        state.settings?.players === 2
          ? [
              { id: "momo", offset: -bridgeW * 0.16, phaseOffset: 0.0 },
              { id: "popo", offset: bridgeW * 0.16, phaseOffset: 0.35 },
            ]
          : [{ id: "momo", offset: 0, phaseOffset: 0.0 }];

      const riderSize = Math.min(w, h) * 0.25;
      const balTilt = state.balanceTilt !== undefined ? state.balanceTilt : Math.max(-1, Math.min(1, angle / 0.42));
      const bRigBuf = this._rigStateBuf;
      bRigBuf.mode = "balance";
      bRigBuf.subAction = "run";
      bRigBuf.bpm = 112;
      bRigBuf.energy = inSafe ? 0.65 : 0.95;
      bRigBuf.tilt = balTilt;
      bRigBuf.frozen = false;
      bRigBuf.wiggling = false;
      bRigBuf.routineOverride = null;

      riders.forEach((rd) => {
        const rx = bridgeCx + Math.cos(angle) * rd.offset + Math.sin(angle) * (riderSize * 0.40);
        const ry = bridgeCy + Math.sin(angle) * rd.offset - Math.cos(angle) * (riderSize * 0.42);
        this.mountOrUpdateRig(
          `rig_bal_${rd.id}`,
          rd.id,
          riderSize,
          rx,
          ry,
          renderDt,
          bRigBuf,
          activeRigs,
          rd.phaseOffset,
          angle * 0.65
        );
      });

      // 5) Flamingo One-Foot Bonus Circular Badge (renders cute pose_flamingo.png!)
      if (state.flamingoActive) {
        const flProg = (state.flamingoHold || 0) / Math.max(0.1, state.flamingoHoldTarget || 1.6);
        this.drawPostureBadge(
          "bal_flamingo",
          Math.max(88, w * 0.095),
          h - Math.max(94, h * 0.15),
          Math.min(50, Math.min(w, h) * 0.078),
          "flamingo",
          "한 발 균형!",
          flProg,
          true,
          activeSprites,
          activeTexts,
          { pulse: flProg > 0.05 ? 1.0 + 0.04 * Math.sin(t * 9) : 1.0 }
        );
      }
    }

    // 4) Sliced 3D Fruit Halves spinning apart!
    state.halves.forEach((hf) => {
      const sp = this.getSprite(`h_${hf.uid}`, hf.texKey);
      if (!sp) return;
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
        sp.parent?.removeChild(sp);
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

/**
 * Exported helper to mount (once) and update a DancePuppetRig on a PixiGameRenderer instance.
 */
export function mountDancePuppetRig(
  renderer,
  id,
  characterId,
  baseSize,
  x,
  y,
  dt,
  rigState,
  activeRigs = null,
  phaseOffset = 0,
  rootRotation = 0
) {
  if (!renderer || !renderer.ready) return null;
  return renderer.mountOrUpdateRig(
    id,
    characterId,
    baseSize,
    x,
    y,
    dt,
    rigState,
    activeRigs,
    phaseOffset,
    rootRotation
  );
}
