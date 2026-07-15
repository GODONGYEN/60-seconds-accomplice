# 60초의 공범 — Technical Architecture

문서 상태: Operation: Black Minute + preserved loop regressions

엔진: Godot 4.7 / Compatibility

언어: statically typed GDScript where practical

## 1. Architecture goals

1. 정식 heist와 full-loop regression의 lifecycle을 명시적으로 분리한다.
2. mission, access, security, Guard scheduling, Recall 책임을 한 manager에 몰지 않는다.
3. blueprint에서 map과 security population을 결정적으로 재현한다.
4. Recall snapshot에 Node reference를 저장하지 않는다.
5. stable object ID를 interaction/replay/validation의 공통 식별자로 사용한다.
6. pause, capture, Recall restore, checkpoint reset, victory의 state transition을 한 번만 확정한다.
7. Web에서 10 Guards, 8 cameras, 3 lasers, 3 Echoes를 예측 가능한 비용으로 처리한다.

## 2. Explicit mode boundary

`scripts/core/game_mode.gd`의 enum이 mode의 유일한 의미 소스다.

```text
MAIN_MENU
OPERATION_BLACK_MINUTE
PROTOTYPE_LOOP
FACILITY_REGRESSION
```

scene name, root node name, 파일 경로 문자열 비교로 mode를 판정하지 않는다.

`AppController`는 다음만 담당한다.

- MainMenu → MissionBriefing → Operation scene 전환;
- developer regression mode launch;
- 현재 session scene 교체;
- session의 optional `return_to_menu_requested` 연결;
- mode-independent fullscreen/mute utility input.

Embedded legacy `GameManager` sessions delegate F11/V to the ancestor utility-input owner and update their local HUD state without applying the action twice. Standalone legacy scenes retain their original handlers.

Operation scene은 export된 `PackedScene`을 우선 사용하고 설정된 fallback path로 load할 수 있다. Command-line user arguments `--prototype`과 `--facility-regression`은 Godot의 `--` separator 뒤에서 사용한다.

## 3. Two gameplay stacks

### Formal heist stack

```text
AppController
→ OperationBlackMinuteLevel
   ├── MissionDirector + ObjectiveGraph
   ├── AccessControlManager
   ├── SecuritySystemManager
   ├── GuardZoneManager
   ├── PatrolScheduler
   ├── ChronoRecallManager
   │   ├── RecallHistory
   │   └── RewindStateRegistry
   ├── MissionPerformanceTracker
   ├── OperationBlackMinuteMap
   ├── ObjectRegistry
   ├── WorldVisibilityController
   ├── HeistHUD
   └── FacilityMapOverlay
```

### Preserved loop stack

```text
AppController
→ PrototypeLoopSession or FacilityRegressionSession
   └── GameManager
       ├── GameplayLevel
       ├── TimelineManager
       ├── ActionRecorder / LoopRecording
       ├── GhostPlayback
       └── legacy HUD / AudioFeedback
```

`TimelineManager`는 formal heist의 mission state, access, CCTV, lasers, Guard zones, Recall charge를 관리하지 않는다. `ChronoRecallManager`는 regression mode의 full-loop index/timeout을 관리하지 않는다.

## 4. Operation scene contract

`scenes/levels/operation_black_minute.tscn` root는 `OperationBlackMinuteLevel`이며 다음 child contract를 가진다.

```text
OperationBlackMinuteLevel
├── OperationMap
│   ├── Floor
│   ├── FloorDetails
│   ├── Walls
│   ├── PropsBelowActors
│   ├── PropsAboveActors
│   ├── RoomLabels
│   └── ObservationWindows
├── ActorLayer
│   ├── PlayerContainer
│   ├── EchoContainer
│   └── GuardContainer
├── DynamicObjects
├── ProgressionTriggers
├── ObjectRegistry
├── VisibilityController
├── MissionDirector
├── AccessControlManager
├── SecuritySystemManager
├── GuardZoneManager
├── PatrolScheduler
├── ChronoRecallManager
├── AudioFeedback
├── HeistHUD
└── FacilityMapOverlay
```

Map geometry와 population은 `resources/maps/operation_black_minute_blueprint.json`에서 생성한다. Gameplay scene은 source image 또는 map preview를 직접 사용하지 않는다.

## 5. Blueprint as data contract

Blueprint는 다음을 선언한다.

- 64×42 map, 32 px tile, 2048×1344 world;
- 15 rooms, connectors, dynamic portals, internal solids;
- object/card/terminal/Core/extraction positions;
- access ranks and vault credential alternatives;
- CCTV camera phases and laser spans;
- 10 Guard routes, waits, start phases, speeds;
- 7 Guard zones and adjacency;
- 15 choke capacities and safe windows;
- objective topological order and solvability declarations.

