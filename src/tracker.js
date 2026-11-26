/**
 * Real-time 1~2 player camera pose tracker powered by MediaPipe PoseLandmarker
 * (runs locally in browser), with automatic mouse/touch fallback so it works
 * even on devices without a camera or offline.
 */

const MEDIAPIPE_BUNDLE =
  "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/vision_bundle.mjs";
const MEDIAPIPE_WASM =
  "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14/wasm";
const POSE_MODEL =
  "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task";

export class PoseTracker {
  constructor(videoEl, onStatus) {
    this.video = videoEl;
    this.onStatus = onStatus || (() => {});
    this.landmarker = null;
    this.stream = null;
    this.mode = "idle"; // 'mediapipe' | 'pointer'
    this.lastVideoTime = -1;

    // Normalized [0..1] player states (mirrored X + aspect-fill mapped to match <video object-fit: cover>)
    this.players = [];
    this.prevHands = new Map();
    this.poseFilters = new Map(); // Per-player slot 14-joint True One-Euro + Confidence Hysteresis + 0.45s Occlusion Persistence
    this.pointerPos = { x: 0.5, y: 0.5, active: false };
    this.pointerVel = 0;

    // Single Dominant Hand Air-Cursor state (1:1 mirror aligned + strong hysteresis lock + hover deadzone)
    this.dominantHandKey = null; // `${playerId}:${side}`
    this._acCandidateKey = null;
    this._acCandidateHold = 0;
    this._acLostTimer = 0;
    this.airCursor = { active: false, x: 0.5, y: 0.5 };
    this._acPrevTime = 0;
  }

  static oneEuroAlpha(cutoff, dt) {
    const tau = 1.0 / (2.0 * Math.PI * Math.max(0.01, cutoff));
    return 1.0 / (1.0 + tau / dt);
  }

  static clamp(v, lo, hi) {
    return v < lo ? lo : v > hi ? hi : v;
  }

  /**
   * Returns current viewport aspect ratio (width / height) for aspect-corrected kinematics.
   */
  getScreenAspect() {
    const vw = this.video?.clientWidth || (typeof window !== "undefined" ? window.innerWidth : 1280);
    const vh = this.video?.clientHeight || (typeof window !== "undefined" ? window.innerHeight : 720);
    if (vw > 10 && vh > 10) return vw / vh;
    return 16 / 9;
  }

  /**
   * Maps raw MediaPipe normalized [0..1] video coordinates into the visible viewport [0..1]
   * accounting for BOTH mirror flip (scaleX(-1)) AND CSS `object-fit: cover` aspect cropping!
   * Preserves off-screen values softly in [-0.5, 1.5] so elbows/hips outside the frame keep true limb angles.
   */
  mapCover(rawX, rawY) {
    let x = 1 - rawX; // Mirror X to match selfie `transform: scaleX(-1)`
    let y = rawY;
    const vidW = this.video?.videoWidth || 0;
    const vidH = this.video?.videoHeight || 0;
    const viewW = this.video?.clientWidth || (typeof window !== "undefined" ? window.innerWidth : 0);
    const viewH = this.video?.clientHeight || (typeof window !== "undefined" ? window.innerHeight : 0);

    if (vidW > 0 && vidH > 0 && viewW > 0 && viewH > 0) {
      const videoAspect = vidW / vidH;
      const screenAspect = viewW / viewH;
      if (screenAspect > videoAspect * 1.005) {
        // Viewport wider than camera stream -> top & bottom cropped by `object-fit: cover`
        const scale = screenAspect / videoAspect;
        y = (y - 0.5) * scale + 0.5;
      } else if (videoAspect > screenAspect * 1.005) {
        // Viewport narrower than camera stream -> left & right cropped by `object-fit: cover`
        const scale = videoAspect / screenAspect;
        x = (x - 0.5) * scale + 0.5;
      }
    }
    return {
      x: PoseTracker.clamp(x, -0.5, 1.5),
      y: PoseTracker.clamp(y, -0.5, 1.5),
    };
  }

  /**
   * Computes true visual Palm / Hand Center from wrist(15/16), index MCP(19/20), pinky MCP(17/18),
   * and elbow(13/14) forearm projection fallback so the dot sits dead-center on the open hand
   * (NEVER lagging back at the wrist or forearm!).
   */
  static computePalmCenter(el, wr, idx, pk, aspect = 16 / 9) {
    const wrV = wr?.v ?? 0;
    const elV = el?.v ?? 0;
    const idxV = idx?.v ?? 0;
    const pkV = pk?.v ?? 0;

    // 1) Forearm-projected palm estimate when finger knuckles dip out of confidence
    let projX = wr.x;
    let projY = wr.y;
    if (el && elV >= 0.25 && wrV >= 0.25) {
      let vx = wr.x - el.x;
      let vy = wr.y - el.y;
      const lenReal = Math.hypot(vx * aspect, vy);
      if (lenReal > 0.02) {
        // Palm center sits ~0.30x forearm length past the wrist (clamped to <= 0.12 screen-height units)
        const desired = Math.min(0.12, lenReal * 0.30);
        const s = desired / lenReal;
        projX = wr.x + vx * s;
        projY = wr.y + vy * s;
      }
    }

    // 2) Knuckle midpoint from MediaPipe index(19/20) + pinky(17/18) -> sits right on the palm/hand center
    const wIdx = Math.max(0, idxV - 0.15);
    const wPk = Math.max(0, pkV - 0.15);
    let knX = projX;
    let knY = projY;
    const handVis = Math.max(idxV, pkV);
    if (wIdx + wPk > 0.01) {
      knX = (idx.x * wIdx + pk.x * wPk) / (wIdx + wPk);
      knY = (idx.y * wIdx + pk.y * wPk) / (wIdx + wPk);
      // Sanity clamp: knuckles cannot be absurdly far from wrist (> 0.20 aspect-corrected units)
      const dx = knX - wr.x;
      const dy = knY - wr.y;
      const dReal = Math.hypot(dx * aspect, dy);
      if (dReal > 0.20 && dReal > 1e-4) {
        const s = 0.20 / dReal;
        knX = wr.x + dx * s;
        knY = wr.y + dy * s;
      }
    }

    // 3) Smooth linear blend from forearm-projected palm to true knuckle/palm center (zero snapping!)
    const t = PoseTracker.clamp((handVis - 0.22) / 0.28, 0, 1);
    return {
      x: projX + (knX - projX) * t,
      y: projY + (knY - projY) * t,
      v: Math.max(wrV, handVis * 0.92),
    };
  }

