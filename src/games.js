/**
 * Fruit Ninja Zen Mode (90s) + Redi & Ludi Family Dopamine Engine:
 *  - 90-second non-stop Zen arc with 3 Boss Relays (Pineapple -> Melon -> Watermelon King!)
 *  - 8 distinct 3D clay fruits launched from ALL directions (bottom arcs, left/right cannons, top bounce, fountains)
 *  - Real 2D physics: gravity, angular inertia, elastic wall bounce, fruit-to-fruit elastic collisions, knockback
 *  - Multi-hit Tough Fruits (HP 2~3) appearing frequently with bounce-back & HP dot indicators
 *  - All 7 Motion Action Mathematical Axioms (doc/motion_game_axioms.md)
 */

const SPEED_MULT = {
  slow: 0.78,
  normal: 1.0,
  fast: 1.26,
};

const HITBOX_MULT = {
  slow: 1.35,
  normal: 1.16,
  fast: 1.0,
};

// 공리 1: 속도 기반 베기 임계치 (px/s)
const SLASH_MIN_VEL = {
  slow: 200,
  normal: 280,
  fast: 360,
};

// 손 궤적 및 손 후광 VFX를 표시하는 손 액션 게임 (전신 포즈/댄스/균형 게임에서는 완전히 숨김!)
const HAND_VFX_GAMES = new Set(["fruit", "balloon", "mole"]);

function distPointToSegment(cx, cy, x0, y0, x1, y1) {
  const vx = x1 - x0;
  const vy = y1 - y0;
  const lenSq = vx * vx + vy * vy;
  if (lenSq < 1e-4) return Math.hypot(cx - x0, cy - y0);
  const s = Math.max(0, Math.min(1, ((cx - x0) * vx + (cy - y0) * vy) / lenSq));
  return Math.hypot(cx - (x0 + s * vx), cy - (y0 + s * vy));
}

// 8종 3D 클레이 과일 (일반 1타 6종 + 단단한 다중타격 2~3타 4종)
const REGULAR_FRUITS = [
  { kind: "strawberry", color: "#FF4D6D", hex: 0xff4d6d, hp: 1 },
  { kind: "apple",      color: "#EF476F", hex: 0xef476f, hp: 1 },
  { kind: "orange",     color: "#FF9F1C", hex: 0xff9f1c, hp: 1 },
  { kind: "banana",     color: "#FFD166", hex: 0xffd166, hp: 1 },
  { kind: "grape",      color: "#9B5DE5", hex: 0x9b5de5, hp: 1 },
  { kind: "peach",      color: "#FF8FA3", hex: 0xff8fa3, hp: 1 },
];

const TOUGH_FRUITS = [
  { kind: "pineapple", color: "#FFB703", hex: 0xffb703, hp: 3 },
  { kind: "melon",     color: "#52D1A0", hex: 0x52d1a0, hp: 2 },
  { kind: "grape",     color: "#9B5DE5", hex: 0x9b5de5, hp: 2 },
  { kind: "peach",     color: "#FF8FA3", hex: 0xff8fa3, hp: 2 },
];

// 90초 동안 등장하는 3단계 보스 릴레이! (온가족이 5~9초간 신나게 연타하는 탱탱 보스전!)
const BOSS_SCHEDULE = [
  { triggerTime: 22, kind: "pineapple", name: "거대 파인애플", hits2p: 26, hits1p: 18, bonus: 12, color: "#FFB703", hex: 0xffd43b },
  { triggerTime: 48, kind: "melon",     name: "거대 황금 멜론", hits2p: 34, hits1p: 24, bonus: 15, color: "#52D1A0", hex: 0x62f2c8 },
  { triggerTime: 72, kind: "watermelon",name: "거대 수박 왕",  hits2p: 45, hits1p: 32, bonus: 25, color: "#FF4D6D", hex: 0x7ef58a },
];

// 4번 게임: 동물 흉내 포즈 따라하기 7종 릴레이 (체형 독립 14관절 전신 판정!)
const ANIMAL_POSES = [
  { id: "giraffe",  tex: "animal_giraffe",  name: "기린",     cue: "두 팔을 머리 위로 쭉!",        shortCue: "기린 만세!",      color: "#FFB703", hex: 0xffb703 },
  { id: "eagle",    tex: "animal_eagle",    name: "독수리",   cue: "두 팔을 양옆으로 활짝!",       shortCue: "독수리 날개!",    color: "#F97316", hex: 0xf97316 },
  { id: "crab",     tex: "animal_crab",     name: "꽃게",     cue: "양팔을 꺾어 집게손 쫙!",       shortCue: "꽃게 집게손!",    color: "#EF4444", hex: 0xef4444 },
  { id: "flamingo", tex: "animal_flamingo", name: "플라밍고", cue: "한 발 들고 균형 잡기!",        shortCue: "한 발 균형!",     color: "#EC4899", hex: 0xec4899 },
  { id: "frog",     tex: "animal_frog",     name: "개구리",   cue: "바닥으로 쏙 웅크리기!",        shortCue: "웅크리기(스쿼트)", color: "#22C55E", hex: 0x22c55e },
  { id: "elephant", tex: "animal_elephant", name: "코끼리",   cue: "몸을 옆으로 기울여 흔들기!",   shortCue: "코끼리 흔들기!",  color: "#38BDF8", hex: 0x38bdf8 },
  { id: "starfish", tex: "animal_starfish", name: "불가사리", cue: "팔·다리 모두 크게 X자로 쫙!",  shortCue: "불가사리 X자!",   color: "#A855F7", hex: 0xa855f7 },
];

function loadSprite(src) {
  const img = new Image();
  img.src = src;
  return img;
}

export class MiniGameEngine {
  constructor(sound, hooks) {
    this.sound = sound;
    this.hooks = hooks;
    this.gameId = "fruit";
    this.settings = { players: 2, quietMode: true, speed: "normal" };
    this.uidSeq = 1;
    this.trails = [[], [], [], []];
    this.prevHandPos = [null, null, null, null];
    this.handEnergy = [0, 0, 0, 0];
    this.swooshCooldown = [0, 0, 0, 0];
    this.emaMotion = 0;

    this.particles = [];
    this.splatters = [];
    this.bubbles = []; // 풍선 전용 상승 비눗방울 파티클!
    this.airRings = []; // 풍선 전용 이중 공기 파동 링!
    this.halves = [];
    this.flashes = [];
    this.confetti = [];
    this.finishTimerId = null;

    this.screenShake = 0;
    this.screenFlash = 0;
    this.screenFlashHex = 0xffffff;
    this.hitstopTimer = 0;
    this.feverActive = false;
    this.combo = 0;
    this.comboTimer = 0;

    this.sprites = {};
    ["strawberry", "apple", "orange", "banana", "grape", "peach", "pineapple", "melon"].forEach((k) => {
      this.sprites[k] = loadSprite(`./assets/fruit_${k}.png`);
      this.sprites[`${k}_left`] = loadSprite(`./assets/fruit_${k}_left.png`);
      this.sprites[`${k}_right`] = loadSprite(`./assets/fruit_${k}_right.png`);
    });
    this.sprites.watermelon = loadSprite("./assets/watermelon.png");
    this.sprites.watermelon_left = loadSprite("./assets/watermelon_left.png");
    this.sprites.watermelon_right = loadSprite("./assets/watermelon_right.png");
    this.sprites.balloon_red = loadSprite("./assets/balloon_red.png");
    this.sprites.balloon_beach = loadSprite("./assets/balloon_beach.png");
    this.sprites.balloon_gold = loadSprite("./assets/balloon_gold.png");
    this.sprites.dino = loadSprite("./assets/dino_sprite.png");
    this.sprites.jungle_vine = loadSprite("./assets/jungle_vine.png");
    this.sprites.momo_squat = loadSprite("./assets/momo_squat.png");
    this.sprites.star_3d = loadSprite("./assets/star_3d.png");
    this.sprites.mole_cute = loadSprite("./assets/mole_cute.png");
    this.sprites.mole_gold = loadSprite("./assets/mole_gold.png");
    this.sprites.log_bridge = loadSprite("./assets/log_bridge.png");

    this.reset("fruit", this.settings);
  }