`MissionSolvabilityValidator`는 runtime 이전에 dimensions, counts, stable IDs, bounds/walkability, room connectivity, objective DAG, access circularity, authorization alternatives, route declarations, safe windows를 검사한다.

Blueprint validation과 runtime validation은 목적이 다르다.

- static validator: authoring/data contract;
- `OperationBlackMinuteLevel._validate_runtime_contracts()`: 실제로 생성된 10 Guards, 8 cameras, 3 lasers, doors, terminals, zone registrations;
- headless scene/test: Node contract와 state transition;
- browser pass: rendering/input/console.

## 6. Mission and objective flow

```text
world trigger or successful interaction
→ OperationBlackMinuteLevel translates to semantic event
→ MissionDirector.report_event(event_id)
→ ObjectiveGraph validates current state/prerequisites
→ objective state changes once
→ HUD and tactical map receive objective list
```

`ObjectiveGraph` stores stable `StringName` IDs, authored insertion order, `all_of` and `any_of` prerequisites, optional flags, and explicit state. It validates missing prerequisites and cycles before mission start.

`MissionDirector` owns mission state:

```text
BRIEFING → ACTIVE → CAPTURE_DECISION → ACTIVE
                         └────────────→ reset mission
ACTIVE → COMPLETED
```

It does not directly move Guards, open doors, draw UI, or restore arbitrary object fields.

## 7. Access flow

```text
live Player interacts with card
→ AccessCard emits stable card ID + level
→ AccessControlManager.grant_access
→ current highest access + credential source stored
→ MissionDirector completes access objective
→ AccessDoor.authorize on interaction
→ door collision/LOS/visibility blocker state changes together
```

Access ranks are `PUBLIC`, `LEVEL_1`, `LEVEL_2`, `VAULT`. Vault authorization is granted from either server override or biometric source after the required physical route. Echoes cannot collect cards or grant credentials. Access state is rewindable; Recall charge spending is not.

## 8. Security data flow

```text
CCTV threshold / Guard alert / laser contact
→ SecuritySystemManager.raise_zone_alert
→ GuardZoneManager resolves zone + adjacent recipients deterministically
→ GuardController.receive_zone_alert(last_seen_position, source, zone)
→ investigate / suspicion / chase / search / return
```

`SecuritySystemManager` owns:

- CCTV network online/offline;
- laser network online/offline;
- `CLEAR`, `SUSPICIOUS`, `ALERTED`, `LOCKDOWN`;
- last known per-zone alert payload;
- alert decay.

Cameras and lasers own their local detection/trigger behavior. Terminals request network changes through the manager. A closed AccessDoor blocks movement, Guard LOS, camera LOS, Player visibility, and light; an open door disables those blockers consistently.

## 9. Guard responsibilities

`GuardController` remains the explicit state machine and target lifecycle owner. It delegates:

- candidate/FOV/LOS/proximity calculation to `GuardPerception`;
- collision-aware movement to `GuardNavigation`;
- directional animation/cone/icons to `GuardVisual`;
- mission chase bounds/zone alerts to `GuardZoneManager`;
- conflicting tile/choke movement decisions to `PatrolScheduler`.

Guard target selection is stable: visible live Player first, then eligible Echoes by deterministic ID/sequence ordering. Node tree order is not a tie-breaker.

### Guard zones

Each Guard has one declared home zone and an explicit allowed response set. Zone manager validates capacity and assignments, clamps chase targets, routes alerts to local/adjacent Guards, and gives return anchors.

### Patrol scheduling

Routes are authored loops with waypoint waits and a start phase. Runtime Guard reset and virtual validation both call the same deterministic phase evaluator, so phase means elapsed route time in both paths. Scheduler reservations are sorted by stable Guard ID. It rejects occupied tiles and choke entries above capacity. The 180-second virtual simulation runs twice and compares trace digests while measuring overlap, choke, zone, deadlock, and separately named capacity-open opportunities. Authored safe-window declarations are never relabeled as measured results.

## 10. Chrono Recall

### History

`RecallHistory` records the live actor at 20 Hz and timestamped stable-ID interaction events. It retains only the active bounded branch needed for a 10-second Recall.

### World snapshots

`ChronoRecallManager` captures:

- actor transform/velocity/extended typed state;
- a `RewindStateRegistry` snapshot of registered contracts;
- monotonic world timestamp.

Each rewindable exposes:

