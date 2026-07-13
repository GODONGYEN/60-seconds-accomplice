# 60초의 공범 — Game Design Document

문서 상태: Prototype 기준  
장르: 2D top-down time-loop action puzzle roguelite  
플랫폼: PC  
플레이 인원: 1인  
엔진: Godot 4.x

---

## 1. High Concept

플레이어는 제한된 시간 동안 보안 시설에 침입한다. 시간이 끝나거나 경비에게 붙잡히면 회차가 초기화되지만, 이전 회차의 플레이어 행동은 Ghost로 남아 다음 회차에서 그대로 재생된다.

플레이어는 여러 시간대의 자신과 협력하여 혼자서는 해결할 수 없는 잠금 장치, 경비, 레이저, 금고를 돌파하고 목표물을 훔쳐 탈출해야 한다.

핵심 문장:

> 실패한 과거도 다음 계획의 공범이 된다.

---

## 2. Player Fantasy

플레이어가 느껴야 하는 핵심 환상은 다음과 같다.

- 혼자서 완벽한 팀 작전을 설계한다.
- 과거의 실수를 새로운 전략으로 전환한다.
- 복잡한 동시 행동이 마지막 회차에 맞아떨어진다.
- 제한시간 직전에 목표물을 들고 탈출한다.
- 여러 명의 내가 화면 안에서 정교하게 협력한다.

게임은 플레이어에게 빠른 반응만 요구하는 것이 아니라, 실행 가능한 계획을 직접 만들어내는 즐거움을 제공해야 한다.

---

## 3. Design Pillars

### 3.1 실패도 진행이다

한 회차가 목표를 달성하지 못해도 그 행동은 다음 회차에서 활용할 수 있어야 한다.

### 3.2 동시 실행의 쾌감

두 명 이상의 Ghost와 현재 플레이어가 같은 순간에 서로 다른 역할을 수행하도록 설계한다.

### 3.3 짧고 강한 반복

각 loop는 짧고 명확해야 한다. 플레이어는 빠르게 시도하고, 결과를 보고, 다음 계획을 수정한다.

### 3.4 이해 가능한 결정성

퍼즐의 핵심 결과는 플레이어가 예측할 수 있어야 한다. 무작위 요소는 전투와 위험을 변화시킬 수 있지만, 핵심 장치가 이유 없이 실패해서는 안 된다.

### 3.5 화면만 봐도 규칙이 전달된다

Ghost가 버튼을 누르고 현재 플레이어가 문을 통과하는 장면만으로 게임의 핵심이 이해되어야 한다.

---

## 4. Core Gameplay Loop

```text
시설 진입
→ 제한시간 동안 행동
→ 시간 종료 또는 경비 포획
→ 행동 기록 확정
→ 스테이지 초기화
→ 이전 기록을 재생하는 Ghost 생성
→ 새로운 역할 수행
→ 목표물 획득
→ 제한시간 안에 탈출
→ 보상 및 다음 스테이지
```

prototype에서는 한 판을 다음처럼 단순화한다.

```text
20초 행동
→ Ghost 생성
→ 압력판과 문 퍼즐 해결
→ Ghost로 경비 유인
→ 목표물 획득
→ 출구 진입
```

---

## 5. Loop Rules

### 5.1 시간

- prototype loop duration: 20초
- vertical slice 목표: 30~45초
- 정식 게임 목표: 최대 60초
- 남은 시간이 5초 이하가 되면 강한 시청각 경고를 제공한다.

### 5.2 회차 종료

회차는 다음 조건에서 종료된다.

- 제한시간이 0이 됨
- 경비에게 플레이어가 포획됨
- 사용자가 loop restart 입력
- 스테이지 성공

prototype에는 체력이나 사망 시스템이 없다. 경비 포획은 실패 화면이 아니라 현재 시점까지 recording을 확정하고 다음 loop를 시작하는 진행 수단이다.

### 5.3 초기화되는 것

