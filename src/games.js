/**
 * Three Wii-style, 4-and-6-year-old friendly mini-games with 3D clay sprites,
 * iridescent rainbow hand swipe trails, star sparkles, and generous hitboxes.
 */

const SPEED_MULT = {
  slow: 0.72,
  normal: 1.0,
  fast: 1.28,
};

const HITBOX_MULT = {
  slow: 1.38,
  normal: 1.18,
  fast: 1.0,
};

const FRUITS = [
  { emoji: "🍓", color: "#FF4D6D" },
  { emoji: "🍊", color: "#FF9F1C" },
  { emoji: "🍎", color: "#EF476F" },
  { emoji: "🍌", color: "#FFD166" },
  { emoji: "🍇", color: "#9B5DE5" },
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
    this.trails = [[], [], [], []];
    this.particles = [];
    this.confetti = [];

    // Preload 3D clay sprites matching design mockups
    this.sprites = {
      watermelon: loadSprite("./assets/watermelon.png"),
      dino: loadSprite("./assets/card_freeze.jpg"),
      balloon: loadSprite("./assets/card_balloon.jpg"),
    };

    this.reset("fruit", this.settings);
  }

  reset(gameId, settings) {
    this.gameId = gameId;
    this.settings = { ...settings };
    this.score = 0;
    this.elapsed = 0;
    this.finished = false;
    this.particles = [];
    this.confetti = [];
    this.trails = [[], [], [], []];

    const spd = SPEED_MULT[settings.speed] || 1.0;

    if (gameId === "fruit") {
      this.targetCount = 8;
      this.fruits = [];
      this.spawnTimer = 0.35;
      this.boss = null;
      this.bossHits = 0;
      this.bossMaxHits = settings.players === 2 ? 8 : 5;
      this.bossHitCooldown = 0;
      this.hooks.onProgress(0, 7);
      this.hooks.onCallout("");
    } else if (gameId === "balloon") {
      this.rallyTarget = 10;
      this.ball = {
        x: 0.5,
        y: 0.25,
        vx: 0.14 * spd,
        vy: 0.05,
        r: 0.09,
        colorIdx: 0,
        bounceCooldown: 0,
      };
      this.hooks.onProgress(0, 5);
      this.hooks.onCallout("풍선을 바닥에 떨어뜨리지 마세요!");
      setTimeout(() => this.hooks.onCallout(""), 2200);
    } else if (gameId === "freeze") {
      this.roundsTotal = 4;
      this.round = 0;
      this.phase = "dance";
      this.phaseTimer = 4.2;
      this.danceEnergy = 0;
      this.freezeHold = 0;
      this.hooks.onProgress(0, this.roundsTotal);
      this.hooks.onCallout("🎵 신나게 흔들어 춤춰요!");
      this.sound.startBgm(330);
    }
    this.hooks.onScore(0);
  }

  stop() {
    this.sound.stopBgm();
  }

  spawnBurst(x, y, color, text = "팡!") {
    for (let i = 0; i < 14; i++) {
      const ang = (Math.PI * 2 * i) / 14 + Math.random() * 0.3;
      const spd = 120 + Math.random() * 210;
      this.particles.push({
        x,
        y,
        vx: Math.cos(ang) * spd,
        vy: Math.sin(ang) * spd - 40,
        life: 0.7,
        maxLife: 0.7,
        color,
        star: i % 2 === 0,
        size: 8 + Math.random() * 8,
      });
    }
    if (text) {
      this.particles.push({
        x,
        y: y - 12,
        vx: 0,
        vy: -78,
        life: 0.78,
        maxLife: 0.78,
        color,
        text,
      });
    }
  }

  spawnConfetti(w) {
    const cols = ["#FF5C70", "#FFD43B", "#48D1CC", "#60A5FA", "#C084FC"];
    for (let i = 0; i < 65; i++) {
      this.confetti.push({
        x: Math.random() * w,
        y: -20 - Math.random() * 260,
        vx: (Math.random() - 0.5) * 95,
        vy: 130 + Math.random() * 180,
        rot: Math.random() * Math.PI,
        vrot: (Math.random() - 0.5) * 8,
        color: cols[i % cols.length],
        size: 8 + Math.random() * 7,
      });
    }
  }

  getAllHands(players, w, h) {
    const hands = [];
    players.forEach((p, idx) => {
      const col = idx === 0 ? "#4AD3C8" : "#FF7D89";
      hands.push({ x: p.leftHand.x * w, y: p.leftHand.y * h, player: idx, color: col, slot: idx * 2 });
      hands.push({ x: p.rightHand.x * w, y: p.rightHand.y * h, player: idx, color: col, slot: idx * 2 + 1 });
    });
    return hands;
  }

  update(dt, players, w, h) {
    this.elapsed += dt;
    const hands = this.getAllHands(players, w, h);

    hands.forEach((hd) => {
      const tr = this.trails[hd.slot];
      if (tr) {
        tr.push({ x: hd.x, y: hd.y, color: hd.color, player: hd.player });
        if (tr.length > 11) tr.shift();
      }
    });

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

    if (this.finished) return;

    if (this.gameId === "fruit") this.updateFruit(dt, hands, w, h);
    else if (this.gameId === "balloon") this.updateBalloon(dt, players, hands, w, h);
    else if (this.gameId === "freeze") this.updateFreeze(dt, players, w, h);
  }

  updateFruit(dt, hands, w, h) {
    const spd = SPEED_MULT[this.settings.speed] || 1.0;
    const hMult = HITBOX_MULT[this.settings.speed] || 1.18;

    if (!this.boss) {
      this.spawnTimer -= dt;
      if (this.spawnTimer <= 0 && this.fruits.length < 4) {
        const meta = FRUITS[Math.floor(Math.random() * FRUITS.length)];
        const xNorm = 0.18 + Math.random() * 0.64;
        this.fruits.push({
          x: xNorm * w,
          y: h + 50,
          vx: (Math.random() - 0.5) * 45,
          vy: -(h * (0.43 + Math.random() * 0.13)) * spd,
          r: Math.min(w, h) * 0.075,
          emoji: meta.emoji,
          color: meta.color,
          wobble: Math.random() * Math.PI * 2,
        });
        this.spawnTimer = 1.0 / spd;
      }

      this.fruits = this.fruits.filter((f) => {
        f.wobble += dt * 3;
        f.x += (f.vx + Math.sin(f.wobble) * 28) * dt;
        f.y += f.vy * dt;
        f.vy += h * 0.24 * spd * dt;

        for (const hd of hands) {
          const dist = Math.hypot(hd.x - f.x, hd.y - f.y);
          if (dist < f.r * 1.48 * hMult) {
            this.score++;
            this.hooks.onScore(this.score);
            this.sound.playPop(this.score);
            this.spawnBurst(f.x, f.y, f.color, "팡! +1");
            const progress = Math.min(5, Math.floor((this.score / this.targetCount) * 5));
            this.hooks.onProgress(progress, 7);
            if (this.score >= this.targetCount && !this.boss) {
              this.spawnGiantWatermelon(w, h);
            }
            return false;
          }
        }
        return f.y < h + 120;
      });
    } else {
      this.boss.y += (h * 0.45 - this.boss.y) * Math.min(1, dt * 5.5);
      this.boss.shake = Math.max(0, this.boss.shake - dt * 4.2);
      this.bossHitCooldown = Math.max(0, this.bossHitCooldown - dt);

      if (this.bossHitCooldown <= 0) {
        for (const hd of hands) {
          const dist = Math.hypot(hd.x - this.boss.x, hd.y - this.boss.y);
          if (dist < this.boss.r * 1.42 * hMult) {
            this.bossHits++;
            this.boss.shake = 1.0;
            this.bossHitCooldown = 0.2;
            this.sound.playBossHit(this.bossHits);
            this.spawnBurst(hd.x, hd.y, "#FFD43B", "퍽!");
            this.hooks.onProgress(6, 7);

            if (this.bossHits >= this.bossMaxHits) {
              this.score += 5;
              this.hooks.onScore(this.score);
              this.hooks.onProgress(7, 7);
              this.sound.playBossSmash();
              this.spawnBurst(this.boss.x, this.boss.y, "#FF4D6D", "와르르! 대성공!!");
              this.spawnConfetti(w);
              this.boss = null;
              this.finishGame(`과일과 거대 수박을 함께 깨서 ⭐ ${this.score}점을 모았어요!`);
            }
            break;
          }
        }
      }
    }
  }

  spawnGiantWatermelon(w, h) {
    this.fruits = [];
    this.boss = {
      x: w * 0.5,
      y: -140,
      r: Math.min(w, h) * 0.19,
      shake: 0,
    };
    this.hooks.onCallout(
      this.settings.players === 2 ? "🍉 거대 수박 등장! 둘이 함께 흔들어 깨기!" : "🍉 거대 수박 등장! 힘껏 흔들어 깨기!"
    );
  }

  updateBalloon(dt, players, hands, w, h) {
    const spd = SPEED_MULT[this.settings.speed] || 1.0;
    const hMult = HITBOX_MULT[this.settings.speed] || 1.18;
    const b = this.ball;
    b.bounceCooldown = Math.max(0, b.bounceCooldown - dt);

    b.vy += 0.27 * spd * dt;
    b.x += b.vx * dt;
    b.y += b.vy * dt;

    if (b.x < 0.09) { b.x = 0.09; b.vx = Math.abs(b.vx); }
    if (b.x > 0.91) { b.x = 0.91; b.vx = -Math.abs(b.vx); }
    if (b.y < 0.1)  { b.y = 0.1;  b.vy = Math.abs(b.vy) * 0.5; }

    if (b.y > 0.88) {
      b.y = 0.88;
      b.vy = -0.35 * spd;
      this.sound.playBounce();
    }

    const bx = b.x * w;
    const by = b.y * h;
    const br = Math.min(w, h) * b.r;

    if (b.bounceCooldown <= 0) {
      const targets = [...hands];
      players.forEach((p, idx) => {
        targets.push({ x: p.head.x * w, y: p.head.y * h, player: idx, color: "#FFD43B" });
      });

      for (const tg of targets) {
        const dist = Math.hypot(tg.x - bx, tg.y - by);
        if (dist < br * 1.48 * hMult) {
          b.vy = -(0.46 + Math.random() * 0.08) * spd;
          b.vx = ((bx - tg.x) / Math.max(40, br)) * 0.24 + (Math.random() - 0.5) * 0.1;
          b.vx = Math.max(-0.34, Math.min(0.34, b.vx));
          b.colorIdx = (b.colorIdx + 1) % 5;
          b.bounceCooldown = 0.28;

          this.score++;
          this.hooks.onScore(this.score);
          this.hooks.onProgress(Math.min(5, Math.ceil((this.score / this.rallyTarget) * 5)), 5);
          this.sound.playPop(this.score);
          this.spawnBurst(bx, by, tg.color, "통! +1");

          if (this.score >= this.rallyTarget) {
            this.spawnConfetti(w);
            this.finishGame(`풍선을 ${this.score}번이나 신나게 넘겼어요!`);
          }
          break;
        }
      }
    }
  }

  updateFreeze(dt, players, w, h) {
    const totalMotion = players.reduce((acc, p) => acc + (p.motion || 0), 0);
    this.phaseTimer -= dt;

    if (this.phase === "dance") {
      if (totalMotion > 0.025) {
        this.danceEnergy = Math.min(1, this.danceEnergy + dt * 0.9);
      }
      if (this.phaseTimer <= 0) {
        this.phase = "freeze";
        this.phaseTimer = 2.8;
        this.freezeHold = 0;
        this.sound.stopBgm();
        this.sound.playFreezeCue();
        this.hooks.onCallout("🧊 얼음!! 움직이지 마세요!");
      }
    } else {
      const threshold = this.settings.speed === "slow" ? 0.14 : 0.095;
      if (totalMotion < threshold) {
        this.freezeHold += dt;
      }
      if (this.phaseTimer <= 0) {
        this.round++;
        this.score += 3;
        this.hooks.onScore(this.score);
        this.hooks.onProgress(this.round, this.roundsTotal);
        this.sound.playReadyOk();
        this.spawnBurst(w * 0.5, h * 0.4, "#48D1CC", "성공! +3");

        if (this.round >= this.roundsTotal) {
          this.spawnConfetti(w);
          this.finishGame("공룡 눈을 피해 얼음 땡 대성공!");
        } else {
          this.phase = "dance";
          this.phaseTimer = 4.0;
          this.danceEnergy = 0;
          this.hooks.onCallout("🎵 땡! 다시 신나게 흔들어요!");
          this.sound.startBgm(320);
        }
      }
    }
  }

  finishGame(summaryText) {
    if (this.finished) return;
    this.finished = true;
    this.sound.stopBgm();
    this.hooks.onCallout("");
    setTimeout(() => {
      this.sound.playFanfare();
      this.hooks.onFinish(summaryText);
    }, 550);
  }

  drawStarShape(ctx, cx, cy, rOuter, rInner, fill) {
    ctx.beginPath();
    for (let i = 0; i < 10; i++) {
      const r = i % 2 === 0 ? rOuter : rInner;
      const a = -Math.PI / 2 + (i * Math.PI) / 5;
      const x = cx + Math.cos(a) * r;
      const y = cy + Math.sin(a) * r;
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.closePath();
    ctx.fillStyle = fill;
    ctx.fill();
  }

  render(ctx, players, w, h) {
    const hands = this.getAllHands(players, w, h);

    // 1) Iridescent rainbow hand swipe ribbons (시안 4번 스타일)
    this.trails.forEach((tr) => {
      if (tr.length < 2) return;
      const isP1 = tr[0].player === 0;
      const bands = isP1
        ? [
            { col: "#5CEFE2", offset: -7, w: 12 },
            { col: "#FFF380", offset: 0, w: 9 },
            { col: "#A78BFA", offset: 7, w: 8 },
          ]
        : [
            { col: "#FF7D89", offset: -7, w: 12 },
            { col: "#FFE066", offset: 0, w: 9 },
            { col: "#FF9F5A", offset: 7, w: 8 },
          ];

      bands.forEach((band) => {
        for (let i = 1; i < tr.length; i++) {
          const ratio = i / tr.length;
          ctx.save();
          ctx.strokeStyle = band.col;
          ctx.globalAlpha = ratio * 0.72;
          ctx.lineWidth = Math.max(2, band.w * ratio);
          ctx.lineCap = "round";
          ctx.shadowColor = band.col;
          ctx.shadowBlur = 12;
          ctx.beginPath();
          ctx.moveTo(tr[i - 1].x, tr[i - 1].y + band.offset);
          ctx.lineTo(tr[i].x, tr[i].y + band.offset);
          ctx.stroke();
          ctx.restore();
        }
      });
    });

    // 2) Glowing double hand halos
    hands.forEach((hd) => {
      ctx.save();
      ctx.beginPath();
      ctx.arc(hd.x, hd.y, 26, 0, Math.PI * 2);
      ctx.fillStyle = hd.color + "38";
      ctx.fill();
      ctx.lineWidth = 3.5;
      ctx.strokeStyle = hd.color;
      ctx.shadowColor = hd.color;
      ctx.shadowBlur = 12;
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(hd.x, hd.y, 7, 0, Math.PI * 2);
      ctx.fillStyle = "#FFFFFF";
      ctx.fill();
      ctx.restore();
    });

    // 3) Game Objects
    if (this.gameId === "fruit") {
      this.fruits.forEach((f) => {
        ctx.save();
        ctx.beginPath();
        ctx.arc(f.x, f.y, f.r, 0, Math.PI * 2);
        ctx.fillStyle = "rgba(255, 255, 255, 0.92)";
        ctx.shadowColor = f.color + "66";
        ctx.shadowBlur = 16;
        ctx.fill();
        ctx.lineWidth = 4.5;
        ctx.strokeStyle = f.color;
        ctx.stroke();
        ctx.shadowBlur = 0;
        ctx.font = `${Math.round(f.r * 1.25)}px sans-serif`;
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        ctx.fillText(f.emoji, f.x, f.y + 3);
        ctx.restore();
      });

      // Giant 3D Clay Watermelon Boss (시안 4번 1:1 매칭!)
      if (this.boss) {
        const sx = (Math.random() - 0.5) * 20 * this.boss.shake;
        const sy = (Math.random() - 0.5) * 14 * this.boss.shake;
        const scalePop = 1 + 0.08 * this.boss.shake;
        const bx = this.boss.x + sx;
        const by = this.boss.y + sy;
        const br = this.boss.r * scalePop;

        ctx.save();
        // Ambient golden star sparkles orbiting the giant watermelon
        for (let i = 0; i < 6; i++) {
          const ang = this.elapsed * 1.4 + (i * Math.PI * 2) / 6;
          const ox = bx + Math.cos(ang) * (br * 1.22);
          const oy = by + Math.sin(ang) * (br * 1.12);
          this.drawStarShape(ctx, ox, oy, 11, 5, "#FFD644");
        }

        if (this.sprites.watermelon.complete && this.sprites.watermelon.naturalWidth > 0) {
          ctx.shadowColor = "rgba(40, 120, 50, 0.32)";
          ctx.shadowBlur = 24;
          ctx.drawImage(this.sprites.watermelon, bx - br, by - br, br * 2, br * 2);
        } else {
          ctx.beginPath();
          ctx.arc(bx, by, br, 0, Math.PI * 2);
          ctx.fillStyle = "#37B24D";
          ctx.fill();
        }
        ctx.restore();

        // Chunky Mint-to-Yellow Gradient Co-op Bar (시안 4번 하단 게이지)
        const barW = Math.min(340, w * 0.36);
        const barH = 26;
        const barX = this.boss.x - barW / 2;
        const barY = Math.min(h - 48, by + br + 22);
        const rem = Math.max(0, 1 - this.bossHits / this.bossMaxHits);

        ctx.save();
        ctx.fillStyle = "rgba(40, 50, 65, 0.36)";
        ctx.beginPath();
        ctx.roundRect(barX, barY, barW, barH, 14);
        ctx.fill();
        ctx.strokeStyle = "#FFFFFF";
        ctx.lineWidth = 4;
        ctx.stroke();

        if (rem > 0.02) {
          const grad = ctx.createLinearGradient(barX, barY, barX + barW, barY);
          grad.addColorStop(0, "#5CEFE2");
          grad.addColorStop(0.55, "#8EF59A");
          grad.addColorStop(1, "#FFE45E");
          ctx.fillStyle = grad;
          ctx.beginPath();
          ctx.roundRect(barX + 4, barY + 4, (barW - 8) * rem, barH - 8, 10);
          ctx.fill();
        }
        ctx.restore();
      }
    } else if (this.gameId === "balloon") {
      const b = this.ball;
      const bx = b.x * w;
      const by = b.y * h;
      const br = Math.min(w, h) * b.r;
      const cols = ["#FF6B81", "#4AD3C8", "#FFD644", "#60A5FA", "#C084FC"];

      ctx.save();
      ctx.beginPath();
      ctx.arc(bx, by, br, 0, Math.PI * 2);
      ctx.clip();
      if (this.sprites.balloon.complete && this.sprites.balloon.naturalWidth > 0) {
        ctx.drawImage(this.sprites.balloon, bx - br * 1.15, by - br * 1.15, br * 2.3, br * 2.3);
      } else {
        ctx.fillStyle = cols[b.colorIdx];
        ctx.fill();
      }
      ctx.restore();

      ctx.save();
      ctx.beginPath();
      ctx.arc(bx, by, br, 0, Math.PI * 2);
      ctx.lineWidth = 6;
      ctx.strokeStyle = "#FFFFFF";
      ctx.shadowColor = cols[b.colorIdx] + "88";
      ctx.shadowBlur = 18;
      ctx.stroke();
      ctx.restore();
    } else if (this.gameId === "freeze") {
      const cx = w * 0.5;
      const cy = h * 0.44;
      const r = Math.min(w, h) * 0.16;

      ctx.save();
      ctx.beginPath();
      ctx.arc(cx, cy, r, 0, Math.PI * 2);
      ctx.clip();
      if (this.sprites.dino.complete && this.sprites.dino.naturalWidth > 0) {
        ctx.drawImage(this.sprites.dino, cx - r, cy - r, r * 2, r * 2);
      }
      if (this.phase === "freeze") {
        ctx.fillStyle = "rgba(96, 185, 255, 0.45)";
        ctx.fillRect(cx - r, cy - r, r * 2, r * 2);
      }
      ctx.restore();

      ctx.save();
      ctx.beginPath();
      ctx.arc(cx, cy, r, 0, Math.PI * 2);
      ctx.lineWidth = 8;
      ctx.strokeStyle = this.phase === "freeze" ? "#60C5FF" : "#5CE596";
      ctx.shadowColor = this.phase === "freeze" ? "#60C5FF" : "#5CE596";
      ctx.shadowBlur = 22;
      ctx.stroke();
      ctx.restore();
    }

    // 4) Star sparkles & pop text
    this.particles.forEach((pt) => {
      const a = Math.max(0, pt.life / pt.maxLife);
      ctx.save();
      ctx.globalAlpha = a;
      if (pt.text) {
        ctx.font = "900 32px 'Jua', 'Apple SD Gothic Neo', sans-serif";
        ctx.textAlign = "center";
        ctx.lineWidth = 6;
        ctx.strokeStyle = pt.color;
        ctx.strokeText(pt.text, pt.x, pt.y);
        ctx.fillStyle = "#FFFFFF";
        ctx.fillText(pt.text, pt.x, pt.y);
      } else if (pt.star) {
        this.drawStarShape(ctx, pt.x, pt.y, pt.size * 1.2 * a, pt.size * 0.5 * a, "#FFD644");
      } else {
        ctx.fillStyle = pt.color;
        ctx.beginPath();
        ctx.arc(pt.x, pt.y, pt.size * a, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.restore();
    });

    // 5) Confetti
    this.confetti.forEach((c) => {
      ctx.save();
      ctx.translate(c.x, c.y);
      ctx.rotate(c.rot);
      ctx.fillStyle = c.color;
      ctx.fillRect(-c.size / 2, -c.size / 3, c.size, c.size * 0.66);
      ctx.restore();
    });
  }
}
