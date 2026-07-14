# 60초의 공범 — Game Design Document

문서 상태: **Operation: Black Minute + preserved regression modes**

장르: 2D top-down single-player stealth heist

플랫폼: Web 우선, desktop 보조

엔진: Godot 4.7 / GDScript

## 1. Game identity

게임의 중심 문장은 다음과 같다.

> 제한된 회귀 능력을 가진 전문 침입자가 보안 시설의 시스템과 경비망을 분석하고 무력화해 목표물을 훔쳐 탈출하는 잠입 절도 게임.

우선순위는 `Heist → Stealth → Planning → Security interaction → Exploration → Time ability → Echo improvisation`이다. 시간 회귀는 중요한 차별점이지만 모든 행동을 다시 수행하게 만드는 강제 목표가 아니다.

기존의 전체 시간선 반복은 삭제하지 않는다. `PROTOTYPE_LOOP`과 `FACILITY_REGRESSION` 모드에서 recording, Ghost playback, 결정적 reset을 검증하는 core-technology demonstration으로 유지한다.

## 2. Player fantasy

- 작전에 앞서 지도를 읽고 침투 경로를 계획한다.
- 순찰과 카메라 sweep을 관찰해 안전한 이동 시점을 고른다.
- 카드, terminal, 보안망을 순서대로 공략한다.
- 실수를 Chrono Recall로 복구하거나 Echo distraction으로 전환한다.
- 전투 없이 시설 최심부의 물체를 훔쳐 원래 침투 지점으로 돌아온다.
- Recall을 한 번도 쓰지 않은 완벽 잠입도 가능하다.

## 3. Design pillars

### Heist first

목표물, 준비 과정, 보안 계층, 진입과 탈출이 명확해야 한다. 플레이어는 “왜 이 방에 가는가”를 HUD와 지도에서 이해할 수 있어야 한다.

### Readable stealth

Guard vision cone, CCTV sweep, laser, 잠긴 문, alert를 색만이 아니라 icon, text, shape으로 함께 표현한다. 실제 감지는 거리, 각도, line of sight, proximity 규칙을 사용한다.

### Deterministic planning

Guard 순찰에는 randomness를 사용하지 않는다. route phase, waypoint wait, zone, choke safe window가 데이터로 고정되어 같은 계획이 같은 결과를 내야 한다.

### Limited recovery

Chrono Recall은 강력하지만 3회뿐이다. 소비한 charge는 되돌아오지 않으며, 회귀 직전 행동은 보안 시스템이 볼 수 있는 Echo가 된다.

### Failure stays fast

포획 시 긴 실패 화면 대신 `RECALL` 또는 `CHECKPOINT`를 선택한다. 현재 checkpoint는 mission start 하나이며, 같은 briefing을 다시 읽지 않고 빠르게 재시도할 수 있다.

## 4. Game modes

### Operation: Black Minute

정식 기본 모드. 전체 mission timer가 20초 또는 60초마다 강제 reset되지 않는다. 플레이어는 긴 infiltration 안에서 최대 3회의 10초 Recall을 선택적으로 사용한다.

### 20-second prototype loop

압력판, 문, Ghost, 목표물, 출구를 두 개 이상의 timeline으로 해결하는 가장 작은 회귀 검증 모드다. `R`, timeout, Guard capture가 recording을 확정하고 다음 Ghost를 만든다.

### 60-second facility regression

26×25 TileMap, terminal/laser, Guard distraction, wall visibility, dynamic door occlusion을 검증하는 확장 회귀 모드다.

## 5. Primary mission loop

```text
Main Menu
→ Mission Briefing와 tactical map 확인
→ 외부 yard에서 침투
→ Level 1 card 획득
→ CCTV를 해제하거나 sweep을 회피
→ electrical room에서 laser network 해제
→ security office에서 Level 2 획득
→ server override 또는 research biometric 획득
→ vault authorization으로 금고 진입
→ Chronos Core 절도
→ extraction yard 복귀
```

위험 구간에서는 다음 선택이 끼어든다.

```text
발각 또는 잘못된 경로
→ Q로 수동 Recall
→ 최근 최대 10초의 Player/world state 복원
→ 버린 구간이 Echo로 한 번 재생
→ 현재 Player가 다른 선택 수행
```

포획 시에는 자동으로 charge를 사용하지 않는다. 선택 UI가 Recall 가능 여부를 보여 주며, Recall하지 않거나 charge가 없으면 mission-start checkpoint로 돌아간다.

## 6. Operation: Black Minute

- 작전명: **OPERATION: BLACK MINUTE / 작전명: 검은 1분**
- 시설: **HELIX TEMPORAL RESEARCH FACILITY / 헬릭스 시간 연구시설**
- 목표물: **CHRONOS CORE / 크로노스 코어**
- 목적: 시설 파괴가 아니라 Core 절도와 생환

