# 「팡팡 프렌즈」 상용 2D 관절 리깅 & 리듬 안무 공리계 (Commercial 2D Puppet Rigging & Rhythm Choreography Axioms)

> 본 문서는 **Just Dance Kids**, **Rhythm Heaven**, **Rayman Legends (UbiArt Framework)**, **Live2D / Spine 2D** 등 상용 2D 리듬·캐릭터 애니메이션 엔진의 핵심 원리를 정립하고, 이를 본 프로젝트의 **Web (`src/danceRig.js`, `src/pixiRenderer.js`, `src/games.js` — PixiJS)** 및 **iOS (`GameScene.swift` — SpriteKit)** 양대 플랫폼에 **1:1 수학적 동일성**으로 구현하기 위한 **7대 공리(Core Axioms)** 및 표준 상수 명세를 정의합니다.

---

## 0. 플랫폼 간 좌표계·회전 부호 정합 규약 (Cross-Platform Coordinate Parity)

PixiJS(Web, Y-Down)와 SpriteKit(iOS, Y-Up)은 Y축 방향과 양(+)의 회전 방향이 정반대입니다. 양쪽 구현이 **픽셀·각도 단위로 100% 동일한 동작**을 출력하도록, 본 문서의 모든 수식은 **표준 논리 좌표계(Canonical Y-Up, CCW-Positive)** 로 정의하며 각 엔진 적용 시 아래 변환 공식을 기계적으로 적용합니다.

| 물리량 | 표준 논리 공간 (Canonical) | iOS SpriteKit (Y-Up) | Web PixiJS (Y-Down) |
| :--- | :---: | :---: | :---: |
| **정규화 앵커** $(a_x, a_y)$ | $(a_x, a_y) \in [0,1]^2$ (좌하단 원점) | `anchorPoint = CGPoint(x: ax, y: ay)` | `anchor.set(ax, 1.0 - ay)` |
| **상대 오프셋** $(o_x, o_y)$ | $(o_x \cdot S,\; o_y \cdot S)$ ($+y$ = 위) | `position = CGPoint(x: ox*S, y: oy*S)` | `position.set(ox*S, -oy*S)` |
| **점프/바운스** $\text{hopY}$ | $\text{hopY} \ge 0$ 이면 위로 도약 | `pelvis.position.y = +hopY * S` | `pelvis.y = -hopY * S` |
| **관절 회전각** $\theta$ (rad) | $+\theta$ = 반시계(CCW), $-\theta$ = 시계(CW) | `node.zRotation = +theta` | `node.rotation = -theta` |
| **부피 스쿼시** $(s_x, s_y)$ | $s_x \cdot s_y = 1.0$ | `pelvis.xScale = sx; pelvis.yScale = sy` | `pelvis.scale.set(sx, sy)` |

> **회전 부호 직관 검증 (Sign Sanity Check)**
> * **왼팔 (`armL`, 화면 왼쪽)**: 어깨 피벗에서 왼쪽(`-x`)으로 뻗어 있으므로, 팔을 하늘로 **들어 올리려면 시계 방향(CW)** 회전 → 논리 각도 $\theta_{\text{armL}} < 0$ (예: `-1.2 rad`).
>   * SpriteKit: `zRotation = -1.2` (CW → 위로 들림) / PixiJS: `rotation = +1.2` (CW → 위로 들림). **완전 일치!**
> * **오른팔 (`armR`, 화면 오른쪽)**: 어깨 피벗에서 오른쪽(`+x`)으로 뻗어 있으므로, 팔을 하늘로 **들어 올리려면 반시계 방향(CCW)** 회전 → 논리 각도 $\theta_{\text{armR}} > 0$ (예: `+1.2 rad`).
>   * SpriteKit: `zRotation = +1.2` (CCW → 위로 들림) / PixiJS: `rotation = -1.2` (CCW → 위로 들림). **완전 일치!**

---

## 1. 7대 관절 리깅 & 리듬 안무 공리 (Core Axioms)

### 공리 1. 계층적 관절 트리 & 정규화 피벗 공리 (Hierarchical Joint Tree & Normalized Anchors)
> **"모든 파츠는 골반(Pelvis)을 중심으로 회전·압축되며, 엔진에 무관하게 동일한 렌더링 계층 순서를 보장한다."**

