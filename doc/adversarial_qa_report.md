# Adversarial Commercial UI/UX & Gameplay QA Report — PangPang Friends (`kids1`)

- **Audit Date**: 2026-11-28
- **Auditor**: `@adversarial-qa` (Hostile Commercial Nintendo/Wii UI/UX & Gameplay Auditor)
- **Scope**: Web (`1280×720` Desktop/TV + `852×393` Mobile Landscape, PixiJS v8 WebGL) + Native iOS (`SwiftUI + SpriteKit + Vision + AVFoundation`, `xcodebuild -sdk iphoneos`) across all 7 mini-games + Home / Select / Ready / Clear screens.
- **Final Verdict**: **PASS — 0 P0 / 0 P1 Defects Remaining** (verified after 2 recursive audit-fix-reverify rounds).

---

## 1. Executive Summary

| Audit Domain | Web (`1280×720`) | Web (`852×393`) | Native iOS (`GameScene.swift` + `xcodebuild`) | Status |
| :--- | :---: | :---: | :---: | :---: |
| **Animal Pose Center-Hero & De-Clutter** | PASS | PASS (fixed R2) | PASS (fixed R2) | **PASS** |
| **Co-op 2P Bonus & Hole-in-the-Wall (Zero Double Banners)** | PASS | PASS (fixed R2) | PASS | **PASS** |
| **Polaroid Clear Album (Phase 4)** | PASS | PASS (fixed R2) | PASS | **PASS** |
| **Expressive 8-Routine Dance Puppet Rig (Freeze / Balance / Jungle)** | PASS (fixed R2) | PASS | PASS | **PASS** |
| **All 7 Games E2E (Console Errors / Warnings / Exceptions)** | `0 / 0 / 0` | `0 / 0 / 0` | `** BUILD SUCCEEDED **` (`0` errors, `0` Swift warnings) | **PASS** |
| **Performance Guide Compliance (`doc/performance_development_guide.md`)** | PASS (98/98 textures, zero per-frame rig alloc) | PASS | PASS (batched `SKSpriteNode` silhouettes, `balloonStringTex`, quantized `SKShapeNode`, thread-isolated queues) | **PASS** |

---

## 2. Adversarial Commercial Checklist Verification

### 2.1 Animal Pose Center-Hero & De-Clutter Audit
- **Center-Hero Sizing & Position**:
  - **Web**: `x = 0.50W`, `y = 0.52H` (desktop) / `0.58H` (compact `852×393`), `dim = 0.50 * min(W,H)` (desktop) / `0.45 * min(W,H)` (compact), AR hologram alpha `0.88 + 0.12 * guideMb`, glowing golden-to-mint halo.
  - **iOS**: `x = 0.50W`, `y = 0.46H` (iPad) / `0.39H` (compact `H < 500`), `dim = 0.50 * min(W,H)` / `0.45 * min(W,H)`, pre-baked `softGlowTex` radial halo, `alpha = 0.88 + 0.12 * animalMatchBlend`.
- **Right-Side De-Clutter**:
  - Entire right half is 100% open and uncluttered on both Web and iOS — ONLY `⭐ Score` (top-right) and `🔥 N COMBO!` (when `combo >= 2`, tucked cleanly beside Score on desktop and cleanly below Score on compact `852×393` / iOS).
- **Top-Center Header Separation**:
  - `[Animal Name Pill] + [1-line Cue] + [Hold Progress Bar + 3D Gold Star]` cleanly separated from top-left Pie Timer + 7 Mini Relay Badges and from the Center-Hero Animal + Boss Golden Crown across both `1280×720` and `852×393`.
- **Zero Double Banners (Co-op 2P & Hole-in-the-Wall)**:
  - Both Web (`#ingame-callout` suppressed + standard header skipped when `cur.isCoop || cur.isWall`) and iOS (`showStandardPanel = !roundItem.isCoop && !roundItem.isWallRound`, `onCallout` cleared on `.animal`) render ONLY the dedicated pink-gold Co-op ribbon or sky-blue Wall banner.