  /**
   * Backward-compatible helper retained for tests/callers.
   */
  static blendHand(wr, idx) {
    return PoseTracker.computePalmCenter(null, wr, idx, null, 16 / 9);
  }

  /**
   * Aspect-corrected 2D upper-bound kinematic bone-length clamp (parent -> child).
   * Preserves legitimate 2D foreshortening toward camera while blocking impossible stretches.
   */
  static clampBoneMax(parent, child, maxLen, aspect = 16 / 9) {
    if (!parent || !child) return;
    const dx = (child.x - parent.x) * aspect;
    const dy = child.y - parent.y;
    const dist = Math.hypot(dx, dy);
    if (dist > maxLen && dist > 1e-5) {
      const s = maxLen / dist;
      child.x = parent.x + (dx * s) / aspect;
      child.y = parent.y + dy * s;
    }
  }

  /**
   * Bounding-box overlap metrics for Pose Non-Maximum Suppression (NMS).
   */
  static bboxOverlap(a, b) {
    const ix0 = Math.max(a.minX, b.minX);
    const iy0 = Math.max(a.minY, b.minY);
    const ix1 = Math.min(a.maxX, b.maxX);
    const iy1 = Math.min(a.maxY, b.maxY);
    const iw = Math.max(0, ix1 - ix0);
    const ih = Math.max(0, iy1 - iy0);
    const inter = iw * ih;
    if (inter <= 0) return { iou: 0, contain: 0 };
    const areaA = Math.max(1e-5, (a.maxX - a.minX) * (a.maxY - a.minY));
    const areaB = Math.max(1e-5, (b.maxX - b.minX) * (b.maxY - b.minY));
    return {
      iou: inter / Math.max(1e-5, areaA + areaB - inter),
      contain: inter / Math.min(areaA, areaB),
    };
  }

  /**
   * Pose Non-Maximum Suppression (NMS): eliminates duplicate/overlapping skeletons
   * emitted by MediaPipe `numPoses: 2` on a single person (fixes the 2P 4-simultaneous-dots bug!).
   */
  static deduplicatePoses(rawParsed, aspect = 16 / 9) {
    if (rawParsed.length <= 1) return rawParsed;
    const ranked = [...rawParsed].sort((a, b) => b.qualityScore - a.qualityScore);
    const kept = [];

    for (const cand of ranked) {
      let isDuplicate = false;
      for (const k of kept) {
        const refShW = Math.max(0.14, cand.shW, k.shW);
        const centerDist = Math.hypot((cand.sortX - k.sortX) * aspect, cand.centerY - k.centerY);
        if (centerDist < Math.max(0.18, 0.88 * refShW)) {
          isDuplicate = true;
          break;
        }
        if (cand.head.v >= 0.35 && k.head.v >= 0.35) {
          const headDist = Math.hypot((cand.head.x - k.head.x) * aspect, cand.head.y - k.head.y);
          if (headDist < Math.max(0.14, 0.58 * refShW)) {
            isDuplicate = true;
            break;
          }
        }
        const ov = PoseTracker.bboxOverlap(cand.bbox, k.bbox);
        if (ov.iou > 0.28 || ov.contain > 0.48) {
          isDuplicate = true;
          break;
        }
        // Check if both hands overlap (direct or swapped L/R)
        const dLL = Math.hypot((cand.leftHand.x - k.leftHand.x) * aspect, cand.leftHand.y - k.leftHand.y);
        const dRR = Math.hypot((cand.rightHand.x - k.rightHand.x) * aspect, cand.rightHand.y - k.rightHand.y);
        const dLR = Math.hypot((cand.leftHand.x - k.rightHand.x) * aspect, cand.leftHand.y - k.rightHand.y);
        const dRL = Math.hypot((cand.rightHand.x - k.leftHand.x) * aspect, cand.rightHand.y - k.leftHand.y);
        if ((dLL < 0.14 && dRR < 0.14) || (dLR < 0.14 && dRL < 0.14)) {
          isDuplicate = true;
          break;
        }
      }
      if (!isDuplicate) kept.push(cand);
    }
    return kept;
  }