  reset(gameId, settings) {
    clearTimeout(this.finishTimerId);
    this.finishTimerId = null;
    this.gameId = gameId;
    this.settings = { ...settings };
    this.score = 0;
    this.elapsed = 0;
    this.finished = false;
    this.particles = [];
    this.splatters = [];
    this.bubbles = [];
    this.airRings = [];
    this.halves = [];
    this.flashes = [];
    this.confetti = [];
    this.trails = [[], [], [], []];
    this.prevHandPos = [null, null, null, null];
    this.handEnergy = [0, 0, 0, 0];
    this.swooshCooldown = [0, 0, 0, 0];
    this.emaMotion = 0;
    this.screenShake = 0;
    this.screenFlash = 0;
    this.hitstopTimer = 0;
    this.feverActive = false;
    this.combo = 0;
    this.comboTimer = 0;

    const spd = SPEED_MULT[settings.speed] || 1.0;

    if (gameId === "fruit") {
      this.zenDuration = 90.0;
      this.zenElapsed = 0;
      this.bossIndex = 0;
      this.boss = null;
      this.bossHits = 0;
      this.bossMaxHits = 10;
      this.bossHitCooldown = 0;
      this.feverBurstTimer = 0;
      this.fruits = [];
      this.spawnTimer = 0.25;
      this.hooks.onProgress(0, 9);
      this.hooks.onCallout("90초 과일 팡팡! 사방에서 날아와요!", 2600);
      this.sound.startBgm("fruit", 1.0);
    } else if (gameId === "balloon") {
      this.rallyTarget = 200;
      this.nextMilestone = 50;
      this.balls = [
        {
          uid: this.uidSeq++,
          kind: "balloon_red",
          x: 0.5,
          y: 0.26,
          vx: 0.12 * spd,
          vy: 0.02,
          r: 0.105,
          rot: 0,
          vrot: 0,
          squash: 0,
          golden: false,
          points: 1,
          bounceCooldown: 0,
          driftSeed: Math.random() * 6.28,
        },
      ];
      this.beachBallSpawned = false;
      this.goldBallSpawned = false;
      this.hooks.onProgress(0, 10);
      this.hooks.onCallout("풍선을 200점까지 신나게 띄워요!", 2800);
      this.sound.startBgm("balloon", 1.0);
    } else if (gameId === "freeze") {
      this.roundsTotal = 5;
      this.round = 0;
      this.phase = "dance";
      this.phaseTimer = 7.4;
      this.freezeDuration = 3.4;
      this.danceEnergy = 0.55;
      this.freezeHold = 0;
      this.freezeElapsed = 0;
      this.freezeWiggleTime = 0;
      this.freezeSuccessCount = 0;
      this.wiggleSfxCooldown = 0;
      this.isWiggling = false;
      this.hooks.onProgress(0, this.roundsTotal);
      this.hooks.onCallout("네온 클럽 오픈! 신나게 흔들어 춤춰요!!", 2500);
      this.sound.startBgm("freeze", 1.0);
    } else if (gameId === "animal") {
      this.animalList = ANIMAL_POSES;
      this.animalIndex = 0;
      this.animalCleared = ANIMAL_POSES.map(() => false);
      this.animalTimeLimit = 10.0;
      this.animalTimer = this.animalTimeLimit;
      this.animalHold = 0;
      this.animalHoldTarget = 1.8;
      this.animalMatch = false;
      this.animalGraceTimer = 0;
      this.animalPause = 0;
      this.animalSuccessCount = 0;
      this.hooks.onProgress(0, ANIMAL_POSES.length);
      this.hooks.onCallout(`🦒 ${ANIMAL_POSES[0].name}! ${ANIMAL_POSES[0].cue}`, 2800);
      this.sound.startBgm("balloon", 1.0);
    } else if (gameId === "jungle") {
      this.jungleDuration = 60.0;
      this.jungleElapsed = 0;
      this.jungleTrackProgress = 0;
      this.jungleCheckpoints = 0;
      this.junglePhaseSeq = ["run", "squat", "run", "jump", "run", "squat", "run", "jump", "run", "squat", "jump"];
      this.junglePhaseIdx = 0;
      this.junglePhase = "run";
      this.junglePhaseTimer = 5.6;
      this.junglePhaseProgress = 0;
      this.jungleActiveDetected = false;
      this.jungleVineY = -0.25;
      this.jungleSquatCleared = false;
      this.junglePhaseTransitionDelay = 0;
      this.jungleStars = [];
      this.jungleJumpWaveCd = 0;
      this.junglePrevKneeDiff = [0, 0];
      this.jungleBaselineHeadY = [0.42, 0.42];
      this.jungleRunTick = 0;
      this.hooks.onProgress(0, 5);
      this.hooks.onCallout("🌴 달려라 정글 모험! 제자리 달리기 시작!!", 2800);
      this.sound.startBgm("adventure", 1.0);
    } else if (gameId === "mole") {
      this.moleDuration = 60.0;
      this.moleElapsed = 0;
      this.moleFeverTriggered = false;
      this.moleSpawnTimer = 0.45;
      this.moleNextRow = "top";
      this.moleHoles = [
        { id: 0, row: "top",    x: 0.24, y: 0.28, state: "idle", pop: 0, kind: "mole_cute", golden: false, holdTimer: 0, bonkTimer: 0, cooldown: 0 },
        { id: 1, row: "top",    x: 0.50, y: 0.26, state: "idle", pop: 0, kind: "mole_cute", golden: false, holdTimer: 0, bonkTimer: 0, cooldown: 0 },
        { id: 2, row: "top",    x: 0.76, y: 0.28, state: "idle", pop: 0, kind: "mole_cute", golden: false, holdTimer: 0, bonkTimer: 0, cooldown: 0 },
        { id: 3, row: "bottom", x: 0.24, y: 0.80, state: "idle", pop: 0, kind: "mole_cute", golden: false, holdTimer: 0, bonkTimer: 0, cooldown: 0 },
        { id: 4, row: "bottom", x: 0.50, y: 0.82, state: "idle", pop: 0, kind: "mole_cute", golden: false, holdTimer: 0, bonkTimer: 0, cooldown: 0 },
        { id: 5, row: "bottom", x: 0.76, y: 0.80, state: "idle", pop: 0, kind: "mole_cute", golden: false, holdTimer: 0, bonkTimer: 0, cooldown: 0 },
      ];
      this.hooks.onProgress(0, 6);
      this.hooks.onCallout("🐹 위는 손 하이파이브! 아래는 발·손 터치!!", 2800);
      this.sound.startBgm("adventure", 1.0);
    } else if (gameId === "balance") {
      this.balanceDuration = 60.0;
      this.balanceElapsed = 0;
      this.bridgeAngle = 0;
      this.bridgeVel = 0;
      this.windDir = 0;
      this.windStrength = 0;
      this.windActive = false;
      this.windTimer = 3.0;
      this.balanceInSafe = true;
      this.balanceWideArms = false;
      this.balancePointAccum = 0;
      this.balanceShowerAccum = 0;
      this.balanceWobbleCd = 0;
      this.flamingoActive = false;
      this.flamingoTimer = 0;
      this.flamingoHold = 0;
      this.flamingoHoldTarget = 1.6;
      this.flamingoTriggered = [false, false];
      this.balanceStars = [];
      this.balanceStarSpawn = 2.0;
      this.hooks.onProgress(0, 6);
      this.hooks.onCallout("🪵 두 팔을 활짝 펴고 외나무다리 균형 잡기!", 2800);
      this.sound.startBgm("adventure", 1.0);
    }
    this.hooks.onScore(0);
  }

  stop() {
    this.finished = true;
    this.feverActive = false;
    clearTimeout(this.finishTimerId);
    this.finishTimerId = null;
    this.sound.stopBgm();
  }

  spawnBalloonVfx(x, y, color, hexColor, label, power = 1) {
    // 1) 이중 공기 파동 링 (Air Puff Ripple!)
    this.airRings.push(
      { x, y, r: 22, maxR: power >= 2 ? 175 : 125, hexColor, life: 0.42, maxLife: 0.42 },
      { x, y, r: 10, maxR: power >= 2 ? 125 : 88,  hexColor: 0xffffff, life: 0.34, maxLife: 0.34 }
    );
    // 2) 위로 둥실 떠오르는 무지개 비눗방울 파티클!
    const bCount = power >= 2 ? 14 : 9;
    const cols = [0x67e8f9, 0xfda4af, 0xfde047, 0xc4b5fd, hexColor];
    for (let i = 0; i < bCount; i++) {
      const a = Math.random() * Math.PI * 2;
      const sp = 55 + Math.random() * 145;
      this.bubbles.push({
        x: x + Math.cos(a) * 18,
        y: y + Math.sin(a) * 18,
        vx: Math.cos(a) * sp,
        vy: -90 - Math.random() * 130,
        r: 7 + Math.random() * 11,
        hexColor: cols[i % cols.length],
        seed: Math.random() * 6.28,
        life: 0.95 + Math.random() * 0.55,
        maxLife: 1.5,
      });
    }
    // 3) 별빛 & 텍스트
    this.spawnBurst(x, y, color, hexColor, label, power);
  }

  registerCombo(x, y) {
    this.combo++;
    this.comboTimer = 1.6;
    if (this.combo >= 3 && this.combo % 2 === 1) {
      const label =
        this.combo >= 11 ? `${this.combo} GODLIKE!!!` :
        this.combo >= 7  ? `${this.combo} FEVER!!!` :
        this.combo >= 5  ? `${this.combo} SUPER!!` :
        `${this.combo} COMBO!`;
      this.particles.push({
        uid: this.uidSeq++,
        x,
        y: Math.max(95, y - 56),
        vx: 0,
        vy: -55,
        life: 0.95,
        maxLife: 0.95,
        color: "#FF6B00",
        hexColor: 0xffd43b,
        text: label,
        bigText: true,
      });
    }
  }

  spawnSplatter(x, y, hexColor, scale = 1.0) {
    const blobs = [];
    for (let i = 0; i < 7; i++) {
      const a = Math.random() * Math.PI * 2;
      const d = (12 + Math.random() * 44) * scale;
      blobs.push({
        dx: Math.cos(a) * d,
        dy: Math.sin(a) * d,
        r: (7 + Math.random() * 14) * scale,
      });
    }
    this.splatters.push({ x, y, hexColor, blobs, life: 1.6, maxLife: 1.6 });
    if (this.splatters.length > 22) this.splatters.shift();
  }

  spawnSlicedHalves(kind, x, y, r, slashAngle = -0.35, slashVx = 0, slashVy = 0) {
    const nx = -Math.sin(slashAngle);
    const ny = Math.cos(slashAngle);
    const splitSpd = 215 + Math.random() * 75;
    this.halves.push(
      {
        uid: this.uidSeq++,
        texKey: `${kind}_left`,
        x: x - nx * r * 0.22,
        y: y - ny * r * 0.22,
        vx: -nx * splitSpd + slashVx * 0.14,
        vy: -ny * splitSpd - 165 + slashVy * 0.08,
        rot: slashAngle * 0.35,
        vrot: -5.4,
        r,
        life: 0.92,
        maxLife: 0.92,
      },
      {
        uid: this.uidSeq++,
        texKey: `${kind}_right`,
        x: x + nx * r * 0.22,
        y: y + ny * r * 0.22,
        vx: nx * splitSpd + slashVx * 0.14,
        vy: ny * splitSpd - 155 + slashVy * 0.08,
        rot: slashAngle * 0.35,
        vrot: 5.6,
        r,
        life: 0.92,
        maxLife: 0.92,
      }
    );
  }

  spawnBurst(x, y, color, hexColor = 0xffdc4d, text = "팡!", power = 1, slashAngle = null) {
    const count = power === 3 ? 42 : power === 2 ? 28 : 18;
    for (let i = 0; i < count; i++) {
      const ang = (Math.PI * 2 * i) / count + Math.random() * 0.25;
      const spd = (140 + power * 65) + Math.random() * (200 + power * 70);
      this.particles.push({
        uid: this.uidSeq++,
        x,
        y,
        vx: Math.cos(ang) * spd,
        vy: Math.sin(ang) * spd - 65,
        life: 0.72 + power * 0.16,
        maxLife: 0.72 + power * 0.16,
        color,
        hexColor,
        star: i % 2 === 0,
        size: (8 + power * 3) + Math.random() * 8,
      });
    }
    this.flashes.push({
      x,
      y,
      maxR: power === 3 ? 280 : power === 2 ? 175 : 125,
      hexColor,
      color,
      angle: slashAngle !== null ? slashAngle : -0.45 + (Math.random() - 0.5) * 0.6,
      life: 0.26 + power * 0.08,
      maxLife: 0.26 + power * 0.08,
    });
    if (text) {
      this.particles.push({
        uid: this.uidSeq++,
        x,
        y: y - 16,
        vx: 0,
        vy: -90,
        life: 0.85,
        maxLife: 0.85,
        color,
        hexColor,
        text,
        bigText: power >= 2,
      });
    }
    this.screenShake = Math.max(this.screenShake, power === 3 ? 1.35 : power === 2 ? 0.75 : 0.45);
    if (power >= 2) {
      this.screenFlash = power === 3 ? 0.65 : 0.3;
      this.screenFlashHex = power === 3 ? 0xffffff : 0xffe875;
    }
  }

  spawnConfetti(w, count = 110) {
    const cols = [
      ["#FF5C70", 0xff5c70],
      ["#FFD43B", 0xffd43b],
      ["#48D1CC", 0x48d1cc],
      ["#60A5FA", 0x60a5fa],
      ["#C084FC", 0xc084fc],
    ];
    for (let i = 0; i < count; i++) {
      const [c, hex] = cols[i % cols.length];
      this.confetti.push({
        x: Math.random() * w,
        y: -20 - Math.random() * 320,
        vx: (Math.random() - 0.5) * 120,
        vy: 140 + Math.random() * 210,
        rot: Math.random() * Math.PI,
        vrot: (Math.random() - 0.5) * 9,
        color: c,
        hexColor: hex,
        size: 9 + Math.random() * 8,
      });
    }
  }

  getAllHands(players, w, h) {
    const hands = [];
    players.forEach((p, idx) => {
      const pid = p.id ?? idx;
      const col = pid === 0 ? "#4AD3C8" : "#FF7D89";
      const lConf = p.leftHand?.smoothConf ?? p.leftHand?.v ?? 1;
      const rConf = p.rightHand?.smoothConf ?? p.rightHand?.v ?? 1;
      if (lConf >= 0.20 && p.leftHand.x >= -0.05 && p.leftHand.x <= 1.05 && p.leftHand.y >= -0.05 && p.leftHand.y <= 1.05) {
        hands.push({ x: p.leftHand.x * w, y: p.leftHand.y * h, player: pid, color: col, slot: pid * 2, conf: lConf });
      }
      if (rConf >= 0.20 && p.rightHand.x >= -0.05 && p.rightHand.x <= 1.05 && p.rightHand.y >= -0.05 && p.rightHand.y <= 1.05) {
        hands.push({ x: p.rightHand.x * w, y: p.rightHand.y * h, player: pid, color: col, slot: pid * 2 + 1, conf: rConf });
      }
    });
    return hands;
  }