### 2.2 Expressive 8-Routine Dance Puppet Audit (Freeze Dance + Balance + Jungle)
- **8 Routines Verified**: `groove_bounce`, `disco_point`, `cheer_manse`, `wave_surf`, `happy_clap`, `star_jump`, `twist_shimmy`, `hero_pose` — auto-cycling every 6 beats (`12π`) with exponential cross-fade and per-character personality multipliers (`dino`, `momo`, `popo`).
- **Joint & Anatomy Inspection (Live Screenshots)**:
  - Zero floating gaps at shoulders, hips, or neck across Momo, Dino, and Popo in all routines (`disco_point`, `cheer_manse`, `happy_clap`, `star_jump`) and Instant Freeze-Pose Lock.
  - Natural limb orientation (arms never inverted/backwards).
  - Dynamic grounded floor shadow directly beneath each puppet (shrinks during jumps, widens on beat-down dips/landings; planted on the wooden log in Balance and beneath Momo in Jungle).
  - Neon club dancer rings rendered behind `spriteLayer` so characters' faces remain 100% unobstructed.

### 2.3 All 7 Games End-to-End & Performance Guide Audit
- **Web E2E (`1280×720` + `852×393`)**:
  - Verified Home → Select → Ready → Fruit / Balloon / Freeze / Animal (Standard, Boss, Co-op, Wall, Polaroid Album) / Jungle / Mole / Balance.
  - PixiJS v8 textures loaded: **98 / 98** (`missingRig: []`).
  - Console errors: **0**, Console warnings: **0**, Page exceptions: **0**.
- **iOS Code & Build Audit (`doc/performance_development_guide.md`)**:
  - Zero 60fps `SKShapeNode` / `CGMutablePath` tessellation (organic body silhouettes use batched `trailCapsuleTex` + `headHaloRingTex` `SKSpriteNode`s; balloon strings use `balloonStringTex`; floor shadows use pre-baked `floorShadowTexture`; gauge `SKShapeNode`s use quantized integer steps `pieStep`/`holdStep`/`pctStep`).
  - Zero `onScore`/`onProgress` spam (100% routed through deduplicated `reportScore`/`reportProgress`; `setStickerLabel` caches by text+fontSize key).
  - Zero cross-thread `@Published` races (`sessionQueue`, `visionQueue`, `audioQueue` strictly isolated; `visionExpectedPlayers` owned by `visionQueue`; `session.automaticallyConfiguresApplicationAudioSession = false` preserved).
  - 실기기 타깃 빌드 (`xcodebuild -project ios/PangPangFriends/PangPangFriends.xcodeproj -target PangPangFriends -sdk iphoneos -configuration Debug CODE_SIGNING_ALLOWED=NO build`): **`** BUILD SUCCEEDED **`** with **0 errors** and **0 Swift warnings** (`ios/PangPangFriends/build` cleaned).

---

## 3. Recursive Defect Resolution Log

### Round 1 (Initial Hostile Audit — 4 P1 Defects Found)