  /**
   * Commercial 4-stage zero-flicker joint filter:
   * 1) Confidence Hysteresis (ENTER=0.40, EXIT=0.22) + Asymmetric Confidence EMA
   * 2) 0.45s Torso-Relative Temporal Occlusion Persistence (zero 30Hz blinking!)
   * 3) Single-Frame Teleport Outlier Gate (never drags high-confidence fast hand slashes)
   * 4) Frame-Rate-Independent True 2D Isotropic One-Euro Filter (Casiez et al., CHI 2012)
   */
  static filterJointState(st, raw, dt, anchor, torsoH, isHand) {
    const ENTER_CONF = 0.40;
    const EXIT_CONF = 0.22;
    const TAU_RISE = 0.08;
    const TAU_FALL = 0.22;
    const HOLD_MAX = 0.45;

    const minCutoff = isHand ? 1.8 : 1.4;
    const beta = isHand ? 0.10 : 0.04; // Scaled for % screen/s (v * 100 => betaNorm 10.0 / 4.0)
    const dCutoff = 1.0;

    const rawConf = PoseTracker.clamp(raw?.v ?? 0, 0, 1);

    if (!st) {
      const tracked = rawConf >= ENTER_CONF;
      const initX = raw?.x ?? anchor.x;
      const initY = raw?.y ?? anchor.y;
      return {
        x: initX,
        y: initY,
        dxHat: 0,
        dyHat: 0,
        smoothConf: tracked ? rawConf : 0,
        rawConf,
        isTracked: tracked,
        missingTime: tracked ? 0 : HOLD_MAX,
        relOffsetX: (initX - anchor.x) / torsoH,
        relOffsetY: (initY - anchor.y) / torsoH,
        hasRelOffset: tracked,
        outlierFrames: 0,
      };
    }

    st.rawConf = rawConf;

    // 1) Confidence Hysteresis
    if (st.isTracked) {
      if (rawConf < EXIT_CONF) st.isTracked = false;
    } else {
      if (rawConf >= ENTER_CONF) st.isTracked = true;
    }

    let targetX = st.x;
    let targetY = st.y;

    if (st.isTracked) {
      st.missingTime = 0;

      // Asymmetric confidence EMA (fast attack, smooth decay)
      const tau = rawConf > st.smoothConf ? TAU_RISE : TAU_FALL;
      const aConf = 1.0 - Math.exp(-dt / tau);
      st.smoothConf = PoseTracker.clamp(st.smoothConf + (rawConf - st.smoothConf) * aConf, 0, 1);

      // 3) Single-frame teleport rejection (high-confidence hands >= 0.62 pass fast slashes immediately!)
      const jump = Math.hypot(raw.x - st.x, raw.y - st.y);
      const maxJump = isHand ? Math.max(0.45, 1.85 * torsoH) : Math.max(0.12, 0.45 * torsoH);
      const rejectSpike = jump > maxJump && st.outlierFrames < 2 && (!isHand || rawConf < 0.62);
      if (rejectSpike) {
        st.outlierFrames += 1;
        targetX = st.x + (raw.x - st.x) * 0.18;
        targetY = st.y + (raw.y - st.y) * 0.18;
      } else {
        st.outlierFrames = 0;
        targetX = raw.x;
        targetY = raw.y;
      }
    } else {
      // 2) 0.45s Temporal Occlusion Persistence relative to torso anchor
      st.missingTime += dt;
      st.outlierFrames = 0;
      if (st.hasRelOffset) {
        targetX = anchor.x + st.relOffsetX * torsoH;
        targetY = anchor.y + st.relOffsetY * torsoH;
      }
      if (st.missingTime <= HOLD_MAX) {
        st.smoothConf = Math.max(0, st.smoothConf * Math.exp(-dt / 0.28));
      } else {
        st.smoothConf = Math.max(0, st.smoothConf - dt * 2.4);
      }
    }

    // 4) True 2D Isotropic One-Euro Filter
    const dx = (targetX - st.x) / dt;
    const dy = (targetY - st.y) / dt;
    const aD = PoseTracker.oneEuroAlpha(dCutoff, dt);
    st.dxHat = aD * dx + (1.0 - aD) * st.dxHat;
    st.dyHat = aD * dy + (1.0 - aD) * st.dyHat;

    const speed = Math.hypot(st.dxHat, st.dyHat);
    const cutoff = minCutoff + beta * (speed * 100.0);
    const alpha = PoseTracker.oneEuroAlpha(cutoff, dt);
    st.x = alpha * targetX + (1.0 - alpha) * st.x;
    st.y = alpha * targetY + (1.0 - alpha) * st.y;

    // Update torso-relative offset while reliably tracked
    if (st.isTracked) {
      st.relOffsetX = (st.x - anchor.x) / torsoH;
      st.relOffsetY = (st.y - anchor.y) / torsoH;
      st.hasRelOffset = true;
    }

    return st;
  }

  static angleDeg(a, b, c) {
    if (!a || !b || !c) return 180;
    const v1x = a.x - b.x, v1y = a.y - b.y;
    const v2x = c.x - b.x, v2y = c.y - b.y;
    const m1 = Math.hypot(v1x, v1y), m2 = Math.hypot(v2x, v2y);
    if (m1 < 1e-4 || m2 < 1e-4) return 180;
    const cos = Math.max(-1, Math.min(1, (v1x * v2x + v1y * v2y) / (m1 * m2)));
    return (Math.acos(cos) * 180) / Math.PI;
  }