  update(dt, players, w, h) {
    if (this.hitstopTimer > 0) {
      this.hitstopTimer -= dt;
      dt *= 0.22;
    }

    this.elapsed += dt;
    this.screenShake = Math.max(0, this.screenShake - dt * 3.6);
    this.screenFlash = Math.max(0, this.screenFlash - dt * 2.2);

    if (this.comboTimer > 0) {
      this.comboTimer -= dt;
      if (this.comboTimer <= 0) this.combo = 0;
    }

    const minVel = SLASH_MIN_VEL[this.settings.speed] || 280;
    const rawHands = this.getAllHands(players, w, h);
    const showHandVfx = HAND_VFX_GAMES.has(this.gameId);
    const activeSlots = new Set(rawHands.map((hd) => hd.slot));

    // Clean up inactive/absent player hand slots so stale trails & velocities NEVER ghost on screen!
    for (let s = 0; s < 4; s++) {
      if (!activeSlots.has(s)) {
        this.prevHandPos[s] = null;
        this.handEnergy[s] = 0;
        if (this.trails[s] && this.trails[s].length > 0) this.trails[s].length = 0;
      }
    }

    this.hands = rawHands.map((hd) => {
      const prev = this.prevHandPos[hd.slot];
      const px = prev ? prev.x : hd.x;
      const py = prev ? prev.y : hd.y;
      const dx = hd.x - px;
      const dy = hd.y - py;
      const vx = dt > 0.0001 ? dx / dt : 0;
      const vy = dt > 0.0001 ? dy / dt : 0;
      const speed = Math.hypot(vx, vy);
      const isSlashing = speed >= minVel;
      const angle = Math.atan2(dy, dx);

      let e = this.handEnergy[hd.slot] || 0;
      if (showHandVfx) {
        if (isSlashing) e = Math.min(1, e + dt * 7.0);
        else e = Math.max(0, e - dt * 2.8);
      } else {
        e = 0;
      }
      this.handEnergy[hd.slot] = e;
      this.prevHandPos[hd.slot] = { x: hd.x, y: hd.y };

      // 과일 팡팡에서 손을 아주 크게 휘두를 때만 은은한 칼날 바람 소리(Swoosh)
      this.swooshCooldown[hd.slot] = Math.max(0, (this.swooshCooldown[hd.slot] || 0) - dt);
      if (this.gameId === "fruit" && !this.finished && speed >= minVel * 2.8 && this.swooshCooldown[hd.slot] <= 0) {
        this.sound.playSwoosh();
        this.swooshCooldown[hd.slot] = 0.72;
      }

      const tr = this.trails[hd.slot];
      if (tr) {
        if (!showHandVfx) {
          if (tr.length > 0) tr.length = 0;
        } else if (e > 0.06) {
          tr.push({ x: hd.x, y: hd.y, color: hd.color, player: hd.player });
          if (tr.length > 13) tr.shift();
        } else if (tr.length > 0) {
          tr.shift();
        }
      }
      return { ...hd, px, py, vx, vy, speed, isSlashing, angle, energy: e };
    });

    this.splatters = this.splatters.filter((sp) => { sp.life -= dt; sp.y += 14 * dt; return sp.life > 0; });
    this.bubbles = this.bubbles.filter((bb) => {
      bb.life -= dt;
      bb.x += (bb.vx + Math.sin(this.elapsed * 6 + bb.seed) * 28) * dt;
      bb.y += bb.vy * dt;
      bb.vx *= 1 - 1.8 * dt;
      return bb.life > 0;
    });
    this.airRings = this.airRings.filter((ar) => { ar.life -= dt; return ar.life > 0; });
    this.halves = this.halves.filter((hf) => {
      hf.life -= dt;
      hf.x += hf.vx * dt;
      hf.y += hf.vy * dt;
      hf.vy += 600 * dt;
      hf.rot += hf.vrot * dt;
      return hf.life > 0;
    });
    this.flashes = this.flashes.filter((fl) => { fl.life -= dt; return fl.life > 0; });
    this.particles = this.particles.filter((pt) => {
      pt.life -= dt;
      pt.x += pt.vx * dt;
      pt.y += pt.vy * dt;
      if (!pt.text) pt.vy += 320 * dt;
      return pt.life > 0;
    });
    this.confetti.forEach((c) => {
      c.x += c.vx * dt;
      c.y += c.vy * dt;
      c.rot += c.vrot * dt;
      if (c.y > h + 30) c.y = -20;
    });

    if (this.finished) {
      // 피날레 아웃트로: 종료 후에도 풍선은 둥실 떠오르고, 3번 댄서들은 승리 댄스 유지!
      if (this.gameId === "balloon") {
        this.balls.forEach((b) => {
          b.y -= 0.16 * dt;
          b.x += Math.sin(this.elapsed * 3.0 + b.driftSeed) * 0.08 * dt;
          b.rot += 0.9 * dt;
        });
      }
      return;
    }

    if (this.gameId === "fruit") this.updateFruitZen(dt, this.hands, w, h);
    else if (this.gameId === "balloon") this.updateBalloon(dt, players, this.hands, w, h);
    else if (this.gameId === "freeze") this.updateFreeze(dt, players, w, h);
    else if (this.gameId === "animal") this.updateAnimalPose(dt, players, w, h);
    else if (this.gameId === "jungle") this.updateJungle(dt, players, this.hands, w, h);
    else if (this.gameId === "mole") this.updateMole(dt, players, this.hands, w, h);
    else if (this.gameId === "balance") this.updateBalance(dt, players, this.hands, w, h);
  }

  /* ------------------------------------------------------------------
   * GAME 1: 90초 Fruit Ninja Zen + 사방 물리 + 다중 타격 + 보스 3종 릴레이
   * ------------------------------------------------------------------ */
  spawnDirectionalFruit(w, h, spd, allowSpecial = true, forcedZone = null) {
    // 28% 확률로 한 번에 안 터지는 단단한 과일(HP 2~3)!
    const isTough = Math.random() < 0.28;
    const pool = isTough ? TOUGH_FRUITS : REGULAR_FRUITS;
    const meta = pool[Math.floor(Math.random() * pool.length)];

    let special = "normal";
    if (allowSpecial && !isTough) {
      const r = Math.random();
      if (r < 0.08) special = "rainbow";
      else if (r < 0.22) special = "golden";
    }

    const r = Math.min(w, h) * (isTough ? 0.095 : special !== "normal" ? 0.092 : 0.078);
    // 5가지 사방 발사 구역 (하단 포물선 / 좌측 캐논 / 우측 캐논 / 상단 낙하 바운스 / 중앙 분수)
    const zones = ["bottom", "bottom", "left", "right", "top"];
    const zone = forcedZone || zones[Math.floor(Math.random() * zones.length)];

    let x, y, vx, vy, bouncesLeft = 0;
    if (zone === "left") {
      x = -r;
      y = h * (0.28 + Math.random() * 0.44);
      vx = w * (0.28 + Math.random() * 0.16) * spd;
      vy = -h * (0.26 + Math.random() * 0.16) * spd;
    } else if (zone === "right") {
      x = w + r;
      y = h * (0.28 + Math.random() * 0.44);
      vx = -w * (0.28 + Math.random() * 0.16) * spd;
      vy = -h * (0.26 + Math.random() * 0.16) * spd;
    } else if (zone === "top") {
      x = w * (0.16 + Math.random() * 0.68);
      y = -r;
      vx = (Math.random() - 0.5) * w * 0.22 * spd;
      vy = h * (0.08 + Math.random() * 0.08) * spd;
      bouncesLeft = 1; // 바닥에서 한 번 통! 튀어 오름
    } else {
      // bottom arc
      x = w * (0.14 + Math.random() * 0.72);
      y = h + r;
      const toCenter = (w * 0.5 - x) * (0.35 + Math.random() * 0.35);
      vx = (toCenter + (Math.random() - 0.5) * 90) * spd;
      vy = -h * (0.56 + Math.random() * 0.16) * spd;
    }

    this.fruits.push({
      uid: this.uidSeq++,
      x, y, vx, vy, r,
      kind: meta.kind,
      special,
      hp: special !== "normal" ? 1 : meta.hp,
      maxHp: special !== "normal" ? 1 : meta.hp,
      hitCooldown: 0,
      squash: 0,
      bouncesLeft,
      color: special === "golden" ? "#FFB703" : special === "rainbow" ? "#A855F7" : meta.color,
      hexColor: special === "golden" ? 0xffd43b : special === "rainbow" ? 0xc084fc : meta.hex,
      rot: (Math.random() - 0.5) * 0.5,
      vrot: (Math.random() - 0.5) * 2.4,
    });
  }

  resolveFruitCollisions() {
    // 물리 법칙: 날아다니는 과일끼리 부딪히면 탄성 충돌로 퉁퉁 튕겨 나감!
    const n = this.fruits.length;
    for (let i = 0; i < n; i++) {
      for (let j = i + 1; j < n; j++) {
        const a = this.fruits[i];
        const b = this.fruits[j];
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        const dist = Math.hypot(dx, dy);
        const minDist = (a.r + b.r) * 0.92;
        if (dist > 0.01 && dist < minDist) {
          const nx = dx / dist;
          const ny = dy / dist;
          const overlap = (minDist - dist) * 0.5;
          a.x -= nx * overlap;
          a.y -= ny * overlap;
          b.x += nx * overlap;
          b.y += ny * overlap;

          const rvx = b.vx - a.vx;
          const rvy = b.vy - a.vy;
          const velAlongNormal = rvx * nx + rvy * ny;
          if (velAlongNormal < 0) {
            const impulse = -(1 + 0.82) * velAlongNormal * 0.5;
            a.vx -= impulse * nx;
            a.vy -= impulse * ny;
            b.vx += impulse * nx;
            b.vy += impulse * ny;
            a.vrot += (Math.random() - 0.5) * 2.2;
            b.vrot += (Math.random() - 0.5) * 2.2;
          }
        }
      }
    }
  }

