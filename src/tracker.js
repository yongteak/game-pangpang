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

    // Normalized [0..1] player states (mirrored X so left on screen = 0, right = 1)
    this.players = [];
    this.prevHands = new Map();
    this.pointerPos = { x: 0.5, y: 0.5, active: false };
    this.pointerVel = 0;
  }

  async init(maxPlayers = 2) {
    this.maxPlayers = maxPlayers;
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

    // 2) Load MediaPipe PoseLandmarker (up to 2 players)
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
        minPoseDetectionConfidence: 0.45,
        minPosePresenceConfidence: 0.45,
        minTrackingConfidence: 0.45,
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
   * Returns an array of detected players sorted left-to-right on screen:
   * [{ id: 0|1, centerX, centerY, head, leftHand, rightHand, handsUp, motion }]
   */
  update(expectedPlayers = 2) {
    if (this.mode === "mediapipe" && this.landmarker && this.video.readyState >= 2) {
      if (this.video.currentTime !== this.lastVideoTime) {
        this.lastVideoTime = this.video.currentTime;
        const result = this.landmarker.detectForVideo(this.video, performance.now());
        const poses = result?.landmarks || [];

        const parsed = poses.map((lm) => {
          // Mirror X (1 - x) to match mirrored selfie video
          const pt = (idx) => ({ x: 1 - lm[idx].x, y: lm[idx].y, v: lm[idx].visibility ?? 1 });
          const nose = pt(0);
          const shL = pt(11);
          const shR = pt(12);
          const wrL = pt(15);
          const wrR = pt(16);
          const idxL = pt(19);
          const idxR = pt(20);

          const leftHand = idxL.v > 0.35 ? idxL : wrL;
          const rightHand = idxR.v > 0.35 ? idxR : wrR;
          const centerX = (shL.x + shR.x) / 2;
          const shoulderY = (shL.y + shR.y) / 2;
          const handsUp = leftHand.y < shoulderY - 0.05 || rightHand.y < shoulderY - 0.05;

          return {
            centerX,
            centerY: shoulderY,
            head: nose,
            shoulders: [shL, shR],
            leftHand,
            rightHand,
            handsUp,
            motion: 0,
          };
        });

        // Sort left-to-right so P1 = left (Momo), P2 = right (Popo)
        parsed.sort((a, b) => a.centerX - b.centerX);

        this.players = parsed.slice(0, expectedPlayers).map((p, idx) => {
          const prev = this.prevHands.get(idx);
          let motion = 0;
          if (prev) {
            motion =
              Math.hypot(p.leftHand.x - prev.lx, p.leftHand.y - prev.ly) +
              Math.hypot(p.rightHand.x - prev.rx, p.rightHand.y - prev.ry) +
              Math.hypot(p.head.x - prev.hx, p.head.y - prev.hy) * 0.6;
          }
          this.prevHands.set(idx, {
            lx: p.leftHand.x,
            ly: p.leftHand.y,
            rx: p.rightHand.x,
            ry: p.rightHand.y,
            hx: p.head.x,
            hy: p.head.y,
          });
          return { ...p, id: idx, motion };
        });
      }
      return this.players;
    }

    // Fallback: Pointer/Touch simulation (supports 1P or mirrored 2P demo)
    const px = this.pointerPos.x;
    const py = this.pointerPos.y;
    const vel = this.pointerVel;
    this.pointerVel *= 0.8;

    if (expectedPlayers === 1) {
      this.players = [
        {
          id: 0,
          centerX: 0.5,
          centerY: 0.62,
          head: { x: 0.5, y: 0.45 },
          shoulders: [
            { x: 0.42, y: 0.58 },
            { x: 0.58, y: 0.58 },
          ],
          leftHand: { x: Math.max(0.06, px - 0.06), y: py },
          rightHand: { x: Math.min(0.94, px + 0.06), y: py },
          handsUp: py < 0.46,
          motion: vel,
        },
      ];
    } else {
      // 2P simulation: mouse controls active side, other buddy waves gently
      const t = performance.now() / 1000;
      const p1Active = px < 0.55;
      this.players = [
        {
          id: 0,
          centerX: 0.28,
          centerY: 0.62,
          head: { x: 0.28, y: 0.44 },
          shoulders: [
            { x: 0.22, y: 0.58 },
            { x: 0.34, y: 0.58 },
          ],
          leftHand: p1Active ? { x: px, y: py } : { x: 0.22 + Math.sin(t * 3) * 0.05, y: 0.44 },
          rightHand: p1Active ? { x: Math.min(0.55, px + 0.08), y: py } : { x: 0.36, y: 0.46 + Math.cos(t * 3) * 0.05 },
          handsUp: py < 0.48,
          motion: vel,
        },
        {
          id: 1,
          centerX: 0.72,
          centerY: 0.66,
          head: { x: 0.72, y: 0.5 },
          shoulders: [
            { x: 0.66, y: 0.62 },
            { x: 0.78, y: 0.62 },
          ],
          leftHand: !p1Active ? { x: px, y: py } : { x: 0.64, y: 0.48 + Math.sin(t * 3.3) * 0.05 },
          rightHand: !p1Active ? { x: Math.min(0.95, px + 0.08), y: py } : { x: 0.78 + Math.cos(t * 3.1) * 0.05, y: 0.46 },
          handsUp: py < 0.48,
          motion: vel,
        },
      ];
    }
    return this.players;
  }
}
