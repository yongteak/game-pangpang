/**
 * Commercial Expressive 6-Part Dance Puppet Rig & 8-Routine 128 BPM Choreography Engine (PixiJS v8)
 *
 * Implements all 7 axioms from doc/dance_choreography_axioms.md with commercial Nintendo/Wii polish:
 *   Axiom 0: Canonical Y-Up / CCW+ -> PixiJS Y-Down / CW+ coordinate conversion
 *   Axiom 1: Deep-tucked hierarchical joint tree (root -> [shadow, pelvis -> 6 sibling parts])
 *   Axiom 2: 128 BPM beat-locked cumulative phase harmonic synthesis
 *   Axiom 3: Volume-preserving squash & stretch (sx * sy === 1.0) + grounded beat-down bounce
 *   Axiom 4: Phase-lag secondary motion (Δphi = -0.35 rad) on head & bob
 *   Axiom 5: 8-routine 6-beat auto-cycling choreography + balance/jungle modes + spring cross-fade
 *   Axiom 6: Player-energy modulation (0.70x..1.28x) + Instant Freeze-Pose Lock + 32Hz micro-tremor
 *   Axiom 7: Zero per-frame heap allocations & graceful single-sprite fallback
 */

const TWO_PI = Math.PI * 2;
const TWELVE_PI = Math.PI * 12; // 6 beats per routine -> lively variety within every dance round!
const HEAD_PHASE_LAG = -0.35;
const BLEND_RATE = 9.5;
const WIGGLE_HZ = 32.0;
const SQUASH_K = 0.14;

export const RIG_CHARACTERS = ["dino", "momo", "popo"];
export const RIG_PART_KEYS = ["body", "head", "arm_l", "arm_r", "leg_l", "leg_r"];
export const ROUTINE_NAMES = [
  "groove_bounce",
  "disco_point",
  "cheer_manse",
  "wave_surf",
  "happy_clap",
  "star_jump",
  "twist_shimmy",
  "hero_pose",
];

/**
 * Per-character subtle personality amplitude multiplier so Dino, Momo & Popo feel alive together.
 */
export const RIG_PERSONALITY = {
  dino: 1.0,
  momo: 1.06,
  popo: 0.94,
};

/**
 * All 18 modular puppet rig texture asset paths (for PixiJS Assets.load preloading).
 */
export const RIG_ASSET_MAP = {};
for (let c = 0; c < RIG_CHARACTERS.length; c++) {
  const ch = RIG_CHARACTERS[c];
  for (let p = 0; p < RIG_PART_KEYS.length; p++) {
    const part = RIG_PART_KEYS[p];
    RIG_ASSET_MAP[`rig_${ch}_${part}`] = `./assets/rig_${ch}_${part}.png`;
  }
}

/**
 * Axiom 1.2: Deep-tucked normalized part specs so NO limb ever detaches or looks dislocated
 * even at extreme disco/starfish/hero poses!
 * - Anchors are in PixiJS Y-Down (ayPixi = 1 - ay_yup).
 * - Offsets (ox, oy) are in canonical Y-Up (applied in PixiJS as (ox * S, -oy * S)):
 *     head: oy = +0.25 -> Y-Down -0.25, ayPixi = 0.84
 *     armL/armR: ox = ±0.14, ax = 0.68 / 0.32, ayPixi = 0.22
 *     legL/legR: oy = -0.20 -> Y-Down +0.20, ayPixi = 0.16
 */
export const RIG_PART_SPECS = {
  body: { suffix: "body",  zIndex:  0, ax: 0.50, ayPixi: 0.55, size: 0.52, ox:  0.00, oy:  0.00 },
  head: { suffix: "head",  zIndex:  1, ax: 0.50, ayPixi: 0.84, size: 0.62, ox:  0.00, oy:  0.25 },
  armL: { suffix: "arm_l", zIndex: -1, ax: 0.68, ayPixi: 0.22, size: 0.34, ox: -0.14, oy:  0.10 },
  armR: { suffix: "arm_r", zIndex: -1, ax: 0.32, ayPixi: 0.22, size: 0.34, ox:  0.14, oy:  0.10 },
  legL: { suffix: "leg_l", zIndex: -2, ax: 0.50, ayPixi: 0.16, size: 0.32, ox: -0.10, oy: -0.20 },
  legR: { suffix: "leg_r", zIndex: -2, ax: 0.50, ayPixi: 0.16, size: 0.32, ox:  0.10, oy: -0.20 },
};