  updateFruitZen(dt, hands, w, h) {
    const spd = SPEED_MULT[this.settings.speed] || 1.0;
    const hMult = HITBOX_MULT[this.settings.speed] || 1.16;

    this.zenElapsed += dt;
    const zenProg = Math.min(9, Math.floor((this.zenElapsed / this.zenDuration) * 9));
    this.hooks.onProgress(zenProg, 9);

    if (this.feverBurstTimer > 0) {
      this.feverBurstTimer -= dt;
      this.feverActive = true;
      if (this.feverBurstTimer <= 0 && !this.boss) {
        this.feverActive = false;
        this.sound.setBgmRate(1.0);
      }
    }

    // 90초 종료 체크 (보스전 진행 중이면 보스를 깨거나 102초에 마무리)
    if (this.zenElapsed >= this.zenDuration && (!this.boss || this.zenElapsed >= this.zenDuration + 12)) {
      this.boss = null;
      this.feverActive = false;
      this.spawnConfetti(w, 130);
      this.finishGame(`90초 동안 사방에서 쏟아진 과일 ⭐ ${this.score}점 대성공!`);
      return;
    }

    // 보스 3종 릴레이 트리거 (24s 파인애플 -> 52s 멜론 -> 76s 수박 왕!)
    if (!this.boss && this.bossIndex < BOSS_SCHEDULE.length) {
      const nextBoss = BOSS_SCHEDULE[this.bossIndex];
      if (this.zenElapsed >= nextBoss.triggerTime) {
        this.spawnScheduledBoss(nextBoss, w, h);
        this.bossIndex++;
      }
    }

    // 사방에서 과일 자주 등장 (보스 중에도 양옆에서 보너스 과일이 가끔 날아옴!)
    this.spawnTimer -= dt;
    const isFever = this.feverActive || this.zenElapsed > 65;
    const maxOnScreen = this.boss ? 3 : isFever ? 9 : 6;
    if (this.spawnTimer <= 0 && this.fruits.length < maxOnScreen) {
      if (this.boss) {
        this.spawnDirectionalFruit(w, h, spd, false, Math.random() < 0.5 ? "left" : "right");
        this.spawnTimer = 1.65 / spd;
      } else {
        // 25% 확률로 분수 동시 발사 (2~3개 사방!)
        const batch = isFever ? (Math.random() < 0.6 ? 3 : 2) : (Math.random() < 0.45 ? 2 : 1);
        for (let b = 0; b < batch; b++) {
          this.spawnDirectionalFruit(w, h, spd * (isFever ? 1.08 : 1.0), true);
        }
        this.spawnTimer = (isFever ? 0.52 : 0.72) / spd;
      }
    }

    // 과일 물리 이동 + 좌우 벽 탄성 반발 + 바닥 1회 바운스
    const gravity = h * 0.46 * spd;
    let rainbowTrigger = false;

    this.fruits = this.fruits.filter((f) => {
      f.hitCooldown = Math.max(0, f.hitCooldown - dt);
      f.squash = Math.max(0, f.squash - dt * 5.0);

      f.x += f.vx * dt;
      f.y += f.vy * dt;
      f.vy += gravity * dt;
      f.vx *= 1 - 0.08 * dt; // 미세 공기 저항
      f.rot += f.vrot * dt;

      // 좌우 벽 탄성 튕김 (화면 안에 머물며 역동적 움직임!)
      if (f.x < f.r * 0.8 && f.vx < 0) {
        f.x = f.r * 0.8;
        f.vx = Math.abs(f.vx) * 0.8;
        f.vrot *= -0.9;
      } else if (f.x > w - f.r * 0.8 && f.vx > 0) {
        f.x = w - f.r * 0.8;
        f.vx = -Math.abs(f.vx) * 0.8;
        f.vrot *= -0.9;
      }

      // 상단 발사 과일 1회 바닥 트램펄린 바운스
      if (f.bouncesLeft > 0 && f.y > h - f.r * 0.9 && f.vy > 0) {
        f.y = h - f.r * 0.9;
        f.vy = -h * 0.52 * spd;
        f.squash = 0.85;
        f.bouncesLeft--;
      }

      // 베기 충돌 판정 (공리 1·2)
      if (f.hitCooldown <= 0) {
        for (const hd of hands) {
          if (!hd.isSlashing) continue;
          const dist = distPointToSegment(f.x, f.y, hd.px, hd.py, hd.x, hd.y);
          if (dist < f.r * 1.42 * hMult) {
            f.hp -= 1;
            if (f.hp > 0) {
              // 한 번에 안 터지는 단단한 과일! 물리 넉백 + 찌그러짐 + 스파크!
              f.hitCooldown = 0.18;
              f.squash = 1.0;
              f.vy = -Math.max(h * 0.34, Math.abs(f.vy) * 0.65); // 위로 톡 튕겨 올라 한 번 더 베기 좋게!
              f.vx += Math.max(-240, Math.min(240, hd.vx * 0.25));
              f.vrot += (hd.vx >= 0 ? 1 : -1) * 4.5;
              this.sound.playToughHit(f.maxHp - f.hp);
              this.spawnBurst(f.x, f.y, "#FFD43B", 0xffd43b, f.hp === 1 ? "한 번 더!!" : "통!", 1, hd.angle);
              return true;
            }

            // HP == 0 -> 시원하게 두 조각 폭발!
            this.registerCombo(f.x, f.y);
            this.spawnSplatter(f.x, f.y, f.hexColor, f.maxHp > 1 || f.special !== "normal" ? 1.45 : 1.0);
            this.spawnSlicedHalves(f.kind, f.x, f.y, f.r, hd.angle, hd.vx, hd.vy);

            if (f.special === "rainbow") {
              this.score += 3;
              this.sound.playRainbowBlast();
              this.spawnBurst(f.x, f.y, "#A855F7", 0xc084fc, "무지개 대폭발!!", 3, hd.angle);
              this.hitstopTimer = 0.14;
              rainbowTrigger = true;
            } else if (f.special === "golden") {
              this.score += 3;
              this.sound.playGoldenPop();
              this.spawnBurst(f.x, f.y, "#FFB703", 0xffd43b, "황금 팡!! +3", 2, hd.angle);
            } else if (f.maxHp > 1) {
              this.score += f.maxHp;
              this.sound.playGoldenPop();
              this.spawnBurst(f.x, f.y, f.color, f.hexColor, `대박 팡!! +${f.maxHp}`, 2, hd.angle);
            } else {
              this.score += 1;
              this.sound.playPop(this.combo);
              this.spawnBurst(f.x, f.y, f.color, f.hexColor, "팡! +1", 1, hd.angle);
            }
            this.hooks.onScore(this.score);
            return false;
          }
        }
      }

      return f.y < h + f.r * 2.5 && f.x > -f.r * 3 && f.x < w + f.r * 3;
    });

    // 과일끼리 탄성 충돌 처리!
    this.resolveFruitCollisions();

    // 무지개 아이템 폭발 시 화면의 모든 과일 연쇄 폭발!
    if (rainbowTrigger && this.fruits.length > 0) {
      this.fruits.forEach((other) => {
        this.score += Math.max(1, other.maxHp);
        this.spawnSplatter(other.x, other.y, other.hexColor, 1.15);
        this.spawnSlicedHalves(other.kind, other.x, other.y, other.r, -0.4);
        this.spawnBurst(other.x, other.y, other.color, other.hexColor, "연쇄 팡!", 1);
      });
      this.fruits = [];
      this.hooks.onScore(this.score);
    }

    // 보스전 물리 & 타격 (파인애플 -> 멜론 -> 수박 왕!)
    if (this.boss) {
      this.boss.x = w * 0.5 + Math.sin(this.elapsed * 2.0) * (w * 0.04); // 살짝 살랑거리며 움직임
      this.boss.y += (h * 0.48 - this.boss.y) * Math.min(1, dt * 5.5);
      const rage = this.bossHits / this.bossMaxHits;
      this.boss.r = Math.min(w, h) * (0.20 + rage * 0.05);
      this.boss.shake = Math.max(0, this.boss.shake - dt * 4.0);
      this.bossHitCooldown = Math.max(0, this.bossHitCooldown - dt);

      if (this.bossHitCooldown <= 0) {
        for (const hd of hands) {
          if (!hd.isSlashing) continue;
          const dist = distPointToSegment(this.boss.x, this.boss.y, hd.px, hd.py, hd.x, hd.y);
          if (dist < this.boss.r * 1.4 * hMult) {
            this.bossHits++;
            this.boss.shake = 1.15;
            this.bossHitCooldown = 0.19;
            this.sound.playBossHit(this.bossHits);
            const hitWords = ["퍽!", "쾅!", "짜릿!", "우지끈!", "파워 업!"];
            this.spawnSplatter(hd.x, hd.y, this.boss.hexColor, 0.95);
            this.spawnBurst(hd.x, hd.y, this.boss.color, this.boss.hexColor, hitWords[this.bossHits % hitWords.length], this.bossHits % 4 === 0 ? 2 : 1, hd.angle);

            if (this.bossHits >= this.bossMaxHits) {
              const b = this.boss;
              this.score += b.bonus;
              this.hooks.onScore(this.score);
              this.sound.playBossSmash();
              this.hitstopTimer = 0.2;
              this.spawnSplatter(b.x, b.y, b.hexColor, 2.3);
              this.spawnSlicedHalves(b.kind, b.x, b.y, b.r, hd.angle, hd.vx, hd.vy);
              this.spawnBurst(b.x, b.y, b.color, b.hexColor, `${b.name} 격파!! +${b.bonus}`, 3, hd.angle);
              this.boss = null;

              // 보스 격파 직후 9초간 과일 소나기 피버 폭발!
              this.feverBurstTimer = 9.0;
              this.feverActive = true;
              this.sound.playFeverStart();
              this.sound.setBgmRate(1.12);
              if (this.bossIndex >= BOSS_SCHEDULE.length) {
                this.spawnConfetti(w, 120);
                this.hooks.onCallout("피날레 피버! 마지막까지 팡팡!!", 3200);
              } else {
                this.hooks.onCallout("보스 클리어! 과일 소나기 피버!!", 3000);
              }
            }
            break;
          }
        }
      }
    }
  }

  spawnScheduledBoss(cfg, w, h) {
    this.bossHits = 0;
    this.bossMaxHits = this.settings.players === 2 ? cfg.hits2p : cfg.hits1p;
    this.bossHitCooldown = 0.2;
    this.boss = {
      kind: cfg.kind,
      name: cfg.name,
      bonus: cfg.bonus,
      color: cfg.color,
      hexColor: cfg.hex,
      x: w * 0.5,
      y: -160,
      r: Math.min(w, h) * 0.2,
      shake: 0,
    };
    this.sound.playBossAppear();
    this.sound.setBgmRate(1.14);
    this.hooks.onCallout(
      this.settings.players === 2
        ? `${cfg.name} 등장! 둘이 함께 흔들어 깨기!`
        : `${cfg.name} 등장! 힘껏 흔들어 깨기!`,
      3400
    );
  }