#### 1.1 노드 계층 트리 (Node Hierarchy)
PixiJS에서 `PIXI.Sprite`의 자식 노드는 음수 `zIndex`를 부여해도 부모 스프라이트 텍스처 뒤에 그려지지 않는 특성이 있으므로, **몸통 스프라이트(`bodySprite`)를 포함한 6개 파츠 모두를 변환 전용 컨테이너 `pelvis` (`PIXI.Container` / `SKNode`)의 형제 자식으로 배치**합니다.

```text
root (전역 위치 x, y / 전역 scale / 좌우 반전)
 └── pelvis (변환 전용 컨테이너: hopY, squash sx/sy, 몸통 기울기 θ_body, sortableChildren = true)
      ├── legL       (z = -2)
      ├── legR       (z = -2)
      ├── armL       (z = -1)
      ├── armR       (z = -1)
      ├── bodySprite (z =  0)
      └── head       (z = +1)
```

* **명시적 Z-Order 불변식**:
  $$z(\text{legL}) = z(\text{legR}) = -2 \;<\; z(\text{armL}) = z(\text{armR}) = -1 \;<\; z(\text{bodySprite}) = 0 \;<\; z(\text{head}) = +1$$

#### 1.2 파츠별 정규화 피벗·크기·오프셋 표준 상수표
기준 크기 $S = \text{baseSize}$ (조립 완료 시 캐릭터의 기준 높이 픽셀, 예: `160 ~ 240 px`)에 대한 비율로 모든 치수를 정규화합니다.

| 파츠 키 | 텍스처 파일명 (`{char}` $\in$ `dino, momo, popo`) | Z-Order | SpriteKit 앵커 (Y-Up) | PixiJS 앵커 (Y-Down) | 파츠 크기 ($W/S, H/S$) | `pelvis` 기준 오프셋 ($o_x, o_y$, Y-Up) |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| `bodySprite` | `rig_{char}_body.png` (`256×256`) | `0` | `(0.50, 0.45)` | `(0.50, 0.55)` | `(0.52, 0.52)` | `( 0.00,  0.00)` |
| `head` | `rig_{char}_head.png` (`256×256`) | `+1` | `(0.50, 0.18)` | `(0.50, 0.82)` | `(0.62, 0.62)` | `( 0.00, +0.20)` |
| `armL` (화면 좌) | `rig_{char}_arm_l.png` (`160×160`) | `-1` | `(0.78, 0.80)` | `(0.78, 0.20)` | `(0.34, 0.34)` | `(-0.20, +0.11)` |
| `armR` (화면 우) | `rig_{char}_arm_r.png` (`160×160`) | `-1` | `(0.22, 0.80)` | `(0.22, 0.20)` | `(0.34, 0.34)` | `(+0.20, +0.11)` |
| `legL` (화면 좌) | `rig_{char}_leg_l.png` (`160×160`) | `-2` | `(0.50, 0.82)` | `(0.50, 0.18)` | `(0.32, 0.32)` | `(-0.11, -0.17)` |
| `legR` (화면 우) | `rig_{char}_leg_r.png` (`160×160`) | `-2` | `(0.50, 0.82)` | `(0.50, 0.18)` | `(0.32, 0.32)` | `(+0.11, -0.17)` |

> **참고**: `head`의 피벗 `(0.50, 0.18)`은 턱·목 관절 하단 중앙, `armL/R`의 `(0.78, 0.80)` / `(0.22, 0.80)`은 각각 우상단/좌상단 어깨 관절, `legL/R`의 `(0.50, 0.82)`는 고관절 상단 중앙에 정확히 일치합니다.

---

### 공리 2. 비트-동기 조화 합성 공리 (128 BPM Beat-Locked Harmonic Synthesis)
> **"모든 관절은 임의의 타이머가 아니라 128 BPM 음악의 위상 $\phi$ 에서 파생된 조화 함수로 호흡한다."**

기본 템포 $\text{BPM}_0 = 128$ (라운드 진행에 따라 동적 변속 가능). 템포가 바뀔 때 위상이 튀지 않도록 **누적 위상 적분** 방식을 사용합니다:

$$\phi(t) = \phi(t - \Delta t) + \Delta t \cdot \frac{\text{BPM}}{60} \cdot 2\pi \qquad \left(\text{일정 BPM 시 } \phi(t) = t \cdot \frac{\text{BPM}}{60} \cdot 2\pi + \phi_0\right)$$