function clamp(v, lo, hi) {
  return v < lo ? lo : v > hi ? hi : v;
}

/** Sharp beat kick pulse [0..1] peaking at beat downstrokes */
export function beatPulse(phi) {
  const c = Math.cos(phi * 0.5);
  if (c <= 0) return 0;
  const c2 = c * c;
  return c2 * c2;
}

/** Smooth grounded beat-down dip [0..1] peaking on every beat */
export function beatDip(phi) {
  const s = Math.abs(Math.sin(phi * 0.5));
  const inv = 1.0 - s;
  return inv * inv;
}

export function stepPulse(phi) {
  return Math.abs(Math.sin(phi * 0.5));
}

/** Smooth cubic S-curve sway in [-1, 1] */
export function smoothSway(phi) {
  const u = (Math.sin(phi * 0.5) + 1.0) * 0.5;
  return 2.0 * u * u * (3.0 - 2.0 * u) - 1.0;
}

/** Smooth cubic binary switch in [0, 1] for crisp L/R alternation */
function cubicSwitch(x) {
  const u = clamp((x + 1.0) * 0.5, 0, 1);
  return u * u * (3.0 - 2.0 * u);
}

function createPoseStruct() {
  return {
    body: 0,
    head: 0,
    armL: 0,
    armR: 0,
    legL: 0,
    legR: 0,
    hopY: 0,
    squash: 0,
    headBob: 0,
  };
}

function copyPose(dst, src) {
  dst.body = src.body;
  dst.head = src.head;
  dst.armL = src.armL;
  dst.armR = src.armR;
  dst.legL = src.legL;
  dst.legR = src.legR;
  dst.hopY = src.hopY;
  dst.squash = src.squash;
  dst.headBob = src.headBob;
}

function resetPose(dst) {
  dst.body = 0;
  dst.head = 0;
  dst.armL = 0;
  dst.armR = 0;
  dst.legL = 0;
  dst.legR = 0;
  dst.hopY = 0;
  dst.squash = 0;
  dst.headBob = 0;
}

/**
 * Pure zero-allocation pose evaluator shared by PixiJS DancePuppetRig and Canvas2D fallback.
 * Writes canonical Y-Up / CCW+ angles & offsets into `out`.
 *
 * Angle reminder (canonical Y-Up / CCW+, negated when applied to PixiJS CW+):
 *   armL < 0 -> left arm raises outward/upward (-1.57 = horizontal, -2.1 = high V/sky-point)
 *   armL > 0 -> left arm tucks inward across chest/hip
 *   armR > 0 -> right arm raises outward/upward (+1.57 = horizontal, +2.1 = high V/sky-point)
 *   armR < 0 -> right arm tucks inward across chest/hip
 *   legL < 0 / legR > 0 -> legs spread outward
 *   hopY < 0 -> grounded beat-down dip; hopY > 0 -> mid-air jump
 */