  /**
   * Computes 1:1 mirror-aligned Single Dominant Hand Air Cursor for hands-free menu selection.
   * - Checks ALL valid players (so P1 or P2 can control menus, while keeping strictly ONE cursor!)
   * - Requires real hand confidence (`smoothConf >= 0.36`) so off-screen/hallucinated hands NEVER steal focus
   * - Strong dominant-hand lock (`0.12` height margin + `0.22s` hold) eliminates accidental L/R teleporting
   * - Micro-deadzone (`0.0045`) keeps hover rock-solid without lag!
   */
  updateAirCursor(players, frameDt = null) {
    const now = performance.now() / 1000;
    const dt = frameDt ?? PoseTracker.clamp(now - (this._acPrevTime || now - 1 / 30), 0.008, 0.1);
    this._acPrevTime = now;

    if (this.mode !== "mediapipe" || !players.length) {
      this._acLostTimer += dt;
      if (this._acLostTimer > 0.18 || this.mode !== "mediapipe") {
        this.airCursor = { active: false, x: this.pointerPos.x, y: this.pointerPos.y };
        this.dominantHandKey = null;
        this._acCandidateKey = null;
        this._acCandidateHold = 0;
      }
      return this.airCursor;
    }

    // Gather all genuinely tracked, on-screen raised hands across valid players
    const candidates = [];
    for (const p of players) {
      const shY = p.centerY ?? 0.5;
      const torsoH = Math.min(0.45, p.metrics?.torsoH ?? 0.25);
      // Seated close-up (shoulders low on screen) -> allow pointing anywhere above bottom 12%
      const activeLineY = shY > 0.62 ? 0.88 : Math.min(0.88, shY + torsoH * 0.32);

      for (const side of ["left", "right"]) {
        const hd = side === "left" ? p.leftHand : p.rightHand;
        const key = `${p.id}:${side}`;
        const conf = hd?.smoothConf ?? hd?.v ?? 0;
        const isCurrent = key === this.dominantHandKey;
        const minConf = isCurrent ? 0.26 : 0.38;
        const maxY = isCurrent ? Math.min(0.94, activeLineY + 0.06) : activeLineY;
        const inView = hd && hd.x >= -0.02 && hd.x <= 1.02 && hd.y >= -0.02 && hd.y <= 1.02;
        if (inView && conf >= minConf && hd.y < maxY) {
          candidates.push({ key, hd, conf, isCurrent });
        }
      }
    }

    if (!candidates.length) {
      this._acLostTimer += dt;
      this._acCandidateKey = null;
      this._acCandidateHold = 0;
      if (this._acLostTimer > 0.18) {
        this.dominantHandKey = null;
        this.airCursor.active = false;
      }
      return this.airCursor;
    }
    this._acLostTimer = 0;

    // Pick highest raised hand, with strong sticky lock on current dominant hand
    candidates.sort((a, b) => a.hd.y - b.hd.y);
    const highest = candidates[0];
    const current = candidates.find((c) => c.isCurrent);

    let chosen = current || highest;
    if (current && highest.key !== current.key) {
      // Switch hands ONLY if another hand is clearly higher (>= 12% screen) for >= 0.22s
      if (current.hd.y - highest.hd.y > 0.12 && highest.conf >= 0.45) {
        if (this._acCandidateKey === highest.key) {
          this._acCandidateHold += dt;
          if (this._acCandidateHold >= 0.22) {
            chosen = highest;
            this._acCandidateKey = null;
            this._acCandidateHold = 0;
          }
        } else {
          this._acCandidateKey = highest.key;
          this._acCandidateHold = 0;
        }
      } else {
        this._acCandidateKey = null;
        this._acCandidateHold = 0;
      }
    } else {
      this._acCandidateKey = null;
      this._acCandidateHold = 0;
    }

    const switched = this.dominantHandKey !== chosen.key;
    this.dominantHandKey = chosen.key;

    // Exact 1:1 mirror coordinates (no weird 1.18x warp away from your real hand!)
    const mappedX = PoseTracker.clamp(chosen.hd.x, 0.02, 0.98);
    const mappedY = PoseTracker.clamp(chosen.hd.y, 0.02, 0.98);

    if (!this.airCursor.active || switched) {
      this.airCursor = { active: true, x: mappedX, y: mappedY };
      return this.airCursor;
    }

    // Palm is already One-Euro filtered; apply a calm micro-deadzone + responsive hover smoothing
    const moveDist = Math.hypot(mappedX - this.airCursor.x, mappedY - this.airCursor.y);
    if (moveDist < 0.0045) {
      return this.airCursor; // Ultra-steady hover inside target!
    }
    const alpha = moveDist > 0.03 ? 0.82 : PoseTracker.clamp((moveDist - 0.0045) / 0.0255, 0.28, 0.82);
    this.airCursor = {
      active: true,
      x: this.airCursor.x + (mappedX - this.airCursor.x) * alpha,
      y: this.airCursor.y + (mappedY - this.airCursor.y) * alpha,
    };
    return this.airCursor;
  }