  /* ------------------------------------------------------------------
   * GAME 2: 풍선 배구 (리얼 공기역학 물리: 공기저항·부력 흔들림·스핀·풍선 간 탄성 충돌!)
   * ------------------------------------------------------------------ */
  updateBalloon(dt, players, hands, w, h) {
    const spd = SPEED_MULT[this.settings.speed] || 1.0;
    const hMult = HITBOX_MULT[this.settings.speed] || 1.16;
    const minBalloonVel = (SLASH_MIN_VEL[this.settings.speed] || 280) * 0.48;

    const targets = hands.filter((hd) => hd.speed >= minBalloonVel);
    players.forEach((p, idx) => {
      targets.push({ x: p.head.x * w, y: p.head.y * h, vx: 0, vy: -220, player: idx, color: "#FFD43B" });
    });

    this.balls.forEach((b) => {
      b.bounceCooldown = Math.max(0, b.bounceCooldown - dt);
      b.squash = Math.max(0, b.squash - dt * 4.8);

      const isBeach = b.kind === "balloon_beach";
      // 1) 리얼 풍선 공기역학: 부드러운 중력 + 제곱 공기저항(정점에서 둥실 체공!) + 부력 좌우 흔들림
      const gravity = (isBeach ? 0.34 : 0.22) * spd;
      const drag = isBeach ? 0.85 : 1.45;
      const airDrift = isBeach ? 0.04 : 0.11;

      b.vy += gravity * dt;
      // 공기 저항 (빠르게 올라갈 때 부드럽게 감속, 내려올 때 종단속도 유지)
      b.vx -= b.vx * drag * dt;
      b.vy -= b.vy * (drag * 0.72) * dt;
      // 자연스러운 거실 공기 흐름 흔들림 + 마그누스 스핀 커브
      b.vx += Math.sin(this.elapsed * 2.4 + b.driftSeed) * airDrift * dt + (isBeach ? b.vrot * 0.015 * dt : 0);

      b.x += b.vx * dt;
      b.y += b.vy * dt;

      if (isBeach) {
        b.rot += b.vrot * dt;
        b.vrot *= 1 - 0.55 * dt;
      } else {
        // 헬륨 풍선은 이동 방향으로 살짝 기울었다가 복원되는 진자 물리!
        const targetTilt = Math.max(-0.32, Math.min(0.32, b.vx * 0.75 + Math.sin(this.elapsed * 3.0 + b.driftSeed) * 0.07));
        b.rot += (targetTilt - b.rot) * Math.min(1, dt * 6.5);
      }

      // 2) 좌/우/천장 벽 탄성 반발
      if (b.x < 0.08) { b.x = 0.08; b.vx = Math.abs(b.vx) * 0.82; b.squash = 0.55; b.vrot *= -0.8; }
      if (b.x > 0.92) { b.x = 0.92; b.vx = -Math.abs(b.vx) * 0.82; b.squash = 0.55; b.vrot *= -0.8; }
      if (b.y < 0.1)  { b.y = 0.1;  b.vy = Math.abs(b.vy) * 0.55; b.squash = 0.5; }

      // 바닥 안전 바운스 (4세도 좌절 없는 탄성 바닥)
      if (b.y > 0.87) {
        b.y = 0.87;
        b.vy = -(isBeach ? 0.42 : 0.34) * spd;
        b.squash = 0.85;
        this.sound.playBounce();
      }

      const bx = b.x * w;
      const by = b.y * h;
      const br = Math.min(w, h) * b.r;

      if (b.bounceCooldown <= 0) {
        for (const tg of targets) {
          const dist = Math.hypot(tg.x - bx, tg.y - by);
          if (dist < br * 1.45 * hMult) {
            // 오프센터 타격 위치에 따른 방향 & 스핀 부여!
            const offsetX = (bx - tg.x) / Math.max(36, br);
            b.vy = -(isBeach ? 0.62 : 0.54) * spd + Math.min(0, (tg.vy || 0) * 0.00022);
            b.vx = offsetX * 0.32 + (tg.vx || 0) * 0.00028;
            b.vx = Math.max(-0.52, Math.min(0.52, b.vx));
            b.vrot = offsetX * 5.5 + (tg.vx || 0) * 0.004;
            b.squash = 1.0;
            b.bounceCooldown = 0.24;

            const comboBonus = this.combo >= 5 ? 1 : 0;
            const gained = (b.points || 1) + comboBonus;
            this.score += gained;
            this.registerCombo(bx, by);
            this.hooks.onScore(this.score);
            this.hooks.onProgress(Math.min(10, Math.floor((this.score / this.rallyTarget) * 10)), 10);

            const fxCol = b.golden ? "#FFB703" : isBeach ? "#38BDF8" : "#FF5C70";
            const fxHex = b.golden ? 0xffd43b : isBeach ? 0x38bdf8 : 0xff5c70;
            this.sound.playBalloonHit(this.combo, b.golden, isBeach);
            const hitText = b.golden ? `황금 통! +${gained}` : isBeach ? `스핀 통! +${gained}` : `통! +${gained}`;
            this.spawnBalloonVfx(bx, by, fxCol, fxHex, hitText, b.golden ? 2 : 1);

            // 25점 달성: 3D 웃는 무지개 비치볼 (+2점) 추가!
            if (!this.beachBallSpawned && this.score >= 25) {
              this.beachBallSpawned = true;
              this.sound.playFeverStart();
              this.balls.push({
                uid: this.uidSeq++,
                kind: "balloon_beach",
                x: 0.28,
                y: 0.16,
                vx: 0.16 * spd,
                vy: 0.02,
                r: 0.10,
                rot: 0,
                vrot: 2.2,
                squash: 0.4,
                golden: false,
                points: 2,
                bounceCooldown: 0.3,
                driftSeed: Math.random() * 6.28,
              });
              this.hooks.onCallout("웃는 비치볼 등장! (+2점!)", 3200);
            }

            // 60점 달성: 왕관 황금 별 풍선 (+3점) 추가 + 피버!
            if (!this.goldBallSpawned && this.score >= 60) {
              this.goldBallSpawned = true;
              this.feverActive = true;
              this.sound.playFeverStart();
              this.sound.setBgmRate(1.06);
              this.balls.push({
                uid: this.uidSeq++,
                kind: "balloon_gold",
                x: 0.72,
                y: 0.16,
                vx: -0.15 * spd,
                vy: 0.02,
                r: 0.105,
                rot: 0,
                vrot: 0,
                squash: 0.4,
                golden: true,
                points: 3,
                bounceCooldown: 0.3,
                driftSeed: Math.random() * 6.28,
              });
              this.hooks.onCallout("황금 왕관 풍선 추가! 3개 풍선 대파티!", 3400);
            }

            // 50 / 100 / 150점 마일스톤 폭죽 & 템포 업!
            if (this.nextMilestone < this.rallyTarget && this.score >= this.nextMilestone) {
              const ms = this.nextMilestone;
              this.nextMilestone += 50;
              this.sound.playMilestone();
              this.spawnConfetti(w, 45);
              this.screenFlash = 0.35;
              this.screenFlashHex = 0xffe875;
              this.sound.setBgmRate(ms >= 150 ? 1.15 : ms >= 100 ? 1.10 : 1.05);
              const msMsg = ms === 150 ? "150점 돌파! 200점까지 조금만 더!!" : `${ms}점 돌파! 슈퍼 피버!!`;
              this.hooks.onCallout(msMsg, 3000);
            }

            if (this.score >= this.rallyTarget) {
              this.feverActive = false;
              this.spawnConfetti(w, 140);
              this.finishGame(`풍선 3종으로 무려 ⭐ ${this.score}점 200점 대성공!`);
            }
            break;
          }
        }
      }
    });

    // 3) 풍선끼리 부딪히면 퉁! 튕겨 나가는 탄성 충돌 물리!
    for (let i = 0; i < this.balls.length; i++) {
      for (let j = i + 1; j < this.balls.length; j++) {
        const a = this.balls[i];
        const b = this.balls[j];
        const ax = a.x * w, ay = a.y * h;
        const bx = b.x * w, by = b.y * h;
        const dx = bx - ax, dy = by - ay;
        const dist = Math.hypot(dx, dy);
        const minDist = (a.r + b.r) * Math.min(w, h) * 0.95;
        if (dist > 0.01 && dist < minDist) {
          const nx = dx / dist, ny = dy / dist;
          const overlap = (minDist - dist) * 0.5;
          a.x -= (nx * overlap) / w; a.y -= (ny * overlap) / h;
          b.x += (nx * overlap) / w; b.y += (ny * overlap) / h;
          const rvx = (b.vx - a.vx) * w, rvy = (b.vy - a.vy) * h;
          const vn = rvx * nx + rvy * ny;
          if (vn < 0) {
            const imp = -(1 + 0.88) * vn * 0.5;
            a.vx -= (imp * nx) / w; a.vy -= (imp * ny) / h;
            b.vx += (imp * nx) / w; b.vy += (imp * ny) / h;
            a.squash = 0.65; b.squash = 0.65;
            this.sound.playBounce();
          }
        }
      }
    }
  }

  /* ------------------------------------------------------------------
   * GAME 3: 네온 클럽 얼음 땡! (128 BPM 디스코 파티 + DJ 스크래치 + 실시간 움직임 감지 페널티)
   * ------------------------------------------------------------------ */
  updateFreeze(dt, players, w, h) {
    const rawMotion = players.reduce((acc, p) => acc + (p.motion || 0), 0);
    const avgMotion = rawMotion / Math.max(1, players.length);
    this.emaMotion = 0.3 * avgMotion + 0.7 * this.emaMotion;
    this.phaseTimer -= dt;

    if (this.phase === "dance") {
      this.isWiggling = false;
      this.freezeWiggleTime = 0;
      this.freezeElapsed = 0;
      if (this.emaMotion > 0.015) {
        this.danceEnergy = Math.min(1, this.danceEnergy + dt * 1.15);
      } else {
        this.danceEnergy = Math.max(0.25, this.danceEnergy - dt * 0.45);
      }
      if (this.phaseTimer <= 0) {
        const freezeDurs = [3.4, 3.8, 4.2, 4.6, 4.8];
        this.freezeDuration = freezeDurs[Math.min(this.round, freezeDurs.length - 1)];
        this.phase = "freeze";
        this.phaseTimer = this.freezeDuration;
        this.freezeElapsed = 0;
        this.freezeHold = 0;
        this.freezeWiggleTime = 0;
        this.wiggleSfxCooldown = 0;
        this.isWiggling = false;
        this.screenFlash = 0.45;
        this.screenFlashHex = 0x38bdf8;
        this.screenShake = 0.55;
        this.sound.pauseBgm();
        this.sound.playFreezeCue();
        const isLast = this.round === this.roundsTotal - 1;
        this.hooks.onCallout(isLast ? "마지막! 만세하고 얼음!!" : "얼음!! 조명 정지! 움직이지 마세요!", 2600);
      }
    } else {
      this.freezeElapsed = (this.freezeElapsed || 0) + dt;
      this.wiggleSfxCooldown = Math.max(0, (this.wiggleSfxCooldown || 0) - dt);
      const threshold = this.settings.speed === "slow" ? 0.055 : this.settings.speed === "fast" ? 0.028 : 0.038;

      // 0.55초 반응 유예 시간 후 움직임 정밀 감지!
      if (this.freezeElapsed > 0.55) {
        if (this.emaMotion > threshold) {
          this.isWiggling = true;
          this.freezeWiggleTime = (this.freezeWiggleTime || 0) + dt;
          this.screenShake = Math.max(this.screenShake, 0.32);
          if (this.wiggleSfxCooldown <= 0) {
            this.wiggleSfxCooldown = 0.48;
            this.sound.playFreezeWiggle();
            this.spawnBurst(w * 0.5, h * 0.34, "#FF4757", 0xff4757, "움찔!! 멈춰요!!", 1);
          }
        } else {
          this.isWiggling = false;
          this.freezeHold += dt;
        }
      } else {
        this.isWiggling = false;
      }

      if (this.phaseTimer <= 0) {
        this.round++;
        const wiggle = this.freezeWiggleTime || 0;
        if (wiggle >= 0.48) {
          // 움직여서 들킴! (페널티: +0점 + 부저음 + 빨간 플래시)
          this.sound.playFreezeFail();
          this.screenFlash = 0.45;
          this.screenFlashHex = 0xff4757;
          this.screenShake = 0.7;
          this.spawnBurst(w * 0.5, h * 0.46, "#FF4757", 0xff4757, "움직여서 들켰어요! +0", 2);
        } else if (wiggle >= 0.14) {
          // 조금 움찔했지만 아슬아슬 세이프!
          this.freezeSuccessCount = (this.freezeSuccessCount || 0) + 1;
          this.score += 2;
          this.sound.playBounce();
          this.spawnBurst(w * 0.5, h * 0.46, "#FFD43B", 0xffd43b, "아슬아슬 세이프! +2", 2);
        } else {
          // 완벽 얼음!
          this.freezeSuccessCount = (this.freezeSuccessCount || 0) + 1;
          this.score += 5;
          this.sound.playDiscoClear();
          this.spawnBurst(w * 0.5, h * 0.46, "#FF2D95", 0xff2d95, "완벽 얼음!! +5", 2);
        }
        this.hooks.onScore(this.score);
        this.hooks.onProgress(this.round, this.roundsTotal);
        this.isWiggling = false;

        if (this.round >= this.roundsTotal) {
          const okCount = this.freezeSuccessCount || 0;
          this.sound.playClubAirhorn();
          this.spawnConfetti(w, 130);
          this.finishGame(`네온 클럽 5라운드 중 ${okCount}번 얼음 성공! ⭐ ${this.score}점!`);
        } else {
          this.phase = "dance";
          // 여유로운 6.8~9.0초 랜덤 댄스 타임 -> 전체 약 1분 구성!
          this.phaseTimer = 6.8 + Math.random() * 2.2;
          this.danceEnergy = 0.55;
          this.screenFlash = 0.42;
          this.screenFlashHex = 0xff2d95;
          this.sound.playClubAirhorn();
          const joinMsg =
            this.round === 1
              ? "디스코 모모 합류!! 둘이 함께 신나게 춤춰요!!"
              : this.round === 3
              ? "디스코 포포 합류!! 3마리 완전체 클럽 떼춤!!"
              : wiggle >= 0.48
              ? "다음엔 꽁꽁! 땡!! 다시 신나게 흔들어요!!"
              : "땡!! 디스코 타임! 신나게 흔들어요!!";
          this.hooks.onCallout(joinMsg, 2600);
          this.sound.setBgmRate(Math.min(1.18, 1.0 + this.round * 0.04));
          this.sound.resumeBgm();
        }
      }
    }
  }