* 캐릭터별 위상 오프셋 $\phi_0$: 다인 무대(얼음 땡 3인 댄서)에서 기계적인 복붙 느낌을 없애되 박자를 맞추려면 $\phi_0 \in \{0.00,\; 0.25,\; -0.25\}\text{ rad}$ (또는 합동 칼군무 시 $0$)를 부여합니다.
* **킥 드럼 임펄스 (Kick Impulse)**:
  $$\text{beatPulse}(\phi) = \max\!\left(0,\; \cos\!\left(\frac{\phi}{2}\right)\right)^4$$
  매 2박자 강박마다 날카롭게 치솟았다가 부드럽게 감쇠하는 타격형 파형($[0, 1]$)을 생성합니다.
* **매 박자 바운스 파형 (Every-Beat Pulse)**:
  $$\text{stepPulse}(\phi) = \left|\sin\!\left(\frac{\phi}{2}\right)\right| \in [0, 1]$$
* **부드러운 좌우 스웨이 (Smooth Ease-In-Out Sway)**:
  $$u(\phi) = \frac{\sin(\phi / 2) + 1}{2}, \qquad \text{smoothSway}(\phi) = 2 \cdot u^2(3 - 2u) - 1 \in [-1, 1]$$

---

### 공리 3. 부피 보존 스쿼시-스트레치 공리 (Volume-Preserving Squash & Stretch)
> **"말랑한 3D 클레이 인형은 찌그러질 때 옆으로 퍼지고, 도약할 때 세로로 늘어나되 부피(면적)는 항상 1.0을 보존한다."**

수직 신축 드라이브 $a \in [-1.5, +1.5]$ 와 탄성 계수 $k$ (기본 댄스 $k = 0.14$, 점프 착지/웅크림 $k = 0.18$)에 대해 `pelvis` 스케일을 다음과 같이 계산합니다:

$$s_y = \operatorname{clamp}\!\left(1.0 + k \cdot a,\;\; 0.74,\;\; 1.30\right), \qquad s_x = \frac{1.0}{s_y}$$

$$\implies s_x \cdot s_y = 1.0 \quad (\text{엄밀한 면적·부피 보존})$$

* **도약 정점 ($a > 0$)**: $s_y > 1, s_x < 1$ → 날렵하게 위로 쭉 뻗는 스트레치.
* **비트 착지·웅크림 ($a < 0$)**: $s_y < 1, s_x > 1$ → 통통하게 옆으로 퍼지는 스쿼시.

---

### 공리 4. 위상 지연 후속 동작 공리 (Phase-Lag Secondary Motion / Disney Follow-Through)
> **"무거운 머리와 귀·장식은 몸통보다 반 박자 살짝 늦게 따라오며 살아있는 탄성을 만든다."**

별도의 스프링-댐퍼 물리 솔버 없이도 디즈니 12원칙 중 **후속 동작(Follow-Through & Overlapping Action)** 을 60fps 제로 비용으로 구현하기 위해, 머리의 조화 함수는 몸통 위상 $\phi$ 보다 **$\Delta\phi = -0.35\text{ rad}$ 지연된 위상**에서 평가합니다:

$$\phi_{\text{head}} = \phi + \Delta\phi, \qquad \Delta\phi = -0.35\text{ rad}$$

* **머리 회전 후속 합성**:
  $$\theta_{\text{head,final}} = \theta_{\text{head}}(\phi_{\text{head}}) + 0.30 \cdot \theta_{\text{body}}(\phi_{\text{head}})$$
* **머리 미세 상하 탄성 밥(Bob)**:
  $$o_{y,\text{head}}(\phi) = 0.20 + 0.022 \cdot \sin(\phi_{\text{head}}) \cdot \text{amp}$$
  몸통이 먼저 내려찍고 올라올 때 머리가 찰나 늦게 출렁이며, 3D 클레이 토이 특유의 말랑한 질감을 극대화합니다.

---

### 공리 5. 4종 8박자 자동 순환 안무 상태 머신 & 게임플레이 전용 모드 (4-Routine 8-Beat Choreography & Gameplay Modes)
> **"안무는 8박자마다 자동으로 순환하며, 모든 루틴·모드 전환은 지수 보간(Cross-Fade)으로 단 한 프레임도 튀지 않는다."**