  async init(maxPlayers = 2, { forcePointer = false } = {}) {
    this.maxPlayers = maxPlayers;

    // 개발자 모드(마우스 테스트): 카메라를 열지 않고 즉시 포인터 모드로 전환
    if (forcePointer) {
      this.stop();
      this.mode = "pointer";
      this.onStatus("🛠️ 개발자 모드 · 마우스로 자유롭게 테스트하세요!");
      return;
    }

    this.onStatus("카메라 연결 중...");

    // 1) Request front camera
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: {
          facingMode: "user",
          width: { ideal: 1280 },
          height: { ideal: 720 },
        },
        audio: false,
      });
      this.video.srcObject = this.stream;
      await this.video.play();
    } catch (err) {
      console.warn("Camera unavailable, switching to pointer simulation:", err);
      this.mode = "pointer";
      this.onStatus("마우스·터치 체험 모드 (카메라 권한 없음)");
      return;
    }

    // 2) Load MediaPipe PoseLandmarker (up to 2 players, stricter confidence to prevent ghost duplicates)
    this.onStatus("AI 모션 인식 모델 불러오는 중...");
    try {
      const vision = await import(/* @vite-ignore */ MEDIAPIPE_BUNDLE);
      const fileset = await vision.FilesetResolver.forVisionTasks(MEDIAPIPE_WASM);
      this.landmarker = await vision.PoseLandmarker.createFromOptions(fileset, {
        baseOptions: {
          modelAssetPath: POSE_MODEL,
          delegate: "GPU",
        },
        runningMode: "VIDEO",
        numPoses: 2,
        minPoseDetectionConfidence: 0.55,
        minPosePresenceConfidence: 0.55,
        minTrackingConfidence: 0.50,
      });
      this.mode = "mediapipe";
      this.onStatus("AI 카메라 인식 준비 완료!");
    } catch (err) {
      console.warn("MediaPipe load failed, using pointer fallback:", err);
      this.mode = "pointer";
      this.onStatus("오프라인/마우스 체험 모드");
    }
  }

  stop() {
    if (this.stream) {
      this.stream.getTracks().forEach((t) => t.stop());
      this.stream = null;
    }
    this.video.srcObject = null;
  }

  setPointer(normX, normY, active = true) {
    const dx = normX - this.pointerPos.x;
    const dy = normY - this.pointerPos.y;
    this.pointerVel = Math.hypot(dx, dy);
    this.pointerPos = { x: normX, y: normY, active };
  }

  /**
   * Assigns persistent player slot IDs (0 = P1 Momo left, 1 = P2 Popo right) without
   * cross-contaminating One-Euro filter states across different people.
   */
  assignPlayerSlots(deduped, expectedPlayers, now) {
    if (!deduped.length) return [];

    // Expire stale filter slots absent > 1.2s
    for (const [slotId, pf] of this.poseFilters.entries()) {
      if (now - pf.lastTime > 1.2) {
        this.poseFilters.delete(slotId);
        this.prevHands.delete(slotId);
      }
    }

    if (expectedPlayers <= 1) {
      const prev0 = this.poseFilters.get(0);
      let pick = deduped[0]; // Already highest qualityScore
      if (deduped.length > 1 && prev0 && now - prev0.lastTime < 0.9) {
        pick = deduped.reduce((best, cand) =>
          Math.abs(cand.sortX - prev0.lastCenterX) < Math.abs(best.sortX - prev0.lastCenterX) ? cand : best
        );
      }
      return [{ slotId: 0, raw: pick }];
    }

    const limited = deduped.slice(0, 2);
    if (limited.length === 2) {
      limited.sort((a, b) => a.sortX - b.sortX);
      return [
        { slotId: 0, raw: limited[0] },
        { slotId: 1, raw: limited[1] },
      ];
    }

    // 1 real person detected in 2P mode:
    // Keep slot 1 ONLY if slot 1 was active recently while slot 0 was absent & person is near slot 1
    const single = limited[0];
    const pf0 = this.poseFilters.get(0);
    const pf1 = this.poseFilters.get(1);
    const has0 = pf0 && now - pf0.lastTime < 0.7;
    const has1 = pf1 && now - pf1.lastTime < 0.7;
    if (has1 && !has0 && Math.abs(single.sortX - pf1.lastCenterX) < 0.26) {
      return [{ slotId: 1, raw: single }];
    }
    return [{ slotId: 0, raw: single }];
  }

  /**
   * Returns an array of genuinely detected players (deduplicated via Pose NMS):
   * [{ id: 0|1, centerX, centerY, head, leftHand, rightHand, handsUp, motion, metrics }]
   */
  update(expectedPlayers = 2) {
    if (this.mode === "mediapipe" && this.landmarker && this.video.readyState >= 2) {
      if (this.video.currentTime !== this.lastVideoTime) {
        this.lastVideoTime = this.video.currentTime;
        const nowMs = performance.now();
        const now = nowMs / 1000;
        const aspect = this.getScreenAspect();
        const result = this.landmarker.detectForVideo(this.video, nowMs);
        const poses = result?.landmarks || [];

        const rawParsed = [];
        for (const lm of poses) {
          if (!lm || lm.length < 29) continue;
          const pt = (idx) => {
            const m = this.mapCover(lm[idx].x, lm[idx].y);
            return { x: m.x, y: m.y, v: lm[idx].visibility ?? 1 };
          };

          const head = pt(0);
          const shL = pt(11), shR = pt(12);
          const elL = pt(13), elR = pt(14);
          const wrL = pt(15), wrR = pt(16);
          const pkL = pt(17), pkR = pt(18);
          const idxL = pt(19), idxR = pt(20);
          const hipL = pt(23), hipR = pt(24);
          const knL = pt(25), knR = pt(26);
          const anL = pt(27), anR = pt(28);

          // True visual palm/hand center (knuckle midpoint + forearm projection fallback)
          const leftHand = PoseTracker.computePalmCenter(elL, wrL, idxL, pkL, aspect);
          const rightHand = PoseTracker.computePalmCenter(elR, wrR, idxR, pkR, aspect);

          // Pose quality gate: reject faint ghost poses & background noise
          const upperPts = [head, shL, shR];
          const upperVisibleCount = upperPts.filter((u) => u.v >= 0.38).length;
          const upperVisAvg = (head.v + shL.v + shR.v) / 3;
          const hasCloseUpHand = head.v >= 0.45 && (leftHand.v >= 0.45 || rightHand.v >= 0.45);
          if (upperVisibleCount < 2 && !hasCloseUpHand) continue;
          if (upperVisAvg < 0.30 && !hasCloseUpHand) continue;

          const bothSh = shL.v >= 0.32 && shR.v >= 0.32;
          const sortX = bothSh ? (shL.x + shR.x) * 0.5 : head.x;
          const centerY = bothSh ? (shL.y + shR.y) * 0.5 : head.y + 0.14;
          const shW = bothSh
            ? Math.max(0.06, Math.hypot((shL.x - shR.x) * aspect, shL.y - shR.y))
            : 0.24;

          // Upper-body bounding box for Pose NMS deduplication
          const boxPts = [head, shL, shR, elL, elR, hipL, hipR].filter((p) => p.v >= 0.28);
          let minX = sortX - 0.08, maxX = sortX + 0.08;
          let minY = centerY - 0.12, maxY = centerY + 0.18;
          if (boxPts.length >= 2) {
            minX = Math.min(...boxPts.map((p) => p.x)) - 0.04;
            maxX = Math.max(...boxPts.map((p) => p.x)) + 0.04;
            minY = Math.min(...boxPts.map((p) => p.y)) - 0.04;
            maxY = Math.max(...boxPts.map((p) => p.y)) + 0.04;
          }
          const qualityScore = upperVisAvg + 0.22 * Math.min(1, shW * 2.4);

          rawParsed.push({
            sortX,
            centerY,
            shW,
            qualityScore,
            bbox: { minX, maxX, minY, maxY },
            head, shL, shR, elL, elR, leftHand, rightHand, hipL, hipR, knL, knR, anL, anR,
          });
        }

        // Deduplicate overlapping poses (kills 2P 4-simultaneous-dots bug on 1 person!)
        const deduped = PoseTracker.deduplicatePoses(rawParsed, aspect);
        const assigned = this.assignPlayerSlots(deduped, expectedPlayers, now);

        let lastFrameDt = 1 / 30;
        this.players = assigned.map(({ slotId, raw }) => {
          let pf = this.poseFilters.get(slotId);
          // Reset filter cleanly if slot expired OR jumped wildly (different person took the slot)
          if (!pf || now - pf.lastTime > 1.2 || Math.abs(raw.sortX - (pf.lastCenterX ?? raw.sortX)) > 0.36) {
            const initTorso = PoseTracker.clamp(raw.shW * 1.48, 0.18, 1.25);
            pf = { lastTime: now - 1 / 30, lastCenterX: raw.sortX, torsoH: initTorso, joints: {} };
            this.poseFilters.set(slotId, pf);
            this.prevHands.delete(slotId);
          }
          const dt = PoseTracker.clamp(now - pf.lastTime, 0.008, 0.10);
          lastFrameDt = dt;
          pf.lastTime = now;
          pf.lastCenterX = raw.sortX;

          // Smart torso height estimation: works identically for full-body standing AND close-up laptop seating!
          const rawShMidX = (raw.shL.x + raw.shR.x) * 0.5;
          const rawShMidY = (raw.shL.y + raw.shR.y) * 0.5;
          const bothShVisible = raw.shL.v >= 0.35 && raw.shR.v >= 0.35;
          const hipsPresent =
            raw.hipL.v >= 0.35 &&
            raw.hipR.v >= 0.35 &&
            raw.hipL.y > 0.02 &&
            raw.hipL.y < 0.96 &&
            raw.hipR.y > 0.02 &&
            raw.hipR.y < 0.96;

          const rawHipMidX = hipsPresent
            ? (raw.hipL.x + raw.hipR.x) * 0.5
            : pf.joints.hipL && pf.joints.hipR && pf.joints.hipL.smoothConf > 0.25
            ? (pf.joints.hipL.x + pf.joints.hipR.x) * 0.5
            : rawShMidX;
          const rawHipMidY = hipsPresent
            ? (raw.hipL.y + raw.hipR.y) * 0.5
            : pf.joints.hipL && pf.joints.hipR && pf.joints.hipL.smoothConf > 0.25
            ? (pf.joints.hipL.y + pf.joints.hipR.y) * 0.5
            : rawShMidY + pf.torsoH;

          let estTorsoH = pf.torsoH;
          if (hipsPresent && bothShVisible) {
            estTorsoH = PoseTracker.clamp(
              Math.hypot((rawShMidX - rawHipMidX) * aspect, rawShMidY - rawHipMidY),
              0.14,
              1.30
            );
          } else if (bothShVisible) {
            // Hips off-screen (seated close to laptop/phone) -> estimate torsoH from shoulder width!
            estTorsoH = PoseTracker.clamp(raw.shW * 1.48, 0.18, 1.30);
          } else if (raw.head.v >= 0.35) {
            const headToSh = Math.abs(rawShMidY - raw.head.y);
            estTorsoH = PoseTracker.clamp(Math.max(0.28, headToSh * 2.6), 0.22, 1.30);
          }

          const aTorso = 1.0 - Math.exp(-dt / 0.22);
          pf.torsoH = PoseTracker.clamp(pf.torsoH + (estTorsoH - pf.torsoH) * aTorso, 0.14, 1.30);
          const smoothTorsoH = pf.torsoH;
          const anchor = hipsPresent
            ? { x: (rawShMidX + rawHipMidX) * 0.5, y: (rawShMidY + rawHipMidY) * 0.5 }
            : { x: rawShMidX, y: rawShMidY + smoothTorsoH * 0.5 };

          // STAGE 1-3: Filter all 14 joints FIRST (True One-Euro + Confidence Hysteresis + 0.45s Persistence + Outlier Gate)
          const runFilter = (key, rawPt, isHand = false) => {
            const st = PoseTracker.filterJointState(pf.joints[key], rawPt, dt, anchor, smoothTorsoH, isHand);
            pf.joints[key] = st;
            return { x: st.x, y: st.y, v: st.smoothConf, smoothConf: st.smoothConf, rawConf: st.rawConf };
          };

          const head = runFilter("head", raw.head, false);
          const shL = runFilter("shL", raw.shL, false);
          const shR = runFilter("shR", raw.shR, false);
          const elL = runFilter("elL", raw.elL, false);
          const elR = runFilter("elR", raw.elR, false);
          const leftHand = runFilter("leftHand", raw.leftHand, true);
          const rightHand = runFilter("rightHand", raw.rightHand, true);
          const hipL = runFilter("hipL", raw.hipL, false);
          const hipR = runFilter("hipR", raw.hipR, false);
          const knL = runFilter("knL", raw.knL, false);
          const knR = runFilter("knR", raw.knR, false);
          const anL = runFilter("anL", raw.anL, false);
          const anR = runFilter("anR", raw.anR, false);

          // STAGE 3b: Aspect-corrected non-destructive upper-bound bone clamping
          // Actively tracked high-confidence hands get a generous anatomical ceiling so real hands are NEVER pulled down!
          const maxUpperArmL = (elL.rawConf >= 0.42 ? 1.55 : 1.05) * smoothTorsoH;
          const maxForearmL = (leftHand.rawConf >= 0.42 ? 1.75 : 1.05) * smoothTorsoH;
          const maxUpperArmR = (elR.rawConf >= 0.42 ? 1.55 : 1.05) * smoothTorsoH;
          const maxForearmR = (rightHand.rawConf >= 0.42 ? 1.75 : 1.05) * smoothTorsoH;
          const maxLeg = 1.40 * smoothTorsoH;

          PoseTracker.clampBoneMax(shL, elL, maxUpperArmL, aspect);
          PoseTracker.clampBoneMax(elL, leftHand, maxForearmL, aspect);
          PoseTracker.clampBoneMax(shR, elR, maxUpperArmR, aspect);
          PoseTracker.clampBoneMax(elR, rightHand, maxForearmR, aspect);
          PoseTracker.clampBoneMax(hipL, knL, maxLeg, aspect);
          PoseTracker.clampBoneMax(knL, anL, maxLeg, aspect);
          PoseTracker.clampBoneMax(hipR, knR, maxLeg, aspect);
          PoseTracker.clampBoneMax(knR, anR, maxLeg, aspect);

          // Sync clamped positions back to filter state
          pf.joints.elL.x = elL.x; pf.joints.elL.y = elL.y;
          pf.joints.leftHand.x = leftHand.x; pf.joints.leftHand.y = leftHand.y;
          pf.joints.elR.x = elR.x; pf.joints.elR.y = elR.y;
          pf.joints.rightHand.x = rightHand.x; pf.joints.rightHand.y = rightHand.y;
          pf.joints.knL.x = knL.x; pf.joints.knL.y = knL.y;
          pf.joints.anL.x = anL.x; pf.joints.anL.y = anL.y;
          pf.joints.knR.x = knR.x; pf.joints.knR.y = knR.y;
          pf.joints.anR.x = anR.x; pf.joints.anR.y = anR.y;

          // STAGE 4: Compute ALL torso-normalized metrics from the FILTERED 14-joint skeleton!
          const centerX = (shL.x + shR.x) * 0.5;
          const shoulderY = (shL.y + shR.y) * 0.5;
          const hipX = (hipL.x + hipR.x) * 0.5;
          const hipY = (hipL.y + hipR.y) * 0.5;
          const torsoH = hipsPresent
            ? Math.max(0.12, Math.hypot(centerX - hipX, shoulderY - hipY))
            : Math.max(0.14, Math.min(0.65, smoothTorsoH));
          const shoulderW = Math.max(0.08, Math.hypot(shL.x - shR.x, shL.y - shR.y));
          const handsUp =
            (leftHand.smoothConf >= 0.30 && leftHand.y < shoulderY - 0.05) ||
            (rightHand.smoothConf >= 0.30 && rightHand.y < shoulderY - 0.05);

          const lElbowAngle = PoseTracker.angleDeg(shL, elL, leftHand);
          const rElbowAngle = PoseTracker.angleDeg(shR, elR, rightHand);
          const lKneeAngle = PoseTracker.angleDeg(hipL, knL, anL);
          const rKneeAngle = PoseTracker.angleDeg(hipR, knR, anR);
          const wristSpan = Math.abs(leftHand.x - rightHand.x);
          const ankleSpan = Math.abs(anL.x - anR.x);
          const footLift = Math.max(Math.abs(anL.y - anR.y), Math.abs(knL.y - knR.y));
          const signedTorsoLean = (centerX - hipX) / torsoH;
          const torsoLean = Math.abs(signedTorsoLean);
          const shoulderTilt = (shR.y - shL.y) / shoulderW;
          const lowerVisible = hipL.smoothConf > 0.25 && hipR.smoothConf > 0.25 && knL.smoothConf > 0.22 && knR.smoothConf > 0.22;
          const kneeYAvg = (knL.y + knR.y) * 0.5;
          const isSquatting =
            (lowerVisible && (Math.min(lKneeAngle, rKneeAngle) < 138 || (kneeYAvg - hipY) < torsoH * 0.48)) ||
            head.y > 0.56;

          const prev = this.prevHands.get(slotId);
          let motion = 0;
          if (prev) {
            motion =
              (leftHand.smoothConf >= 0.25 ? Math.hypot(leftHand.x - prev.lx, leftHand.y - prev.ly) : 0) +
              (rightHand.smoothConf >= 0.25 ? Math.hypot(rightHand.x - prev.rx, rightHand.y - prev.ry) : 0) +
              Math.hypot(head.x - prev.hx, head.y - prev.hy) * 0.6;
          }
          this.prevHands.set(slotId, {
            lx: leftHand.x,
            ly: leftHand.y,
            rx: rightHand.x,
            ry: rightHand.y,
            hx: head.x,
            hy: head.y,
          });

          return {
            id: slotId,
            centerX,
            centerY: shoulderY,
            head,
            shoulders: [shL, shR],
            elbows: [elL, elR],
            hips: [hipL, hipR],
            knees: [knL, knR],
            ankles: [anL, anR],
            leftHand,
            rightHand,
            handsUp,
            motion,
            metrics: {
              torsoH,
              shoulderW,
              shoulderY,
              hipY,
              lElbowAngle,
              rElbowAngle,
              lKneeAngle,
              rKneeAngle,
              wristSpan,
              ankleSpan,
              footLift,
              torsoLean,
              signedTorsoLean,
              shoulderTilt,
              lowerVisible,
              isSquatting,
            },
          };
        });

        // Update air cursor ONLY on fresh video frames so 60fps loop never feeds duplicate zero-speed frames!
        this.updateAirCursor(this.players, lastFrameDt);
      }
      return this.players;
    }

    // Fallback: Pointer/Touch simulation (supports full 14-joint skeleton & metrics for 1P/2P testing!)
    const px = this.pointerPos.x;
    const py = this.pointerPos.y;
    const vel = this.pointerVel;
    this.pointerVel *= 0.8;
    const t = performance.now() / 1000;

    const buildSimPlayer = (id, baseCx, isActive, ptrX, ptrY) => {
      const lean = isActive ? Math.max(-0.55, Math.min(0.55, (ptrX - baseCx) * 1.4)) : Math.sin(t * 2 + id) * 0.05;
      const squatAmt = isActive ? Math.max(0, Math.min(1, (ptrY - 0.58) / 0.24)) : 0;
      const jumpAmt = isActive ? Math.max(0, Math.min(1, (0.36 - ptrY) / 0.26)) : 0;
      const stride = Math.sin(t * 9 + id * 2.1) * (vel > 0.008 ? 0.06 : 0.01);

      const hipX = baseCx;
      const hipY = 0.64 + squatAmt * 0.12 - jumpAmt * 0.07;
      const centerX = baseCx + lean * 0.14;
      const shoulderY = 0.44 + squatAmt * 0.16 - jumpAmt * 0.08;
      const head = { x: centerX + lean * 0.04, y: shoulderY - 0.11, v: 1, smoothConf: 1 };
      const shL = { x: centerX - 0.075, y: shoulderY - lean * 0.03, v: 1, smoothConf: 1 };
      const shR = { x: centerX + 0.075, y: shoulderY + lean * 0.03, v: 1, smoothConf: 1 };

      let leftHand, rightHand;
      if (isActive) {
        const span = Math.max(0.08, Math.min(0.24, 0.10 + Math.abs(ptrX - baseCx) * 0.35));
        leftHand = { x: Math.max(0.04, ptrX - span * 0.55), y: ptrY, v: 1, smoothConf: 1 };
        rightHand = { x: Math.min(0.96, ptrX + span * 0.55), y: ptrY, v: 1, smoothConf: 1 };
      } else {
        leftHand = { x: shL.x - 0.06, y: shoulderY + Math.sin(t * 3 + id) * 0.05, v: 1, smoothConf: 1 };
        rightHand = { x: shR.x + 0.06, y: shoulderY + Math.cos(t * 3 + id) * 0.05, v: 1, smoothConf: 1 };
      }

      const elL = { x: (shL.x + leftHand.x) * 0.5 - 0.02, y: (shL.y + leftHand.y) * 0.5 + 0.03, v: 1, smoothConf: 1 };
      const elR = { x: (shR.x + rightHand.x) * 0.5 + 0.02, y: (shR.y + rightHand.y) * 0.5 + 0.03, v: 1, smoothConf: 1 };
      const hipL = { x: hipX - 0.055, y: hipY, v: 1, smoothConf: 1 };
      const hipR = { x: hipX + 0.055, y: hipY, v: 1, smoothConf: 1 };

      const footLiftSim = isActive && ptrY < 0.38 && Math.abs(ptrX - baseCx) > 0.12 ? 0.09 : Math.abs(stride);
      const knL = {
        x: hipL.x - squatAmt * 0.04,
        y: hipY + 0.14 - squatAmt * 0.05 + Math.min(0, stride),
        v: 1,
        smoothConf: 1,
      };
      const knR = {
        x: hipR.x + squatAmt * 0.04,
        y: hipY + 0.14 - squatAmt * 0.05 - footLiftSim * 0.7 + Math.max(0, -stride),
        v: 1,
        smoothConf: 1,
      };
      const anL = {
        x: isActive && ptrY > 0.68 ? Math.max(0.06, ptrX - 0.05) : hipL.x - 0.01,
        y: isActive && ptrY > 0.68 ? Math.min(0.92, ptrY + 0.03) : 0.88 - jumpAmt * 0.07 + Math.min(0, stride),
        v: 1,
        smoothConf: 1,
      };
      const anR = {
        x: isActive && ptrY > 0.68 ? Math.min(0.94, ptrX + 0.05) : hipR.x + 0.01,
        y: isActive && ptrY > 0.68 ? Math.min(0.92, ptrY + 0.03) : 0.88 - jumpAmt * 0.07 - footLiftSim,
        v: 1,
        smoothConf: 1,
      };

      const torsoH = Math.max(0.12, Math.hypot(centerX - hipX, shoulderY - hipY));
      const shoulderW = Math.max(0.08, Math.hypot(shL.x - shR.x, shL.y - shR.y));
      const lElbowAngle = PoseTracker.angleDeg(shL, elL, leftHand);
      const rElbowAngle = PoseTracker.angleDeg(shR, elR, rightHand);
      const lKneeAngle = PoseTracker.angleDeg(hipL, knL, anL);
      const rKneeAngle = PoseTracker.angleDeg(hipR, knR, anR);
      const wristSpan = Math.abs(leftHand.x - rightHand.x);
      const ankleSpan = Math.abs(anL.x - anR.x);
      const footLift = Math.max(Math.abs(anL.y - anR.y), Math.abs(knL.y - knR.y));
      const signedTorsoLean = (centerX - hipX) / torsoH;
      const torsoLean = Math.abs(signedTorsoLean);
      const shoulderTilt = (shR.y - shL.y) / shoulderW;
      const isSquatting = squatAmt > 0.45 || head.y > 0.55;

      return {
        id,
        centerX,
        centerY: shoulderY,
        head,
        shoulders: [shL, shR],
        elbows: [elL, elR],
        hips: [hipL, hipR],
        knees: [knL, knR],
        ankles: [anL, anR],
        leftHand,
        rightHand,
        handsUp: leftHand.y < shoulderY - 0.04 || rightHand.y < shoulderY - 0.04,
        motion: isActive ? vel : vel * 0.25,
        metrics: {
          torsoH,
          shoulderW,
          shoulderY,
          hipY,
          lElbowAngle,
          rElbowAngle,
          lKneeAngle,
          rKneeAngle,
          wristSpan,
          ankleSpan,
          footLift,
          torsoLean,
          signedTorsoLean,
          shoulderTilt,
          lowerVisible: true,
          isSquatting,
        },
      };
    };

    if (expectedPlayers === 1) {
      this.players = [buildSimPlayer(0, 0.5, true, px, py)];
    } else {
      const p1Active = px < 0.52;
      this.players = [
        buildSimPlayer(0, 0.28, p1Active, px, py),
        buildSimPlayer(1, 0.72, !p1Active, px, py),
      ];
    }
    return this.players;
  }
}