  /* ------------------------------------------------------------------
   * GAME 4: 동물 흉내 포즈 따라하기 (14관절 전신 체형 정규화 판정 + 7종 릴레이)
   * ------------------------------------------------------------------ */
  checkSinglePlayerAnimalPose(p, animalId) {
    if (!p) return false;
    const m = p.metrics;
    // 개발자(마우스) 테스트 모드 폴백: 마우스 위치로 포즈 시뮬레이션
    if (!m) {
      const hy = Math.min(p.leftHand.y, p.rightHand.y);
      if (animalId === "giraffe" || animalId === "starfish") return hy < 0.34;
      if (animalId === "frog") return hy > 0.66;
      return hy < 0.56;
    }

    const headY = p.head.y;
    const shY = m.shoulderY;
    const th = m.torsoH;
    const sw = m.shoulderW;
    const lH = p.leftHand;
    const rH = p.rightHand;
    const bothUp = lH.y < headY + th * 0.08 && rH.y < headY + th * 0.08;
    const bothAboveShoulder = lH.y < shY - th * 0.05 && rH.y < shY - th * 0.05;

    switch (animalId) {
      case "giraffe":
        return bothUp && Math.max(m.lElbowAngle, m.rElbowAngle) > 115;
      case "eagle":
        return (
          m.wristSpan > sw * 1.75 &&
          Math.abs(lH.y - shY) < th * 0.55 &&
          Math.abs(rH.y - shY) < th * 0.55
        );
      case "crab": {
        const lEl = p.elbows?.[0];
        const rEl = p.elbows?.[1];
        const handsAboveElbows = lEl && rEl ? lH.y < lEl.y && rH.y < rEl.y : bothAboveShoulder;
        const elbowsBent = m.lElbowAngle < 135 && m.rElbowAngle < 135;
        return handsAboveElbows && elbowsBent && m.wristSpan > sw * 1.15;
      }
      case "flamingo":
        return (
          m.footLift > th * 0.22 ||
          (!m.lowerVisible && m.wristSpan > sw * 1.65 && m.torsoLean > 0.12)
        );
      case "frog":
        return m.isSquatting || (lH.y > m.hipY - th * 0.1 && rH.y > m.hipY - th * 0.1 && p.head.y > 0.52);
      case "elephant": {
        const bothSameSide =
          (lH.x < p.centerX - sw * 0.2 && rH.x < p.centerX + sw * 0.3) ||
          (lH.x > p.centerX - sw * 0.3 && rH.x > p.centerX + sw * 0.2);
        return m.torsoLean > 0.14 || bothSameSide;
      }
      case "starfish":
        return (bothAboveShoulder || m.wristSpan > sw * 1.7) && (m.ankleSpan > sw * 1.15 || bothUp);
      default:
        return bothUp;
    }
  }

  updateAnimalPose(dt, players, w, h) {
    if (this.animalPause > 0) {
      this.animalPause -= dt;
      return;
    }
    const cur = ANIMAL_POSES[this.animalIndex];
    if (!cur) return;

    this.animalTimer = Math.max(0, this.animalTimer - dt);

    let matchCount = 0;
    for (const p of players) {
      if (this.checkSinglePlayerAnimalPose(p, cur.id)) matchCount++;
    }
    this.animalMatch = matchCount > 0;

    if (this.animalMatch) {
      this.animalGraceTimer = 0.15; // 4-6세 아이의 미세 흔들림에도 0.15초 관대 유예!
      // 2인 모드에서 둘 다 성공하면 1.35배속 슈퍼 게이지!
      const boost = matchCount >= 2 ? 1.35 : 1.0;
      const prevStep = Math.floor((this.animalHold / this.animalHoldTarget) * 3);
      this.animalHold = Math.min(this.animalHoldTarget, this.animalHold + dt * boost);
      const nextStep = Math.floor((this.animalHold / this.animalHoldTarget) * 3);
      if (nextStep > prevStep && nextStep < 3) {
        this.sound.playClick();
      }
    } else if ((this.animalGraceTimer || 0) > 0) {
      this.animalGraceTimer = Math.max(0, this.animalGraceTimer - dt);
    } else {
      this.animalHold = Math.max(0, this.animalHold - dt * 0.45);
    }

    const cleared = this.animalHold >= this.animalHoldTarget;
    const timedOut = this.animalTimer <= 0;

    if (cleared || timedOut) {
      if (cleared) {
        this.animalCleared[this.animalIndex] = true;
        this.animalSuccessCount++;
        this.score += 10;
        this.sound.playGoldenPop();
        this.screenFlash = 0.36;
        this.screenFlashHex = cur.hex;
        this.spawnBurst(w * 0.5, h * 0.45, cur.color, cur.hex, `${cur.name} 완벽 변신! +10`, 2);
      } else {
        this.score += 2;
        this.sound.playBounce();
        this.spawnBurst(w * 0.5, h * 0.45, "#94A3B8", 0x94a3b8, "아쉬워요! 다음 동물 도전! +2", 1);
      }
      this.hooks.onScore(this.score);
      this.animalIndex++;
      this.hooks.onProgress(this.animalIndex, ANIMAL_POSES.length);

      if (this.animalIndex >= ANIMAL_POSES.length) {
        this.spawnConfetti(w, 140);
        this.finishGame(`동물 7종 중 ${this.animalSuccessCount}마리 완벽 변신! ⭐ ${this.score}점!`);
      } else {
        const next = ANIMAL_POSES[this.animalIndex];
        this.animalTimer = this.animalTimeLimit;
        this.animalHold = 0;
        this.animalMatch = false;
        this.animalGraceTimer = 0;
        this.animalPause = 0.85;
        this.hooks.onCallout(`${next.name}! ${next.cue}`, 2800);
      }
    }
  }

  /* ------------------------------------------------------------------
   * GAME 5: 달려라! 정글 모험 (60초, 5체크포인트 — 달리기 · 웅크리기 · 점프 만세!)
   * ------------------------------------------------------------------ */
  startJunglePhase(phase, w, h) {
    this.junglePhase = phase;
    this.junglePhaseProgress = 0;
    this.jungleActiveDetected = false;
    this.junglePhaseTransitionDelay = 0;
    this.jungleSquatCleared = false;
    this.jungleStars = [];
    this.jungleJumpWaveCd = 0;

    if (phase === "run") {
      this.junglePhaseTimer = 5.4;
      this.jungleVineY = -0.28;
      this.hooks.onCallout("🏃 제자리 달리기! 무릎을 번갈아 톡톡!!", 2200);
    } else if (phase === "squat") {
      this.junglePhaseTimer = 6.2;
      this.jungleVineY = -0.18;
      this.sound.playWindWhoosh();
      this.hooks.onCallout("🌿 숙여요! 웅크리기(스쿼트)로 덩굴 통과!!", 2600);
    } else if (phase === "jump") {
      this.junglePhaseTimer = 6.4;
      this.jungleVineY = -0.28;
      const xs = [0.22, 0.40, 0.60, 0.78];
      this.jungleStars = xs.map((nx, i) => ({
        uid: this.uidSeq++,
        x: nx,
        y: i % 2 === 0 ? 0.20 : 0.26,
        baseY: i % 2 === 0 ? 0.20 : 0.26,
        r: 0.068,
        collected: false,
        seed: i * 1.4,
      }));
      this.hooks.onCallout("⭐ 점프 만세! 머리 위 반짝별을 터뜨려요!!", 2600);
    }
  }

  advanceJunglePhase(w, h) {
    this.junglePhaseIdx = (this.junglePhaseIdx + 1) % this.junglePhaseSeq.length;
    this.startJunglePhase(this.junglePhaseSeq[this.junglePhaseIdx], w, h);
  }