#### 5.1 포즈 상태 벡터 및 지수 크로스페이드 블렌딩
모든 안무와 게임 모드는 동일한 8차원 목표 포즈 벡터 $\mathbf{P}_{\text{target}}$ 를 출력합니다:
$$\mathbf{P} = \bigl(\theta_{\text{body}},\; \theta_{\text{head}},\; \theta_{\text{armL}},\; \theta_{\text{armR}},\; \theta_{\text{legL}},\; \theta_{\text{legR}},\; \text{hopY},\; a_{\text{squash}}\bigr)$$

현재 출력 포즈 $\mathbf{P}_{\text{cur}}$ 는 매 프레임 목표 포즈로 부드럽게 수렴합니다:
$$\alpha = \min\!\left(1.0,\;\; 8.0 \cdot \Delta t\right), \qquad \mathbf{P}_{\text{cur}} \leftarrow \mathbf{P}_{\text{cur}} + \alpha \cdot \left(\mathbf{P}_{\text{target}} - \mathbf{P}_{\text{cur}}\right)$$
* `blendRate = 8.0 * dt` (약 `0.15~0.20초` 내 자연스러운 크로스페이드 완료, 60fps 기준 프레임당 ~13.3% 수렴).

#### 5.2 4종 8박자 자동 순환 댄스 루틴 (`mode = "dance"`)
1박자 = $2\pi\text{ rad}$ 이므로 **8박자 = $16\pi\text{ rad}$** 마다 루틴 인덱스 $r$ 이 자동 순환합니다:
$$r = \left\lfloor \frac{\phi}{16\pi} \right\rfloor \bmod 4 \in \{0, 1, 2, 3\}$$

아래 수식에서 $A = \text{amp}$ (공리 6의 에너지 진폭 계수), $\phi_h = \phi - 0.35$, $p = \text{beatPulse}(\phi) = \max(0, \cos(\phi/2))^4$ 입니다.

1. **Routine 0 — `bounce_step` (바운스 스텝: 리드미컬한 무릎 바운스 & 팔 흔들기)**
   $$\begin{aligned}
   \text{hopY} &= 0.060 \cdot |\sin(\phi/2)| \cdot A, & a_{\text{squash}} &= (|\sin(\phi/2)| - 0.55) \cdot 1.10 \cdot A \\
   \theta_{\text{body}} &= 0.10 \cdot \text{smoothSway}(\phi) \cdot A, & \theta_{\text{head}} &= 0.14 \cdot \sin(\phi_h / 2) \cdot A \\
   \theta_{\text{armL}} &= (-0.35 + 0.55 \cdot \sin(\phi/2)) \cdot A, & \theta_{\text{armR}} &= (+0.35 + 0.55 \cdot \sin(\phi/2)) \cdot A \\
   \theta_{\text{legL}} &= +0.22 \cdot \sin(\phi/2) \cdot A, & \theta_{\text{legR}} &= -0.22 \cdot \sin(\phi/2) \cdot A
   \end{aligned}$$

2. **Routine 1 — `disco_wave` (디스코 웨이브: 번갈아 하늘 찌르기 & 힙 스웨이)**
   $$\begin{aligned}
   \text{hopY} &= 0.055 \cdot p \cdot A, & a_{\text{squash}} &= (p - 0.35) \cdot 1.20 \cdot A \\
   \theta_{\text{body}} &= 0.16 \cdot \text{smoothSway}(\phi) \cdot A, & \theta_{\text{head}} &= -0.18 \cdot \sin(\phi_h / 2) \cdot A \\
   \theta_{\text{armL}} &= (-0.65 - 0.65 \cdot \sin(\phi/2)) \cdot A, & \theta_{\text{armR}} &= (+0.65 - 0.65 \cdot \sin(\phi/2)) \cdot A \\
   \theta_{\text{legL}} &= +0.18 \cdot \cos(\phi/2) \cdot A, & \theta_{\text{legR}} &= -0.18 \cdot \cos(\phi/2) \cdot A
   \end{aligned}$$