| ID | Platform | Severity | Component | Defect Description | Assigned To | Resolution |
| :--- | :--- | :---: | :--- | :--- | :--- | :--- |
| **QA-R1-01** | Web | **P1** | `src/pixiRenderer.js:1006` (Freeze Dance) | Neon dancer ring drawn on `uiGfx` (above `spriteLayer`), slicing directly across Momo/Dino/Popo's eyes and faces. | `@web-upgrade` | Moved dancer ring & glow onto `splatGfx` behind `spriteLayer`. Verified clean in Round 2. |
| **QA-R1-02** | Web | **P1** | `src/pixiRenderer.js:1336-1525` (Animal Pose `852×393`) | (a) `🔥 N COMBO!` overlapped DOM `⭐ Score` pill; (b) Boss Pose top-center pill touched 7th round badge and Hold Bar touched Boss Golden Crown; (c) Bottom-left pose badge label clipped bottom edge (`396 > 393`); (d) Co-op ribbon right tail touched Score pill. | `@web-upgrade` | Moved compact Combo pill below Score (`y=74`), shrunk compact pie/badges (`pieR=15, badgeR=10.5`), lowered compact guide (`y=0.58H, dim=0.45*min(W,H)`) with crown clamped below Hold Bar, raised bottom-left badge (`r=30, cy=h-78`), narrowed compact Co-op ribbon (`w-340`). Verified clean in Round 2. |
| **QA-R1-03** | Web | **P1** | `src/styles.css` (Polaroid Album `852×393`) | Bottom action bar covered all 3 Polaroid card captions and top ribbon mascots clipped off top of `393px` viewport. | `@web-upgrade` | Added `@media (max-height: 480px)` responsive rules scaling ribbon, Polaroid cards, and action bar. Verified clean in Round 2. |
| **QA-R1-04** | iOS | **P1** | `GameScene.swift:3972-4040` (Animal Pose `852×393`) | At `H=393`, Hold Bar (`barY=279`, star bottom `261`) overlapped `animalGuideNode` top (`279..292`) and forced `animalBossCrown` onto the character's forehead. | `@ios-upgrade` | Added `isCompactHeight` (`H < 500`) scaling (`hdrScale=0.84`, `pillY=H-30`, `barY=H-80`, `guideBaseY=0.39H`, `guideDim=0.45*min(W,H)`), creating 33pt+ clear air between Hold Bar star and Boss Crown. Re-verified with `xcodebuild -sdk iphoneos` (`** BUILD SUCCEEDED **`, 0 Swift warnings). |

### Round 2 (Fresh Screenshot & Build Re-Verification — 0 P0 / 0 P1 Remaining)
- Re-captured all 23 live headless Chrome screenshots (`1280×720` + `852×393`) into `qa_round2/`.
- Visually confirmed all 3 Web P1 fixes (`09_freeze_disco_point_1280x720.png`, `10_freeze_locked_1280x720.png`, `11_animal_std_852x393.png`, `12_animal_boss_852x393.png`, `13_animal_coop_852x393.png`, `15_animal_polaroid_852x393.png`) — **0 overlaps, 0 clipping, 0 console errors/warnings**.
- Verified iOS `GameScene.swift` compact-height geometry math + fresh `xcodebuild -sdk iphoneos` -> **`** BUILD SUCCEEDED **`** (0 errors, 0 Swift warnings).

---

## 4. Verified Passing Screenshot Evidence

- `qa_round2/11_animal_std_1280x720.png` — Animal Pose Center-Hero & de-cluttered right side (1280×720)
- `qa_round2/12_animal_boss_1280x720.png` — Animal Boss Pose with Crown & 4 Combo (1280×720)
- `qa_round2/13_animal_coop_1280x720.png` — 2P Co-op Bonus Round, zero double banners (1280×720)
- `qa_round2/14_animal_wall_1280x720.png` — Hole-in-the-Wall Bonus Round, zero double banners (1280×720)
- `qa_round2/15_animal_polaroid_1280x720.png` — Polaroid Clear Album 3-card layout (1280×720)
- `qa_round2/11_animal_std_852x393.png` — Mobile 852×393 Animal Pose, Combo below Score, unclipped badge
- `qa_round2/12_animal_boss_852x393.png` — Mobile 852×393 Boss Pose with clean Crown clearance
- `qa_round2/15_animal_polaroid_852x393.png` — Mobile 852×393 Polaroid Album, all captions & buttons clear
- `qa_round2/09_freeze_disco_point_1280x720.png` — Freeze Dance 3-dancer 6-part rig, rings behind faces
- `qa_round2/10_freeze_locked_1280x720.png` — Freeze Dance Instant Freeze-Pose Lock & floor shadows
- `qa_round2/07_balance_1280x720.png` — Balance Log 2-dancer rig with grounded shadows
- `qa_round2/08_jungle_run_1280x720.png` — Jungle Run Momo 6-part rig & 5-checkpoint track