export function evaluateTargetPose(
  out,
  phi,
  mode,
  subAction,
  energy,
  tilt,
  routineOverride,
  personality = 1.0
) {
  const phiH = phi + HEAD_PHASE_LAG;
  const amp = (0.70 + 0.58 * clamp(energy, 0, 1)) * (personality || 1.0);

  if (mode === "balance") {
    const tau = clamp(tilt, -1, 1);
    const body = -0.30 * tau;
    const micro = Math.sin(phi * 0.5);
    out.hopY = -0.022 * Math.abs(tau) + 0.010 * Math.abs(micro);
    out.squash = -0.14 * Math.abs(tau);
    out.body = body;
    out.head = 0.16 * tau + 0.06 * Math.sin(phiH * 0.5) + 0.30 * body;
    // Wide airplane counter-balance arms!
    out.armL = -1.25 + 0.48 * tau + 0.14 * Math.sin(phi);
    out.armR = 1.25 + 0.48 * tau - 0.14 * Math.sin(phi);
    out.legL = -0.14 + 0.08 * micro;
    out.legR = 0.14 - 0.08 * micro;
    out.headBob = 0.012 * Math.sin(phiH);
    return -1;
  }

  if (mode === "jungle") {
    if (subAction === "squat") {
      out.hopY = -0.15;
      out.squash = -1.18;
      out.body = -0.18;
      out.head = 0.18;
      out.armL = -0.62;
      out.armR = 0.62;
      out.legL = -0.34;
      out.legR = 0.34;
      out.headBob = -0.012;
      return -1;
    }
    if (subAction === "jump") {
      out.hopY = 0.15;
      out.squash = 0.98;
      out.body = 0.05 * Math.sin(phi);
      out.head = -0.08;
      out.armL = -1.85;
      out.armR = 1.85;
      out.legL = -0.38;
      out.legR = 0.38;
      out.headBob = 0.018 * Math.sin(phiH);
      return -1;
    }
    // Default jungle subAction: "run"
    const psi = 1.6 * phi;
    const psiH = psi + HEAD_PHASE_LAG;
    const sinPsi = Math.sin(psi);
    const absSinPsi = Math.abs(sinPsi);
    const bodyLag = -0.14 + 0.06 * Math.sin(2.0 * psiH);
    out.hopY = -0.030 + 0.075 * absSinPsi;
    out.squash = (absSinPsi - 0.52) * 0.72;
    out.body = -0.14 + 0.06 * Math.sin(2.0 * psi);
    out.head = 0.09 + 0.07 * Math.sin(psiH) + 0.30 * bodyLag;
    out.armL = -0.30 + 0.82 * sinPsi;
    out.armR = 0.30 + 0.82 * sinPsi;
    out.legL = -0.62 * sinPsi;
    out.legR = 0.62 * sinPsi;
    out.headBob = 0.018 * Math.sin(psiH);
    return -1;
  }

  // Default mode: "dance" — 8 Distinct Expressive Commercial Dance Routines!
  const routineCount = ROUTINE_NAMES.length;
  const r =
    routineOverride !== null && routineOverride !== undefined
      ? (((routineOverride | 0) % routineCount) + routineCount) % routineCount
      : Math.floor(Math.max(0, phi) / TWELVE_PI) % routineCount;

  const halfPhi = phi * 0.5;
  const sinHalf = Math.sin(halfPhi);
  const cosHalf = Math.cos(halfPhi);
  const halfPhiH = phiH * 0.5;
  const dip = beatDip(phi);
  const pulse = beatPulse(phi);

  if (r === 0) {
    // 0) groove_bounce: hip-hop beat-down dip + alternating arm pump + cool head nod
    const sway = smoothSway(phi);
    const bodyLag = 0.13 * smoothSway(phiH) * amp;
    out.hopY = -0.062 * dip * amp;
    out.squash = (-0.95 * dip + 0.25) * amp;
    out.body = 0.13 * sway * amp;
    out.head = 0.16 * Math.sin(halfPhiH) * amp + 0.30 * bodyLag;
    // Alternating hip-hop arm pump
    out.armL = (-0.55 - 0.52 * sinHalf) * amp;
    out.armR = (0.55 - 0.52 * sinHalf) * amp;
    // Planted legs gently counter-flex with beat dip
    out.legL = (-0.08 - 0.14 * dip + 0.10 * sinHalf) * amp;
    out.legR = (0.08 + 0.14 * dip + 0.10 * sinHalf) * amp;
    out.headBob = (-0.022 * dip + 0.012 * Math.sin(phiH)) * amp;
  } else if (r === 1) {
    // 1) disco_point: classic Saturday-Night-Fever diagonal sky-point (alternating L/R + hip tuck + torso lean!)
    const side = cubicSwitch(Math.sin(phi * 0.25) * 2.2); // 0 = left sky-point, 1 = right sky-point
    const invSide = 1.0 - side;
    const thrust = 0.78 + 0.22 * pulse;
    const lean = (side * 2.0 - 1.0) * 0.19; // leans away from pointing arm
    const bodyLag = (cubicSwitch(Math.sin(phiH * 0.25) * 2.2) * 2.0 - 1.0) * 0.19 * amp;
    out.hopY = (-0.055 * dip + 0.018 * pulse) * amp;
    out.squash = (-0.75 * dip + 0.45 * pulse) * amp;
    out.body = lean * amp;
    out.head = (-0.18 * (side * 2.0 - 1.0) + 0.08 * Math.sin(phiH)) * amp + 0.25 * bodyLag;
    // Pointing arm stretched high diagonal (~2.05 rad), other hand tucked at hip (~0.25 rad inward)
    out.armL = (invSide * (-2.05 * thrust) + side * 0.26) * amp;
    out.armR = (side * (2.05 * thrust) + invSide * -0.26) * amp;
    // Grooving disco stance (planted with stylish weight shift)
    out.legL = (-0.12 - 0.16 * side * dip) * amp;
    out.legR = (0.12 + 0.16 * invSide * dip) * amp;
    out.headBob = (-0.016 * dip + 0.014 * pulse) * amp;
  } else if (r === 2) {
    // 2) cheer_manse: energetic double-arm V-manse cheer jump + spring landing squash
    const j = sinHalf > 0 ? Math.pow(sinHalf, 1.45) : 0;
    const land = sinHalf < 0 ? Math.pow(-sinHalf, 1.4) : 0;
    const bodyLag = 0.07 * Math.cos(halfPhiH) * amp;
    out.hopY = (0.145 * j - 0.068 * land) * amp;
    out.squash = (1.35 * j - 1.15 * land) * amp;
    out.body = 0.07 * cosHalf * amp;
    out.head = (-0.10 * j + 0.12 * Math.sin(phiH)) * amp + 0.28 * bodyLag;
    // Both arms fly up into joyous V-manse on jump, bounce down on landing!
    out.armL = (-0.42 - 1.58 * j + 0.22 * land) * amp;
    out.armR = (0.42 + 1.58 * j - 0.22 * land) * amp;
    out.legL = (-0.24 * j - 0.12 * land) * amp;
    out.legR = (0.24 * j + 0.12 * land) * amp;
    out.headBob = (0.022 * j - 0.020 * land) * amp;
  } else if (r === 3) {
    // 3) wave_surf: flowing L-to-R arm wave + smooth hip sway + head follow-through
    const sway = smoothSway(phi);
    const bodyLag = 0.18 * smoothSway(phiH) * amp;
    const waveL = Math.sin(halfPhi + 0.65);
    const waveR = Math.sin(halfPhi - 0.65);
    out.hopY = -0.045 * dip * amp;
    out.squash = (-0.65 * dip + 0.20) * amp;
    out.body = 0.18 * sway * amp;
    out.head = -0.16 * Math.sin(halfPhiH) * amp + 0.35 * bodyLag;
    // Flowing surfing arm wave from left to right!
    out.armL = (-1.15 - 0.58 * waveL) * amp;
    out.armR = (1.15 + 0.58 * waveR) * amp;
    out.legL = (-0.14 + 0.14 * cosHalf) * amp;
    out.legR = (0.14 + 0.14 * cosHalf) * amp;
    out.headBob = 0.018 * Math.sin(phiH) * amp;
  } else if (r === 4) {
    // 4) happy_clap: rhythmic chest-front double clap + alternating toe-tap + cute head tilt
    const clapWave = 0.5 + 0.5 * Math.sin(phi * 1.0); // 1 = open, 0 = clap!
    const clapSnap = Math.pow(1.0 - clapWave, 2.2); // crisp inward clap snap
    const tap = Math.sin(halfPhi);
    const bodyLag = 0.11 * Math.sin(halfPhiH) * amp;
    out.hopY = -0.052 * clapSnap * amp;
    out.squash = (-0.85 * clapSnap + 0.35 * clapWave) * amp;
    out.body = 0.11 * tap * amp;
    out.head = 0.19 * Math.cos(halfPhiH) * amp + 0.25 * bodyLag;
    // Crisp inward chest clap (+0.56 / -0.56) -> bouncy open (-0.75 / +0.75)
    out.armL = (-0.72 + 1.28 * clapSnap) * amp;
    out.armR = (0.72 - 1.28 * clapSnap) * amp;
    // Alternating playful toe-tap!
    out.legL = (tap > 0 ? -0.34 * tap : -0.06) * amp;
    out.legR = (tap < 0 ? 0.34 * -tap : 0.06) * amp;
    out.headBob = (-0.018 * clapSnap + 0.012 * clapWave) * amp;
  } else if (r === 5) {
    // 5) star_jump: joyful big X-shape starfish jump fever (arms & legs spread wide mid-air!)
    const j = sinHalf > 0 ? Math.pow(sinHalf, 1.35) : 0;
    const land = sinHalf < 0 ? Math.pow(-sinHalf, 1.5) : 0;
    const bodyLag = 0.06 * Math.sin(phiH) * amp;
    out.hopY = (0.165 * j - 0.072 * land) * amp;
    out.squash = (1.45 * j - 1.20 * land) * amp;
    out.body = 0.06 * Math.sin(phi) * amp;
    out.head = 0.12 * Math.cos(phiH) * amp + 0.25 * bodyLag;
    // Wide X-shape starfish burst in mid-air!
    out.armL = (-0.28 - 1.62 * j) * amp;
    out.armR = (0.28 + 1.62 * j) * amp;
    out.legL = (-0.08 - 0.46 * j - 0.10 * land) * amp;
    out.legR = (0.08 + 0.46 * j + 0.10 * land) * amp;
    out.headBob = (0.026 * j - 0.022 * land) * amp;
  } else if (r === 6) {
    // 6) twist_shimmy: playful shoulder-shimmy twist + bent-arm crab groove
    const shimmy = Math.sin(phi * 2.0); // lively 2x-beat shimmy!
    const sway = smoothSway(phi);
    const bodyLag = 0.16 * smoothSway(phiH) * amp;
    out.hopY = -0.054 * dip * amp;
    out.squash = (-0.82 * dip + 0.18 * Math.abs(shimmy)) * amp;
    out.body = (0.16 * sway + 0.06 * shimmy) * amp;
    out.head = (-0.14 * sway + 0.10 * Math.sin(phiH * 2.0)) * amp + 0.25 * bodyLag;
    // Playful alternating crab-groove shoulder shimmy!
    out.armL = (-1.05 + 0.42 * shimmy) * amp;
    out.armR = (1.05 + 0.42 * shimmy) * amp;
    out.legL = (-0.18 + 0.16 * sway) * amp;
    out.legR = (0.18 + 0.16 * sway) * amp;
    out.headBob = -0.016 * dip * amp;
  } else {
    // 7) hero_pose: dramatic superhero finish pose (one arm sky-high, one arm out-side, proud lean)
    const side = cubicSwitch(Math.sin(phi * 0.25) * 2.6); // 0 = Left Hero, 1 = Right Hero
    const invSide = 1.0 - side;
    const pop = 0.85 + 0.15 * pulse;
    const lean = (side * 2.0 - 1.0) * 0.17;
    const bodyLag = (cubicSwitch(Math.sin(phiH * 0.25) * 2.6) * 2.0 - 1.0) * 0.17 * amp;
    out.hopY = (-0.048 * dip + 0.032 * pulse) * amp;
    out.squash = (-0.70 * dip + 0.55 * pulse) * amp;
    out.body = lean * amp;
    out.head = (-0.14 * (side * 2.0 - 1.0) + 0.06 * pulse) * amp + 0.25 * bodyLag;
    // Hero arm sky-high (~2.15 rad), support arm strong out-side (~1.12 rad)
    out.armL = (invSide * (-2.15 * pop) + side * (-1.12 * pop)) * amp;
    out.armR = (side * (2.15 * pop) + invSide * (1.12 * pop)) * amp;
    // Wide heroic power stance!
    out.legL = (-0.26 - 0.08 * dip) * amp;
    out.legR = (0.26 + 0.08 * dip) * amp;
    out.headBob = (-0.014 * dip + 0.016 * pulse) * amp;
  }

  return r;
}