  updateJungle(dt, players, hands, w, h) {
    const spd = SPEED_MULT[this.settings.speed] || 1.0;
    const hMult = HITBOX_MULT[this.settings.speed] || 1.16;

    this.jungleElapsed += dt;
    if (this.jungleElapsed >= this.jungleDuration) {
      this.jungleTrackProgress = 1;
      this.jungleCheckpoints = 5;
      this.hooks.onProgress(5, 5);
      this.spawnConfetti(w, 140);
      this.finishGame(`정글 모험 5개 체크포인트 완주!! ⭐ ${this.score}점 대모험 성공!`);
      return;
    }

    // Track baseline head height smoothly during run phase for jump detection
    players.forEach((p, idx) => {
      if (this.junglePhase === "run" && p.head) {
        this.jungleBaselineHeadY[idx] = (this.jungleBaselineHeadY[idx] || p.head.y) * 0.94 + p.head.y * 0.06;
      }
    });

    // Check 5 jungle checkpoints along the top progress track
    const reachedCp = Math.min(5, Math.floor(this.jungleTrackProgress * 5 + 0.001));
    if (reachedCp > this.jungleCheckpoints) {
      this.jungleCheckpoints = reachedCp;
      this.hooks.onProgress(this.jungleCheckpoints, 5);
      this.score += 5;
      this.hooks.onScore(this.score);
      this.sound.playMilestone();
      this.screenFlash = 0.28;
      this.screenFlashHex = 0x22ff88;
      this.spawnBurst(w * 0.5, h * 0.26, "#22C55E", 0x22ff88, `🏁 체크포인트 ${reachedCp}/5 통과! +5`, 2);
      if (reachedCp >= 4) {
        this.feverActive = true;
        this.sound.setBgmRate(1.1);
      }
    }

    if (this.junglePhaseTransitionDelay > 0) {
      this.junglePhaseTransitionDelay -= dt;
      if (this.junglePhaseTransitionDelay <= 0) {
        this.advanceJunglePhase(w, h);
      }
      return;
    }

    this.junglePhaseTimer -= dt;

    if (this.junglePhase === "run") {
      let runners = 0;
      players.forEach((p, idx) => {
        const knL = p.knees?.[0];
        const knR = p.knees?.[1];
        const kneeDiff = knL && knR ? knL.y - knR.y : 0;
        const prevDiff = this.junglePrevKneeDiff[idx] || 0;
        this.junglePrevKneeDiff[idx] = kneeDiff;
        const altKnee = Math.abs(kneeDiff - prevDiff) > 0.012;
        const activeMotion = (p.motion || 0) > 0.025 || altKnee;
        if (activeMotion) runners++;
      });

      this.jungleActiveDetected = runners > 0;
      if (runners > 0) {
        const boost = runners >= 2 ? 1.35 : 1.0;
        this.junglePhaseProgress = Math.min(1, this.junglePhaseProgress + dt * 0.27 * boost * spd);
        this.jungleTrackProgress = Math.min(1, this.jungleTrackProgress + dt * 0.028 * boost);
        this.jungleRunTick += dt * boost;
        if (this.jungleRunTick >= 0.62) {
          this.jungleRunTick = 0;
          this.score += 1;
          this.hooks.onScore(this.score);
          this.sound.playPop(this.combo);
          this.spawnBurst(w * (0.35 + Math.random() * 0.3), h * 0.72, "#22C55E", 0x38ef7d, "달려! +1", 1);
        }
      } else {
        // Gentle baseline progress so young toddlers never get stuck
        this.jungleTrackProgress = Math.min(1, this.jungleTrackProgress + dt * 0.006);
      }

      if (this.junglePhaseProgress >= 1 || this.junglePhaseTimer <= 0) {
        this.advanceJunglePhase(w, h);
      }
    } else if (this.junglePhase === "squat") {
      // Smoothly lower the lush 3D clay jungle vine across upper-mid screen
      const targetVineY = this.jungleSquatCleared ? -0.22 : 0.36;
      this.jungleVineY += (targetVineY - this.jungleVineY) * Math.min(1, dt * 4.5);

      let squatters = 0;
      players.forEach((p) => {
        const isLow = Boolean(p.metrics?.isSquatting) || (p.head && p.head.y > 0.56);
        if (isLow) squatters++;
      });
      this.jungleActiveDetected = squatters > 0;

      if (squatters > 0 && !this.jungleSquatCleared) {
        const boost = squatters >= 2 ? 1.35 : 1.0;
        const prevStep = Math.floor(this.junglePhaseProgress * 3);
        this.junglePhaseProgress = Math.min(1, this.junglePhaseProgress + (dt / 1.25) * boost);
        const nextStep = Math.floor(this.junglePhaseProgress * 3);
        if (nextStep > prevStep && nextStep < 3) this.sound.playClick();

        if (this.junglePhaseProgress >= 1) {
          this.jungleSquatCleared = true;
          this.score += 8;
          this.hooks.onScore(this.score);
          this.jungleTrackProgress = Math.min(1, this.jungleTrackProgress + 0.09);
          this.registerCombo(w * 0.5, h * 0.42);
          this.sound.playJumpStar(this.combo);
          this.screenFlash = 0.32;
          this.screenFlashHex = 0x22ff88;
          this.spawnBurst(w * 0.5, h * 0.42, "#22C55E", 0x22ff88, "덩굴 쏙 통과!! +8", 2);
          this.junglePhaseTransitionDelay = 0.72;
        }
      } else if (!this.jungleSquatCleared) {
        this.junglePhaseProgress = Math.max(0, this.junglePhaseProgress - dt * 0.35);
      }

      if (!this.jungleSquatCleared && this.junglePhaseTimer <= 0) {
        this.score += 2;
        this.hooks.onScore(this.score);
        this.jungleTrackProgress = Math.min(1, this.jungleTrackProgress + 0.04);
        this.sound.playBounce();
        this.spawnBurst(w * 0.5, h * 0.42, "#FFD43B", 0xffd43b, "잘했어요! 계속 달려요! +2", 1);
        this.advanceJunglePhase(w, h);
      }
    } else if (this.junglePhase === "jump") {
      this.jungleJumpWaveCd = Math.max(0, this.jungleJumpWaveCd - dt);
      let anyJumping = false;

      // 1) Direct hand touch on overhead stars + 2) Both-hands-up jump wave smash!
      players.forEach((p, idx) => {
        const shY = p.metrics?.shoulderY ?? p.centerY ?? 0.46;
        const headY = p.head?.y ?? 0.38;
        const bothHandsUp = p.leftHand.y < shY - 0.06 && p.rightHand.y < shY - 0.06;
        const baseY = this.jungleBaselineHeadY[idx] || 0.42;
        const headRises = headY < baseY - 0.028 || Math.min(p.leftHand.y, p.rightHand.y) < 0.29;
        if (bothHandsUp && headRises) anyJumping = true;
      });
      this.jungleActiveDetected = anyJumping;

      const smashStar = (st) => {
        st.collected = true;
        const sx = st.x * w;
        const sy = st.y * h;
        this.score += 5;
        this.hooks.onScore(this.score);
        this.jungleTrackProgress = Math.min(1, this.jungleTrackProgress + 0.025);
        this.registerCombo(sx, sy);
        this.sound.playJumpStar(this.combo);
        this.spawnBurst(sx, sy, "#FFB703", 0xffd43b, "점프 별 팡! +5", 2);
      };

      this.jungleStars.forEach((st) => {
        if (st.collected) return;
        st.y = st.baseY + Math.sin(this.elapsed * 3.8 + st.seed) * 0.025;
        const sx = st.x * w;
        const sy = st.y * h;
        const sr = Math.min(w, h) * st.r;
        for (const hd of hands) {
          if (Math.hypot(hd.x - sx, hd.y - sy) < sr * 1.65 * hMult) {
            smashStar(st);
            break;
          }
        }
      });

      if (anyJumping && this.jungleJumpWaveCd <= 0) {
        const remaining = this.jungleStars.filter((s) => !s.collected);
        if (remaining.length > 0) {
          smashStar(remaining[0]);
          this.jungleJumpWaveCd = 0.34;
        }
      }

      const collected = this.jungleStars.filter((s) => s.collected).length;
      const total = Math.max(1, this.jungleStars.length);
      this.junglePhaseProgress = collected / total;

      if (collected >= total) {
        this.jungleTrackProgress = Math.min(1, this.jungleTrackProgress + 0.04);
        this.screenFlash = 0.28;
        this.screenFlashHex = 0xffe875;
        this.junglePhaseTransitionDelay = 0.62;
      } else if (this.junglePhaseTimer <= 0) {
        this.advanceJunglePhase(w, h);
      }
    }
  }

  /* ------------------------------------------------------------------
   * GAME 6: 두더지 손·발 하이파이브 (60초 — 상단 3구멍 손 하이파이브 + 하단 3구멍 발차기/숙여 터치 + 40초 피버!)
   * ------------------------------------------------------------------ */
  updateMole(dt, players, hands, w, h) {
    const spd = SPEED_MULT[this.settings.speed] || 1.0;
    const hMult = HITBOX_MULT[this.settings.speed] || 1.16;

    this.moleElapsed += dt;
    this.hooks.onProgress(Math.min(6, Math.floor((this.moleElapsed / this.moleDuration) * 6)), 6);

    if (!this.moleFeverTriggered && this.moleElapsed >= 40.0) {
      this.moleFeverTriggered = true;
      this.feverActive = true;
      this.sound.playFeverStart();
      this.sound.setBgmRate(1.14);
      this.screenFlash = 0.4;
      this.screenFlashHex = 0xffd43b;
      this.hooks.onCallout("🔥 40초 피버 웨이브!! 두더지 대파티!!", 3200);
    }

    if (this.moleElapsed >= this.moleDuration) {
      this.feverActive = false;
      this.spawnConfetti(w, 140);
      this.finishGame(`두더지 손·발 하이파이브 ⭐ ${this.score}점 대성공!`);
      return;
    }

    // Spawn moles into idle holes (balanced top/bottom rows)
    const isFever = this.moleFeverTriggered;
    const maxActive = isFever ? 4 : this.settings.players === 2 ? 3 : 2;
    const activeCount = this.moleHoles.filter((hl) => hl.state !== "idle").length;

    this.moleSpawnTimer -= dt;
    if (this.moleSpawnTimer <= 0 && activeCount < maxActive) {
      const wantRow = Math.random() < 0.65 ? this.moleNextRow : this.moleNextRow === "top" ? "bottom" : "top";
      let candidates = this.moleHoles.filter((hl) => hl.state === "idle" && hl.cooldown <= 0 && hl.row === wantRow);
      if (!candidates.length) {
        candidates = this.moleHoles.filter((hl) => hl.state === "idle" && hl.cooldown <= 0);
      }
      if (candidates.length > 0) {
        const pick = candidates[Math.floor(Math.random() * candidates.length)];
        const isGold = Math.random() < (isFever ? 0.34 : 0.24);
        pick.state = "rising";
        pick.pop = 0;
        pick.golden = isGold;
        pick.kind = isGold ? "mole_gold" : "mole_cute";
        pick.holdTimer = (isGold ? 2.4 : 3.0) / spd;
        pick.bonkTimer = 0;
        this.moleNextRow = pick.row === "top" ? "bottom" : "top";
      }
      this.moleSpawnTimer = (isFever ? 0.42 : 0.86) / spd;
    }

    // Build hit points: upper row uses HANDS; lower row uses FEET (ankles + knees) OR crouching HANDS!
    const lowerTargets = [];
    players.forEach((p, idx) => {
      const col = idx === 0 ? "#4AD3C8" : "#FF7D89";
      (p.ankles || []).forEach((a) => {
        if (a && (a.v ?? 1) > 0.2) lowerTargets.push({ x: a.x * w, y: a.y * h, isFoot: true, player: idx, color: col });
      });
      (p.knees || []).forEach((k) => {
        if (k && (k.v ?? 1) > 0.25) lowerTargets.push({ x: k.x * w, y: k.y * h, isFoot: true, player: idx, color: col });
      });
    });
    hands.forEach((hd) => {
      lowerTargets.push({ x: hd.x, y: hd.y, isFoot: false, player: hd.player, color: hd.color });
    });

    const holeR = Math.min(w, h) * 0.095;

    this.moleHoles.forEach((hl) => {
      hl.cooldown = Math.max(0, hl.cooldown - dt);

      if (hl.state === "rising") {
        hl.pop = Math.min(1, hl.pop + dt * 4.4);
        if (hl.pop >= 1) hl.state = "up";
      } else if (hl.state === "up") {
        hl.holdTimer -= dt;
        if (hl.holdTimer <= 0) hl.state = "hiding";
      } else if (hl.state === "bonked") {
        hl.bonkTimer -= dt;
        hl.pop = Math.max(0, hl.pop - dt * 2.2);
        if (hl.bonkTimer <= 0) {
          hl.state = "idle";
          hl.pop = 0;
          hl.cooldown = isFever ? 0.35 : 0.7;
        }
      } else if (hl.state === "hiding") {
        hl.pop = Math.max(0, hl.pop - dt * 3.8);
        if (hl.pop <= 0) {
          hl.state = "idle";
          hl.cooldown = isFever ? 0.3 : 0.65;
        }
      }

      // Hit check when mole is popped up enough
      if ((hl.state === "rising" || hl.state === "up") && hl.pop > 0.35) {
        const mx = hl.x * w;
        const my = hl.y * h - holeR * 0.38 * hl.pop;
        const hitPool = hl.row === "top" ? hands : lowerTargets;

        for (const tg of hitPool) {
          const dist = Math.hypot(tg.x - mx, tg.y - my);
          if (dist < holeR * 1.48 * hMult) {
            hl.state = "bonked";
            hl.bonkTimer = 0.36;
            const basePts = hl.golden ? 5 : 2;
            const comboBonus = this.combo >= 8 ? 2 : this.combo >= 4 ? 1 : 0;
            const gained = basePts + comboBonus;
            this.score += gained;
            this.hooks.onScore(this.score);
            this.registerCombo(mx, my);
            this.sound.playMoleBonk(this.combo);
            if (hl.golden) this.sound.playGoldenPop();

            const fxCol = hl.golden ? "#FFB703" : hl.row === "top" ? "#38BDF8" : "#22C55E";
            const fxHex = hl.golden ? 0xffd43b : hl.row === "top" ? 0x38bdf8 : 0x22ff88;
            const msg = hl.golden
              ? `황금 두더지!! +${gained}`
              : hl.row === "top"
              ? `하이파이브! +${gained}`
              : tg.isFoot
              ? `발차기 팡! +${gained}`
              : `터치 팡! +${gained}`;
            this.spawnBurst(mx, my, fxCol, fxHex, msg, hl.golden ? 2 : 1);
            break;
          }
        }
      }
    });
  }