시설 blueprint contract:

- 64×42 cells, 32 px tile, 2048×1344 world
- 15 named rooms/operational spaces
- 23 room connectors and 15 dynamic security portals
- 10 Guards in 7 bounded Guard zones
- 8 CCTV cameras and 3 laser barriers
- 15 choke points; every declared safe window is at least 3 seconds

상세 layout은 [operation_black_minute_layout.md](maps/operation_black_minute_layout.md)를 따른다.

## 7. Objective and access progression

Objective는 `LOCKED`, `AVAILABLE`, `ACTIVE`, `COMPLETED`, `FAILED` 상태를 갖는 acyclic graph다.

주요 progression:

1. reception checkpoint 침투
2. locker room에서 Level 1 card 획득
3. CCTV disable 또는 안전한 회피 경로 선택
4. electrical room에서 laser network disable
5. security office에서 Level 2 card 획득
6. server override 또는 research biometric 중 하나로 Vault authorization 획득
7. laser offline + Level 2 + Vault authorization 조건으로 vault 진입
8. Chronos Core 획득
9. 활성화된 extraction으로 복귀

CCTV 해제는 유리하지만 Core progression을 강제로 막지 않는다. Laser 해제와 Vault authorization은 필수다. Core는 live Player만 획득할 수 있다.

## 8. Stealth rules

### Guards

Guard state는 `IDLE`, `PATROL`, `SUSPICIOUS`, `CHASE`, `SEARCH`, `RETURN`으로 유지한다. Player와 Echo를 볼 수 있으며, 동시에 노출되면 live Player가 우선이다.

감지 조건:

- vision distance 안에 있음;
- facing 기준 시야각 안에 있음;
- wall 또는 닫힌 door에 막히지 않음;
- 아주 가까운 거리에서는 뒤쪽도 감지하는 proximity awareness;
- mission active이며 pause/restore 중이 아님.

발각은 zone 및 인접 response zone에 last-seen 위치를 전달한다. Guard는 시설 전체를 무기한 추격하지 않고 zone bounds 안에서 조사한 뒤 route로 복귀한다.

### CCTV

8개 camera는 deterministic phase로 sweep한다. Player와 Echo가 threshold 동안 보이면 zone alert를 발생시킨다. CCTV control terminal을 완료하면 network가 offline되어 sweep/detection이 멈춘다.

### Lasers

3개 barrier는 active일 때 live Player 접촉을 capture request로 바꾼다. Echo는 laser에 잡히지 않는다. Electrical terminal이 network 전체를 disable한다.

### Alert

시설 alert는 `CLEAR`, `SUSPICIOUS`, `ALERTED`, `LOCKDOWN`이다. 일반 alert는 감지가 없으면 단계적으로 감소한다. Core 절도는 `LOCKDOWN`을 발생시키고 extraction route를 연다.

## 9. Chrono Recall and Echo

기본값:

- 3 mission-persistent charges;
- 10-second bounded history;
- 20 Hz transform/world snapshots;
- Q manual activation;
- maximum 3 Echoes;
- world clock remains monotonic.

Recall은 현재 branch 시작 전으로 넘어가지 않는다. 연속 Recall은 각각 새 branch를 시작한다. 사용한 charge는 snapshot restore 대상이 아니므로 복구되지 않는다.

Rewindable state에는 Player transform/facing, access inventory, doors, terminals, CCTV/laser state, mission objectives, Guards, cameras, Core/extraction state가 포함된다. Object reference를 snapshot data에 저장하지 않는다.

Echo가 할 수 있는 것:

- 과거 이동과 facing 재생;
- Guard/CCTV distraction;
- pressure plate occupancy;
- 허용된 door/terminal event replay.

Echo가 할 수 없는 것:

- access card 획득 또는 전달;
- Chronos Core 획득;
- 현재 Player inventory 직접 변경;
- Recall 사용;
- mission completion 중복 발생.

세 번째 Echo 이후 새 Echo가 필요하면 가장 오래된 Echo를 안전하게 제거한다.

## 10. Checkpoint and failure policy

- 영구 campaign save: 없음.
- Core 획득 전 checkpoint: mission start.
- Core 획득 후 checkpoint: 없음.
- capture + charge/history available: Recall 또는 checkpoint 선택.
- capture + Recall 불가: mission-start checkpoint restart.
- laser capture도 같은 capture decision protocol을 사용.
- victory 이후 capture와 simulation을 중단.

Checkpoint reset은 cards, access, doors, terminals, CCTV, lasers, alert, Guards, Core, extraction, objective graph, Echoes, Recall history/charges를 mission initial state로 복원한다.

## 11. Tactical map and onboarding