/**
 * PixiJS v8 Modular 6-Part DancePuppetRig with dynamic grounded floor shadow.
 * Zero per-frame allocations; graceful fallback to single sprite if any rig texture is missing.
 */
export class DancePuppetRig {
  /**
   * @param {object} PIXI - PixiJS v8 module namespace
   * @param {Record<string, any>} textures - PixiJS texture dictionary
   * @param {"dino"|"momo"|"popo"} characterId
   * @param {number} baseSize - Reference character height in pixels
   * @param {number} [phaseOffset=0] - Initial phase offset in radians
   */
  constructor(PIXI, textures, characterId, baseSize = 180, phaseOffset = 0) {
    this.PIXI = PIXI;
    this.textures = textures;
    this.characterId = characterId;
    this.personality = RIG_PERSONALITY[characterId] || 1.0;
    this.baseSize = Math.max(32, baseSize);
    this.phaseOffset = phaseOffset || 0;
    this.phase = this.phaseOffset;
    this.wiggleClock = 0;
    this.wasFrozen = false;
    this.currentRoutine = 0;

    // Pre-allocated mutable pose structs (Axiom 7: zero per-frame allocations)
    this.currentPose = createPoseStruct();
    this.targetPose = createPoseStruct();
    this.frozenPose = createPoseStruct();

    // Node hierarchy: root -> [shadow (z=-10), pelvis (z=0) -> 6 sibling parts]
    this.root = new PIXI.Container();
    this.root.sortableChildren = true;

    // Pre-drawn normalized unit floor shadow ellipse (scaled per frame with zero allocations!)
    this.shadow = new PIXI.Graphics();
    this.shadow.ellipse(0, 0, 100, 26).fill({ color: 0x0f172a, alpha: 0.34 });
    this.shadow.zIndex = -10;
    this.root.addChild(this.shadow);

    this.pelvis = new PIXI.Container();
    this.pelvis.sortableChildren = true;
    this.pelvis.zIndex = 0;
    this.root.addChild(this.pelvis);

    const tBody = textures[`rig_${characterId}_body`];
    const tHead = textures[`rig_${characterId}_head`];
    const tArmL = textures[`rig_${characterId}_arm_l`];
    const tArmR = textures[`rig_${characterId}_arm_r`];
    const tLegL = textures[`rig_${characterId}_leg_l`];
    const tLegR = textures[`rig_${characterId}_leg_r`];

    this.fallbackMode = !(tBody && tHead && tArmL && tArmR && tLegL && tLegR);
    this.parts = null;
    this.fallbackSprite = null;
    this.fallbackDanceTex = null;
    this.fallbackFreezeTex = null;

    if (!this.fallbackMode) {
      this.parts = {
        legL: this._createPartSprite(tLegL, RIG_PART_SPECS.legL),
        legR: this._createPartSprite(tLegR, RIG_PART_SPECS.legR),
        armL: this._createPartSprite(tArmL, RIG_PART_SPECS.armL),
        armR: this._createPartSprite(tArmR, RIG_PART_SPECS.armR),
        body: this._createPartSprite(tBody, RIG_PART_SPECS.body),
        head: this._createPartSprite(tHead, RIG_PART_SPECS.head),
      };
      this.pelvis.addChild(
        this.parts.legL,
        this.parts.legR,
        this.parts.armL,
        this.parts.armR,
        this.parts.body,
        this.parts.head
      );
      this.pelvis.sortChildren();
    } else {
      // Axiom 7.4: Graceful single-sprite fallback
      this.fallbackDanceTex =
        textures[`${characterId}_dance1`] ||
        textures[characterId] ||
        textures.dino ||
        null;
      this.fallbackFreezeTex =
        textures[`${characterId}_freeze`] || this.fallbackDanceTex;
      if (this.fallbackDanceTex) {
        const sp = new PIXI.Sprite(this.fallbackDanceTex);
        sp.anchor.set(0.5, 0.55);
        this.pelvis.addChild(sp);
        this.fallbackSprite = sp;
      }
    }

    this._applyBaseSize();
  }