3. **Routine 2 — `jump_fever` (점프 피버: 강박 별 점프 & 큰 스쿼시-스트레치)**
   $$j(\phi) = \max\!\left(0,\; \sin(\phi/2)\right)^{1.6}$$
   $$\begin{aligned}
   \text{hopY} &= 0.160 \cdot j(\phi) \cdot A, & a_{\text{squash}} &= (1.60 \cdot j(\phi) - 0.55) \cdot A \\
   \theta_{\text{body}} &= 0.08 \cdot \cos(\phi/2) \cdot A, & \theta_{\text{head}} &= 0.12 \cdot \sin(\phi_h) \cdot A \\
   \theta_{\text{armL}} &= (-0.30 - 0.95 \cdot j(\phi)) \cdot A, & \theta_{\text{armR}} &= (+0.30 + 0.95 \cdot j(\phi)) \cdot A \\
   \theta_{\text{legL}} &= -0.32 \cdot j(\phi) \cdot A, & \theta_{\text{legR}} &= +0.32 \cdot j(\phi) \cdot A
   \end{aligned}$$

4. **Routine 3 — `clap_shuffle` (박수 셔플: 매 박자 더블타임 박수 & 경쾌한 스텝)**
   $$c(\phi) = 0.5 + 0.5 \cdot \sin(\phi)$$
   $$\begin{aligned}
   \text{hopY} &= 0.070 \cdot |\sin(\phi)| \cdot A, & a_{\text{squash}} &= (|\sin(\phi)| - 0.50) \cdot 0.95 \cdot A \\
   \theta_{\text{body}} &= 0.12 \cdot \sin(\phi/2) \cdot A, & \theta_{\text{head}} &= 0.15 \cdot \cos(\phi_h) \cdot A \\
   \theta_{\text{armL}} &= (+0.25 - 0.85 \cdot c(\phi)) \cdot A, & \theta_{\text{armR}} &= (-0.25 + 0.85 \cdot c(\phi)) \cdot A \\
   \theta_{\text{legL}} &= +0.28 \cdot \sin(\phi) \cdot A, & \theta_{\text{legR}} &= -0.28 \cdot \sin(\phi) \cdot A
   \end{aligned}$$

#### 5.3 재사용 게임플레이 전용 모드 (2종)

* **모드 A — `balance` (외나무다리 균형잡기 · Game 7)**
  * 입력: 정규화 기울기 $\tau = \operatorname{clamp}(\text{tilt}, -1, +1)$ ($+\tau$: 오른쪽 기울어짐, $-\tau$: 왼쪽 기울어짐).
  * 양팔을 넓게 벌려 기울기 반대 방향으로 균형을 잡으며, 머리는 수평을 유지하려 역보정합니다:
  $$\begin{aligned}
  \text{hopY} &= 0.015 \cdot |\sin(\phi/2)|, & a_{\text{squash}} &= -0.10 \cdot |\tau| \\
  \theta_{\text{body}} &= -0.28 \cdot \tau, & \theta_{\text{head}} &= +0.14 \cdot \tau + 0.06 \cdot \sin(\phi_h / 2) \\
  \theta_{\text{armL}} &= -0.25 + 0.55 \cdot \tau + 0.12 \cdot \sin(\phi), & \theta_{\text{armR}} &= +0.25 + 0.55 \cdot \tau - 0.12 \cdot \sin(\phi) \\
  \theta_{\text{legL}} &= -0.14 + 0.08 \cdot \sin(\phi/2), & \theta_{\text{legR}} &= +0.14 - 0.08 \cdot \sin(\phi/2)
  \end{aligned}$$

