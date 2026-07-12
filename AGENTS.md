# AGENTS.md

## 1. 프로젝트 개요

프로젝트명: **60초의 공범**  
영문 작업명: **Sixty-Second Accomplice**  
엔진: **Godot 4.x**  
언어: **GDScript**  
형태: **2D top-down single-player time-loop action puzzle roguelite**

이 게임의 핵심은 플레이어가 한 회차에서 수행한 행동을 기록하고, 다음 회차에서 과거의 자신인 `Ghost`가 그 행동을 재생하도록 만드는 것이다.

현재 최우선 목표는 완성형 게임이 아니라 아래 장면이 안정적으로 동작하는 prototype (프로토타입)을 만드는 것이다.

> 첫 번째 회차의 Ghost가 pressure plate (압력판)를 누르고 있는 동안, 현재 플레이어가 열린 문을 통과하여 목표물을 획득하고 출구로 탈출한다.

게임 규칙은 `docs/game_design.md`, 시스템 구조는 `docs/architecture.md`를 따른다.

---

## 2. Codex 작업 원칙

Codex는 코드를 수정하기 전에 반드시 다음 순서로 작업한다.

1. 현재 저장소 구조와 관련 파일을 읽는다.
2. 요청 범위와 영향을 받는 시스템을 요약한다.
3. 최소 변경 계획을 세운다.
4. 기존 구조를 유지하면서 구현한다.
5. 실행 또는 정적 검증을 수행한다.
6. 변경 파일, 검증 결과, 남은 위험을 보고한다.

한 번에 여러 핵심 시스템을 동시에 구현하지 않는다. 요청 범위를 넘는 기능은 임의로 추가하지 않는다.

---

## 3. 기술 기준

### 3.1 Godot

- Godot 4.x API만 사용한다.
- Godot 3.x 문법이나 deprecated API를 사용하지 않는다.
- 기본 물리 프레임은 프로젝트 설정을 따른다.
- 입력 동작은 하드코딩된 키가 아니라 `Input Map` action을 사용한다.
- scene과 script의 책임을 분리한다.
- node path에 과도하게 의존하지 않는다.

### 3.2 GDScript

- 가능한 모든 변수, 매개변수, 반환값에 static typing을 사용한다.
- 공개 설정값은 `@export`를 사용한다.
- 외부에서 읽기만 해야 하는 값은 setter를 제한한다.
- 숫자와 문자열 magic value를 반복해서 사용하지 않는다.
- 한 script는 한 가지 주요 책임만 가진다.
- 긴 함수는 의미 단위의 작은 함수로 분리한다.
- 불필요한 singleton과 global state를 만들지 않는다.
- 오류를 숨기기 위한 빈 `pass`, 무조건적인 null 무시는 금지한다.

### 3.3 이름 규칙

- 파일명: `snake_case.gd`
- class 이름: `PascalCase`
- 변수와 함수: `snake_case`
- signal: 과거형 또는 사건형 이름
- stable object ID: 소문자 snake_case 문자열

예시:

```gdscript
class_name TimelineManager

signal loop_started(loop_index: int)
signal loop_ended(loop_index: int)

@export var loop_duration_seconds: float = 20.0
var current_loop_index: int = 0
```

---

## 4. 프로젝트 구조

권장 구조는 다음과 같다.

```text
60_seconds_accomplice/
├── project.godot
├── README.md
├── AGENTS.md
├── docs/
│   ├── game_design.md
│   └── architecture.md
├── scenes/
│   ├── main/
│   ├── player/
│   ├── ghost/
│   ├── enemies/
│   ├── levels/
│   ├── objects/
│   └── ui/
├── scripts/
│   ├── core/
│   ├── player/
│   ├── ghost/
│   ├── enemies/
│   ├── objects/
│   └── ui/
├── resources/
├── assets/
└── tests/
```

기존 저장소에 이미 다른 구조가 있다면 무조건 재배치하지 말고, 요청 범위 안에서 점진적으로 정리한다.