```gdscript
func get_recall_state_id() -> StringName
func capture_recall_state() -> Dictionary
func restore_recall_state(snapshot: Dictionary) -> bool
```

Legacy-equivalent `capture_rewind_state`/`restore_rewind_state` names are accepted by the registry. Duplicate/empty IDs, missing methods, invalid snapshots, and Object references fail validation instead of being ignored.

### Restore transaction

```text
validate availability and target snapshot
→ build abandoned LoopRecording segment
→ enter RESTORING and spend one charge
→ restore registry snapshot in deterministic phase/ID order
→ restore Player state
→ spawn Echo from abandoned segment
→ clear old bounded branch
→ begin new branch at monotonic world time
→ resume simulation
```

The world clock does not move backward. Snapshot state moves to the selected historical point while a new branch starts at the current monotonic timestamp. A later Recall cannot cross an earlier branch boundary. The oldest Echo is removed before exceeding the cap of three.

## 11. State categories

### Rewindable within a Recall

- Player transform/facing/velocity and heist actor state;
- cards and access inventory;
- access doors and terminals;
- CCTV/laser/alert state;
- objective graph and Core possession;
- Guards and cameras;
- extraction activation and operation tutorial state.

### Mission-persistent across a Recall

- consumed Recall charge;
- monotonic world time;
- Echo sequence/cap policy;
- current branch boundary.

### Reset by mission-start checkpoint

- all rewindable state;
- all Echoes/history;
- Recall charges;
- Guard scheduler runtime reservations;
- discovered maintenance route;
- objective and alert state.

There is no post-Core checkpoint in the current implementation.

## 12. Stable interaction contract

Interactive runtime objects register a human-readable stable ID in `ObjectRegistry`. Recording stores the stable ID, event type, order, and minimal payload, never a NodePath or Node reference.

Player and Echo identity uses groups/contracts (`player_actor`, `ghost_actor`, `detectable_actor`), not node-name string comparisons.

Object policy:

- AccessCard: live Player only;
- AccessDoor: live authorization; eligible Echo replay may reproduce an already-authorized interaction;
- HackTerminal: live Player; explicitly allowed Echo replay;
- ChronosCore and extraction: live Player only;
- SecurityLaser: captures live Player, ignores Echo;
- CCTV/Guards: detect both.

## 13. Pause, capture, and victory

Operation input/simulation gates are centralized in `OperationBlackMinuteLevel` without changing manager internals directly.

- tactical map: pauses tree and closes before resume;
- pause menu: process-always UI, gameplay stopped;
- capture: re-entry flag, simulation disabled, mission enters `CAPTURE_DECISION`;
- Recall choice: temporarily enables Recall transaction, restores, resumes `ACTIVE`;
- checkpoint choice: full `reset_operation()` from mission start;
- victory: simulation disabled, tree unpaused for victory UI, further capture ignored.

## 14. Performance and feedback

```text
Guard/CCTV stable actor detection + accepted capture
→ MissionPerformanceTracker persistent attempt ledger
→ extraction samples Recall charges, security state, route, and monotonic world time
→ positive-only directive scoring
→ immutable deep-copied result
→ HeistHUD debrief + AudioFeedback
```

The tracker is a focused `RefCounted` value object owned by `OperationBlackMinuteLevel`; it does not draw UI or mutate mission systems. It is deliberately absent from `recall_rewindable`, so abandoned-branch detections and captures cannot be erased by Recall. A mission-start checkpoint reset creates a fresh attempt ledger. Scripted Core `LOCKDOWN` is not classified as detection.

HUD cues and the debrief use Canvas UI, Tween animation, and low-alpha color washes that are safe for the Web Compatibility renderer. Procedural audio is additive; text and shape remain authoritative when audio is muted or browser playback is unavailable.

## 15. Preserved hybrid replay

Regression modes retain the original model:

- transform snapshots sampled at 20 Hz;
- timestamp-ordered discrete events;
- immutable/deep-copied `LoopRecording`;
- position interpolation instead of Ghost physics resimulation;
- stable-ID event dispatch exactly once;
- pause-safe clock and deterministic reset.

Loop-end reason arbitration and Ghost count remain the responsibility of `TimelineManager` only inside those modes.

## 16. Performance rules

- Do not call `get_nodes_in_group()` every frame; cache candidates/registries at setup or controlled rebuild points.
- Camera/Guard physics rays operate on cached candidates and bounded update cadence.
- Vision geometry is generated from configuration, not rebuilt unnecessarily.
- Navigation targets and reservations update only when movement requires it.
- Rewind history is bounded; full mission history is not retained.
- Temporary snapshot data contains value types only.
- Reset must not accumulate signal connections, orphan Echoes, or stale reservations.