* **모드 B — `jungle` (정글 모험 · Game 5: 3가지 서브 액션)**
  1. **`jungle_run` (하이니 달리기)**: 위상 $\psi = 1.6 \cdot \phi$ 로 경쾌한 전력 질주 사이클 생성.
     $$\begin{aligned}
     \text{hopY} &= 0.065 \cdot |\sin(\psi)|, & a_{\text{squash}} &= (|\sin(\psi)| - 0.50) \cdot 0.70 \\
     \theta_{\text{body}} &= -0.14 + 0.05 \cdot \sin(2\psi), & \theta_{\text{head}} &= +0.08 + 0.07 \cdot \sin(\psi - 0.35) \\
     \theta_{\text{armL}} &= +0.75 \cdot \sin(\psi), & \theta_{\text{armR}} &= -0.75 \cdot \sin(\psi) \\
     \theta_{\text{legL}} &= -0.68 \cdot \sin(\psi), & \theta_{\text{legR}} &= +0.68 \cdot \sin(\psi)
     \end{aligned}$$
  2. **`jungle_squat` (낮게 웅크려 피하기)**: 중심을 확 낮추고 양팔을 벌려 덩굴 아래를 통과.
     $$\begin{aligned}
     \text{hopY} &= -0.14, & a_{\text{squash}} &= -1.15 \quad (s_y \approx 0.84,\; s_x \approx 1.19) \\
     \theta_{\text{body}} &= -0.18, & \theta_{\text{head}} &= +0.16 \\
     \theta_{\text{armL}} &= -0.42, & \theta_{\text{armR}} &= +0.42 \\
     \theta_{\text{legL}} &= -0.38, & \theta_{\text{legR}} &= +0.38
     \end{aligned}$$
  3. **`jungle_jump` (축하 별 점프)**: 양팔과 다리를 크게 별 모양으로 펼치며 도약.
     $$\begin{aligned}
     \text{hopY} &= +0.14, & a_{\text{squash}} &= +0.95 \quad (s_y \approx 1.13,\; s_x \approx 0.88) \\
     \theta_{\text{body}} &= 0.05 \cdot \sin(\phi), & \theta_{\text{head}} &= -0.06 \\
     \theta_{\text{armL}} &= -1.25, & \theta_{\text{armR}} &= +1.25 \\
     \theta_{\text{legL}} &= -0.40, & \theta_{\text{legR}} &= +0.40
     \end{aligned}$$

---

### 공리 6. 플레이어 에너지 연동 & 순간 얼음 자세 고정 공리 (Energy Modulation & Instant Freeze-Pose Lock)
> **"아이가 신나게 움직일수록 마스코트도 더 크게 춤추며, '얼음!' 순간에는 정지 이미지로 바뀌는 대신 방금 취하던 우스꽝스러운 자세 그대로 얼어붙는다."**

#### 6.1 실시간 플레이어 에너지 증폭
플레이어 움직임 에너지 $E \in [0, 1]$ 에 따라 댄스 진폭 계수 $\text{amp}$ 를 실시간 변조합니다:
$$\text{amp} = 0.65 + 0.65 \cdot \operatorname{clamp}(E,\; 0,\; 1) \in [0.65,\; 1.30]$$
* $E = 0$ (휴식/관찰): `0.65x` 기본 흥겨움 유지 (화면이 죽지 않음).
* $E = 1$ (격렬한 댄스): `1.30x` (2배 증폭) — 점프 높이와 팔 스윙이 즉각 커져 즉각적 반응성(Agency) 제공.

#### 6.2 순간 얼음 자세 고정 (Instant Freeze-Pose Lock)
* 상태 전이 `frozen: false → true` 가 발생하는 **정확한 그 프레임**에 현재 관절 각도 벡터를 스냅샷 저장합니다:
  $$\mathbf{P}_{\text{frozen}} \leftarrow \mathbf{P}_{\text{cur}}$$
* `frozen == true` 인 동안에는 안무 위상 $\phi$ 와 보간을 일시 정지하고 모든 관절을 $\mathbf{P}_{\text{frozen}}$ 에 고정합니다.
  * 점프 정점이나 디스코 찌르기 도중에 "얼음!"이 걸리면, 그 자세 그대로 공중·포즈가 굳어 유아에게 큰 웃음과 명확한 게임 규칙 인지를 제공합니다.

#### 6.3 움직임 경고 미세 떨림 (32 Hz Micro-Tremor)
`frozen == true` 상태에서 플레이어가 미세하게 움직여 경고 상태(`wiggling == true`)가 되면, 고정된 $\mathbf{P}_{\text{frozen}}$ 위에 **32 Hz 고주파 떨림**을 중첩합니다:
$$\delta_{\text{wiggle}}(t) = 0.06 \cdot \sin(2\pi \cdot 32 \cdot t)\;\;(\pm 0.06\text{ rad})$$
$$\begin{aligned}
\theta'_{\text{body}} &= \theta_{\text{body,frozen}} + 1.0 \cdot \delta_{\text{wiggle}}(t) \\
\theta'_{\text{head}} &= \theta_{\text{head,frozen}} + 1.2 \cdot \delta_{\text{wiggle}}(t) \\
\theta'_{\text{armL/R}} &= \theta_{\text{armL/R,frozen}} \pm 1.3 \cdot \delta_{\text{wiggle}}(t) \\
\Delta x_{\text{pelvis}} &= 0.012 \cdot S \cdot \sin(2\pi \cdot 32 \cdot t)
\end{aligned}$$
아이가 "어! 인형이 부들부들 떨린다! 얼른 멈춰야지!" 하고 직관적으로 인지할 수 있습니다.

