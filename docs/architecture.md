# 60초의 공범 — Technical Architecture

문서 상태: Prototype architecture  
엔진: Godot 4.x  
언어: GDScript with static typing  
대상: Codex 및 프로젝트 개발자

---

## 1. Architecture Goals

이 구조의 목표는 다음과 같다.

1. time-loop recording과 Ghost replay를 안정적으로 구현한다.
2. level object가 replay system에 과도하게 결합되지 않도록 한다.
3. prototype을 빠르게 만들되 정식 게임으로 확장 가능한 경계를 유지한다.
4. frame rate와 physics 오차로 인한 replay drift를 최소화한다.
5. Codex가 파일 책임과 데이터 흐름을 쉽게 이해할 수 있게 한다.

---

## 2. Core Decisions

### 2.1 Hybrid Replay

prototype은 hybrid replay를 사용한다.

- movement: position/facing snapshot을 timestamp에 따라 interpolation
- discrete action: 별도 event list를 timestamp에 맞춰 실행

이유:

- input만 다시 실행하면 physics 상태에 따라 경로가 달라질 수 있다.
- position만 재생하면 상호작용 시점을 안정적으로 복원하기 어렵다.
- 두 방식을 결합하면 이동은 안정적이고 행동은 명확해진다.

### 2.2 In-Memory Recording

prototype에서는 recording을 disk에 저장하지 않는다.

- 한 level session 동안만 유지
- level 종료 또는 timeline reset 시 폐기
- meta save와 분리

### 2.3 Stable Object Registry

상호작용 대상은 stable object ID로 조회한다.

- NodePath를 recording에 저장하지 않는다.
- level 시작 시 registry를 구성한다.
- Ghost event는 ID로 object를 찾는다.

### 2.4 Level State Reset

level mutable state는 매 loop 시작 전에 초기 snapshot 또는 명시적 reset contract를 통해 복구한다.

prototype에서는 각 resettable object가 `reset_for_loop()`를 구현하는 방식이 가장 단순하다.

---

## 3. Recommended Scene Tree

```text
Main.tscn
└── Main
    ├── GameManager
    ├── LevelContainer
    │   └── PrototypeLevel
    │       ├── Environment
    │       ├── PlayerSpawn
    │       ├── Player
    │       ├── GhostContainer
    │       ├── ObjectRegistry
    │       ├── ResettableContainer
    │       ├── PressurePlate
    │       ├── SecurityDoor
    │       ├── ObjectiveItem
    │       └── ExitZone
    ├── TimelineManager
    └── UI
        ├── TimerLabel
        ├── LoopLabel
        └── StatusLabel
```

실제 scene tree는 다를 수 있지만 책임 경계는 유지한다.

---

## 4. Module Map

```text
GameManager
├── level lifecycle
├── success/failure state
└── session orchestration

TimelineManager
├── loop clock
├── recording lifecycle
├── stored recordings
└── Ghost spawn orchestration

PlayerController
├── movement
├── facing
├── interaction request
└── current live actor state

ActionRecorder
├── snapshot sampling
├── event capture
└── completed recording creation

GhostPlayback
├── recording playback clock
├── snapshot interpolation
└── event dispatch

ObjectRegistry
├── stable ID registration
└── object lookup

LoopResetManager or reset contract
├── reset mutable objects
└── restore spawn state

Interactables
├── pressure plate
├── door
├── objective
└── exit
```

---

## 5. Data Model

### 5.1 TransformSnapshot

```gdscript
class_name TransformSnapshot
extends RefCounted

var timestamp: float
var position: Vector2
var facing_angle: float

func _init(
    p_timestamp: float,
    p_position: Vector2,
    p_facing_angle: float
) -> void:
    timestamp = p_timestamp
    position = p_position
    facing_angle = p_facing_angle
```

필요하면 `velocity` 또는 animation hint를 나중에 추가할 수 있다.

### 5.2 RecordedEvent

```gdscript
class_name RecordedEvent
extends RefCounted

enum EventType {
    INTERACT,
    SHOOT,
    ITEM_DROP,
}

var timestamp: float
var type: EventType
var target_object_id: StringName
var payload: Dictionary
```

prototype에서는 `INTERACT`만 사용해도 된다.

### 5.3 LoopRecording

```gdscript
class_name LoopRecording
extends RefCounted

var duration: float
var snapshots: Array[TransformSnapshot]
var events: Array[RecordedEvent]
```

추가 metadata 후보:

- recording ID
- loop index
- end reason
- player cosmetic variant

prototype에서는 필요하지 않으면 넣지 않는다.

---

## 6. Main Responsibilities

### 6.1 GameManager

담당:

- current level 시작
- level 성공 처리
- 전체 timeline reset
- pause 상태와 UI 상위 흐름