### Environment presentation boundary

Operation environment art is deliberately split from gameplay geometry:

- the original `Walls` TileMap and `facility_tileset.tres` own collision and occlusion;
- `WallArt`, `Floor`, `FloorDetails`, `PropsAbove`, `HeroDetails`, and `AnimatedDetails` use `facility_environment_art.tres`, which has zero physics and occlusion layers;
- `WallArt` renders only the walkable-facing boundary and a two-cell deep-wall ring; the full invisible `Walls` field remains authoritative;
- `facility_environment_catalog.gd` is generated beside the TileSet and is the runtime source for room families, seeded variants, semantic-solid mappings, hero/state cells, and atlas coordinates;
- semantic furniture is placed only on the blueprint's existing `internal_solid_rects`;
- room variation uses stable room seeds and integer cell hashes, never runtime randomness;
- `OperationEnvironmentPresenter` owns the fixed 6 Hz visual clock, 15 room heroes, room-clipped painted pools, and state-tile selection; it owns no collision, LOS, visibility, or mission state;
- access doors build exact-span interaction, blocker, and occluder shapes per instance without root scaling or shared-shape mutation;
- dynamic doors, terminals, cameras, lasers, cards, the Core, extraction, actors, and Echoes remain independent gameplay scenes.

This lets an art rebuild change pixels without changing pathing, LOS, registry IDs, reset order, or Recall snapshots. The environment pipeline validates the boundary before CI accepts generated derivatives.

## 17. Testing layers

1. parser/import and scene load;
2. objective/access/security unit behavior;
3. Recall history, immutable segment, registry restore, persistent charge, Echo cap;
4. Guard zone assignment/alert propagation;
5. 180-second deterministic patrol simulation;
6. static mission solvability validation;
7. formal mission and preserved mode integration;
8. Web export structure;
9. manual local-HTTP browser rendering/input/console review.

Run the static operation validator:

```bash
godot --headless --path . --script tools/validate_operation_black_minute.gd
```

Run the full harness:

```bash
GODOT_BIN=godot tools/run_tests.sh
```

Headless tests cannot certify PointLight/TileMap shadow pixels, readable cone alpha, responsive UI, or browser console state.

## 18. File ownership

```text
scripts/core/app_controller.gd                  menu and session switching
scripts/core/game_mode.gd                       explicit mode enum/arguments
scripts/missions/operation_black_minute_level.gd mission composition/orchestration
scripts/missions/mission_director.gd            mission lifecycle/objective events
scripts/missions/objective_graph.gd              acyclic objective state
scripts/missions/mission_solvability_validator.gd blueprint contract validation
scripts/missions/mission_performance_tracker.gd Recall-persistent attempt metrics/result
scripts/security/access_control_manager.gd      credentials/access ranks
scripts/security/security_system_manager.gd     networks/alerts
scripts/security/security_camera.gd             camera sweep/perception
scripts/security/security_laser.gd              laser live-Player trigger
scripts/enemies/guard_zone_manager.gd            zone assignment/alert propagation
scripts/enemies/patrol_scheduler.gd              deterministic reservations/simulation
scripts/recording/chrono_recall_manager.gd       Recall transaction/Echo lifecycle
scripts/recording/recall_history.gd              bounded branch recording
scripts/recording/rewind_state_registry.gd       value snapshot contracts
scripts/presentation/operation_black_minute_map.gd blueprint-driven map layers
scripts/presentation/operation_environment_presenter.gd fixed-tick room light/motion/state presentation
tools/environment_art_pipeline.py              deterministic visual-only HELIX atlas
tools/build_environment_contact_sheet.py       deterministic 15-room visual evidence sheet
resources/environment/facility_environment_catalog.gd generated runtime art mapping
scripts/ui/mission_briefing.gd                   pre-mission briefing
scripts/ui/facility_map_overlay.gd                tactical map
scripts/ui/heist_hud.gd                           operation HUD/decisions
scripts/ui/audio_feedback.gd                      optional procedural event tones
scripts/core/timeline_manager.gd                 preserved full-loop lifecycle only
```

## 19. Known architectural limits

- Mission composition is specific to the one authored operation; it is not a generic campaign framework.
- Guard movement is route/zone/reservation based, not NavigationServer-driven general pathfinding.
- There is no persistent save serialization or schema migration.
- The tactical map is authored information, not fog-of-war pathfinding.
- Dynamic visual cones are guides; physics LOS remains authoritative.
- Sound hooks are secondary to visual feedback and no external audio dependency is required.