  _createPartSprite(tex, spec) {
    const sp = new this.PIXI.Sprite(tex);
    sp.anchor.set(spec.ax, spec.ayPixi);
    sp.zIndex = spec.zIndex;
    return sp;
  }

  _applyBaseSize() {
    const S = this.baseSize;
    if (this.shadow) {
      this.shadow.x = 0;
      this.shadow.y = S * 0.44;
    }
    if (!this.fallbackMode && this.parts) {
      const p = this.parts;
      this._layoutPart(p.body, RIG_PART_SPECS.body, S);
      this._layoutPart(p.head, RIG_PART_SPECS.head, S);
      this._layoutPart(p.armL, RIG_PART_SPECS.armL, S);
      this._layoutPart(p.armR, RIG_PART_SPECS.armR, S);
      this._layoutPart(p.legL, RIG_PART_SPECS.legL, S);
      this._layoutPart(p.legR, RIG_PART_SPECS.legR, S);
    } else if (this.fallbackSprite && this.fallbackSprite.texture) {
      const tex = this.fallbackSprite.texture;
      const sc = (S * 1.05) / Math.max(1, tex.width, tex.height);
      this.fallbackSprite.scale.set(sc);
      this.fallbackSprite.position.set(0, 0);
    }
  }

  _layoutPart(sprite, spec, S) {
    const tex = sprite.texture;
    const sc = (spec.size * S) / Math.max(1, tex.width, tex.height);
    sprite.scale.set(sc);
    // Axiom 0: Canonical Y-Up offset (ox, oy) -> PixiJS Y-Down (ox * S, -oy * S)
    sprite.position.set(spec.ox * S, -spec.oy * S);
  }

