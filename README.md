# 팡팡 프렌즈 (PangPang Friends) — 4·6세 유아용 카메라 모션 게임

아이폰/아이패드/맥북의 전면 카메라로 **별도 컨트롤러 없이 온몸으로 즐기는 Wii 스타일 1~2인 유아 모션 게임** 프로토타입입니다.

## 폴더 구조
```text
kids1/
├── index.html              # 앱 진입점 (홈·놀이선택·인원확인·인게임·클리어·설정)
├── src/
│   ├── styles.css          # 아이폰 가로 / TV 투영 미니멀 UI 스타일
│   ├── sound.js            # Web Audio API Wii 스타일 효과음·BGM 엔진
│   ├── tracker.js          # MediaPipe 2인 실시간 포즈/손 추적 (+ 마우스/터치 폴백)
│   ├── games.js            # 미니게임 3종 (과일 팡팡 / 풍선 배구 / 얼음 땡!)
│   └── main.js             # 전체 화면 전환·인원 확인·카운트다운·설정 상태 관리
└── doc/
    ├── ui_ux_design_spec.md      # UI/UX 상세 설계서
    ├── fruit_pop_2p_sample.mp4   # 12초 샘플 데모 영상
    └── images/                   # 아이폰 가로 화면 시안 5종
```

## 바로 실행해 보기

카메라(`getUserMedia`)는 로컬 서버(`localhost` 또는 HTTPS)에서 동작합니다.

```bash
cd /Users/kwon/codes/yong-workspace/games/kids1
python3 -m http.server 8080
```

브라우저에서 `http://localhost:8080` 으로 접속하면 바로 플레이할 수 있습니다!
* **카메라가 없거나 권한을 거부한 경우**에도 마우스/터치로 모모(P1)·포포(P2) 손을 움직여 모든 게임을 바로 테스트할 수 있습니다.
* **거실 TV에서 아이들과 놀 때**: 맥북/아이패드를 HDMI 또는 AirPlay로 TV에 미러링하고 우상단 **전체 화면 버튼**을 눌러주세요.