---

## 5. 핵심 아키텍처 규칙

### 5.1 TimelineManager

`TimelineManager`는 시간선의 상태만 관리한다.

담당:

- 회차 시작 및 종료
- 남은 시간
- 회차 번호
- recording 저장
- Ghost 생성 요청
- loop reset orchestration

금지:

- 플레이어 이동 구현
- 문, 스위치, 적의 세부 로직
- 직접적인 UI 그리기
- 특정 level node path 하드코딩

### 5.2 Recording

prototype 단계의 replay 방식은 hybrid replay를 사용한다.

- 이동과 방향: 일정 주기의 position snapshot 재생
- 상호작용과 공격: timestamp 기반 event 재생

기록 데이터는 현재 회차 동안 메모리에 저장한다. prototype에서는 영구 저장하지 않는다.

### 5.3 Ghost

Ghost는 저장된 recording을 재생하는 actor다.

- 현재 플레이어와 충돌하지 않는다.
- scene object와 직접 결합하지 않는다.
- 상호작용 대상은 stable object ID로 찾는다.
- replay 데이터가 유효하지 않을 경우 crash하지 않고 warning을 남긴다.

### 5.4 Interactable

상호작용 가능한 object는 공통 계약을 따른다.

필수 개념:

- `object_id`
- 현재 상호작용 가능 여부
- `interact(actor)` 또는 동등한 공통 API

문, 압력판, 목표물, 출구마다 완전히 다른 호출 방식을 만들지 않는다.

### 5.5 Stable Object ID

상호작용 대상은 scene tree node path가 아니라 stable ID를 사용한다.

예:

```text
pressure_plate_entry
security_door_a
objective_core
escape_zone
```

- 같은 level 안에서 ID는 중복될 수 없다.
- runtime registry가 중복을 발견하면 명확한 오류를 출력한다.
- ID를 자동 생성한 임시 node name에 의존하지 않는다.

---

## 6. Prototype 범위

### 반드시 구현

- WASD 플레이어 이동
- 벽 충돌
- 20초 loop timer
- position과 facing 기록
- interaction event 기록
- 이전 회차 Ghost 재생
- pressure plate
- 연결된 door
- objective item
- exit zone
- loop count와 남은 시간 UI
- level reset
- 최소한의 debug logging

### 구현하지 않음

prototype 단계에서는 다음을 추가하지 않는다.

- multiplayer
- online leaderboard
- procedural generation
- Steam API
- 복잡한 skill tree
- meta progression
- 3D 전환
- inventory grid
- 다양한 무기 체계
- boss battle
- 복잡한 enemy AI
- 대규모 save system
- paid asset 의존

요청이 없는 기능을 “나중에 필요할 것 같다”는 이유로 미리 구현하지 않는다.

---

## 7. Input Map 기준

최소 action 이름:

```text
move_up
move_down
move_left
move_right
interact
restart_loop
pause
```

전투 단계가 시작되면 아래를 추가할 수 있다.

```text
shoot
dash
reload
```

script 안에서 `KEY_W`, `KEY_E` 같은 물리 키를 직접 검사하지 않는다.

---

## 8. 결정성 및 replay 안전성

- Ghost 이동은 physics 재시뮬레이션보다 기록된 위치의 interpolation을 우선한다.
- interaction은 위치만 보고 추측하지 말고 recorded event로 재생한다.
- frame rate에 따라 replay 속도가 달라지지 않아야 한다.
- replay 시간은 `_process(delta)` 누적 시간 또는 명시적 clock을 사용한다.
- pause 중에는 recording과 playback 시간이 진행되지 않아야 한다.
- level reset 후 이전 회차의 mutable state가 남지 않아야 한다.
- event는 같은 회차에서 중복 실행되지 않아야 한다.

---

## 9. Signal 사용 원칙

시스템 간 결합을 줄이기 위해 signal을 사용한다.