Briefing은 조작 전에 operation/facility/target/security/Recall charge와 정적 시설 지도를 보여 준다.

게임 중 `M` 또는 `Tab`으로 map을 열면 tactical pause가 적용된다. Map은 rooms, Player, objective region, extraction, security status, locked doors, 발견된 maintenance passage를 보여 주되 정답 경로나 실시간 Guard 위치를 기본 제공하지 않는다.

튜토리얼은 상황에 맞춰 한 번씩 표시한다.

- 시작: `OPEN THE TACTICAL MAP WITH M`
- reception: vision cone과 proximity awareness
- 잠긴 문: required access level
- CCTV: camera가 nearby Guards에 alert 가능
- laser: electrical network 해제 필요
- Recall: 10초 복원, limited charge, Echo 생성

## 12. Difficulty and fairness

목표 플레이 시간:

- first clear: 15–25 minutes;
- practiced clear: 6–12 minutes;
- perfect infiltration: 0 Recalls;
- typical first clear: 1–3 Recalls.

공정성 조건:

- spawn 직후 이유 없이 포획되지 않는다.
- 각 mandatory security step은 접근 가능한 room과 단서를 가진다.
- Level 1 card는 Level 1 뒤에, Level 2 card는 Level 2 뒤에 놓이지 않는다.
- Vault authorization은 Vault access를 먼저 요구하지 않는다.
- laser shutdown terminal은 active laser corridor 뒤에 있지 않는다.
- 모든 mandatory room/object zone은 spawn room graph에서 도달 가능하다.
- choke마다 3초 이상의 declared safe window가 있다.
- Recall 없이도 완주 가능한 declared route가 있다.

`MissionSolvabilityValidator`와 180초 virtual patrol simulation이 이 데이터 계약을 자동 검사한다. 이는 실제 플레이 감각이나 browser rendering 검증을 대체하지 않는다.

## 13. Presentation and accessibility

- Player/Recall/Echo: cyan 계열
- Guard/danger/alert: orange/red 계열
- Objective/Core: violet/cyan
- extraction active: green/cyan
- neutral UI: dark navy/gray

중요한 상태는 색뿐 아니라 text, icon, meter, shape으로 표현한다. 화면 흔들림과 flashing은 약하게 유지하고, mute 상태에서도 objective, alert, capture, countdown 상태를 읽을 수 있어야 한다.

주요 작전 beat는 동일한 cue 문법을 사용한다.

- objective/access/security 완료: 중앙 cue card와 짧은 procedural tone;
- Recall: cyan timeline wash와 `ECHO ACTIVE` text;
- Core theft: violet cue와 extraction directive;
- capture: red modal, Recall/checkpoint 선택, non-color text;
- extraction: grade, score, elapsed time, Recall/detection/capture/route, directive breakdown.

Mission performance는 완주 `5,000`점에 `SHADOW`, `TEMPORAL DISCIPLINE` 또는 `PARADOX DECOY`, `UNTOUCHABLE`, `BLACKOUT` 보너스를 더하는 positive-only `10,000`점 구조다. no-Recall과 실제 Echo distraction이 같은 S-rank ceiling을 가진다. elapsed time은 결과에 표시하지만 점수에 사용하지 않는다. 상세 계약은 [mission_performance.md](mission_performance.md)를 따른다.

## 14. Preserved loop technology

Regression modes continue to validate:

```text
20 Hz recording
→ immutable LoopRecording
→ timestamp interpolation and stable-ID event playback
→ Ghost pressure plate/door interaction
→ Guard distraction and capture recording
→ deterministic loop reset
```

이 시스템은 formal heist의 `ChronoRecallManager`와 데이터 타입을 공유할 수 있지만 lifecycle은 분리한다. 정식 mission을 `TimelineManager`의 full-loop 규칙으로 실행하지 않는다.

## 15. Scope guard

현재 범위에 포함하지 않는다.

- combat, health, weapons, damage, reinforcements;
- hearing/noise simulation, cover, crouch;
- campaign, persistent saves, online leaderboard, meta progression;
- procedural maps, boss, additional enemy archetypes;
- multiplayer, accounts, leaderboard, analytics;
- touch control and user-generated content.

## 16. Acceptance goals

Formal mission acceptance:

```text
briefing
→ 64×42 facility boot
→ access/security progression
→ deterministic 10-Guard patrol
→ optional no-Recall route
→ Recall restore + Echo distraction route
→ Core theft
→ extraction, immutable debrief, and victory
```

Regression acceptance remains:

```text
first loop recording
→ next-loop Ghost
→ pressure plate and door
→ Guard distraction
→ objective and exit
→ clean deterministic reset
```

Headless success validates data, resources, and logic. Compatibility-renderer pixels, responsive UI, browser input, and console cleanliness require a separate browser pass and must not be inferred.