- 현재 플레이어 위치와 상태
- 문, 스위치, 목표물 등 level mutable state
- 일시적인 projectile과 effect
- 적의 위치와 AI 상태

### 5.4 유지되는 것

- 완료된 이전 회차 recording
- 현재 loop index
- 스테이지 안에서 허용된 메타 정보
- UI에 표시되는 Ghost 수

### 5.5 Ghost 수

- prototype 권장 최대: 5
- 성능 목표: 10개의 Ghost 재생 가능
- 최대 수에 도달한 뒤의 정책은 정식 설계 단계에서 결정한다.

prototype에서는 가장 오래된 Ghost를 자동 삭제하지 않는다. 최대 수 도달 시 사용자에게 재시작을 안내해도 된다.

---

## 6. Player Controls

### Prototype

| 입력 | 행동 |
|---|---|
| WASD | 이동 |
| E | 상호작용 |
| R | 현재 loop 즉시 종료/재시작 |
| Esc | 일시정지 |

### Later

| 입력 | 행동 |
|---|---|
| Left Mouse | 발사 |
| Space | dash |
| Q | 장비 사용 |
| F | 보조 상호작용 |

조작은 간단하고 즉각적이어야 한다. 시간 반복 구조를 이해하기 전에 복잡한 key binding을 요구하지 않는다.

---

## 7. Recording and Ghost Rules

### 7.1 기록 대상

prototype에서 기록하는 항목:

- timestamp
- player position
- facing direction
- interaction event
- interaction target object ID

추후 추가 가능:

- 공격
- 장비 사용
- item drop
- damage event
- animation state

### 7.2 Ghost 속성

- 반투명 또는 시간 왜곡 효과로 현재 플레이어와 구분된다.
- 현재 플레이어와 물리 충돌하지 않는다.
- 벽과의 충돌을 재계산하지 않고 recording 경로를 재생한다.
- 압력판과 스위치 등 허용된 object와 상호작용한다.
- 현재 prototype의 순찰 경비에게 보이며 유인 대상으로 작동한다.
- playback이 끝난 Ghost는 마지막 위치를 시각적으로 유지하지만 더 이상 감지 대상이 아니므로 경비는 탐색 후 순찰로 복귀한다.

prototype에서는 Ghost가 적과 전투하지 않는다.

### 7.3 Replay failure

상호작용 대상이 사라졌거나 ID를 찾지 못한 경우:

- 해당 event만 건너뛴다.
- 게임을 중단하지 않는다.
- 개발 build에서는 warning을 출력한다.

---

## 8. Prototype Level

### 8.1 목표

최소 두 개의 시간선을 사용해야만 클리어 가능한 한 개의 방을 만든다.

### 8.2 배치

```text
[Player Spawn]
      |
[Upper corridor: Guard lure]
             |
[Pressure Plate] ---- controls ---- [Security Door]
                                      |
                            [Lower vault: Objective]
                                      |
                                   [Exit]
```

압력판은 누군가 위에 올라가 있는 동안에만 door를 연다.

### 8.3 의도된 해결 과정

1회차:

1. 플레이어가 압력판까지 이동한다.
2. 다음 회차의 현재 Player가 문을 통과할 시간을 만들기 위해 잠시 머문다.
3. 시작 방의 upper corridor에서 경비의 시선을 끈다.
4. 포획되거나 수동으로 loop를 끝내 recording을 저장한다.

2회차:

1. 첫 번째 Ghost가 압력판으로 이동한다.
2. Ghost가 압력판 위에 있는 동안 문이 열린다.
3. 현재 플레이어가 문을 통과한다.
4. Ghost가 시작 방 upper corridor의 유인 행동을 반복해 경비를 끌어간다.
5. 현재 플레이어가 lower vault lane으로 이동해 목표물을 획득한다.
6. 출구에 들어간다.

이 동선은 학습을 위한 권장 해법이며 유일한 정답은 아니다. 현재 Player가 Ghost와 함께 upper corridor에 노출되면 경비는 현재 Player를 우선하므로, 문 뒤 lower vault lane이 시간선의 역할 분리를 자연스럽게 가르친다.