비담당:

- snapshot 기록
- Ghost interpolation
- door 상태 직접 변경

권장 signal:

```gdscript
signal level_started
signal level_completed
signal timeline_reset
```

### 6.2 TimelineManager

권장 공개 상태:

```gdscript
@export var loop_duration_seconds: float = 20.0
@export var max_recordings: int = 5

var current_loop_index: int
var elapsed_time: float
var is_loop_running: bool
var recordings: Array[LoopRecording]
```

핵심 함수:

```gdscript
func start_first_loop() -> void
func finish_current_loop(reason: StringName) -> void
func start_next_loop() -> void
func reset_timeline() -> void
func get_remaining_time() -> float
```

권장 signal:

```gdscript
signal loop_started(loop_index: int)
signal loop_time_updated(remaining_seconds: float)
signal loop_ended(loop_index: int, reason: StringName)
signal recording_added(recording: LoopRecording)
```

### 6.3 PlayerController

담당:

- input 기반 이동
- facing 갱신
- interaction 요청
- spawn state 복구

PlayerController는 recording array를 직접 관리하지 않는다. `ActionRecorder`에 현재 상태를 제공하거나 recorder가 player를 참조한다.

### 6.4 ActionRecorder

권장 설정:

```gdscript
@export var sample_rate_hz: float = 20.0
```

동작:

1. loop 시작 시 buffer 초기화
2. 일정 주기로 snapshot 추가
3. player interaction 성공 시 event 추가
4. loop 종료 시 `LoopRecording` 생성
5. recording을 TimelineManager에 전달

샘플 간격:

```text
sample_interval = 1.0 / sample_rate_hz
```

`delta`가 interval보다 커도 sample을 잃지 않도록 accumulator 기반으로 처리한다.

### 6.5 GhostPlayback

상태:

```gdscript
var recording: LoopRecording
var playback_time: float
var next_event_index: int
var is_playing: bool
```

매 frame:

1. playback_time 증가
2. 현재 시간 앞뒤 snapshot index 찾기
3. position과 facing interpolation
4. timestamp가 지난 event를 순서대로 실행
5. recording 종료 시 마지막 상태 유지 또는 비활성화

event 실행은 `while`을 사용하여 한 frame에 여러 event 시간이 지나도 누락하지 않는다.

```gdscript
while next_event_index < recording.events.size():
    var event := recording.events[next_event_index]
    if event.timestamp > playback_time:
        break
    _dispatch_event(event)
    next_event_index += 1
```

---

## 7. Interaction Architecture

### 7.1 Interactable Contract

Godot의 strict interface가 없으므로 base class 또는 duck typing을 선택한다.

권장 base class:

```gdscript
class_name Interactable
extends Node2D

@export var object_id: StringName

func can_interact(actor: Node) -> bool:
    return true

func interact(actor: Node) -> void:
    push_warning("interact() must be overridden")
```

모든 상호작용 object가 반드시 Node2D일 필요가 없다면 `Node` base와 별도 area child를 사용할 수 있다.

### 7.2 Interaction Flow

현재 player:

```text
input interact
→ PlayerInteractor finds nearby Interactable
→ can_interact(player)
→ interact(player)
→ success
→ ActionRecorder records INTERACT event with object_id
```

Ghost:

```text
RecordedEvent timestamp reached
→ ObjectRegistry.get_object(object_id)
→ can_interact(ghost)
→ interact(ghost)
```

기록은 interaction input이 아니라 **성공한 interaction**을 기준으로 남긴다. 실패한 입력을 기록하면 replay에서 의미 없는 event가 쌓인다.

### 7.3 Actor Identity

object가 player와 Ghost를 구분해야 할 수 있다.

권장 방식:

- group: `player_actor`, `ghost_actor`
- 또는 공통 `TimelineActor` base class

prototype에서는 group 방식이 단순하다.

---

## 8. Object Registry

### 8.1 Responsibilities

- level 안의 object ID 등록
- 중복 검사
- ID 기반 lookup
- level 종료 시 clear

예시:

```gdscript
class_name ObjectRegistry
extends Node

var _objects: Dictionary[StringName, Node] = {}

func register_object(object_id: StringName, object: Node) -> void:
    if object_id == StringName():
        push_error("Cannot register empty object_id")
        return
    if _objects.has(object_id):
        push_error("Duplicate object_id: %s" % object_id)
        return
    _objects[object_id] = object

func get_object(object_id: StringName) -> Node:
    return _objects.get(object_id)
```

### 8.2 Registration Strategy

권장 순서:

1. level scene ready
2. `interactable` group 순회
3. object ID 등록
4. 중복 검증
5. loop 시작