  /* ------------------------------------------------------------------
   * GAME 7: 흔들흔들 외나무다리 균형잡기 (60초 — 바람 맞서 기울이기 + 넓은 팔 안정화 + 플라밍고 보너스 + 하늘 별잡기!)
   * ------------------------------------------------------------------ */
  updateBalance(dt, players, hands, w, h) {
    const spd = SPEED_MULT[this.settings.speed] || 1.0;
    const hMult = HITBOX_MULT[this.settings.speed] || 1.16;

    this.balanceElapsed += dt;
    this.hooks.onProgress(Math.min(6, Math.floor((this.balanceElapsed / this.balanceDuration) * 6)), 6);

    if (this.balanceElapsed >= this.balanceDuration) {
      this.feverActive = false;
      this.spawnConfetti(w, 140);
      this.finishGame(`외나무다리 균형잡기 완주!! ⭐ ${this.score}점 균형 마스터!`);
      return;
    }

    // 1) Playful Wind Gust Cycles
    this.windTimer -= dt;
    if (this.windTimer <= 0) {
      if (this.windActive) {
        this.windActive = false;
        this.windDir = 0;
        this.windTimer = 2.6 / spd;
      } else {
        this.windActive = true;
        this.windDir = Math.random() < 0.5 ? 1 : -1;
        this.windTimer = 4.6;
        this.sound.playWindWhoosh();
        const msg =
          this.windDir > 0
            ? "🌬️ 왼쪽 바람! 오른쪽으로 기울여요!"
            : "🌬️ 오른쪽 바람! 왼쪽으로 기울여요!";
        this.hooks.onCallout(msg, 3000);
      }
    }
    const targetWind = this.windActive ? 1.0 : 0.0;
    this.windStrength += (targetWind - this.windStrength) * Math.min(1, dt * 3.5);

    // 2) Occasional Flamingo One-Foot Bonus Challenge (~19s and ~43s)
    const flamingoMarks = [19, 43];
    flamingoMarks.forEach((mark, i) => {
      if (!this.flamingoTriggered[i] && this.balanceElapsed >= mark) {
        this.flamingoTriggered[i] = true;
        this.flamingoActive = true;
        this.flamingoTimer = 6.5;
        this.flamingoHold = 0;
        this.hooks.onCallout("🦩 한 발 들고 균형! 보너스 도전!!", 3000);
      }
    });

    if (this.flamingoActive) {
      this.flamingoTimer -= dt;
      const lifted = players.some((p) => {
        const m = p.metrics;
        if (!m) return false;
        return m.footLift > (m.torsoH || 0.2) * 0.17;
      });
      if (lifted) {
        this.flamingoHold = Math.min(this.flamingoHoldTarget, this.flamingoHold + dt);
        if (this.flamingoHold >= this.flamingoHoldTarget) {
          this.flamingoActive = false;
          this.score += 10;
          this.hooks.onScore(this.score);
          this.sound.playGoldenPop();
          this.screenFlash = 0.34;
          this.screenFlashHex = 0xf472b6;
          this.spawnBurst(w * 0.5, h * 0.45, "#EC4899", 0xf472b6, "🦩 한 발 균형 성공! +10", 2);
        }
      } else {
        this.flamingoHold = Math.max(0, this.flamingoHold - dt * 0.5);
      }
      if (this.flamingoTimer <= 0) {
        this.flamingoActive = false;
      }
    }

    // 3) Read player torso lean + shoulder tilt + wide airplane arms!
    let leanSum = 0;
    let wideCount = 0;
    players.forEach((p) => {
      const m = p.metrics;
      if (m) {
        const sLean = (m.signedTorsoLean ?? 0) * 1.45 + (m.shoulderTilt ?? 0) * 0.55;
        leanSum += Math.max(-1.0, Math.min(1.0, sLean));
        if (m.wristSpan > m.shoulderW * 1.4) wideCount++;
      }
    });
    const avgLean = players.length > 0 ? leanSum / players.length : 0;
    this.balanceWideArms = wideCount > 0;

    // 4) Realistic Bridge Tilt Physics (Wind pushes bridge; player lean & wide arms stabilize!)
    const windTorque = this.windActive
      ? -this.windDir * this.windStrength * 0.52 * spd
      : Math.sin(this.elapsed * 1.55) * 0.11;
    const playerTorque = avgLean * 0.72;
    const dampingSpring = -this.bridgeAngle * (this.balanceWideArms ? 2.5 : 1.5);
    this.bridgeVel += (windTorque + playerTorque + dampingSpring) * dt * 2.1;
    this.bridgeVel *= Math.exp(-3.5 * dt);
    this.bridgeAngle = Math.max(-0.42, Math.min(0.42, this.bridgeAngle + this.bridgeVel * dt));

    this.balanceInSafe = Math.abs(this.bridgeAngle) < 0.16;
    this.balanceWobbleCd = Math.max(0, this.balanceWobbleCd - dt);

    if (this.balanceInSafe) {
      const mult = (this.balanceWideArms ? 1.4 : 1.0) * (this.settings.players === 2 ? 1.15 : 1.0);
      this.balancePointAccum += dt * mult;
      this.balanceShowerAccum += dt;
      if (this.balancePointAccum >= 0.72) {
        this.balancePointAccum = 0;
        const pts = this.balanceWideArms ? 2 : 1;
        this.score += pts;
        this.hooks.onScore(this.score);
        if (this.balanceShowerAccum >= 1.5) {
          this.balanceShowerAccum = 0;
          this.sound.playPop(Math.min(6, Math.floor(this.balanceElapsed / 8)));
          this.spawnBurst(w * 0.5, h * 0.62, "#22C55E", 0x22ff88, this.balanceWideArms ? "비행기 균형! +2" : "균형 굿! +1", 1);
        }
      }
    } else if (Math.abs(this.bridgeAngle) > 0.32 && this.balanceWobbleCd <= 0) {
      this.balanceWobbleCd = 1.6;
      this.sound.playBounce();
      this.spawnBurst(w * 0.5, h * 0.60, "#FFB703", 0xffd43b, "어이쿠! 중심 잡아요!", 1);
    }

    // 5) Floating star_3d stars to catch while balancing!
    this.balanceStarSpawn -= dt;
    if (this.balanceStarSpawn <= 0 && this.balanceStars.length < 3) {
      this.balanceStarSpawn = 2.8 / spd;
      const fromLeft = Math.random() < 0.5;
      this.balanceStars.push({
        uid: this.uidSeq++,
        x: fromLeft ? 0.08 : 0.92,
        y: 0.28 + Math.random() * 0.20,
        vx: (fromLeft ? 1 : -1) * (0.09 + Math.random() * 0.05) * spd,
        r: 0.062,
        seed: Math.random() * 6.28,
      });
    }

    this.balanceStars = this.balanceStars.filter((st) => {
      st.x += st.vx * dt;
      const drawY = st.y + Math.sin(this.elapsed * 3.2 + st.seed) * 0.025;
      const sx = st.x * w;
      const sy = drawY * h;
      const sr = Math.min(w, h) * st.r;

      for (const hd of hands) {
        if (Math.hypot(hd.x - sx, hd.y - sy) < sr * 1.65 * hMult) {
          this.score += 3;
          this.hooks.onScore(this.score);
          this.registerCombo(sx, sy);
          this.sound.playJumpStar(this.combo);
          this.spawnBurst(sx, sy, "#FFB703", 0xffd43b, "하늘 별 캐치! +3", 2);
          return false;
        }
      }
      return st.x > -0.08 && st.x < 1.08;
    });
  }

  finishGame(summaryText) {
    if (this.finished) return;
    this.finished = true;
    this.feverActive = false;

    // 1) 부드러운 BGM 페이드아웃 + 황금 피날레 플래시 + 축하 콜아웃!
    this.sound.fadeOutBgm(1100);
    this.sound.playMilestone();
    this.screenFlash = 0.52;
    this.screenFlashHex = 0xffe875;
    this.hooks.onCallout("🎉 피니시!! 대성공!! 🎉", 2000);

    // 2) 게임별 피날레 마무리 모션!
    if (this.gameId === "fruit" && this.fruits.length > 0) {
      this.fruits.forEach((f) => {
        this.spawnSplatter(f.x, f.y, f.hexColor, 1.15);
        this.spawnSlicedHalves(f.kind, f.x, f.y, f.r, -0.4);
        this.spawnBurst(f.x, f.y, "#FFD43B", 0xffd43b, "팡!", 1);
      });
      this.fruits = [];
    } else if (this.gameId === "freeze") {
      // 얼음 땡!은 3마리 완전체 승리 댄스 상태로 전환해 축제를 이어감!
      this.phase = "dance";
      this.isWiggling = false;
      this.round = this.roundsTotal;
      this.danceEnergy = 0.9;
    }

    // 3) 1.85초간 생생한 피날레 축하 모션 후 통합 결과 팝업 부드럽게 표시!
    clearTimeout(this.finishTimerId);
    this.finishTimerId = setTimeout(() => {
      this.sound.playFanfare();
      this.hooks.onFinish(summaryText);
    }, 1850);
  }

  renderFallback2D(ctx, players, w, h) {
    const hands = this.hands || this.getAllHands(players, w, h);
    ctx.save();
    if (this.screenShake > 0.01) {
      ctx.translate((Math.random() - 0.5) * 14 * this.screenShake, (Math.random() - 0.5) * 10 * this.screenShake);
    }
    if (this.gameId === "fruit") {
      this.fruits.forEach((f) => {
        const sp = this.sprites[f.kind];
        if (sp && sp.complete && sp.naturalWidth > 0) {
          ctx.save();
          ctx.translate(f.x, f.y);
          ctx.rotate(f.rot);
          ctx.drawImage(sp, -f.r * 1.1, -f.r * 1.1, f.r * 2.2, f.r * 2.2);
          ctx.restore();
        }
      });
      if (this.boss) {
        const sp = this.sprites[this.boss.kind];
        if (sp && sp.complete) {
          const br = this.boss.r * (1 + 0.08 * this.boss.shake);
          ctx.drawImage(sp, this.boss.x - br, this.boss.y - br, br * 2, br * 2);
        }
      }
    }
    if (HAND_VFX_GAMES.has(this.gameId)) {
      hands.forEach((hd) => {
        ctx.beginPath();
        ctx.arc(hd.x, hd.y, 20, 0, Math.PI * 2);
        ctx.strokeStyle = hd.color;
        ctx.lineWidth = 3;
        ctx.stroke();
      });
    }
    ctx.restore();
  }
}