### 8.4 Tutorial 전달

긴 설명문보다 다음 순서로 학습시킨다.

- 닫힌 문을 먼저 보여준다.
- 문과 압력판을 선 또는 같은 색으로 연결한다.
- 첫 회차 종료 후 Ghost 생성 장면을 강조한다.
- 두 번째 회차에 열린 문을 시각적으로 명확하게 보여준다.
- 경비의 부채꼴 시야, `?` 의심, `!` 추격 표시를 색과 형태로 함께 보여준다.
- 첫 회차에는 압력판을 잠시 유지한 뒤 시작 방 upper corridor에서 경비를 유인하도록 안내한다.
- 두 번째 회차에는 Ghost가 경비를 유인하는 동안 문 뒤 lower vault lane을 사용하도록 한 문장씩 안내한다.

---

## 9. Interactable Objects

### 9.1 Pressure Plate

- actor가 위에 있는 동안 active
- player와 Ghost 모두 활성화 가능
- active 상태를 색과 소리로 표현
- 여러 actor가 동시에 올라가도 정상 작동

### 9.2 Door

- 연결된 source가 active이면 열린다.
- 열림과 닫힘 animation 중 충돌 상태가 명확해야 한다.
- prototype에서는 즉시 또는 짧은 animation으로 작동한다.
- actor를 문 안에 끼우지 않도록 한다.

### 9.3 Objective Item

- 현재 player만 획득 가능
- Ghost는 획득하지 않는다.
- 획득 후 UI에 상태 표시
- level reset 시 원래 위치로 복구

### 9.4 Exit Zone

- 현재 player가 objective를 보유한 상태로 들어가면 성공
- objective가 없으면 명확한 feedback 제공
- Ghost는 성공 조건을 발동하지 않는다.

---

## 10. Win and Fail Conditions

### Prototype 승리

- 현재 player가 objective item을 획득한다.
- 현재 player가 exit zone에 진입한다.

### Prototype 실패

- 아직 영구 실패는 없다.
- loop가 끝나면 새로운 시도가 시작된다.
- 경비에게 포획된 회차도 capture 시점까지 저장되어 다음 Ghost가 된다.
- 사용자가 전체 timeline reset을 선택할 수 있다.

### Later 실패

- 최대 loop 수 초과
- timeline corruption 최대치 도달
- objective 파괴 또는 회수 불가
- 특수 스테이지의 경보 제한 초과

---

## 11. Feedback and Dopamine Design

### 11.1 Loop 시작

- 짧은 화면 왜곡
- loop 번호 표시
- Ghost들이 시간 균열에서 나타나는 연출

### 11.2 Interaction 성공

- 압력판: 강한 click과 색 변화
- 문: 무거운 unlock sound
- 목표물: 빛, 짧은 hit stop 또는 강조

### 11.3 경비 상태

- 순찰: 낮은 alpha의 부채꼴 시야와 `PATROLLING` 상태
- 의심: orange 계열 시야, `?` icon, 의심도 meter
- 추격: red 계열 시야, `!` icon, `CHASING` 상태
- 포획: 짧은 `CAUGHT — THIS TIMELINE WAS SAVED` feedback 후 즉시 다음 loop

### 11.4 동기화 성공

두 개 이상의 시간선 행동이 연결될 때 다음 feedback을 제공할 수 있다.

```text
GHOST ASSIST
PERFECT SYNC
TIMELINE TRICK
LAST SECOND ESCAPE
```

prototype에서는 텍스트 효과를 최소화하고, 문이 열리는 순간의 시청각 feedback에 집중한다.

### 11.5 남은 시간

- 10초: UI 색 또는 pulse 변화
- 5초: 초 단위 경고음
- 3초: 더 강한 화면 효과
- 0초: 즉시 끊기지 않고 짧은 rewind transition 후 reset

---

## 12. Visual Direction

### Prototype