---

### 공리 7. 60fps 제로-할당 배칭 공리 (Zero-Allocation 60fps Node Rig)
> **"매 프레임 단 하나의 노드·객체·경로도 힙에 새로 할당하지 않으며, 파츠 리소스가 누락되어도 게임은 절대 깨지지 않는다."**

1. **초기화 시 1회 생성 (One-Time Setup)**:
   * `DancePuppetRig` 생성 시 `root`, `pelvis`, 6개 파츠 스프라이트(`body`, `head`, `armL`, `armR`, `legL`, `legR`), 그리고 가변 포즈 구조체(`currentPose`, `targetPose`, `frozenPose`)를 **단 1회** 할당합니다.
2. **프레임 루프 제로-할당 (Zero Per-Frame Heap Allocation)**:
   * `update(dt, options)` 내부에서는 오직 기존 노드의 스칼라 수치(`x`, `y`, `rotation/zRotation`, `scale`)만 덮어씁니다.
   * 매 프레임 `new Object()`, `Array`, `SKNode`, `PIXI.Sprite`, `CGPath` 생성을 **엄격히 금지**합니다 (`doc/performance_development_guide.md` 준수).
3. **온디맨드 텍스처 로딩 (On-Demand Texture Residency)**:
   * 총 18개 파츠 텍스처(`rig_{dino,momo,popo}_{head,body,arm_l,arm_r,leg_l,leg_r}.png`)는 필요한 게임(`.freeze`, `.jungle`, `.balance`) 진입 시에만 로드하며, iOS에서는 `textureNames(for:)` 매핑에 등록해 불필요한 VRAM 점유를 방지합니다.
4. **안전한 단일 스프라이트 폴백 (Graceful Single-Sprite Fallback)**:
   * 6개 파츠 텍스처 중 **단 하나라도 누락(`null` / `nil`)**된 경우, 즉시 `fallbackMode = true` 로 전환하여 단일 전신 스프라이트(`dino.png`, `momo.png`, `popo.png`)를 `pelvis`에 마운트합니다.
   * 폴백 모드에서도 공리 2(바운스 `hopY`), 공리 3(부피 보존 스쿼시 `sx/sy`), 공리 6(얼음 고정 및 32Hz 떨림)은 `pelvis` 레벨에서 그대로 작동하여 시각적 결함이나 크래시가 절대 발생하지 않습니다.

---

## 2. 표준 인터페이스 요약 (`DancePuppetRig` API Contract)

Web(`src/danceRig.js`)과 iOS(`GameScene.swift`) 양측 구현체는 아래 개념적 인터페이스를 공유합니다:

| 메서드 / 프로퍼티 | 시그니처 및 역할 |
| :--- | :--- |
| **생성자 (`init`)** | `(characterId: "dino" \| "momo" \| "popo", baseSize: number, phaseOffset?: number)` — 6파츠 조립 또는 단일 스프라이트 폴백 |
| **`update(dt, state)`** | `state = { mode: "dance" \| "balance" \| "jungle", subAction?: "run" \| "squat" \| "jump", bpm?: 128, energy?: 0..1, tilt?: -1..1, frozen?: bool, wiggling?: bool, routineOverride?: 0..3 \| null }` |
| **`setBaseSize(size)`** | 화면 리사이즈 시 파츠 크기·오프셋 재계산 (노드 재생성 없음) |
| **`resetPhase(offset?)`** | 라운드 시작 시 위상 $\phi$ 및 얼음 스냅샷 초기화 |
| **적용 게임 매핑** | **Game 3 (`freeze` 얼음 땡!)**: Dino(1R), Momo(2R), Popo(4R) + 클리어 합동 댄스<br>**Game 5 (`jungle` 정글 모험)**: Momo (`jungle_run` / `jungle_squat` / `jungle_jump`)<br>**Game 7 (`balance` 외나무다리)**: Momo & Popo (`balance` + 실시간 `tilt`) |