매 interaction마다 scene tree 전체를 검색하지 않는다.

---

## 9. Loop Reset Architecture

### 9.1 Resettable Contract

```gdscript
func reset_for_loop() -> void:
    pass
```

reset 대상 예:

- door
- pressure plate
- objective item
- exit state
- player
- future enemy
- projectile container

### 9.2 Reset Order

권장 순서:

1. 현재 live player 입력 정지
2. ActionRecorder 종료 및 recording 확정
3. 일시적 node 삭제
4. resettable object 초기화
5. current player를 spawn point로 복구
6. 기존 recording으로 Ghost 생성
7. 새 recorder 시작
8. loop clock 시작

Ghost는 새 loop 시작 전 모두 제거하고 recordings 기반으로 다시 생성하는 것이 안전하다. 이전 loop의 Ghost node를 재사용하면 playback state가 남을 위험이 있다.

### 9.3 State Restoration

prototype에서는 object별 초기값을 export property 또는 `_ready()` 시점에 저장한다.

예:

```gdscript
var _initial_position: Vector2
var _initial_visible: bool

func _ready() -> void:
    _initial_position = global_position
    _initial_visible = visible

func reset_for_loop() -> void:
    global_position = _initial_position
    visible = _initial_visible
```

복잡한 level이 생기면 snapshot resource 기반 reset으로 확장할 수 있다.

---

## 10. Pressure Plate and Door

### 10.1 PressurePlate

구성 예:

```text
PressurePlate (Area2D)
├── CollisionShape2D
├── Sprite2D
└── AudioStreamPlayer2D
```

상태:

```gdscript
var occupying_actor_ids: Dictionary[int, bool]
var is_active: bool
```

`body_entered`와 `body_exited`를 사용하고, actor instance ID를 set처럼 관리한다. 단일 boolean만 사용하면 여러 actor가 올라갔을 때 한 명이 나가는 순간 잘못 비활성화될 수 있다.

signal:

```gdscript
signal active_changed(is_active: bool)
```

### 10.2 SecurityDoor

Door는 pressure plate signal을 구독한다.

```text
PressurePlate.active_changed
→ SecurityDoor.set_open(is_active)
```

Door는 TimelineManager를 알 필요가 없다.

초기 prototype에서는 animation 없이 collision enable/disable과 sprite 상태만 바꿔도 된다.

---

## 11. Objective and Exit

### 11.1 ObjectiveItem

- player만 pickup 가능
- pickup 시 player 또는 GameManager에 objective state 전달
- 자신은 숨기고 collision 비활성화
- reset 시 다시 활성화

권장 signal:

```gdscript
signal collected
```

### 11.2 ExitZone

- player가 진입했을 때 objective 보유 여부 확인
- 성공 시 GameManager에 level complete 요청
- Ghost 진입은 무시

objective state는 player component 또는 GameManager session state 중 하나에 둔다. prototype에서는 player의 boolean도 가능하지만, 장기적으로 inventory와 분리될 것을 고려한다.

---

## 12. UI Data Flow

UI는 manager를 직접 조작하지 않고 상태만 표시한다.

```text
TimelineManager.loop_time_updated
→ HUD updates timer

TimelineManager.loop_started
→ HUD updates loop index

GameManager.level_completed
→ HUD shows success state
```

매 frame manager node를 찾아 값을 polling하지 않는다.

---

## 13. Pause and Time Control

- pause 중 recording time과 playback time이 멈춰야 한다.
- UI pause menu는 process mode를 `When Paused`로 설정할 수 있다.
- loop transition 연출에서 Engine.time_scale을 사용할 경우 반드시 원상 복구한다.
- prototype에서는 global time scale보다 animation/tween 중심 연출을 권장한다.

---

## 14. Determinism Strategy

### Stable

- pressure plate
- door
- objective
- exit
- fixed laser
- scripted platform

이 object들은 같은 event와 상태에서 같은 결과를 내야 한다.

### Dynamic Later

- enemy AI
- projectile
- physics box
- explosion

dynamic system은 퍼즐 필수 경로의 단일 실패 지점이 되지 않도록 설계한다.

### Replay Drift Prevention

- position snapshot sampling: 기본 20Hz
- playback: timestamp 기반 interpolation
- event: 별도 정렬된 list
- event index는 한 방향으로만 증가
- loop clock은 playback과 recording이 같은 기준을 사용
- physics input 재실행에 의존하지 않음

---

## 15. Error and Validation Checks

시작 시 검사:

- loop duration > 0
- sample rate > 0
- PlayerSpawn 존재
- Player 존재
- Ghost scene 지정
- ObjectRegistry 존재
- stable ID 중복 없음

recording 종료 시 검사:

- snapshot이 최소 1개 이상
- timestamp가 감소하지 않음
- event가 timestamp 순서로 정렬됨
- duration이 음수가 아님

playback 시 검사:

- recording null 아님
- snapshot array 비어 있지 않음
- 대상 object 누락 시 warning 후 continue

---

## 16. Testing Strategy

Godot 프로젝트에서 가능한 경우 GUT 같은 framework를 도입할 수 있지만, prototype 첫 단계에서는 수동 integration test와 작은 pure-data unit test를 우선한다.

### 16.1 Data Tests

- snapshot interpolation 결과
- event ordering
- sample accumulator
- recording duration

### 16.2 Integration Tests

1. loop 1에서 player가 지정 경로 이동
2. recording 생성 확인
3. loop 2에서 Ghost 위치 확인
4. pressure plate active 확인
5. door collision disable 확인
6. objective pickup 확인
7. exit success 확인

### 16.3 Regression Checks

- R 연속 입력으로 recording 중복 저장되지 않음
- pause 중 timer 감소하지 않음
- Ghost event 중복 실행되지 않음
- timeline reset 후 recordings 비어 있음
- object ID 중복 시 명확한 오류

---

## 17. Performance Budget

prototype 기준:

- target: 60 FPS
- loop duration: 20초
- sample rate: 20Hz
- snapshots per Ghost: 약 400
- Ghost target count: 5
- stretch target: 10

20초 × 20Hz × 10 Ghost = 4,000 snapshots이므로 prototype 규모에서는 충분히 관리 가능하다.

최적화 우선순위:

1. 매 frame scene tree search 제거
2. event 중복 처리 방지
3. 불필요한 allocation 감소
4. Ghost 시각 효과 단순화

object pooling은 실제 profiling에서 필요할 때 도입한다.

---

## 18. File Responsibility Proposal

```text
scripts/core/game_manager.gd
- level lifecycle, success, timeline reset

scripts/core/timeline_manager.gd
- loop timing, recording collection, loop transitions

scripts/core/object_registry.gd
- stable ID registration and lookup

scripts/core/loop_recording.gd
- recording data container

scripts/core/transform_snapshot.gd
- movement snapshot data

scripts/core/recorded_event.gd
- event data

scripts/player/player_controller.gd
- current player movement and input

scripts/player/player_interactor.gd
- nearby interaction selection

scripts/player/action_recorder.gd
- snapshot and event recording

scripts/ghost/ghost_playback.gd
- playback interpolation and event dispatch

scripts/objects/interactable.gd
- common interaction base

scripts/objects/pressure_plate.gd
- occupancy and active state

scripts/objects/security_door.gd
- open/close and collision

scripts/objects/objective_item.gd
- objective pickup and reset

scripts/objects/exit_zone.gd
- completion check

scripts/ui/hud.gd
- timer, loop, status display
```

한 파일에 여러 주요 class를 몰아넣지 않는다.

---

## 19. Incremental Build Order

### Milestone 1: Foundation

- Godot project
- folders
- Input Map
- prototype level shell
- player spawn

### Milestone 2: Player

- movement
- collision
- interaction detector

### Milestone 3: Recording

- data classes
- ActionRecorder
- loop timer
- recording finalization

### Milestone 4: Ghost

- Ghost scene
- snapshot interpolation
- event playback

### Milestone 5: Puzzle

- registry
- pressure plate
- door
- reset contract

### Milestone 6: Goal

- objective
- exit
- success state
- HUD

### Milestone 7: Hardening

- pause
- manual restart
- duplicate event guards
- validation
- headless parse check

각 milestone은 독립적으로 실행 가능하고 검증 가능해야 한다.

---

## 20. Prototype Acceptance Test

다음 시나리오를 수동으로 재현할 수 있어야 한다.

### Setup

- loop duration 20초
- player spawn과 pressure plate 사이 이동 가능
- door 뒤에 objective와 exit 배치

### Test

1. 게임 시작
2. player가 pressure plate로 이동
3. plate 위에서 loop 종료
4. 두 번째 loop 시작
5. 첫 recording의 Ghost 생성 확인
6. Ghost가 plate 위에 도착
7. door가 열림
8. 현재 player가 door 통과
9. objective 획득
10. exit 진입
11. level complete UI 표시

### Pass Conditions

- Ghost 경로가 눈에 띄게 흔들리거나 크게 어긋나지 않음
- plate event와 door 상태가 정확히 연결됨
- objective는 current player만 획득함
- exit는 objective 보유 시에만 성공함
- runtime error 없음
- 새 loop가 시작될 때 level 상태가 정확히 초기화됨

이 acceptance test를 통과하기 전에는 enemy AI, combat, meta progression을 구현하지 않는다.