- player: 파란색 도형
- Ghost: 반투명 청록색 도형
- guard: 짙은 uniform과 orange accent
- guard vision: 상태에 따라 cyan/orange/red로 변하는 반투명 부채꼴과 `?`/`!` icon
- wall: 짙은 회색
- door: 밝은 회색
- pressure plate: 노란색, active 시 녹색
- objective: 빛나는 흰색 또는 금색
- exit: 명확한 외곽선과 화살표

prototype에서는 custom art보다 읽기 쉬운 상태 표현을 우선한다.

### Final Direction

권장 분위기:

- 근미래 보안 시설
- 선명한 neon accent
- 어두운 배경과 높은 대비
- Ghost는 afterimage와 scanline 왜곡
- UI는 작전 타이머와 보안 시스템 느낌

---

## 13. Audio Direction

필수 prototype sound:

- loop start
- loop end
- Ghost spawn
- pressure plate active
- door open/close
- objective pickup
- exit success
- countdown warning
- guard suspicion/alert/capture

음악은 없어도 되지만, 타이머와 상호작용 효과음은 핵심 feedback이므로 우선순위가 높다.

---

## 14. Difficulty Principles

- 플레이어가 첫 실패의 이유를 즉시 이해할 수 있어야 한다.
- 반복은 실행 시간을 늘리는 것이 아니라 역할을 추가해야 한다.
- 퍼즐은 하나의 정답만 강요하기보다 여러 시간선 배치를 허용한다.
- 정확한 frame 단위 입력보다 0.2~0.5초 정도의 여유를 둔다.
- 시간 제한은 압박을 만들되, 조작 학습을 방해하지 않아야 한다.

---

## 15. Future Content Framework

prototype 성공 후 확장 후보:

### 퍼즐

- 두 개의 동시 압력판
- 시간 제한 스위치
- 서로 다른 방향의 문
- 레이저 차단
- 이동식 상자
- Ghost가 운반하는 key

### 적

- 고정 감시 카메라
- 소리에 반응하는 경비
- 여러 경비 간 경보 전달

현재 prototype은 한 명의 결정적 순찰 경비와 Player/Ghost 시야 감지를 이미 포함한다. 이후 적 확장은 이 동작을 깨뜨리지 않는 playtest 근거가 있을 때만 진행한다.

### 장비

- 소음 권총
- EMP
- time anchor
- Ghost delay device
- recording edit tool

### 스테이지

- casino
- moving train
- time laboratory
- underwater vault

이 항목들은 prototype 완료 전에는 구현하지 않는다.

---

## 16. Scope Guard

prototype에서 가장 중요한 질문은 단 하나다.

> 과거의 내가 압력판을 열고 경비를 유인하는 동안 현재의 내가 다른 역할을 수행하는 순간이 실제로 재미있는가?

아래 기능은 이 질문에 답하는 데 필요하지 않으므로 뒤로 미룬다.

- lore와 긴 story
- character customization
- progression economy
- 다수의 weapon
- procedural level
- crafting
- multiplayer
- Steam achievement

---

## 17. Prototype Success Criteria

prototype은 다음 질문에 대부분 “예”라고 답할 수 있어야 한다.

- 첫 Ghost가 등장했을 때 규칙이 직관적으로 이해되는가?
- Ghost가 과거 행동을 충분히 정확하게 재현하는가?
- 압력판과 문 연결 관계가 명확한가?
- 두 번째 회차에서 문을 통과할 때 성취감이 있는가?
- 포획된 실패가 다음 회차의 유용한 경비 유인으로 전환되는가?
- Ghost distraction과 현재 Player의 lower-lane 이동이 화면에서 이해되는가?
- loop reset이 답답할 정도로 오래 걸리지 않는가?
- 다시 시도해서 더 좋은 동선을 만들고 싶은가?
- 10초짜리 영상만으로 핵심 재미가 전달되는가?

최소 기술 완료 기준:

```text
1회차 recording
→ 2회차 Ghost replay
→ pressure plate 활성화
→ door 통과
→ Ghost가 guard 유인
→ objective 획득
→ exit 성공
```