  setBaseSize(size) {
    const next = Math.max(32, size);
    if (Math.abs(next - this.baseSize) < 0.5) return;
    this.baseSize = next;
    this._applyBaseSize();
  }

  resetPhase(offset = this.phaseOffset) {
    this.phaseOffset = offset || 0;
    this.phase = this.phaseOffset;
    this.wiggleClock = 0;
    this.wasFrozen = false;
    resetPose(this.currentPose);
    resetPose(this.targetPose);
    resetPose(this.frozenPose);
  }

  /**
   * Zero-allocation per-frame rig update (Axioms 2–7).
   * @param {number} dt - Frame delta seconds
   * @param {object} state - { mode, subAction, bpm, energy, tilt, frozen, wiggling, routineOverride }
   */
  update(dt, state) {
    const safeDt = dt > 0.1 ? 0.1 : dt < 0 ? 0 : dt;
    const mode = state.mode || "dance";
    const subAction = state.subAction || "run";
    const bpm = state.bpm > 0 ? state.bpm : 128;
    const energy = state.energy !== undefined ? state.energy : 0.5;
    const tilt = state.tilt !== undefined ? state.tilt : 0;
    const frozen = Boolean(state.frozen);
    const wiggling = Boolean(state.wiggling);
    const routineOverride = state.routineOverride !== undefined ? state.routineOverride : null;

    // Axiom 6.2: Instant Freeze-Pose Lock on false -> true transition
    if (frozen && !this.wasFrozen) {
      copyPose(this.frozenPose, this.currentPose);
      this.wiggleClock = 0;
    }
    this.wasFrozen = frozen;

    let activePose = this.currentPose;

    if (!frozen) {
      // Axiom 2: Cumulative phase integration (tempo changes never jump phase)
      this.phase += safeDt * (bpm / 60.0) * TWO_PI;

      // Axiom 5: Evaluate target pose & smooth spring/exponential cross-fade blend
      const r = evaluateTargetPose(
        this.targetPose,
        this.phase,
        mode,
        subAction,
        energy,
        tilt,
        routineOverride,
        this.personality
      );
      if (r >= 0) this.currentRoutine = r;

      const alpha = safeDt * BLEND_RATE < 1.0 ? safeDt * BLEND_RATE : 1.0;
      const cur = this.currentPose;
      const tgt = this.targetPose;
      cur.body += alpha * (tgt.body - cur.body);
      cur.head += alpha * (tgt.head - cur.head);
      cur.armL += alpha * (tgt.armL - cur.armL);
      cur.armR += alpha * (tgt.armR - cur.armR);
      cur.legL += alpha * (tgt.legL - cur.legL);
      cur.legR += alpha * (tgt.legR - cur.legR);
      cur.hopY += alpha * (tgt.hopY - cur.hopY);
      cur.squash += alpha * (tgt.squash - cur.squash);
      cur.headBob += alpha * (tgt.headBob - cur.headBob);
      activePose = cur;
    } else {
      activePose = this.frozenPose;
    }

    // Axiom 6.3: 32 Hz Micro-Tremor overlay when frozen & wiggling
    let wiggleRad = 0;
    let wiggleX = 0;
    if (frozen && wiggling) {
      this.wiggleClock += safeDt;
      const s32 = Math.sin(TWO_PI * WIGGLE_HZ * this.wiggleClock);
      wiggleRad = 0.06 * s32;
      wiggleX = 0.012 * this.baseSize * s32;
    }

    const S = this.baseSize;

    // Axiom 3: Volume-preserving squash & stretch (sx * sy === 1.0)
    const sy = clamp(1.0 + SQUASH_K * activePose.squash, 0.74, 1.30);
    const sx = 1.0 / sy;

    // Dynamic grounded floor shadow: shrinks in mid-air jump, widens on beat-down dip & landing!
    if (this.shadow) {
      const baseShadowScale = (S * 0.27) / 100.0;
      const heightFactor = clamp(1.0 - activePose.hopY * 2.25, 0.48, 1.24);
      const squashSpread = clamp(1.0 - activePose.squash * 0.08, 0.88, 1.16);
      this.shadow.x = wiggleX * 0.5;
      this.shadow.y = S * 0.44;
      this.shadow.scale.set(baseShadowScale * heightFactor * squashSpread, baseShadowScale * heightFactor);
      this.shadow.alpha = clamp(0.95 * heightFactor, 0.35, 1.0);
    }

    // Apply pelvis transform (Axiom 0: PixiJS Y-Down -> y = -hopY * S, rotation = -theta)
    this.pelvis.x = wiggleX;
    this.pelvis.y = -activePose.hopY * S;
    this.pelvis.scale.set(sx, sy);
    this.pelvis.rotation = -(activePose.body + wiggleRad);

    if (!this.fallbackMode && this.parts) {
      const p = this.parts;
      // Axiom 0 & 4 & 6.3: Convert canonical CCW+ angles to PixiJS CW+ (negated)
      p.head.rotation = -(activePose.head + 1.2 * wiggleRad);
      p.head.y = -(RIG_PART_SPECS.head.oy + activePose.headBob) * S;
      p.armL.rotation = -(activePose.armL + 1.3 * wiggleRad);
      p.armR.rotation = -(activePose.armR - 1.3 * wiggleRad);
      p.legL.rotation = -activePose.legL;
      p.legR.rotation = -activePose.legR;
    } else if (this.fallbackSprite) {
      const wantTex = frozen ? this.fallbackFreezeTex : this.fallbackDanceTex;
      if (wantTex && this.fallbackSprite.texture !== wantTex) {
        this.fallbackSprite.texture = wantTex;
        this._applyBaseSize();
      }
    }
  }

  destroy() {
    this.root.parent?.removeChild(this.root);
    this.root.destroy({ children: true });
    this.parts = null;
    this.shadow = null;
    this.fallbackSprite = null;
  }
}