권장 signal:

```text
loop_started
loop_time_updated
loop_ended
recording_completed
ghost_spawned
objective_collected
level_completed
player_died
```

하지만 단순한 부모-자식 호출까지 전부 signal로 바꾸지는 않는다. 흐름을 이해하기 어려운 global event bus는 prototype에서 금지한다.

---

## 10. 오류 처리

다음 상황에서 조용히 실패하지 않는다.

- stable object ID 중복
- replay 대상 object를 찾지 못함
- recording frame이 시간순으로 정렬되지 않음
- loop duration이 0 이하
- player spawn point 누락
- required node 누락

개발 중에는 `push_error`, `push_warning`, assertion 또는 명확한 return guard를 사용한다.

사용자 입력이나 정상적인 게임 실패는 crash로 처리하지 않는다.

---

## 11. 성능 기준

prototype 목표:

- 60 FPS를 목표로 한다.
- 20초 loop, 20Hz snapshot 기준으로 Ghost 10개까지 안정적으로 재생한다.
- 매 frame 전체 scene tree를 순회하여 object ID를 찾지 않는다.
- interaction object registry는 level 시작 시 구성한다.
- recording 데이터에 Node reference를 영구 저장하지 않는다.

초기 최적화를 위해 복잡성을 높이지 말되, 명백한 O(n²) 반복 탐색은 피한다.

---

## 12. 검증 규칙

각 작업 후 가능한 범위에서 아래를 확인한다.

1. Godot project가 parse error 없이 열린다.
2. 수정된 script에 문법 오류가 없다.
3. 관련 scene의 required node가 존재한다.
4. Input Map action이 누락되지 않았다.
5. 한 회차 종료 후 Ghost가 생성된다.
6. loop reset 후 player와 level state가 초기화된다.
7. Ghost의 interaction event가 한 번만 실행된다.
8. pause와 restart가 replay clock을 깨뜨리지 않는다.

Godot executable을 사용할 수 있다면 headless 검증을 우선한다.

예:

```bash
godot --headless --path . --quit
```

프로젝트 환경에서 executable 이름이 `godot4`라면 해당 명령을 사용한다.

---

## 13. 변경 보고 형식

Codex는 작업 완료 후 다음 형식으로 보고한다.

```text
Summary
- 무엇을 구현했는지

Changed files
- 경로: 변경 목적

Validation
- 실행한 명령
- 성공/실패 결과

Known risks
- 아직 검증하지 못한 부분

Next recommended step
- 다음 한 단계만 제안
```

검증하지 않은 내용을 “완료”라고 표현하지 않는다.

---

## 14. Git 원칙

- 사용자 요청 없이 기존 history를 재작성하지 않는다.
- 대규모 삭제나 rename 전에 영향 범위를 확인한다.
- unrelated change를 함께 commit하지 않는다.
- secret, token, 개인 경로를 저장소에 넣지 않는다.
- generated import cache와 build output을 commit하지 않는다.

권장 `.gitignore` 항목:

```gitignore
.godot/
.export/
build/
.DS_Store
*.tmp
```

---

## 15. Definition of Done

prototype의 핵심 기능은 다음 조건을 모두 만족해야 완료로 본다.

- 첫 회차에서 player가 pressure plate 위로 이동할 수 있다.
- 시간이 끝나면 level이 초기 상태로 reset된다.
- 두 번째 회차에서 첫 회차 recording을 재생하는 Ghost가 생성된다.
- Ghost가 같은 시점에 pressure plate를 활성화한다.
- door가 열리고 현재 player가 통과할 수 있다.
- player가 objective를 획득하고 exit에 들어가면 성공 처리된다.
- replay가 frame rate 변화에 의해 심하게 어긋나지 않는다.
- parse error와 치명적인 runtime error가 없다.

이 기준을 만족하기 전에는 콘텐츠 확장보다 replay 안정성을 우선한다.
